-- Data layer: Athena / Glue — the `traces` query table
--
-- One wide Parquet table that is the UNION of every command stage's columns, keyed by a
-- `type` partition. Every report query reads `FROM traces`. Parquet is read by name, so a
-- partition whose command type lacks a stage reads those columns as NULL (e.g. a type=run
-- row has NULL commit* columns).
--
-- Columns are typed (timestamp / bigint / double / boolean / string): the compaction job
-- casts each column as it writes the Parquet, so reports read real types and
-- need no casts. (The raw per-type ingest tables in 03 stay all-string — an OpenCSVSerde
-- constraint — and the compactor converts on the way in.)
--
-- This table reads the compacted Parquet written by the compaction job (see ../compaction/).
-- Partitions are registered as the compactor writes them — it runs
-- `ALTER TABLE traces ADD IF NOT EXISTS PARTITION (...)` per day — so there is no partition
-- projection here and no crawler. The paths are Hive-style (tenant=.../source=.../...), so
-- for a one-time or manual setup you can instead discover every existing partition at once
-- with `MSCK REPAIR TABLE traces`.
--
-- `tenant` is an ordinary partition column. Your export contains only your own tenant, so
-- queries need no `tenant` predicate; it stays a column you can still select or group by.
--
-- Prefer not to compact? Query the per-type CSV ingest tables in
-- 02-create-ingest-tables.sql directly — same column names, but all string.
--
-- Replace <your-compacted-bucket> with the bucket that holds the compacted Parquet.

CREATE EXTERNAL TABLE IF NOT EXISTS traces (
    origin                          string,
    path                            string,
    branch                          string,
    developer                       string,
    syncoutcome                     string,
    synccloneuri                    string,
    synclstdownloaduri              string,
    syncstarttime                   timestamp,
    syncendtime                     timestamp,
    syncchangeset                   string,
    syncelapsedtimems               bigint,
    buildoutcome                    string,
    buildstarttime                  timestamp,
    buildendtime                    timestamp,
    buildid                         string,
    builddependencyresolutiontimems bigint,
    buildchangeset                  string,
    buildmavenversion               string,
    buildgradleversion              string,
    buildbazelversion               string,
    builddotnetversion              string,
    buildpythonversion              string,
    buildnodeversion                string,
    buildosname                     string,
    buildosversion                  string,
    buildoseol                      string,
    buildgitautocrlf                string,
    buildgiteol                     string,
    buildsourcefilecount            bigint,
    buildlinecount                  bigint,
    buildparseerrorcount            bigint,
    buildweight                     bigint,
    buildmaxweight                  bigint,
    buildmaxweightsourcefile        string,
    buildcliversion                 string,
    buildelapsedtimems              bigint,
    runoutcome                      string,
    runstarttime                    timestamp,
    runendtime                      timestamp,
    runid                           string,
    rununlicensedattempt            boolean,
    runstreaming                    boolean,
    runrecipeid                     string,
    runrecipeinstancename           string,
    runrecipeoptions                string,
    runrecipeartifact               string,
    runestimatedefforttimesavingsms bigint,
    rundependencyresolutiontimems   bigint,
    runpomcachehitrate              double,
    runresolvedpomcachehitrate      double,
    runfileswithfixresults          bigint,
    runfileswithsearchresults       bigint,
    runfileswitherrors              bigint,
    runfilessearched                bigint,
    rundatatables                   string,
    runthread                       string,
    runelapsedtimems                bigint,
    applyoutcome                    string,
    applystarttime                  timestamp,
    applyendtime                    timestamp,
    applyid                         string,
    applyelapsedtimems              bigint,
    addoutcome                      string,
    addstarttime                    timestamp,
    addendtime                      timestamp,
    addid                           string,
    addelapsedtimems                bigint,
    commitoutcome                   string,
    commitstarttime                 timestamp,
    commitendtime                   timestamp,
    commitid                        string,
    commitbranch                    string,
    commitelapsedtimems             bigint,
    publishoutcome                  string,
    publishstarttime                timestamp,
    publishendtime                  timestamp,
    publishid                       string,
    publishuri                      string,
    publishelapsedtimems            bigint,
    mcpoutcome                      string,
    mcpstarttime                    timestamp,
    mcpendtime                      timestamp,
    mcpsessionid                    string,
    mcptoolname                     string,
    mcprecipeid                     string,
    mcpmatchcount                   bigint,
    mcpchangecount                  bigint,
    mcprunid                        string,
    mcpresultbytes                  bigint,
    mcparguments                    string,
    mcpelapsedtimems                bigint,
    organization                    string
)
PARTITIONED BY (
    tenant STRING,
    source STRING,
    type   STRING,
    year   STRING,
    month  STRING,
    day    STRING
)
STORED AS PARQUET
LOCATION 's3://<your-compacted-bucket>/';
