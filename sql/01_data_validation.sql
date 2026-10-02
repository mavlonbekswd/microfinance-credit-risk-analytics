-- ============================================================================
-- 01_data_validation.sql
-- Purpose : Confirm the dataset is complete and internally consistent before
--           any KPI is calculated or published, and build the cleaned
--           analytical layer that every later script reads from.
-- Engine  : PostgreSQL
-- Source  : Ishonch Mikromoliya synthetic dataset (2023-01-01 .. 2026-06-30)
--
-- RUN THIS FILE FIRST. Scripts 02-08 read v_loan_status_clean (section 11).
--
-- ----------------------------------------------------------------------------
-- DATA-QUALITY DISCOVERY — duplicated latest loan-status snapshot
-- ----------------------------------------------------------------------------
--   fact_loan_status should hold ONE row per (snapshot_date_id, loan_id).
--   41 of 42 month-end snapshots meet that grain. The latest snapshot does not:
--
--     snapshot_date_id 1277 (2026-06-30): 7,830 rows for 3,915 distinct loans
--
--   Every loan in that snapshot appears twice. The copies carry identical
--   outstanding_principal, but 226 pairs conflict on days_past_due, and
--   4 of those also conflict on par_bucket and provision_amount.
--
--   Impact: a plain SUM over the raw table doubles every balance at
--   2026-06-30 (portfolio, PAR30 balance, provisions) and creates an
--   artificial step in every trend that ends in that month.
--
--   Treatment: the raw table is NOT modified. A cleaned view,
--   v_loan_status_clean, enforces the intended grain with
--     ROW_NUMBER() OVER (PARTITION BY snapshot_date_id, loan_id
--                        ORDER BY status_id DESC) = 1
--   i.e. the most recently written row wins (deterministic tie-break).
--   Audit: section 10. Cleaned layer and reconciliation: section 11.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Row counts per table
--    Expected: 12 tables, ~315,000 rows in total.
-- ----------------------------------------------------------------------------
SELECT 'dim_date'               AS table_name, COUNT(*) AS row_count FROM dim_date
UNION ALL SELECT 'dim_branch',             COUNT(*) FROM dim_branch
UNION ALL SELECT 'dim_officer',            COUNT(*) FROM dim_officer
UNION ALL SELECT 'dim_product',            COUNT(*) FROM dim_product
UNION ALL SELECT 'dim_client',             COUNT(*) FROM dim_client
UNION ALL SELECT 'fact_application',       COUNT(*) FROM fact_application
UNION ALL SELECT 'fact_loan',              COUNT(*) FROM fact_loan
UNION ALL SELECT 'fact_schedule',          COUNT(*) FROM fact_schedule
UNION ALL SELECT 'fact_payment',           COUNT(*) FROM fact_payment
UNION ALL SELECT 'fact_loan_status',       COUNT(*) FROM fact_loan_status
UNION ALL SELECT 'fact_transaction_daily', COUNT(*) FROM fact_transaction_daily
UNION ALL SELECT 'fact_branch_cost',       COUNT(*) FROM fact_branch_cost
ORDER BY table_name;


-- ----------------------------------------------------------------------------
-- 2. Duplicate primary keys
--    Expected: zero rows returned.
-- ----------------------------------------------------------------------------
SELECT 'fact_loan' AS table_name, loan_id AS key_value, COUNT(*) AS duplicates
FROM fact_loan GROUP BY loan_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'fact_application', application_id, COUNT(*)
FROM fact_application GROUP BY application_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'fact_loan_status', status_id, COUNT(*)
FROM fact_loan_status GROUP BY status_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'dim_client', client_id, COUNT(*)
FROM dim_client GROUP BY client_id HAVING COUNT(*) > 1;

-- Business-key duplicate: one status row per loan per snapshot.
-- Expected: zero rows returned.
-- RESULT ON RAW DATA: FAILS for snapshot_date_id 1277 (3,915 duplicated loans,
-- 7,830 rows). Audited in section 10, resolved by the cleaned view in section 11.
SELECT
    snapshot_date_id,
    COUNT(*)                AS duplicated_loans,
    SUM(rows_per_loan)      AS status_rows
