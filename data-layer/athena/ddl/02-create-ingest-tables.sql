-- Data layer: Athena / Glue — per-type raw CSV ingest tables
--
-- One table per command type over the RAW telemetry CSV (the bucket your tenant's
-- telemetry replicates into). OpenCSVSerde is POSITIONAL, and each command type
-- writes a different CSV width and column order, so each type needs its own table
-- whose column list exactly matches that command's on-disk header. `type` is pinned
-- to a single enum value per table.
--
-- These tables are the INPUT to the compaction job (../compaction/), which reads
-- each one and writes name-aligned Parquet into the `traces` table. You can also
-- query them directly if you prefer to skip compaction — the column names match
-- `traces`, so a report query works against, say, traces_run_ingest by swapping the
-- table name and dropping the `type` predicate (the table is already type-scoped).
--
-- Replace <your-telemetry-bucket> with the bucket that holds the raw replicated CSV, and
-- <your-tenant> with your tenant name. Your export holds a single tenant, so `tenant` is
-- projected as a one-value enum and no query needs a `tenant` predicate.
-- projection.year.range spans 2026-2099; empty future years hold no objects, so they cost
-- nothing to scan and add only trivial split-planning overhead.

-- Shared partitioning + projection for every ingest table below. Each table sets
-- 'projection.type.values' to its own single type and pins that type in the
-- storage.location.template.

CREATE EXTERNAL TABLE IF NOT EXISTS traces_sync_ingest (
    origin string, path string, branch string, developer string,
    syncoutcome string, synccloneuri string, synclstdownloaduri string,
    syncstarttime string, syncendtime string, syncchangeset string, syncelapsedtimems string,
    organization string
)
PARTITIONED BY (tenant STRING, source STRING, type STRING, year STRING, month STRING, day STRING)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"', 'escapeChar' = '\\')
STORED AS TEXTFILE
LOCATION 's3://<your-telemetry-bucket>/'
TBLPROPERTIES (
    'skip.header.line.count'    = '1',
    'projection.enabled'        = 'true',
    'projection.tenant.type'    = 'enum',
    'projection.tenant.values'  = '<your-tenant>',
    'projection.source.type'    = 'enum',
    'projection.source.values'  = 'saas,cli',
    'projection.type.type'      = 'enum',
    'projection.type.values'    = 'sync',
    'projection.year.type'      = 'integer',
    'projection.year.range'     = '2026,2099',
    'projection.year.digits'    = '4',
    'projection.month.type'     = 'integer',
    'projection.month.range'    = '1,12',
    'projection.month.digits'   = '2',
    'projection.day.type'       = 'integer',
    'projection.day.range'      = '1,31',
    'projection.day.digits'     = '2',
    'storage.location.template' =
      's3://<your-telemetry-bucket>/tenant=${tenant}/source=${source}/type=sync/year=${year}/month=${month}/day=${day}/'
);

CREATE EXTERNAL TABLE IF NOT EXISTS traces_build_ingest (
    origin string, path string, branch string, developer string,
    syncoutcome string, synccloneuri string, synclstdownloaduri string,
    syncstarttime string, syncendtime string, syncchangeset string, syncelapsedtimems string,
    buildoutcome string, buildstarttime string, buildendtime string, buildid string,
    builddependencyresolutiontimems string, buildchangeset string, buildmavenversion string,
    buildgradleversion string, buildbazelversion string, builddotnetversion string,
    buildpythonversion string, buildnodeversion string, buildosname string, buildosversion string,
    buildoseol string, buildgitautocrlf string, buildgiteol string, buildsourcefilecount string,
    buildlinecount string, buildparseerrorcount string, buildweight string, buildmaxweight string,
    buildmaxweightsourcefile string, buildcliversion string, buildelapsedtimems string,
    organization string
)
PARTITIONED BY (tenant STRING, source STRING, type STRING, year STRING, month STRING, day STRING)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"', 'escapeChar' = '\\')
STORED AS TEXTFILE
LOCATION 's3://<your-telemetry-bucket>/'
TBLPROPERTIES (
    'skip.header.line.count'    = '1',
    'projection.enabled'        = 'true',
    'projection.tenant.type'    = 'enum',
    'projection.tenant.values'  = '<your-tenant>',
    'projection.source.type'    = 'enum',
    'projection.source.values'  = 'saas,cli',
    'projection.type.type'      = 'enum',
    'projection.type.values'    = 'build',
    'projection.year.type'      = 'integer',
    'projection.year.range'     = '2026,2099',
    'projection.year.digits'    = '4',
    'projection.month.type'     = 'integer',
    'projection.month.range'    = '1,12',
    'projection.month.digits'   = '2',
    'projection.day.type'       = 'integer',
    'projection.day.range'      = '1,31',
    'projection.day.digits'     = '2',
    'storage.location.template' =
      's3://<your-telemetry-bucket>/tenant=${tenant}/source=${source}/type=build/year=${year}/month=${month}/day=${day}/'
);

