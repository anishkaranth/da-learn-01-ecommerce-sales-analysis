# Databricks package - executed on Databricks (2026-10-01)

The full pipeline was run on a Databricks **serverless SQL warehouse** (Unity Catalog) on 2026-10-01, and a Lakeview
(AI/BI) dashboard was created and published over the resulting tables. The warehouse was stopped afterwards.

| Object | Workspace location |
|---|---|
| Raw CSVs (full data, 8 files, 63.4 MB) | UC volume `/Volumes/workspace/da_learn_01/raw/` |
| Tables (stg_*, cln_*, dim_*, fact_*, a_*, dq_*) | `workspace.da_learn_01` |
| Notebook | `/Workspace/Shared/da-learn-01-ecommerce-sales-analysis/olist_pipeline_notebook` |
| Dashboard (published) | **da-learn-01 Olist e-commerce sales** - `/Workspace/Shared/da-learn-01-ecommerce-sales-analysis/da-learn-01 Olist e-commerce sales.lvdash.json` |

## Files here
| File | What it is |
|---|---|
| `olist_pipeline_notebook.sql` | Databricks SQL notebook source (`-- Databricks notebook source` / `-- COMMAND ----------`), exported back from the workspace (identical to the imported file) |
| `olist_sales_dashboard.lvdash.json` | Lakeview dashboard definition exported back from the workspace: 2 pages, **8 visuals** - KPI counters (GMV, AOV, avg review, late-delivery rate), monthly GMV trend (line), top-10 categories (bar), delivery time vs review (bar), GMV by customer state (bar) |
| `run_outputs/` | Tables queried back from Databricks + `duckdb_vs_databricks.json` (row counts and cell-by-cell comparison with the DuckDB run) |

## DuckDB vs Databricks
All **21 tables have identical row counts** on both engines (stg 99,441 / 112,650 / 103,886 / 99,224 / 99,441 / 32,951 / 3,095 / 71;
cln_reviews 98,673; fact_orders 99,441; fact_order_items 112,650; dim_date 774; dim_customer 99,441; dim_product 32,951; dim_seller 3,095).
`a_kpi_headline`, `dq_assertions` (10/10 PASS), `a_late_vs_ontime`, `a_payment_mix`, `a_region_rollup` and `a_seller_concentration`
are identical cell by cell. The only difference: **"items: price in top 1%" = 1,134 on Databricks vs 1,117 on DuckDB**, because
`percentile_approx` is approximate on Spark and exact (`quantile_cont`) in the DuckDB shim. The IQR outlier count (4,074) matched.
Run time: 47 statements, ~457 s total on the warehouse; `dq_issues` alone took ~221 s (many `NOT IN` subqueries), everything else 1-18 s each.

## Re-run it yourself
1. `CREATE SCHEMA IF NOT EXISTS workspace.da_learn_01; CREATE VOLUME IF NOT EXISTS workspace.da_learn_01.raw;`
   (different catalog/schema? edit `CATALOG`, `SCHEMA`, `VOLUME` in `scripts/build_databricks.py`, then `python scripts/build_databricks.py --with-dashboard`).
2. Upload the 8 CSVs from `data/raw_full/` (`python scripts/download_full_data.py`) or the subset in `data/raw/` to the volume
   (Catalog Explorer -> *Upload to this volume*, or `databricks fs cp data/raw_full/ dbfs:/Volumes/workspace/da_learn_01/raw/ --recursive`).
3. Workspace -> *Import* -> `olist_pipeline_notebook.sql`; attach a SQL warehouse (or DBR 13.3 LTS+) -> *Run all*.
   Check that `dq_assertions` shows 10 x PASS.
4. Dashboards -> *Import dashboard from file* -> `olist_sales_dashboard.lvdash.json` -> pick a warehouse -> *Publish*.
   (API used here: `POST /api/2.0/lakeview/dashboards` with `serialized_dashboard`, then `POST .../published`.)
5. Notebook charts: under each "Visualization:" cell use **+ -> Visualization** with the settings in the cell comment
   (notebook visual settings live in the workspace, not in the source file).

## Dialect notes (DuckDB vs Databricks)
| Topic | DuckDB run | Databricks |
|---|---|---|
| CSV load | `read_csv(path, header = true, all_varchar = true)` | `read_files(path, format => 'csv', header => true, multiLine => true, inferColumnTypes => false)` (adds a harmless `_rescued_data` column) |
| `unix_timestamp`, 2-arg `datediff(end, start)`, `percentile_approx`, `dayofweek` (1 = Sunday) | macros in `sql/00_duckdb_compat.sql` | built-in |
| `CREATE OR REPLACE TABLE ... AS` | in-memory table | managed Delta table |
| Everything else (`TRY_CAST`, `translate`, `lpad`, window functions, `date_trunc('MONTH', ..)`, `date_add(date, int)`, `VALUES` tables) | same | same |
