-- 05_quality_checks.sql  Data-quality evidence (Spark SQL dialect): row counts raw vs clean,
-- duplicates removed, null rates before/after, RI orphans, flags, and PASS/FAIL assertions.

CREATE OR REPLACE TABLE dq_row_counts AS
SELECT 'orders' AS entity, (SELECT COUNT(*) FROM stg_orders) AS raw_rows, (SELECT COUNT(DISTINCT order_id) FROM stg_orders) AS distinct_keys, (SELECT COUNT(*) FROM cln_orders) AS clean_rows, 'order_id' AS grain
UNION ALL SELECT 'order_items', (SELECT COUNT(*) FROM stg_order_items), (SELECT COUNT(*) FROM (SELECT DISTINCT order_id, order_item_id FROM stg_order_items) x), (SELECT COUNT(*) FROM cln_order_items), 'order_id + order_item_id'
UNION ALL SELECT 'payments', (SELECT COUNT(*) FROM stg_payments), (SELECT COUNT(*) FROM (SELECT DISTINCT order_id, payment_sequential FROM stg_payments) x), (SELECT COUNT(*) FROM cln_payments), 'order_id + payment_sequential'
UNION ALL SELECT 'reviews', (SELECT COUNT(*) FROM stg_reviews), (SELECT COUNT(DISTINCT order_id) FROM stg_reviews), (SELECT COUNT(*) FROM cln_reviews), 'order_id (latest review kept)'
UNION ALL SELECT 'customers', (SELECT COUNT(*) FROM stg_customers), (SELECT COUNT(DISTINCT customer_id) FROM stg_customers), (SELECT COUNT(*) FROM cln_customers), 'customer_id'
UNION ALL SELECT 'products', (SELECT COUNT(*) FROM stg_products), (SELECT COUNT(DISTINCT product_id) FROM stg_products), (SELECT COUNT(*) FROM cln_products), 'product_id'
UNION ALL SELECT 'sellers', (SELECT COUNT(*) FROM stg_sellers), (SELECT COUNT(DISTINCT seller_id) FROM stg_sellers), (SELECT COUNT(*) FROM cln_sellers), 'seller_id'
UNION ALL SELECT 'fact_order_items', NULL, NULL, (SELECT COUNT(*) FROM fact_order_items), 'order line'
UNION ALL SELECT 'fact_orders', NULL, NULL, (SELECT COUNT(*) FROM fact_orders), 'order';

CREATE OR REPLACE TABLE dq_null_rates AS
-- raw = empty-or-NULL share in staging (strings); clean = NULL share after 02_cleaning.sql
SELECT 'orders' AS entity, 'order_approved_at' AS column_name,
  (SELECT ROUND(100.0 * SUM(CASE WHEN order_approved_at IS NULL OR trim(order_approved_at) = '' THEN 1 ELSE 0 END) / COUNT(*), 3) FROM stg_orders) AS raw_null_pct,
  (SELECT ROUND(100.0 * SUM(CASE WHEN approved_ts IS NULL THEN 1 ELSE 0 END) / COUNT(*), 3) FROM cln_orders) AS clean_null_pct,
  'kept NULL (not yet approved)' AS treatment
UNION ALL SELECT 'orders', 'order_delivered_customer_date',
  (SELECT ROUND(100.0 * SUM(CASE WHEN order_delivered_customer_date IS NULL OR trim(order_delivered_customer_date) = '' THEN 1 ELSE 0 END) / COUNT(*), 3) FROM stg_orders),
  (SELECT ROUND(100.0 * SUM(CASE WHEN delivered_customer_ts IS NULL THEN 1 ELSE 0 END) / COUNT(*), 3) FROM cln_orders),
  'kept NULL; is_delivered = 0'
UNION ALL SELECT 'products', 'product_category_name',
  (SELECT ROUND(100.0 * SUM(CASE WHEN product_category_name IS NULL OR trim(product_category_name) = '' THEN 1 ELSE 0 END) / COUNT(*), 3) FROM stg_products),
  (SELECT ROUND(100.0 * SUM(CASE WHEN category_en IS NULL THEN 1 ELSE 0 END) / COUNT(*), 3) FROM cln_products),
  'filled with unknown + dq_missing_category flag'
