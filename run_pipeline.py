#!/usr/bin/env python3
"""Run the SQL pipeline (sql/00..05) on DuckDB and export clean tables, KPI tables, metrics and charts.

Usage
  python run_pipeline.py --source sample     # repo-contained subset  (data/raw)      -> data/clean/cleaned, powerbi/data, results/sample/
  python run_pipeline.py --source full       # full Kaggle data       (data/raw_full) -> data/clean_full/{cleaned,star}, results/
                                             #   (download first: python scripts/download_full_data.py)
"""
import argparse, csv, json, pathlib, platform, time
import duckdb

ROOT = pathlib.Path(__file__).resolve().parent
SQL_FILES = ["00_duckdb_compat.sql", "01_staging.sql", "02_cleaning.sql", "03_model.sql",
             "04_analysis.sql", "05_quality_checks.sql"]
STAR = ["fact_order_items", "fact_orders", "dim_date", "dim_customer", "dim_product", "dim_seller"]
CLEAN = ["cln_orders", "cln_order_items", "cln_payments", "cln_reviews", "cln_customers", "cln_products", "cln_sellers"]


def split_sql(text):
    """Split on ';' at end of line after removing -- comments (scripts contain no ';' inside strings)."""
    stmts, buf = [], []
    for line in text.splitlines():
        i = line.find("--")
        if i >= 0 and line[:i].count("'") % 2 == 0:  # drop comment unless inside a string literal
            line = line[:i]
        if not line.strip():
            continue
        buf.append(line)
        if line.rstrip().endswith(";"):
            s = "\n".join(buf).strip().rstrip(";").strip()
            if s:
                stmts.append(s)
            buf = []
    return stmts


def rows(con, q):
    cur = con.execute(q)
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, r)) for r in cur.fetchall()]


def jsonable(v):
    if hasattr(v, "isoformat"):
        return v.isoformat()
    if v.__class__.__name__ == "Decimal":
        return float(v)
    return v


def export(con, table, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    cur = con.execute(f"SELECT * FROM {table} ORDER BY ALL")
    cols = [d[0] for d in cur.description]
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(cols)
        for r in cur.fetchall():
            w.writerow(["" if v is None else jsonable(v) for v in r])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", choices=["sample", "full"], default="sample")
    ap.add_argument("--no-charts", action="store_true")
    a = ap.parse_args()
    raw = ROOT / ("data/raw" if a.source == "sample" else "data/raw_full")
    clean_dir = ROOT / ("data/clean" if a.source == "sample" else "data/clean_full")
    res = ROOT / ("results/sample" if a.source == "sample" else "results")
    if not (raw / "olist_orders_dataset.csv").exists():
        raise SystemExit(f"missing {raw}; run scripts/download_full_data.py first")

    con = duckdb.connect()  # in-memory
    timings = {}
    for f in SQL_FILES:
        t0 = time.time()
        text = (ROOT / "sql" / f).read_text().replace("{{RAW_DIR}}", raw.as_posix())
        for s in split_sql(text):
            con.execute(s)
        timings[f] = round(time.time() - t0, 3)
        print(f"ran {f:24s} {timings[f]:6.2f}s")

    # star schema: sample run -> powerbi/data (the Power BI kit ships with it); full run -> data/clean_full/star
    star_dir = ROOT / "powerbi" / "data" if a.source == "sample" else clean_dir / "star"
    for t in STAR:
        export(con, t, star_dir / f"{t}.csv")
    for t in CLEAN:
        export(con, t, clean_dir / "cleaned" / f"{t.replace('cln_', '')}.csv")
    tables = [r["table_name"] for r in rows(con, "SELECT table_name FROM information_schema.tables "
              "WHERE table_name LIKE 'a\\_%' ESCAPE '\\' OR table_name LIKE 'dq\\_%' ESCAPE '\\' ORDER BY 1")]
    for t in tables:
        export(con, t, res / "tables" / f"{t}.csv")

    kpi = {k: jsonable(v) for k, v in rows(con, "SELECT * FROM a_kpi_headline")[0].items()}
    dq = {
        "row_counts": [{k: jsonable(v) for k, v in r.items()} for r in rows(con, "SELECT * FROM dq_row_counts")],
        "null_rates": [{k: jsonable(v) for k, v in r.items()} for r in rows(con, "SELECT * FROM dq_null_rates")],
        "issues": {r["check_name"]: jsonable(r["affected_rows"]) for r in rows(con, "SELECT * FROM dq_issues")},
        "assertions": {r["check_name"]: r["status"] for r in rows(con, "SELECT * FROM dq_assertions")},
    }
    window = rows(con, "SELECT MIN(purchase_ts) AS first_order, MAX(purchase_ts) AS last_order FROM fact_orders")[0]
    metrics = {
        "project": "da-learn-01-ecommerce-sales-analysis",
        "dataset": "Olist Brazilian E-Commerce Public Dataset (Kaggle: olistbr/brazilian-ecommerce, CC BY-NC-SA 4.0)",
        "source_mode": a.source,
        "order_window": {k: jsonable(v) for k, v in window.items()},
        "currency": "BRL",
        "kpis": kpi,
        "data_quality": dq,
        "engine": {"duckdb": duckdb.__version__, "python": platform.python_version()},
        "sql_timings_s": timings,
    }
    res.mkdir(parents=True, exist_ok=True)
    (res / "metrics.json").write_text(json.dumps(metrics, indent=2))

    top_cat = rows(con, "SELECT category_en, gmv_brl, gmv_share_pct FROM a_category_performance ORDER BY gmv_rank LIMIT 3")
    late = {r["delivery_status"]: r for r in rows(con, "SELECT * FROM a_late_vs_ontime")}
    shot = {
        "snapshot": "headline KPIs + run config",
        "source_mode": a.source,
        "config": {"engine": f"duckdb {duckdb.__version__}", "sql_dialect": "Spark/Databricks SQL (+ DuckDB shims in 00)",
                   "revenue_definition": "price + freight, orders not canceled/unavailable",
                   "trend_window": "2017-01..2018-08", "outlier_rule": "price > Q3 + 3*IQR",
                   "review_dedupe": "latest answered review per order"},
        "headline": {k: kpi[k] for k in ["orders_total", "revenue_orders", "gmv_brl", "aov_brl", "unique_customers",
                                         "repeat_customer_pct", "avg_review_score", "avg_delivery_days",
                                         "late_delivery_pct"]},
        "late_vs_on_time_review": {k: jsonable(v["avg_review"]) for k, v in late.items()},
        "top3_categories_by_gmv": [{k: jsonable(v) for k, v in r.items()} for r in top_cat],
        "assertions_passed": sum(1 for v in dq["assertions"].values() if v == "PASS"),
        "assertions_total": len(dq["assertions"]),
    }
    (res / "JSON.shot").write_text(json.dumps(shot, indent=2))
    print(json.dumps(shot["headline"], indent=2))

    if not a.no_charts:
        import importlib.util
        spec = importlib.util.spec_from_file_location("make_charts", ROOT / "scripts" / "make_charts.py")
        mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
        mod.make_all(res / "tables", res / "charts")


if __name__ == "__main__":
    main()
