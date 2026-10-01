-- 03_model.sql  Star schema (Spark SQL dialect)
--   facts : fact_order_items (grain: order line)   fact_orders (grain: order)
--   dims  : dim_date, dim_customer, dim_product, dim_seller
-- Keys: date_key = yyyymmdd INT; natural (hash) keys for customer/product/seller.

-- ---------- dim_date: gap-free calendar spine from first to last purchase date (portable digits cross join) ----------
CREATE OR REPLACE TABLE dim_date AS
WITH d AS (SELECT * FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS t(n)),
nums AS (SELECT a.n + 10 * b.n + 100 * c.n + 1000 * e.n AS n FROM d a CROSS JOIN d b CROSS JOIN d c CROSS JOIN d e),
bounds AS (SELECT MIN(purchase_date) AS d0, MAX(purchase_date) AS d1 FROM cln_orders),
cal AS (SELECT date_add(b.d0, nums.n) AS date_day FROM nums CROSS JOIN bounds b WHERE nums.n <= datediff(b.d1, b.d0))
SELECT
  CAST(year(date_day) * 10000 + month(date_day) * 100 + day(date_day) AS INT) AS date_key,
  date_day                                                   AS calendar_date,
  year(date_day)                                             AS year,
  month(date_day)                                            AS month,
  CAST(date_trunc('MONTH', date_day) AS DATE)                AS month_start,
  dayofweek(date_day)                                        AS day_of_week       -- 1 = Sunday (Spark convention)
FROM cal;

-- ---------- dim_customer (order-level customer_id -> person-level customer_unique_id + region + cohort) ----------
CREATE OR REPLACE TABLE dim_customer AS
WITH first_order AS (
  SELECT c.customer_unique_id, MIN(o.purchase_ts) AS first_purchase_ts
  FROM cln_orders o JOIN cln_customers c ON o.customer_id = c.customer_id
  GROUP BY c.customer_unique_id
)
SELECT
  c.customer_id, c.customer_unique_id, c.customer_zip_prefix, c.customer_city, c.customer_state,
  CASE WHEN c.customer_state IN ('SP','RJ','MG','ES') THEN 'Southeast'
       WHEN c.customer_state IN ('PR','SC','RS') THEN 'South'
       WHEN c.customer_state IN ('MT','MS','GO','DF') THEN 'Center-West'
       WHEN c.customer_state IN ('BA','SE','AL','PE','PB','RN','CE','PI','MA') THEN 'Northeast'
       WHEN c.customer_state IN ('AM','RR','AP','PA','TO','RO','AC') THEN 'North'
       ELSE 'Unknown' END                                    AS customer_region,
  CAST(date_trunc('MONTH', f.first_purchase_ts) AS DATE)     AS cohort_month
FROM cln_customers c
LEFT JOIN first_order f ON c.customer_unique_id = f.customer_unique_id;

-- ---------- dim_product ----------
CREATE OR REPLACE TABLE dim_product AS
SELECT product_id, category_pt, category_en, dq_missing_category,
       product_photos_qty, product_weight_g,
       ROUND(product_length_cm * product_height_cm * product_width_cm / 1000.0, 2) AS product_volume_l
FROM cln_products;

-- ---------- dim_seller ----------
CREATE OR REPLACE TABLE dim_seller AS
SELECT seller_id, seller_zip_prefix, seller_city, seller_state,
  CASE WHEN seller_state IN ('SP','RJ','MG','ES') THEN 'Southeast'
       WHEN seller_state IN ('PR','SC','RS') THEN 'South'
       WHEN seller_state IN ('MT','MS','GO','DF') THEN 'Center-West'
       WHEN seller_state IN ('BA','SE','AL','PE','PB','RN','CE','PI','MA') THEN 'Northeast'
       WHEN seller_state IN ('AM','RR','AP','PA','TO','RO','AC') THEN 'North'
       ELSE 'Unknown' END AS seller_region
FROM cln_sellers;

-- ---------- fact_order_items (grain: one order line) ----------
CREATE OR REPLACE TABLE fact_order_items AS
SELECT
  i.order_id, i.order_item_id, i.product_id, i.seller_id, o.customer_id,
  CAST(year(o.purchase_date) * 10000 + month(o.purchase_date) * 100 + day(o.purchase_date) AS INT) AS order_date_key,
  o.order_status,
  CASE WHEN o.order_status IN ('canceled', 'unavailable') THEN 0 ELSE 1 END AS is_revenue_order,
  i.price, i.freight_value,
  CAST(i.price + i.freight_value AS DECIMAL(12,2)) AS item_total,
  i.is_price_outlier_iqr3, i.is_price_top1pct, i.is_freight_gt_price
FROM cln_order_items i
JOIN cln_orders o ON i.order_id = o.order_id;

-- ---------- fact_orders (grain: one order) ----------
CREATE OR REPLACE TABLE fact_orders AS
WITH items AS (
  SELECT order_id, COUNT(*) AS items_qty, COUNT(DISTINCT seller_id) AS sellers_qty,
         SUM(price) AS items_value, SUM(freight_value) AS freight_value
  FROM cln_order_items GROUP BY order_id
), pay AS (
  SELECT order_id, SUM(payment_value) AS payment_value, MAX(payment_installments) AS max_installments,
         COUNT(*) AS payment_rows
  FROM cln_payments GROUP BY order_id
), main_pay AS (
  SELECT order_id, payment_type AS main_payment_type FROM (
    SELECT order_id, payment_type,
           ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY payment_value DESC, payment_sequential) AS rn
    FROM cln_payments) t
  WHERE rn = 1
)
SELECT
  o.order_id, o.customer_id, c.customer_unique_id,
  CAST(year(o.purchase_date) * 10000 + month(o.purchase_date) * 100 + day(o.purchase_date) AS INT) AS order_date_key,
  o.purchase_ts, o.order_status,
  CASE WHEN o.order_status IN ('canceled', 'unavailable') THEN 0 ELSE 1 END AS is_revenue_order,
  COALESCE(i.items_qty, 0) AS items_qty, COALESCE(i.sellers_qty, 0) AS sellers_qty,
  COALESCE(i.items_value, 0) AS items_value, COALESCE(i.freight_value, 0) AS freight_value,
  COALESCE(i.items_value, 0) + COALESCE(i.freight_value, 0) AS order_value,
  p.payment_value, mp.main_payment_type, p.max_installments,
  o.is_delivered, o.delivery_days, o.promised_days, o.days_vs_estimate, o.is_late,
  o.dq_bad_chronology,
  r.review_score, r.has_comment,
  CASE WHEN c.cohort_month = CAST(date_trunc('MONTH', o.purchase_ts) AS DATE) THEN 1 ELSE 0 END AS is_first_month_order
FROM cln_orders o
LEFT JOIN items i        ON o.order_id = i.order_id
LEFT JOIN pay p          ON o.order_id = p.order_id
LEFT JOIN main_pay mp    ON o.order_id = mp.order_id
LEFT JOIN cln_reviews r  ON o.order_id = r.order_id
LEFT JOIN dim_customer c ON o.customer_id = c.customer_id;
