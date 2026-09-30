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
from typing import NamedTuple

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark import SparkConf
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql import types as T
from pyspark.storagelevel import StorageLevel

LOG = logging.getLogger("build_traces")
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s", force=True)

ARGUMENTS = ["JOB_NAME", "raw_location", "warehouse", "database"]
TARGET_TABLE = "traces"
RAW_TABLE = "traces_raw"
TYPING_TABLE = "traces_typing"
GROUP_SIZE_BYTES = str(128 * 1024 * 1024)

# ---- rules: key layout and typing rules ----

PARTITION_COLUMNS = ("tenant", "source", "type", "year", "month", "day")
PARTITION_SPEC = PARTITION_COLUMNS[:5]  # month-level partitions; `day` stays a column
SOURCE_KEY_COLUMN = "_source_key"  # the object each raw row came from

KEY_PATTERN = (
    r"^tenant=([^/=]+)/source=([^/=]+)/type=([^/=]+)"
    r"/year=(\d{4})/month=(\d{2})/day=(\d{2})/[^/]+\.csv$"
)

BOOLEAN_PATTERN = r"^(true|false)$"
BIGINT_PATTERN = r"^-?\d{1,18}$"
DOUBLE_PATTERN = r"^(-?\d{1,18}(\.\d+)?([eE][+-]?\d+)?|NaN|-?Infinity)$"
TIMESTAMP_PATTERN = r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$"

# A column takes the first rule that at least 99.9% of its non-null values match.
RULE_PATTERNS = {
    "boolean": BOOLEAN_PATTERN,
    "bigint": BIGINT_PATTERN,
    "double": DOUBLE_PATTERN,
    "timestamp": TIMESTAMP_PATTERN,
}
RULES = tuple(RULE_PATTERNS)

THRESHOLD_NUMERATOR = 999
THRESHOLD_DENOMINATOR = 1000


class ColumnStats(NamedTuple):
    non_null: int
    matches: dict


def is_always_string(column):
    return column in PARTITION_COLUMNS or column.endswith("id") or column.startswith("tag_")


def decide_type(column, non_null, matches):
    if is_always_string(column) or non_null == 0:
        return "string"
    for rule in RULES:
        if matches[rule] * THRESHOLD_DENOMINATOR >= THRESHOLD_NUMERATOR * non_null:
            return rule
    return "string"


def merge_totals(previous, increment):
    merged = dict(previous)
    for column, stats in increment.items():
        base = merged.get(column, ColumnStats(0, dict.fromkeys(RULES, 0)))
        merged[column] = ColumnStats(
            base.non_null + stats.non_null,
            {rule: base.matches[rule] + stats.matches[rule] for rule in RULES},
        )
    return merged


def changed_decisions(current, decided):
    return {c: (current[c], decided[c]) for c in decided if c in current and current[c] != decided[c]}


def rebuild_needed(changed, raw_exists, silver_exists, replaced):
    return bool(changed) or not raw_exists or not silver_exists or replaced > 0


# ---- transforms: raw CSV rows to typed rows ----

ISO_TO_CANONICAL = r"^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})(\.\d{1,6})?\d*Z$"


def normalize_columns(df):
    """Lowercase headers to the names Athena exposes (runStartTime -> runstarttime,
    tag.team -> tag_team). Headers that collapse to the same name are coalesced."""
    positional = df.toDF(*[f"c{i}" for i in range(len(df.columns))])
    merged = {}
    for index, original in enumerate(df.columns):
        name = re.sub(r"[^a-z0-9_]", "_", original.strip().lower())
        merged.setdefault(name, []).append(F.col(f"c{index}"))
    return positional.select(*[
        (F.coalesce(*[F.when(c != "", c) for c in cols]) if len(cols) > 1 else cols[0]).alias(name)
        for name, cols in merged.items()
    ])


def _relative_key(raw_location):
    return F.substring(F.col(SOURCE_KEY_COLUMN), len(raw_location) + 1, 4096)


def with_partition_columns(df, raw_location):
    clash = [c for c in PARTITION_COLUMNS if c in df.columns]
    if clash:
        raise ValueError(f"trace columns collide with partition columns: {clash}")
    relative = _relative_key(raw_location)
    out = df
    for index, name in enumerate(PARTITION_COLUMNS, start=1):
        out = out.withColumn(name, F.regexp_extract(relative, KEY_PATTERN, index))
    return out


def _outside_layout(raw_location):
    key = F.col(SOURCE_KEY_COLUMN)
    return key.isNull() | (F.regexp_extract(_relative_key(raw_location), KEY_PATTERN, 0) == "")


def invalid_keys(df, raw_location, limit=5):
    rows = (
        df.filter(_outside_layout(raw_location))
        .select(SOURCE_KEY_COLUMN)
        .distinct()
        .limit(limit)
        .collect()
    )
    return [r[0] for r in rows]


