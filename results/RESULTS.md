# Results - full Olist dataset (99,441 orders, 2016-09-04 .. 2018-10-17)

Run: `python run_pipeline.py --source full` on DuckDB 1.5.6 (Python 3.13), 2026-10-01. Every number below is copied
from `results/tables/*.csv` / `metrics.json` produced by that run. Currency BRL. Revenue (GMV) = item price + freight
of orders that are not `canceled`/`unavailable`. Trend charts use the complete months 2017-01 .. 2018-08.

![dashboard](charts/dashboard.svg)

## Headline KPIs
| KPI | Value |
|---|---|
| Orders (all statuses) | 99,441 |
| Revenue orders (not canceled/unavailable, with items) | 98,199 |
| GMV | R$ 15,735,527.03 (products R$ 13,494,400.74 + freight R$ 2,241,126.29) |
| AOV | R$ 160.24 (1.142 items/order) |
| Unique customers (`customer_unique_id`) | 94,983 |
| Repeat customers (>1 order) | 3.04 % |
| Avg review score | 4.086 / 5 (14.69 % of reviews are 1-2 stars) |
| Delivery time, purchase -> customer | mean 12.57 d, median 10.23 d |
| Late deliveries (delivered after promised date) | 6.77 % of delivered orders |
| Cancel rate | 0.63 % |

## Key findings
1. **Fast growth, Black-Friday spike.** GMV Jan-Aug 2018 was R$ 8.59m vs R$ 3.57m in Jan-Aug 2017 (**+140.4 %**). Nov-2017 was the
   peak month (7,421 orders, R$ 1.17m, **+53.3 % MoM**), followed by -26.5 % in Dec. Growth plateaued in 2018 at ~R$ 1.0-1.16m/month. AOV stayed flat (R$ 146.67-174.01).
2. **Late delivery destroys satisfaction.** Late orders average **2.27 stars vs 4.29** on-time, and **62.4 %** of late orders get a 1-2 star review
   (on-time: 9.3 %). By delivery time: <3 days -> 4.48, 21-30 days -> 3.61, 30+ days -> **2.25** (63 % low reviews).
   Months with late-rate spikes (Nov-2017 12.4 %, Feb-2018 14.1 %, Mar-2018 19.0 %) are exactly the months where the average review dropped below 4.
3. **Geography = logistics problem.** The Southeast is 64.6 % of GMV (SP alone 37.4 %) and gets orders in **10.8 days** on average; the North
   waits **22.6 days** and the Northeast 20.0 days. SP delivers in 8.77 d with 4.49 % late; AL has 21.41 % late, MA 17.43 %. Remote states also pay
   more freight (RR 22.2 % of order value vs SP 12.2 %) but have a higher AOV (e.g. PB R$ 264.64 vs SP R$ 142.93).
4. **Category mix.** Top categories by GMV: health_beauty R$ 1.44m (9.14 %), watches_gifts R$ 1.30m (8.25 %), bed_bath_table R$ 1.24m (7.88 %),
   sports_leisure R$ 1.15m, computers_accessories R$ 1.05m. bed_bath_table is the #1 by orders (9,399) but has the lowest review of the top 5 (3.92).
5. **Almost no retention.** Only 3.04 % of customers ever order twice; on average just **0.46 %** of a monthly cohort buys again in month +1
   and ~0.2-0.3 % in months +2..+6. Olist growth is acquisition-driven -> retention/CRM is the largest untapped lever.
6. **Concentrated supply, card-financed demand.** The top 1 % of sellers (30) generate **25.3 %** of GMV and the top 10 % (305) **66.6 %**; the bottom
   50 % of sellers only 3.5 %. Credit card is the main payment for **75.5 %** of orders with **3.55 installments** on average; boleto 19.9 %.

## Data quality (what the cleaning found / did)
| Entity | Raw rows | Clean rows | Treatment |
|---|---|---|---|
| orders | 99,441 | 99,441 | types parsed; 166 with timestamps before purchase flagged & excluded from delivery KPIs; 8 'delivered' without date flagged |
| order_items | 112,650 | 112,650 | 4,074 price outliers (> Q3 + 3*IQR) and 1,117 top-1 % prices flagged (kept - real luxury items); 4,124 lines with freight > price flagged |
| payments | 103,886 | 103,886 | 3 `not_defined` -> `unknown`; 2 zero-installment rows -> 1; 9 zero-value voucher rows flagged |
| reviews | 99,224 | **98,673** | **551** older duplicate reviews per order dropped (latest answer kept); 814 review_ids are reused across orders (kept) |
| customers | 99,441 | 99,441 | zip prefix re-padded to 5 chars; city trim/lower/accent-strip (0 changes needed - source already normalized) |
| products | 32,951 | 32,951 | 610 missing categories -> `unknown`; 13 products in 2 untranslated categories keep the PT name; 4 weights of 0 g -> NULL |
| sellers | 3,095 | 3,095 | same text standardization as customers |

Referential integrity: 0 orphan items / payments / reviews / orders. 775 orders have no items (mostly unavailable/canceled; revenue 0) and 1 order has no payment row.
1,021 orders differ by > R$ 1 between payments and price + freight (interest on installments / vouchers) - GMV uses price + freight.
**All 10 assertions in `dq_assertions` PASS.**

Cross-engine check: the same SQL was also run on a Databricks serverless SQL warehouse; all 21 table row counts and the headline KPIs are identical (only the approximate top-1 % price flag differs: 1,134 vs 1,117). See `../databricks/run_outputs/duckdb_vs_databricks.json`.

## Charts (SVG)
`charts/dashboard.svg` (6-panel preview) and the individual panels: `monthly_gmv_aov.svg`, `delivery_vs_review.svg`, `category_top10.svg`,
`state_gmv_delivery.svg`, `cohort_retention.svg`, `payment_mix.svg`.

## Files
* `metrics.json` - all KPIs + data-quality stats + engine/timings
* `JSON.shot` - headline KPI snapshot + run config
* `tables/` - every `a_*` (analysis) and `dq_*` (quality) table as CSV
* `sample/JSON.shot` - the same pipeline on the 22-order repo subset (`--source sample`) for verification, not for insight
