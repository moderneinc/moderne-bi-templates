-- Recipe Run Trend
--
-- Monthly adoption trend: recipe runs, distinct recipes, and unique users over time.
-- Data source: mod run trace, or any later-stage trace.
--
-- Compatible with: AWS Athena, Trino, PostgreSQL, and other engines supporting DATE_TRUNC.
-- Replace 'month' with 'week', 'quarter', or 'year' to change granularity.

SELECT
    DATE_TRUNC('month', CAST(runStartTime AS TIMESTAMP)) AS month,
    COUNT(DISTINCT runId)       AS recipe_runs,
    COUNT(DISTINCT runRecipeId) AS distinct_recipes,
    COUNT(DISTINCT developer)   AS unique_users
FROM trace
WHERE runOutcome IS NOT NULL
GROUP BY DATE_TRUNC('month', CAST(runStartTime AS TIMESTAMP))
ORDER BY month;
