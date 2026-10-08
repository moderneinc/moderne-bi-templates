"""Nightly AWS Glue job that builds the typed `traces` table from raw trace CSV.

Each run:

1. Reads only the raw CSV objects it has not seen before (Glue job bookmarks), each by
   its own header, so every command type's column set lands by name and a new trace
   field needs no DDL change.
2. Also reads any object from the last three days that `traces_raw` doesn't have.
   S3 replication keeps the source's last-modified time, so a replica that lands after
   a run has started looks older than that run and the bookmark alone would skip it.
3. Appends those rows, all as strings, to the Iceberg table `traces_raw`. An object
   that is delivered again replaces its earlier rows.
4. Gives each column one type (boolean, bigint, double, timestamp, or string) decided
   from every value it has ever held. Running per-column counts in `traces_typing` mean
   only the new (and replaced) rows are scanned to update those decisions.
5. Appends the new rows, typed, to the Iceberg table `traces`, replacing the rows of
   any object delivered again. It rebuilds `traces` from `traces_raw` only on the first
   run or when a column's type changes. Values that don't match their column's type
   become NULL.
6. Expires old Iceberg snapshots and compacts the small files nightly appends leave.

This is a minimal example for a single tenant's export, with no metrics or alarms.
"""

import datetime
import hashlib
import logging
import operator
import re
import sys
from functools import reduce
from typing import NamedTuple

import boto3
from botocore.config import Config
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
RECONCILE_LOOKBACK = datetime.timedelta(days=3)
GLUE_BOOKMARK_GRACE_PERIOD = datetime.timedelta(minutes=15)
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
# Timestamps end in Z or a +-HH:MM offset, optionally followed by a zone id such as [Etc/UTC].
OPTIONAL_ZONE_ID = r"(?:\[[^\]]+\])?$"
ZONE_SUFFIX = r"(?:Z|[+-]\d{2}:\d{2})" + OPTIONAL_ZONE_ID
TIMESTAMP_PATTERN = r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?" + ZONE_SUFFIX

# A column takes the first rule that at least 99.9% of its non-null values match.
RULE_PATTERNS = {
    "boolean": BOOLEAN_PATTERN,
    "bigint": BIGINT_PATTERN,
    "double": DOUBLE_PATTERN,
    "timestamp": TIMESTAMP_PATTERN,
}
RULES = tuple(RULE_PATTERNS)
# Saved with the running totals, so changing a rule re-profiles history on the next run.
RULE_FINGERPRINT = hashlib.sha256("\n".join(f"{rule}={pattern}" for rule, pattern in RULE_PATTERNS.items()).encode()).hexdigest()[:16]

THRESHOLD_NUMERATOR = 999
THRESHOLD_DENOMINATOR = 1000


class ColumnStats(NamedTuple):
    non_null: int
    matches: dict


def is_always_string(column):
    return column in PARTITION_COLUMNS or column.endswith("id") or column.startswith("tag_")


def decide_type(column, non_null, matches):
    if is_always_string(column) or non_null <= 0:
        return "string"
    for rule in RULES:
        if matches[rule] * THRESHOLD_DENOMINATOR >= THRESHOLD_NUMERATOR * non_null:
            return rule
    return "string"


def merge_totals(previous, increment):
    merged = dict(previous)
    for column, stats in increment.items():
        merged[column] = _combined(merged.get(column, ColumnStats(0, dict.fromkeys(RULES, 0))), stats, operator.add)
    return merged


def subtract_totals(previous, removed):
    return {
        column: _combined(stats, removed[column], operator.sub) if column in removed else stats
        for column, stats in previous.items()
    }


def _combined(base, stats, op):
    return ColumnStats(
        op(base.non_null, stats.non_null),
        {rule: op(base.matches[rule], stats.matches[rule]) for rule in RULES},
    )


def changed_decisions(current, decided):
    return {c: (current[c], decided[c]) for c in decided if c in current and current[c] != decided[c]}


def rebuild_needed(changed, raw_rows, current):
    return bool(changed) or not raw_rows or SOURCE_KEY_COLUMN not in current


# ---- transforms: raw CSV rows to typed rows ----

ISO_TO_WALL_CLOCK = r"^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})(\.\d{1,6})?\d*" + ZONE_SUFFIX
UTC_OFFSET = r"([+-])(\d{2}):(\d{2})" + OPTIONAL_ZONE_ID


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


