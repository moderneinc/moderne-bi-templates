-- Optional convenience view: v_commits — one typed row per commit (type = 'commit').
--
-- Each commit row embeds the recipe run that produced it, so run identifiers and
-- effort savings read directly off the commit. Scoping to type='commit' means one row
-- per commit with no per-commitId de-duplication needed. commitoutcome is exposed (not
-- filtered) so reports can split successful vs. all commits.

CREATE OR REPLACE VIEW v_commits AS
SELECT
    source,
    organization,
    origin,
    path,
    branch,
    developer,
    commitid,
    commitoutcome,
    commitstarttime               AS commit_started,
    commitbranch,
    runid,
    runrecipeid                                           AS recipe_id,
    runrecipeinstancename                                 AS recipe_name,
    runestimatedefforttimesavingsms   AS effort_savings_ms,
    runfileswithfixresults           AS files_with_fixes,
    buildcliversion                                       AS cli_version,
    year, month, day
FROM traces
WHERE type = 'commit'
  AND commitstarttime IS NOT NULL;
