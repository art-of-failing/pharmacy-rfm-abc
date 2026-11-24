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
receipt_quality AS (
    SELECT count(DISTINCT receipt_id) FILTER (WHERE version_count > 1) AS conflicting_receipt_ids
    FROM checked_receipts
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
),
segment_map (segment_id, segment_name, codes) AS (
    VALUES
        (1, 'Самые лояльные клиенты', ARRAY['111']),
        (2, 'Много тратят, редко ходят', ARRAY['121', '131', '221', '231', '331']),
        (3, 'Средне тратят, редко ходят', ARRAY['122', '132', '222', '232']),
        (4, 'Средне тратят, часто ходят', ARRAY['112', '212']),
        (5, 'Давно не были', ARRAY['211', '311', '312', '321', '322', '332']),
        (6, 'Низкая сумма покупок', ARRAY['113', '123', '133', '213', '223', '233', '313', '323', '333'])
),
segment_summary AS (
    SELECT
        m.segment_id,
        string_agg(DISTINCT r.rfm_code, ', ' ORDER BY r.rfm_code) AS observed_rfm_codes,
        count(*) AS customer_count,
        sum(receipt_count)::bigint AS receipt_count,
        sum(customer_spend) AS purchase_amount,
        round(sum(customer_spend) / sum(receipt_count), 2) AS average_receipt
    FROM rfm_codes AS r
    JOIN segment_map AS m ON r.rfm_code = ANY(m.codes)
    GROUP BY m.segment_id
)
SELECT
    settings.as_of_date,
    quality.conflicting_receipt_ids,
    names.segment_name,
    summary.observed_rfm_codes,
    coalesce(summary.customer_count, 0) AS customer_count,
    coalesce(summary.receipt_count, 0) AS receipt_count,
    round(
        100.0 * coalesce(summary.customer_count, 0)
        / nullif(sum(summary.customer_count) OVER (), 0), 2
    ) AS customer_share_pct,
    coalesce(summary.purchase_amount, 0) AS purchase_amount,
    round(
        100.0 * coalesce(summary.purchase_amount, 0)
        / nullif(sum(summary.purchase_amount) OVER (), 0), 2
    ) AS purchase_amount_share_pct,
    summary.average_receipt
FROM segment_map AS names
CROSS JOIN settings
CROSS JOIN receipt_quality AS quality
LEFT JOIN segment_summary AS summary USING (segment_id)
ORDER BY names.segment_id;
