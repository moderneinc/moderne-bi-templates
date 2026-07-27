# Dashboards: the visualization layer

The presentation layer of the repo. Each subdirectory is **one BI tool's take on the same reports**: it renders the queries in [`../reports`](../reports) using whatever that tool natively speaks (notebook cells, an analysis, a workbook, a report). Pick the one that matches your stack; ignore the rest. If your tool isn't listed, the report SQL ports to it the same way.

They all read the same source: the wide **`traces`** table the [data layer](../data-layer/) produces. Point datasets at it directly and scope by command `type` in the tool, or start from a [report query](../reports). If you'd rather point a dataset at a pre-typed, pre-scoped surface, you can optionally define convenience views, either in Athena ([`../data-layer/athena/views`](../data-layer/athena/views)) or natively in your BI tool. (Jupyter is the exception: the notebooks read each report's bundled sample CSV, so they chart without cloud access.)

## Tools

| Tool | What it is | Where |
|------|------------|-------|
| **Jupyter** | One notebook per report, running on bundled sample CSVs. The quickest way to see a chart, with no cloud access needed. | [`jupyter/`](jupyter/) |
| **QuickSight** | Amazon QuickSight analyses over `traces`. | [`quicksight/`](quicksight/) |
| **Tableau** | Tableau workbooks over `traces`. | [`tableau/`](tableau/) |
| **Power BI** | Power BI reports over `traces`. | [`powerbi/`](powerbi/) |

## Adding another tool

Anything else that can query the [data layer](../data-layer/) drops in the same way: add a `dashboards/<tool>/` folder and point its datasets at `traces`.
