# Data layer: Google BigQuery

This is the BigQuery version of the [data layer](../). It takes the raw trace CSV from your telemetry export and turns it into the wide, typed `traces` table that the [reports](../../reports) read. The [data layer overview](../) describes the table contract and the key layout this assumes.

## How it is built

A nightly job ([`external-table/`](external-table/)) starts from the raw trace CSV in a Cloud Storage bucket of yours. It reads each new file once, writes a copy with the two things BigQuery can't read fixed, and looks after two objects over those copies:

1. `traces_raw` is a BigLake external table over the fixed copies, with every column a string. BigQuery matches columns by header name. That's how files from every command type fit in one wide table: if a file is missing a column, it reads as `NULL`. The job adds a column the first time a header has it. Hive partitioning gives you `tenant`, `source`, `type`, `year`, `month`, and `day` from each object's path.
2. `traces` is a view over `traces_raw` that casts each column to the type its values support (timestamps, counts, durations, rates, booleans). The job works out the types from the data each night and rebuilds the view. This is the one the reports read.

```
raw CSV in Cloud Storage  ──►  nightly job (new files only, headers fixed)  ──►  traces_raw (external, strings)  ──►  traces (view, typed)  ──►  reports
```

There's no load step. A query reads the fixed copies where they sit, and a new trace field becomes a typed, queryable column on the next run, with no DDL to edit.

## Setup

### 1. Run the job

[`external-table/README.md`](external-table/README.md) walks through getting the files into Cloud Storage, creating the dataset and the connection, running the job once over your history, and scheduling it nightly. The first run creates `traces_raw` and `traces`.

### 2. Query

The reports use unqualified table names (`FROM traces`), so pass `moderne_telemetry` as the default dataset:

```bash
bq query --use_legacy_sql=false --dataset_id=moderne_telemetry < ../../reports/top-recipes/top-recipes.sql
```

In the console, write `moderne_telemetry.traces` instead.

The report SQL is written in Trino syntax, and one thing in it needs changing for BigQuery. The reports that trend by month call `date_trunc('month', col)`; write `TIMESTAMP_TRUNC(col, MONTH)` instead. Everything else runs as is. Each report filters on command `type`, and you don't need casts (the columns are typed) or a tenant filter.

If your export has never contained a given command type, a report that uses its columns fails with a column-not-found error instead of returning no rows. It starts working once the first trace of that type has been through a nightly run.

## Performance

BigQuery on-demand pricing bills on bytes read, and a CSV external table reads every byte of every file a query touches, with no column pruning. That shapes how you query it:

- Filter on the partition columns. `type` skips every file of the other command types, and every report here already does that. Once you have enough history that an all-time scan is wasteful, add `AND year = '2026'` (or a range). The partition columns are strings, so quote the value.
- Query `traces`, not `traces_raw`. They scan the same bytes, but only `traces` is typed. `traces_raw` is there so the job can rebuild `traces`.
- If dashboards refresh often, put a native table behind `traces`. See [making it production-grade](external-table/README.md#making-it-production-grade).
- To tell whether a query is read-bound or listing-bound, open *Job information* in the console and compare *Bytes processed* against *Duration*.

## Other options

- Convenience views. If you'd rather point a BI tool at something already scoped by command type than at raw `traces`, define views for it, either in BigQuery or in your BI tool, using the same `type` filter the reports use. See [`views/`](views/).
- A different engine. See the [data layer overview](../#adding-another-engine).
