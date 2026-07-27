-- Optional convenience view: v_publish — one typed row per LST publication (type = 'publish').
--
-- Publish traces come from `mod publish` (the LST publication path used by mass ingest
-- and CI). Not used by the current reports, but part of the complete semantic
-- layer — mass-ingest volume analysis lives here.

CREATE OR REPLACE VIEW v_publish AS
SELECT
    source,
    organization,
    origin,
    path,
    branch,
    developer,
    publishid,
    publishoutcome,
    publishstarttime    AS publish_started,
    publishuri,
    publishelapsedtimems    AS elapsed_ms,
    buildcliversion                             AS cli_version,
    year, month, day
FROM traces
WHERE type = 'publish'
  AND publishstarttime IS NOT NULL;
