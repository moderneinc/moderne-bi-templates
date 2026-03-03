-- Top Recipes with Commits
--
-- Recipes ranked by committed code changes — shows which recipes deliver real results.
-- Data source: mod git commit trace, or any later-stage trace.
--
-- Compatible with: AWS Athena, Trino, PostgreSQL, and other standard SQL engines.

SELECT
    runRecipeId                                            AS recipe_id,
    MAX(runRecipeInstanceName)                             AS recipe_name,
    COUNT(DISTINCT commitId)                               AS commits,
    COUNT(DISTINCT developer)                              AS unique_users,
    ROUND(SUM(runEstimatedEffortTimeSavingsMs) / 3600000.0, 1) AS estimated_hours_saved
FROM trace
WHERE commitOutcome = 'Succeeded'
GROUP BY runRecipeId
ORDER BY commits DESC;
