-- ============================================================================
-- 07_operations_analysis.sql
-- Purpose : Are we still paying for cash desks that nobody uses?
--           Channel mix, digital share, cashier workload and branch cost per
--           branch-handled transaction.
-- Channels in fact_transaction_daily:
--   'Filial kassasi'   = branch cash desk   -> the ONLY branch-handled channel
--   'Mobil ilova'      = mobile app         -> digital
--   'Bank o''tkazmasi' = bank transfer      -> digital / remote
--   'Agent'            = agent network      -> remote, not branch-handled
-- Rule    : Branch cost per transaction divides branch operating cost by
--           branch-handled ('Filial kassasi') transactions only. Dividing by
--           all channels would make every branch look efficient and hide the
--           shift to digital.
-- Source  : v_loan_status_clean (cleaned loan-status layer, one row per
--           snapshot_date_id x loan_id). Run 01_data_validation.sql first.
--           The raw fact_loan_status table is never queried directly here.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Transactions by channel by month, with share of total
-- ----------------------------------------------------------------------------
SELECT
    date_trunc('month', d.full_date)::date                              AS month,
    t.channel,
    SUM(t.transaction_count)                                            AS transactions,
    SUM(t.transaction_value)                                            AS transaction_value,
    ROUND(100.0 * SUM(t.transaction_count)
          / SUM(SUM(t.transaction_count)) OVER (PARTITION BY date_trunc('month', d.full_date)), 2)
                                                                        AS share_of_month_pct
FROM fact_transaction_daily t
JOIN dim_date d ON d.date_id = t.date_id
GROUP BY date_trunc('month', d.full_date), t.channel
ORDER BY month, t.channel;


-- ----------------------------------------------------------------------------
-- 2. Digital share — first vs last month of the period
--    Digital share  = ('Mobil ilova' + 'Bank o''tkazmasi') / all transactions
--    Mobile share   = 'Mobil ilova' / all transactions
--    Cash-desk share = 'Filial kassasi' / all transactions
-- ----------------------------------------------------------------------------
WITH monthly AS (
    SELECT
        date_trunc('month', d.full_date)::date                                         AS month,
        SUM(t.transaction_count)                                                       AS total_tx,
        SUM(t.transaction_count) FILTER (WHERE t.channel IN ('Mobil ilova', 'Bank o''tkazmasi')) AS digital_tx,
        SUM(t.transaction_count) FILTER (WHERE t.channel = 'Mobil ilova')              AS mobile_tx,
        SUM(t.transaction_count) FILTER (WHERE t.channel = 'Filial kassasi')           AS cash_desk_tx
    FROM fact_transaction_daily t
    JOIN dim_date d ON d.date_id = t.date_id
    GROUP BY date_trunc('month', d.full_date)
)
SELECT
    month,
    total_tx,
    ROUND(100.0 * digital_tx   / total_tx, 1) AS digital_share_pct,
    ROUND(100.0 * mobile_tx    / total_tx, 1) AS mobile_share_pct,
    ROUND(100.0 * cash_desk_tx / total_tx, 1) AS cash_desk_share_pct
FROM monthly
WHERE month IN ((SELECT MIN(month) FROM monthly), (SELECT MAX(month) FROM monthly))
ORDER BY month;


-- ----------------------------------------------------------------------------
-- 3. Branch cashier transactions per branch employee (monthly)
--    Headcount comes from fact_branch_cost (month-end grain).
-- ----------------------------------------------------------------------------
WITH cash_desk AS (
    SELECT
        t.branch_id,
        date_trunc('month', d.full_date)::date  AS month,
        SUM(t.transaction_count)                AS cash_desk_tx
    FROM fact_transaction_daily t
    JOIN dim_date d ON d.date_id = t.date_id
    WHERE t.channel = 'Filial kassasi'
    GROUP BY t.branch_id, date_trunc('month', d.full_date)
),
cost AS (
    SELECT
        c.branch_id,
        date_trunc('month', d.full_date)::date  AS month,
        c.headcount,
        c.total_cost
    FROM fact_branch_cost c
    JOIN dim_date d ON d.date_id = c.month_end_date_id
)
SELECT
    b.branch_name,
    c.month,
    c.headcount,
    k.cash_desk_tx,
    ROUND(1.0 * k.cash_desk_tx / NULLIF(c.headcount, 0), 1)          AS cash_desk_tx_per_employee
FROM cost c
JOIN dim_branch b     ON b.branch_id = c.branch_id
LEFT JOIN cash_desk k ON k.branch_id = c.branch_id AND k.month = c.month
ORDER BY b.branch_name, c.month;


