-- Build Tool & Language Distribution
--
-- Distribution of build tools and versions across successfully built repositories.
-- Data source: mod build trace, or any later-stage trace.
--
-- Compatible with: AWS Athena, Trino, PostgreSQL, and other standard SQL engines.

-- Query 1: Build tool summary — repos per build tool
SELECT
    CASE
        WHEN buildMavenVersion IS NOT NULL AND buildMavenVersion != '' THEN 'Maven'
        WHEN buildGradleVersion IS NOT NULL AND buildGradleVersion != '' THEN 'Gradle'
        WHEN buildBazelVersion IS NOT NULL AND buildBazelVersion != '' THEN 'Bazel'
        WHEN buildDotnetVersion IS NOT NULL AND buildDotnetVersion != '' THEN '.NET'
        WHEN buildPythonVersion IS NOT NULL AND buildPythonVersion != '' THEN 'Python'
        WHEN buildNodeVersion IS NOT NULL AND buildNodeVersion != '' THEN 'Node.js'
        ELSE 'Other'
    END                      AS build_tool,
    COUNT(DISTINCT path)     AS repos,
    COUNT(DISTINCT buildId)  AS builds
FROM trace
WHERE buildOutcome = 'Succeeded'
GROUP BY 1
ORDER BY repos DESC;

-- Query 2: Version breakdown — repos per tool version
SELECT
    CASE
        WHEN buildMavenVersion IS NOT NULL AND buildMavenVersion != '' THEN 'Maven'
        WHEN buildGradleVersion IS NOT NULL AND buildGradleVersion != '' THEN 'Gradle'
        WHEN buildBazelVersion IS NOT NULL AND buildBazelVersion != '' THEN 'Bazel'
        WHEN buildDotnetVersion IS NOT NULL AND buildDotnetVersion != '' THEN '.NET'
        WHEN buildPythonVersion IS NOT NULL AND buildPythonVersion != '' THEN 'Python'
        WHEN buildNodeVersion IS NOT NULL AND buildNodeVersion != '' THEN 'Node.js'
        ELSE 'Other'
    END                      AS build_tool,
    COALESCE(
        NULLIF(buildMavenVersion, ''),
        NULLIF(buildGradleVersion, ''),
        NULLIF(buildBazelVersion, ''),
        NULLIF(buildDotnetVersion, ''),
        NULLIF(buildPythonVersion, ''),
        NULLIF(buildNodeVersion, ''),
        'Unknown'
    )                        AS tool_version,
    COUNT(DISTINCT path)     AS repos,
    COUNT(DISTINCT buildId)  AS builds
FROM trace
WHERE buildOutcome = 'Succeeded'
GROUP BY 1, 2
ORDER BY build_tool, repos DESC;