def nullify_empty(df):
    return df.select(*[F.when(F.col(c) == "", None).otherwise(F.col(c)).alias(c) for c in df.columns])


def profile(df, columns):
    """One aggregate pass: per column, its non-null count and how many values match each rule."""
    aggregates = []
    for column in columns:
        col = F.col(column)
        aggregates.append(F.count(col).alias(f"{column}__nonnull"))
        for rule, pattern in RULE_PATTERNS.items():
            aggregates.append(F.count(F.when(col.rlike(pattern), True)).alias(f"{column}__{rule}"))
    row = df.agg(*aggregates).first()
    return {
        column: ColumnStats(row[f"{column}__nonnull"], {rule: row[f"{column}__{rule}"] for rule in RULES})
        for column in columns
    }


def _typed(col, rule):
    if rule == "boolean":
        return F.when(col.rlike(BOOLEAN_PATTERN), col == "true")
    if rule == "bigint":
        return F.when(col.rlike(BIGINT_PATTERN), col.cast("long"))
    if rule == "double":
        return F.when(col.rlike(DOUBLE_PATTERN), col.cast("double"))
    if rule == "timestamp":
        canonical = F.regexp_replace(col, ISO_TO_CANONICAL, "$1 $2$3")
        return F.when(col.rlike(TIMESTAMP_PATTERN), F.to_timestamp_ntz(canonical))


def apply_types(df, decided):
    return df.select(*[
        (F.col(c) if decided.get(c, "string") == "string" else _typed(F.col(c), decided[c])).alias(c)
        for c in df.columns
    ])


SPARK_TYPE_RULES = {
    T.LongType: "bigint",
    T.DoubleType: "double",
    T.BooleanType: "boolean",
    T.TimestampNTZType: "timestamp",
    T.StringType: "string",
}


def current_types(schema):
    return {field.name: SPARK_TYPE_RULES.get(type(field.dataType)) for field in schema.fields}


# ---- tables: Iceberg reads, writes, and maintenance ----

TYPING_COLUMNS = ("column_name", "non_null") + tuple(f"matches_{rule}" for rule in RULES) + ("decided",)
KEYS_VIEW = "incoming_keys"


def _clustered(df):
    return df.repartition(*PARTITION_SPEC).sortWithinPartitions(*PARTITION_COLUMNS)


def replace_table(df, table, location):
    (
        _clustered(df)
        .writeTo(table)
        .using("iceberg")
        .partitionedBy(*[F.col(c) for c in PARTITION_SPEC])
        .tableProperty("format-version", "2")
        .tableProperty("location", location)
        .tableProperty("write.distribution-mode", "none")
        .tableProperty("write.spark.accept-any-schema", "true")  # new trace fields add columns
        .createOrReplace()
    )


def append_rows(df, table):
    # mergeSchema adds new trace fields as columns; check-ordering lets a new field
    # arrive mid-header instead of only at the end of the table's column list.
    _clustered(df).writeTo(table).option("mergeSchema", "true").option("check-ordering", "false").append()


def rows_with_keys(spark, table, keys):
    keys.createOrReplaceTempView(KEYS_VIEW)
    return spark.sql(
        f"SELECT count(*) AS n FROM {table} "
        f"WHERE {SOURCE_KEY_COLUMN} IN (SELECT {SOURCE_KEY_COLUMN} FROM {KEYS_VIEW})"
    ).first()["n"]


def delete_keys(spark, table, keys):
    keys.createOrReplaceTempView(KEYS_VIEW)
    spark.sql(
        f"DELETE FROM {table} WHERE {SOURCE_KEY_COLUMN} IN (SELECT {SOURCE_KEY_COLUMN} FROM {KEYS_VIEW})"
    )


def expire_snapshots(spark, table, older_than, retain_last=5):
    spark.sql(
        f"CALL glue_catalog.system.expire_snapshots(table => '{_identifier(table)}', "
        f"older_than => TIMESTAMP '{older_than:%Y-%m-%d %H:%M:%S}', retain_last => {retain_last})"
    )


def compact(spark, table):
    spark.sql(f"CALL glue_catalog.system.rewrite_data_files(table => '{_identifier(table)}')")


def _identifier(table):
    return table.removeprefix("glue_catalog.")


def save_totals(spark, table, location, totals, decided):
    rows = [
        (column, stats.non_null, *[stats.matches[rule] for rule in RULES], decided[column])
        for column, stats in sorted(totals.items())
    ]
    df = spark.createDataFrame(rows, list(TYPING_COLUMNS))
    (
        df.writeTo(table)
        .using("iceberg")
        .tableProperty("format-version", "2")
        .tableProperty("location", location)
        .createOrReplace()
    )


