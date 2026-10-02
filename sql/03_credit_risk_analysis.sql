-- ============================================================================
-- 03_credit_risk_analysis.sql
-- Purpose : Portfolio quality — PAR30, PAR90, PAR bucket mix, provisions,
--           write-offs, cost of risk and month-to-month roll rates.
-- Rule    : v_loan_status_clean is the ONLY official source for delinquency.
--           PAR is never reconstructed from fact_schedule vs fact_payment.
--           Trends use month-end snapshots (dim_date.is_month_end = 1).
-- Source  : v_loan_status_clean (cleaned loan-status layer, one row per
--           snapshot_date_id x loan_id). Run 01_data_validation.sql first.
--           The raw fact_loan_status table is never queried directly here.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. PAR30 at the latest snapshot
--    Validated on the cleaned layer (snapshot_date_id = 1277, 2026-06-30):
--      PAR30 amount    = 10,641,742,000 UZS
--      Total portfolio = 130,134,379,500 UZS
--      PAR30           = 8.18%
--    (The raw table returns 21,249,317,300 / 260,268,759,000 / 8.16% because
--     every loan is duplicated in this snapshot — superseded, see 01 §10-11.)
-- ----------------------------------------------------------------------------
SELECT
    SUM(
        CASE
            WHEN days_past_due > 30
            THEN outstanding_principal
            ELSE 0
        END
    ) AS par30_amount,
    SUM(outstanding_principal) AS total_portfolio,
    ROUND(
        100.0 *
        SUM(
            CASE
                WHEN days_past_due > 30
                THEN outstanding_principal
                ELSE 0
            END
        )
        / SUM(outstanding_principal),
        2
    ) AS par30_pct
FROM v_loan_status_clean
WHERE snapshot_date_id = 1277;


-- ----------------------------------------------------------------------------
-- 2. PAR30 and PAR90 at the latest snapshot (parameter-free version)
-- ----------------------------------------------------------------------------
SELECT
    SUM(outstanding_principal)                                         AS portfolio,
    SUM(outstanding_principal) FILTER (WHERE days_past_due > 30)       AS par30_amount,
    SUM(outstanding_principal) FILTER (WHERE days_past_due > 90)       AS par90_amount,
    ROUND(100.0 * SUM(outstanding_principal) FILTER (WHERE days_past_due > 30)
          / SUM(outstanding_principal), 2)                             AS par30_pct,
    ROUND(100.0 * SUM(outstanding_principal) FILTER (WHERE days_past_due > 90)
          / SUM(outstanding_principal), 2)                             AS par90_pct
FROM v_loan_status_clean
WHERE snapshot_date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean);


-- ----------------------------------------------------------------------------
-- 3. PAR bucket distribution at the latest snapshot (% of outstanding)
--    Validated (cleaned layer):
--      Standart 91.82% | 1-30 0.00% (no loans) | 31-60 0.55% | 61-90 0.58% | 90+ 7.04%
--    Note: exact PAR30 = 8.18%; rounded bucket values sum to 8.17%.
-- ----------------------------------------------------------------------------
SELECT
    par_bucket,
    COUNT(DISTINCT loan_id)                                          AS loans,
    SUM(outstanding_principal)                                       AS outstanding,
    ROUND(100.0 * SUM(outstanding_principal)
          / SUM(SUM(outstanding_principal)) OVER (), 2)              AS pct_of_portfolio
FROM v_loan_status_clean
WHERE snapshot_date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean)
GROUP BY par_bucket
ORDER BY MIN(days_past_due);


-- ----------------------------------------------------------------------------
-- 4. Monthly risk trend — portfolio, PAR30 %, PAR90 %, provision coverage
--    One row per month-end (42 rows). This is the "growth vs risk" view.
-- ----------------------------------------------------------------------------
SELECT
    d.full_date                                                          AS month_end,
    SUM(s.outstanding_principal)                                         AS portfolio,
    ROUND(100.0 * SUM(s.outstanding_principal) FILTER (WHERE s.days_past_due > 30)
          / SUM(s.outstanding_principal), 2)                             AS par30_pct,
    ROUND(100.0 * SUM(s.outstanding_principal) FILTER (WHERE s.days_past_due > 90)
          / SUM(s.outstanding_principal), 2)                             AS par90_pct,
    SUM(s.provision_amount)                                              AS provisions_held,
    ROUND(100.0 * SUM(s.provision_amount)
          / NULLIF(SUM(s.outstanding_principal) FILTER (WHERE s.days_past_due > 30), 0), 1)
                                                                         AS provision_coverage_pct
FROM v_loan_status_clean s
JOIN dim_date d ON d.date_id = s.snapshot_date_id
WHERE d.is_month_end = 1
GROUP BY d.full_date
ORDER BY d.full_date;


