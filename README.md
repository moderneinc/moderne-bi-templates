# Moderne BI Templates

This repo has starter examples for turning Moderne CLI and platform telemetry into reports and dashboards. The repo has three layers: one that gets the data ready for querying, one that queries it, and one that visualizes it. That's the approach we'd suggest, but take whichever pieces fit and change the rest to match your stack or what you need to report on.

## The layers

```
raw trace CSV  ──►  data layer  ──►  `traces` table  ──►  queries  ──►  visualizations
```

If you think in medallion terms, the raw CSV is bronze, the queryable `traces` table is silver, and the reports and dashboards are gold.

| Layer | What it is | Where |
|-------|------------|-------|
| Data layer | Examples that take the raw trace CSV in your object storage and turn it into one wide `traces` table that's ready to query. | [`data-layer/`](data-layer/) |
| Queries | One SQL report per folder. Each reads `traces` directly and comes with its docs and a screenshot. | [`reports/`](reports/) |
| Visualizations | One folder per BI tool, each rendering the same queries. | [`dashboards/`](dashboards/) |

## The `traces` table

Every query and visualization here expects the same logical table, however you produce it:

- It's one wide table called `traces`, the union of every command stage's columns (see the [trace.csv reference](https://docs.moderne.io/user-documentation/moderne-cli/references/trace-csv)).
- It has `tenant`, `source`, `type`, `year`, `month`, and `day` columns, taken from each object's key.
- Rows are keyed by command `type` (`run`, `commit`, `build`, and so on). If a row's type doesn't have a stage, those columns read as `NULL`.
- Columns are typed (timestamps, counts, durations, rates, booleans), so queries need no casts. Timestamps are in UTC.
- `tenant` is a partition column, but your export only has your own tenant, so the reports don't filter on it.
- A data layer can add bookkeeping columns of its own, named with a leading underscore (the Athena example adds `_source_key`). No report reads them.

The reports read `traces` directly. Each report stands alone: copy one file and run it. Every query filters on command `type` itself, so a stage that gets re-emitted can't inflate the totals. If you'd rather point a BI tool at a reusable, pre-scoped surface, you can define convenience views in Athena or BigQuery, or in the BI tool itself.

Build the table with the [data layer](data-layer/), which is what we suggest, or build it some other way and adapt the queries to match. The [telemetry export docs](https://docs.moderne.io/administrator-documentation/moderne-platform/how-to-guides/configuring-telemetry-exports/overview) cover the platform side of the export.

## Available reports

The reports are sorted by the minimum CLI command that produces the data each one needs.

| Report | Description | Minimum CLI command |
|--------|-------------|---------------------|
| [Build Success Trend](reports/build-success-trend/) | Monthly build health: success vs. failure rates over time | `mod build` |
| [Build Tool Distribution](reports/build-tool-distribution/) | Build tool and version distribution across built repositories | `mod build` |
| [Recipe Run Trend](reports/recipe-run-trend/) | Monthly adoption: recipe runs, distinct recipes, and unique users | `mod run` |
| [Top Recipes](reports/top-recipes/) | Most-used recipes by run count, unique users, and repos searched | `mod run` |
| [Dashboard KPIs](reports/dashboard-kpis/) | Executive snapshot: all-time totals and a monthly trend | `mod git commit` |
| [Commit Trend](reports/commit-trend/) | Monthly trend correlating recipe execution with committed code impact | `mod git commit` |
| [Commit Activity](reports/commit-activity/) | Monthly committed output: successful commits, repos changed, hours saved | `mod git commit` |
| [Top Users](reports/top-users/) | User engagement ranking by recipe runs and commits | `mod git commit` |
| [Top Recipes with Commits](reports/top-recipes-with-commits/) | Recipes that produce real committed code changes | `mod git commit` |
| [Security Recipe Run Trend](reports/security-recipe-run-trend/) | Monthly security remediation trend: committed fixes, repos, hours | `mod git commit` |

## Getting started

If you just want to see a chart, every notebook runs on bundled sample data, so you don't need any cloud access:

```bash
pip install pandas matplotlib jupyter
jupyter notebook            # open anything under dashboards/jupyter/
```

If you're wiring up your own telemetry:

1. Configure telemetry export so the trace CSV lands in a bucket you own. The [telemetry export docs](https://docs.moderne.io/administrator-documentation/moderne-platform/how-to-guides/configuring-telemetry-exports/overview) cover how.
2. Build the `traces` table with the [data layer](data-layer/). There are Athena and BigQuery walkthroughs.
3. Pick a report under [`reports/`](reports/) and run it. The SQL is self-contained.
4. Render it in a [notebook](dashboards/jupyter/), or wire it into your BI tool. The [dashboards overview](dashboards/) explains how each tool reads the same table.

## Repository structure

```
moderne-bi-templates/
├── data-layer/                   # optimize the raw CSV for querying
│   ├── README.md                 # the `traces` contract, shared by every engine
│   ├── athena/
│   │   ├── glue/                 # nightly Glue job that builds the typed Iceberg `traces` table (example)
│   │   └── views/                # optional convenience views (no report depends on them)
│   └── bigquery/
│       ├── external-table/       # nightly job that builds a typed `traces` view over Cloud Storage (example)
│       └── views/                # optional convenience views (no report depends on them)
├── reports/                    # one self-contained report per folder
│   └── <report>/
│       ├── <report>.sql          # the query
│       ├── <report>-sample-data.csv  # example output (feeds the notebook + docs)
│       ├── README.md
│       └── images/               # chart screenshot
└── dashboards/                   # the visualization layer (one folder per BI tool)
    ├── jupyter/                  # one notebook per report (reads each report's sample CSV)
    ├── quicksight/               # QuickSight asset bundle
    ├── tableau/                  # Tableau workbooks
    └── powerbi/                  # Power BI reports
```