UNION ALL SELECT 'products', 'product_weight_g',
  (SELECT ROUND(100.0 * SUM(CASE WHEN product_weight_g IS NULL OR trim(product_weight_g) = '' THEN 1 ELSE 0 END) / COUNT(*), 3) FROM stg_products),
  (SELECT ROUND(100.0 * SUM(CASE WHEN product_weight_g IS NULL THEN 1 ELSE 0 END) / COUNT(*), 3) FROM cln_products),
  '0 g set to NULL; NULL kept'
UNION ALL SELECT 'reviews', 'review_comment_message',
  (SELECT ROUND(100.0 * SUM(CASE WHEN review_comment_message IS NULL OR trim(review_comment_message) = '' THEN 1 ELSE 0 END) / COUNT(*), 3) FROM stg_reviews),
  (SELECT ROUND(100.0 * SUM(CASE WHEN has_comment = 0 THEN 1 ELSE 0 END) / COUNT(*), 3) FROM cln_reviews),
  'text dropped; has_comment (title or message) + comment_length kept'
UNION ALL SELECT 'payments', 'payment_type = not_defined',
  (SELECT ROUND(100.0 * SUM(CASE WHEN payment_type = 'not_defined' THEN 1 ELSE 0 END) / COUNT(*), 3) FROM stg_payments),
  (SELECT ROUND(100.0 * SUM(CASE WHEN payment_type = 'not_defined' THEN 1 ELSE 0 END) / COUNT(*), 3) FROM cln_payments),
  'recoded to unknown';

CREATE OR REPLACE TABLE dq_issues AS
SELECT 'reviews: orders with >1 review (older ones dropped)' AS check_name,
       (SELECT COUNT(*) FROM stg_reviews) - (SELECT COUNT(DISTINCT order_id) FROM stg_reviews) AS affected_rows
UNION ALL SELECT 'reviews: review_id reused across orders', (SELECT COUNT(*) FROM stg_reviews) - (SELECT COUNT(DISTINCT review_id) FROM stg_reviews)
UNION ALL SELECT 'customers: city text changed by trim/lower/accent standardization', (SELECT COUNT(*) FROM stg_customers s JOIN cln_customers c ON lower(trim(s.customer_id)) = c.customer_id WHERE s.customer_city <> c.customer_city)
UNION ALL SELECT 'customers: distinct city spellings raw', (SELECT COUNT(DISTINCT customer_city) FROM stg_customers)
UNION ALL SELECT 'customers: distinct city spellings clean', (SELECT COUNT(DISTINCT customer_city) FROM cln_customers)
UNION ALL SELECT 'sellers: distinct city spellings raw', (SELECT COUNT(DISTINCT seller_city) FROM stg_sellers)
UNION ALL SELECT 'sellers: distinct city spellings clean', (SELECT COUNT(DISTINCT seller_city) FROM cln_sellers)
UNION ALL SELECT 'products: missing category -> unknown', (SELECT SUM(dq_missing_category) FROM cln_products)
UNION ALL SELECT 'products: category without English translation', (SELECT COUNT(*) FROM cln_products p WHERE p.category_pt <> 'unknown' AND p.category_pt NOT IN (SELECT lower(trim(product_category_name)) FROM stg_category_translation))
UNION ALL SELECT 'products: weight 0 g -> NULL', (SELECT COUNT(*) FROM stg_products WHERE TRY_CAST(product_weight_g AS DOUBLE) = 0)
UNION ALL SELECT 'payments: not_defined type -> unknown', (SELECT COUNT(*) FROM cln_payments WHERE payment_type = 'unknown')
UNION ALL SELECT 'payments: 0 installments -> 1', (SELECT SUM(dq_installments_fixed) FROM cln_payments)
UNION ALL SELECT 'payments: zero-value rows (vouchers)', (SELECT SUM(dq_zero_value) FROM cln_payments)
UNION ALL SELECT 'orders: delivered status but no delivery date', (SELECT SUM(dq_delivered_without_date) FROM cln_orders)
UNION ALL SELECT 'orders: timestamps before purchase (excluded from delivery KPIs)', (SELECT SUM(dq_bad_chronology) FROM cln_orders)
UNION ALL SELECT 'orders: no order items (revenue = 0)', (SELECT COUNT(*) FROM fact_orders WHERE items_qty = 0)
UNION ALL SELECT 'orders: no payment rows', (SELECT COUNT(*) FROM fact_orders WHERE payment_value IS NULL)
UNION ALL SELECT 'orders: |payment - (price+freight)| > 1 BRL', (SELECT COUNT(*) FROM fact_orders WHERE abs(payment_value - order_value) > 1)
UNION ALL SELECT 'items: price outlier (> Q3 + 3*IQR)', (SELECT SUM(is_price_outlier_iqr3) FROM cln_order_items)
UNION ALL SELECT 'items: price in top 1%', (SELECT SUM(is_price_top1pct) FROM cln_order_items)
UNION ALL SELECT 'items: freight > price', (SELECT SUM(is_freight_gt_price) FROM cln_order_items)
UNION ALL SELECT 'RI: items with unknown order', (SELECT COUNT(*) FROM stg_order_items WHERE lower(trim(order_id)) NOT IN (SELECT order_id FROM cln_orders))
UNION ALL SELECT 'RI: items with unknown product', (SELECT COUNT(*) FROM stg_order_items WHERE lower(trim(product_id)) NOT IN (SELECT product_id FROM cln_products))
UNION ALL SELECT 'RI: items with unknown seller', (SELECT COUNT(*) FROM stg_order_items WHERE lower(trim(seller_id)) NOT IN (SELECT seller_id FROM cln_sellers))
UNION ALL SELECT 'RI: orders with unknown customer', (SELECT COUNT(*) FROM stg_orders WHERE lower(trim(customer_id)) NOT IN (SELECT customer_id FROM cln_customers))
UNION ALL SELECT 'RI: payments with unknown order', (SELECT COUNT(*) FROM stg_payments WHERE lower(trim(order_id)) NOT IN (SELECT order_id FROM cln_orders))
UNION ALL SELECT 'RI: reviews with unknown order', (SELECT COUNT(*) FROM stg_reviews WHERE lower(trim(order_id)) NOT IN (SELECT order_id FROM cln_orders));

