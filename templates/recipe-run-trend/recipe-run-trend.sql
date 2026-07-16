-- Recipe Run Trend
--
-- Monthly adoption trend: recipe runs, distinct recipes, and unique users over time.
-- Data source: mod run traces (type = 'run').
--
-- Compatible with: AWS Athena, Trino, PostgreSQL, and other engines supporting DATE_TRUNC.
-- Replace 'month' with 'week', 'quarter', or 'year' to change granularity.
-- Replace <your-tenant> with your tenant name.

SELECT
    DATE_TRUNC('month', CAST(runStartTime AS TIMESTAMP)) AS month,
    COUNT(DISTINCT runId)       AS recipe_runs,
    COUNT(DISTINCT runRecipeId) AS distinct_recipes,
    COUNT(DISTINCT developer)   AS unique_users
FROM traces
WHERE tenant = '<your-tenant>'
  AND type = 'run'
  AND runOutcome IS NOT NULL
GROUP BY DATE_TRUNC('month', CAST(runStartTime AS TIMESTAMP))
ORDER BY month;
