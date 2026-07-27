# Data layer: optimizing the data for querying

The raw trace CSV that lands in your object storage isn't shaped for reporting: it is all-string, uncompressed, and split into a different set of columns per command type. This layer turns it into one wide, typed `traces` table that the [reports](../reports) and [dashboards](../dashboards) read.

Each subdirectory is one engine's way of producing that table. AWS Athena is worked through end to end; the same layout applies to any engine that reads Hive-partitioned data from object storage.

| Engine | Where |
|--------|-------|
| **AWS Athena** | [`athena/`](athena/) |

## What the reports expect

Every report expects the same logical table, regardless of how you produce it:

- One wide table, `traces`, the **union of every command stage's columns** (see the [trace.csv reference](https://docs.moderne.io/user-documentation/moderne-cli/references/trace-csv)).
- Partitioned by `tenant`, `source`, `type`, `year`, `month`, `day` (Hive-style keys, exactly as the CLI and platform write them to object storage).
- Keyed by command **`type`** (`run`, `commit`, `build`, and so on). A row whose type lacks a stage reads those columns as `NULL`.
- Columns are **typed** (timestamps, counts, durations, rates, booleans), so queries need no casts.
- `tenant` is a partition column, but your export contains only your own tenant, so the reports don't filter on it.

As long as your data layer produces that, the queries and visualizations in this repo are interchangeable across engines. If you produce something different, adapt the queries to match.

## How telemetry lands

Trace CSV replicates into a bucket you own with this key layout (see the [telemetry export docs](https://docs.moderne.io/administrator-documentation/moderne-platform/how-to-guides/configuring-telemetry-exports/overview)):

```
tenant=<your-tenant>/source={saas|cli}/type=<command>/year=YYYY/month=MM/day=DD/<command-id>.csv
```

Because each command **type** writes a different CSV width and column order, one positional table cannot parse them all. So the layer is built in stages: a table per command type over the raw CSV, a compaction step that writes typed Parquet, and the wide `traces` table over that output.

```
raw CSV (per-type)  ──►  ingest tables  ──►  compaction  ──►  traces  ──►  reports
```

Compaction is optional but recommended. You can point reports at the raw CSV tables instead and skip it entirely, trading query speed and cost for less to run. See [`athena/`](athena/) for both paths.

## Adding another engine

Add a `data-layer/<engine>/` folder that produces the same `traces` table. Nothing above is Athena-specific: Snowflake, BigQuery, Databricks, Fabric, and DuckDB all read this partition layout directly.
