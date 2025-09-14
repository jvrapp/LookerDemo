WITH params AS (
  SELECT DATE_SUB(CURRENT_DATE(), INTERVAL 25 MONTH) AS start_date,
         CURRENT_DATE() AS end_date
),

-- 1) Sold items within time range
sales AS (
  SELECT
    oi.id AS order_item_id,
    oi.order_id,
    oi.user_id,
    oi.product_id,
    oi.inventory_item_id,
    oi.sale_price,
    oi.created_at AS item_ts,
    DATE_TRUNC(DATE(oi.created_at), MONTH) AS month
  FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi
  CROSS JOIN params p
  WHERE
    oi.status = 'Complete'
    AND oi.returned_at IS NULL
    AND DATE(oi.created_at) BETWEEN p.start_date AND p.end_date
),

-- 2) Inventory costs
inv AS (
  SELECT
    id AS inventory_item_id,
    product_id,
    cost,
    created_at AS cost_ts
  FROM `bigquery-public-data.thelook_ecommerce.inventory_items`
),

-- 3) Direct cost by inventory_item_id
direct_cost AS (
  SELECT
    s.order_item_id,
    i.cost AS unit_cost_direct
  FROM sales s
  JOIN inv i
    ON i.inventory_item_id = s.inventory_item_id
),

-- 4) Fallback cost (if no direct match): last product cost <= item timestamp
fallback_cost AS (
  SELECT
    s.order_item_id,
    i.cost AS unit_cost_fallback,
    ROW_NUMBER() OVER (
      PARTITION BY s.order_item_id
      ORDER BY i.cost_ts DESC
    ) AS rn
  FROM sales s
  JOIN inv i
    ON i.product_id = s.product_id
   AND i.cost_ts   <= s.item_ts
  WHERE s.order_item_id NOT IN (SELECT order_item_id FROM direct_cost)
),

fallback_cost_final AS (
  SELECT order_item_id, unit_cost_fallback
  FROM fallback_cost
  WHERE rn = 1
),

-- 5) Consolidate unit cost (direct > fallback > 0)
sales_costed AS (
  SELECT
    s.*,
    COALESCE(d.unit_cost_direct, f.unit_cost_fallback, 0.0) AS unit_cost
  FROM sales s
  LEFT JOIN direct_cost d USING (order_item_id)
  LEFT JOIN fallback_cost_final f USING (order_item_id)
),

RESULTS_A AS(
-- 6) Monthly aggregates and metrics
SELECT
  month,

  -- Total Revenue
  SUM(sale_price) AS revenue,

  -- COGS: one unit per row
  SUM(unit_cost) AS cogs,

  SUM(sale_price) - SUM(unit_cost) AS gross_profit,

  COUNT(DISTINCT order_id) AS orders,         -- orders with at least one completed item in the month
  COUNT(*)                  AS units,         -- one unit per row
  SAFE_DIVIDE(SUM(sale_price), COUNT(DISTINCT order_id)) AS aov,

  SAFE_DIVIDE(
    SUM(sale_price) - SUM(unit_cost),
    NULLIF(SUM(sale_price), 0)
  ) AS gross_margin_pct,

  -- MoM revenue growth
  SAFE_DIVIDE(
    SUM(sale_price) - LAG(SUM(sale_price)) OVER (ORDER BY month),
    LAG(SUM(sale_price)) OVER (ORDER BY month)
  ) AS mom_revenue_growth

FROM sales_costed
GROUP BY month
ORDER BY month),

-- Task B — New vs Returning Mix
paramsB AS (
  SELECT DATE_SUB(CURRENT_DATE(), INTERVAL 60 MONTH) AS start_date,
         CURRENT_DATE() AS end_date
),

-- 1) Completed sales
salesB AS (
  SELECT
    oi.user_id,
    oi.sale_price,
    DATE_TRUNC(DATE(oi.created_at), MONTH) AS month,
    oi.created_at AS item_ts
  FROM `bigquery-public-data.thelook_ecommerce.order_items` oi
  CROSS JOIN paramsB p
  WHERE oi.status = 'Complete'
    AND oi.returned_at IS NULL
    AND DATE(oi.created_at) BETWEEN p.start_date AND p.end_date
),

-- 2) First purchase per user (cohort definition)
first_purchase AS (
  SELECT
    user_id,
    MIN(DATE_TRUNC(DATE(item_ts), MONTH)) AS first_purchase_month
  FROM salesB
  GROUP BY user_id
),

