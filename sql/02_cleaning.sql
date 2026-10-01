-- 02_cleaning.sql  (Spark SQL dialect; runs on DuckDB via 00_duckdb_compat.sql shims)
-- Steps: trim/standardize text -> type casting & date parsing -> null handling -> dedupe
--        -> outlier / data-quality flags -> referential-integrity filtering.
-- Accent stripping uses translate(), which exists in both engines.

-- ---------- customers ----------
CREATE OR REPLACE TABLE cln_customers AS
WITH typed AS (
  SELECT
    lower(trim(customer_id))                                   AS customer_id,
    lower(trim(customer_unique_id))                            AS customer_unique_id,
    lpad(trim(customer_zip_code_prefix), 5, '0')               AS customer_zip_prefix,   -- restore leading zeros
    lower(trim(translate(customer_city, 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÉÊÍÓÔÕÚÇ', 'aaaaaeeeeiiiiooooouuuucAAAAEEIOOOUC'))) AS customer_city,
    upper(trim(customer_state))                                AS customer_state
  FROM stg_customers
  WHERE customer_id IS NOT NULL AND trim(customer_id) <> ''
), ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY customer_unique_id) AS rn FROM typed
)
SELECT customer_id, customer_unique_id, customer_zip_prefix, customer_city, customer_state
FROM ranked WHERE rn = 1;

-- ---------- sellers ----------
CREATE OR REPLACE TABLE cln_sellers AS
WITH typed AS (
  SELECT
    lower(trim(seller_id))                                     AS seller_id,
    lpad(trim(seller_zip_code_prefix), 5, '0')                 AS seller_zip_prefix,
    lower(trim(translate(seller_city, 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÉÊÍÓÔÕÚÇ', 'aaaaaeeeeiiiiooooouuuucAAAAEEIOOOUC'))) AS seller_city,
    upper(trim(seller_state))                                  AS seller_state
  FROM stg_sellers
  WHERE seller_id IS NOT NULL AND trim(seller_id) <> ''
), ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY seller_zip_prefix) AS rn FROM typed
)
SELECT seller_id, seller_zip_prefix, seller_city, seller_state FROM ranked WHERE rn = 1;

-- ---------- products (+ English category, fixes source typo 'lenght') ----------
CREATE OR REPLACE TABLE cln_products AS
WITH tr AS (
  SELECT lower(trim(product_category_name)) AS category_pt,
         lower(trim(product_category_name_english)) AS category_en
  FROM stg_category_translation
), typed AS (
  SELECT
    lower(trim(p.product_id))                                    AS product_id,
    NULLIF(lower(trim(p.product_category_name)), '')             AS category_pt,
    TRY_CAST(p.product_name_lenght        AS INT)                AS product_name_length,
    TRY_CAST(p.product_description_lenght AS INT)                AS product_description_length,
    TRY_CAST(p.product_photos_qty         AS INT)                AS product_photos_qty,
    TRY_CAST(p.product_weight_g           AS DOUBLE)             AS product_weight_g,
    TRY_CAST(p.product_length_cm          AS DOUBLE)             AS product_length_cm,
    TRY_CAST(p.product_height_cm          AS DOUBLE)             AS product_height_cm,
    TRY_CAST(p.product_width_cm           AS DOUBLE)             AS product_width_cm
  FROM stg_products p
  WHERE p.product_id IS NOT NULL
), ranked AS (
  SELECT t.*, ROW_NUMBER() OVER (PARTITION BY t.product_id ORDER BY t.category_pt) AS rn FROM typed t
)
SELECT
  r.product_id,
  COALESCE(r.category_pt, 'unknown')                                        AS category_pt,
  -- 2 Portuguese categories have no translation row -> fall back to the PT name; NULL -> 'unknown'
  COALESCE(tr.category_en, r.category_pt, 'unknown')                        AS category_en,
  CASE WHEN r.category_pt IS NULL THEN 1 ELSE 0 END                         AS dq_missing_category,
  r.product_name_length, r.product_description_length,
  COALESCE(r.product_photos_qty, 0)                                         AS product_photos_qty,
  CASE WHEN r.product_weight_g > 0 THEN r.product_weight_g END              AS product_weight_g,  -- 0 g is not a real weight
  r.product_length_cm, r.product_height_cm, r.product_width_cm
FROM ranked r LEFT JOIN tr ON r.category_pt = tr.category_pt
WHERE r.rn = 1;

-- ---------- orders (date parsing + chronology flags + RI to customers) ----------
CREATE OR REPLACE TABLE cln_orders AS
WITH typed AS (
  SELECT
    lower(trim(order_id))                                        AS order_id,
    lower(trim(customer_id))                                     AS customer_id,
    lower(trim(order_status))                                    AS order_status,
    TRY_CAST(order_purchase_timestamp      AS TIMESTAMP)         AS purchase_ts,
    TRY_CAST(order_approved_at             AS TIMESTAMP)         AS approved_ts,
    TRY_CAST(order_delivered_carrier_date  AS TIMESTAMP)         AS delivered_carrier_ts,
    TRY_CAST(order_delivered_customer_date AS TIMESTAMP)         AS delivered_customer_ts,
    TRY_CAST(order_estimated_delivery_date AS TIMESTAMP)         AS estimated_delivery_ts
  FROM stg_orders
  WHERE order_id IS NOT NULL
), ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY purchase_ts) AS rn FROM typed
)
SELECT
  o.order_id, o.customer_id, o.order_status,
  o.purchase_ts, o.approved_ts, o.delivered_carrier_ts, o.delivered_customer_ts, o.estimated_delivery_ts,
  CAST(o.purchase_ts AS DATE)                                                       AS purchase_date,
  CASE WHEN o.order_status = 'delivered' AND o.delivered_customer_ts IS NOT NULL THEN 1 ELSE 0 END AS is_delivered,
  ROUND((unix_timestamp(o.delivered_customer_ts) - unix_timestamp(o.purchase_ts)) / 86400.0, 2)   AS delivery_days,
  ROUND((unix_timestamp(o.estimated_delivery_ts) - unix_timestamp(o.purchase_ts)) / 86400.0, 2)   AS promised_days,
  datediff(o.delivered_customer_ts, o.estimated_delivery_ts)                                       AS days_vs_estimate, -- >0 = late
  CASE WHEN o.delivered_customer_ts IS NULL THEN NULL
       WHEN CAST(o.delivered_customer_ts AS DATE) > CAST(o.estimated_delivery_ts AS DATE) THEN 1 ELSE 0 END AS is_late,
  CASE WHEN o.delivered_customer_ts < o.purchase_ts
         OR o.approved_ts < o.purchase_ts
         OR o.delivered_carrier_ts < o.purchase_ts THEN 1 ELSE 0 END                AS dq_bad_chronology,
  CASE WHEN o.order_status = 'delivered' AND o.delivered_customer_ts IS NULL THEN 1 ELSE 0 END AS dq_delivered_without_date
