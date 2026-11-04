-- Optional convenience view: v_runs, one typed row per recipe run (type = 'run').
--
-- Curated layer over traces. The run type-scoping (which keeps stage re-emission from
-- inflating totals) and the friendly column names live here; `traces` columns are already
-- typed, so the view adds no casts.

CREATE OR REPLACE VIEW moderne_telemetry.v_runs AS
SELECT
    source,
    organization,
    origin,
    path,
    branch,
    developer,
    runId,
    runOutcome,
    runStartTime                    AS run_started,
    runEndTime                      AS run_ended,
    runRecipeId                     AS recipe_id,
    runRecipeInstanceName           AS recipe_name,
    runRecipeArtifact               AS recipe_artifact,
    runEstimatedEffortTimeSavingsMs AS effort_savings_ms,
    runFilesWithFixResults          AS files_with_fixes,
    runFilesWithSearchResults       AS files_with_search_results,
    runFilesSearched                AS files_searched,
    runElapsedTimeMs                AS elapsed_ms,
    buildCliVersion                 AS cli_version,
    year, month, day
FROM moderne_telemetry.traces
WHERE type = 'run'
  AND runStartTime IS NOT NULL;
