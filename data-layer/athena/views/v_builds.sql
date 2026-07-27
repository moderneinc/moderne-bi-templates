-- Optional convenience view: v_builds — typed build rows across every command that runs a build.
--
-- Build columns are populated on build, run, apply, add, commit, and publish traces, so
-- this view spans all six types. Rows are at TRACE grain, not build grain: a single
-- build is re-embedded by each later command that reuses it, so consumers must
-- COUNT(DISTINCT buildid) to count a build once (every report here does).

CREATE OR REPLACE VIEW v_builds AS
SELECT
    source,
    organization,
    origin,
    path,
    branch,
    developer,
    buildid,
    buildoutcome,
    buildstarttime      AS build_started,
    buildmavenversion                           AS maven_version,
    buildgradleversion                          AS gradle_version,
    buildbazelversion                           AS bazel_version,
    builddotnetversion                          AS dotnet_version,
    buildpythonversion                          AS python_version,
    buildnodeversion                            AS node_version,
    buildcliversion                             AS cli_version,
    buildosname                                 AS os_name,
    buildsourcefilecount   AS source_file_count,
    buildlinecount          AS line_count,
    buildparseerrorcount   AS parse_error_count,
    buildelapsedtimems      AS elapsed_ms,
    year, month, day
FROM traces
WHERE type IN ('build', 'run', 'apply', 'add', 'commit', 'publish')
  AND buildstarttime IS NOT NULL;
