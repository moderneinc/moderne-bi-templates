# Data layer: Google BigQuery

A Google BigQuery implementation of the [data layer](../): it turns the raw trace CSV from your telemetry export into the wide, typed `traces` table that the [reports](../../reports) read. See the [data layer overview](../) for the table contract and the key layout this assumes.

## How it is built

Starting from the raw trace CSV in a Cloud Storage bucket of yours, a nightly job ([`external-table/`](external-table/)) reads each new file once, writes a copy with the two things fixed that BigQuery can't read, and owns two objects over those copies:

1. **`traces_raw`**: a BigLake external table over the fixed copies, every column a string. BigQuery matches each file's columns to the table by header name, so every command type's files feed the one wide table and a file that lacks a column reads it as `NULL`. The job adds a column the first time a header carries it. Hive partitioning supplies `tenant`, `source`, `type`, `year`, `month`, `day` from each object's path.
2. **`traces`**: a view over `traces_raw` with each column cast to the type its values support (timestamps, counts, durations, rates, booleans), by the same rules the Glue job uses. The job decides the types from the data each night and rebuilds the view. This is the table the reports read.

```
raw CSV in Cloud Storage  ──►  nightly job (new files only, headers fixed)  ──►  traces_raw (external, strings)  ──►  traces (view, typed)  ──►  reports
```

There is no load: a query reads the fixed copies where they sit. A new trace field becomes a typed, queryable column on the next run, with no DDL to edit.

## Setup

### 1. Run the job

See [`external-table/README.md`](external-table/README.md) for landing the files, creating the dataset and the connection, running the job once over your history, and scheduling it nightly. The first run creates `traces_raw` and `traces`.

### 2. Query

The reports use **unqualified** table names (`FROM traces`), so pass `moderne_telemetry` as the default dataset:

```bash
bq query --use_legacy_sql=false --dataset_id=moderne_telemetry < ../../reports/top-recipes/top-recipes.sql
```

In the console, write `moderne_telemetry.traces` instead.

The report SQL is written for Athena (Trino). The reports that trend by month call `date_trunc('month', col)`; in BigQuery write `TIMESTAMP_TRUNC(col, MONTH)`. The rest runs unchanged: each report scopes by command `type`, needs no casts (the columns are typed), and needs no tenant filter.

A column exists only once some object has carried it, as on Athena. If your export has never held a given command type, a report that names one of its columns fails with a column-not-found error instead of returning no rows; it works once the first such trace has been through a nightly run.

## Performance

BigQuery on-demand pricing bills on **bytes read**, and a CSV external table reads every byte of every file a query touches, with no column pruning, so the rules differ a little from Athena's:

- **Filter on the partition columns.** `type` skips every file of the other command types, and every report here already does this. Add `AND year = '2026'` (or a range) once you have enough history that an all-time scan is wasteful; the partition columns are strings, so quote the value.
- **Read `traces`, not `traces_raw`.** They scan the same bytes, but only `traces` is typed; `traces_raw` exists so the job can rebuild `traces`, not for querying.
- **Read `traces` through a native table for heavy use.** If dashboards refresh often, see [making it production-grade](external-table/README.md#making-it-production-grade).
- **Check the job statistics.** In the console's *Job information*, compare *Bytes processed* against *Duration* to see whether a query is read-bound or listing-bound.

## Other options

- **Convenience views (optional).** If you'd rather point a BI tool at a pre-scoped surface than at raw `traces`, you can define views, either in BigQuery or natively in your BI tool, that encapsulate the same `type` scoping the reports use. See [`views/`](views/).
- **A different engine.** See the [data layer overview](../#adding-another-engine).