FROM ranked o
WHERE o.rn = 1
  AND o.purchase_ts IS NOT NULL
  AND o.customer_id IN (SELECT customer_id FROM cln_customers);          -- referential integrity

-- ---------- order items (casts, outlier flags, RI to orders/products/sellers) ----------
CREATE OR REPLACE TABLE cln_order_items AS
WITH typed AS (
  SELECT
    lower(trim(order_id))                                     AS order_id,
    TRY_CAST(order_item_id AS INT)                            AS order_item_id,
    lower(trim(product_id))                                   AS product_id,
    lower(trim(seller_id))                                    AS seller_id,
    TRY_CAST(shipping_limit_date AS TIMESTAMP)                AS shipping_limit_ts,
    TRY_CAST(price         AS DECIMAL(12,2))                  AS price,
    TRY_CAST(freight_value AS DECIMAL(12,2))                  AS freight_value
  FROM stg_order_items
), ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY order_id, order_item_id ORDER BY shipping_limit_ts) AS rn FROM typed
), valid AS (
  SELECT r.* FROM ranked r
  WHERE r.rn = 1 AND r.price IS NOT NULL AND r.price > 0
    AND r.order_id   IN (SELECT order_id   FROM cln_orders)
    AND r.product_id IN (SELECT product_id FROM cln_products)
    AND r.seller_id  IN (SELECT seller_id  FROM cln_sellers)
), bounds AS (
  SELECT percentile_approx(CAST(price AS DOUBLE), 0.25) AS q1,
         percentile_approx(CAST(price AS DOUBLE), 0.75) AS q3,
         percentile_approx(CAST(price AS DOUBLE), 0.99) AS p99
  FROM valid
)
SELECT
  v.order_id, v.order_item_id, v.product_id, v.seller_id, v.shipping_limit_ts,
  v.price, COALESCE(v.freight_value, CAST(0 AS DECIMAL(12,2))) AS freight_value,
  CASE WHEN CAST(v.price AS DOUBLE) > b.q3 + 3 * (b.q3 - b.q1) THEN 1 ELSE 0 END AS is_price_outlier_iqr3,  -- extreme (3x IQR) fence
  CASE WHEN CAST(v.price AS DOUBLE) > b.p99 THEN 1 ELSE 0 END                    AS is_price_top1pct,
  CASE WHEN v.freight_value > v.price THEN 1 ELSE 0 END                          AS is_freight_gt_price
