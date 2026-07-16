-- Top Users
--
-- User engagement ranking by recipe runs and commits.
-- Data source: mod git commit trace, or any later-stage trace.
-- If only mod run traces are available, recipe runs will be accurate but commits will be zero.
--
-- Compatible with: AWS Athena, Trino, PostgreSQL, and other standard SQL engines.
-- Replace <your-tenant> with your tenant name.

SELECT
    developer,
    COUNT(DISTINCT runId)                                              AS recipe_runs,
    COUNT(DISTINCT CASE WHEN commitOutcome = 'Succeeded' THEN commitId END) AS commits
FROM traces
WHERE tenant = '<your-tenant>'
  AND runOutcome IS NOT NULL
GROUP BY developer
ORDER BY recipe_runs DESC;
