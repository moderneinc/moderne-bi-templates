-- Commit Activity
--
-- Monthly committed output: successful commits, repos changed, and estimated hours saved.
-- Data source: mod git commit traces (type = 'commit').
--
-- Compatible with: AWS Athena, Trino, PostgreSQL, and other engines supporting DATE_TRUNC.
-- Replace 'month' with 'week', 'quarter', or 'year' to change granularity.
-- Replace <your-tenant> with your tenant name.

SELECT
    DATE_TRUNC('month', CAST(commitStartTime AS TIMESTAMP))    AS month,
    COUNT(*)                                                   AS successful_commits,
    COUNT(DISTINCT path)                                       AS unique_repos_changed,
    ROUND(SUM(runEstimatedEffortTimeSavingsMs) / 3600000.0, 1) AS estimated_hours_saved
FROM (
    SELECT
        commitId,
        MAX(commitStartTime)                 AS commitStartTime,
        MAX(path)                            AS path,
        MAX(runEstimatedEffortTimeSavingsMs) AS runEstimatedEffortTimeSavingsMs
    FROM traces
    WHERE tenant = '<your-tenant>'
      AND type = 'commit'
      AND commitOutcome = 'Succeeded'
    GROUP BY commitId
) commits
GROUP BY DATE_TRUNC('month', CAST(commitStartTime AS TIMESTAMP))
ORDER BY month;
