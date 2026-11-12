# Convenience views (optional)

These are optional views over [`traces`](../glue/). No report depends on them: every query in [`../../../reports`](../../../reports) reads `traces` directly and does its own `type` filtering and casts, so each one stands alone.

They're here for one case: you'd rather point a BI tool (or an ad-hoc query) at something already scoped and renamed than repeat that logic in every dataset. They do two things:

- They pin the `type`. Each view filters to the command type(s) it needs, so re-emitted stages can't double-count metrics.
- They give columns friendlier names. `runrecipeid` becomes `recipe_id`, and so on.

The `traces` columns are already typed, so the views don't cast anything. They only filter and rename.

## The views

| View | Type(s) | Grain | Useful for |
|------|---------|-------|------------|
| [`v_runs`](v_runs.sql) | `run` | one row per recipe run | recipe adoption, top recipes, per-user activity |
| [`v_commits`](v_commits.sql) | `commit` | one row per commit (embeds its run) | committed impact, hours saved, security remediation |
| [`v_builds`](v_builds.sql) | build-bearing (`build,run,apply,add,commit,publish`) | one row per trace; use `COUNT(DISTINCT buildid)` to count a build once | build health, build tool distribution |
| [`v_publish`](v_publish.sql) | `publish` | one row per LST publication | mass-ingest volume |
| [`v_mcp`](v_mcp.sql) | `mcp` | one row per MCP tool call | MCP / agent tool usage |
| [`v_sync`](v_sync.sql) | `sync` | one row per repo sync | clone and LST-download analysis |

`apply` and `add` are intermediate git stages that aren't much use on their own, so they're folded into the `v_commits` chain. Query `traces` directly if you need them separately.

## Setup

The views are independent, so create only the ones you want, with your database selected as the Athena query context (`USE moderne_telemetry;`). If a view fails with a column-not-found error, `traces` doesn't have those columns yet. They show up on the first nightly run after a trace that has them.

## Or build the same thing in your BI tool

Nothing requires these to live in Athena. The same logic works as a Tableau data source, a Power BI model, or a QuickSight dataset, which keeps the definitions next to the dashboards that use them. See [`../../../dashboards`](../../../dashboards).
