-- ============================================================================
-- 04_branch_analysis.sql
-- Purpose : Which branch is growing into a problem?
--           Branch portfolio, PAR30/PAR90, like-for-like growth and
--           efficiency (cost per active loan, operating cost ratio,
--           loans per officer) on one grain so risk and efficiency can be
--           read together.
-- Rules   : Risk from v_loan_status_clean month-end snapshots only.
--           Growth is like-for-like: a branch is only compared over periods
--           in which it existed for the full comparison window.
-- Source  : v_loan_status_clean (cleaned loan-status layer, one row per
--           snapshot_date_id x loan_id). Run 01_data_validation.sql first.
--           The raw fact_loan_status table is never queried directly here.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Branch snapshot — portfolio, active loans, PAR30, PAR90 (latest month-end)
-- ----------------------------------------------------------------------------
SELECT
    b.branch_id,
    b.branch_name,
    b.branch_size,
    b.opened_date,
    COUNT(DISTINCT s.loan_id) FILTER (WHERE s.is_written_off = 0)       AS active_loans,
    SUM(s.outstanding_principal)                                        AS portfolio,
    ROUND(100.0 * SUM(s.outstanding_principal) FILTER (WHERE s.days_past_due > 30)
          / SUM(s.outstanding_principal), 2)                            AS par30_pct,
    ROUND(100.0 * SUM(s.outstanding_principal) FILTER (WHERE s.days_past_due > 90)
          / SUM(s.outstanding_principal), 2)                            AS par90_pct
FROM v_loan_status_clean s
JOIN dim_branch b ON b.branch_id = s.branch_id
WHERE s.snapshot_date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean)
GROUP BY b.branch_id, b.branch_name, b.branch_size, b.opened_date
ORDER BY par30_pct DESC;


-- ----------------------------------------------------------------------------
-- 2. Disbursed YTD by branch vs prior-year YTD
-- ----------------------------------------------------------------------------
WITH latest AS (
    SELECT full_date
    FROM dim_date
    WHERE date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean)
)
SELECT
    b.branch_name,
    SUM(l.principal_amount) FILTER (
        WHERE d.full_date BETWEEN date_trunc('year', x.full_date)::date AND x.full_date
    )                                                                   AS disbursed_ytd,
    SUM(l.principal_amount) FILTER (
        WHERE d.full_date BETWEEN (date_trunc('year', x.full_date) - INTERVAL '1 year')::date
                              AND (x.full_date - INTERVAL '1 year')::date
    )                                                                   AS disbursed_prior_ytd
FROM fact_loan l
JOIN dim_date   d ON d.date_id   = l.disbursement_date_id
JOIN dim_branch b ON b.branch_id = l.branch_id
CROSS JOIN latest x
GROUP BY b.branch_name
ORDER BY disbursed_ytd DESC NULLS LAST;


-- ----------------------------------------------------------------------------
-- 3. Like-for-like portfolio growth (latest month-end vs 12 months earlier)
--    Eligible only if the branch was open for the WHOLE comparison window
--    (opened on or before the start snapshot). Branches that were open
--    for less than 12 months at the start snapshot are flagged as "young
--    base" because growth off a near-zero base is not comparable.
-- ----------------------------------------------------------------------------
WITH latest AS (
    SELECT date_id, full_date
    FROM dim_date
    WHERE date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean)
),
start_snap AS (
    SELECT d.date_id, d.full_date
    FROM dim_date d
    CROSS JOIN latest x
    WHERE d.full_date = (x.full_date - INTERVAL '1 year')::date
      AND d.is_month_end = 1
),
branch_portfolio AS (
    SELECT
        s.branch_id,
        SUM(s.outstanding_principal) FILTER (WHERE s.snapshot_date_id = (SELECT date_id FROM start_snap)) AS portfolio_start,
        SUM(s.outstanding_principal) FILTER (WHERE s.snapshot_date_id = (SELECT date_id FROM latest))     AS portfolio_end,
        SUM(s.outstanding_principal) FILTER (WHERE s.snapshot_date_id = (SELECT date_id FROM start_snap)
                                               AND s.days_past_due > 30)                                  AS par30_start,
        SUM(s.outstanding_principal) FILTER (WHERE s.snapshot_date_id = (SELECT date_id FROM latest)
                                               AND s.days_past_due > 30)                                  AS par30_end
    FROM v_loan_status_clean s
    GROUP BY s.branch_id
)
SELECT
    b.branch_name,
    b.opened_date,
    CASE
        WHEN b.opened_date > (SELECT full_date FROM start_snap)                         THEN 'Not comparable (opened inside window)'
        WHEN b.opened_date > (SELECT full_date FROM start_snap) - INTERVAL '12 months'  THEN 'Young base (<12m old at start)'
        ELSE 'Like-for-like'
    END                                                                  AS comparison_basis,
    p.portfolio_start,
    p.portfolio_end,
    ROUND(100.0 * (p.portfolio_end - p.portfolio_start) / NULLIF(p.portfolio_start, 0), 1)
                                                                         AS portfolio_growth_pct,
    ROUND(100.0 * p.par30_start / NULLIF(p.portfolio_start, 0), 2)       AS par30_pct_start,
    ROUND(100.0 * p.par30_end   / NULLIF(p.portfolio_end,   0), 2)       AS par30_pct_end
FROM branch_portfolio p
JOIN dim_branch b ON b.branch_id = p.branch_id
ORDER BY comparison_basis, portfolio_growth_pct DESC;


