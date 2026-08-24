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

Ten sheets, one per report, plus a KPI landing sheet. Every dataset is a report query from [`../../reports`](../../reports) with the schema qualified as `telemetry.traces` — see each report's folder for the query, its documentation, sample data, and a screenshot.

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

A thirteenth dataset, **`traces`**, is a direct relational table over `telemetry.traces` (all 98 columns). It is declared in the analysis but no visual uses it — it's there as a starting point for building your own sheets against the raw table.

Other analysis-level details: NITRO theme, `LENIENT` validation, no parameters, no filter groups, and one calculated field — `Built Tool + Version` on the `Build Tool Versions` dataset, defined as `concat({Build Tool}, ' ', {Tool Version})`.

All 13 datasets use **SPICE** import mode, so they hold a snapshot rather than querying Athena live. The bundle carries no refresh schedules; after import, refresh each dataset once to populate it, then schedule refreshes to taste. It also carries no permissions or tags, so whoever runs the import becomes the sole owner of every asset.

## Prerequisites

- An **Athena data source** reachable from QuickSight, with a workgroup whose query-result location QuickSight can write to. The bundle's data source is named `BI Telemetry` and points at a workgroup called `telemetry`.
- A **schema** (the bundle assumes `telemetry`) containing the wide **`traces`** table. Stand it up with the [data layer](../../data-layer/), or produce the same table another way — the [`traces` contract](../../README.md#the-traces-table) is what matters.
- **QuickSight permission to create SPICE datasets**, plus enough SPICE capacity for 13 datasets. The importing principal needs `quicksight:StartAssetBundleImportJob` and create permissions on analyses, datasets, and data sources.

The 12 custom-SQL datasets read 22 columns from `traces`:

`type`, `path`, `developer`, `runid`, `runrecipeid`, `runrecipeinstancename`, `runstarttime`, `runfileswithfixresults`, `runestimatedefforttimesavingsms`, `commitid`, `commitstarttime`, `commitoutcome`, `buildid`, `buildstarttime`, `buildoutcome`, `buildmavenversion`, `buildgradleversion`, `buildbazelversion`, `builddotnetversion`, `buildpythonversion`, `buildnodeversion`, `month`

The `traces` table has 98 columns in total; the other 76 go unused by these datasets, though the raw `traces` dataset declares all of them. See the [trace.csv reference](https://docs.moderne.io/user-documentation/moderne-cli/references/trace-csv) for what each column means.

## Importing

### 1. Substitute the placeholders

From this directory, replace the account ID and region everywhere they appear (14 files — all 13 datasets and the analysis):

```bash
grep -rl '<AWS_ACCOUNT_ID>\|<REGION>' analysis dataset datasource | xargs sed -i.bak -e 's/<AWS_ACCOUNT_ID>/123456789012/g' -e 's/<REGION>/us-east-1/g' && find . -name '*.bak' -delete
```

If your Athena schema isn't `telemetry`, rewrite the 15 `telemetry.traces` references in the SQL plus the `"schema"` field on the raw `traces` dataset:

```bash
grep -rl 'telemetry' analysis dataset | xargs sed -i.bak -e 's/telemetry\.traces/my_schema.traces/g' -e 's/"schema": "telemetry"/"schema": "my_schema"/g' && find . -name '*.bak' -delete
```

And if your workgroup isn't `telemetry`, edit `"workGroup"` in `datasource/0727c710-7910-4a77-bfce-a0ad18953eea.json` — or override it at import time (see below). Do these as a copy, not in place, if you want the repo's placeholders to stay intact.

### 2. Zip and import

Zip the three directories at their common root — no wrapping folder, or the import job won't find the assets:

```bash
zip -r ../../moderne-quicksight-bundle.zip analysis dataset datasource
```

```bash
aws quicksight start-asset-bundle-import-job \
  --region us-east-1 \
  --aws-account-id 123456789012 \
  --asset-bundle-import-job-id moderne-bi-templates-import-1 \
  --asset-bundle-import-source-bytes fileb://../../moderne-quicksight-bundle.zip \
  --failure-action ROLLBACK
```

The call returns immediately with a `JobStatus` of `QUEUED_FOR_IMMEDIATE_EXECUTION`. Poll for the outcome — a failed job lists every offending asset under `Errors`:

```bash
aws quicksight describe-asset-bundle-import-job \
  --region us-east-1 \
  --aws-account-id 123456789012 \
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

## Round-tripping

Re-exporting from QuickSight after import does **not** reproduce these files. The export is minified rather than pretty-printed, and QuickSight assigns fresh UUIDs to every asset (which also renames every file). A re-export therefore diffs as a complete rewrite of all 15 files, not as the edits you actually made. Treat the bundle here as a starting template to import from, and keep your own exports somewhere else.
