# Compaction — daily CSV → Parquet

[`compact_traces.py`](compact_traces.py) compacts one day of raw trace CSV into the Parquet that backs the `traces` table — the suggested approach for a hands-off, incremental daily build. Read it top to bottom; the module docstring explains the design.

## What it does

For each `(source, type)` partition of your tenant that has raw CSV for the target day, it runs an `INSERT INTO traces` that selects from that type's ingest table ([`../ddl/02-create-ingest-tables.sql`](../ddl/02-create-ingest-tables.sql)), casting each string column to the `traces` table's declared type (read from Glue, so the DDL stays the single source of truth). Athena writes the Parquet into the partition path and registers the partition itself, so there is no staging table to manage and no `ALTER TABLE ADD PARTITION` to run.

Each partition is deleted before it is written, so re-running a day replaces it rather than appending a second copy of every row. The output location is read from the `traces` table's own Glue definition, so the delete targets the same location Athena writes to.

The `SELECT` also strips the trailing carriage return that CRLF line endings leave on the last CSV column (`organization`).

## Configuration

The handler reads these environment variables:

| Variable                  | Purpose                                                       |
|---------------------------|---------------------------------------------------------------|
| `RAW_BUCKET`              | Bucket holding the replicated raw trace CSV                    |
| `GLUE_DATABASE`           | Glue database, e.g. `moderne_telemetry`                       |
| `ATHENA_WORKGROUP`        | Workgroup to run queries in (e.g. `primary` or `moderne-bi`)  |
| `ATHENA_RESULTS_LOCATION` | S3 location for Athena query results                          |
| `TENANT`                  | Your tenant — the `tenant=` value in the export path          |

The IAM role needs S3 read on the raw bucket, S3 read/write/delete on the compacted bucket, Athena `StartQueryExecution`/`GetQueryExecution`, and Glue read (`GetTable`/`GetPartition`) plus `UpdateTable` and `CreatePartition`/`BatchCreatePartition`, which Athena uses to register the partitions it writes.

## Running

Runs as an AWS Lambda or from a shell with AWS credentials and the env vars above set. With no day it compacts *yesterday* (today is still being written, so it is never compacted); pass a day to backfill. Re-running a day replaces it, so you can safely loop a date range.

```bash
# as a Lambda, one day
aws lambda invoke --function-name <fn> --payload '{"day":"2026-06-01"}' out.json

# or locally
python compact_traces.py 2026-06-01     # omit the date for yesterday
```

## Making it production-grade

This example is deliberately minimal — it runs sequentially, for one tenant, with no metrics, alarms, retries, or parallelism. Nothing here is Moderne-specific; it is stock Athena + S3, so add what your environment needs. For example:

- **Scheduling** — an EventBridge rule (e.g. daily at 02:00 UTC) that invokes it with no payload.
- **Observability** — emit CloudWatch metrics and alarm on failures, and on a run that compacted nothing (which the plain Lambda `Errors` metric can't see).
- **Error handling** — isolate per-partition failures so one bad type doesn't abort the whole day; alert on a failed invocation.
- **Scale** — run partitions concurrently, and note that a very large single day can exceed the Athena query wait or the Lambda timeout.

None of that changes the core contract: read the per-type ingest table, write typed Parquet under the partition path, strip the trailing CR on `organization`.

## Approaches

- **This scheduled job (incremental).** Best for ongoing, hands-off daily compaction: it replaces late and backfilled days cleanly and never re-scans history. Cost: it is the most infrastructure to stand up and own.
- **A one-shot CTAS.** `CREATE TABLE traces WITH (format = 'PARQUET', partitioned_by = ARRAY['tenant','source','type','year','month','day']) AS SELECT <cast columns>, <partitions> FROM <ingest union>`. Materializes a typed Parquet `traces` in a single statement, with no Lambda and no scheduler. Downsides: it is one-shot (re-runs need drop/recreate), and Athena caps CTAS at ~100 partitions per statement, so it does not scale to daily-per-partition. Ideal for an initial load or small data.
- **A saved `INSERT INTO` query.** The same statement this job runs, kept as an Athena saved query you trigger yourself. No Lambda to own; you give up the discovery, the per-partition delete, and the scheduling.
- **Glue ETL job.** A visual or PySpark AWS Glue job reads the CSV and writes typed Parquet, using the Glue Data Catalog as the schema. More managed than a hand-rolled Lambda if you already use Glue.
- **Warehouse-native / dbt.** If your BI stack runs on a warehouse (Snowflake, BigQuery, Databricks), a dbt model or the warehouse's own scheduled task that reads the external CSV and writes a typed table is often the most maintainable — the transform lives with the rest of your analytics code.
- **No compaction at all.** Query the raw CSV ingest tables directly (see [`../README.md`](../README.md#other-options)). Simplest of all; you trade Parquet's scan efficiency for zero build infrastructure.
