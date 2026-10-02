-- ============================================================================
-- 08_vintage_analysis.sql
-- Purpose : Do loans disbursed later perform better or worse than earlier
--           loans AT THE SAME AGE?
-- Definition
--   Vintage / cohort  = quarter in which the loan was disbursed.
--   Months-on-book    = whole months between disbursement month and the
--                       month-end snapshot month (MOB 0 = disbursement month).
--   PAR30 @ MOB n     = outstanding principal with days_past_due > 30
--                       / outstanding principal, for loans of that cohort,
--                       measured at the snapshot where each loan is n months
--                       on book.
-- Note    : A calendar-month PAR trend is NOT vintage analysis. Here every
--           cohort is compared at equal age. Cohorts that have not yet
--           reached MOB n return NULL (they are too young to judge).
-- Denominator choice
--   Primary   : outstanding at MOB n (portfolio-at-risk definition, consistent
--               with PAR30 elsewhere).
--   Secondary : original disbursed principal of the cohort (shows the share of
--               money lent that is >30 days late at MOB n; insensitive to
--               amortisation).
-- Source  : v_loan_status_clean (cleaned loan-status layer, one row per
--           snapshot_date_id x loan_id). Run 01_data_validation.sql first.
--           The raw fact_loan_status table is never queried directly here.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Loan-level months-on-book panel (base for all vintage views)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_vintage_panel;

CREATE TEMP TABLE tmp_vintage_panel AS
SELECT
    l.loan_id,
    l.product_id,
    l.branch_id,
    l.principal_amount,
    dd.full_date                                                          AS disbursement_date,
    to_char(dd.full_date, 'YYYY') || '-Q' || EXTRACT(QUARTER FROM dd.full_date)
                                                                          AS vintage_quarter,
    ds.full_date                                                          AS snapshot_date,
    (EXTRACT(YEAR FROM ds.full_date) - EXTRACT(YEAR FROM dd.full_date)) * 12
      + (EXTRACT(MONTH FROM ds.full_date) - EXTRACT(MONTH FROM dd.full_date))
                                                                          AS months_on_book,
    s.outstanding_principal,
    s.days_past_due
FROM v_loan_status_clean s
JOIN fact_loan l  ON l.loan_id  = s.loan_id
JOIN dim_date  ds ON ds.date_id = s.snapshot_date_id
JOIN dim_date  dd ON dd.date_id = l.disbursement_date_id
WHERE ds.is_month_end = 1;


-- ----------------------------------------------------------------------------
-- 2. Cohort sizes and maximum observable age
-- ----------------------------------------------------------------------------
WITH last_obs AS (
    SELECT MAX(full_date) AS last_snapshot
    FROM dim_date
    WHERE date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean)
)
SELECT
    to_char(d.full_date, 'YYYY') || '-Q' || EXTRACT(QUARTER FROM d.full_date) AS vintage_quarter,
    COUNT(*)                                                                  AS loans,
    SUM(l.principal_amount)                                                   AS disbursed,
    MIN((EXTRACT(YEAR FROM x.last_snapshot) - EXTRACT(YEAR FROM d.full_date)) * 12
        + (EXTRACT(MONTH FROM x.last_snapshot) - EXTRACT(MONTH FROM d.full_date)))
                                                                              AS max_mob_fully_observed
FROM fact_loan l
JOIN dim_date d ON d.date_id = l.disbursement_date_id
CROSS JOIN last_obs x
GROUP BY 1
ORDER BY 1;


