-- Tagged Activity
--
-- Groups committed recipe output by a trace tag, so you can attribute commits,
-- repositories, recipes, and estimated hours saved to whatever dimension you tag
-- runs with. The example uses `tag.changeSetId`, the canonical tag injected via
-- `--trace-tag changeSetId=<id>`, but any `tag.<key>` column works (for example
-- `tag.team` or `tag.region`).
--
-- Tags are added on the command line and become extra `tag.<key>` columns in the
-- trace.csv, for example:
--   mod run . --recipe ... --trace-tag changeSetId=CS-2026-0142 --trace-tag team=payments
-- See the README and the data dictionary's "Trace tags" section for details.
--
-- Note: the column name contains a dot, so it must be quoted as an identifier
-- ("tag.changeSetId") in AWS Athena, Trino, and PostgreSQL. Some loaders sanitize
-- dots to underscores (tag_changeSetId) — adjust the identifier to match your table.
--
-- A commit's stage data is re-emitted by every later command (e.g. mod git push
-- carries the commit stage too), so the inner query collapses to one row per
-- commitId first; the counts and sums are then correct even when both commit and
-- push traces are loaded.
--
-- Compatible with: AWS Athena, Trino, PostgreSQL, and other standard SQL engines.

SELECT
    "tag.changeSetId"                                          AS change_set,
    COUNT(*)                                                   AS successful_commits,
    COUNT(DISTINCT path)                                       AS repos_changed,
    COUNT(DISTINCT runRecipeId)                                AS distinct_recipes,
    ROUND(SUM(runEstimatedEffortTimeSavingsMs) / 3600000.0, 1) AS estimated_hours_saved
FROM (
    SELECT
        commitId,
        MAX("tag.changeSetId")               AS "tag.changeSetId",
        MAX(path)                            AS path,
        MAX(runRecipeId)                     AS runRecipeId,
        MAX(runEstimatedEffortTimeSavingsMs) AS runEstimatedEffortTimeSavingsMs
    FROM trace
    WHERE commitOutcome = 'Succeeded'
      AND "tag.changeSetId" IS NOT NULL
    GROUP BY commitId
) commits
GROUP BY "tag.changeSetId"
ORDER BY successful_commits DESC;
