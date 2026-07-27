-- Data layer: Athena / Glue — database
--
-- The ingest tables, the `traces` table, and the views all live in one Glue database.
-- Create one and name it whatever fits your conventions (this example uses `moderne_telemetry`).
-- The report queries and views use UNQUALIFIED table names (`FROM traces`), so make this
-- database your Athena query context — pick it in the console's "Database" selector, or run
-- `USE moderne_telemetry;` — before running the DDL and reports. The compaction job writes here
-- too: point its GLUE_DATABASE environment variable at the same name.

CREATE DATABASE IF NOT EXISTS moderne_telemetry;
