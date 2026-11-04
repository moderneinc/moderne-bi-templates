import argparse
import collections
import concurrent.futures
import csv
import logging
import re
import threading

from google.api_core.exceptions import NotFound
from google.cloud import bigquery, storage

LOG = logging.getLogger("build_traces")
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

RAW_TABLE = "traces_raw"
TARGET_TABLE = "traces"
PARTITION_COLUMNS = ("tenant", "source", "type", "year", "month", "day")
KEY_PATTERN = re.compile(
    r"^tenant=[^/=]+/source=[^/=]+/type=[^/=]+/year=\d{4}/month=\d{2}/day=\d{2}/[^/]+\.csv$"
)
ZONE_ID = re.compile(r"(Z|[+-]\d{2}:\d{2})\[[A-Za-z0-9_+/-]+\]")
SOURCE_CHECKSUM = "source-crc32c"
WORKERS = 10

BOOLEAN_PATTERN = r"^(true|false)$"
BIGINT_PATTERN = r"^-?\d{1,18}$"
DOUBLE_PATTERN = r"^(-?\d{1,18}(\.\d+)?([eE][+-]?\d+)?|NaN|-?Infinity)$"
TIMESTAMP_PATTERN = r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?(Z|[+-]\d{2}:\d{2})(\[[^\]]+\])?$"
RULE_PATTERNS = {
    "boolean": BOOLEAN_PATTERN,
    "bigint": BIGINT_PATTERN,
    "double": DOUBLE_PATTERN,
    "timestamp": TIMESTAMP_PATTERN,
}
RULES = tuple(RULE_PATTERNS)
THRESHOLD_NUMERATOR = 999
THRESHOLD_DENOMINATOR = 1000
EXPRESSIONS = {
    "boolean": "SAFE_CAST({} AS BOOL)",
    "bigint": "SAFE_CAST({} AS INT64)",
    "double": "SAFE_CAST({} AS FLOAT64)",
    "timestamp": "SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S%Ez', {})",
    "string": "NULLIF({}, '')",
}
BIGQUERY_TYPE_RULES = {
    "BOOL": "boolean", "BOOLEAN": "boolean",
    "INT64": "bigint", "INTEGER": "bigint",
    "FLOAT64": "double", "FLOAT": "double",
    "TIMESTAMP": "timestamp",
    "STRING": "string",
}


def split_uri(uri, scheme):
    match = re.fullmatch(rf"{scheme}://([^/]+)/(|.*/)", uri)
    if match is None:
        raise ValueError(f"{uri!r} must look like {scheme}://bucket/prefix/ and end in /")
    return match.group(1), match.group(2)


def column_name(header):
    return re.sub(r"[^A-Za-z0-9_]", "_", header.strip())


def rewrite(text):
    header, newline, body = text.partition("\n")
    columns = [column_name(c) for c in next(csv.reader([header]))]
    line_end = "\r" + newline if header.endswith("\r") else newline
    return columns, ",".join(columns) + line_end + ZONE_ID.sub(r"\1", body)


def list_source(bucket, prefix):
    objects = {}
    outside = 0
    for blob in bucket.list_blobs(prefix=prefix):
        key = blob.name[len(prefix):]
        if KEY_PATTERN.match(key):
            objects[key] = blob.crc32c
        else:
            outside += 1
    return objects, outside


def list_destination(bucket, prefix):
    return {
        blob.name[len(prefix):]: (blob.metadata or {}).get(SOURCE_CHECKSUM)
        for blob in bucket.list_blobs(prefix=prefix)
    }


def is_always_string(column):
    name = column.lower()
    return column in PARTITION_COLUMNS or name.endswith("id") or name.startswith("tag_")


def decide_type(column, non_null, matches):
    if is_always_string(column) or non_null <= 0:
        return "string"
    for rule in RULES:
        if matches[rule] * THRESHOLD_DENOMINATOR >= THRESHOLD_NUMERATOR * non_null:
            return rule
    return "string"


def profile_sql(table_id, columns):
    aggregates = []
    for column in columns:
        aggregates.append(f"COUNTIF(`{column}` <> '') AS `{column}__nonnull`")
        for rule, pattern in RULE_PATTERNS.items():
            aggregates.append(f"COUNTIF(REGEXP_CONTAINS(`{column}`, r'{pattern}')) AS `{column}__{rule}`")
    return "SELECT " + ", ".join(aggregates) + f" FROM `{table_id}`"


def decide_types(row, columns):
    return {
        column: decide_type(column, row[f"{column}__nonnull"], {rule: row[f"{column}__{rule}"] for rule in RULES})
        for column in columns
    }


def view_sql(view_id, raw_id, columns, decided):
    selected = [f"`{c}`" for c in PARTITION_COLUMNS]
    selected += [EXPRESSIONS[decided[c]].format(f"`{c}`") + f" AS `{c}`" for c in columns]
    return f"CREATE OR REPLACE VIEW `{view_id}` AS\nSELECT\n    " + ",\n    ".join(selected) + f"\nFROM `{raw_id}`"


def changed_decisions(current, decided):
    return {c: (current[c], decided[c]) for c in decided if c in current and current[c] != decided[c]}


def external_config(destination, connection):
    bucket, prefix = destination
    config = bigquery.ExternalConfig("CSV")
    config.source_uris = [f"gs://{bucket}/{prefix}*.csv"]
    config.autodetect = False
    config.ignore_unknown_values = True
    config.connection_id = connection
    hive = bigquery.HivePartitioningOptions()
    hive.mode = "STRINGS"
    hive.source_uri_prefix = f"gs://{bucket}/{prefix}"
    config.hive_partitioning = hive
    config.csv_options.allow_jagged_rows = True
    config.csv_options.allow_quoted_newlines = True
    config.csv_options.skip_leading_rows = 1
    config.csv_options.source_column_match = "NAME"
    return config


