# Jupyter dashboards

There's one notebook per report, and each one draws a single report's chart from that report's bundled sample CSV (in [`../../reports/<report>/`](../../reports)), so they all run right away. You don't need the data layer or any cloud access.

| Notebook | Report |
|----------|--------|
| [build-success-trend.ipynb](build-success-trend.ipynb) | Monthly build health |
| [build-tool-distribution.ipynb](build-tool-distribution.ipynb) | Build tool + version distribution |
| [recipe-run-trend.ipynb](recipe-run-trend.ipynb) | Monthly recipe-run adoption |
| [top-recipes.ipynb](top-recipes.ipynb) | Most-used recipes |
| [dashboard-kpis.ipynb](dashboard-kpis.ipynb) | Executive KPI snapshot |
| [commit-trend.ipynb](commit-trend.ipynb) | Recipe execution vs. committed impact |
| [commit-activity.ipynb](commit-activity.ipynb) | Monthly committed output |
| [top-users.ipynb](top-users.ipynb) | User engagement |
| [top-recipes-with-commits.ipynb](top-recipes-with-commits.ipynb) | Recipes producing commits |
| [security-recipe-run-trend.ipynb](security-recipe-run-trend.ipynb) | Security remediation trend |

Each notebook goes with the query and docs for its report under [`../../reports/<report>/`](../../reports).

## Running

```bash
pip install pandas matplotlib jupyter
jupyter notebook            # then open any notebook above
```

The notebooks read each report's sample CSV by relative path (`../../reports/<report>/<report>-sample-data.csv`). To chart your own data, run the report's SQL (from `../../reports/<report>/`) against your `traces` table, export the result to a CSV with the same columns, and point the notebook's `read_csv(...)` at it.

## Combining panels

There's one notebook per report so you can grab just the panel you want. If you'd rather have a single dashboard view, copy the panels you care about into one notebook and lay them out on a grid.