-- ----------------------------------------------------------------------------
-- 3. Vintage matrix — PAR30 at 6, 12 and 18 months-on-book by quarterly cohort
-- ----------------------------------------------------------------------------
WITH cohort_disbursed AS (
    SELECT vintage_quarter, SUM(principal_amount) AS disbursed
    FROM (SELECT DISTINCT loan_id, vintage_quarter, principal_amount FROM tmp_vintage_panel) x
    GROUP BY vintage_quarter
),
at_mob AS (
    SELECT
        vintage_quarter,
        months_on_book,
        SUM(outstanding_principal)                                    AS outstanding,
        SUM(outstanding_principal) FILTER (WHERE days_past_due > 30)  AS par30_amount
    FROM tmp_vintage_panel
    WHERE months_on_book IN (6, 12, 18)
    GROUP BY vintage_quarter, months_on_book
)
SELECT
    c.vintage_quarter,
    -- primary: % of outstanding at that age
    ROUND(100.0 * MAX(m.par30_amount) FILTER (WHERE m.months_on_book = 6)
          / NULLIF(MAX(m.outstanding) FILTER (WHERE m.months_on_book = 6), 0), 2)   AS par30_pct_mob6,
    ROUND(100.0 * MAX(m.par30_amount) FILTER (WHERE m.months_on_book = 12)
          / NULLIF(MAX(m.outstanding) FILTER (WHERE m.months_on_book = 12), 0), 2)  AS par30_pct_mob12,
    ROUND(100.0 * MAX(m.par30_amount) FILTER (WHERE m.months_on_book = 18)
          / NULLIF(MAX(m.outstanding) FILTER (WHERE m.months_on_book = 18), 0), 2)  AS par30_pct_mob18,
    -- secondary: % of original disbursed principal
    ROUND(100.0 * COALESCE(MAX(m.par30_amount) FILTER (WHERE m.months_on_book = 6), 0)
          / c.disbursed, 2)                                                        AS par30_of_disbursed_mob6,
    ROUND(100.0 * COALESCE(MAX(m.par30_amount) FILTER (WHERE m.months_on_book = 12), 0)
          / c.disbursed, 2)                                                        AS par30_of_disbursed_mob12,
    ROUND(100.0 * COALESCE(MAX(m.par30_amount) FILTER (WHERE m.months_on_book = 18), 0)
          / c.disbursed, 2)                                                        AS par30_of_disbursed_mob18
FROM cohort_disbursed c
LEFT JOIN at_mob m ON m.vintage_quarter = c.vintage_quarter
GROUP BY c.vintage_quarter, c.disbursed
ORDER BY c.vintage_quarter;
-- Interpretation guard: secondary columns show 0.00 (not NULL) when a cohort
-- has not reached that MOB — read them together with max_mob_fully_observed
-- from query 2.


-- ----------------------------------------------------------------------------
-- 4. Full vintage curve — PAR30 % by cohort for every months-on-book value
--    (source for a line chart: X = MOB, one line per cohort)
-- ----------------------------------------------------------------------------
SELECT
    vintage_quarter,
    months_on_book,
    COUNT(*)                                                          AS loans_on_book,
    ROUND(100.0 * SUM(outstanding_principal) FILTER (WHERE days_past_due > 30)
          / NULLIF(SUM(outstanding_principal), 0), 2)                 AS par30_pct
FROM tmp_vintage_panel
WHERE months_on_book BETWEEN 0 AND 36
GROUP BY vintage_quarter, months_on_book
ORDER BY vintage_quarter, months_on_book;


-- ----------------------------------------------------------------------------
-- 5. Vintage by product — PAR30 at 12 MOB, yearly cohorts
-- ----------------------------------------------------------------------------
SELECT
    p.product_name,
    EXTRACT(YEAR FROM v.disbursement_date)                            AS vintage_year,
    COUNT(*)                                                          AS loans_at_mob12,
    ROUND(100.0 * SUM(v.outstanding_principal) FILTER (WHERE v.days_past_due > 30)
          / NULLIF(SUM(v.outstanding_principal), 0), 2)               AS par30_pct_mob12
FROM tmp_vintage_panel v
JOIN dim_product p ON p.product_id = v.product_id
WHERE v.months_on_book = 12
GROUP BY p.product_name, EXTRACT(YEAR FROM v.disbursement_date)
ORDER BY p.product_name, vintage_year;
