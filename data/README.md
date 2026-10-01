# Data

| Folder | Content | In git? |
|---|---|---|
| `raw/` | **Reproducible subset** of the raw Olist CSVs (original columns, values copied verbatim) | yes |
| `clean/cleaned/` | Cleaned entity tables from `sql/02_cleaning.sql`, run on the subset | yes |
| `raw_full/` | Full Kaggle CSVs (~63 MB) - `python scripts/download_full_data.py` | no (`.gitignore`) |
| `clean_full/` | Cleaned + star-schema tables from the full run (`--source full`) | no (`.gitignore`) |

The star-schema tables from the subset run are in `../powerbi/data/`.

## Source
* Original: **Brazilian E-Commerce Public Dataset by Olist** - https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
* License: **CC BY-NC-SA 4.0** (attribution, non-commercial, share-alike) - this repo is a non-commercial learning project and keeps the same license for the data.
* Mirror used (no Kaggle API key available): https://github.com/0PeterAdel/Brazilian-ECommerce/tree/master/0.DataSet (raw CSVs identical in shape to Kaggle: 99,441 orders, 112,650 items, 103,886 payments, 99,224 reviews, 99,441 customers, 32,951 products, 3,095 sellers, 71 translations). SHA-256 of every file is pinned in `scripts/download_full_data.py`.
* `olist_geolocation_dataset.csv` (1M rows, ~60 MB) is **not used** by this project and not included.

## Why a subset in git
The full files are 0.2-17.7 MB each (63 MB total), and this repo was published through a text-only GitHub API, so committing ~63 MB of CSV was not feasible (the subset is deliberately tiny: it is a smoke-test / wiring dataset, not an analysis sample). **All numbers in `results/` come from the FULL dataset**; the subset lets anyone run the pipeline in seconds without downloading anything.

## Subset rule (`scripts/make_sample.py`, deterministic)
1. orders with `order_id < '001'` (order_id is a uniform 32-hex hash -> unbiased ~0.025% of orders, all periods and statuses) -> **22 orders**
2. all their order_items (23), payments (22), reviews (22)
3. the customers (22), products (22) and sellers (22) they reference
4. the full category translation table (71)
