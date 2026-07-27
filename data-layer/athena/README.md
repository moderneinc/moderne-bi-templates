# Data layer: AWS Athena

An AWS Athena implementation of the [data layer](../): it turns the raw trace CSV in your object storage into the wide, typed `traces` table that the [reports](../../reports) read. See the [data layer overview](../) for the table contract and the partition layout this assumes.

## How it is built

Because each command **type** writes a different CSV width and column order, a single positional table cannot parse them all, so the layer is built in stages:

1. **Per-type ingest tables** ([`ddl/02-create-ingest-tables.sql`](ddl/02-create-ingest-tables.sql)) — one CSV table per command type over the raw bucket, each pinned to its `type`.
2. **Compaction** ([`compaction/`](compaction/)) — a daily job that reads each ingest table and writes name-aligned Parquet into a compacted bucket, casting each column on the way in. The ingest tables and the raw CSV underneath stay all-string.
3. **The `traces` table** ([`ddl/03-create-traces-table.sql`](ddl/03-create-traces-table.sql)) — one wide Parquet table over the compacted bucket, which the reports read.

```
raw CSV (per-type)  ──►  ingest tables  ──►  compaction (INSERT INTO, as Parquet)  ──►  traces  ──►  reports
```

## Setup

Replace `<your-telemetry-bucket>` (raw replicated CSV) and `<your-compacted-bucket>` (Parquet output) throughout, then:

### 1. Create the database and select it

```bash
ddl/01-create-database.sql        # CREATE DATABASE moderne_telemetry
```

Everything else uses **unqualified** table names (`FROM traces`), so make this database your Athena query context — pick it in the console's *Database* selector, or run `USE moderne_telemetry;` — before running the DDL or the reports.

### 2. Register the tables

```bash
ddl/02-create-ingest-tables.sql   # per-type raw CSV tables (compaction input)
ddl/03-create-traces-table.sql    # the wide Parquet query table
```

The ingest tables use partition projection, so Athena infers their partitions from the path template. The `traces` table instead uses **registered partitions**, which Athena adds as the compaction job writes each day. For a one-time or manual setup you can discover everything already present with `MSCK REPAIR TABLE traces`.

### 3. Create an Athena workgroup

Athena writes query results to S3; a dedicated workgroup keeps them tidy and caps cost:

```bash
aws athena create-work-group \
    --name moderne-bi \
    --configuration "ResultConfiguration={OutputLocation=s3://<your-compacted-bucket>/athena-results/},BytesScannedCutoffPerQuery=107374182400"
```

The `athena-results/` prefix sits outside the partition tree, so it won't interfere with data. The 100 GB per-query scan cap guards against runaway cost.

### 4. Run compaction

See [`compaction/README.md`](compaction/README.md) for deploying the daily CSV→Parquet job and backfilling history. The compactor reads each column's target type from the `traces` table ([`ddl/03-create-traces-table.sql`](ddl/03-create-traces-table.sql)) and casts to match, so register that table first.

### 5. Query

Run any report SQL in [`../../reports`](../../reports) as-is. Each one is self-contained: it scopes by command `type`, needs no casts (the columns are typed), and needs no tenant filter.

## Performance

Athena bills on **bytes scanned**, so a few rules keep queries cheap and fast:

- **Filter a date on large datasets.** The reports ship without a date filter so they return all-time results; add `AND year = '2026'` (or a range) once you have enough history that a full scan is wasteful.
- **Narrow `type`.** Restricting `type` to the command types a report needs prunes whole partitions — every report here already does this.
- **Compact.** Parquet plus column pruning means a report reading five columns scans far less than the raw CSV. If queries feel heavy, confirm compaction is running.
- **Check the query stats.** In the Athena console, compare *Data scanned* against total runtime to see whether you are scan-bound or planning-bound.

## Other options

You do not have to compact. Two lighter alternatives:

- **Query the raw CSV directly.** The per-type ingest tables already expose every column by name — point a report at, say, `traces_run_ingest` (dropping the `type` predicate, since the table is already type-scoped). You trade Parquet's scan efficiency for zero compaction infrastructure, which is a reasonable way to explore before committing to a build.
- **Use a different engine.** Snowflake external stages, BigQuery BigLake, Databricks Unity Catalog, Microsoft Fabric, and DuckDB all read this Hive-partitioned CSV layout directly.

**Convenience views (optional).** If you'd rather point a BI tool at a pre-typed, pre-scoped surface than at raw `traces`, you can define views, either in Athena or natively in your BI tool, that encapsulate the same `type` scoping the reports use. See [`views/`](views/).

