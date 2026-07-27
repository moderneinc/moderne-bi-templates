-- Top Recipes with Commits
--
-- Recipes ranked by committed code changes — which recipes deliver real, committed results.
--
-- Reads the wide `traces` table directly, scoped to type='commit'. The recipe that drove
-- each commit is runrecipeid on the commit trace; one row per commit, so counts are not
-- inflated by stage re-emission. Timestamp and numeric columns are typed, so no casts are
-- needed. Single-tenant export, so no tenant filter. Optional convenience views:
-- data-layer/athena/views. Add `AND year = '2026'` to bound the scan.

SELECT
    runrecipeid                                                AS recipe_id,
    max(runrecipeinstancename)                                 AS recipe_name,
    count(DISTINCT commitid)                                   AS commits,
    count(DISTINCT developer)                                  AS unique_users,
    round(sum(runestimatedefforttimesavingsms) / 3600000.0, 1) AS estimated_hours_saved
FROM traces
WHERE type = 'commit'
  AND commitstarttime IS NOT NULL
  AND commitoutcome = 'Succeeded'
  AND runrecipeid <> ''
GROUP BY runrecipeid
ORDER BY commits DESC;
