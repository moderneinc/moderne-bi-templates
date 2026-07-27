-- Build Tool & Language Distribution
--
-- Distribution of build tools and versions across successfully built repositories.
--
-- Reads the wide `traces` table directly. Spans every type that runs a build, and
-- COUNT(DISTINCT buildid) counts each build once. Single-tenant export, so no tenant
-- filter. Optional convenience views: data-layer/athena/views.
-- Add `AND year = '2026'` to bound the scan.

-- Query 1: Build tool summary — repos per build tool
SELECT
    CASE
        WHEN buildmavenversion  <> '' THEN 'Maven'
        WHEN buildgradleversion <> '' THEN 'Gradle'
        WHEN buildbazelversion  <> '' THEN 'Bazel'
        WHEN builddotnetversion <> '' THEN '.NET'
        WHEN buildpythonversion <> '' THEN 'Python'
        WHEN buildnodeversion   <> '' THEN 'Node.js'
        ELSE 'Other'
    END                      AS build_tool,
    count(DISTINCT path)     AS repos,
    count(DISTINCT buildid)  AS builds
FROM traces
WHERE type IN ('build', 'run', 'apply', 'add', 'commit', 'publish')
  AND buildoutcome = 'Succeeded'
GROUP BY 1
ORDER BY repos DESC;

-- Query 2: Version breakdown — repos per tool version
SELECT
    CASE
        WHEN buildmavenversion  <> '' THEN 'Maven'
        WHEN buildgradleversion <> '' THEN 'Gradle'
        WHEN buildbazelversion  <> '' THEN 'Bazel'
        WHEN builddotnetversion <> '' THEN '.NET'
        WHEN buildpythonversion <> '' THEN 'Python'
        WHEN buildnodeversion   <> '' THEN 'Node.js'
        ELSE 'Other'
    END                      AS build_tool,
    coalesce(
        nullif(buildmavenversion,  ''),
        nullif(buildgradleversion, ''),
        nullif(buildbazelversion,  ''),
        nullif(builddotnetversion, ''),
        nullif(buildpythonversion, ''),
        nullif(buildnodeversion,   ''),
        'Unknown'
    )                        AS tool_version,
    count(DISTINCT path)     AS repos,
    count(DISTINCT buildid)  AS builds
FROM traces
WHERE type IN ('build', 'run', 'apply', 'add', 'commit', 'publish')
  AND buildoutcome = 'Succeeded'
GROUP BY 1, 2
ORDER BY build_tool, repos DESC;
