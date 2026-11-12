# Commit Activity

This report tracks committed output over time: how many commits landed and how many repositories they touched. It's the evidence that recipes produce real code changes.

## Data Source

This report uses trace data produced by `mod git commit` (or later). Commit-stage traces include run-stage data, which is where the estimated hours saved come from. The query reads `traces` directly, so you can copy the file and run it. It filters on the command `type` it needs. The columns are already typed, so there are no casts.

The [trace.csv reference](https://docs.moderne.io/user-documentation/moderne-cli/references/trace-csv) describes every column.

## What This Report Shows

The report gives a monthly view of committed recipe changes with three metrics:

| Metric | Description |
|--------|-------------|
| **Successful Commits** | Number of repositories where recipe changes were successfully committed |
| **Unique Repos Changed** | Distinct repositories that received committed changes |
| **Estimated Hours Saved** | Total estimated developer time saved by committed changes |

## Suggested Visualization

Try a stacked bar chart for successful commits by month with a line overlay for unique repos changed. Estimated hours saved works well as a secondary y-axis or as a separate KPI card.

![Commit Activity](images/commit-activity.png)

See [commit-activity.ipynb](../../dashboards/jupyter/commit-activity.ipynb) for a ready-to-run Jupyter notebook that produces this visualization from [sample data](commit-activity-sample-data.csv).

## Trace.csv Fields Used

| Field | Stage | Purpose |
|-------|-------|---------|
| `commitId` | Commit | Deduplicate to one row per commit; avoids double-counting re-emitted stages |
| `commitStartTime` | Commit | Time axis, grouped by month |
| `commitOutcome` | Commit | Filter to successful commits |
| `path` | Common | Count distinct for unique repos changed |
| `runEstimatedEffortTimeSavingsMs` | Run | Sum for estimated hours saved |

## Example Output

| month | successful_commits | unique_repos_changed | estimated_hours_saved |
|-------|--------------------|----------------------|----------------------|
| 2026-01-01 | 182 | 156 | 640.5 |
| 2026-02-01 | 224 | 198 | 820.3 |
| 2026-03-01 | 207 | 175 | 710.8 |

## Usage

Run `commit-activity.sql` against your `traces` table. The SQL is written in Trino syntax. For BigQuery, see [querying on BigQuery](../../data-layer/bigquery/README.md#2-query).

The query has no date filter, so it scans every partition. Once you have a lot of history, add `AND year = '2026'` (or a range like `year IN ('2026','2027')`) to narrow the scan. Both engines bill by bytes read. See the performance notes for [Athena](../../data-layer/athena/README.md#performance) and [BigQuery](../../data-layer/bigquery/README.md#performance).

Replace `'month'` in the `DATE_TRUNC` calls with `'week'`, `'quarter'`, or `'year'` to change the time granularity.