-- ----------------------------------------------------------------------------
-- 5. PAR bucket composition over time (% of portfolio, stacked-area source)
-- ----------------------------------------------------------------------------
SELECT
    d.full_date                                                    AS month_end,
    s.par_bucket,
    SUM(s.outstanding_principal)                                   AS outstanding,
    ROUND(100.0 * SUM(s.outstanding_principal)
          / SUM(SUM(s.outstanding_principal)) OVER (PARTITION BY d.full_date), 2)
                                                                   AS pct_of_portfolio
FROM v_loan_status_clean s
JOIN dim_date d ON d.date_id = s.snapshot_date_id
WHERE d.is_month_end = 1
GROUP BY d.full_date, s.par_bucket
ORDER BY d.full_date, MIN(s.days_past_due);


-- ----------------------------------------------------------------------------
-- 6. PAR30 today vs one year earlier
-- ----------------------------------------------------------------------------
WITH latest AS (
    SELECT date_id, full_date
    FROM dim_date
    WHERE date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean)
),
compare AS (
    SELECT d.date_id, d.full_date
    FROM dim_date d
    CROSS JOIN latest
    WHERE d.full_date IN (latest.full_date, (latest.full_date - INTERVAL '1 year')::date)
      AND d.is_month_end = 1
)
SELECT
    c.full_date                                                      AS snapshot_date,
    SUM(s.outstanding_principal)                                     AS portfolio,
    ROUND(100.0 * SUM(s.outstanding_principal) FILTER (WHERE s.days_past_due > 30)
          / SUM(s.outstanding_principal), 2)                         AS par30_pct
FROM v_loan_status_clean s
JOIN compare c ON c.date_id = s.snapshot_date_id
GROUP BY c.full_date
ORDER BY c.full_date;


-- ----------------------------------------------------------------------------
-- 7. Provision coverage at the latest snapshot
--    Provision Coverage = provisions held / PAR30 balance. Target = 100%.
-- ----------------------------------------------------------------------------
SELECT
    SUM(provision_amount)                                            AS provisions_held,
    SUM(outstanding_principal) FILTER (WHERE days_past_due > 30)     AS par30_balance,
    ROUND(100.0 * SUM(provision_amount)
          / SUM(outstanding_principal) FILTER (WHERE days_past_due > 30), 1)
                                                                     AS provision_coverage_pct
FROM v_loan_status_clean
WHERE snapshot_date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean);


-- ----------------------------------------------------------------------------
-- 8. Write-offs
--    A loan is counted as written off in the FIRST month-end where
--    is_written_off = 1. Written-off principal = outstanding at that snapshot.
--    Write-off Rate = written-off principal in period / average portfolio.
-- ----------------------------------------------------------------------------
WITH first_write_off AS (
    SELECT
        s.loan_id,
        MIN(s.snapshot_date_id) AS write_off_date_id
    FROM v_loan_status_clean s
    WHERE s.is_written_off = 1
    GROUP BY s.loan_id
),
write_off_amounts AS (
    SELECT
        d.year,
        COUNT(*)                     AS loans_written_off,
        SUM(s.outstanding_principal) AS written_off_principal
    FROM first_write_off w
    JOIN v_loan_status_clean s
      ON s.loan_id = w.loan_id AND s.snapshot_date_id = w.write_off_date_id
    JOIN dim_date d ON d.date_id = w.write_off_date_id
    GROUP BY d.year
),
avg_portfolio AS (
    SELECT year, AVG(portfolio) AS avg_portfolio
    FROM (
        SELECT d.year, d.full_date, SUM(s.outstanding_principal) AS portfolio
        FROM v_loan_status_clean s
        JOIN dim_date d ON d.date_id = s.snapshot_date_id
        WHERE d.is_month_end = 1
        GROUP BY d.year, d.full_date
    ) m
    GROUP BY year
)
SELECT
    a.year,
    COALESCE(w.loans_written_off, 0)                                 AS loans_written_off,
    COALESCE(w.written_off_principal, 0)                             AS written_off_principal,
    ROUND(a.avg_portfolio, 0)                                        AS avg_portfolio,
    ROUND(100.0 * COALESCE(w.written_off_principal, 0) / a.avg_portfolio, 2)
                                                                     AS write_off_rate_pct
FROM avg_portfolio a
LEFT JOIN write_off_amounts w ON w.year = a.year
ORDER BY a.year;
-- Note: 2026 covers Jan–Jun only; annualise before comparing with full years.


