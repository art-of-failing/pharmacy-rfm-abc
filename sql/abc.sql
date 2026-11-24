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
),
class_metrics AS (
    SELECT
        m.metric,
        coalesce(c.abc_class, 'unclassified') AS abc_class,
        count(*) AS sku_count,
        sum(m.amount) AS metric_total
    FROM sku_metrics AS m
    LEFT JOIN classes AS c ON c.sku = m.sku AND c.metric = m.metric
    GROUP BY m.metric, coalesce(c.abc_class, 'unclassified')
)
SELECT
    metric,
    abc_class,
    sku_count,
    round(100.0 * sku_count / sum(sku_count) OVER (PARTITION BY metric), 2) AS sku_share_pct,
    round(metric_total, 2) AS metric_total,
    CASE WHEN abc_class <> 'unclassified' THEN
        round(100.0 * metric_total / nullif(
            sum(metric_total) FILTER (WHERE abc_class <> 'unclassified') OVER (PARTITION BY metric),
            0
        ), 2)
    END AS positive_total_share_pct
FROM class_metrics
ORDER BY metric, abc_class;
