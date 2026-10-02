-- ============================================================================
-- 05_product_analysis.sql
-- Purpose : Which product is priced as if it were safe when it is not?
--           Product volume, pricing, risk, provisions, portfolio yield and
--           risk-adjusted yield.
-- Rule    : Products are ranked on Risk-Adjusted Yield, never on interest
--           rate alone.
--             Portfolio Yield %    = interest due in period / avg portfolio
--             Cost of Risk %       = provision charge in period / avg portfolio
--             Risk-Adjusted Yield  = Portfolio Yield % - Cost of Risk %
--           Period = trailing 12 months to the latest snapshot.
-- Source  : v_loan_status_clean (cleaned loan-status layer, one row per
--           snapshot_date_id x loan_id). Run 01_data_validation.sql first.
--           The raw fact_loan_status table is never queried directly here.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Product volume and pricing (all disbursed loans)
-- ----------------------------------------------------------------------------
SELECT
    p.product_id,
    p.product_name,
    p.client_type,
    ROUND(p.base_rate * 100, 2)                 AS base_rate_pct,
    COUNT(l.loan_id)                            AS loan_count,
    SUM(l.principal_amount)                     AS disbursed,
    ROUND(AVG(l.principal_amount), 0)           AS avg_ticket,
    ROUND(AVG(l.annual_rate) * 100, 2)          AS avg_granted_rate_pct,
    ROUND(AVG(l.term_months), 1)                AS avg_term_months
FROM dim_product p
LEFT JOIN fact_loan l ON l.product_id = p.product_id
GROUP BY p.product_id, p.product_name, p.client_type, p.base_rate
ORDER BY p.product_id;


-- ----------------------------------------------------------------------------
-- 2. Product risk at the latest snapshot — portfolio, PAR30, provision %
-- ----------------------------------------------------------------------------
SELECT
    p.product_name,
    SUM(s.outstanding_principal)                                     AS portfolio,
    ROUND(100.0 * SUM(s.outstanding_principal) FILTER (WHERE s.days_past_due > 30)
          / SUM(s.outstanding_principal), 2)                         AS par30_pct,
    ROUND(100.0 * SUM(s.outstanding_principal) FILTER (WHERE s.days_past_due > 90)
          / SUM(s.outstanding_principal), 2)                         AS par90_pct,
    ROUND(100.0 * SUM(s.provision_amount) / SUM(s.outstanding_principal), 2)
                                                                     AS provision_pct_of_portfolio
FROM v_loan_status_clean s
JOIN dim_product p ON p.product_id = s.product_id
WHERE s.snapshot_date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean)
GROUP BY p.product_name
ORDER BY par30_pct DESC;


-- ----------------------------------------------------------------------------
-- 3. Portfolio Yield, Cost of Risk and Risk-Adjusted Yield (trailing 12 months)
--    Interest due  : fact_schedule.interest_due with due date in the window
--                    (contractual yield — what the product is priced to earn).
--    Provision charge per product
--                  = closing provision stock - opening provision stock
--                    + provisions utilised by written-off loans leaving the book.
--    Average portfolio = mean of the 12 month-end portfolios in the window.
-- ----------------------------------------------------------------------------
WITH month_ends AS (
    SELECT
        d.date_id,
        d.full_date,
        LAG(d.date_id) OVER (ORDER BY d.full_date) AS prev_date_id
    FROM dim_date d
    WHERE d.is_month_end = 1
      AND d.date_id <= (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean)
),
bounds AS (
    SELECT
        MAX(full_date)                                AS end_date,
        (MAX(full_date) - INTERVAL '12 months')::date AS start_date
    FROM month_ends
),
window_months AS (
    SELECT m.*
    FROM month_ends m
    CROSS JOIN bounds b
    WHERE m.full_date > b.start_date AND m.full_date <= b.end_date
),
stock AS (
    SELECT snapshot_date_id, product_id,
           SUM(provision_amount)      AS provisions,
           SUM(outstanding_principal) AS portfolio
    FROM v_loan_status_clean
    GROUP BY snapshot_date_id, product_id
),
utilised AS (
    SELECT m.date_id, s.product_id, SUM(s.provision_amount) AS utilised
    FROM v_loan_status_clean s
    JOIN (
        SELECT loan_id, MAX(snapshot_date_id) AS last_id
        FROM v_loan_status_clean
        GROUP BY loan_id
    ) last_row ON last_row.loan_id = s.loan_id AND last_row.last_id = s.snapshot_date_id
    JOIN month_ends m ON m.prev_date_id = s.snapshot_date_id
    WHERE s.is_written_off = 1
    GROUP BY m.date_id, s.product_id
),
risk AS (
    SELECT
        p.product_id,
        AVG(cur.portfolio)                                                         AS avg_portfolio,
        SUM(cur.provisions - COALESCE(prev.provisions, 0) + COALESCE(u.utilised, 0)) AS provision_charge
    FROM window_months w
    CROSS JOIN dim_product p
    LEFT JOIN stock cur   ON cur.snapshot_date_id  = w.date_id      AND cur.product_id  = p.product_id
    LEFT JOIN stock prev  ON prev.snapshot_date_id = w.prev_date_id AND prev.product_id = p.product_id
    LEFT JOIN utilised u  ON u.date_id             = w.date_id      AND u.product_id    = p.product_id
    GROUP BY p.product_id
),
interest AS (
    SELECT l.product_id, SUM(sc.interest_due) AS interest_due_12m
    FROM fact_schedule sc
    JOIN fact_loan l ON l.loan_id = sc.loan_id
    JOIN dim_date  d ON d.date_id = sc.due_date_id
    CROSS JOIN bounds b
    WHERE d.full_date > b.start_date AND d.full_date <= b.end_date
    GROUP BY l.product_id
)
SELECT
    p.product_name,
    ROUND(r.avg_portfolio, 0)                                                AS avg_portfolio_12m,
    ROUND(i.interest_due_12m, 0)                                             AS interest_due_12m,
    ROUND(r.provision_charge, 0)                                             AS provision_charge_12m,
    ROUND(100.0 * i.interest_due_12m / NULLIF(r.avg_portfolio, 0), 2)        AS portfolio_yield_pct,
    ROUND(100.0 * r.provision_charge / NULLIF(r.avg_portfolio, 0), 2)        AS cost_of_risk_pct,
    ROUND(100.0 * (i.interest_due_12m - r.provision_charge) / NULLIF(r.avg_portfolio, 0), 2)
                                                                             AS risk_adjusted_yield_pct
