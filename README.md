# Moderne BI Templates

Starter templates for building reports and dashboards from Moderne CLI telemetry data. These templates provide SQL queries and documentation that you can import into your BI tool of choice — Power BI, Tableau, Looker, Grafana, AWS QuickSight, or any tool that supports SQL.

## Data Source

All templates work with the **trace.csv** produced by the [Moderne CLI](https://docs.moderne.io/user-documentation/moderne-cli/how-to-guides/cli-telemetry). The trace format is hierarchical — each CLI command in the workflow (sync, build, run, apply, commit, push) produces a trace that includes data from all prior stages. See the [data dictionary](data-dictionary/trace-csv.md) for the full column reference.

## Available Templates

| Template | Description | Minimum CLI Command |
|----------|-------------|---------------------|
| [Recipe Run Trend](templates/recipe-run-trend/) | Monthly adoption trend — recipe runs, distinct recipes, and unique users over time | `mod run` |
| [Top Users](templates/top-users/) | User engagement ranking by recipe runs and commits | `mod git commit` |
| [Top Recipes](templates/top-recipes/) | Most-used recipes by run count, unique users, and repos searched | `mod run` |

## Getting Started

1. Ensure your Moderne CLI is configured to publish trace data (see [CLI telemetry docs](https://docs.moderne.io/user-documentation/moderne-cli/how-to-guides/cli-telemetry))
2. Choose a template from the table above
3. Review the template's README for the report description, required fields, and example output
4. Copy the SQL query into your BI tool or query engine (Athena, Trino, BigQuery, etc.)
5. Customize as needed for your organization

## Repository Structure

```
moderne-bi-templates/
├── data-dictionary/
│   └── trace-csv.md          # Full trace.csv column reference
├── templates/
│   ├── recipe-run-trend/     # One folder per template
│   │   ├── README.md          # Report description and example output
│   │   └── recipe-run-trend.sql
│   ├── top-users/
│   │   ├── README.md
│   │   └── top-users.sql
│   └── top-recipes/
│       ├── README.md
│       └── top-recipes.sql
```

Each template is a self-contained folder with a README describing the report and a SQL file you can run directly against your trace data.