def _bucket_and_prefix(raw_location):
    match = re.match(r"^s3://([^/]+)/(.*)$", raw_location)
    if match is None or not raw_location.endswith("/"):
        raise ValueError(f"raw_location must look like s3://bucket/prefix/ with a trailing slash: {raw_location!r}")
    return match.group(1), match.group(2)


def list_csv_keys(s3, raw_location, modified_after, modified_before):
    bucket, prefix = _bucket_and_prefix(raw_location)
    keys = set()
    for page in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            if obj["Key"].endswith(".csv") and modified_after <= obj["LastModified"] < modified_before:
                keys.add(f"s3://{bucket}/{obj['Key']}")
    return keys


def unknown_keys(listed, known, delivered, raw_location):
    stored = known | delivered
    if stored and not any(key.startswith(raw_location) for key in stored):
        raise RuntimeError(f"stored source keys do not start with {raw_location!r}, e.g. {min(stored)!r}; "
                           "the listing and the reader disagree on the key form")
    return sorted(listed - stored)


def union_by_name(frames):
    return reduce(lambda a, b: a.unionByName(b, allowMissingColumns=True), frames)


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


def _utc(col):
    """Parse the wall-clock part and subtract the offset, so the stored value is UTC."""
    wall = F.to_timestamp_ntz(F.regexp_replace(col, ISO_TO_WALL_CLOCK, "$1 $2$3"))
    sign = F.when(F.regexp_extract(col, UTC_OFFSET, 1) == "-", -1).otherwise(1)
    hours = F.coalesce(F.regexp_extract(col, UTC_OFFSET, 2).cast("int"), F.lit(0)) * sign
    minutes = F.coalesce(F.regexp_extract(col, UTC_OFFSET, 3).cast("int"), F.lit(0)) * sign
    return wall - F.make_dt_interval(F.lit(0), hours, minutes)


def _typed(col, rule):
    if rule == "boolean":
        return F.when(col.rlike(BOOLEAN_PATTERN), col == "true")
    if rule == "bigint":
        return F.when(col.rlike(BIGINT_PATTERN), col.cast("long"))
    if rule == "double":
        return F.when(col.rlike(DOUBLE_PATTERN), col.cast("double"))
    if rule == "timestamp":
        return F.when(col.rlike(TIMESTAMP_PATTERN), _utc(col))


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
RAW_ROWS_PROPERTY = "raw-rows"
RULES_PROPERTY = "rules"


def snapshot_rows(spark, table):
    if not spark.catalog.tableExists(table):
        return None
    rows = spark.sql(
        f"SELECT summary['total-records'] AS total FROM {table}.snapshots "
        "ORDER BY committed_at DESC LIMIT 1"
    ).collect()
    return int(rows[0]["total"]) if rows else None


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


def rows_for_keys(spark, table, keys):
    keys.createOrReplaceTempView(KEYS_VIEW)
    return spark.sql(
        f"SELECT * FROM {table} "
        f"WHERE {SOURCE_KEY_COLUMN} IN (SELECT {SOURCE_KEY_COLUMN} FROM {KEYS_VIEW})"
    )


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


def save_totals(spark, table, location, totals, decided, raw_rows):
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
        .tableProperty(RAW_ROWS_PROPERTY, str(raw_rows))
        .tableProperty(RULES_PROPERTY, RULE_FINGERPRINT)
        .createOrReplace()
    )


def load_totals(spark, table, raw_rows):
    """The saved totals, or nothing when they were counted against a different
    traces_raw (a run failed between the two writes) or under different rules."""
    if snapshot_rows(spark, table) is None:
        return {}
    properties = {r["key"]: r["value"] for r in spark.sql(f"SHOW TBLPROPERTIES {table}").collect()}
    if properties.get(RAW_ROWS_PROPERTY) != str(raw_rows) or properties.get(RULES_PROPERTY) != RULE_FINGERPRINT:
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


