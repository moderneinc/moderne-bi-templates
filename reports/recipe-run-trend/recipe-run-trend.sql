-- Recipe Run Trend
--
-- Monthly adoption trend: recipe runs, distinct recipes, and unique users over time.
--
-- Reads the wide `traces` table directly, scoped to type='run' (one row per run). Timestamp
-- and numeric columns are typed, so no casts are needed. Single-tenant export, so no tenant
-- filter. Optional convenience views: data-layer/athena/views.
-- Tune it: replace 'month' with 'week'/'quarter'/'year'; add `AND year = '2026'` to bound the scan.

SELECT
    date_trunc('month', runstarttime) AS month,
    count(DISTINCT runid)             AS recipe_runs,
    count(DISTINCT runrecipeid)       AS distinct_recipes,
    count(DISTINCT developer)         AS unique_users
FROM traces
WHERE type = 'run'
  AND runstarttime IS NOT NULL
GROUP BY date_trunc('month', runstarttime)
ORDER BY month;