def load_totals(spark, table):
    if not spark.catalog.tableExists(table):
        return {}
    return {
        r["column_name"]: ColumnStats(r["non_null"], {rule: r[f"matches_{rule}"] for rule in RULES})
        for r in spark.table(table).collect()
    }


# ---- the job ----

def iceberg_conf(warehouse):
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


def read_csv(glue, raw_location):
    """Read the CSV objects the job bookmark has not seen yet, each by its own header."""
    dyf = glue.create_dynamic_frame.from_options(
        connection_type="s3",
        connection_options={
            "paths": [raw_location],
            "recurse": True,
            "groupFiles": "inPartition",
            "groupSize": GROUP_SIZE_BYTES,
            "attachFilename": SOURCE_KEY_COLUMN,
        },
        format="csv",
        format_options={"withHeader": True, "multiLine": True},
        transformation_ctx=f"raw_csv:{raw_location}",  # the bookmark is keyed on this
    )
    return dyf.toDF()


def data_columns(df):
    return [c for c in df.columns if c not in PARTITION_COLUMNS and c != SOURCE_KEY_COLUMN]


def main():
    args = getResolvedOptions(sys.argv, ARGUMENTS)
    raw_location = args["raw_location"]
    warehouse = args["warehouse"]

    def location(name):
        return f"{warehouse}{name}/"

    silver = f"glue_catalog.{args['database']}.{TARGET_TABLE}"
    raw = f"glue_catalog.{args['database']}.{RAW_TABLE}"
    typing = f"glue_catalog.{args['database']}.{TYPING_TABLE}"

    sc = SparkContext.getOrCreate(iceberg_conf(warehouse))
    glue = GlueContext(sc)
    spark = glue.spark_session
    job = Job(glue)
    job.init(args["JOB_NAME"], args)
    spark.sql(f"CREATE DATABASE IF NOT EXISTS glue_catalog.{args['database']}")

    incoming = read_csv(glue, raw_location)

    raw_exists = spark.catalog.tableExists(raw)
    silver_exists = spark.catalog.tableExists(silver)
    ingested = 0
    if incoming.columns:
        increment = nullify_empty(with_partition_columns(normalize_columns(incoming), raw_location))
        increment = increment.persist(StorageLevel.MEMORY_AND_DISK)
        bad = invalid_keys(increment, raw_location)
        if bad:
            # Any other CSV under raw_location would add its columns to the table.
            raise RuntimeError(f"object(s) outside the trace layout under {raw_location}: {bad} "
                               "(None means no file name was attached)")
        ingested = increment.count()
    if not ingested:
        if not raw_exists:
            raise RuntimeError(f"no trace rows read under {raw_location}")
        LOG.info("no new rows under %s", raw_location)
        job.commit()
        return

    columns = data_columns(increment)
    stats = profile(increment, columns)

    keys = increment.select(SOURCE_KEY_COLUMN).distinct()
    current = current_types(spark.table(silver).schema) if silver_exists else {}
    replaced = 0
    if raw_exists:
        replaced = rows_with_keys(spark, raw, keys)
        if replaced:
            LOG.warning("%d row(s) of already ingested objects were replaced", replaced)
            delete_keys(spark, raw, keys)
        append_rows(increment, raw)
    else:
        replace_table(increment, raw, location(RAW_TABLE))

    # Running totals cover every raw row. Replaced rows can't be subtracted from them,
    # so after a replace (or with no totals yet) they are recounted from traces_raw.
    previous = {} if not raw_exists or replaced else load_totals(spark, typing)
    if previous:
        totals = merge_totals(previous, stats)
    else:
        if raw_exists and not replaced:
            LOG.warning("%s has no totals; profiling %s from history", typing, raw)
        history = spark.table(raw)
        totals = profile(history, data_columns(history))
    decided = {c: decide_type(c, s.non_null, s.matches) for c, s in totals.items()}
    save_totals(spark, typing, location(TYPING_TABLE), totals, decided)

    changed = changed_decisions(current, decided)
    for column, (old, new) in sorted(changed.items()):
        LOG.info("column %s changes from %s to %s", column, old, new)
    rebuild = rebuild_needed(changed, raw_exists, silver_exists, replaced)

    if rebuild:
        history = apply_types(spark.table(raw).drop(SOURCE_KEY_COLUMN), decided)
        replace_table(history, silver, location(TARGET_TABLE))
    else:
        append_rows(apply_types(increment.drop(SOURCE_KEY_COLUMN), decided), silver)
    increment.unpersist()
    LOG.info("%s %s: %d rows ingested", "rebuilt" if rebuild else "appended", silver, ingested)

    # Advance the bookmark only once every table is written. If the job fails before
    # this, the next run re-reads the same objects and they replace their own rows.
    job.commit()
    cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1)
    for table in (silver, raw, typing):
        expire_snapshots(spark, table, cutoff)
    for table in (silver, raw):
        compact(spark, table)


if __name__ == "__main__":
    main()
