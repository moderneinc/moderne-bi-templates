-- Build Success Trend
--
-- Monthly build health: total builds, successes, failures, success rate, and repos built.
--
-- Reads the wide `traces` table directly. Build columns are populated on build/run/apply/
-- add/commit/publish traces, so this spans those types and COUNT(DISTINCT buildid) counts
-- each build once (a build is re-embedded by every later command that reuses it). Timestamp
-- and numeric columns in `traces` are typed, so no casts are needed. Your export holds a
-- single tenant, so there is no tenant filter. Optional convenience views:
-- data-layer/athena/views.
-- Tune it: replace 'month' with 'week'/'quarter'/'year'; add `AND year = '2026'` to bound the scan.

SELECT
    date_trunc('month', buildstarttime)                                   AS month,
    count(DISTINCT buildid)                                               AS total_builds,
    count(DISTINCT CASE WHEN buildoutcome = 'Succeeded' THEN buildid END) AS successful_builds,
    count(DISTINCT CASE WHEN buildoutcome <> 'Succeeded' THEN buildid END) AS failed_builds,
    round(100.0 * count(DISTINCT CASE WHEN buildoutcome = 'Succeeded' THEN buildid END)
        / count(DISTINCT buildid), 1)                                     AS success_rate_pct,
    count(DISTINCT path)                                                  AS unique_repos
FROM traces
WHERE type IN ('build', 'run', 'apply', 'add', 'commit', 'publish')
  AND buildstarttime IS NOT NULL
GROUP BY date_trunc('month', buildstarttime)
ORDER BY month;
