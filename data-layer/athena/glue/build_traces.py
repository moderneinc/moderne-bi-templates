"""Nightly AWS Glue job that builds the typed `traces` table from raw trace CSV.

Each run:

1. Reads only the raw CSV objects it has not seen before (Glue job bookmarks), each by
   its own header, so every command type's column set lands by name and a new trace
   field needs no DDL change.
2. Appends those rows, all as strings, to the Iceberg table `traces_raw`. An object
   that is delivered again replaces its earlier rows, and a late object lands in the
   day its key names, so there is no separate backfill step.
3. Gives each column one type (boolean, bigint, double, timestamp, or string) decided
   from every value it has ever held. Running per-column counts in `traces_typing` mean
   only the new rows are scanned to update those decisions.
4. Appends the new rows, typed, to the Iceberg table `traces`. It rebuilds `traces` from
   `traces_raw` only when it has to: on the first run, when a column's type changes,
   or when an object was delivered again. Values that don't match their column's type
   become NULL.
5. Expires old Iceberg snapshots and compacts the small files nightly appends leave.

This is a minimal example for a single tenant's export, with no metrics or alarms.
"""

import datetime
import logging
import re
import sys

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark import SparkConf
from pyspark.context import SparkContext
from pyspark.sql import functions as F

LOG = logging.getLogger("build_traces")
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s", force=True)

RAW_TABLE = "traces_raw"
TABLE = "traces"
TYPING_TABLE = "traces_typing"

# The export key layout: tenant=.../source=.../type=.../year=YYYY/month=MM/day=DD/<id>.csv
PARTITION_COLUMNS = ("tenant", "source", "type", "year", "month", "day")
PARTITION_SPEC = PARTITION_COLUMNS[:5]  # month-level partitions; `day` stays a column
KEY_PATTERN = (
    r"^tenant=([^/=]+)/source=([^/=]+)/type=([^/=]+)"
    r"/year=(\d{4})/month=(\d{2})/day=(\d{2})/[^/]+\.csv$"
)
SOURCE_KEY = "_source_key"  # the object each raw row came from

# A column takes the first type that at least 99.9% of its non-null values match.
TYPE_PATTERNS = {
    "boolean": r"^(true|false)$",
    "bigint": r"^-?\d{1,18}$",
    "double": r"^(-?\d{1,18}(\.\d+)?([eE][+-]?\d+)?|NaN|-?Infinity)$",
    "timestamp": r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$",
}
THRESHOLD = 0.999
ISO_TO_SPARK = r"^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})(\.\d{1,6})?\d*Z$"


