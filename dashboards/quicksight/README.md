# QuickSight dashboards

Amazon QuickSight analyses over the `traces` table, shipped as a sanitized [asset bundle](https://docs.aws.amazon.com/quicksight/latest/developerguide/asset-bundle-ops.html) export. Importing it creates one analysis, **Moderne BI Templates**, backed by 13 SPICE datasets and a single Athena data source.

> **This bundle will not import as-is.** Real identifiers have been stripped: every ARN in `analysis/` and `dataset/` carries the literal placeholders `<AWS_ACCOUNT_ID>` and `<REGION>`, which are not valid ARN components. `StartAssetBundleImportJob` rejects the bundle until you [substitute them](#1-substitute-the-placeholders).

## What's in the bundle

```
dashboards/quicksight/
├── analysis/      # 1 file  — the "Moderne BI Templates" analysis (10 sheets, 17 visuals)
├── dataset/       # 13 files — 12 custom-SQL datasets + the raw `traces` table
└── datasource/    # 1 file  — "BI Telemetry", an Athena data source
```

Filenames are the asset UUIDs, which is what a QuickSight export produces and what the import job expects. There is no manifest — the three directories *are* the bundle, zipped at their common root. Additional analyses drop in as more files in the same directories.

The JSON is pretty-printed (2-space indent, original key order, trailing newline) purely so diffs are readable; whitespace has no effect on import. Each `sqlQuery` remains a single escaped string, which JSON gives no way around.

## What the analysis shows

Ten sheets, one per report, plus a KPI landing sheet. Every dataset is a report query from [`../../reports`](../../reports) with the schema qualified as `moderne_telemetry.traces` — see each report's folder for the query, its documentation, sample data, and a screenshot.

| Sheet | Visuals | Dataset(s) | Report |
|-------|---------|------------|--------|
| Dashboard KPIs | 6 KPI tiles (untitled — labels come from their fields) + combo chart "Monthly Trend" | `Dashboard KPIs Summary`, `Dashboard KPIs Trend` | [Dashboard KPIs](../../reports/dashboard-kpis/) |
| Build Tool Distribution | bar "Build Tool Versions (by Repos)", pie "Build Tool Distribution (by Repos)" | `Build Tool Versions`, `Build Tool Distribution` | [Build Tool Distribution](../../reports/build-tool-distribution/) |
| Build Success Trend | combo "Build Success Trend" | `Build Success Trend` | [Build Success Trend](../../reports/build-success-trend/) |
| Commit Activity | combo "Commit Activity" | `Commit Activity` | [Commit Activity](../../reports/commit-activity/) |
| Commit Trend | combo "Commit Trend" | `Commit Trend` | [Commit Trend](../../reports/commit-trend/) |
| Recipe Run Trends | bar "Recipe Run Trend" | `Recipe Run Trend` | [Recipe Run Trend](../../reports/recipe-run-trend/) |
| Security Recipe Run Trends | combo "Security Recipe Run Trend" | `Security Recipe Run Trend` | [Security Recipe Run Trend](../../reports/security-recipe-run-trend/) |
| Top Recipes | bar "Top Recipes" | `Top Recipes` | [Top Recipes](../../reports/top-recipes/) |
| Top Recipes with Commits | bar "Top Recipes with Commits" | `Top Recipes with Commits` | [Top Recipes with Commits](../../reports/top-recipes-with-commits/) |
| Top Users | bar "Top Users" | `Top Users` | [Top Users](../../reports/top-users/) |

A thirteenth dataset, **`traces`**, is a direct relational table over `moderne_telemetry.traces` (all 98 columns). It is declared in the analysis but no visual uses it — it's there as a starting point for building your own sheets against the raw table.

Other analysis-level details: NITRO theme, `LENIENT` validation, no parameters, no filter groups, and one calculated field — `Built Tool + Version` on the `Build Tool Versions` dataset, defined as `concat({Build Tool}, ' ', {Tool Version})`.

All 13 datasets use **SPICE** import mode, so they hold a snapshot rather than querying Athena live. The bundle deliberately carries no refresh schedules, permissions, or tags — see [After import](#after-import) for what to set up once the assets land.

## Prerequisites

- An **Athena data source** reachable from QuickSight, with a workgroup whose query-result location QuickSight can write to. The bundle's data source is named `BI Telemetry` and points at a workgroup called `telemetry`. The workgroup name is arbitrary — the repo sets no convention for it, so use whichever one you created in [step 2 of the Athena setup](../../data-layer/athena/README.md#2-create-an-athena-workgroup).
- A **schema** containing the wide **`traces`** table. The bundle qualifies its SQL as `moderne_telemetry.traces`, matching the Glue database the [data layer's Glue job](../../data-layer/athena/glue/) creates — so if you followed that walkthrough, the datasets resolve as-is. Produce the table another way and the [`traces` contract](../../README.md#the-traces-table) is what matters; rename the schema below if yours differs.
- **QuickSight permission to create SPICE datasets**, plus enough SPICE capacity for 13 datasets. The importing principal needs `quicksight:StartAssetBundleImportJob` and create permissions on analyses, datasets, and data sources.

The 12 custom-SQL datasets read 22 columns from `traces`:

`type`, `path`, `developer`, `runid`, `runrecipeid`, `runrecipeinstancename`, `runstarttime`, `runfileswithfixresults`, `runestimatedefforttimesavingsms`, `commitid`, `commitstarttime`, `commitoutcome`, `buildid`, `buildstarttime`, `buildoutcome`, `buildmavenversion`, `buildgradleversion`, `buildbazelversion`, `builddotnetversion`, `buildpythonversion`, `buildnodeversion`, `month`

The `traces` table has 98 columns in total; the other 76 go unused by these datasets, though the raw `traces` dataset declares all of them. See the [trace.csv reference](https://docs.moderne.io/user-documentation/moderne-cli/references/trace-csv) for what each column means.

## Importing

Every command below reads two shell variables, named to match the placeholders in the JSON. Set them once:

```bash
export AWS_ACCOUNT_ID=123456789012   # your 12-digit QuickSight account ID
export REGION=us-east-1              # the region your QuickSight account lives in
```

### 1. Substitute the placeholders

From this directory, replace the account ID and region everywhere they appear (14 files — all 13 datasets and the analysis):

```bash
grep -rl '<AWS_ACCOUNT_ID>\|<REGION>' analysis dataset datasource | xargs sed -i.bak -e "s/<AWS_ACCOUNT_ID>/$AWS_ACCOUNT_ID/g" -e "s/<REGION>/$REGION/g" && find . -name '*.bak' -delete
```

The data layer's Glue job creates whichever database its `--database` argument names. The walkthrough uses `moderne_telemetry`, and the bundle matches it, so this step is a no-op if you followed that walkthrough. If you named yours something else, rewrite the 15 `moderne_telemetry.traces` references in the SQL plus the `"schema"` field on the raw `traces` dataset:

```bash
grep -rl moderne_telemetry dataset | xargs sed -i.bak -e 's/moderne_telemetry\.traces/my_schema.traces/g' -e 's/"schema": "moderne_telemetry"/"schema": "my_schema"/g' && find . -name '*.bak' -delete
```

The workgroup is tracked separately from the schema, so it is deliberately left as plain `telemetry` and the command above will not touch it. If yours differs, edit `"workGroup"` in `datasource/0727c710-7910-4a77-bfce-a0ad18953eea.json` — or override it at import time (see below). Work on a copy, not in place, if you want the repo's placeholders to stay intact.

### 2. Zip and import

Zip the three directories at their common root — no wrapping folder, or the import job won't find the assets:

```bash
zip -r ../../moderne-quicksight-bundle.zip analysis dataset datasource
```

```bash
aws quicksight start-asset-bundle-import-job \
  --region "$REGION" \
  --aws-account-id "$AWS_ACCOUNT_ID" \
  --asset-bundle-import-job-id moderne-bi-templates-import-1 \
  --asset-bundle-import-source-bytes fileb://../../moderne-quicksight-bundle.zip \
  --failure-action ROLLBACK
```

The call returns immediately with a `JobStatus` of `QUEUED_FOR_IMMEDIATE_EXECUTION`. Poll for the outcome — a failed job lists every offending asset under `Errors`:

```bash
aws quicksight describe-asset-bundle-import-job \
  --region "$REGION" \
  --aws-account-id "$AWS_ACCOUNT_ID" \
  --asset-bundle-import-job-id moderne-bi-templates-import-1
```

Use a fresh `--asset-bundle-import-job-id` for each attempt; IDs can't be reused. `--asset-bundle-import-source-bytes` inlines the zip and caps at 20 MB (this bundle is ~180 KB); for anything larger, upload to S3 and pass `--asset-bundle-import-source S3Uri=s3://...` instead.

### Overriding instead of editing

`--override-parameters file://overrides.json` supplies values at import time rather than editing files. It covers the data source's connection parameters and credentials, and the names and IDs of the imported assets:

```json
{
  "DataSources": [
    {
      "DataSourceId": "0727c710-7910-4a77-bfce-a0ad18953eea",
      "Name": "BI Telemetry",
      "DataSourceParameters": {
        "AthenaParameters": {
          "WorkGroup": "my-workgroup"
        }
      }
    }
  ]
}
```

That handles the **workgroup**, but not the two things most likely to block you: overrides can't rewrite the `<REGION>`/`<AWS_ACCOUNT_ID>` placeholders inside the ARNs, and dataset overrides accept only `DataSetId` and `Name` — there's no knob for the Athena schema. Both still need the substitutions in step 1.

## After import

A successful import creates the assets but leaves them empty and private. Three things are worth doing, in order. These commands reuse the `$AWS_ACCOUNT_ID` and `$REGION` variables set [above](#importing).

### 1. Populate SPICE

Every dataset imports empty — visuals stay blank until each one is ingested once. The dataset IDs are the filenames in `dataset/`, so the whole set can be kicked off in a loop:

```bash
for f in dataset/*.json; do id=$(basename "$f" .json); aws quicksight create-ingestion --region "$REGION" --aws-account-id "$AWS_ACCOUNT_ID" --data-set-id "$id" --ingestion-id "initial-load-$id" --ingestion-type FULL_REFRESH; done
```

Ingestion IDs must be unique per dataset, hence the suffix. Poll one with `describe-ingestion` if a dataset looks wrong — a query that fails against your schema surfaces there, not at import time.

### 2. Schedule refreshes

This is the step the bundle intentionally leaves out: a schedule's `StartAfterDateTime` has to be in the future, so any date committed to the repo would go stale and start failing imports. Create one per dataset at whatever cadence suits your telemetry export:

```bash
aws quicksight create-refresh-schedule \
  --region "$REGION" \
  --aws-account-id "$AWS_ACCOUNT_ID" \
  --data-set-id 4716a22e-7f2b-4b0f-9ae5-575c91ec21e9 \
  --schedule '{
    "ScheduleId": "daily-full-refresh",
    "RefreshType": "FULL_REFRESH",
    "ScheduleFrequency": {
      "Interval": "DAILY",
      "TimeOfTheDay": "06:00",
      "Timezone": "America/Los_Angeles"
    }
  }'
```

Daily suits the nightly data-layer job. Refreshing more often than the data layer lands new partitions just re-scans Athena for the same rows.

### 3. Share it

The bundle ships no permissions, so the principal that ran the import is the sole owner of all 15 assets. Granting access to the analysis alone is not enough — QuickSight resolves permissions per asset, so a viewer who can open the analysis but can't read its datasets gets errors instead of visuals. Grant down the whole chain: the analysis, all 13 datasets, and the data source.

```bash
aws quicksight update-analysis-permissions \
  --region "$REGION" \
  --aws-account-id "$AWS_ACCOUNT_ID" \
  --analysis-id c47fe26c-0ba2-4888-80dd-d89557138865 \
  --grant-permissions \
    Principal=arn:aws:quicksight:$REGION:$AWS_ACCOUNT_ID:group/default/analysts,Actions=quicksight:DescribeAnalysis,quicksight:QueryAnalysis,quicksight:DescribeAnalysisPermissions
```

Datasets take the equivalent read set via `update-data-set-permissions` (`DescribeDataSet`, `DescribeDataSetPermissions`, `PassDataSet`, `DescribeIngestion`, `ListIngestions`), and the data source via `update-data-source-permissions` (`DescribeDataSource`, `DescribeDataSourcePermissions`, `PassDataSource`). See the [QuickSight permissions docs](https://docs.aws.amazon.com/quicksight/latest/developerguide/security_iam_service-with-iam.html) for the full action lists.

To hand this to people who shouldn't edit it, publish a read-only dashboard from the analysis with `create-dashboard --source-entity`, and share that instead.

### Optional: switch to DIRECT_QUERY

SPICE is the deliberate default here. These queries carry no date filter by design, so under DIRECT_QUERY every visual interaction re-scans every partition in Athena, where cost tracks bytes scanned — ten sheets of that adds up fast. SPICE confines Athena reads to refresh time, which is bounded and predictable, at the cost of showing a snapshot.

If you want live data anyway, change `"importMode": "SPICE"` to `"importMode": "DIRECT_QUERY"` in each dataset **before** importing, and bound the scans by adding a partition predicate (`AND year = '2026'`) to each `sqlQuery`. See the [data layer performance notes](../../data-layer/athena/README.md#performance).

## Round-tripping

Re-exporting from QuickSight after import does **not** reproduce these files. The export is minified rather than pretty-printed, and QuickSight assigns fresh UUIDs to every asset (which also renames every file). A re-export therefore diffs as a complete rewrite of all 15 files, not as the edits you actually made. Treat the bundle here as a starting template to import from, and keep your own exports somewhere else.
