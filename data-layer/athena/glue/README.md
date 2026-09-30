# Glue job — raw CSV → typed Iceberg `traces`

[`build_traces.py`](build_traces.py) is a nightly AWS Glue (Spark) job that turns the raw trace CSV into the typed `traces` table the reports read. Read it top to bottom; the module docstring explains the design.

## What it does

Each run:

1. **Reads only new objects.** A Glue [job bookmark](https://docs.aws.amazon.com/glue/latest/dg/monitor-continuations.html) remembers which CSV objects earlier runs read, so a normal night reads just that day's uploads, however much history the bucket holds. Each object is read by its own header, so every command type's columns land by name.
2. **Keeps every raw row in `traces_raw`.** New rows are appended, all as strings, to an Iceberg table. An object that is delivered again replaces its earlier rows, and a late upload lands in the day its key names, so there is no backfill step.
3. **Decides each column's type from all its history.** Each column gets one type (`boolean`, `bigint`, `double`, `timestamp`, or `string`): the first type that at least 99.9% of its non-null values match. Partition keys, `*id` columns, and `tag_*` columns always stay strings. Running per-column counts in a small `traces_typing` table mean each night only the new rows are counted.
4. **Appends to `traces`, rebuilding only when it must.** On a normal night the new rows are typed and appended, and a new field is added as a column. The job rebuilds `traces` from `traces_raw` only on the first run, when a column's type changes (say, a text value turns up in a column that was all numbers), or when a file was delivered again. A value that doesn't match its column's type becomes `NULL`.
5. **Maintains the tables.** It expires snapshots older than a day and compacts the small files nightly appends leave.

So a normal night costs time in proportion to that night's uploads, not to your history. Only the occasional rebuild reads everything, and it reads compact Parquet from `traces_raw`, not the CSV.

Column names are the CSV headers lowercased (`runStartTime` → `runstarttime`, `tag.team` → `tag_team`), which is how Athena exposes them anyway. **A new trace field becomes a typed, queryable column on the next run** with no DDL to edit. The job creates the database and all three tables in the Glue Data Catalog itself, so there is no DDL to run.

If the job fails partway, the bookmark does not advance, so the next run reads the same objects again. They count as delivered again, so the job replaces their rows and rebuilds, and nothing is doubled.

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

To start over from scratch (for example after changing the typing rules), reset the bookmark with `aws glue reset-job-bookmark --job-name moderne-build-traces` and drop the three tables before the next run.

## Making it production-grade

This example is deliberately minimal. Nothing here is Moderne-specific; it is stock Glue, Iceberg, and S3, so add what your environment needs. For example:

- **Alerting.** An EventBridge rule on Glue *Job State Change* events for `FAILED` or `TIMEOUT`, or CloudWatch metrics emitted from the job (rows ingested, run duration) with alarms on a night that ingested nothing.
- **Managed table maintenance.** The Glue Data Catalog can compact Iceberg tables and expire their snapshots for you, in place of the calls at the end of the script.

## Other approaches

- **A different engine.** Snowflake, BigQuery, Databricks, Fabric, and DuckDB all read this Hive-partitioned CSV layout directly; a dbt model or scheduled task there can do the same header-by-name read and typing.
- **Fixed types.** If you'd rather pin every column's type than infer it, replace `decide_types` with a dictionary of column → type. You then own adding each new trace field to it.
