-- Optional convenience view: v_sync — one typed row per repository sync (type = 'sync').
--
-- Sync traces record the clone / LST-download step. Not used by the current reports,
-- but part of the complete semantic layer — clone/download performance and outcome
-- analysis lives here.

CREATE OR REPLACE VIEW v_sync AS
SELECT
    source,
    organization,
    origin,
    path,
    branch,
    developer,
    syncoutcome,
    syncstarttime       AS sync_started,
    syncchangeset,
    synclstdownloaduri,
    syncelapsedtimems       AS elapsed_ms,
    year, month, day
FROM traces
WHERE type = 'sync'
  AND syncstarttime IS NOT NULL;
