# Glue job — raw CSV → typed Iceberg `traces`

[`build_traces.py`](build_traces.py) is a nightly AWS Glue (Spark) job that turns the raw trace CSV into the typed `traces` table the reports read. Read it top to bottom; the module docstring explains the design.

## What it does

Each run:

1. **Reads only new objects.** A Glue [job bookmark](https://docs.aws.amazon.com/glue/latest/dg/monitor-continuations.html) remembers which CSV objects earlier runs read, so a normal night reads just that day's uploads, however much history the bucket holds. Each object is read by its own header, so every command type's columns land by name.
2. **Catches late replicas.** S3 replication keeps the source's last-modified time, so a replica that lands after a run has started looks older than that run, and the bookmark alone would skip it. So each run also lists the objects modified in the last three days and reads any that `traces_raw` doesn't have.
3. **Keeps every raw row in `traces_raw`.** New rows are appended, all as strings, to an Iceberg table. An object that is delivered again replaces its earlier rows, and a late upload lands in the day its key names.
4. **Decides each column's type from all its history.** Each column gets one type (`boolean`, `bigint`, `double`, `timestamp`, or `string`): the first type that at least 99.9% of its non-null values match. Partition keys, `*id` columns, and `tag_*` columns always stay strings. Timestamps may end in `Z` or an offset, with or without a zone id (`2026-06-10T21:50:25Z[Etc/UTC]`, `2026-06-10T16:50:25-05:00[America/Chicago]`), and are stored in UTC. Running per-column counts in a small `traces_typing` table mean each night only the new rows are counted. The counts are saved with a fingerprint of the rules, so if you change a rule, the next run that ingests rows recounts from `traces_raw`.
5. **Appends to `traces`, rebuilding only when it must.** On a normal night the new rows are typed and appended, and a new field is added as a column. A file that was delivered again has its rows replaced in place; `traces` keeps a `_source_key` column naming the object each row came from, which is what makes that possible. The job rebuilds `traces` from `traces_raw` only on the first run or when a column's type changes. One stray value doesn't do that: a column changes type only once fewer than 99.9% of all the values it has ever held match it. Short of that, a value that doesn't match its column's type just becomes `NULL`.
6. **Maintains the tables.** It expires snapshots older than a day and compacts the small files nightly appends leave.

Column names are the CSV headers lowercased (`runStartTime` → `runstarttime`, `tag.team` → `tag_team`), which is how Athena exposes them anyway. **A new trace field becomes a typed, queryable column on the next run** with no DDL to edit. The job creates the database and all three tables in the Glue Data Catalog itself, so there is no DDL to run.

The job is safe to rerun after a failure. Every table is written before the bookmark advances, so a run that fails before then reads the same objects again next time and replaces their rows, and nothing is doubled. Snapshot expiry and compaction run after the bookmark advances. A failure there shows the run as `FAILED`, but the tables are already complete, and the next run does the maintenance.

## Setup

Replace `<your-telemetry-bucket>` (the raw replicated CSV), `<your-warehouse-bucket>` (where the Iceberg tables and the script live), and `<account-id>` throughout. The job creates the Glue database named by `--database` if it doesn't exist, along with its tables.

### 1. Upload the script

```bash
aws s3 cp build_traces.py s3://<your-warehouse-bucket>/scripts/build_traces.py
```

### 2. Create the job's role

The AWS managed `AWSGlueServiceRole` policy covers the Data Catalog and CloudWatch Logs. [`s3-policy.json`](s3-policy.json) adds read on the raw bucket and read/write on the warehouse bucket.

```bash
aws iam create-role --role-name moderne-traces-glue \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"glue.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam attach-role-policy --role-name moderne-traces-glue \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
aws iam put-role-policy --role-name moderne-traces-glue \
    --policy-name moderne-traces-s3 --policy-document file://s3-policy.json
```

### 3. Create the job

```bash
aws glue create-job --name moderne-build-traces \
    --role arn:aws:iam::<account-id>:role/moderne-traces-glue \
    --glue-version 5.0 --worker-type G.1X --number-of-workers 2 --timeout 120 \
    --command Name=glueetl,PythonVersion=3,ScriptLocation=s3://<your-warehouse-bucket>/scripts/build_traces.py \
    --default-arguments '{
        "--datalake-formats": "iceberg",
        "--job-bookmark-option": "job-bookmark-enable",
        "--raw_location": "s3://<your-telemetry-bucket>/",
        "--warehouse": "s3://<your-warehouse-bucket>/",
        "--database": "moderne_telemetry"
    }'
```

`--raw_location` must be the prefix directly above `tenant=` and end in `/`. The job fails on any CSV under it that doesn't follow the export layout, since that file's columns would otherwise join the table.

### 4. Run it, then schedule it

The first run reads the whole bucket once, so it takes longest. Every run after that reads only what's new.

```bash
aws glue start-job-run --job-name moderne-build-traces

aws glue create-trigger --name moderne-build-traces-nightly --type SCHEDULED \
    --schedule "cron(0 2 * * ? *)" --start-on-creation \
    --actions JobName=moderne-build-traces
```

If replication into your bucket is interrupted for more than three days, reset the bookmark with `aws glue reset-job-bookmark --job-name moderne-build-traces`. The next run reads the whole bucket again and replaces each object's rows, so nothing is doubled. To start over from scratch, also drop the three tables before that run.

## Making it production-grade

This example is deliberately minimal. Nothing here is Moderne-specific; it is stock Glue, Iceberg, and S3, so add what your environment needs. For example:

- **Alerting.** An EventBridge rule on Glue *Job State Change* events for `FAILED` or `TIMEOUT`, or CloudWatch metrics emitted from the job (rows ingested, run duration) with alarms on a night that ingested nothing.
- **Managed table maintenance.** The Glue Data Catalog can compact Iceberg tables and expire their snapshots for you, in place of the calls at the end of the script.

## Other approaches

- **A different engine.** Snowflake, BigQuery, Databricks, Fabric, and DuckDB all read this Hive-partitioned CSV layout directly; a dbt model or scheduled task there can do the same header-by-name read and typing.
- **Fixed types.** If you'd rather pin every column's type than infer it, replace `decide_type` with a dictionary of column → type. You then own adding each new trace field to it.
