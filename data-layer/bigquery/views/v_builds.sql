-- Optional convenience view: v_builds, typed build rows across every command that runs a build.
--
-- Build columns are populated on build, run, apply, add, commit, and publish traces, so
-- this view spans all six types. Rows are at TRACE grain, not build grain: a single
-- build is re-embedded by each later command that reuses it, so consumers must
-- COUNT(DISTINCT buildId) to count a build once (every report here does).

CREATE OR REPLACE VIEW moderne_telemetry.v_builds AS
SELECT
    source,
    organization,
    origin,
    path,
    branch,
    developer,
    buildId,
    buildOutcome,
    buildStartTime       AS build_started,
    buildMavenVersion    AS maven_version,
    buildGradleVersion   AS gradle_version,
    buildBazelVersion    AS bazel_version,
    buildDotnetVersion   AS dotnet_version,
    buildPythonVersion   AS python_version,
    buildNodeVersion     AS node_version,
    buildCliVersion      AS cli_version,
    buildOsName          AS os_name,
    buildSourceFileCount AS source_file_count,
    buildLineCount       AS line_count,
    buildParseErrorCount AS parse_error_count,
    buildElapsedTimeMs   AS elapsed_ms,
    year, month, day
FROM moderne_telemetry.traces
WHERE type IN ('build', 'run', 'apply', 'add', 'commit', 'publish')
  AND buildStartTime IS NOT NULL;
