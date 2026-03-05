-- Build Success Trend
--
-- Monthly build health: total builds, successes, failures, success rate, and repos built.
-- Data source: mod build trace, or any later-stage trace.
--
-- Compatible with: AWS Athena, Trino, PostgreSQL, and other engines supporting DATE_TRUNC.
-- Replace 'month' with 'week', 'quarter', or 'year' to change granularity.

SELECT
    DATE_TRUNC('month', CAST(buildStartTime AS TIMESTAMP))                                      AS month,
    COUNT(DISTINCT buildId)                                                                     AS total_builds,
    COUNT(DISTINCT CASE WHEN buildOutcome = 'Succeeded' THEN buildId END)                       AS successful_builds,
    COUNT(DISTINCT CASE WHEN buildOutcome != 'Succeeded' THEN buildId END)                      AS failed_builds,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN buildOutcome = 'Succeeded' THEN buildId END)
        / COUNT(DISTINCT buildId), 1)                                                           AS success_rate_pct,
    COUNT(DISTINCT path)                                                                        AS unique_repos
FROM trace
WHERE buildOutcome IS NOT NULL
GROUP BY DATE_TRUNC('month', CAST(buildStartTime AS TIMESTAMP))
ORDER BY month;
