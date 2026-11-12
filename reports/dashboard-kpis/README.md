# Dashboard KPIs

This report gives executives a snapshot of Moderne adoption: a handful of headline numbers, plus the monthly trend behind them.

## Data Source

This template includes two queries:

- The summary KPIs use trace data from `mod git commit` (or later) for the fullest picture. With only `mod run` traces you still get the run-only metrics.
- The monthly trend uses trace data from `mod git commit` (or later).

The query reads `traces` directly. Run metrics come from `type = 'run'` rows and commit metrics come from `type = 'commit'` rows. The query counts them separately and joins the results, so a re-emitted stage can't inflate the totals. The columns are already typed, so there are no casts.

The [trace.csv reference](https://docs.moderne.io/user-documentation/moderne-cli/references/trace-csv) describes every column.

## What This Report Shows

### Summary KPIs (single numbers)

| KPI | Description |
|-----|-------------|
| **Total Recipe Runs** | Total recipe executions across all users and repos |
| **Total Commits** | Successful commit operations |
| **Unique Users** | Distinct users who ran recipes |
| **Unique Recipes** | Distinct recipes used |
| **Files Changed** | Total files with fix results from recipe runs |
| **Estimated Hours Saved** | Total estimated developer time saved |

### Monthly Trend

The same metrics broken down by month to show adoption trajectory.

## Suggested Visualization

Put KPI cards (large single numbers) across the top of a dashboard, with a multi-series area or bar chart below showing the monthly trend. This layout makes a good landing page.

![Dashboard KPIs Summary](images/dashboard-kpis-summary.png)

![Dashboard KPIs Trend](images/dashboard-kpis-trend.png)

See [dashboard-kpis.ipynb](../../dashboards/jupyter/dashboard-kpis.ipynb) for a ready-to-run Jupyter notebook that produces these visualizations from sample data ([summary](dashboard-kpis-summary-sample-data.csv), [trend](dashboard-kpis-trend-sample-data.csv)).

## Trace.csv Fields Used

| Field | Stage | Purpose |
|-------|-------|---------|
| `runId` | Run | Count distinct for total recipe runs |
| `runRecipeId` | Run | Count distinct for unique recipes |
| `runOutcome` | Run | Filter to rows that reached the run stage |
| `runStartTime` | Run | Time axis for monthly trend |
| `runFilesWithFixResults` | Run | Sum for files changed |
| `runEstimatedEffortTimeSavingsMs` | Run | Sum for estimated hours saved |
| `commitOutcome` | Commit | Filter and count successful commits |
| `developer` | Common | Count distinct for unique users |

## Example Output: Summary KPIs

| total_recipe_runs | total_commits | unique_users | unique_recipes | files_changed | estimated_hours_saved |
|-------------------|---------------|--------------|----------------|---------------|-----------------------|
| 1785 | 1924 | 24 | 375 | 105420 | 6920.0 |

## Example Output: Monthly Trend

| month | recipe_runs | commits | unique_users | unique_recipes | files_changed | estimated_hours_saved |
|-------|-------------|---------|--------------|----------------|---------------|-----------------------|
| 2026-01-01 | 342 | 182 | 18 | 47 | 18200 | 1240.5 |
| 2026-02-01 | 415 | 224 | 23 | 52 | 22400 | 1580.3 |
| 2026-03-01 | 389 | 207 | 21 | 49 | 19800 | 1410.8 |

## Usage

Run `dashboard-kpis.sql` against your `traces` table. The file contains two queries:

1. Summary KPIs returns a single row with all-time totals.
2. Monthly Trend returns one row per month with the same metrics.

The SQL is written in Trino syntax. For BigQuery, see [querying on BigQuery](../../data-layer/bigquery/README.md#2-query).

The queries have no date filter, so they scan every partition. Once you have a lot of history, add `AND year = '2026'` (or a range like `year IN ('2026','2027')`) to narrow the scan. Both engines bill by bytes read. See the performance notes for [Athena](../../data-layer/athena/README.md#performance) and [BigQuery](../../data-layer/bigquery/README.md#performance).

Replace `'month'` in the trend query's `DATE_TRUNC` calls with `'week'`, `'quarter'`, or `'year'` to change the time granularity.