CREATE OR REPLACE TABLE dq_assertions AS
WITH c AS (
  SELECT 'fact_orders.order_id unique' AS check_name, (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM fact_orders) AS failed_rows
  UNION ALL SELECT 'fact_order_items (order_id, order_item_id) unique', (SELECT COUNT(*) FROM (SELECT order_id, order_item_id FROM fact_order_items GROUP BY order_id, order_item_id HAVING COUNT(*) > 1) x)
  UNION ALL SELECT 'fact_order_items.product_id -> dim_product', (SELECT COUNT(*) FROM fact_order_items WHERE product_id NOT IN (SELECT product_id FROM dim_product))
  UNION ALL SELECT 'fact_order_items.seller_id -> dim_seller', (SELECT COUNT(*) FROM fact_order_items WHERE seller_id NOT IN (SELECT seller_id FROM dim_seller))
  UNION ALL SELECT 'fact_orders.customer_id -> dim_customer', (SELECT COUNT(*) FROM fact_orders WHERE customer_id NOT IN (SELECT customer_id FROM dim_customer))
  UNION ALL SELECT 'fact_orders.order_date_key -> dim_date', (SELECT COUNT(*) FROM fact_orders WHERE order_date_key NOT IN (SELECT date_key FROM dim_date))
  UNION ALL SELECT 'review_score in 1..5', (SELECT COUNT(*) FROM fact_orders WHERE review_score IS NOT NULL AND review_score NOT BETWEEN 1 AND 5)
  UNION ALL SELECT 'price > 0', (SELECT COUNT(*) FROM fact_order_items WHERE price <= 0)
  UNION ALL SELECT 'no NULL purchase_ts', (SELECT COUNT(*) FROM fact_orders WHERE purchase_ts IS NULL)
  UNION ALL SELECT 'categories trimmed/lowercase', (SELECT COUNT(*) FROM dim_product WHERE category_en <> lower(trim(category_en)))
)
SELECT check_name, failed_rows, CASE WHEN failed_rows = 0 THEN 'PASS' ELSE 'FAIL' END AS status FROM c;