FROM valid v CROSS JOIN bounds b;

-- ---------- payments ----------
CREATE OR REPLACE TABLE cln_payments AS
WITH typed AS (
  SELECT
    lower(trim(order_id))                                     AS order_id,
    TRY_CAST(payment_sequential   AS INT)                     AS payment_sequential,
    CASE WHEN lower(trim(payment_type)) IN ('not_defined', '') OR payment_type IS NULL THEN 'unknown'
         ELSE lower(trim(payment_type)) END                   AS payment_type,
    TRY_CAST(payment_installments AS INT)                     AS payment_installments_raw,
    TRY_CAST(payment_value AS DECIMAL(12,2))                  AS payment_value
  FROM stg_payments
), ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY order_id, payment_sequential ORDER BY payment_value DESC) AS rn FROM typed
)
SELECT order_id, payment_sequential, payment_type,
       CASE WHEN payment_installments_raw IS NULL OR payment_installments_raw < 1 THEN 1
            ELSE payment_installments_raw END                AS payment_installments,   -- 0 installments -> 1 (single payment)
       CASE WHEN payment_installments_raw IS NULL OR payment_installments_raw < 1 THEN 1 ELSE 0 END AS dq_installments_fixed,
       payment_value,
       CASE WHEN payment_value <= 0 THEN 1 ELSE 0 END        AS dq_zero_value
FROM ranked
WHERE rn = 1 AND payment_value IS NOT NULL
  AND order_id IN (SELECT order_id FROM cln_orders);

-- ---------- reviews (one review per order: latest answer wins) ----------
CREATE OR REPLACE TABLE cln_reviews AS
WITH typed AS (
  SELECT
    lower(trim(review_id))                                     AS review_id,
    lower(trim(order_id))                                      AS order_id,
    TRY_CAST(review_score AS INT)                              AS review_score,
    NULLIF(trim(review_comment_title), '')                     AS comment_title,
    NULLIF(trim(review_comment_message), '')                   AS comment_message,
    TRY_CAST(review_creation_date    AS TIMESTAMP)             AS review_created_ts,
    TRY_CAST(review_answer_timestamp AS TIMESTAMP)             AS review_answered_ts
  FROM stg_reviews
), ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answered_ts DESC, review_id) AS rn
  FROM typed
  WHERE review_score BETWEEN 1 AND 5
)
SELECT review_id, order_id, review_score,
       CASE WHEN comment_message IS NOT NULL OR comment_title IS NOT NULL THEN 1 ELSE 0 END AS has_comment,
       COALESCE(length(comment_message), 0)                    AS comment_length,
       review_created_ts, review_answered_ts
FROM ranked
WHERE rn = 1 AND order_id IN (SELECT order_id FROM cln_orders);