def spark_conf(warehouse):
    """Register the Glue Data Catalog as an Iceberg catalog named glue_catalog."""
    return (
        SparkConf()
        .set("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
        .set("spark.sql.catalog.glue_catalog", "org.apache.iceberg.spark.SparkCatalog")
        .set("spark.sql.catalog.glue_catalog.warehouse", warehouse)
        .set("spark.sql.catalog.glue_catalog.catalog-impl", "org.apache.iceberg.aws.glue.GlueCatalog")
        .set("spark.sql.catalog.glue_catalog.io-impl", "org.apache.iceberg.aws.s3.S3FileIO")
        .set("spark.sql.session.timeZone", "UTC")
    )


def read_new_csv(glue, raw_location):
    """Read the CSV objects the job bookmark has not seen yet, each by its own header."""
    return glue.create_dynamic_frame.from_options(
        connection_type="s3",
        connection_options={
            "paths": [raw_location],
            "recurse": True,
            "groupFiles": "inPartition",
            "attachFilename": SOURCE_KEY,
        },
        format="csv",
        format_options={"withHeader": True, "multiLine": True},
        transformation_ctx="raw_csv",  # the bookmark is keyed on this
    ).toDF()


def normalize_columns(df):
    """Lowercase headers to the names Athena exposes (runStartTime -> runstarttime,
    tag.team -> tag_team). Headers that collapse to the same name are coalesced."""
    positional = df.toDF(*[f"c{i}" for i in range(len(df.columns))])
    merged = {}
    for i, header in enumerate(df.columns):
        name = re.sub(r"[^a-z0-9_]", "_", header.strip().lower())
        merged.setdefault(name, []).append(F.col(f"c{i}"))
    return positional.select(*[
        (F.coalesce(*[F.when(c != "", c) for c in cols]) if len(cols) > 1 else cols[0]).alias(name)
        for name, cols in merged.items()
    ])


def with_partition_columns(df, raw_location):
    """Derive the partition columns from each row's object key. Any other CSV under
    raw_location would add its columns to the table, so it fails the run instead."""
    relative = F.substring(F.col(SOURCE_KEY), len(raw_location) + 1, 4096)
    outside = F.regexp_extract(relative, KEY_PATTERN, 0) == ""
    stray = [r[0] for r in df.filter(outside).select(SOURCE_KEY).distinct().limit(5).collect()]
    if stray:
        raise RuntimeError(f"objects outside the trace layout under {raw_location}: {stray}")
    for i, name in enumerate(PARTITION_COLUMNS, start=1):
        df = df.withColumn(name, F.regexp_extract(relative, KEY_PATTERN, i))
    return df


def nullify_empty(df):
    return df.select(*[F.when(F.col(c) == "", None).otherwise(F.col(c)).alias(c) for c in df.columns])


def append_rows(df, table):
    # mergeSchema adds new trace fields as columns; check-ordering lets a new field
    # arrive mid-header instead of only at the end of the table's column list.
    df.writeTo(table).option("mergeSchema", "true").option("check-ordering", "false").append()


def create_table(df, table, location, partitioned=True):
    writer = df.writeTo(table).using("iceberg")
    if partitioned:
        writer = writer.partitionedBy(*[F.col(c) for c in PARTITION_SPEC])
    (writer.tableProperty("format-version", "2")
        .tableProperty("location", location)
        .tableProperty("write.spark.accept-any-schema", "true")  # new trace fields add columns
        .createOrReplace())


def upsert_raw(spark, increment, raw, location):
    """Append the new rows to traces_raw, first deleting rows from any object read again.
    Returns how many earlier rows were replaced."""
    ordered = increment.sortWithinPartitions(*PARTITION_COLUMNS)
    if not spark.catalog.tableExists(raw):
        create_table(ordered, raw, location)
        return 0
    increment.select(SOURCE_KEY).distinct().createOrReplaceTempView("incoming_keys")
    matching = f"{SOURCE_KEY} IN (SELECT {SOURCE_KEY} FROM incoming_keys)"
    replaced = spark.sql(f"SELECT count(*) AS n FROM {raw} WHERE {matching}").first()["n"]
    if replaced:
        LOG.warning("%d row(s) from objects delivered again will be replaced", replaced)
        spark.sql(f"DELETE FROM {raw} WHERE {matching}")
    append_rows(ordered, raw)
    return replaced


def always_string(column):
    return column in PARTITION_COLUMNS or column.endswith("id") or column.startswith("tag_")


def data_columns(df):
    return [c for c in df.columns if c not in PARTITION_COLUMNS and c != SOURCE_KEY]


def count_matches(df):
    """One aggregate pass: per column, its non-null count and how many values match each type."""
    columns = data_columns(df)
    aggregates = []
    for c in columns:
        aggregates.append(F.count(F.col(c)).alias(f"{c}__non_null"))
        for t, pattern in TYPE_PATTERNS.items():
            aggregates.append(F.count(F.when(F.col(c).rlike(pattern), True)).alias(f"{c}__{t}"))
    row = df.agg(*aggregates).first()
    return {c: {k: row[f"{c}__{k}"] for k in ("non_null", *TYPE_PATTERNS)} for c in columns}


def add_counts(previous, new):
    totals = {c: dict(counts) for c, counts in previous.items()}
    for c, counts in new.items():
        base = totals.setdefault(c, dict.fromkeys(counts, 0))
        for k, n in counts.items():
            base[k] += n
    return totals


def decide(column, counts):
    n = counts["non_null"]
    if n == 0 or always_string(column):
        return "string"
    return next((t for t in TYPE_PATTERNS if counts[t] >= THRESHOLD * n), "string")


def load_counts(spark, typing):
    if not spark.catalog.tableExists(typing):
        return None
    return {r["column_name"]: {k: r[k] for k in ("non_null", *TYPE_PATTERNS)} for r in spark.table(typing).collect()}


def save_counts(spark, typing, location, totals, decided):
    rows = [(c, *[totals[c][k] for k in ("non_null", *TYPE_PATTERNS)], decided[c]) for c in sorted(totals)]
    create_table(spark.createDataFrame(rows, ["column_name", "non_null", *TYPE_PATTERNS, "decided"]),
                 typing, location, partitioned=False)


SPARK_TYPES = {"LongType": "bigint", "DoubleType": "double", "BooleanType": "boolean",
               "TimestampNTZType": "timestamp", "StringType": "string"}


def current_types(spark, table):
    if not spark.catalog.tableExists(table):
        return None
    return {f.name: SPARK_TYPES.get(type(f.dataType).__name__) for f in spark.table(table).schema.fields}


def typed(column, type_name):
    col = F.col(column)
    ok = col.rlike(TYPE_PATTERNS[type_name])
    if type_name == "boolean":
        return F.when(ok, col == "true")
    if type_name == "bigint":
        return F.when(ok, col.cast("long"))
    if type_name == "double":
        return F.when(ok, col.cast("double"))
    return F.when(ok, F.to_timestamp_ntz(F.regexp_replace(col, ISO_TO_SPARK, "$1 $2$3")))


def apply_types(df, decided):
    df = df.drop(SOURCE_KEY)
    return df.select(*[
        (F.col(c) if decided.get(c, "string") == "string" else typed(c, decided[c])).alias(c)
        for c in df.columns
    ])


def maintain(spark, tables):
    """Expire snapshots older than a day, and compact the small files appends leave behind."""
    cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1)
    for t in tables:
        name = t.removeprefix("glue_catalog.")
        spark.sql(f"CALL glue_catalog.system.expire_snapshots(table => '{name}', "
                  f"older_than => TIMESTAMP '{cutoff:%Y-%m-%d %H:%M:%S}', retain_last => 5)")
        spark.sql(f"CALL glue_catalog.system.rewrite_data_files(table => '{name}')")


