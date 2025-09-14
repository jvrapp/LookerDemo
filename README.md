# Analytics Demo — thelook_ecommerce (BigQuery)

This repository contains three SQL tasks (A, B, C) solved using **Google BigQuery** and the public dataset [`bigquery-public-data.thelook_ecommerce`](https://console.cloud.google.com/marketplace/product/bigquery-public-data/thelook-ecommerce).  
The goal is to demonstrate SQL fluency, analytic reasoning, and ability to translate business requirements into reproducible queries to create a useful BI dashobard ['https://lookerstudio.google.com/reporting/477b9fbe-7547-40b6-87a9-15e9d9c2a197']

---

## 📊 Tasks Overview

### Task A — Monthly Financials
- **Definition of metrics:**
  - *Completed sale*: `order_items.status = 'Complete'` AND `returned_at IS NULL`.
  - *Revenue*: `SUM(order_items.sale_price)`.
  - *COGS*: `SUM(inventory_items.cost)` joined via `inventory_item_id`.
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
  - *Churn rate 90d*: churned_customers_90d ÷ active_customers.

- **Important note:**  
  Churn is **assigned back to the month of last purchase**, not the month 90 days later.  
  This allows interpreting results as: *“Of the customers active in February, X% failed to repurchase within 90 days.”*  
  Recent months (within 90 days of `CURRENT_DATE`) are censored and will show churn = 0.

---

## 📅 Date Ranges

- By default, queries filter data to:
  - **Task A & B:** last 13 months relative to `CURRENT_DATE`.
  - **Task C:** last 60 months for historical churn, but censoring applied to the last 3 months.
- Parameters are defined in a CTE `params`, e.g.:

```sql
WITH params AS (
  SELECT
    DATE_SUB(CURRENT_DATE(), INTERVAL 13 MONTH) AS start_date,
    CURRENT_DATE() AS end_date
)
