# Convenience views (optional)

Optional views over [`traces`](../external-table/). **No report depends on them**: every query in [`../../../reports`](../../../reports) reads `traces` directly and carries its own `type` scoping and casts, so it stays self-contained.

These exist for one case: you would rather point a BI tool (or an ad-hoc query) at a pre-scoped, renamed surface than restate that logic in every dataset. They encapsulate:

- **`type` scoping**: each view pins the command type(s) it needs, so the stage re-emission that would double-count metrics can't happen downstream.
- **Friendly names**: `runRecipeId` becomes `recipe_id`, and so on.

(`traces` columns are already typed, so the views don't cast; they're pure scoping and renaming.)

## The views

| View | Type(s) | Grain | Useful for |
|------|---------|-------|------------|
| [`v_runs`](v_runs.sql) | `run` | one row per recipe run | recipe adoption, top recipes, per-user activity |
| [`v_commits`](v_commits.sql) | `commit` | one row per commit (embeds its run) | committed impact, hours saved, security remediation |
| [`v_builds`](v_builds.sql) | build-bearing (`build,run,apply,add,commit,publish`) | one row per trace; `COUNT(DISTINCT buildId)` to count a build once | build health, build tool distribution |
| [`v_publish`](v_publish.sql) | `publish` | one row per LST publication | mass-ingest volume |
| [`v_mcp`](v_mcp.sql) | `mcp` | one row per MCP tool call | MCP / agent tool usage |
| [`v_sync`](v_sync.sql) | `sync` | one row per repo sync | clone and LST-download analysis |

`apply` and `add` are intermediate git stages with little standalone value and are folded into the `v_commits` chain; query `traces` directly if you need them on their own.

## Setup

A table reference inside a BigQuery view must name its dataset, so each file reads `moderne_telemetry.traces` and creates the view in that dataset; edit both if yours differs. The views are independent, so create only the ones you want:

```bash
bq query --use_legacy_sql=false < v_runs.sql
```

## Or build the same thing in your BI tool

Nothing requires these to live in BigQuery. The identical logic works as a Looker Studio data source, a Tableau data source, or a Power BI model, which keeps the semantics next to the dashboards that use them. See [`../../../dashboards`](../../../dashboards).
