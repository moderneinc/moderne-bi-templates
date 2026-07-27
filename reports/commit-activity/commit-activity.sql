-- Commit Activity
--
-- Monthly committed output: successful commits, repos changed, and estimated hours saved.
--
-- Reads the wide `traces` table directly, scoped to type='commit'. Each commit trace embeds
-- the recipe run that produced it, and scoping to type='commit' yields one row per commit,
-- so COUNT(*) of succeeded commits is exact (no stage re-emission to de-duplicate). Timestamp
-- and numeric columns are typed, so no casts are needed. Single-tenant export, so no tenant
-- filter. Optional convenience views: data-layer/athena/views.
-- Tune it: replace 'month' with 'week'/'quarter'/'year'; add `AND year = '2026'` to bound the scan.

SELECT
    date_trunc('month', commitstarttime)                AS month,
    count(*)                                            AS successful_commits,
    count(DISTINCT path)                                AS unique_repos_changed,
    round(sum(runestimatedefforttimesavingsms) / 3600000.0, 1) AS estimated_hours_saved
FROM traces
WHERE type = 'commit'
  AND commitstarttime IS NOT NULL
  AND commitoutcome = 'Succeeded'
GROUP BY date_trunc('month', commitstarttime)
ORDER BY month;
