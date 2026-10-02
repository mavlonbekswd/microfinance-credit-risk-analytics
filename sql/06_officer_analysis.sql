-- ============================================================================
-- 06_officer_analysis.sql
-- Purpose : Is anyone approving loans they should not be approving?
-- Rules   : Approval rate is never read on its own. It is interpreted
--           together with PAR30, approved-client credit score, portfolio
--           size and sample size.
--           Officers with fewer than 40 applications are flagged
--           (min_sample_flag) and excluded from the ranking query.
-- Source  : v_loan_status_clean (cleaned loan-status layer, one row per
--           snapshot_date_id x loan_id). Run 01_data_validation.sql first.
--           The raw fact_loan_status table is never queried directly here.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Officer scorecard
--    applications handled, approval rate, loans disbursed, portfolio and PAR30
--    at the latest snapshot, average credit score of approved clients,
--    average granted rate.
-- ----------------------------------------------------------------------------
WITH apps AS (
    SELECT
        officer_id,
        COUNT(*)                                             AS applications,
        COUNT(*) FILTER (WHERE is_approved = 1)              AS approved,
        AVG(credit_score) FILTER (WHERE is_approved = 1)     AS avg_approved_score
    FROM fact_application
    GROUP BY officer_id
),
loans AS (
    SELECT officer_id, COUNT(*) AS loans_disbursed, AVG(annual_rate) AS avg_rate
    FROM fact_loan
    GROUP BY officer_id
),
book AS (
    SELECT
        officer_id,
        SUM(outstanding_principal)                                       AS portfolio,
        SUM(outstanding_principal) FILTER (WHERE days_past_due > 30)     AS par30_amount
    FROM v_loan_status_clean
    WHERE snapshot_date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean)
    GROUP BY officer_id
)
SELECT
    o.officer_id,
    o.full_name                                                          AS officer_name,
    b.branch_name,
    o.termination_date IS NOT NULL                                       AS has_left,
    a.applications,
    ROUND(100.0 * a.approved / a.applications, 1)                        AS approval_rate_pct,
    l.loans_disbursed,
    bk.portfolio,
    ROUND(100.0 * bk.par30_amount / NULLIF(bk.portfolio, 0), 2)          AS par30_pct,
    ROUND(a.avg_approved_score, 0)                                       AS avg_approved_credit_score,
    ROUND(l.avg_rate * 100, 2)                                           AS avg_granted_rate_pct,
    CASE WHEN a.applications < 40 THEN 'Below 40 applications' ELSE 'OK' END
                                                                         AS min_sample_flag
FROM dim_officer o
JOIN dim_branch b  ON b.branch_id  = o.branch_id
LEFT JOIN apps  a  ON a.officer_id = o.officer_id
LEFT JOIN loans l  ON l.officer_id = o.officer_id
LEFT JOIN book  bk ON bk.officer_id = o.officer_id
ORDER BY par30_pct DESC NULLS LAST;


-- ----------------------------------------------------------------------------
-- 2. Company-average reference lines for the approval-rate vs PAR30 scatter
-- ----------------------------------------------------------------------------
SELECT
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_approved = 1) / COUNT(*), 1) AS company_approval_rate_pct,
    (SELECT ROUND(100.0 * SUM(outstanding_principal) FILTER (WHERE days_past_due > 30)
                  / SUM(outstanding_principal), 2)
     FROM v_loan_status_clean
     WHERE snapshot_date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean))
                                                                         AS company_par30_pct,
    ROUND(AVG(credit_score) FILTER (WHERE is_approved = 1), 0)           AS company_avg_approved_score
FROM fact_application;


-- ----------------------------------------------------------------------------
-- 3. Officers above company average on approval rate AND PAR30, with
--    approved-client credit score below company average.
--    All three signals must point the same way. Officers below the
--    40-application threshold are excluded.
-- ----------------------------------------------------------------------------
WITH company AS (
    SELECT
        1.0 * COUNT(*) FILTER (WHERE is_approved = 1) / COUNT(*)  AS approval_rate,
        AVG(credit_score) FILTER (WHERE is_approved = 1)          AS avg_score
    FROM fact_application
),
company_par AS (
    SELECT SUM(outstanding_principal) FILTER (WHERE days_past_due > 30)
           / SUM(outstanding_principal) AS par30
    FROM v_loan_status_clean
    WHERE snapshot_date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean)
),
officer AS (
    SELECT
        a.officer_id,
        COUNT(*)                                                   AS applications,
        1.0 * COUNT(*) FILTER (WHERE a.is_approved = 1) / COUNT(*) AS approval_rate,
        AVG(a.credit_score) FILTER (WHERE a.is_approved = 1)       AS avg_score
    FROM fact_application a
    GROUP BY a.officer_id
    HAVING COUNT(*) >= 40
),
officer_par AS (
    SELECT officer_id,
           SUM(outstanding_principal) FILTER (WHERE days_past_due > 30)
           / SUM(outstanding_principal) AS par30,
           SUM(outstanding_principal)   AS portfolio
    FROM v_loan_status_clean
    WHERE snapshot_date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean)
    GROUP BY officer_id
)
SELECT
    d.full_name                              AS officer_name,
    b.branch_name,
    o.applications,
    ROUND(100 * o.approval_rate, 1)          AS approval_rate_pct,
    ROUND(100 * op.par30, 2)                 AS par30_pct,
    ROUND(o.avg_score, 0)                    AS avg_approved_credit_score,
    op.portfolio