CREATE EXTERNAL TABLE IF NOT EXISTS traces_run_ingest (
    origin string, path string, branch string, developer string,
    syncoutcome string, synccloneuri string, synclstdownloaduri string,
    syncstarttime string, syncendtime string, syncchangeset string, syncelapsedtimems string,
    buildoutcome string, buildstarttime string, buildendtime string, buildid string,
    builddependencyresolutiontimems string, buildchangeset string, buildmavenversion string,
    buildgradleversion string, buildbazelversion string, builddotnetversion string,
    buildpythonversion string, buildnodeversion string, buildosname string, buildosversion string,
    buildoseol string, buildgitautocrlf string, buildgiteol string, buildsourcefilecount string,
    buildlinecount string, buildparseerrorcount string, buildweight string, buildmaxweight string,
    buildmaxweightsourcefile string, buildcliversion string, buildelapsedtimems string,
    runoutcome string, runstarttime string, runendtime string, runid string,
    rununlicensedattempt string, runstreaming string, runrecipeid string, runrecipeinstancename string,
    runrecipeoptions string, runrecipeartifact string, runestimatedefforttimesavingsms string,
    rundependencyresolutiontimems string, runpomcachehitrate string, runresolvedpomcachehitrate string,
    runfileswithfixresults string, runfileswithsearchresults string, runfileswitherrors string,
    runfilessearched string, rundatatables string, runthread string, runelapsedtimems string,
    organization string
)
PARTITIONED BY (tenant STRING, source STRING, type STRING, year STRING, month STRING, day STRING)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"', 'escapeChar' = '\\')
STORED AS TEXTFILE
LOCATION 's3://<your-telemetry-bucket>/'
TBLPROPERTIES (
    'skip.header.line.count'    = '1',
    'projection.enabled'        = 'true',
    'projection.tenant.type'    = 'enum',
    'projection.tenant.values'  = '<your-tenant>',
    'projection.source.type'    = 'enum',
    'projection.source.values'  = 'saas,cli',
    'projection.type.type'      = 'enum',
    'projection.type.values'    = 'run',
    'projection.year.type'      = 'integer',
    'projection.year.range'     = '2026,2099',
    'projection.year.digits'    = '4',
    'projection.month.type'     = 'integer',
    'projection.month.range'    = '1,12',
    'projection.month.digits'   = '2',
    'projection.day.type'       = 'integer',
    'projection.day.range'      = '1,31',
    'projection.day.digits'     = '2',
    'storage.location.template' =
      's3://<your-telemetry-bucket>/tenant=${tenant}/source=${source}/type=run/year=${year}/month=${month}/day=${day}/'
);

