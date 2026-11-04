-- Optional convenience view: v_sync, one typed row per repository sync (type = 'sync').
--
-- Sync traces record the clone / LST-download step. Not used by the current reports,
-- but part of the complete semantic layer; clone/download performance and outcome
-- analysis lives here.

CREATE OR REPLACE VIEW moderne_telemetry.v_sync AS
SELECT
    source,
    organization,
    origin,
    path,
    branch,
    developer,
    syncOutcome,
    syncStartTime      AS sync_started,
    syncChangeset,
    syncLstDownloadUri,
    syncElapsedTimeMs  AS elapsed_ms,
    year, month, day
FROM moderne_telemetry.traces
WHERE type = 'sync'
  AND syncStartTime IS NOT NULL;