FROM (
    SELECT snapshot_date_id, loan_id, COUNT(*) AS rows_per_loan
    FROM fact_loan_status
    GROUP BY snapshot_date_id, loan_id
    HAVING COUNT(*) > 1
) d
GROUP BY snapshot_date_id
ORDER BY snapshot_date_id;


-- ----------------------------------------------------------------------------
-- 3. Null checks on columns that drive KPIs
--    Expected: zero for every column.
-- ----------------------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE outstanding_principal IS NULL) AS null_outstanding,
    COUNT(*) FILTER (WHERE days_past_due        IS NULL) AS null_dpd,
    COUNT(*) FILTER (WHERE par_bucket           IS NULL) AS null_par_bucket,
    COUNT(*) FILTER (WHERE provision_amount     IS NULL) AS null_provision,
    COUNT(*) FILTER (WHERE branch_id            IS NULL) AS null_branch,
    COUNT(*) FILTER (WHERE officer_id           IS NULL) AS null_officer,
    COUNT(*) FILTER (WHERE product_id           IS NULL) AS null_product
FROM fact_loan_status;

SELECT
    COUNT(*) FILTER (WHERE principal_amount     IS NULL) AS null_principal,
    COUNT(*) FILTER (WHERE annual_rate          IS NULL) AS null_rate,
    COUNT(*) FILTER (WHERE disbursement_date_id IS NULL) AS null_disbursement_date,
    COUNT(*) FILTER (WHERE application_id       IS NULL) AS null_application
FROM fact_loan;

-- decline_reason should be populated for declined applications only.
SELECT
    is_approved,
    COUNT(*)                                     AS applications,
    COUNT(*) FILTER (WHERE decline_reason IS NULL OR decline_reason = '') AS reason_missing
FROM fact_application
GROUP BY is_approved
ORDER BY is_approved;


-- ----------------------------------------------------------------------------
-- 4. Date ranges
--    Expected: calendar 2023-01-01 .. 2026-06-30, 42 month-ends.
-- ----------------------------------------------------------------------------
SELECT
    MIN(full_date)                            AS first_date,
    MAX(full_date)                            AS last_date,
    COUNT(*)                                  AS calendar_days,
    COUNT(*) FILTER (WHERE is_month_end = 1)  AS month_ends
FROM dim_date;

SELECT 'application' AS event, MIN(d.full_date) AS first_date, MAX(d.full_date) AS last_date
FROM fact_application a JOIN dim_date d ON d.date_id = a.application_date_id
UNION ALL
SELECT 'disbursement', MIN(d.full_date), MAX(d.full_date)
FROM fact_loan l JOIN dim_date d ON d.date_id = l.disbursement_date_id
UNION ALL
SELECT 'payment', MIN(d.full_date), MAX(d.full_date)
FROM fact_payment p JOIN dim_date d ON d.date_id = p.payment_date_id
UNION ALL
SELECT 'loan_status_snapshot', MIN(d.full_date), MAX(d.full_date)
FROM fact_loan_status s JOIN dim_date d ON d.date_id = s.snapshot_date_id;


-- ----------------------------------------------------------------------------
-- 5. Latest loan-status snapshot
--    Validated: snapshot_date_id = 1277, full_date = 2026-06-30, is_month_end = 1
-- ----------------------------------------------------------------------------
SELECT
    MAX(snapshot_date_id) AS latest_snapshot
FROM fact_loan_status;

SELECT d.date_id, d.full_date, d.is_month_end
FROM dim_date d
WHERE d.date_id = (SELECT MAX(snapshot_date_id) FROM fact_loan_status);


