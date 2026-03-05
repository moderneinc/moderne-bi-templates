# Moderne BI Templates

Starter templates for building reports and dashboards from Moderne CLI telemetry data. These templates provide SQL queries and documentation that you can import into your BI tool of choice — Power BI, Tableau, Looker, Grafana, AWS QuickSight, or any tool that supports SQL.

## Data Source

All templates work with the **trace.csv** produced by the [Moderne CLI](https://docs.moderne.io/user-documentation/moderne-cli/how-to-guides/cli-telemetry). The trace format is hierarchical — each CLI command in the workflow (sync, build, run, apply, commit, push) produces a trace that includes data from all prior stages. See the [data dictionary](data-dictionary/trace-csv.md) for the full column reference.

## Available Templates

Templates are sorted by [trace hierarchy](https://docs.moderne.io/user-documentation/moderne-cli/how-to-guides/cli-telemetry#how-telemetry-is-generated) — earlier pipeline stages first, broadest applicability within each group second.

| Template | Description | Minimum CLI Command |
|----------|-------------|---------------------|
| [Build Success Trend](templates/build-success-trend/) | Monthly build health — success vs. failure rates over time | `mod build` |
| [Build Tool Distribution](templates/build-tool-distribution/) | Build tool and version distribution across successfully built repositories | `mod build` |
| [Recipe Run Trend](templates/recipe-run-trend/) | Monthly adoption trend — recipe runs, distinct recipes, and unique users over time | `mod run` |
| [Top Recipes](templates/top-recipes/) | Most-used recipes by run count, unique users, and repos searched | `mod run` |
| [Dashboard KPIs](templates/dashboard-kpis/) | Executive-level snapshot — all-time totals and monthly trend | `mod git commit` |
| [Commit Trend](templates/commit-trend/) | Monthly trend correlating recipe execution with committed code impact | `mod git commit` |
| [Commit Activity](templates/commit-activity/) | Monthly committed output — successful commits, repos changed, and hours saved | `mod git commit` |
| [Top Users](templates/top-users/) | User engagement ranking by recipe runs and commits | `mod git commit` |
| [Top Recipes with Commits](templates/top-recipes-with-commits/) | Recipes that produce real committed code changes | `mod git commit` |
| [Security Recipe Run Trend](templates/security-recipe-run-trend/) | Monthly security remediation trend — committed fixes, repos fixed, and hours saved | `mod git commit` |

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
│   └── trace-csv.md              # Full trace.csv column reference
├── samples/                          # Fabricated CSV data for each template
│   ├── build-success-trend.csv
│   ├── build-tool-summary.csv
│   ├── build-tool-versions.csv
│   ├── commit-activity.csv
│   ├── commit-trend.csv
│   ├── dashboard-kpis-summary.csv
│   ├── dashboard-kpis-trend.csv
│   ├── recipe-run-trend.csv
│   ├── security-recipe-run-trend.csv
│   ├── top-recipes.csv
│   ├── top-recipes-with-commits.csv
│   └── top-users.csv
└── templates/
    ├── build-success-trend/
    ├── build-tool-distribution/
    ├── commit-activity/
    ├── commit-trend/
    ├── dashboard-kpis/
    ├── recipe-run-trend/
    ├── security-recipe-run-trend/
    ├── top-recipes/
    ├── top-recipes-with-commits/
    └── top-users/                    # Each contains README, SQL, notebook, and images/
```

Each template is a self-contained folder with a README, SQL query, Jupyter notebook visualization, and screenshot. Sample CSV data in the `samples/` directory lets you run any notebook immediately.