-- ----------------------------------------------------------------------------
-- 4. Branch PAR30 trend (month-end) — for small multiples / branch slicer
--    Months before the branch's opening date are excluded.
-- ----------------------------------------------------------------------------
SELECT
    b.branch_name,
    d.full_date                                                      AS month_end,
    SUM(s.outstanding_principal)                                     AS portfolio,
    ROUND(100.0 * SUM(s.outstanding_principal) FILTER (WHERE s.days_past_due > 30)
          / SUM(s.outstanding_principal), 2)                         AS par30_pct
FROM v_loan_status_clean s
JOIN dim_date   d ON d.date_id   = s.snapshot_date_id
JOIN dim_branch b ON b.branch_id = s.branch_id
WHERE d.is_month_end = 1
  AND d.full_date >= b.opened_date
GROUP BY b.branch_name, d.full_date
ORDER BY b.branch_name, d.full_date;


-- ----------------------------------------------------------------------------
-- 5. Branch efficiency (trailing 12 months) next to branch risk
--    Cost per Active Loan  = 12m branch total cost / average month-end active loans
--    Operating Cost Ratio  = 12m branch total cost / average month-end portfolio
--    Loans per Officer     = active loans at latest snapshot / officers employed
--                            at the latest snapshot date
--    Efficiency and risk are returned on ONE row per branch on purpose:
--    a branch can look cheapest per loan precisely because it is under-
--    investing in credit assessment.
-- ----------------------------------------------------------------------------
WITH latest AS (
    SELECT date_id, full_date
    FROM dim_date
    WHERE date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean)
),
window_months AS (
    SELECT d.date_id
    FROM dim_date d
    CROSS JOIN latest x
    WHERE d.is_month_end = 1
      AND d.full_date >  (x.full_date - INTERVAL '12 months')::date
      AND d.full_date <=  x.full_date
),
cost_12m AS (
    SELECT c.branch_id, SUM(c.total_cost) AS total_cost_12m, AVG(c.headcount) AS avg_headcount
    FROM fact_branch_cost c
    WHERE c.month_end_date_id IN (SELECT date_id FROM window_months)
    GROUP BY c.branch_id
),
book_12m AS (
    SELECT
        branch_id,
        AVG(active_loans) AS avg_active_loans,
        AVG(portfolio)    AS avg_portfolio
    FROM (
        SELECT
            s.branch_id,
            s.snapshot_date_id,
            COUNT(DISTINCT s.loan_id) FILTER (WHERE s.is_written_off = 0) AS active_loans,
            SUM(s.outstanding_principal)                                  AS portfolio
        FROM v_loan_status_clean s
        WHERE s.snapshot_date_id IN (SELECT date_id FROM window_months)
        GROUP BY s.branch_id, s.snapshot_date_id
    ) m
    GROUP BY branch_id
),
latest_risk AS (
    SELECT
        s.branch_id,
        COUNT(DISTINCT s.loan_id) FILTER (WHERE s.is_written_off = 0)  AS active_loans,
        ROUND(100.0 * SUM(s.outstanding_principal) FILTER (WHERE s.days_past_due > 30)
              / SUM(s.outstanding_principal), 2)                       AS par30_pct
    FROM v_loan_status_clean s
    WHERE s.snapshot_date_id = (SELECT date_id FROM latest)
    GROUP BY s.branch_id
),
officers AS (
    SELECT o.branch_id, COUNT(*) AS active_officers
    FROM dim_officer o
    CROSS JOIN latest x
    WHERE o.hire_date <= x.full_date
      AND (o.termination_date IS NULL OR o.termination_date > x.full_date)
    GROUP BY o.branch_id
)
SELECT
    b.branch_name,
    b.branch_size,
    r.par30_pct,
    ROUND(c.total_cost_12m / NULLIF(k.avg_active_loans, 0), 0)          AS cost_per_active_loan,
    ROUND(100.0 * c.total_cost_12m / NULLIF(k.avg_portfolio, 0), 2)     AS operating_cost_ratio_pct,
    o.active_officers,
    ROUND(r.active_loans::numeric / NULLIF(o.active_officers, 0), 1)    AS loans_per_officer,
    ROUND(c.avg_headcount, 1)                                           AS avg_headcount
FROM dim_branch b
LEFT JOIN cost_12m    c ON c.branch_id = b.branch_id
LEFT JOIN book_12m    k ON k.branch_id = b.branch_id
LEFT JOIN latest_risk r ON r.branch_id = b.branch_id
LEFT JOIN officers    o ON o.branch_id = b.branch_id
ORDER BY cost_per_active_loan;


-- ----------------------------------------------------------------------------
-- 6. Branch map source — coordinates, portfolio and PAR30
-- ----------------------------------------------------------------------------
SELECT
    b.branch_name,
    b.city,
    b.region,
    b.latitude,
    b.longitude,
    SUM(s.outstanding_principal)                                     AS portfolio,
    ROUND(100.0 * SUM(s.outstanding_principal) FILTER (WHERE s.days_past_due > 30)
          / SUM(s.outstanding_principal), 2)                         AS par30_pct
FROM v_loan_status_clean s
JOIN dim_branch b ON b.branch_id = s.branch_id
WHERE s.snapshot_date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean)
GROUP BY b.branch_name, b.city, b.region, b.latitude, b.longitude
ORDER BY portfolio DESC;
