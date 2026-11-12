# Dashboards: the visualization layer

Each subdirectory here is one BI tool's take on the same reports. It renders the queries in [`../reports`](../reports) in whatever form that tool uses natively: notebook cells, an analysis, a workbook, a report. Pick the one that matches your stack and ignore the rest. If your tool isn't listed, the report SQL ports over the same way.

They all read the same source, the wide `traces` table the [data layer](../data-layer/) produces. Point datasets at it directly and filter on command `type` in the tool, or start from a [report query](../reports). If you'd rather point a dataset at something already typed and scoped, you can define convenience views in Athena ([`../data-layer/athena/views`](../data-layer/athena/views)) or BigQuery ([`../data-layer/bigquery/views`](../data-layer/bigquery/views)), or in your BI tool. Jupyter is the one exception: the notebooks read each report's bundled sample CSV, so they chart without cloud access.

## Tools

| Tool | What it is | Where |
|------|------------|-------|
| Jupyter | One notebook per report, running on bundled sample CSVs. It's the quickest way to see a chart, and needs no cloud access. | [`jupyter/`](jupyter/) |
| QuickSight | The reports in Amazon QuickSight, built on `traces` and packaged as an importable asset bundle: one analysis covering all ten reports, backed by SPICE datasets. | [`quicksight/`](quicksight/) |
| Tableau | Tableau workbooks built on `traces`. | [`tableau/`](tableau/) |
| Power BI | Power BI reports built on `traces`. | [`powerbi/`](powerbi/) |

## Adding another tool

Anything that can query the [data layer](../data-layer/) drops in the same way. Add a `dashboards/<tool>/` folder and point its datasets at `traces`.
