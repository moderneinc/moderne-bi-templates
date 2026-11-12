# Data layer: AWS Athena

This is the Athena version of the [data layer](../). It takes the raw trace CSV in your object storage and turns it into the wide, typed `traces` table that the [reports](../../reports) read. The [data layer overview](../) describes the table contract and the key layout this assumes.

## How it is built

A nightly AWS Glue job ([`glue/`](glue/)) does all the work and owns three tables:

1. `traces_raw` is an Iceberg table holding every row of every CSV object, as strings. Each night the job appends the objects it hasn't seen before, plus any from the last three days that arrived late. It reads each object by its own header.
2. `traces` is an Iceberg table with the same rows, each column cast to the type its values support (timestamps, counts, durations, rates, booleans). This is the table the reports read. Each night the job appends the new rows and replaces the rows of any file that was delivered again. It rebuilds the table from `traces_raw` only when a column's type changes. A `_source_key` column names the object each row came from. That's the job's bookkeeping, not a trace field (see the [table contract](../README.md#what-the-reports-expect)).
3. `traces_typing` is a small table of per-column value counts, so the job can decide types without re-reading history.

```
raw CSV  ──►  Glue job (bookmarked, reads new objects only)  ──►  traces_raw  ──►  traces  ──►  reports
```

All three are registered in the Glue Data Catalog, which Athena reads natively. A new trace field becomes a new typed column on the next run, with no DDL to edit and no partitions to register.

## Setup

### 1. Deploy and run the Glue job

[`glue/README.md`](glue/README.md) walks through uploading the script, creating its role, running it once over your history, and scheduling it nightly. The first run creates the `moderne_telemetry` database and its tables.

### 2. Create an Athena workgroup

Athena writes query results to S3. A dedicated workgroup keeps them organized and caps cost:

```bash
aws athena create-work-group \
    --name moderne-bi \
    --configuration "ResultConfiguration={OutputLocation=s3://<your-warehouse-bucket>/athena-results/},BytesScannedCutoffPerQuery=107374182400"
```

The `athena-results/` prefix sits beside the table folders, so it won't interfere with data. The 100 GB per-query scan cap protects you from a runaway query.

### 3. Query

The reports use unqualified table names (`FROM traces`), so make `moderne_telemetry` your Athena query context first, either by picking it in the console's *Database* selector or by running `USE moderne_telemetry;`.

Then run any report SQL in [`../../reports`](../../reports) as is. Each one is self-contained: it filters on command `type` itself, and you don't need casts or a tenant filter.

If your export has no traces of a command type yet, a report that uses that type fails with a column-not-found error instead of returning no rows. The job adds a type's columns the first time one of its traces shows up, so the report starts working after the next nightly run.

## Performance

Athena bills on bytes scanned, so a few habits keep queries cheap and fast:

- The reports ship without a date filter so they return all-time results. Once you have enough history that a full scan is wasteful, add `AND year = '2026'` (or a range).
- Narrow `type`. Restricting it to the command types a report needs skips whole partitions, and every report here already does that.
- Query `traces`, not `traces_raw`. Both are Parquet, but only `traces` is typed. `traces_raw` is there so the job can rebuild `traces`.
- To tell whether you're scan-bound or planning-bound, compare *Data scanned* against total runtime in the Athena console.

## Other options

- A different engine. [`../bigquery/`](../bigquery/) covers Google BigQuery. Snowflake external stages, Databricks Unity Catalog, Microsoft Fabric, and DuckDB all read this Hive-partitioned CSV layout directly.
- Convenience views. If you'd rather point a BI tool at something already scoped by command type than at raw `traces`, define views for it, either in Athena or in your BI tool, using the same `type` filter the reports use. See [`views/`](views/).