FROM dim_product p
LEFT JOIN risk     r ON r.product_id = p.product_id
LEFT JOIN interest i ON i.product_id = p.product_id
ORDER BY risk_adjusted_yield_pct;


-- ----------------------------------------------------------------------------
-- 4. Disbursement mix by product over time (100% stacked, monthly)
-- ----------------------------------------------------------------------------
SELECT
    date_trunc('month', d.full_date)::date                           AS month,
    p.product_name,
    SUM(l.principal_amount)                                          AS disbursed,
    ROUND(100.0 * SUM(l.principal_amount)
          / SUM(SUM(l.principal_amount)) OVER (PARTITION BY date_trunc('month', d.full_date)), 2)
                                                                     AS share_of_month_pct
FROM fact_loan l
JOIN dim_date    d ON d.date_id    = l.disbursement_date_id
JOIN dim_product p ON p.product_id = l.product_id
GROUP BY date_trunc('month', d.full_date), p.product_name
ORDER BY month, p.product_name;


-- ----------------------------------------------------------------------------
-- 5. Interest rate vs PAR30 (one dot per product, bubble = portfolio)
-- ----------------------------------------------------------------------------
WITH rate AS (
    SELECT product_id, AVG(annual_rate) AS avg_rate
    FROM fact_loan
    GROUP BY product_id
)
SELECT
    p.product_name,
    ROUND(r.avg_rate * 100, 2)                                       AS avg_granted_rate_pct,
    ROUND(100.0 * SUM(s.outstanding_principal) FILTER (WHERE s.days_past_due > 30)
          / SUM(s.outstanding_principal), 2)                         AS par30_pct,
    SUM(s.outstanding_principal)                                     AS portfolio
FROM v_loan_status_clean s
JOIN dim_product p ON p.product_id = s.product_id
JOIN rate        r ON r.product_id = s.product_id
WHERE s.snapshot_date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean)
GROUP BY p.product_name, r.avg_rate
ORDER BY avg_granted_rate_pct DESC;


-- ----------------------------------------------------------------------------
-- 6. Approval rate and requested vs approved amount by product
--    Approved amount = principal actually disbursed on the resulting loan.
-- ----------------------------------------------------------------------------
SELECT
    p.product_name,
    COUNT(a.application_id)                                          AS applications,
    COUNT(*) FILTER (WHERE a.is_approved = 1)                        AS approved,
    ROUND(100.0 * COUNT(*) FILTER (WHERE a.is_approved = 1) / COUNT(*), 1)
                                                                     AS approval_rate_pct,
    ROUND(AVG(a.requested_amount), 0)                                AS avg_requested_all,
    ROUND(AVG(a.requested_amount) FILTER (WHERE a.is_approved = 1), 0) AS avg_requested_approved,
    ROUND(AVG(l.principal_amount), 0)                                AS avg_disbursed,
    ROUND(100.0 * SUM(l.principal_amount)
          / NULLIF(SUM(a.requested_amount) FILTER (WHERE l.loan_id IS NOT NULL), 0), 1)
                                                                     AS disbursed_to_requested_pct
FROM fact_application a
JOIN dim_product p    ON p.product_id = a.product_id
LEFT JOIN fact_loan l ON l.application_id = a.application_id
GROUP BY p.product_name
ORDER BY approval_rate_pct;