-- ----------------------------------------------------------------------------
-- 6. Month-end status validation
--    Every snapshot must land on a month-end; otherwise trends double-count.
--    Expected: 42 distinct snapshots, 0 non-month-end rows.
-- ----------------------------------------------------------------------------
SELECT
    COUNT(DISTINCT s.snapshot_date_id)               AS distinct_snapshots,
    COUNT(*) FILTER (WHERE d.is_month_end <> 1)      AS rows_not_on_month_end,
    COUNT(*) FILTER (WHERE d.date_id IS NULL)        AS rows_without_date
FROM fact_loan_status s
LEFT JOIN dim_date d ON d.date_id = s.snapshot_date_id;


-- ----------------------------------------------------------------------------
-- 7. PAR bucket boundaries vs days_past_due
--    Confirms that "days_past_due > 30" is equivalent to the 31+ buckets.
-- ----------------------------------------------------------------------------
SELECT
    par_bucket,
    MIN(days_past_due) AS min_dpd,
    MAX(days_past_due) AS max_dpd,
    COUNT(*)           AS status_rows
FROM fact_loan_status
GROUP BY par_bucket
ORDER BY MIN(days_past_due);


-- ----------------------------------------------------------------------------
-- 8. Referential integrity
--    Expected: zero orphans in every row.
-- ----------------------------------------------------------------------------
SELECT 'loan -> application' AS relationship, COUNT(*) AS orphans
FROM fact_loan l LEFT JOIN fact_application a ON a.application_id = l.application_id
WHERE a.application_id IS NULL
UNION ALL
SELECT 'loan -> declined application', COUNT(*)
FROM fact_loan l JOIN fact_application a ON a.application_id = l.application_id
WHERE a.is_approved <> 1
UNION ALL
SELECT 'status -> loan', COUNT(*)
FROM fact_loan_status s LEFT JOIN fact_loan l ON l.loan_id = s.loan_id
WHERE l.loan_id IS NULL
UNION ALL
SELECT 'payment -> loan', COUNT(*)
FROM fact_payment p LEFT JOIN fact_loan l ON l.loan_id = p.loan_id
WHERE l.loan_id IS NULL
UNION ALL
SELECT 'schedule -> loan', COUNT(*)
FROM fact_schedule sc LEFT JOIN fact_loan l ON l.loan_id = sc.loan_id
WHERE l.loan_id IS NULL
UNION ALL
SELECT 'officer -> branch', COUNT(*)
FROM dim_officer o LEFT JOIN dim_branch b ON b.branch_id = o.branch_id
WHERE b.branch_id IS NULL;

-- Every loan has exactly one application; not every application has a loan.
SELECT
    COUNT(*)                                        AS applications,
    COUNT(*) FILTER (WHERE is_approved = 1)         AS approved_applications,
    (SELECT COUNT(*) FROM fact_loan)                AS disbursed_loans
FROM fact_application;


-- ----------------------------------------------------------------------------
-- 9. Known data-treatment decisions (documented in docs/methodology.md)
-- ----------------------------------------------------------------------------

-- 9a. Loans disbursed but with no payment recorded yet.
--     The dataset guide states 252 such loans. They stay in the portfolio;
--     their risk status comes from fact_loan_status, not from payments.
SELECT COUNT(*) AS loans_without_any_payment
FROM fact_loan l
WHERE NOT EXISTS (SELECT 1 FROM fact_payment p WHERE p.loan_id = l.loan_id);

-- 9b. Branch opening dates relative to the analysis window
--     (must be handled in any growth comparison).
SELECT
    branch_id,
    branch_name,
    opened_date,
    branch_size,
    opened_date > DATE '2023-01-01'                         AS opened_inside_window,
    opened_date > DATE '2023-01-01' - INTERVAL '12 months'  AS young_at_window_start
FROM dim_branch
ORDER BY opened_date;


-- ============================================================================
-- 10. DATA-QUALITY AUDIT — duplicated loans in snapshot 1277 (2026-06-30)
--     Source data-quality issue. The raw table is left untouched; every
--     query in this section reads fact_loan_status as loaded.
-- ============================================================================

