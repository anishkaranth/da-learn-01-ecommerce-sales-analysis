# Power BI build guide

> A `.pbix` file cannot be produced on the Linux box this project was built on (Power BI Desktop is Windows-only
> and has no headless/CLI author mode), so this folder is a **kit**: data + model + measures + layout spec.
> Estimated build time: 45-60 min.

1. **Get the data.** Either use the subset CSVs in `powerbi/data/` (22 orders - enough to wire up the model and visuals, not for insight), or
   for the real numbers run `pip install -r requirements.txt && python scripts/download_full_data.py && python run_pipeline.py --source full`
   and use `data/clean_full/star/` (~99k orders).
2. **Load.** Power BI Desktop -> *Get data -> Text/CSV* for each of the 6 files (`fact_orders`, `fact_order_items`, `dim_date`,
   `dim_customer`, `dim_product`, `dim_seller`). In Power Query set the data types listed in `model.md`
   (zip prefixes as Text!). Locale: English (United States) - CSVs use `.` decimals and ISO dates.
3. **Model.** Model view -> create the 6 relationships from `model.md` (all *:1, single direction). Then
   *Table tools -> Mark as date table* on `dim_date[calendar_date]`. Hide all
   key / flag columns from report view.
4. **Measures.** Create a table `_Measures` (*Enter data*, one dummy column, then delete it) and paste each measure
   from `measures.dax` (one *New measure* per line block). Set formats: GMV/AOV currency, % measures percentage.
5. **Calculated column.** Add `Delivery Bucket` to `fact_orders` (DAX in `dashboard_spec.md`) and sort it by itself.
6. **Cohort matrix.** *Modeling -> New table*: `Months Since First = GENERATESERIES(0, 12, 1)` (rename column to `n`), then
   ```DAX
   Retention % =
   VAR n = SELECTEDVALUE ( 'Months Since First'[n] )
   VAR cohort = SELECTEDVALUE ( dim_customer[cohort_month] )
   VAR target = EDATE ( cohort, n )
   VAR active =
       CALCULATE ( DISTINCTCOUNT ( fact_orders[customer_unique_id] ),
           fact_orders[is_revenue_order] = 1,
           FILTER ( ALL ( dim_date ), dim_date[month_start] = target ) )
   RETURN DIVIDE ( active, [Cohort Size] )
   ```
7. **Pages.** Build the 3 pages exactly as listed in `dashboard_spec.md`; compare with the preview `results/charts/dashboard.svg`.
8. **Validate** against the SQL run (full data): GMV R$ 15,735,527.03, Revenue Orders 98,199, AOV R$ 160.24,
   Customers 94,983, Repeat 3.04 %, Avg review 4.086, Late 6.77 % (`results/metrics.json`). On the subset the
   expected values are in `results/sample/JSON.shot` (GMV R$ 3,652.99, 22 revenue orders, AOV R$ 166.05).
9. Save as `olist_sales.pbix` (not committed - binary).
