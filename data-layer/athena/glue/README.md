# Glue job: raw trace CSV to a typed Iceberg `traces` table

[`build_traces.py`](build_traces.py) is a nightly AWS Glue (Spark) job that turns the raw trace CSV into the typed `traces` table the reports read.

## What it does

Each run goes through seven steps.

1. It only reads new objects. A Glue [job bookmark](https://docs.aws.amazon.com/glue/latest/dg/monitor-continuations.html) remembers which CSV objects earlier runs read, so a normal night reads just that day's uploads, however much history the bucket holds. Each object is read by its own header, so every command type's columns land by name.
2. It catches late replicas. A replica can land after a run has started but still carry an older last-modified time, because S3 replication keeps the source's timestamp. The bookmark would skip it. To catch it, each run also lists the objects modified in the last three days and reads any that `traces_raw` doesn't have.
3. It keeps every raw row in `traces_raw`. New rows are appended, all as strings, to an Iceberg table. If an object is delivered again, its rows replace the earlier ones. A late upload lands in the day its key names.
4. It decides each column's type from all its history. Each column gets one type (`boolean`, `bigint`, `double`, `timestamp`, or `string`): the first type that at least 99.9% of its non-null values match. Partition keys, `*id` columns, and `tag_*` columns always stay strings. Timestamps may end in `Z` or an offset, with or without a zone id (`2026-06-10T21:50:25Z[Etc/UTC]`, `2026-06-10T16:50:25-05:00[America/Chicago]`), and are stored in UTC. Running per-column counts in a small `traces_typing` table means each night only the new and replaced rows are counted. The counts are saved with a fingerprint of the rules, so if you change a rule, the next run that ingests rows recounts from `traces_raw`.
5. It appends to `traces`. On a normal night the new rows are typed and appended, and a new field is added as a column. If a file was delivered again, its rows are replaced in place. The `_source_key` column makes that possible: it names the object each row came from. It's the job's bookkeeping, not a trace field, and no report reads it.
6. It rebuilds `traces` only when it has to. That happens on the first run, or when a column's type changes. One stray value doesn't trigger a rebuild. A column changes type only once fewer than 99.9% of all the values it has ever held match it. Until then, a value that doesn't match its column's type becomes `NULL`.
7. It maintains the tables. It expires snapshots older than a day and compacts the small files that nightly appends leave behind.

Column names are the CSV headers lowercased (`runStartTime` becomes `runstarttime`, `tag.team` becomes `tag_team`), which is how Athena exposes them anyway. A new trace field becomes a typed, queryable column on the next run. The job creates the database and all three tables in the Glue Data Catalog itself, so there's no DDL to run.

If your export has never contained a given command type (say, no `mod git commit` traces yet), `traces` has none of that type's columns. A query that names one fails with a column-not-found error instead of returning no rows. The columns appear on the first run after such a trace arrives.

You can safely rerun the job after a failure. Every table is written before the bookmark advances. If a run fails before then, the next run reads the same objects again and replaces their rows, so nothing is doubled. Snapshot expiry and compaction run after the bookmark advances. If one of those fails, the run shows as `FAILED`, but the tables are already complete, and the next run does the maintenance.

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

`--raw_location` has to be the prefix directly above `tenant=`, and it must end in `/`. The job fails on any object under it that doesn't follow the export layout, because that file's columns would otherwise join the table.

### 4. Run it, then schedule it

The first run reads the whole bucket once, so it takes the longest. Every run after that reads only what's new.

```bash
aws glue start-job-run --job-name moderne-build-traces

aws glue create-trigger --name moderne-build-traces-nightly --type SCHEDULED \
    --schedule "cron(0 2 * * ? *)" --start-on-creation \
    --actions JobName=moderne-build-traces
```

If replication into your bucket is interrupted for more than three days, reset the bookmark with `aws glue reset-job-bookmark --job-name moderne-build-traces`. The next run reads the whole bucket again and replaces each object's rows, so nothing is doubled. To start over from scratch, also drop the three tables before that run.

## Making it production-grade

This example is minimal, so there are no metrics or alarms. It's stock Glue, Iceberg, and S3, with nothing Moderne-specific in it, so add whatever your environment needs. A couple of ideas:

- Alerting. Use an EventBridge rule on Glue *Job State Change* events for `FAILED` or `TIMEOUT`, or emit CloudWatch metrics from the job (rows ingested, run duration) and alarm on a night that ingested nothing.
- Managed table maintenance. The Glue Data Catalog can compact Iceberg tables and expire their snapshots for you, in place of the calls at the end of the script.

## Other approaches

- A different engine. [`../../bigquery/`](../../bigquery/) does this for Google BigQuery. Snowflake, Databricks, Fabric, and DuckDB all read this Hive-partitioned CSV layout directly, and a dbt model or scheduled task there can do the same header-by-name read and typing.
- Fixed types. If you'd rather pin every column's type than infer it, replace `decide_type` with a dictionary of column to type. Then you're the one adding each new trace field to it.
