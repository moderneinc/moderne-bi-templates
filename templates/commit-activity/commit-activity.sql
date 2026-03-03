-- Commit Activity
--
-- Monthly committed output: successful commits, repos changed, and estimated hours saved.
-- Data source: mod git commit trace, or any later-stage trace.
--
-- Compatible with: AWS Athena, Trino, PostgreSQL, and other engines supporting DATE_TRUNC.
-- Replace 'month' with 'week', 'quarter', or 'year' to change granularity.

SELECT
    DATE_TRUNC('month', CAST(commitStartTime AS TIMESTAMP))    AS month,
    COUNT(*)                                                   AS successful_commits,
    COUNT(DISTINCT path)                                       AS unique_repos_changed,
    ROUND(SUM(runEstimatedEffortTimeSavingsMs) / 3600000.0, 1) AS estimated_hours_saved
FROM trace
WHERE commitOutcome = 'Succeeded'
GROUP BY DATE_TRUNC('month', CAST(commitStartTime AS TIMESTAMP))
ORDER BY month;
