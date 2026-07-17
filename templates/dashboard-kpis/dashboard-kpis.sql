-- Dashboard KPIs
--
-- Executive-level snapshot: all-time summary and monthly trend.
-- Data source: mod git commit trace for full metrics, or mod run trace for run-only metrics.
--
-- Compatible with: AWS Athena, Trino, PostgreSQL, and other standard SQL engines.
--
-- Run-stage columns are re-emitted by every later-stage trace (apply, add, commit), so a
-- single run can appear on several rows. Both queries below first collapse to one row per
-- (runId, path) -- one repository's participation in one run -- before summing, so the
-- totals are not inflated. Counts of commits still work because the inner query keeps the
-- commit columns, which only later-stage traces carry.

-- Query 1: Summary KPIs (single row, all-time totals)

SELECT
    COUNT(DISTINCT runId)                                      AS total_recipe_runs,
    COUNT(DISTINCT committedCommitId)                          AS total_commits,
    COUNT(DISTINCT developer)                                  AS unique_users,
    COUNT(DISTINCT runRecipeId)                                AS unique_recipes,
    SUM(runFilesWithFixResults)                                AS files_changed,
    ROUND(SUM(runEstimatedEffortTimeSavingsMs) / 3600000.0, 1) AS estimated_hours_saved
FROM (
    SELECT
        runId,
        path,
        MAX(developer)                       AS developer,
        MAX(runRecipeId)                     AS runRecipeId,
        MAX(runFilesWithFixResults)          AS runFilesWithFixResults,
        MAX(runEstimatedEffortTimeSavingsMs) AS runEstimatedEffortTimeSavingsMs,
        MAX(CASE WHEN commitOutcome = 'Succeeded' THEN commitId END) AS committedCommitId
    FROM traces
    WHERE runOutcome IS NOT NULL
    GROUP BY runId, path
) runs;

-- Query 2: Monthly Trend
-- Replace 'month' with 'week', 'quarter', or 'year' to change granularity.

SELECT
    DATE_TRUNC('month', CAST(runStartTime AS TIMESTAMP))       AS month,
    COUNT(DISTINCT runId)                                      AS recipe_runs,
    COUNT(DISTINCT committedCommitId)                          AS commits,
    COUNT(DISTINCT developer)                                  AS unique_users,
    COUNT(DISTINCT runRecipeId)                                AS unique_recipes,
    SUM(runFilesWithFixResults)                                AS files_changed,
    ROUND(SUM(runEstimatedEffortTimeSavingsMs) / 3600000.0, 1) AS estimated_hours_saved
FROM (
    SELECT
        runId,
        path,
        MAX(runStartTime)                    AS runStartTime,
        MAX(developer)                       AS developer,
        MAX(runRecipeId)                     AS runRecipeId,
        MAX(runFilesWithFixResults)          AS runFilesWithFixResults,
        MAX(runEstimatedEffortTimeSavingsMs) AS runEstimatedEffortTimeSavingsMs,
        MAX(CASE WHEN commitOutcome = 'Succeeded' THEN commitId END) AS committedCommitId
    FROM traces
    WHERE runOutcome IS NOT NULL
    GROUP BY runId, path
) runs
GROUP BY DATE_TRUNC('month', CAST(runStartTime AS TIMESTAMP))
ORDER BY month;
