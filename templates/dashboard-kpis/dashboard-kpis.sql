-- Dashboard KPIs
--
-- Executive-level snapshot: all-time summary and monthly trend.
-- Data source: mod git commit trace for full metrics, or mod run trace for run-only metrics.
--
-- Compatible with: AWS Athena, Trino, PostgreSQL, and other standard SQL engines.

-- Query 1: Summary KPIs (single row, all-time totals)

SELECT
    COUNT(DISTINCT runId)                                                          AS total_recipe_runs,
    COUNT(DISTINCT CASE WHEN commitOutcome = 'Succeeded' THEN commitId END)        AS total_commits,
    COUNT(DISTINCT developer)                                                      AS unique_users,
    COUNT(DISTINCT runRecipeId)                                                    AS unique_recipes,
    SUM(runFilesWithFixResults)                                                    AS files_changed,
    ROUND(SUM(runEstimatedEffortTimeSavingsMs) / 3600000.0, 1)                     AS estimated_hours_saved
FROM trace
WHERE runOutcome IS NOT NULL;

-- Query 2: Monthly Trend
-- Replace 'month' with 'week', 'quarter', or 'year' to change granularity.

SELECT
    DATE_TRUNC('month', CAST(runStartTime AS TIMESTAMP))                           AS month,
    COUNT(DISTINCT runId)                                                          AS recipe_runs,
    COUNT(DISTINCT CASE WHEN commitOutcome = 'Succeeded' THEN commitId END)        AS commits,
    COUNT(DISTINCT developer)                                                      AS unique_users,
    COUNT(DISTINCT runRecipeId)                                                    AS unique_recipes,
    SUM(runFilesWithFixResults)                                                    AS files_changed,
    ROUND(SUM(runEstimatedEffortTimeSavingsMs) / 3600000.0, 1)                     AS estimated_hours_saved
FROM trace
WHERE runOutcome IS NOT NULL
GROUP BY DATE_TRUNC('month', CAST(runStartTime AS TIMESTAMP))
ORDER BY month;
