"""Daily CSV → Parquet compaction for a single tenant's Moderne telemetry.

Compacts one day at a time: yesterday by default, or the day named in the event
({"day": "YYYY-MM-DD"}) for a backfill. For each (source, type) that has raw CSV
that day, it runs an INSERT INTO that reads the per-type ingest table, casts each
string column to the type `traces` declares (read from Glue, so the DDL stays the
source of truth), and writes Parquet straight into the partition. Athena registers
the new partition itself, so no ALTER TABLE is needed. The SELECT also strips the
trailing CR that CRLF (\\r\\n) line endings leave on the last column (organization).

Each partition is deleted before it is written, so a re-run replaces a day rather
than appending duplicate rows. The output location comes from the `traces` table's
own Glue definition, so the delete targets the same location Athena writes to.

This is a minimal, readable example: it runs sequentially, one tenant, and has no
metrics, alarms, retries, or parallelism. Set TENANT to your tenant. For production,
add whatever observability, error handling, scaling, and scheduling you need — see
the README. Runs as an AWS Lambda (lambda_handler) or from a shell with AWS creds
(`python compact_traces.py [YYYY-MM-DD]`).
"""

from __future__ import annotations

import datetime as dt
import logging
import os
import re
import time
from typing import Iterable

import boto3

LOG = logging.getLogger()
LOG.setLevel(logging.INFO)

RAW_BUCKET = os.environ["RAW_BUCKET"]
DATABASE = os.environ["GLUE_DATABASE"]
WORKGROUP = os.environ["ATHENA_WORKGROUP"]
RESULTS_LOCATION = os.environ["ATHENA_RESULTS_LOCATION"]
TENANT = os.environ["TENANT"]

# Max wait for a single Athena query before it counts as failed (Athena keeps
# running server-side regardless).
QUERY_TIMEOUT_S = 600

# The export writes source=cli and source=saas; both are compacted.
SOURCES = ("cli", "saas")

TYPE_INGEST_TABLES = {
    "sync": "traces_sync_ingest",
    "build": "traces_build_ingest",
    "run": "traces_run_ingest",
    "apply": "traces_apply_ingest",
    "add": "traces_add_ingest",
    "commit": "traces_commit_ingest",
    "publish": "traces_publish_ingest",
    "mcp": "traces_mcp_ingest",
}

COMPACTED_TABLE = "traces"

# Partition values are interpolated into SQL, so they are validated before use.
_PARTITION_VALUE_RE = re.compile(r"^[A-Za-z0-9_-]+$")

_s3 = boto3.client("s3")
_athena = boto3.client("athena")
_glue = boto3.client("glue")


def lambda_handler(event, context=None):
    day = _resolve_day(event or {}, dt.datetime.now(dt.UTC).date())
    partitions = list(_discover_partitions(day))
    LOG.info("compacting %d partition(s) for %s", len(partitions), day)

    bucket, prefix = _traces_location()
    for p in partitions:
        # Clear the partition first so a re-run replaces the day instead of
        # appending a second copy of every row. The location comes from the
        # `traces` table itself, so this can't target a different bucket than
        # the one Athena writes to.
        _delete_prefix(bucket, f"{prefix}{_partition_path(p)}/")
        _wait_for_query(_start_insert(p))
        LOG.info("compacted %s", _partition_path(p))

    return {"day": day.isoformat(), "compacted": len(partitions)}


# --------------------------------------------------------------------------
# Discovery
# --------------------------------------------------------------------------

def _resolve_day(event: dict, today_utc: dt.date) -> dt.date:
    """The single day to compact: yesterday by default, or the event's
    {"day": ISO} for a backfill. Never today — the current day is still being
    written, so it is clamped to yesterday."""
    yesterday = today_utc - dt.timedelta(days=1)
    day = dt.date.fromisoformat(event["day"]) if event.get("day") else yesterday
    return min(day, yesterday)


def _discover_partitions(day: dt.date) -> Iterable[dict]:
    """Yield {tenant, source, type, year, month, day} dicts for each (source, type)
    that has raw data for `day`. source/type come from bounded sets and each
    candidate is probed for data, so there is no full-history walk."""
    for src in SOURCES:
        for trace_type in TYPE_INGEST_TABLES:
            p = {
                "tenant": TENANT,
                "source": src,
                "type": trace_type,
                "year": f"{day.year:04d}",
                "month": f"{day.month:02d}",
                "day": f"{day.day:02d}",
            }
            if not all(_PARTITION_VALUE_RE.match(v) for v in p.values()):
                LOG.warning("skipping non-conforming partition: %s", p)
                continue
            if _has_raw_data(p):
                yield p


def _has_raw_data(p: dict) -> bool:
    """True if the raw bucket holds at least one object under this partition."""
    resp = _s3.list_objects_v2(
        Bucket=RAW_BUCKET, Prefix=_partition_path(p) + "/", MaxKeys=1)
    return resp.get("KeyCount", 0) > 0


def _partition_path(p: dict) -> str:
    """The bare ``tenant=.../day=...`` partition path, no leading prefix or
    trailing slash."""
    return (
        f"tenant={p['tenant']}/source={p['source']}/type={p['type']}/"
        f"year={p['year']}/month={p['month']}/day={p['day']}"
    )


# --------------------------------------------------------------------------
# Typing + the INSERT
# --------------------------------------------------------------------------

_INGEST_COLUMNS: dict[str, list[str]] = {}
_TRACES_COLUMN_TYPES: dict[str, str] = {}


