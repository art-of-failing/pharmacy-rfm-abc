WITH settings AS (
    SELECT date '2022-06-10' AS as_of_date
),
receipt_versions AS (
    SELECT DISTINCT
        btrim(doc_id::text) AS receipt_id,
        card::text AS customer_id,
        datetime::date AS purchased_at,
        summ::numeric AS purchase_amount
    FROM bonuscheques
    CROSS JOIN settings
    WHERE card::text ~ '^[0-9]+$'
      AND nullif(btrim(doc_id::text), '') IS NOT NULL
      AND datetime < settings.as_of_date
      AND summ IS NOT NULL
),
checked_receipts AS (
    SELECT *, count(*) OVER (PARTITION BY receipt_id) AS version_count
    FROM receipt_versions
),
receipts AS (
    SELECT customer_id, purchased_at, purchase_amount
    FROM checked_receipts
    WHERE version_count = 1
),
customer_metrics AS (
    SELECT
        r.customer_id,
        s.as_of_date - max(r.purchased_at)::date AS days_since_purchase,
        count(*) AS receipt_count,
        sum(r.purchase_amount) AS customer_spend
    FROM receipts AS r
    CROSS JOIN settings AS s
    GROUP BY r.customer_id, s.as_of_date
),
scores AS (
    SELECT
        *,
        CASE WHEN days_since_purchase <= 18 THEN 1
             WHEN days_since_purchase <= 62 THEN 2
             ELSE 3 END AS r_score,
        CASE WHEN receipt_count >= 7 THEN 1
             WHEN receipt_count >= 2 THEN 2
             ELSE 3 END AS f_score,
        CASE WHEN customer_spend >= 6400 THEN 1
             WHEN customer_spend > 1000 THEN 2
             ELSE 3 END AS m_score
    FROM customer_metrics
),
rfm_codes AS (
    SELECT *, concat(r_score, f_score, m_score) AS rfm_code
    FROM scores
)
SELECT rfm_code, count(*) AS customer_count
FROM rfm_codes
GROUP BY rfm_code
ORDER BY rfm_code;
