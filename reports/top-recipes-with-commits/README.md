# Top Recipes with Commits

This report lists the recipes that ended up as committed code changes. It separates the recipes people tried from the ones that landed in real codebases.

## Data Source

This report uses trace data produced by `mod git commit` (or later). Commit-stage traces include both run and commit data, so each commit can be tied back to its recipe. The query reads `traces` directly, so you can copy the file and run it. It filters on the command `type` it needs. The columns are already typed, so there are no casts.

The [trace.csv reference](https://docs.moderne.io/user-documentation/moderne-cli/references/trace-csv) describes every column.

## What This Report Shows

The report gives a ranked list of recipes filtered to only those with successful commits:

| Metric | Description |
|--------|-------------|
| **Commits** | Number of repositories where recipe changes were successfully committed |
| **Unique Users** | Number of distinct users who committed changes from this recipe |
| **Estimated Hours Saved** | Total estimated developer time saved by committed changes |

## Suggested Visualization

Try a horizontal bar chart sorted by commit count. Pair with the [Top Recipes](../top-recipes/) template to compare total runs vs. committed results; the gap shows you which recipes people explore but don't apply.

![Top Recipes with Commits](images/top-recipes-with-commits.png)

See [top-recipes-with-commits.ipynb](../../dashboards/jupyter/top-recipes-with-commits.ipynb) for a ready-to-run Jupyter notebook that produces this visualization from [sample data](top-recipes-with-commits-sample-data.csv).

## Trace.csv Fields Used

| Field | Stage | Purpose |
|-------|-------|---------|
| `runRecipeId` | Run | Recipe identifier, the grouping key |
| `runRecipeInstanceName` | Run | Human-readable recipe name |
| `commitOutcome` | Commit | Filter to successful commits |
| `commitId` | Commit | Count distinct for total commits |
| `developer` | Common | Count distinct for unique users |
| `runEstimatedEffortTimeSavingsMs` | Run | Sum for estimated hours saved |

## Example Output

| recipe_id | recipe_name | commits | unique_users | estimated_hours_saved |
|-----------|-------------|---------|--------------|----------------------|
| org.openrewrite.java.migrate.UpgradeToJava17 | Migrate to Java 17 | 482 | 31 | 1240.5 |
| org.openrewrite.staticanalysis.CommonStaticAnalysis | Common static analysis | 318 | 28 | 890.2 |
| org.openrewrite.java.OrderImports | Order imports | 215 | 19 | 420.0 |

## Usage

Run `top-recipes-with-commits.sql` against your `traces` table. The SQL is written in Trino syntax. For BigQuery, see [querying on BigQuery](../../data-layer/bigquery/README.md#2-query).

The query has no date filter, so it scans every partition. Once you have a lot of history, add `AND year = '2026'` (or a range like `year IN ('2026','2027')`) to narrow the scan. Both engines bill by bytes read. See the performance notes for [Athena](../../data-layer/athena/README.md#performance) and [BigQuery](../../data-layer/bigquery/README.md#performance).

Results are sorted by commits descending. Add a `LIMIT` clause to show only the top N recipes (e.g., `LIMIT 20`).