class RawTable:
    def __init__(self, client, table_id):
        self.client = client
        self.table_id = table_id
        self.lock = threading.Lock()
        try:
            self.table = client.get_table(table_id)
        except NotFound:
            self.table = None
        self.columns = [field.name for field in self.table.schema] if self.table else []
        self.known = {c.lower() for c in self.columns}

    def exists(self):
        return self.table is not None

    def data_columns(self):
        return [c for c in self.columns if c not in PARTITION_COLUMNS]

    def ensure(self, header):
        if all(c.lower() in self.known for c in header):
            return
        with self.lock:
            unknown = list({c.lower(): c for c in header if c.lower() not in self.known}.values())
            if not unknown:
                return
            if self.table is not None:
                self.table.schema = list(self.table.schema) + [bigquery.SchemaField(c, "STRING") for c in unknown]
                self.table = self.client.update_table(self.table, ["schema"])
                LOG.info("column(s) %s added to %s", ", ".join(unknown), self.table_id)
            self.columns.extend(unknown)
            self.known.update(c.lower() for c in unknown)

    def create(self, header, destination, connection):
        self.columns = list(dict.fromkeys(list(header) + list(PARTITION_COLUMNS)))
        self.known = {c.lower() for c in self.columns}
        table = bigquery.Table(self.table_id, schema=[bigquery.SchemaField(c, "STRING") for c in self.columns])
        table.external_data_configuration = external_config(destination, connection)
        self.table = self.client.create_table(table)


def current_types(client, view_id):
    try:
        view = client.get_table(view_id)
    except NotFound:
        return {}
    return {field.name: BIGQUERY_TYPE_RULES.get(field.field_type) for field in view.schema}


def main():
    parser = argparse.ArgumentParser(
        description="Read raw trace CSV from Cloud Storage and keep the BigQuery traces table over a fixed copy of it."
    )
    parser.add_argument("--source", required=True, metavar="gs://bucket/prefix/",
                        help="where the raw files land; the prefix directly above tenant=")
    parser.add_argument("--destination", required=True, metavar="gs://bucket/prefix/",
                        help="where the fixed copies go; the external table reads this prefix")
    parser.add_argument("--dataset", required=True, metavar="[project.]dataset",
                        help="the dataset that holds traces_raw and traces")
    parser.add_argument("--connection", required=True, metavar="project.region.name",
                        help="the BigLake connection the external table reads the bucket through")
    args = parser.parse_args()

    source_bucket, source_prefix = split_uri(args.source, "gs")
    destination_bucket, destination_prefix = split_uri(args.destination, "gs")
    if args.source.startswith(args.destination) or args.destination.startswith(args.source):
        raise ValueError("--source and --destination must not overlap")
    gcs = storage.Client()
    source = (gcs.bucket(source_bucket), source_prefix)
    dataset = bigquery.DatasetReference.from_string(args.dataset, default_project=bigquery.Client().project)
    bq = bigquery.Client(project=dataset.project)
    raw = RawTable(bq, f"{dataset.project}.{dataset.dataset_id}.{RAW_TABLE}")
    view_id = f"{dataset.project}.{dataset.dataset_id}.{TARGET_TABLE}"
    destination = (gcs.bucket(destination_bucket), destination_prefix)

    objects, outside = list_source(*source)
    if not objects:
        raise RuntimeError(f"no trace objects under {args.source}")
    if outside:
        LOG.warning("%d object(s) under %s are outside the trace layout and were not copied",
                    outside, args.source)
    if raw.exists():
        copied = list_destination(*destination)
        pending = sorted(key for key, etag in objects.items() if copied.get(key) != etag)
    else:
        pending = sorted(objects)
    LOG.info("%d object(s) under %s, %d to copy", len(objects), args.source, len(pending))
    current = current_types(bq, view_id)
    if not pending and current:
        return

    def copy(key):
        body = source[0].blob(source_prefix + key).download_as_bytes()
        header, text = rewrite(body.decode("utf-8"))
        raw.ensure(header)
        blob = destination[0].blob(destination_prefix + key)
        blob.metadata = {SOURCE_CHECKSUM: objects[key]}
        blob.upload_from_string(text, content_type="text/csv")
        return header

    rest = pending
    if not raw.exists():
        raw.create(copy(pending[0]), (destination_bucket, destination_prefix), args.connection)
        LOG.info("created %s with %d column(s)", raw.table_id, len(raw.data_columns()))
        rest = pending[1:]
    with concurrent.futures.ThreadPoolExecutor(WORKERS) as pool:
        for _ in pool.map(copy, rest):
            pass
    LOG.info("%d object(s) copied to %s", len(pending), args.destination)

    columns = raw.data_columns()
    profile = next(iter(bq.query(profile_sql(raw.table_id, columns)).result()))
    decided = decide_types(profile, columns)
    for column, (old, new) in sorted(changed_decisions(current, decided).items()):
        LOG.info("column %s changes from %s to %s", column, old, new)
    bq.query(view_sql(view_id, raw.table_id, columns, decided)).result()
    LOG.info("%s %s: %d column(s), %s", "replaced" if current else "created", view_id, len(columns),
             dict(collections.Counter(decided.values())))


if __name__ == "__main__":
    main()
