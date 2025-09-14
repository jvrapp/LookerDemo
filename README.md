# Analytics Demo — thelook_ecommerce (BigQuery)

This repository contains three SQL tasks (A, B, C) implemented in **Google BigQuery** using the public dataset [`bigquery-public-data.thelook_ecommerce`](https://console.cloud.google.com/marketplace/product/bigquery-public-data/thelook-ecommerce).  
The objective is to demonstrate SQL proficiency, analytical reasoning, and the ability to translate business requirements into reproducible queries that support the development of a practical [BI dashboard (Looker Studio)](https://lookerstudio.google.com/reporting/477b9fbe-7547-40b6-87a9-15e9d9c2a197).

---

## 📊 Tasks Overview

### Task A — Monthly Financials
- **Definition of metrics:**
  - *Completed sale*: `order_items.status = 'Complete'` AND `returned_at IS NULL`.
  - *Revenue*: `SUM(order_items.sale_price)`.
  - *COGS*: `SUM(inventory_items.cost)` joined via `inventory_item_id` (fallback by product_id if missing).
  - *Gross Profit*: Revenue − COGS.
  - *Orders*: distinct count of `order_id`.
  - *Units*: each order_item is treated as one unit.
  - *AOV (Average Order Value)*: Revenue ÷ Orders.
  - *Gross Margin %*: (Revenue − COGS) ÷ Revenue.
  - *MoM Revenue Growth*: change in Revenue vs. previous month (`LAG` window).

### Task B — New vs Returning Mix
- **Definitions:**
  - *Active customer*: user with ≥1 completed purchase in the month.
  - *New customer*: user whose **first-ever purchase** is in the given month.
  - *Returning customer*: user with prior purchases before the given month.
  - *Revenue_new*: revenue from new customers.
  - *Revenue_returning*: revenue from returning customers.
  - *% revenue from returning*: revenue_returning ÷ total revenue.

- **Assumptions:**
  - Newness defined by first purchase, not user signup (`users.created_at`).
  - Returning customers can include “resurrected” customers (after long inactivity).

### Task C — 90-Day Churn
- **Definitions:**
  - *Active customer (month m)*: user with ≥1 completed purchase in month m.
  - *Churned customer 90d (month m)*: user active in month m whose **last purchase in that month** had **no further purchases within the following 90 days**.
  - *Churn rate 90d*: churned_customers_90d ÷ active_customers (denominator restricted to months with a full 90-day observation window).

- **Important note:**  
  Churn is **assigned back to the month of last purchase**, not the month 90 days later.  
  This allows interpreting results as: *“Of the customers active in February, X% failed to repurchase within 90 days.”*  
  Recent months (within 90 days of `CURRENT_DATE`) are censored and will show churn = 0.

---

## 📅 Date Ranges

- By default, queries filter data to:
  - **Task A (Financials):** last **25 months** relative to `CURRENT_DATE`.
  - **Task B (New vs Returning):** last **60 months** to capture first-time cohorts and returning users.
  - **Task C (90-Day Churn):** last **60 months**, with **censoring** applied to the most recent ~3 months (where the 90-day horizon has not yet passed).

Date parameters are defined inside each query via a `params` CTE, e.g.:

```sql
WITH params AS (
  SELECT
    DATE_SUB(CURRENT_DATE(), INTERVAL 25 MONTH) AS start_date,
    CURRENT_DATE() AS end_date
)
```

## ▶️ How to Run the Query

1. Open the BigQuery Console.

2. Create a new SQL query and set dialect to Standard SQL.

3. Copy-paste the provided script (part1_queries.sql) into the editor.

4. Run the query.

The script executes Tasks A, B, and C in sequence using CTEs.

The final SELECT joins the results into a single fact table grouped by month.

## 📦 Output: Monthly Fact Table

The final result can be consumed directly as a fact table in a star schema for BI dashboards.

Each row = one month, with measures from all three tasks:

* From Task A (Financials): revenue, cogs, gross_profit, orders, units, aov, gross_margin_pct, mom_revenue_growth

* From Task B (New vs Returning): active_customers, new_customers, returning_customers, revenue_new, revenue_returning, pct_revenue_returning

* From Task C (Churn): active_customers, churned_customers_90d, churn_rate_90d

This table can be joined with dimension tables (e.g., product, customer, geography) to build a star schema supporting BI dashboards in Looker Studio or any visualization tool.

## ⚙️ Performance Notes

Heavy joins are constrained by date filters early in the pipeline.

Fallback cost calculation uses ROW_NUMBER() only for missing direct matches.

Window functions (LAG) are applied after aggregation to minimize scanned data.

SAFE_DIVIDE avoids division-by-zero errors in percentage calculations.