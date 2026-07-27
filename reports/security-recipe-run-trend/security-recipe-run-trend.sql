-- Security Recipe Run Trend
--
-- Monthly security remediation trend: committed fixes, repos fixed, files remediated,
-- hours saved, and distinct security recipes over time.
--
-- Reads the wide `traces` table directly, scoped to type='commit' (commit traces embed the
-- run that produced them; one row per commit, so totals are not inflated by stage
-- re-emission). Timestamp and numeric columns are typed, so no casts are needed. Single-
-- tenant export, so no tenant filter. Optional convenience views: data-layer/athena/views.
-- Tune it: replace 'month' with 'week'/'quarter'/'year'; add `AND year = '2026'` to bound the scan.
--          The runrecipeid LIKE filter targets rewrite-java-security and rewrite-static-
--          analysis; adjust it for your security recipe namespaces.

SELECT
    date_trunc('month', commitstarttime)                       AS month,
    count(*)                                                   AS successful_commits,
    count(DISTINCT path)                                       AS unique_repos_fixed,
    sum(runfileswithfixresults)                                AS files_remediated,
    round(sum(runestimatedefforttimesavingsms) / 3600000.0, 1) AS estimated_hours_saved,
    count(DISTINCT runrecipeid)                                AS distinct_recipes
FROM traces
WHERE type = 'commit'
  AND commitstarttime IS NOT NULL
  AND commitoutcome = 'Succeeded'
  AND ( runrecipeid LIKE 'org.openrewrite.java.security.%'
     OR runrecipeid LIKE 'org.openrewrite.staticanalysis.%' )
GROUP BY date_trunc('month', commitstarttime)
ORDER BY month;