-- 10a. Grain check for every month-end snapshot
--      Expected: status_rows = distinct_loans everywhere.
--      Result  : true for 41 snapshots; 2026-06-30 has 7,830 rows for
--                3,915 distinct loans.
SELECT
    d.full_date                                  AS snapshot_date,
    s.snapshot_date_id,
    COUNT(*)                                     AS status_rows,
    COUNT(DISTINCT s.loan_id)                    AS distinct_loans,
    COUNT(*) - COUNT(DISTINCT s.loan_id)         AS excess_rows,
    SUM(s.outstanding_principal)                 AS raw_sum_outstanding
FROM fact_loan_status s
JOIN dim_date d ON d.date_id = s.snapshot_date_id
GROUP BY d.full_date, s.snapshot_date_id
ORDER BY d.full_date;

-- 10b. Summary: snapshots that break the grain
--      Result: 1 of 42 snapshots (snapshot_date_id 1277).
SELECT
    COUNT(*)                                         AS snapshots,
    COUNT(*) FILTER (WHERE status_rows > loans)      AS snapshots_breaking_grain
FROM (
    SELECT snapshot_date_id, COUNT(*) AS status_rows, COUNT(DISTINCT loan_id) AS loans
    FROM fact_loan_status
    GROUP BY snapshot_date_id
) g;

-- 10c. Do the duplicated copies agree? Column-by-column conflict count.
--      Result: 3,915 duplicated loans; outstanding_principal identical in all
--      pairs; 226 conflict on days_past_due; 4 conflict on par_bucket and
--      provision_amount; 0 conflict on is_written_off.
WITH pairs AS (
    SELECT loan_id, MIN(status_id) AS first_id, MAX(status_id) AS last_id
    FROM fact_loan_status
    WHERE snapshot_date_id = 1277
    GROUP BY loan_id
    HAVING COUNT(*) > 1
)
SELECT
    COUNT(*)                                                                   AS duplicated_loans,
    COUNT(*) FILTER (WHERE a.outstanding_principal <> b.outstanding_principal) AS conflict_outstanding,
    COUNT(*) FILTER (WHERE a.days_past_due         <> b.days_past_due)         AS conflict_dpd,
    COUNT(*) FILTER (WHERE a.par_bucket            <> b.par_bucket)            AS conflict_par_bucket,
    COUNT(*) FILTER (WHERE a.provision_amount      <> b.provision_amount)      AS conflict_provision,
    COUNT(*) FILTER (WHERE a.is_written_off        <> b.is_written_off)        AS conflict_write_off,
    COUNT(*) FILTER (WHERE a.branch_id <> b.branch_id
                        OR a.officer_id <> b.officer_id
                        OR a.product_id <> b.product_id)                       AS conflict_dimension_keys
FROM pairs p
JOIN fact_loan_status a ON a.status_id = p.first_id
JOIN fact_loan_status b ON b.status_id = p.last_id;

-- 10d. The pairs that conflict on par_bucket (they move between buckets)
WITH pairs AS (
    SELECT loan_id, MIN(status_id) AS first_id, MAX(status_id) AS last_id
    FROM fact_loan_status
    WHERE snapshot_date_id = 1277
    GROUP BY loan_id
    HAVING COUNT(*) > 1
)
SELECT
    p.loan_id,
    a.status_id  AS first_status_id, a.days_past_due AS first_dpd, a.par_bucket AS first_bucket, a.provision_amount AS first_provision,
    b.status_id  AS kept_status_id,  b.days_past_due AS kept_dpd,  b.par_bucket AS kept_bucket,  b.provision_amount AS kept_provision
FROM pairs p
JOIN fact_loan_status a ON a.status_id = p.first_id
JOIN fact_loan_status b ON b.status_id = p.last_id
WHERE a.par_bucket <> b.par_bucket
ORDER BY p.loan_id;


