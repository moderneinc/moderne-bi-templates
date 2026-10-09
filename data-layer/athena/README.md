# Data layer: AWS Athena

An AWS Athena implementation of the [data layer](../): it turns the raw trace CSV in your object storage into the wide, typed `traces` table that the [reports](../../reports) read. See the [data layer overview](../) for the table contract and the key layout this assumes.

## How it is built

A nightly AWS Glue job ([`glue/`](glue/)) does all the work and owns three tables:

1. **`traces_raw`** — an Iceberg table holding every row of every CSV object, as strings. Each night the job reads only the objects it hasn't seen before, plus any from the last three days that arrived late, each by its own header, and appends them.
2. **`traces`** — an Iceberg table with the same rows, each column cast to the type its values support (timestamps, counts, durations, rates, booleans). The job appends each night's rows, replaces the rows of any file delivered again, and rebuilds it from `traces_raw` only when a column's type changes. It also carries a `_source_key` column naming the object each row came from, which is the job's bookkeeping rather than a trace field (see the [table contract](../README.md#what-the-reports-expect)). This is the table the reports read.
3. **`traces_typing`** — a small table of per-column value counts, so the job can decide types without re-reading history.

```
raw CSV  ──►  Glue job (bookmarked, reads new objects only)  ──►  traces_raw  ──►  traces  ──►  reports
```

All three are registered in the Glue Data Catalog, which Athena reads natively. A new trace field becomes a new typed column on the next run, with no DDL to edit and no partitions to register.

## Setup

### 1. Deploy and run the Glue job

See [`glue/README.md`](glue/README.md) for uploading the script, creating its role, running it once over your history, and scheduling it nightly. The first run creates the `moderne_telemetry` database and its tables.

### 2. Create an Athena workgroup

Athena writes query results to S3; a dedicated workgroup keeps them tidy and caps cost:

```bash
aws athena create-work-group \
    --name moderne-bi \
    --configuration "ResultConfiguration={OutputLocation=s3://<your-warehouse-bucket>/athena-results/},BytesScannedCutoffPerQuery=107374182400"
```

The `athena-results/` prefix sits beside the table folders, so it won't interfere with data. The 100 GB per-query scan cap guards against runaway cost.

### 3. Query

The reports use **unqualified** table names (`FROM traces`), so make `moderne_telemetry` your Athena query context — pick it in the console's *Database* selector, or run `USE moderne_telemetry;` — first.

Run any report SQL in [`../../reports`](../../reports) as-is. Each one is self-contained: it scopes by command `type`, needs no casts (the columns are typed), and needs no tenant filter.

A report needs at least one trace of each command type it reads. The job adds a column only once some trace has carried it, so if your export has never held, say, a `commit` trace, the `commit*` columns don't exist yet and a report that names them fails with a column-not-found error instead of returning no rows. It works once the first such trace has been through a nightly run.

## Performance

Athena bills on **bytes scanned**, so a few rules keep queries cheap and fast:

- **Filter a date on large datasets.** The reports ship without a date filter so they return all-time results; add `AND year = '2026'` (or a range) once you have enough history that a full scan is wasteful.
- **Narrow `type`.** Restricting `type` to the command types a report needs skips whole partitions — every report here already does this.
- **Read `traces`, not `traces_raw`.** Both are Parquet, but only `traces` is typed; `traces_raw` exists so the job can rebuild `traces`, not for querying.
- **Check the query stats.** In the Athena console, compare *Data scanned* against total runtime to see whether you are scan-bound or planning-bound.

## Other options

- **Use a different engine.** Snowflake external stages, BigQuery BigLake, Databricks Unity Catalog, Microsoft Fabric, and DuckDB all read this Hive-partitioned CSV layout directly.
- **Convenience views (optional).** If you'd rather point a BI tool at a pre-scoped surface than at raw `traces`, you can define views, either in Athena or natively in your BI tool, that encapsulate the same `type` scoping the reports use. See [`views/`](views/).