def _data_columns(table: str) -> list[str]:
    """Data (non-partition) column names for an ingest table, from its Glue schema,
    cached per run. Lets the INSERT list columns explicitly rather than via a
    SELECT * modifier (which is engine-version-specific) while the Glue table
    definitions (../ddl/) stay the source of truth for the schema. Partition keys
    are excluded — they come from the path, not the row data."""
    cols = _INGEST_COLUMNS.get(table)
    if cols is None:
        resp = _glue.get_table(DatabaseName=DATABASE, Name=table)
        cols = [c["Name"] for c in resp["Table"]["StorageDescriptor"]["Columns"]]
        _INGEST_COLUMNS[table] = cols
    return cols


def _traces_location() -> tuple[str, str]:
    """(bucket, key prefix) the `traces` table is stored at, from its Glue
    definition. Taking it from the table rather than an env var keeps the
    partition delete pointed at the location Athena writes to."""
    resp = _glue.get_table(DatabaseName=DATABASE, Name=COMPACTED_TABLE)
    location = resp["Table"]["StorageDescriptor"]["Location"]
    if not location.startswith("s3://"):
        raise ValueError(f"unexpected {COMPACTED_TABLE} location: {location!r}")
    bucket, _, prefix = location[len("s3://"):].partition("/")
    if prefix and not prefix.endswith("/"):
        prefix += "/"
    return bucket, prefix


def _traces_column_types() -> dict[str, str]:
    """Target type per column, read from the `traces` Glue table so the DDL stays
    the single source of truth — a schema/type change needs no edit here."""
    if not _TRACES_COLUMN_TYPES:
        resp = _glue.get_table(DatabaseName=DATABASE, Name=COMPACTED_TABLE)
        for c in resp["Table"]["StorageDescriptor"]["Columns"]:
            _TRACES_COLUMN_TYPES[c["Name"]] = c.get("Type", "string")
    return _TRACES_COLUMN_TYPES


def _cast_expr(col: str, target_type: str) -> str:
    if target_type == "string":
        return col
    if target_type == "timestamp":
        return f"TRY(CAST(from_iso8601_timestamp({col}) AS timestamp)) AS {col}"
    if target_type in ("bigint", "double", "boolean"):
        return f"TRY_CAST({col} AS {target_type}) AS {col}"
    raise ValueError(f"unsupported Glue type {target_type!r} for column {col!r}")


def _start_insert(p: dict) -> str:
    """INSERT INTO `traces` for one partition. Athena writes Parquet to the
    partition path and registers the partition in Glue, so no staging table,
    object moves, or ALTER TABLE ADD PARTITION are needed."""
    ingest_table = TYPE_INGEST_TABLES[p["type"]]
    # Explicit column list from the ingest table's Glue schema, casting each column
    # to its `traces` type. organization carries a trailing CR from \r\n line
    # endings; chr(13) strips it (a literal '\r' would NOT work — Trino string
    # literals don't expand backslash escapes). The partition columns are selected
    # last, in the order `traces` declares them.
    types = _traces_column_types()
    select_list = ",\n       ".join(
        f"regexp_replace({c}, chr(13), '') AS {c}" if c == "organization"
        else _cast_expr(c, types.get(c, "string"))
        for c in _data_columns(ingest_table)
    )
    sql = (
        f'INSERT INTO "{DATABASE}"."{COMPACTED_TABLE}"\n'
        f"SELECT {select_list},\n"
        f"       tenant, source, type, year, month, day\n"
        f'FROM "{DATABASE}"."{ingest_table}"\n'
        f"WHERE tenant = '{p['tenant']}'\n"
        f"  AND source = '{p['source']}'\n"
        f"  AND type   = '{p['type']}'\n"
        f"  AND year   = '{p['year']}'\n"
        f"  AND month  = '{p['month']}'\n"
        f"  AND day    = '{p['day']}'"
    )
    return _start_query(sql)


def _start_query(sql: str) -> str:
    return _athena.start_query_execution(
        QueryString=sql,
        WorkGroup=WORKGROUP,
        QueryExecutionContext={"Database": DATABASE},
        ResultConfiguration={"OutputLocation": RESULTS_LOCATION},
    )["QueryExecutionId"]


def _wait_for_query(qid: str, timeout_s: float = QUERY_TIMEOUT_S) -> None:
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        s = _athena.get_query_execution(QueryExecutionId=qid)["QueryExecution"]["Status"]
        state = s["State"]
        if state == "SUCCEEDED":
            return
        if state in ("FAILED", "CANCELLED"):
            raise RuntimeError(f"Athena query {qid} {state}: {s.get('StateChangeReason')}")
        time.sleep(2)
    raise TimeoutError(f"Athena query {qid} did not finish within {timeout_s}s")


# --------------------------------------------------------------------------
# S3
# --------------------------------------------------------------------------

def _delete_prefix(bucket: str, prefix: str) -> None:
    keys = list(_iter_keys(bucket, prefix))
    for i in range(0, len(keys), 1000):
        batch = keys[i:i + 1000]
        resp = _s3.delete_objects(
            Bucket=bucket,
            Delete={"Objects": [{"Key": k} for k in batch]},
        )
        errors = resp.get("Errors") or []
        if errors:
            raise RuntimeError(f"failed to delete {len(errors)} object(s) under {prefix}: {errors[:3]}")


def _iter_keys(bucket: str, prefix: str) -> Iterable[str]:
    paginator = _s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents") or []:
            yield obj["Key"]


if __name__ == "__main__":
    import json
    import sys

    event = {"day": sys.argv[1]} if len(sys.argv) > 1 else {}
    print(json.dumps(lambda_handler(event)))
