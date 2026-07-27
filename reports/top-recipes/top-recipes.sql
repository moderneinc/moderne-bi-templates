-- Top Recipes
--
-- Most-used recipes ranked by run count, unique users, and repos searched.
--
-- Reads the wide `traces` table directly, scoped to type='run' (one row per run). Timestamp
-- and numeric columns are typed, so no casts are needed. Single-tenant export, so no tenant
-- filter. Optional convenience views: data-layer/athena/views. Add `AND year = '2026'` to
-- bound the scan.

SELECT
    runrecipeid                AS recipe_id,
    max(runrecipeinstancename) AS recipe_name,
    count(DISTINCT runid)      AS recipe_runs,
    count(DISTINCT developer)  AS unique_users,
    count(DISTINCT path)       AS repos_searched
FROM traces
WHERE type = 'run'
  AND runstarttime IS NOT NULL
  AND runrecipeid <> ''
GROUP BY runrecipeid
ORDER BY recipe_runs DESC;
