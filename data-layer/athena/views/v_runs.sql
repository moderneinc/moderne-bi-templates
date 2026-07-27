-- Optional convenience view: v_runs — one typed row per recipe run (type = 'run').
--
-- Curated layer over traces. The run type-scoping (which keeps stage re-emission from
-- inflating totals) and the friendly column names live here; `traces` columns are already
-- typed, so the view adds no casts.

CREATE OR REPLACE VIEW v_runs AS
SELECT
    source,
    organization,
    origin,
    path,
    branch,
    developer,
    runid,
    runoutcome,
    runstarttime                  AS run_started,
    runendtime                    AS run_ended,
    runrecipeid                                           AS recipe_id,
    runrecipeinstancename                                 AS recipe_name,
    runrecipeartifact                                     AS recipe_artifact,
    runestimatedefforttimesavingsms   AS effort_savings_ms,
    runfileswithfixresults           AS files_with_fixes,
    runfileswithsearchresults        AS files_with_search_results,
    runfilessearched                 AS files_searched,
    runelapsedtimems                  AS elapsed_ms,
    buildcliversion                                       AS cli_version,
    year, month, day
FROM traces
WHERE type = 'run'
  AND runstarttime IS NOT NULL;
