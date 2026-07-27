-- Commit Trend
--
-- Monthly trend correlating recipe execution with committed code impact.
--
-- Reads the wide `traces` table directly, scoped to type='commit' (one row per commit, so
-- stage re-emission does not inflate totals). Each commit trace embeds the run that produced
-- it. Timestamp and numeric columns are typed, so no casts are needed. Single-tenant export,
-- so no tenant filter. Optional convenience views: data-layer/athena/views.
-- Tune it: replace 'month' with 'week'/'quarter'/'year'; add `AND year = '2026'` to bound the scan.

SELECT
    date_trunc('month', commitstarttime)                                    AS month,
    count(DISTINCT commitid)                                                AS commit_jobs,
    count(DISTINCT runid)                                                   AS recipe_runs,
    count(DISTINCT developer)                                               AS unique_users,
    count(DISTINCT runrecipeid)                                             AS unique_recipes,
    count(DISTINCT path)                                                    AS repos_with_commits,
    count(DISTINCT CASE WHEN commitoutcome = 'Succeeded' THEN commitid END) AS successful_commits,
    round(sum(runestimatedefforttimesavingsms) / 3600000.0, 1)             AS estimated_hours_saved
FROM traces
WHERE type = 'commit'
  AND commitstarttime IS NOT NULL
GROUP BY date_trunc('month', commitstarttime)
ORDER BY month;
