-- Metabase text variables: kol_abc, rev_abc, marg_abc. The last filters the profit class.
WITH retail AS (
    SELECT
        dr_cdrugs::text AS sku,
        dr_ndrugs AS product_name,
        dr_kol::numeric AS quantity,
        dr_croz::numeric * dr_kol::numeric AS gross_sales,
        dr_czak::numeric * dr_kol::numeric AS cost_amount
    FROM sales
    WHERE dr_tdoc = 'Розничная реализация'
      AND dr_kol::numeric > 0
      AND nullif(btrim(dr_cdrugs::text), '') IS NOT NULL
      AND dr_croz IS NOT NULL
      AND dr_czak IS NOT NULL
),
sku_totals AS (
    SELECT
        sku,
        max(product_name) AS product_name,
        sum(quantity) AS units,
        sum(gross_sales) AS sales_before_discount,
        sum(gross_sales - cost_amount) AS profit_before_discount
    FROM retail
    GROUP BY sku
),
sku_metrics AS (
    SELECT t.sku, m.metric, m.amount
    FROM sku_totals AS t
    CROSS JOIN LATERAL (
        VALUES ('units', t.units),
               ('sales_before_discount', t.sales_before_discount),
               ('profit_before_discount', t.profit_before_discount)
    ) AS m(metric, amount)
),
ranked AS (
    SELECT
        sku,
        metric,
        sum(amount) OVER (
            PARTITION BY metric ORDER BY amount DESC, sku
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / sum(amount) OVER (PARTITION BY metric) AS cumulative_share
    FROM sku_metrics
    WHERE amount > 0
),
classes AS (
    SELECT
        sku,
        metric,
        CASE WHEN cumulative_share <= 0.80 THEN 'A'
             WHEN cumulative_share <= 0.95 THEN 'B'
             ELSE 'C' END AS abc_class
    FROM ranked
)
SELECT
    t.sku,
    t.product_name,
    t.units,
    round(t.sales_before_discount, 2) AS sales_before_discount,
    round(t.profit_before_discount, 2) AS profit_before_discount,
    round(100 * t.profit_before_discount / nullif(t.sales_before_discount, 0), 2) AS margin_pct,
    u.abc_class AS quantity_class,
    r.abc_class AS sales_class,
    p.abc_class AS profit_class
FROM sku_totals AS t
LEFT JOIN classes AS u ON u.sku = t.sku AND u.metric = 'units'
LEFT JOIN classes AS r ON r.sku = t.sku AND r.metric = 'sales_before_discount'
LEFT JOIN classes AS p ON p.sku = t.sku AND p.metric = 'profit_before_discount'
WHERE true
[[ AND u.abc_class = {{kol_abc}} ]]
[[ AND r.abc_class = {{rev_abc}} ]]
[[ AND p.abc_class = {{marg_abc}} ]]
ORDER BY quantity_class, sales_class, profit_class, t.sku;