-- ----------------------------------------------------------------------------
-- 9. Cost of risk — trailing 12 months
--    Provision charge = closing provision stock - opening provision stock
--                       + provisions utilised by loans that left the book
--                         while written off.
--    Cost of Risk %   = provision charge / average month-end portfolio.
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
window_ AS (
    SELECT
        MAX(full_date)                                    AS end_date,
        (MAX(full_date) - INTERVAL '12 months')::date     AS start_date
    FROM month_ends
),
stock AS (
    SELECT s.snapshot_date_id, SUM(s.provision_amount) AS provisions, SUM(s.outstanding_principal) AS portfolio
    FROM v_loan_status_clean s
    GROUP BY s.snapshot_date_id
),
utilised AS (
    -- written-off loans whose status rows stop before the latest snapshot:
    -- their last provision is consumed in the following month
    SELECT m.date_id AS utilised_in_date_id, SUM(s.provision_amount) AS utilised
    FROM v_loan_status_clean s
    JOIN (
        SELECT loan_id, MAX(snapshot_date_id) AS last_id
        FROM v_loan_status_clean
        GROUP BY loan_id
    ) last_row ON last_row.loan_id = s.loan_id AND last_row.last_id = s.snapshot_date_id
    JOIN month_ends m ON m.prev_date_id = s.snapshot_date_id
    WHERE s.is_written_off = 1
    GROUP BY m.date_id
),
monthly AS (
    SELECT
        m.full_date,
        cur.portfolio,
        cur.provisions - COALESCE(prev.provisions, 0) + COALESCE(u.utilised, 0) AS provision_charge
    FROM month_ends m
    JOIN stock cur        ON cur.snapshot_date_id  = m.date_id
    LEFT JOIN stock prev  ON prev.snapshot_date_id = m.prev_date_id
    LEFT JOIN utilised u  ON u.utilised_in_date_id = m.date_id
)
SELECT
    w.start_date + 1                                      AS period_start,
    w.end_date                                            AS period_end,
    SUM(provision_charge)                                 AS provision_charge_12m,
    ROUND(AVG(portfolio), 0)                              AS avg_portfolio_12m,
    ROUND(100.0 * SUM(provision_charge) / AVG(portfolio), 2) AS cost_of_risk_pct
FROM monthly
CROSS JOIN window_ w
WHERE monthly.full_date > w.start_date
  AND monthly.full_date <= w.end_date
GROUP BY w.start_date, w.end_date;


-- ----------------------------------------------------------------------------
-- 10. Roll-rate matrix — month-to-month migration between PAR buckets
--     For every loan in bucket X at month-end t-1, where is it at t?
--     "Exited" = no status row at t (repaid / closed).
-- ----------------------------------------------------------------------------
WITH month_ends AS (
    SELECT
        date_id,
        LEAD(date_id) OVER (ORDER BY full_date) AS next_date_id
    FROM dim_date
    WHERE is_month_end = 1
      AND date_id <= (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean)
),
transitions AS (
    SELECT
        cur.par_bucket                         AS from_bucket,
        COALESCE(nxt.par_bucket, 'Exited')     AS to_bucket,
        cur.outstanding_principal              AS from_balance
    FROM v_loan_status_clean cur
    JOIN month_ends m ON m.date_id = cur.snapshot_date_id
    LEFT JOIN v_loan_status_clean nxt
           ON nxt.loan_id = cur.loan_id
          AND nxt.snapshot_date_id = m.next_date_id
    WHERE m.next_date_id IS NOT NULL
      AND cur.is_written_off = 0
)
SELECT
    from_bucket,
    to_bucket,
    COUNT(*)                                                             AS loans,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY from_bucket), 2)
                                                                         AS pct_of_from_bucket_loans,
    ROUND(100.0 * SUM(from_balance) / SUM(SUM(from_balance)) OVER (PARTITION BY from_bucket), 2)
                                                                         AS pct_of_from_bucket_balance
FROM transitions
GROUP BY from_bucket, to_bucket
ORDER BY from_bucket, to_bucket;


-- ----------------------------------------------------------------------------
-- 11. Provision adequacy stress test (scenario, not a forecast)
--     Scenario: every loan currently in 61-90 DPD rolls to 90+ next month.
--     Assumption: 90+ loans are provisioned at the rate currently observed on
--     the 90+ bucket (provision_amount / outstanding).
-- ----------------------------------------------------------------------------
WITH latest AS (
    SELECT *
    FROM v_loan_status_clean
    WHERE snapshot_date_id = (SELECT MAX(snapshot_date_id) FROM v_loan_status_clean)
),
rate_90 AS (
    SELECT SUM(provision_amount) / SUM(outstanding_principal) AS provision_rate_90
    FROM latest
    WHERE days_past_due > 90
)
SELECT
    SUM(l.outstanding_principal)                               AS balance_61_90,
    SUM(l.provision_amount)                                    AS current_provision_61_90,
    ROUND(SUM(l.outstanding_principal) * r.provision_rate_90, 0) AS stressed_provision_61_90,
    ROUND(SUM(l.outstanding_principal) * r.provision_rate_90 - SUM(l.provision_amount), 0)
                                                               AS additional_provision_required
FROM latest l
CROSS JOIN rate_90 r
WHERE l.days_past_due BETWEEN 61 AND 90
GROUP BY r.provision_rate_90;