-- ============================================================================
-- 11. CLEANED ANALYTICAL LAYER — v_loan_status_clean
--     Grain   : one row per (snapshot_date_id, loan_id)
--     Rule    : ROW_NUMBER() OVER (PARTITION BY snapshot_date_id, loan_id
--                                  ORDER BY status_id DESC) = 1
--               (deterministic tie-break: the most recently written row wins)
--     Raw     : fact_loan_status is never updated or deleted.
--     Used by : every analysis in 02-08 and the Power BI model.
-- ============================================================================
CREATE OR REPLACE VIEW v_loan_status_clean AS
SELECT
    status_id,
    snapshot_date_id,
    loan_id,
    branch_id,
    officer_id,
    product_id,
    outstanding_principal,
    days_past_due,
    par_bucket,
    provision_amount,
    is_written_off
FROM (
    SELECT
        s.*,
        ROW_NUMBER() OVER (
            PARTITION BY s.snapshot_date_id, s.loan_id
            ORDER BY s.status_id DESC
        ) AS rn
    FROM fact_loan_status s
) ranked
WHERE rn = 1;

-- 11a. Grain check on the cleaned layer. Expected: zero rows.
SELECT snapshot_date_id, loan_id, COUNT(*) AS rows_per_loan
FROM v_loan_status_clean
GROUP BY snapshot_date_id, loan_id
HAVING COUNT(*) > 1;

-- 11b. Reconciliation raw vs clean, per snapshot.
--      Expected: identical for the 41 clean snapshots; only 2026-06-30 changes.
SELECT
    d.full_date                                              AS snapshot_date,
    r.raw_rows,
    c.clean_rows,
    r.raw_outstanding,
    c.clean_outstanding,
    r.raw_outstanding - c.clean_outstanding                  AS removed_outstanding
FROM (
    SELECT snapshot_date_id, COUNT(*) AS raw_rows, SUM(outstanding_principal) AS raw_outstanding
    FROM fact_loan_status GROUP BY snapshot_date_id
) r
JOIN (
    SELECT snapshot_date_id, COUNT(*) AS clean_rows, SUM(outstanding_principal) AS clean_outstanding
    FROM v_loan_status_clean GROUP BY snapshot_date_id
) c ON c.snapshot_date_id = r.snapshot_date_id
JOIN dim_date d ON d.date_id = r.snapshot_date_id
WHERE r.raw_rows <> c.clean_rows
   OR r.snapshot_date_id = (SELECT MAX(snapshot_date_id) FROM fact_loan_status)
ORDER BY d.full_date;

-- 11c. Headline KPIs at the latest snapshot: raw (superseded) vs clean (official)
SELECT
    'raw fact_loan_status (superseded)'                                AS source,
    COUNT(*)                                                           AS status_rows,
    SUM(outstanding_principal)                                         AS portfolio,
    SUM(outstanding_principal) FILTER (WHERE days_past_due > 30)       AS par30_amount,
    ROUND(100.0 * SUM(outstanding_principal) FILTER (WHERE days_past_due > 30)
          / SUM(outstanding_principal), 2)                             AS par30_pct
FROM fact_loan_status
WHERE snapshot_date_id = 1277
UNION ALL
SELECT
    'v_loan_status_clean (official)',
    COUNT(*),
    SUM(outstanding_principal),
    SUM(outstanding_principal) FILTER (WHERE days_past_due > 30),
    ROUND(100.0 * SUM(outstanding_principal) FILTER (WHERE days_past_due > 30)
          / SUM(outstanding_principal), 2)
FROM v_loan_status_clean
WHERE snapshot_date_id = 1277;

-- 11d. Written-off loans still present in the latest snapshot (clean layer).
--      The headline portfolio is the plain sum of outstanding_principal and
--      therefore INCLUDES these rows; Active Loans excludes them.
SELECT
    is_written_off,
    COUNT(*)                   AS loans,
    SUM(outstanding_principal) AS outstanding_principal,
    SUM(provision_amount)      AS provision_amount
FROM v_loan_status_clean
WHERE snapshot_date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean)
GROUP BY is_written_off
ORDER BY is_written_off;