-- 3) Classification new vs returning
classified_sales AS (
  SELECT
    s.month,
    s.user_id,
    s.sale_price,
    CASE
      WHEN s.month = f.first_purchase_month THEN 'new'
      ELSE 'returning'
    END AS customer_type
  FROM salesB s
  JOIN first_purchase f USING (user_id)
),

-- 4) Aggregates
agg AS (
  SELECT
    month,
    COUNT(DISTINCT user_id) AS active_customers,
    COUNT(DISTINCT IF(customer_type='new', user_id, NULL)) AS new_customers,
    COUNT(DISTINCT IF(customer_type='returning', user_id, NULL)) AS returning_customers,
    SUM(IF(customer_type='new', sale_price, 0)) AS revenue_new,
    SUM(IF(customer_type='returning', sale_price, 0)) AS revenue_returning
  FROM classified_sales
  GROUP BY month
),

-- 5) Output with % revenue from returning
RESULTS_B AS (
SELECT
  month,
  active_customers,
  new_customers,
  returning_customers,
  revenue_new,
  revenue_returning,
  SAFE_DIVIDE(revenue_returning, revenue_new + revenue_returning) AS pct_revenue_returning
FROM agg
ORDER BY month),

-- Task C — 90-Day Churn
-- Definition: churn is assigned to the MONTH of the last purchase
-- if no repurchases occur in the following 90 days.

paramsC AS (
  SELECT 
    DATE_SUB(CURRENT_DATE(), INTERVAL 60 MONTH) AS start_date,
    CURRENT_DATE() AS end_date,
    TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY) AS cutoff_ts -- last date with full 90d window
),

-- 1) Completed sales
salesC AS (
  SELECT
    oi.user_id,
    oi.created_at AS item_ts,
    DATE_TRUNC(DATE(oi.created_at), MONTH) AS month
  FROM `bigquery-public-data.thelook_ecommerce.order_items` oi
  CROSS JOIN paramsC p
  WHERE oi.status = 'Complete'
    AND oi.returned_at IS NULL
    AND DATE(oi.created_at) BETWEEN p.start_date AND p.end_date
),

-- 2) Last purchase per user per month
user_month_last AS (
  SELECT
    user_id,
    month,
    MAX(item_ts) AS last_purchase_ts
  FROM salesC
  GROUP BY user_id, month
),

-- 3) Check for repurchase within 90 days after last purchase
retention_check AS (
  SELECT
    u.user_id,
    u.month,
    u.last_purchase_ts,
    MIN(s.item_ts) AS next_purchase_ts
  FROM user_month_last u
  LEFT JOIN sales s
    ON s.user_id = u.user_id
   AND s.item_ts > u.last_purchase_ts
   AND s.item_ts <= TIMESTAMP_ADD(u.last_purchase_ts, INTERVAL 90 DAY)
  GROUP BY u.user_id, u.month, u.last_purchase_ts
),

-- 4) Churn classification + censoring
classified AS (
  SELECT
    r.month,
    r.user_id,
    r.last_purchase_ts,
    CASE WHEN r.last_purchase_ts <= (SELECT cutoff_ts FROM paramsC) THEN 1 ELSE 0 END AS full_window,
    CASE WHEN r.last_purchase_ts <= (SELECT cutoff_ts FROM paramsC)
              AND r.next_purchase_ts IS NULL
         THEN 1 ELSE 0 END AS churned_90d
  FROM retention_check r
),

-- 5) Aggregates (denominator = only evaluable months)
RESULTS_C AS (
SELECT
  month,
  COUNT(DISTINCT user_id) AS active_customers,
  COUNT(DISTINCT IF(churned_90d=1, user_id, NULL)) AS churned_customers_90d,
  SAFE_DIVIDE(
    COUNT(DISTINCT IF(churned_90d=1, user_id, NULL)),
    COUNT(DISTINCT IF(full_window=1, user_id, NULL))       -- only evaluable months
  ) AS churn_rate_90d
FROM classified
GROUP BY month
ORDER BY month)

-- Final join of all results
SELECT 
    a.*,
    b.*,
    c.*
FROM RESULTS_A a
LEFT JOIN RESULTS_B b ON a.month = b.month
LEFT JOIN RESULTS_C c ON a.month = c.month
ORDER BY a.month;
