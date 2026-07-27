-- Optional convenience view: v_mcp — one typed row per MCP server tool call (type = 'mcp').
--
-- MCP traces are standalone (common columns + MCP columns), emitted by Moderne MCP
-- server tool calls. Not used by the current reports, but part of the complete
-- semantic layer — MCP tool adoption/usage analysis lives here.

CREATE OR REPLACE VIEW v_mcp AS
SELECT
    source,
    organization,
    developer,
    mcpsessionid                                AS session_id,
    mcptoolname                                 AS tool_name,
    mcprecipeid                                 AS recipe_id,
    mcprunid                                    AS run_id,
    mcpoutcome                                  AS outcome,
    mcpstarttime        AS mcp_started,
    mcpmatchcount          AS match_count,
    mcpchangecount         AS change_count,
    mcpresultbytes          AS result_bytes,
    mcpelapsedtimems        AS elapsed_ms,
    mcparguments                                AS arguments,
    year, month, day
FROM traces
WHERE type = 'mcp'
  AND mcpstarttime IS NOT NULL;
