-- Top Recipes with Commits
--
-- Recipes ranked by committed code changes — shows which recipes deliver real results.
-- Data source: mod git commit traces (type = 'commit').
--
-- Compatible with: AWS Athena, Trino, PostgreSQL, and other standard SQL engines.
-- Replace <your-tenant> with your tenant name.

SELECT
    runRecipeId                                            AS recipe_id,
    MAX(runRecipeInstanceName)                             AS recipe_name,
    COUNT(DISTINCT commitId)                               AS commits,
    COUNT(DISTINCT developer)                              AS unique_users,
    ROUND(SUM(runEstimatedEffortTimeSavingsMs) / 3600000.0, 1) AS estimated_hours_saved
FROM traces
WHERE tenant = '<your-tenant>'
  AND type = 'commit'
  AND commitOutcome = 'Succeeded'
GROUP BY runRecipeId
ORDER BY commits DESC;