CREATE EXTERNAL TABLE IF NOT EXISTS traces_apply_ingest (
    origin string, path string, branch string, developer string,
    syncoutcome string, synccloneuri string, synclstdownloaduri string,
    syncstarttime string, syncendtime string, syncchangeset string, syncelapsedtimems string,
    buildoutcome string, buildstarttime string, buildendtime string, buildid string,
    builddependencyresolutiontimems string, buildchangeset string, buildmavenversion string,
    buildgradleversion string, buildbazelversion string, builddotnetversion string,
    buildpythonversion string, buildnodeversion string, buildosname string, buildosversion string,
    buildoseol string, buildgitautocrlf string, buildgiteol string, buildsourcefilecount string,
    buildlinecount string, buildparseerrorcount string, buildweight string, buildmaxweight string,
    buildmaxweightsourcefile string, buildcliversion string, buildelapsedtimems string,
    runoutcome string, runstarttime string, runendtime string, runid string,
    rununlicensedattempt string, runstreaming string, runrecipeid string, runrecipeinstancename string,
    runrecipeoptions string, runrecipeartifact string, runestimatedefforttimesavingsms string,
    rundependencyresolutiontimems string, runpomcachehitrate string, runresolvedpomcachehitrate string,
    runfileswithfixresults string, runfileswithsearchresults string, runfileswitherrors string,
    runfilessearched string, rundatatables string, runthread string, runelapsedtimems string,
    applyoutcome string, applystarttime string, applyendtime string, applyid string, applyelapsedtimems string,
    organization string
)
PARTITIONED BY (tenant STRING, source STRING, type STRING, year STRING, month STRING, day STRING)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"', 'escapeChar' = '\\')
STORED AS TEXTFILE
LOCATION 's3://<your-telemetry-bucket>/'
TBLPROPERTIES (
    'skip.header.line.count'    = '1',
    'projection.enabled'        = 'true',
    'projection.tenant.type'    = 'enum',
    'projection.tenant.values'  = '<your-tenant>',
    'projection.source.type'    = 'enum',
    'projection.source.values'  = 'saas,cli',
    'projection.type.type'      = 'enum',
    'projection.type.values'    = 'apply',
    'projection.year.type'      = 'integer',
    'projection.year.range'     = '2026,2099',
    'projection.year.digits'    = '4',
    'projection.month.type'     = 'integer',
    'projection.month.range'    = '1,12',
    'projection.month.digits'   = '2',
    'projection.day.type'       = 'integer',
    'projection.day.range'      = '1,31',
    'projection.day.digits'     = '2',
    'storage.location.template' =
      's3://<your-telemetry-bucket>/tenant=${tenant}/source=${source}/type=apply/year=${year}/month=${month}/day=${day}/'
);

CREATE EXTERNAL TABLE IF NOT EXISTS traces_add_ingest (
    origin string, path string, branch string, developer string,
    syncoutcome string, synccloneuri string, synclstdownloaduri string,
    syncstarttime string, syncendtime string, syncchangeset string, syncelapsedtimems string,
    buildoutcome string, buildstarttime string, buildendtime string, buildid string,
    builddependencyresolutiontimems string, buildchangeset string, buildmavenversion string,
    buildgradleversion string, buildbazelversion string, builddotnetversion string,
    buildpythonversion string, buildnodeversion string, buildosname string, buildosversion string,
    buildoseol string, buildgitautocrlf string, buildgiteol string, buildsourcefilecount string,
    buildlinecount string, buildparseerrorcount string, buildweight string, buildmaxweight string,
    buildmaxweightsourcefile string, buildcliversion string, buildelapsedtimems string,
    runoutcome string, runstarttime string, runendtime string, runid string,
    rununlicensedattempt string, runstreaming string, runrecipeid string, runrecipeinstancename string,
    runrecipeoptions string, runrecipeartifact string, runestimatedefforttimesavingsms string,
    rundependencyresolutiontimems string, runpomcachehitrate string, runresolvedpomcachehitrate string,
    runfileswithfixresults string, runfileswithsearchresults string, runfileswitherrors string,
    runfilessearched string, rundatatables string, runthread string, runelapsedtimems string,
    applyoutcome string, applystarttime string, applyendtime string, applyid string, applyelapsedtimems string,
    addoutcome string, addstarttime string, addendtime string, addid string, addelapsedtimems string,
    organization string
)
PARTITIONED BY (tenant STRING, source STRING, type STRING, year STRING, month STRING, day STRING)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"', 'escapeChar' = '\\')
STORED AS TEXTFILE
LOCATION 's3://<your-telemetry-bucket>/'
TBLPROPERTIES (
    'skip.header.line.count'    = '1',
    'projection.enabled'        = 'true',
    'projection.tenant.type'    = 'enum',
    'projection.tenant.values'  = '<your-tenant>',
    'projection.source.type'    = 'enum',
    'projection.source.values'  = 'saas,cli',
    'projection.type.type'      = 'enum',
    'projection.type.values'    = 'add',
    'projection.year.type'      = 'integer',
    'projection.year.range'     = '2026,2099',
    'projection.year.digits'    = '4',
    'projection.month.type'     = 'integer',
    'projection.month.range'    = '1,12',
    'projection.month.digits'   = '2',
    'projection.day.type'       = 'integer',
    'projection.day.range'      = '1,31',
    'projection.day.digits'     = '2',
    'storage.location.template' =
      's3://<your-telemetry-bucket>/tenant=${tenant}/source=${source}/type=add/year=${year}/month=${month}/day=${day}/'
);