def read_csv(glue, paths, context):
    """Read CSV objects, each by its own header. With a context, the job bookmark limits
    the read to objects it has not seen yet; with none, every path is read."""
    dyf = glue.create_dynamic_frame.from_options(
        connection_type="s3",
        connection_options={
            "paths": paths,
            "recurse": True,
            "groupFiles": "inPartition",
            "groupSize": GROUP_SIZE_BYTES,
            "attachFilename": SOURCE_KEY_COLUMN,
        },
        format="csv",
        format_options={"withHeader": True, "multiLine": True},
        transformation_ctx=context,
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

    run_started = datetime.datetime.now(datetime.timezone.utc)
    incoming = read_csv(glue, [raw_location], f"raw_csv:{raw_location}")
    if incoming.columns:
        incoming = incoming.persist(StorageLevel.MEMORY_AND_DISK)

    raw_rows = snapshot_rows(spark, raw) or 0
    silver_rows = snapshot_rows(spark, silver) or 0
    frames = [normalize_columns(incoming)] if incoming.columns else []
    late = []
    if raw_rows:
        # The window ends where Glue's own bookmark band begins, so the two never overlap.
        s3 = boto3.client("s3", config=Config(retries={"max_attempts": 10, "mode": "adaptive"}))
        listed = list_csv_keys(s3, raw_location, run_started - RECONCILE_LOOKBACK, run_started - GLUE_BOOKMARK_GRACE_PERIOD)
        known = {r[0] for r in spark.table(raw).select(SOURCE_KEY_COLUMN).distinct().collect()}
        delivered = {r[0] for r in incoming.select(SOURCE_KEY_COLUMN).distinct().collect()} if incoming.columns else set()
        late = unknown_keys(listed, known, delivered, raw_location)
        if late:
            LOG.info("%d object(s) under %s found by key reconciliation", len(late), raw_location)
            reconciled = read_csv(glue, late, "")
            if reconciled.columns:
                frames.append(normalize_columns(reconciled))
            else:
                LOG.warning("none of the %d reconciled object(s) under %s carried a header", len(late), raw_location)
    ingested = 0
    if frames:
        increment = nullify_empty(with_partition_columns(union_by_name(frames), raw_location))
        increment = increment.persist(StorageLevel.MEMORY_AND_DISK)
        bad = invalid_keys(increment, raw_location)
        if bad:
            # Any other CSV under raw_location would add its columns to the table.
            raise RuntimeError(f"object(s) outside the trace layout under {raw_location}: {bad} "
                               "(None means no file name was attached)")
        ingested = increment.count()
        if incoming.columns:
            incoming.unpersist()
        if late:
            with_rows = increment.filter(increment[SOURCE_KEY_COLUMN].isin(late)).select(SOURCE_KEY_COLUMN).distinct().count()
            LOG.info("%d of %d reconciled object(s) carried rows", with_rows, len(late))
    if not ingested:
        if not raw_rows:
            raise RuntimeError(f"no trace rows read under {raw_location}")
        LOG.info("no new rows under %s", raw_location)
        job.commit()
        return

    columns = data_columns(increment)
    stats = profile(increment, columns)

    keys = increment.select(SOURCE_KEY_COLUMN).distinct()
    current = current_types(spark.table(silver).schema) if silver_rows else {}
    previous = load_totals(spark, typing, raw_rows) if raw_rows else {}
    replaced = 0
    if raw_rows:
        stale = rows_for_keys(spark, raw, keys)
        replaced = stale.count()
        if replaced:
            LOG.warning("%d row(s) of already ingested objects were replaced", replaced)
            if previous:
                previous = subtract_totals(previous, profile(stale, data_columns(stale)))
            delete_keys(spark, raw, keys)
        append_rows(increment, raw)
    else:
        replace_table(increment, raw, location(RAW_TABLE))

    if previous:
        totals = merge_totals(previous, stats)
    else:
        if raw_rows:
            LOG.warning("%s has no totals matching %s; profiling from history", typing, raw)
        history = spark.table(raw)
        totals = profile(history, data_columns(history))
    decided = {c: decide_type(c, s.non_null, s.matches) for c, s in totals.items()}
    save_totals(spark, typing, location(TYPING_TABLE), totals, decided, snapshot_rows(spark, raw))

    changed = changed_decisions(current, decided)
    for column, (old, new) in sorted(changed.items()):
        LOG.info("column %s changes from %s to %s", column, old, new)
    rebuild = rebuild_needed(changed, raw_rows, current)

    if rebuild:
        replace_table(apply_types(spark.table(raw), decided), silver, location(TARGET_TABLE))
    else:
        delete_keys(spark, silver, keys)
        append_rows(apply_types(increment, decided), silver)
    increment.unpersist()
    written = snapshot_rows(spark, silver)
    LOG.info("%s %s: %d rows ingested, %d rows total (previous %d)",
             "rebuilt" if rebuild else "appended", silver, ingested, written, silver_rows)

    # Every table is written before the bookmark advances, so a run that fails earlier
    # is safe to rerun: the same objects are read again and replace their own rows.
    job.commit()
    cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1)
    for table in (silver, raw, typing):
        expire_snapshots(spark, table, cutoff)
    for table in (silver, raw):
        compact(spark, table)


if __name__ == "__main__":
    main()
