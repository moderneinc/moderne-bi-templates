-- Optional convenience view: v_mcp, one typed row per MCP server tool call (type = 'mcp').
--
-- MCP traces are standalone (common columns + MCP columns), emitted by Moderne MCP
-- server tool calls. Not used by the current reports, but part of the complete
-- semantic layer; MCP tool adoption/usage analysis lives here.

CREATE OR REPLACE VIEW moderne_telemetry.v_mcp AS
SELECT
    source,
    organization,
    developer,
    mcpSessionId     AS session_id,
    mcpToolName      AS tool_name,
    mcpRecipeId      AS recipe_id,
    mcpRunId         AS run_id,
    mcpOutcome       AS outcome,
    mcpStartTime     AS mcp_started,
    mcpMatchCount    AS match_count,
    mcpChangeCount   AS change_count,
    mcpResultBytes   AS result_bytes,
    mcpElapsedTimeMs AS elapsed_ms,
    mcpArguments     AS arguments,
    year, month, day
FROM moderne_telemetry.traces
WHERE type = 'mcp'
  AND mcpStartTime IS NOT NULL;