CREATE EXTERNAL TABLE IF NOT EXISTS traces_commit_ingest (
    origin string, path string, branch string, developer string,
    syncoutcome string, synccloneuri string, synclstdownloaduri string,
    syncstarttime string, syncendtime string, syncchangeset string, syncelapsedtimems string,
    buildoutcome string, buildstarttime string, buildendtime string, buildid string,
    builddependencyresolutiontimems string, buildchangeset string, buildmavenversion string,
    buildgradleversion string, buildbazelversion string, builddotnetversion string,
    buildpythonversion string, buildnodeversion string, buildosname string, buildosversion string,
    buildoseol string, buildgitautocrlf string, buildgiteol string, buildsourcefilecount string,
    buildlinecount string, buildparseerrorcount string, buildweight string, buildmaxweight string,
    buildmaxweightsourcefile string, buildcliversion string, buildelapsedtimems string,
    runoutcome string, runstarttime string, runendtime string, runid string,
    rununlicensedattempt string, runstreaming string, runrecipeid string, runrecipeinstancename string,
    runrecipeoptions string, runrecipeartifact string, runestimatedefforttimesavingsms string,
    rundependencyresolutiontimems string, runpomcachehitrate string, runresolvedpomcachehitrate string,
    runfileswithfixresults string, runfileswithsearchresults string, runfileswitherrors string,
    runfilessearched string, rundatatables string, runthread string, runelapsedtimems string,
    applyoutcome string, applystarttime string, applyendtime string, applyid string, applyelapsedtimems string,
    addoutcome string, addstarttime string, addendtime string, addid string, addelapsedtimems string,
    commitoutcome string, commitstarttime string, commitendtime string, commitid string,
    commitbranch string, commitelapsedtimems string,
    organization string
)
PARTITIONED BY (tenant STRING, source STRING, type STRING, year STRING, month STRING, day STRING)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"', 'escapeChar' = '\\')
STORED AS TEXTFILE
LOCATION 's3://<your-telemetry-bucket>/'
TBLPROPERTIES (
    'skip.header.line.count'    = '1',
    'projection.enabled'        = 'true',
    'projection.tenant.type'    = 'enum',
    'projection.tenant.values'  = '<your-tenant>',
    'projection.source.type'    = 'enum',
    'projection.source.values'  = 'saas,cli',
    'projection.type.type'      = 'enum',
    'projection.type.values'    = 'commit',
    'projection.year.type'      = 'integer',
    'projection.year.range'     = '2026,2099',
    'projection.year.digits'    = '4',
    'projection.month.type'     = 'integer',
    'projection.month.range'    = '1,12',
    'projection.month.digits'   = '2',
    'projection.day.type'       = 'integer',
    'projection.day.range'      = '1,31',
    'projection.day.digits'     = '2',
    'storage.location.template' =
      's3://<your-telemetry-bucket>/tenant=${tenant}/source=${source}/type=commit/year=${year}/month=${month}/day=${day}/'
);

