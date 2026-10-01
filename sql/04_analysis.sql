-- 04_analysis.sql  Business KPI queries (Spark SQL dialect). Each result is materialised as a_* table
-- and exported by run_pipeline.py to results/tables/<name>.csv.
-- Revenue (GMV) = item price + freight of orders NOT canceled/unavailable (is_revenue_order = 1).
-- Trend analyses use complete months 2017-01 .. 2018-08 (2016 and Sep/Oct 2018 are sparse in the source).

-- Q1 Headline KPIs
CREATE OR REPLACE TABLE a_kpi_headline AS
WITH rev AS (SELECT * FROM fact_orders WHERE is_revenue_order = 1 AND items_qty > 0),
cust AS (SELECT customer_unique_id, COUNT(*) AS n_orders FROM rev GROUP BY customer_unique_id)
SELECT
  (SELECT COUNT(*) FROM fact_orders)                                         AS orders_total,
  (SELECT COUNT(*) FROM rev)                                                 AS revenue_orders,
  (SELECT SUM(is_delivered) FROM fact_orders)                                AS delivered_orders,
  (SELECT ROUND(SUM(order_value), 2) FROM rev)                               AS gmv_brl,
  (SELECT ROUND(SUM(items_value), 2) FROM rev)                               AS product_revenue_brl,
  (SELECT ROUND(SUM(freight_value), 2) FROM rev)                             AS freight_revenue_brl,
  (SELECT ROUND(AVG(order_value), 2) FROM rev)                               AS aov_brl,
  (SELECT ROUND(AVG(items_qty), 3) FROM rev)                                 AS items_per_order,
  (SELECT COUNT(*) FROM cust)                                                AS unique_customers,
  (SELECT ROUND(100.0 * SUM(CASE WHEN n_orders > 1 THEN 1 ELSE 0 END) / COUNT(*), 2) FROM cust) AS repeat_customer_pct,
  (SELECT ROUND(AVG(review_score), 3) FROM fact_orders WHERE review_score IS NOT NULL)            AS avg_review_score,
  (SELECT ROUND(100.0 * SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) / COUNT(review_score), 2) FROM fact_orders) AS low_review_pct,
  (SELECT ROUND(AVG(delivery_days), 2) FROM fact_orders WHERE is_delivered = 1 AND dq_bad_chronology = 0) AS avg_delivery_days,
  (SELECT ROUND(percentile_approx(delivery_days, 0.5), 2) FROM fact_orders WHERE is_delivered = 1 AND dq_bad_chronology = 0) AS median_delivery_days,
  (SELECT ROUND(100.0 * SUM(is_late) / COUNT(is_late), 2) FROM fact_orders WHERE is_delivered = 1) AS late_delivery_pct,
  (SELECT ROUND(100.0 * SUM(CASE WHEN order_status = 'canceled' THEN 1 ELSE 0 END) / COUNT(*), 2) FROM fact_orders) AS cancel_pct;

-- Q2 Monthly revenue trend, AOV, MoM growth
CREATE OR REPLACE TABLE a_monthly_revenue AS
WITH m AS (
  SELECT d.month_start, COUNT(*) AS orders, ROUND(SUM(f.order_value), 2) AS gmv_brl,
         ROUND(AVG(f.order_value), 2) AS aov_brl, COUNT(DISTINCT f.customer_unique_id) AS customers,
         ROUND(AVG(f.review_score), 3) AS avg_review, ROUND(100.0 * SUM(f.is_late) / COUNT(f.is_late), 2) AS late_pct
  FROM fact_orders f JOIN dim_date d ON f.order_date_key = d.date_key
  WHERE f.is_revenue_order = 1 AND f.items_qty > 0
    AND d.month_start BETWEEN DATE '2017-01-01' AND DATE '2018-08-01'
  GROUP BY d.month_start
)
SELECT m.*,
       ROUND(100.0 * (gmv_brl - LAG(gmv_brl) OVER (ORDER BY month_start)) / LAG(gmv_brl) OVER (ORDER BY month_start), 2) AS gmv_mom_pct
