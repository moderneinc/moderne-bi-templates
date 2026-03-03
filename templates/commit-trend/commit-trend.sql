-- Commit Trend
--
-- Monthly trend correlating recipe execution with committed code impact.
-- Data source: mod git commit trace, or any later-stage trace.
--
-- Compatible with: AWS Athena, Trino, PostgreSQL, and other engines supporting DATE_TRUNC.
-- Replace 'month' with 'week', 'quarter', or 'year' to change granularity.

SELECT
    DATE_TRUNC('month', CAST(commitStartTime AS TIMESTAMP))                AS month,
    COUNT(DISTINCT commitId)                                               AS commit_jobs,
    COUNT(DISTINCT runId)                                                  AS recipe_runs,
    COUNT(DISTINCT developer)                                              AS unique_users,
    COUNT(DISTINCT runRecipeId)                                            AS unique_recipes,
    COUNT(DISTINCT path)                                                   AS repos_with_commits,
    COUNT(DISTINCT CASE WHEN commitOutcome = 'Succeeded' THEN commitId END) AS successful_commits,
    ROUND(SUM(runEstimatedEffortTimeSavingsMs) / 3600000.0, 1)             AS estimated_hours_saved
FROM trace
WHERE commitOutcome IS NOT NULL
GROUP BY DATE_TRUNC('month', CAST(commitStartTime AS TIMESTAMP))
ORDER BY month;
