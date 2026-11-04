-- Optional convenience view: v_commits, one typed row per commit (type = 'commit').
--
-- Each commit row embeds the recipe run that produced it, so run identifiers and
-- effort savings read directly off the commit. Scoping to type='commit' means one row
-- per commit with no per-commitId de-duplication needed. commitOutcome is exposed (not
-- filtered) so reports can split successful vs. all commits.

CREATE OR REPLACE VIEW moderne_telemetry.v_commits AS
SELECT
    source,
    organization,
    origin,
    path,
    branch,
    developer,
    commitId,
    commitOutcome,
    commitStartTime                 AS commit_started,
    commitBranch,
    commitSha,
    runId,
    runRecipeId                     AS recipe_id,
    runRecipeInstanceName           AS recipe_name,
    runEstimatedEffortTimeSavingsMs AS effort_savings_ms,
    runFilesWithFixResults          AS files_with_fixes,
    buildCliVersion                 AS cli_version,
    year, month, day
FROM moderne_telemetry.traces
WHERE type = 'commit'
  AND commitStartTime IS NOT NULL;
