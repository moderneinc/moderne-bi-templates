-- Optional convenience view: v_publish, one typed row per LST publication (type = 'publish').
--
-- Publish traces come from `mod publish` (the LST publication path used by mass ingest
-- and CI). Not used by the current reports, but part of the complete semantic layer;
-- mass-ingest volume analysis lives here.

CREATE OR REPLACE VIEW moderne_telemetry.v_publish AS
SELECT
    source,
    organization,
    origin,
    path,
    branch,
    developer,
    publishId,
    publishOutcome,
    publishStartTime     AS publish_started,
    publishUri,
    publishElapsedTimeMs AS elapsed_ms,
    buildCliVersion      AS cli_version,
    year, month, day
FROM moderne_telemetry.traces
WHERE type = 'publish'
  AND publishStartTime IS NOT NULL;
