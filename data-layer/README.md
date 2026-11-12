# Data layer: optimizing the data for querying

The raw trace CSV that lands in your object storage isn't shaped for reporting. It's all strings, it's uncompressed, and each command type has its own set of columns. This layer turns it into one wide, typed `traces` table that the [reports](../reports) and [dashboards](../dashboards) read.

Each subdirectory is one engine's way of producing that table. AWS Athena and Google BigQuery are worked through end to end, and the same layout applies to any engine that reads Hive-partitioned data from object storage.

| Engine | Where |
|--------|-------|
| AWS Athena | [`athena/`](athena/) |
| Google BigQuery | [`bigquery/`](bigquery/) |

## What the reports expect

Every report expects the same logical table, however you produce it:

- It's one wide table called `traces`, the union of every command stage's columns (see the [trace.csv reference](https://docs.moderne.io/user-documentation/moderne-cli/references/trace-csv)).
- It has `tenant`, `source`, `type`, `year`, `month`, and `day` columns, taken from the Hive-style keys the CLI and platform write to object storage. Filtering on them lets the engine skip data.
- Rows are keyed by command `type` (`run`, `commit`, `build`, and so on). If a row's type doesn't have a stage, those columns read as `NULL`.
- Columns are typed (timestamps, counts, durations, rates, booleans), so queries need no casts. Timestamps are in UTC.
- `tenant` is a partition column, but your export only has your own tenant, so the reports don't filter on it.
- A data layer can add bookkeeping columns of its own, named with a leading underscore. The Athena example adds `_source_key`, the object each row came from. They aren't trace fields, no report reads them, and another engine's data layer doesn't need to produce them.

As long as your data layer produces that, the queries and visualizations in this repo work across engines. If you produce something different, adapt the queries to match.

## How telemetry lands

Trace CSV replicates into a bucket you own with this key layout (see the [telemetry export docs](https://docs.moderne.io/administrator-documentation/moderne-platform/how-to-guides/configuring-telemetry-exports/overview)):

```
tenant=<your-tenant>/source={saas|cli}/type=<command>/year=YYYY/month=MM/day=DD/<command-id>.csv
```

Each command type writes a different set of columns, and new trace fields show up over time. So the layer reads each CSV object by its own header, keeps every raw row, and builds the wide, typed `traces` table from that:

```
raw CSV  ──►  traces_raw (every row, as strings)  ──►  traces (typed)  ──►  reports
```

Two things about how objects arrive shape any data layer:

- An object can be delivered more than once. Its rows need to replace the earlier copy's, not add to them.
- A replica can land late. Replication keeps the source's last-modified time, so a late arrival can look older than objects you've already read. Anything that decides what's new by modification time alone will miss it.

[`athena/`](athena/) has a nightly AWS Glue job that handles both, and [`bigquery/`](bigquery/) has a nightly job over Cloud Storage that does the same.

## Adding another engine

Add a `data-layer/<engine>/` folder that produces the same `traces` table. Nothing above is specific to Athena or BigQuery. Snowflake, Databricks, Fabric, and DuckDB all read this partition layout directly.
