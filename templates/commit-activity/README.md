# Commit Activity

Tracks committed output over time — the proof that recipes produce real code changes. Shows both the volume of commits and the breadth of repositories affected.

## Data Source

This report uses trace data produced by **`mod git commit`** (or later). Commit-stage traces include run-stage data, allowing correlation between committed output and estimated capacity recovered.

See the [trace.csv data dictionary](../../data-dictionary/trace-csv.md) for the full column reference.

## What This Report Shows

A monthly view of committed recipe changes with three metrics:

| Metric | Description |
|--------|-------------|
| **Successful Commits** | Number of repositories where recipe changes were successfully committed |
| **Unique Repos Changed** | Distinct repositories that received committed changes |
| **Estimated Hours Saved** | Total estimated developer time saved by committed changes |

## Suggested Visualization

Stacked bar chart for successful commits by month with a line overlay for unique repos changed. Estimated hours saved works well as a secondary y-axis or as a separate KPI card.

## Trace.csv Fields Used

| Field | Stage | Purpose |
|-------|-------|---------|
| `commitStartTime` | Commit | Time axis — grouped by month |
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

Run `commit-activity.sql` against your trace data table. The query uses standard SQL compatible with AWS Athena, Trino, PostgreSQL, and most SQL engines that support `DATE_TRUNC`.

Replace `'month'` in the `DATE_TRUNC` calls with `'week'`, `'quarter'`, or `'year'` to change the time granularity.