def main():
    args = getResolvedOptions(sys.argv, ["JOB_NAME", "raw_location", "warehouse", "database"])
    raw_location, warehouse = args["raw_location"], args["warehouse"]
    raw, table, typing = (f"glue_catalog.{args['database']}.{t}" for t in (RAW_TABLE, TABLE, TYPING_TABLE))

    def location(name):
        return f"{warehouse}{name}/"

    glue = GlueContext(SparkContext.getOrCreate(spark_conf(warehouse)))
    spark = glue.spark_session
    job = Job(glue)
    job.init(args["JOB_NAME"], args)
    spark.sql(f"CREATE DATABASE IF NOT EXISTS glue_catalog.{args['database']}")

    incoming = read_new_csv(glue, raw_location)
    if not incoming.columns:
        LOG.info("no new objects under %s", raw_location)
        job.commit()
        return

    increment = nullify_empty(with_partition_columns(normalize_columns(incoming), raw_location)).cache()
    LOG.info("%d new row(s)", increment.count())
    first_run = not spark.catalog.tableExists(raw)
    replaced = upsert_raw(spark, increment, raw, location(RAW_TABLE))

    # Running counts cover every raw row. Replaced rows can't be subtracted from them,
    # so after a replace (or with no counts yet) they are recounted from traces_raw.
    previous = None if first_run or replaced else load_counts(spark, typing)
    if previous is None:
        totals = count_matches(spark.table(raw))
    else:
        totals = add_counts(previous, count_matches(increment))
    decided = {c: decide(c, counts) for c, counts in totals.items()}
    save_counts(spark, typing, location(TYPING_TABLE), totals, decided)

    current = current_types(spark, table)
    changed = sorted(c for c in decided if current and c in current and current[c] != decided[c])
    for c in changed:
        LOG.info("column %s changes type from %s to %s", c, current[c], decided[c])

    if current is None or replaced or changed:
        LOG.info("rebuilding %s from %s", table, raw)
        history = apply_types(spark.table(raw), decided)
        create_table(history.repartition(*PARTITION_SPEC).sortWithinPartitions(*PARTITION_COLUMNS),
                     table, location(TABLE))
    else:
        LOG.info("appending to %s", table)
        append_rows(apply_types(increment, decided).sortWithinPartitions(*PARTITION_COLUMNS), table)
    increment.unpersist()

    # Advance the bookmark only once every table is written. If the job fails before
    # this, the next run re-reads the same objects and the upsert replaces their rows.
    job.commit()
    maintain(spark, (raw, table, typing))


if __name__ == "__main__":
    main()