FROM m;

-- Q3 Delivery time vs review score
CREATE OR REPLACE TABLE a_delivery_vs_review AS
SELECT
  CASE WHEN delivery_days < 3 THEN '01: <3 d' WHEN delivery_days < 7 THEN '02: 3-7 d'
       WHEN delivery_days < 14 THEN '03: 7-14 d' WHEN delivery_days < 21 THEN '04: 14-21 d'
       WHEN delivery_days < 30 THEN '05: 21-30 d' ELSE '06: 30+ d' END AS delivery_bucket,
  COUNT(*) AS orders,
  ROUND(AVG(review_score), 3) AS avg_review,
  ROUND(100.0 * SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS low_review_pct,
  ROUND(100.0 * SUM(is_late) / COUNT(*), 2) AS late_pct
FROM fact_orders
WHERE is_delivered = 1 AND dq_bad_chronology = 0 AND review_score IS NOT NULL
GROUP BY 1;

CREATE OR REPLACE TABLE a_late_vs_ontime AS
SELECT CASE WHEN is_late = 1 THEN 'late' ELSE 'on_time' END AS delivery_status,
       COUNT(*) AS orders, ROUND(AVG(review_score), 3) AS avg_review,
       ROUND(100.0 * SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS low_review_pct,
       ROUND(AVG(delivery_days), 2) AS avg_delivery_days
FROM fact_orders
WHERE is_delivered = 1 AND review_score IS NOT NULL
GROUP BY 1;

-- Q4 Category performance
CREATE OR REPLACE TABLE a_category_performance AS
WITH line AS (
  SELECT p.category_en, f.order_id, f.price, f.item_total
  FROM fact_order_items f JOIN dim_product p ON f.product_id = p.product_id
  WHERE f.is_revenue_order = 1
), cat AS (
  SELECT category_en, COUNT(DISTINCT order_id) AS orders, COUNT(*) AS items,
         ROUND(SUM(item_total), 2) AS gmv_brl, ROUND(AVG(price), 2) AS avg_item_price
  FROM line GROUP BY category_en
), rv AS (
  SELECT p.category_en, ROUND(AVG(o.review_score), 3) AS avg_review,
         ROUND(100.0 * SUM(o.is_late) / COUNT(o.is_late), 2) AS late_pct
  FROM (SELECT DISTINCT order_id, product_id FROM fact_order_items) x
  JOIN dim_product p ON x.product_id = p.product_id
  JOIN fact_orders o ON x.order_id = o.order_id
  GROUP BY p.category_en
)
SELECT cat.*, ROUND(100.0 * cat.gmv_brl / SUM(cat.gmv_brl) OVER (), 2) AS gmv_share_pct,
       rv.avg_review, rv.late_pct,
       RANK() OVER (ORDER BY cat.gmv_brl DESC) AS gmv_rank
FROM cat LEFT JOIN rv ON cat.category_en = rv.category_en;

-- Q5 Regional (customer state) performance
CREATE OR REPLACE TABLE a_region_performance AS
SELECT c.customer_state, c.customer_region,
       COUNT(*) AS orders, COUNT(DISTINCT f.customer_unique_id) AS customers,
       ROUND(SUM(f.order_value), 2) AS gmv_brl, ROUND(AVG(f.order_value), 2) AS aov_brl,
       ROUND(100.0 * SUM(f.freight_value) / SUM(f.order_value), 2) AS freight_share_pct,
       ROUND(AVG(CASE WHEN f.is_delivered = 1 AND f.dq_bad_chronology = 0 THEN f.delivery_days END), 2) AS avg_delivery_days,
       ROUND(100.0 * SUM(f.is_late) / COUNT(f.is_late), 2) AS late_pct,
       ROUND(AVG(f.review_score), 3) AS avg_review
FROM fact_orders f JOIN dim_customer c ON f.customer_id = c.customer_id
WHERE f.is_revenue_order = 1 AND f.items_qty > 0
GROUP BY c.customer_state, c.customer_region;

CREATE OR REPLACE TABLE a_region_rollup AS
SELECT c.customer_region, COUNT(*) AS orders, ROUND(SUM(f.order_value), 2) AS gmv_brl,
       ROUND(100.0 * SUM(f.order_value) / SUM(SUM(f.order_value)) OVER (), 2) AS gmv_share_pct,
       ROUND(AVG(CASE WHEN f.is_delivered = 1 AND f.dq_bad_chronology = 0 THEN f.delivery_days END), 2) AS avg_delivery_days,
       ROUND(100.0 * SUM(f.is_late) / COUNT(f.is_late), 2) AS late_pct,
       ROUND(AVG(f.review_score), 3) AS avg_review
FROM fact_orders f JOIN dim_customer c ON f.customer_id = c.customer_id
WHERE f.is_revenue_order = 1 AND f.items_qty > 0
GROUP BY c.customer_region;

-- Q6 Payment mix
CREATE OR REPLACE TABLE a_payment_mix AS
SELECT main_payment_type, COUNT(*) AS orders, ROUND(SUM(payment_value), 2) AS paid_brl,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS orders_share_pct,
       ROUND(AVG(max_installments), 2) AS avg_installments, ROUND(AVG(payment_value), 2) AS avg_payment_brl
FROM fact_orders
WHERE is_revenue_order = 1 AND main_payment_type IS NOT NULL
GROUP BY main_payment_type;

-- Q7 Monthly acquisition cohorts & retention (person = customer_unique_id)
CREATE OR REPLACE TABLE a_cohort_retention AS
WITH act AS (
  SELECT DISTINCT c.customer_unique_id, c.cohort_month, CAST(date_trunc('MONTH', f.purchase_ts) AS DATE) AS active_month
  FROM fact_orders f JOIN dim_customer c ON f.customer_id = c.customer_id
  WHERE f.is_revenue_order = 1
), idx AS (
  SELECT customer_unique_id, cohort_month,
         (year(active_month) - year(cohort_month)) * 12 + (month(active_month) - month(cohort_month)) AS month_number
  FROM act
), sizes AS (SELECT cohort_month, COUNT(DISTINCT customer_unique_id) AS cohort_size FROM idx WHERE month_number = 0 GROUP BY cohort_month)
SELECT i.cohort_month, s.cohort_size, i.month_number, COUNT(DISTINCT i.customer_unique_id) AS active_customers,
       ROUND(100.0 * COUNT(DISTINCT i.customer_unique_id) / s.cohort_size, 3) AS retention_pct
FROM idx i JOIN sizes s ON i.cohort_month = s.cohort_month
WHERE i.cohort_month BETWEEN DATE '2017-01-01' AND DATE '2018-08-01'
GROUP BY i.cohort_month, s.cohort_size, i.month_number;

-- Q8 Seller concentration (Pareto)
CREATE OR REPLACE TABLE a_seller_concentration AS
WITH s AS (
  SELECT seller_id, SUM(item_total) AS gmv FROM fact_order_items WHERE is_revenue_order = 1 GROUP BY seller_id
), r AS (
  SELECT seller_id, gmv, ROW_NUMBER() OVER (ORDER BY gmv DESC) AS rk, COUNT(*) OVER () AS n,
         SUM(gmv) OVER () AS total FROM s
)
SELECT CASE WHEN rk <= n * 0.01 THEN 'top_1pct' WHEN rk <= n * 0.10 THEN 'top_2_10pct'
            WHEN rk <= n * 0.50 THEN 'top_11_50pct' ELSE 'bottom_50pct' END AS seller_tier,
       COUNT(*) AS sellers, ROUND(SUM(gmv), 2) AS gmv_brl, ROUND(100.0 * SUM(gmv) / MAX(total), 2) AS gmv_share_pct
FROM r GROUP BY 1;