FROM officer o
JOIN officer_par op ON op.officer_id = o.officer_id
JOIN dim_officer d  ON d.officer_id  = o.officer_id
JOIN dim_branch  b  ON b.branch_id   = d.branch_id
CROSS JOIN company c
CROSS JOIN company_par cp
WHERE o.approval_rate > c.approval_rate
  AND op.par30        > cp.par30
  AND o.avg_score     < c.avg_score
ORDER BY op.par30 DESC;


-- ----------------------------------------------------------------------------
-- 4. Decline reason mix by branch (share of each branch's declines)
-- ----------------------------------------------------------------------------
SELECT
    b.branch_name,
    a.decline_reason,
    COUNT(*)                                                         AS declines,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY b.branch_name), 1)
                                                                     AS share_of_branch_declines_pct
FROM fact_application a
JOIN dim_branch b ON b.branch_id = a.branch_id
WHERE a.is_approved = 0
GROUP BY b.branch_name, a.decline_reason
ORDER BY b.branch_name, declines DESC;


-- ----------------------------------------------------------------------------
-- 5. Approved credit-score distribution by officer (min / quartiles / max)
-- ----------------------------------------------------------------------------
SELECT
    o.full_name                                                        AS officer_name,
    COUNT(*)                                                           AS approved_applications,
    MIN(a.credit_score)                                                AS min_score,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY a.credit_score)       AS p25_score,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY a.credit_score)       AS median_score,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY a.credit_score)       AS p75_score,
    MAX(a.credit_score)                                                AS max_score
FROM fact_application a
JOIN dim_officer o ON o.officer_id = a.officer_id
WHERE a.is_approved = 1
GROUP BY o.full_name
ORDER BY median_score;


-- ----------------------------------------------------------------------------
-- 6. Officer portfolio growth over the latest 12 months
-- ----------------------------------------------------------------------------
WITH latest AS (
    SELECT date_id, full_date
    FROM dim_date
    WHERE date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean)
),
start_snap AS (
    SELECT d.date_id
    FROM dim_date d
    CROSS JOIN latest x
    WHERE d.full_date = (x.full_date - INTERVAL '1 year')::date
      AND d.is_month_end = 1
)
SELECT
    o.full_name                                                       AS officer_name,
    SUM(s.outstanding_principal) FILTER (WHERE s.snapshot_date_id = (SELECT date_id FROM start_snap)) AS portfolio_12m_ago,
    SUM(s.outstanding_principal) FILTER (WHERE s.snapshot_date_id = (SELECT date_id FROM latest))     AS portfolio_latest,
    ROUND(100.0 * (
        SUM(s.outstanding_principal) FILTER (WHERE s.snapshot_date_id = (SELECT date_id FROM latest))
      - SUM(s.outstanding_principal) FILTER (WHERE s.snapshot_date_id = (SELECT date_id FROM start_snap))
    ) / NULLIF(SUM(s.outstanding_principal) FILTER (WHERE s.snapshot_date_id = (SELECT date_id FROM start_snap)), 0), 1)
                                                                      AS growth_pct
FROM v_loan_status_clean s
JOIN dim_officer o ON o.officer_id = s.officer_id
WHERE s.snapshot_date_id IN ((SELECT date_id FROM latest), (SELECT date_id FROM start_snap))
GROUP BY o.full_name
ORDER BY growth_pct DESC NULLS LAST;


-- ----------------------------------------------------------------------------
-- 7. Officer capacity curve (optional advanced view)
--    Caseload band at each month-end vs PAR30 of that officer's book.
-- ----------------------------------------------------------------------------
WITH officer_month AS (
    SELECT
        s.snapshot_date_id,
        s.officer_id,
        COUNT(DISTINCT s.loan_id) FILTER (WHERE s.is_written_off = 0)  AS active_loans,
        SUM(s.outstanding_principal)                                   AS portfolio,
        SUM(s.outstanding_principal) FILTER (WHERE s.days_past_due > 30) AS par30_amount
    FROM v_loan_status_clean s
    JOIN dim_date d ON d.date_id = s.snapshot_date_id
    WHERE d.is_month_end = 1
    GROUP BY s.snapshot_date_id, s.officer_id
)
SELECT
    (active_loans / 25) * 25                                         AS caseload_band_from,
    (active_loans / 25) * 25 + 24                                    AS caseload_band_to,
    COUNT(*)                                                         AS officer_months,
    ROUND(100.0 * SUM(par30_amount) / SUM(portfolio), 2)             AS par30_pct
FROM officer_month
GROUP BY (active_loans / 25)
ORDER BY caseload_band_from;
