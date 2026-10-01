#!/usr/bin/env python3
"""Build the repo-sized, reproducible raw subset in data/raw/ from the full Kaggle files in data/raw_full/.

Rule (deterministic, no randomness):
  1. keep orders with order_id < '001' (order_id is a uniform 32-char hex hash, so this keeps the first
     1/4096 of the hash space = an unbiased ~0.025% sample of orders across the whole period and all statuses)
  2. keep ALL order_items / payments / reviews of those orders
  3. keep the customers, products and sellers referenced by them
  4. keep the full category translation table (71 rows)
Values are copied verbatim as strings (no cleaning) - cleaning happens in sql/02_cleaning.sql.
"""
import pathlib, duckdb

UPPER = "001"  # exclusive upper bound on order_id
ROOT = pathlib.Path(__file__).resolve().parents[1]
FULL, OUT = ROOT / "data/raw_full", ROOT / "data/raw"
OUT.mkdir(parents=True, exist_ok=True)
con = duckdb.connect()
def src(name):
    return f"read_csv('{(FULL / name).as_posix()}', header = true, all_varchar = true)"
con.execute(f"CREATE TABLE o AS SELECT * FROM {src('olist_orders_dataset.csv')} WHERE order_id < '{UPPER}'")
queries = {
    "olist_orders_dataset.csv": "SELECT * FROM o",
    "olist_order_items_dataset.csv": f"SELECT * FROM {src('olist_order_items_dataset.csv')} WHERE order_id IN (SELECT order_id FROM o)",
    "olist_order_payments_dataset.csv": f"SELECT * FROM {src('olist_order_payments_dataset.csv')} WHERE order_id IN (SELECT order_id FROM o)",
    "olist_order_reviews_dataset.csv": f"SELECT * FROM {src('olist_order_reviews_dataset.csv')} WHERE order_id IN (SELECT order_id FROM o)",
    "olist_customers_dataset.csv": f"SELECT * FROM {src('olist_customers_dataset.csv')} WHERE customer_id IN (SELECT customer_id FROM o)",
    "olist_products_dataset.csv": f"SELECT * FROM {src('olist_products_dataset.csv')} WHERE product_id IN (SELECT product_id FROM {src('olist_order_items_dataset.csv')} WHERE order_id IN (SELECT order_id FROM o))",
    "olist_sellers_dataset.csv": f"SELECT * FROM {src('olist_sellers_dataset.csv')} WHERE seller_id IN (SELECT seller_id FROM {src('olist_order_items_dataset.csv')} WHERE order_id IN (SELECT order_id FROM o))",
    "product_category_name_translation.csv": f"SELECT * FROM {src('product_category_name_translation.csv')}",
}
for name, q in queries.items():
    first = con.execute(f"SELECT * FROM ({q}) LIMIT 0").description[0][0]
    con.execute(f"COPY (SELECT * FROM ({q}) ORDER BY \"{first}\") TO '{(OUT / name).as_posix()}' (HEADER, DELIMITER ',')")
    n = con.execute(f"SELECT COUNT(*) FROM ({q})").fetchone()[0]
    print(f"{name:42s} {n:6d} rows")
