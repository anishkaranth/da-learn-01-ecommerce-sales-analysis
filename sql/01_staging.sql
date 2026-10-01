-- 01_staging.sql
-- Land every raw CSV as an all-STRING staging table (no type inference), so that all type casting
-- happens explicitly and identically in 02_cleaning.sql on both engines.
-- {{RAW_DIR}} is substituted by run_pipeline.py.
-- DuckDB : read_csv(path, header = true, all_varchar = true)
-- Databricks equivalent (used in databricks/olist_pipeline_notebook.sql):
--   SELECT * FROM read_files('/Volumes/<catalog>/<schema>/raw/<file>.csv', format => 'csv',
--          header => true, multiLine => true, escape => '"', inferColumnTypes => false)
CREATE OR REPLACE TABLE stg_orders      AS SELECT * FROM read_csv('{{RAW_DIR}}/olist_orders_dataset.csv',            header = true, all_varchar = true);
CREATE OR REPLACE TABLE stg_order_items AS SELECT * FROM read_csv('{{RAW_DIR}}/olist_order_items_dataset.csv',       header = true, all_varchar = true);
CREATE OR REPLACE TABLE stg_payments    AS SELECT * FROM read_csv('{{RAW_DIR}}/olist_order_payments_dataset.csv',    header = true, all_varchar = true);
CREATE OR REPLACE TABLE stg_reviews     AS SELECT * FROM read_csv('{{RAW_DIR}}/olist_order_reviews_dataset.csv',     header = true, all_varchar = true);
CREATE OR REPLACE TABLE stg_customers   AS SELECT * FROM read_csv('{{RAW_DIR}}/olist_customers_dataset.csv',         header = true, all_varchar = true);
CREATE OR REPLACE TABLE stg_products    AS SELECT * FROM read_csv('{{RAW_DIR}}/olist_products_dataset.csv',          header = true, all_varchar = true);
CREATE OR REPLACE TABLE stg_sellers     AS SELECT * FROM read_csv('{{RAW_DIR}}/olist_sellers_dataset.csv',           header = true, all_varchar = true);
CREATE OR REPLACE TABLE stg_category_translation AS SELECT * FROM read_csv('{{RAW_DIR}}/product_category_name_translation.csv', header = true, all_varchar = true);
