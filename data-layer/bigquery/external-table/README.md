# Nightly job: raw trace CSV to a typed `traces` view

[`build_traces.py`](build_traces.py) is a nightly job. It takes the raw trace CSV you've put in Cloud Storage, writes a fixed copy of each file under a second prefix, and keeps a BigQuery external table and a typed view on top of those copies. The view is called `traces`, and it's the table the reports read.

It starts from files that are already in Cloud Storage. Moderne's export lands in S3 or Azure Blob Storage, so getting it across is up to you. A scheduled `gcloud storage rsync -r s3://<your-telemetry-bucket> gs://<your-bucket>/raw/` is one way.

## What it does

Each run goes through five steps.

1. It only touches new and changed objects. It lists both prefixes and rewrites any raw object whose checksum doesn't match the one recorded on its copy. A normal night handles just that day's uploads, no matter how much history is in the bucket. If an object is delivered again, the new one replaces the earlier copy, and a late replica gets picked up whenever it shows up, even if its modification time is old. The [data layer overview](../../README.md#how-telemetry-lands) covers both cases.
2. It fixes two things BigQuery can't read, in the copy only. A trace tag header `tag.<key>` becomes `tag_<key>`, because BigQuery doesn't allow a period in a column name and the platform tags every run it executes. A timestamp that ends in a bracketed zone id, like `2026-06-10T21:50:25Z[Etc/UTC]` (CLI versions before 4.8.9 wrote these), loses the bracket so BigQuery can parse it. Nothing else in a file changes, and the raw files are never modified.
3. It adds columns as it finds them. Before uploading a file it reads the header, and any name `traces_raw` doesn't have yet becomes a new STRING column first. That way no query ever hits a file with a column the table doesn't know about. Trace tags work the same way, one `tag_<key>` column per key. On the first run it builds `traces_raw` from the first file's header and grows it from there. BigQuery column names are case-insensitive, so two headers that differ only in case end up as one column.
4. It works out each column's type from the values in it. One query over `traces_raw` counts, for every column, how many values are a boolean, an integer, a double, or a timestamp. A column gets the first of those types that at least 99.9% of its non-empty values match, and stays a string if none do. `*id` columns, `tag_*` columns, and the partition keys are always strings.
5. It rebuilds the `traces` view. The view selects every column of `traces_raw` through `SAFE_CAST`, or `SAFE.PARSE_TIMESTAMP` for timestamps. A value that doesn't fit its column's type reads as `NULL` in that cell instead of failing the query, and an empty string reads as `NULL` too. If a column's type changes between runs, only the view changes. No data gets rewritten.

That leaves two objects in BigQuery that the job owns.

`traces_raw` is a BigLake external table over the fixed copies, with every column a STRING. Columns match by header name, so a column can sit at a different position in each file (they move between CLI versions) and a file that's missing a column reads it as `NULL`. That's how one table covers every command type: a `build` file just has no `run*` columns. Hive partitioning reads `tenant`, `source`, `type`, `year`, `month`, and `day` from each object's path as STRING columns, and a filter on them skips the files it rules out. Free-text columns like `agentPrompt` can span lines, so the table allows quoted newlines. You'll also see `_FILE_NAME`, BigQuery's pseudo column for the object a row came from. No report uses it.

`traces` is the typed view the reports read.

Column names keep the header's case (`runStartTime`). BigQuery resolves names case-insensitively, so the reports' lowercase names (`runstarttime`) work unchanged. A new trace field becomes a typed, queryable column on the next run, and there's no DDL to edit.

You can safely rerun the job after a failure. If a copy stopped partway, the next run picks up the objects it hadn't copied, and any column already added to `traces_raw` stays. If `traces_raw` is gone, the run copies the whole bucket again so the table ends up with every header. Each copy replaces its earlier self, so nothing is doubled.

## Setup

Replace `<your-bucket>` (the Cloud Storage bucket holding your trace files), `<project-id>`, and `<region>` throughout. The bucket, the connection, and the dataset all have to be in the same location.

### 1. Create the dataset and the connection

The table reads the bucket through a BigLake connection, so the people who query need access to the dataset, not to the bucket.

```bash
bq mk --dataset --location=<region> moderne_telemetry
bq mk --connection --location=<region> --connection_type=CLOUD_RESOURCE moderne-traces
bq show --connection <project-id>.<region>.moderne-traces
```

The last command prints the connection's `serviceAccountId`. Give that account read access to the bucket:

```bash
gcloud storage buckets add-iam-policy-binding gs://<your-bucket> \
    --member=serviceAccount:<service-account-id> --role=roles/storage.objectViewer
```

### 2. Run the job

The job needs Google [Application Default Credentials](https://cloud.google.com/docs/authentication/application-default-credentials) that can read and write the bucket, create and update tables in the dataset (BigQuery Data Editor on the dataset), and run queries (BigQuery Job User on the project).

```bash
pip install google-cloud-storage google-cloud-bigquery
python build_traces.py \
    --source gs://<your-bucket>/raw/ \
    --destination gs://<your-bucket>/traces/ \
    --dataset moderne_telemetry \
    --connection <project-id>.<region>.moderne-traces
```

`--source` is where your raw files land. It has to be the prefix directly above `tenant=` and end in `/`. Anything under it that doesn't follow the export layout is counted in the log and left alone. `--destination` is a prefix the job owns, in the same bucket or another one. The first run reads your whole history and creates both `traces_raw` and `traces`, so it's the slow one. After that, each run only touches what's new.

### 3. Schedule it

Run step 2 every night, after your copy into the bucket has finished. Use whatever you already schedule jobs with: cron, a CI schedule, or a Cloud Run job started by Cloud Scheduler. A non-zero exit means something needs a look.

To start over, drop `traces_raw` with `bq rm -t moderne_telemetry.traces_raw`. The next run rewrites every copy and recreates the table and the view.

## Making it production-grade

This example is minimal on purpose, so there are no metrics or alarms. It's a Python script, Cloud Storage, and a BigQuery external table, with nothing Moderne-specific in it, so add whatever your environment needs. A few things you might want:

- Alerting on a non-zero exit of the job, and on a night that found nothing new.
- Metadata caching. Every query over `traces_raw` lists the bucket first. Once the bucket holds tens of thousands of objects, BigLake [metadata caching](https://cloud.google.com/bigquery/docs/metadata-caching) takes that listing off the query path. The catch is that a newly copied file only shows up after the next cache refresh.
- A native table if you query it heavily. A CSV external table reads every byte of every file a query touches. A [scheduled query](https://cloud.google.com/bigquery/docs/scheduling-queries) that appends each day's partitions from `traces` into a native table, partitioned by day and clustered by `type`, gives your dashboards columnar reads over the same columns.

## Other approaches

- You could load the files instead of referencing them. `bq load --source_column_match=NAME --column_name_character_map=V2` into a native table also matches columns by name, and the V2 character map renames `tag.<key>` for you, so it reads the raw files as they are into STRING columns. The catch is that you have to track which objects you've loaded, and the hive keys don't show up as columns.
- If you'd rather pin every column's type than infer it, replace `decide_type` with a dictionary of column to type. Then you're the one adding each new trace field to it.
