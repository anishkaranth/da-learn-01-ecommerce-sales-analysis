# Dashboard spec (3 pages) - mirrors `results/charts/dashboard.svg`

Theme: 16:9 canvas, primary `#1F6F8B`, accent `#E07A5F`, positive `#81B29A`. Currency format `R$ #,0.00`.
Global slicers on every page (sync slicers): `dim_date[month_start]` (between), `dim_customer[customer_region]` (dropdown), `fact_orders[order_status]` (dropdown, default all).

## Page 1 - Executive overview
| # | Visual | Fields | Notes |
|---|---|---|---|
| 1-7 | Card (new card visual) | `[GMV]`, `[Revenue Orders]`, `[AOV]`, `[Customers]`, `[Repeat Customer %]`, `[Avg Review]`, `[Late Delivery %]` | top row |
| 8 | Line & clustered column chart | X `dim_date[month_start]` (continuous), column `[GMV]`, line `[AOV]` | visual filter month_start 2017-01-01..2018-08-01 |
| 9 | Clustered bar | Y `dim_product[category_en]`, X `[Item GMV]`, tooltip `[Avg Review]` | Top N = 10 by `[Item GMV]` |
| 10 | Donut | Legend `fact_orders[main_payment_type]`, values `[Revenue Orders]` | |
| 11 | KPI | value `[GMV]`, trend `dim_date[month_start]`, target `[GMV PY]` | |

## Page 2 - Delivery & customer satisfaction
| # | Visual | Fields | Notes |
|---|---|---|---|
| 1 | Clustered column | X delivery bucket (calculated column below), Y `[Avg Review]`, tooltip `[Low Review %]`, `[Orders]` | bucket order = sort column |
| 2 | Clustered column | X `fact_orders[is_late]` (0 = on time / 1 = late), Y `[Avg Review]`, `[Low Review %]` | |
| 3 | Filled map / Shape map (Brazil states) | Location `dim_customer[customer_state]`, color saturation `[Avg Delivery Days]` | fallback: bar chart by state |
| 4 | Table | `dim_customer[customer_state]`, `[GMV]`, `[AOV]`, `[Avg Delivery Days]`, `[Late Delivery %]`, `[Avg Review]` | conditional formatting on Late % |
| 5 | Line | X `dim_date[month_start]`, Y `[Late Delivery %]`, secondary `[Avg Review]` | shows the Nov-2017 / Feb-Mar-2018 spikes |

Delivery bucket calculated column (fact_orders):
```DAX
Delivery Bucket =
SWITCH ( TRUE (),
    ISBLANK ( fact_orders[delivery_days] ), BLANK (),
    fact_orders[delivery_days] < 3, "01: <3 d", fact_orders[delivery_days] < 7, "02: 3-7 d",
    fact_orders[delivery_days] < 14, "03: 7-14 d", fact_orders[delivery_days] < 21, "04: 14-21 d",
    fact_orders[delivery_days] < 30, "05: 21-30 d", "06: 30+ d" )
```

## Page 3 - Customers, cohorts & sellers
| # | Visual | Fields | Notes |
|---|---|---|---|
| 1 | Matrix (heatmap) | Rows `dim_customer[cohort_month]`, columns `Months Since First[n]`, values `[Retention %]` | background color scale white -> `#1F6F8B` (see BUILD_GUIDE step 6) |
| 2 | Cards | `[Repeat Customer %]`, `[Cohort Size]` | |
| 3 | Clustered bar | Y `dim_seller[seller_state]`, X `[Item GMV]` | |
| 4 | Pareto (line & column) | X `dim_seller[seller_id]` sorted by `[Item GMV]` desc, column `[Item GMV]`, line running % | optional |
| 5 | Table | `dim_product[category_en]`, `[Item GMV]`, `[Item GMV Share %]`, `[Avg Item Price]`, `[Avg Review]` | |

## Data-quality tooltip page (optional)
Import `results/tables/dq_assertions.csv` and `dq_row_counts.csv` as disconnected tables and show them in a table visual.
