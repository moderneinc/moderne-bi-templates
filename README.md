# Moderne BI Templates

Starter examples for turning Moderne CLI and platform telemetry into reports and dashboards. The repo is organized as three layers: **optimize the data for querying**, **query it**, and **visualize it**. These reflect the suggested approach, but adopt whichever pieces fit and adapt them where your stack or reporting needs differ.

## The layers

```
raw trace CSV  ──►  data layer  ──►  `traces` table  ──►  queries  ──►  visualizations
```

The three layers map to the familiar medallion pattern — raw CSV (**bronze**) → the queryable `traces` table (**silver**) → reports and dashboards (**gold**).

| Layer | What it is | Where |
|-------|------------|-------|
| **Data layer** | Examples that take the raw trace CSV in your object storage and optimize it for querying, landing one wide `traces` table. | [`data-layer/`](data-layer/) |
| **Queries** | One SQL report per folder, reading the wide `traces` table directly, plus its docs and a screenshot. | [`reports/`](reports/) |
| **Visualizations** | The presentation layer, with one folder per BI tool as sibling ways to render the same queries. | [`dashboards/`](dashboards/) |

## The `traces` table

Every query and visualization here expects the same logical table, however you produce it:

- One wide table, **`traces`**, the union of every command stage's columns (see the [trace.csv reference](https://docs.moderne.io/user-documentation/moderne-cli/references/trace-csv)).
- Carries `tenant`, `source`, `type`, `year`, `month`, `day` columns, taken from each object's key.
- Keyed by command **`type`** (`run`, `commit`, `build`, …); a row whose type lacks a stage reads those columns as `NULL`.
- Columns are **typed** (timestamps, counts, durations, rates, booleans), so queries need no casts. Timestamps are in UTC.
- `tenant` is a partition column, but your export contains only your own tenant, so the reports don't filter on it.
- A data layer may add bookkeeping columns of its own, named with a leading underscore (the Athena example adds `_source_key`). No report reads them.

The reports read `traces` **directly**. Each query carries its own command-`type` scoping (so stage re-emission can't inflate totals), which keeps every report self-contained — copy one file and run it. If you'd rather point a BI tool at a reusable, pre-scoped surface, you can optionally define convenience views in Athena or natively in your BI tool.

Produce this table with the [data layer](data-layer/), which is the path we suggest, or produce it another way and adapt the queries to match. See the [telemetry export docs](https://docs.moderne.io/administrator-documentation/moderne-platform/how-to-guides/configuring-telemetry-exports/overview) for the platform-side export configuration.

## Available reports

Sorted by the minimum CLI command that produces the data each report needs.

| Report | Description | Minimum CLI command |
|--------|-------------|---------------------|
| [Build Success Trend](reports/build-success-trend/) | Monthly build health — success vs. failure rates over time | `mod build` |
| [Build Tool Distribution](reports/build-tool-distribution/) | Build tool and version distribution across built repositories | `mod build` |
| [Recipe Run Trend](reports/recipe-run-trend/) | Monthly adoption — recipe runs, distinct recipes, and unique users | `mod run` |
| [Top Recipes](reports/top-recipes/) | Most-used recipes by run count, unique users, and repos searched | `mod run` |
| [Dashboard KPIs](reports/dashboard-kpis/) | Executive snapshot — all-time totals and monthly trend | `mod git commit` |
| [Commit Trend](reports/commit-trend/) | Monthly trend correlating recipe execution with committed code impact | `mod git commit` |
| [Commit Activity](reports/commit-activity/) | Monthly committed output — successful commits, repos changed, hours saved | `mod git commit` |
| [Top Users](reports/top-users/) | User engagement ranking by recipe runs and commits | `mod git commit` |
| [Top Recipes with Commits](reports/top-recipes-with-commits/) | Recipes that produce real committed code changes | `mod git commit` |
| [Security Recipe Run Trend](reports/security-recipe-run-trend/) | Monthly security remediation trend — committed fixes, repos, hours | `mod git commit` |

## Getting started

**Just want to see a chart?** Every notebook runs on bundled sample data — no cloud access needed:

```bash
pip install pandas matplotlib jupyter
jupyter notebook            # open anything under dashboards/jupyter/
```

**Wiring up your own telemetry?**

1. Configure telemetry export so trace CSV lands in a bucket you own — see the [telemetry export docs](https://docs.moderne.io/administrator-documentation/moderne-platform/how-to-guides/configuring-telemetry-exports/overview).
2. Stand up the `traces` table with the [data layer](data-layer/) (Athena walkthrough included).
3. Pick a report under [`reports/`](reports/) and run it — the SQL is self-contained.
4. Render it with a [notebook](dashboards/jupyter/), or wire it into the BI tool of your choice. See the [dashboards overview](dashboards/) for how each tool reads the same table.

## Repository structure

```
moderne-bi-templates/
├── data-layer/                   # optimize the raw CSV for querying
│   ├── README.md                 # the `traces` contract, shared by every engine
│   └── athena/
│       ├── glue/                 # nightly Glue job: raw CSV → typed Iceberg `traces` (example)
│       └── views/                # optional convenience views (no report depends on them)
├── reports/                    # one self-contained report per folder
│   └── <report>/
│       ├── <report>.sql          # the query
│       ├── <report>-sample-data.csv  # example output (feeds the notebook + docs)
│       ├── README.md
│       └── images/               # chart screenshot
└── dashboards/                   # the visualization layer (one folder per BI tool)
    ├── jupyter/                  # one notebook per report (reads each report's sample CSV)
    ├── quicksight/               # QuickSight analyses over `traces`
    ├── tableau/                  # Tableau workbooks over `traces`
    └── powerbi/                  # Power BI reports over `traces`
```