-- ----------------------------------------------------------------------------
-- 4. Branch operating cost per BRANCH-HANDLED transaction (monthly)
--    Also shows the misleading "all-channel" version side by side so the
--    difference is explicit.
-- ----------------------------------------------------------------------------
WITH tx AS (
    SELECT
        t.branch_id,
        date_trunc('month', d.full_date)::date                                   AS month,
        SUM(t.transaction_count) FILTER (WHERE t.channel = 'Filial kassasi')     AS branch_handled_tx,
        SUM(t.transaction_count)                                                 AS all_channel_tx
    FROM fact_transaction_daily t
    JOIN dim_date d ON d.date_id = t.date_id
    GROUP BY t.branch_id, date_trunc('month', d.full_date)
),
cost AS (
    SELECT c.branch_id, date_trunc('month', d.full_date)::date AS month, c.total_cost
    FROM fact_branch_cost c
    JOIN dim_date d ON d.date_id = c.month_end_date_id
)
SELECT
    b.branch_name,
    c.month,
    c.total_cost,
    x.branch_handled_tx,
    ROUND(c.total_cost / NULLIF(x.branch_handled_tx, 0), 0)          AS cost_per_branch_handled_tx,
    ROUND(c.total_cost / NULLIF(x.all_channel_tx, 0), 0)             AS cost_per_any_tx_DO_NOT_USE
FROM cost c
JOIN dim_branch b ON b.branch_id = c.branch_id
LEFT JOIN tx    x ON x.branch_id = c.branch_id AND x.month = c.month
ORDER BY b.branch_name, c.month;


-- ----------------------------------------------------------------------------
-- 5. Payment channel mix by branch (fact_payment, loan repayments)
--    Branch = branch of the loan being repaid.
-- ----------------------------------------------------------------------------
SELECT
    b.branch_name,
    p.channel,
    COUNT(*)                                                         AS payments,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY b.branch_name), 1)
                                                                     AS share_of_branch_payments_pct
FROM fact_payment p
JOIN fact_loan  l ON l.loan_id   = p.loan_id
JOIN dim_branch b ON b.branch_id = l.branch_id
GROUP BY b.branch_name, p.channel
ORDER BY b.branch_name, p.channel;


-- ----------------------------------------------------------------------------
-- 6. Headcount vs transaction volume by branch — latest 12 months
-- ----------------------------------------------------------------------------
WITH bounds AS (
    SELECT
        (SELECT full_date FROM dim_date
         WHERE date_id = (SELECT MAX(date_id) FROM fact_transaction_daily)) AS end_date
),
tx AS (
    SELECT
        t.branch_id,
        SUM(t.transaction_count)                                               AS all_tx_12m,
        SUM(t.transaction_count) FILTER (WHERE t.channel = 'Filial kassasi')   AS cash_desk_tx_12m
    FROM fact_transaction_daily t
    JOIN dim_date d ON d.date_id = t.date_id
    CROSS JOIN bounds x
    WHERE d.full_date > (x.end_date - INTERVAL '12 months')::date
      AND d.full_date <= x.end_date
    GROUP BY t.branch_id
),
cost AS (
    SELECT c.branch_id, AVG(c.headcount) AS avg_headcount, SUM(c.total_cost) AS total_cost_12m
    FROM fact_branch_cost c
    JOIN dim_date d ON d.date_id = c.month_end_date_id
    CROSS JOIN bounds x
    WHERE d.full_date > (x.end_date - INTERVAL '12 months')::date
      AND d.full_date <= x.end_date
    GROUP BY c.branch_id
)
SELECT
    b.branch_name,
    b.branch_size,
    ROUND(c.avg_headcount, 1)                                         AS avg_headcount,
    x.all_tx_12m,
    x.cash_desk_tx_12m,
    ROUND(100.0 * x.cash_desk_tx_12m / NULLIF(x.all_tx_12m, 0), 1)    AS cash_desk_share_pct,
    ROUND(x.cash_desk_tx_12m / NULLIF(c.avg_headcount, 0), 0)         AS cash_desk_tx_per_employee_12m,
    ROUND(c.total_cost_12m / NULLIF(x.cash_desk_tx_12m, 0), 0)        AS cost_per_branch_handled_tx_12m
FROM dim_branch b
LEFT JOIN tx   x ON x.branch_id = b.branch_id
LEFT JOIN cost c ON c.branch_id = b.branch_id
ORDER BY cost_per_branch_handled_tx_12m DESC NULLS LAST;
