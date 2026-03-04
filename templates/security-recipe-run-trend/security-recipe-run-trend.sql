-- Security Recipe Run Trend
--
-- Monthly security remediation trend: committed fixes, repos fixed,
-- files remediated, hours saved, and distinct security recipes over time.
-- Data source: mod git commit trace (commit-stage traces include run-stage data).
--
-- Compatible with: AWS Athena, Trino, PostgreSQL, and other engines supporting DATE_TRUNC.
-- Replace 'month' with 'week', 'quarter', or 'year' to change granularity.
--
-- Default filter targets recipes from rewrite-java-security and
-- rewrite-static-analysis. See the README for customization guidance.

SELECT
    DATE_TRUNC('month', CAST(commitStartTime AS TIMESTAMP))    AS month,
    COUNT(*)                                                   AS successful_commits,
    COUNT(DISTINCT path)                                       AS unique_repos_fixed,
    SUM(runFilesWithFixResults)                                AS files_remediated,
    ROUND(SUM(runEstimatedEffortTimeSavingsMs) / 3600000.0, 1) AS estimated_hours_saved,
    COUNT(DISTINCT runRecipeId)                                AS distinct_recipes
FROM trace
WHERE commitOutcome = 'Succeeded'
  AND (runRecipeId LIKE 'org.openrewrite.java.security.%'
    OR runRecipeId LIKE 'org.openrewrite.staticanalysis.%')
GROUP BY DATE_TRUNC('month', CAST(commitStartTime AS TIMESTAMP))
ORDER BY month;
