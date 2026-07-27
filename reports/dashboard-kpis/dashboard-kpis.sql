-- Dashboard KPIs
--
-- Executive-level snapshot: all-time summary and monthly trend.
--
-- Reads the wide `traces` table directly. Run metrics come from type='run' rows (one row
-- per run) and commit counts from type='commit' rows, kept separate so stage re-emission
-- does not inflate the run totals (a run is re-embedded by each later apply/add/commit
-- trace). Timestamp and numeric columns are typed, so no casts are needed. Single-tenant
-- export, so no tenant filter. Optional convenience views: data-layer/athena/views.
-- Add `AND year = '2026'` to each scan to bound cost; omit it for true all-time totals.

-- Query 1: Summary KPIs (single row, all-time totals)
SELECT
    count(DISTINCT runid)                                        AS total_recipe_runs,
    ( SELECT count(*)
      FROM traces
      WHERE type = 'commit'
        AND commitstarttime IS NOT NULL
        AND commitoutcome = 'Succeeded' )                        AS total_commits,
    count(DISTINCT developer)                                    AS unique_users,
    count(DISTINCT runrecipeid)                                  AS unique_recipes,
    sum(runfileswithfixresults)                                  AS files_changed,
    round(sum(runestimatedefforttimesavingsms) / 3600000.0, 1)   AS estimated_hours_saved
FROM traces
WHERE type = 'run'
  AND runstarttime IS NOT NULL;

-- Query 2: Monthly Trend
-- Replace 'month' with 'week', 'quarter', or 'year' to change granularity.
WITH runs AS (
    SELECT
        date_trunc('month', runstarttime)     AS month,
        count(DISTINCT runid)                 AS recipe_runs,
        count(DISTINCT developer)             AS unique_users,
        count(DISTINCT runrecipeid)           AS unique_recipes,
        sum(runfileswithfixresults)           AS files_changed,
        sum(runestimatedefforttimesavingsms)  AS savings_ms
    FROM traces
    WHERE type = 'run'
      AND runstarttime IS NOT NULL
    GROUP BY 1
),
commits AS (
    SELECT
        date_trunc('month', commitstarttime) AS month,
        count(*)                             AS commits
    FROM traces
    WHERE type = 'commit'
      AND commitstarttime IS NOT NULL
      AND commitoutcome = 'Succeeded'
    GROUP BY 1
)
SELECT
    coalesce(r.month, c.month)                      AS month,
    coalesce(r.recipe_runs, 0)                      AS recipe_runs,
    coalesce(c.commits, 0)                          AS commits,
    coalesce(r.unique_users, 0)                     AS unique_users,
    coalesce(r.unique_recipes, 0)                   AS unique_recipes,
    coalesce(r.files_changed, 0)                    AS files_changed,
    round(coalesce(r.savings_ms, 0) / 3600000.0, 1) AS estimated_hours_saved
FROM runs r
FULL OUTER JOIN commits c ON r.month = c.month
ORDER BY month;