CREATE EXTERNAL TABLE IF NOT EXISTS traces_publish_ingest (
    origin string, path string, branch string, developer string,
    syncoutcome string, synccloneuri string, synclstdownloaduri string,
    syncstarttime string, syncendtime string, syncchangeset string, syncelapsedtimems string,
    buildoutcome string, buildstarttime string, buildendtime string, buildid string,
    builddependencyresolutiontimems string, buildchangeset string, buildmavenversion string,
    buildgradleversion string, buildbazelversion string, builddotnetversion string,
    buildpythonversion string, buildnodeversion string, buildosname string, buildosversion string,
    buildoseol string, buildgitautocrlf string, buildgiteol string, buildsourcefilecount string,
    buildlinecount string, buildparseerrorcount string, buildweight string, buildmaxweight string,
    buildmaxweightsourcefile string, buildcliversion string, buildelapsedtimems string,
    publishoutcome string, publishstarttime string, publishendtime string, publishid string,
    publishuri string, publishelapsedtimems string,
    organization string
)
PARTITIONED BY (tenant STRING, source STRING, type STRING, year STRING, month STRING, day STRING)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"', 'escapeChar' = '\\')
STORED AS TEXTFILE
LOCATION 's3://<your-telemetry-bucket>/'
TBLPROPERTIES (
    'skip.header.line.count'    = '1',
    'projection.enabled'        = 'true',
    'projection.tenant.type'    = 'enum',
    'projection.tenant.values'  = '<your-tenant>',
    'projection.source.type'    = 'enum',
    'projection.source.values'  = 'saas,cli',
    'projection.type.type'      = 'enum',
    'projection.type.values'    = 'publish',
    'projection.year.type'      = 'integer',
    'projection.year.range'     = '2026,2099',
    'projection.year.digits'    = '4',
    'projection.month.type'     = 'integer',
    'projection.month.range'    = '1,12',
    'projection.month.digits'   = '2',
    'projection.day.type'       = 'integer',
    'projection.day.range'      = '1,31',
    'projection.day.digits'     = '2',
    'storage.location.template' =
      's3://<your-telemetry-bucket>/tenant=${tenant}/source=${source}/type=publish/year=${year}/month=${month}/day=${day}/'
);

CREATE EXTERNAL TABLE IF NOT EXISTS traces_mcp_ingest (
    origin string, path string, branch string, developer string,
    mcpoutcome string, mcpstarttime string, mcpendtime string, mcpsessionid string,
    mcptoolname string, mcprecipeid string, mcpmatchcount string, mcpchangecount string,
    mcprunid string, mcpresultbytes string, mcparguments string, mcpelapsedtimems string,
    organization string
)
PARTITIONED BY (tenant STRING, source STRING, type STRING, year STRING, month STRING, day STRING)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"', 'escapeChar' = '\\')
STORED AS TEXTFILE
LOCATION 's3://<your-telemetry-bucket>/'
TBLPROPERTIES (
    'skip.header.line.count'    = '1',
    'projection.enabled'        = 'true',
    'projection.tenant.type'    = 'enum',
    'projection.tenant.values'  = '<your-tenant>',
    'projection.source.type'    = 'enum',
    'projection.source.values'  = 'saas,cli',
    'projection.type.type'      = 'enum',
    'projection.type.values'    = 'mcp',
    'projection.year.type'      = 'integer',
    'projection.year.range'     = '2026,2099',
    'projection.year.digits'    = '4',
    'projection.month.type'     = 'integer',
    'projection.month.range'    = '1,12',
    'projection.month.digits'   = '2',
    'projection.day.type'       = 'integer',
    'projection.day.range'      = '1,31',
    'projection.day.digits'     = '2',
    'storage.location.template' =
      's3://<your-telemetry-bucket>/tenant=${tenant}/source=${source}/type=mcp/year=${year}/month=${month}/day=${day}/'
);
