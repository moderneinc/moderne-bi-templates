# Job: raw CSV in Cloud Storage → external `traces_raw` → typed `traces` view

[`build_traces.py`](build_traces.py) is a nightly job that reads the raw trace CSV from the Cloud Storage prefix you land it in, writes a copy BigQuery can read under a second prefix, and keeps a BigQuery external table and a typed view over that copy, so the reports read the same `traces` here as on Athena.

It starts from files already in Cloud Storage. Moderne's export lands in S3 or Azure Blob Storage, so move it across with whatever you already use; one way is a scheduled `gcloud storage rsync -r s3://<your-telemetry-bucket> gs://<your-bucket>/raw/`.

## What it does

Each run:

1. **Reads only new and changed objects.** It lists both prefixes and rewrites each raw object whose checksum isn't the one recorded on its copy. A normal night touches just that day's uploads, however much history the bucket holds. An object that is delivered again replaces its earlier copy, and a late replica is picked up whenever it appears, however old its modification time, which covers both delivery cases in the [data layer overview](../../README.md#how-telemetry-lands).
2. **Fixes two things BigQuery can't read, in the copy.** A trace tag header `tag.<key>` becomes `tag_<key>`, because BigQuery doesn't allow a period in a column name and the platform tags every run it executes. A timestamp that ends in a bracketed zone id (`2026-06-10T21:50:25Z[Etc/UTC]`, written by CLI versions before 4.8.9) loses the bracket, so BigQuery can parse it. Nothing else in a file changes, and the raw files are never modified.
3. **Adds a column the moment it sees one.** It reads each file's header before uploading the file, and a header name that `traces_raw` doesn't have becomes a new STRING column first, so no query ever meets a file with an unknown column. Trace tags arrive this way too, one `tag_<key>` column per tag key. On the first run it creates `traces_raw` from the first file's header and grows it from there. BigQuery column names are case-insensitive, so two headers that differ only in case share one column.
4. **Decides each column's type from all its values.** One query over `traces_raw` counts, per column, how many values are a boolean, an integer, a double, or a timestamp. A column takes the first of those that at least 99.9% of its non-empty values match, and otherwise stays a string. `*id` columns, `tag_*` columns, and the partition keys always stay strings. These are the Glue job's rules, so both engines type a column the same way.
5. **Rebuilds the `traces` view.** `traces` selects every column of `traces_raw` through `SAFE_CAST`, or `SAFE.PARSE_TIMESTAMP` for timestamps, so a value that doesn't match its column's type reads as `NULL` in that cell rather than failing the query, and an empty string reads as `NULL`. A type that changes between runs only changes the view; no data is rewritten.

The two objects it owns:

- **`traces_raw`**: a BigLake external table over the fixed copies, every column STRING. Columns match by header name, so a column may sit at a different position in each file (they move between CLI versions) and a file that lacks a column reads it as `NULL`. That is what lets one table span every command type: a `build` file simply has no `run*` columns. Hive partitioning reads `tenant`, `source`, `type`, `year`, `month`, `day` from each object's path as STRING columns, and a filter on them skips the files it rules out. Free-text columns such as `agentPrompt` span lines, so the table allows quoted newlines. `_FILE_NAME` is BigQuery's pseudo column naming the object each row came from, the counterpart of the Athena layer's `_source_key`; no report reads it.
- **`traces`**: the typed view the reports read.

Column names keep the header's case (`runStartTime`). BigQuery resolves column names case-insensitively, so the reports' lowercase names (`runstarttime`) work unchanged. **A new trace field becomes a typed, queryable column on the next run** with no DDL to edit.

The job is safe to rerun after a failure. A copy that stopped partway resumes with the objects it hadn't copied, and a column added to `traces_raw` stays added. If `traces_raw` doesn't exist, the run copies the whole bucket again, so that the table ends up with every header; a copy replaces its earlier self, so nothing is doubled.

## Setup

Replace `<your-bucket>` (the Cloud Storage bucket holding your trace files), `<project-id>`, and `<region>` throughout. The bucket, the connection, and the dataset must be in the same location.

### 1. Create the dataset and the connection

The table reads the bucket through a BigLake connection, so people who query need access to the dataset rather than the bucket.

```bash
bq mk --dataset --location=<region> moderne_telemetry
bq mk --connection --location=<region> --connection_type=CLOUD_RESOURCE moderne-traces
bq show --connection <project-id>.<region>.moderne-traces
```

The last command prints the connection's `serviceAccountId`. Give it read access to the bucket:

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

`--source` is where your raw files land. It must be the prefix directly above `tenant=` and end in `/`; objects under it that don't follow the export layout are counted in the log and left alone. `--destination` is a prefix the job owns, in the same or another bucket. The first run reads the whole history and creates both `traces_raw` and `traces`, so it takes longest; every run after that touches only what is new.

### 3. Schedule it

Run step 2 nightly, after your copy into the bucket, from wherever you schedule jobs: a cron entry, a CI schedule, or a Cloud Run job started by Cloud Scheduler. Treat a non-zero exit as something to look at.

To start over from scratch, drop `traces_raw` with `bq rm -t moderne_telemetry.traces_raw`; the next run rewrites every copy and recreates the table and the view.

## Making it production-grade

This example is deliberately minimal, with no metrics or alarms. Nothing here is Moderne-specific; it is a Python script, Cloud Storage, and a BigQuery external table, so add what your environment needs. For example:

- **Alerting.** A notification on a non-zero exit of the job, and on a night that found nothing new.
- **Metadata caching.** Each query over `traces_raw` lists the bucket first. Once the bucket holds tens of thousands of objects, BigLake [metadata caching](https://cloud.google.com/bigquery/docs/metadata-caching) takes that off the query path, at the cost of a copied file appearing only after the next cache refresh.
- **A native table for heavy use.** A CSV external table reads every byte of every file a query touches. A [scheduled query](https://cloud.google.com/bigquery/docs/scheduling-queries) that appends each day's partitions from `traces` into a native table partitioned by day and clustered by `type` gives dashboards columnar reads over the same columns.

## Other approaches

- **Load instead of reference.** `bq load --source_column_match=NAME --column_name_character_map=V2` into a native table also matches columns by name, and the V2 character map renames `tag.<key>` for you, so it reads the raw files unchanged into STRING columns. You then own tracking which objects you have loaded, and the hive keys aren't added as columns.
- **Fixed types.** If you'd rather pin every column's type than infer it, replace `decide_type` with a dictionary of column → type. You then own adding each new trace field to it.
