-- Top Recipes
--
-- Most-used recipes ranked by run count, unique users, and repos searched.
-- Data source: mod run trace, or any later-stage trace.
--
-- Compatible with: AWS Athena, Trino, PostgreSQL, and other standard SQL engines.

SELECT
    runRecipeId                AS recipe_id,
    MAX(runRecipeInstanceName) AS recipe_name,
    COUNT(DISTINCT runId)      AS recipe_runs,
    COUNT(DISTINCT developer)  AS unique_users,
    COUNT(DISTINCT path)       AS repos_searched
FROM trace
WHERE runOutcome IS NOT NULL
GROUP BY runRecipeId
ORDER BY recipe_runs DESC;
