-- Top Users
--
-- User engagement ranking by recipe runs and commits.
--
-- Reads the wide `traces` table directly. Runs come from type='run' rows and commits from
-- type='commit' rows, counted separately and joined per developer so stage re-emission does
-- not inflate either side. If only run traces exist, recipe_runs is accurate and commits is
-- zero. Single-tenant export, so no tenant filter. Optional convenience views:
-- data-layer/athena/views. Add `AND year = '2026'` to each scan to bound cost.

SELECT
    coalesce(r.developer, c.developer) AS developer,
    coalesce(r.recipe_runs, 0)         AS recipe_runs,
    coalesce(c.commits, 0)             AS commits
FROM (
    SELECT developer, count(DISTINCT runid) AS recipe_runs
    FROM traces
    WHERE type = 'run'
      AND runstarttime IS NOT NULL
      AND developer <> ''
    GROUP BY developer
) r
FULL OUTER JOIN (
    SELECT developer, count(DISTINCT commitid) AS commits
    FROM traces
    WHERE type = 'commit'
      AND commitstarttime IS NOT NULL
      AND commitoutcome = 'Succeeded'
      AND developer <> ''
    GROUP BY developer
) c ON r.developer = c.developer
ORDER BY recipe_runs DESC;
