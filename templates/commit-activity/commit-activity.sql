-- Commit Activity
--
-- Monthly committed output: successful commits, repos changed, and estimated hours saved.
-- Data source: mod git commit trace, or any later-stage trace.
--
-- Compatible with: AWS Athena, Trino, PostgreSQL, and other engines supporting DATE_TRUNC.
-- Replace 'month' with 'week', 'quarter', or 'year' to change granularity.
--
-- A commit's stage data is re-emitted by every later command (e.g. mod git push
-- carries the commit stage too), so the same commitId can appear in more than one
-- trace row. The inner query collapses to one row per commitId first, so the counts
-- and sums below are not inflated when both commit and push traces are loaded.

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
    FROM trace
    WHERE commitOutcome = 'Succeeded'
    GROUP BY commitId
) commits
GROUP BY DATE_TRUNC('month', CAST(commitStartTime AS TIMESTAMP))
ORDER BY month;
