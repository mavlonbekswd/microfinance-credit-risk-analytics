-- ============================================================================
-- 02_portfolio_analysis.sql
-- Purpose : Portfolio size and growth — disbursement volume, ticket size,
--           outstanding balance, active loans and active clients.
-- Rule    : Balances come from v_loan_status_clean at month-end snapshots only.
--           Volumes (disbursement) come from fact_loan.
-- Source  : v_loan_status_clean (cleaned loan-status layer, one row per
--           snapshot_date_id x loan_id). Run 01_data_validation.sql first.
--           The raw fact_loan_status table is never queried directly here.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Lifetime disbursement, loan count and average ticket
-- ----------------------------------------------------------------------------
SELECT
    COUNT(*)                                 AS loan_count,
    SUM(principal_amount)                    AS total_disbursed,
    ROUND(AVG(principal_amount), 0)          AS avg_ticket,
    ROUND(AVG(annual_rate) * 100, 2)         AS avg_annual_rate_pct,
    ROUND(AVG(term_months), 1)               AS avg_term_months
FROM fact_loan;


-- ----------------------------------------------------------------------------
-- 2. Disbursement by year, with year-to-date comparison on equal days
--    (latest data year is partial: Jan–Jun 2026)
-- ----------------------------------------------------------------------------
SELECT
    d.year,
    COUNT(*)                         AS loans_disbursed,
    SUM(l.principal_amount)          AS disbursed,
    ROUND(AVG(l.principal_amount),0) AS avg_ticket
FROM fact_loan l
JOIN dim_date d ON d.date_id = l.disbursement_date_id
GROUP BY d.year
ORDER BY d.year;

-- Disbursed YTD vs prior-year YTD (same calendar window)
WITH latest AS (
    SELECT d.full_date
    FROM dim_date d
    WHERE d.date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean)
)
SELECT
    SUM(l.principal_amount) FILTER (
        WHERE d.full_date BETWEEN date_trunc('year', latest.full_date)::date AND latest.full_date
    ) AS disbursed_ytd,
    SUM(l.principal_amount) FILTER (
        WHERE d.full_date BETWEEN (date_trunc('year', latest.full_date) - INTERVAL '1 year')::date
                              AND (latest.full_date - INTERVAL '1 year')::date
    ) AS disbursed_prior_ytd
FROM fact_loan l
JOIN dim_date d ON d.date_id = l.disbursement_date_id
CROSS JOIN latest
GROUP BY latest.full_date;


-- ----------------------------------------------------------------------------
-- 3. Current portfolio outstanding (latest snapshot)
--    Validated (cleaned layer): 130,134,379,500 UZS at snapshot_date_id = 1277
--    (2026-06-30). The raw table's 260,268,759,000 double-counts duplicated
--    rows and is superseded — see 01_data_validation.sql §10-11.
-- ----------------------------------------------------------------------------
SELECT
    SUM(outstanding_principal) AS portfolio_outstanding
FROM v_loan_status_clean
WHERE snapshot_date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean);


-- ----------------------------------------------------------------------------
-- 4. Monthly portfolio trend (42 month-ends)
--    Joined to dim_date with is_month_end = 1 so that no snapshot is
--    double-counted.
-- ----------------------------------------------------------------------------
SELECT
    d.full_date                                   AS month_end,
    COUNT(DISTINCT s.loan_id)                     AS loans_on_book,
    SUM(s.outstanding_principal)                  AS portfolio_outstanding,
    ROUND(
        100.0 * SUM(s.outstanding_principal)
        / NULLIF(LAG(SUM(s.outstanding_principal), 12) OVER (ORDER BY d.full_date), 0)
        - 100, 2
    )                                             AS yoy_growth_pct
FROM v_loan_status_clean s
JOIN dim_date d ON d.date_id = s.snapshot_date_id
WHERE d.is_month_end = 1
GROUP BY d.full_date
ORDER BY d.full_date;


-- ----------------------------------------------------------------------------
-- 5. Active loans and active clients — latest snapshot vs one year earlier
--    Active loan  = loan present in the month-end snapshot with
--                   outstanding_principal > 0 and not written off.
--    Active client = distinct client holding at least one active loan.
-- ----------------------------------------------------------------------------
WITH latest AS (
    SELECT date_id, full_date
    FROM dim_date
    WHERE date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean)
),
prior_year AS (
    SELECT d.date_id
    FROM dim_date d
    CROSS JOIN latest
    WHERE d.full_date = (latest.full_date - INTERVAL '1 year')::date
      AND d.is_month_end = 1
)
SELECT
    d.full_date                                  AS snapshot_date,
    COUNT(DISTINCT s.loan_id)                    AS active_loans,
    COUNT(DISTINCT l.client_id)                  AS active_clients,
    SUM(s.outstanding_principal)                 AS active_portfolio
FROM v_loan_status_clean s
JOIN fact_loan l ON l.loan_id = s.loan_id
JOIN dim_date  d ON d.date_id = s.snapshot_date_id
WHERE s.snapshot_date_id IN (SELECT date_id FROM latest
                             UNION ALL
                             SELECT date_id FROM prior_year)
  AND s.outstanding_principal > 0
  AND s.is_written_off = 0
GROUP BY d.full_date
ORDER BY d.full_date;


-- ----------------------------------------------------------------------------
-- 6. Monthly active loans and active clients (trend)
-- ----------------------------------------------------------------------------
SELECT
    d.full_date                  AS month_end,
    COUNT(DISTINCT s.loan_id)    AS active_loans,
    COUNT(DISTINCT l.client_id)  AS active_clients
FROM v_loan_status_clean s
JOIN fact_loan l ON l.loan_id = s.loan_id
JOIN dim_date  d ON d.date_id = s.snapshot_date_id
WHERE d.is_month_end = 1
  AND s.outstanding_principal > 0
  AND s.is_written_off = 0
GROUP BY d.full_date
ORDER BY d.full_date;


-- ----------------------------------------------------------------------------
-- 7. Repeat borrowing — clients with more than one disbursed loan
--    (The dataset guide states 2,293 clients have more than one loan.)
-- ----------------------------------------------------------------------------
SELECT
    loans_per_client,
    COUNT(*) AS clients
FROM (
    SELECT client_id, COUNT(*) AS loans_per_client
    FROM fact_loan
    GROUP BY client_id
) c
GROUP BY loans_per_client
ORDER BY loans_per_client;
