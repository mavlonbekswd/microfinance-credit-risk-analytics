# Methodology

How every number in this project is defined, which table it comes from, and which data-treatment decisions were made.

---

## Data-quality discovery — duplicated latest loan-status snapshot

**Status: resolved in the analytical layer. The source table is left unchanged.**

Validating the intended grain of `fact_loan_status` (one row per `snapshot_date_id`, `loan_id`) showed that the **latest snapshot breaks it**:

| Check | Result |
|---|---|
| Month-end snapshots in the table | 42 |
| Snapshots with one row per loan | 41 (2023-01-31 → 2026-05-31) |
| Snapshot 1277 (2026-06-30) | **7,830 rows for 3,915 distinct loans.** Every loan appears twice |
| Copies with identical `outstanding_principal` | All 3,915 pairs |
| Copies conflicting on `days_past_due` | 226 pairs |
| …of which also conflicting on `par_bucket` and `provision_amount` | 4 pairs |
| Copies conflicting on `is_written_off` or dimension keys | 0 |

**Why it matters.** Because outstanding principal is the same in both copies, a plain `SUM` over the raw table doubles every balance at 2026-06-30. The portfolio appears to jump from UZS 131.72B (2026-05-31) to UZS 260.27B in one month. The same distortion reaches every metric that uses the latest month: PAR30 balance, provisions held, year-on-year growth, average portfolio, cost of risk, yield and the operating cost ratio. The UZS 260.27B figure quoted in the original dataset guide comes from this double count and is **not used** anywhere in this project.

**Treatment.**

1. The raw table `fact_loan_status` is **not modified or deleted**. The audit queries in `01_data_validation.sql` §10 read it as loaded.
2. A cleaned analytical view, **`v_loan_status_clean`**, enforces the intended grain (`01_data_validation.sql` §11):

   ```sql
   ROW_NUMBER() OVER (PARTITION BY snapshot_date_id, loan_id ORDER BY status_id DESC)  -- keep rn = 1
   ```

   The tie-break is deterministic: when copies conflict, the row with the highest `status_id` (the most recently written row) is kept.
3. Every analysis in `02`–`08` and the Power BI model reads `v_loan_status_clean`. None of them query the raw table directly.
4. Reconciliation (`01_data_validation.sql` §11b–§11c): the 41 clean snapshots are identical in raw and cleaned form. Only 2026-06-30 changes, from 7,830 rows / UZS 260,268,759,000 to 3,915 rows / UZS 130,134,379,500.

**Effect of the tie-break.** Ratios move slightly because 226 copies disagree on days past due. PAR30 is 8.18% on the cleaned layer against 8.16% on the raw table. In the 4 pairs that disagree on bucket, the kept row moves loans between `1-30`, `31-60`, `61-90` and `90+`.

## 1. Source of truth for credit risk

`fact_loan_status`, read through the cleaned view **`v_loan_status_clean`**, is the **only** official source for delinquency, PAR, provisions and write-offs.

- The cleaned view holds exactly one row per loan per month-end snapshot.
- PAR is **not** reconstructed by comparing `fact_schedule` (what the client should pay) with `fact_payment` (what the client actually paid). That comparison is a useful cross-check, but it is not the official number.
- Any trend joins `snapshot_date_id` → `dim_date[date_id]` and filters `dim_date[is_month_end] = 1`.
- Point-in-time KPIs use a single snapshot — by default the latest one (`snapshot_date_id = 1277`, 2026-06-30). Status rows from different months are never summed together.

## 2. PAR definitions

| Metric | Numerator | Denominator |
|---|---|---|
| PAR30 % | Outstanding principal where `days_past_due > 30` | Total outstanding principal, same snapshot |
| PAR90 % | Outstanding principal where `days_past_due > 90` | Total outstanding principal, same snapshot |

- PAR is based on **outstanding money**, not on customer or loan count.
- PAR30 does not mean every loan will default. It means that share of the current outstanding portfolio is more than 30 days late.
- PAR bucket boundaries in the data: `Standart` (0 DPD), `1-30 kun`, `31-60 kun`, `61-90 kun`, `90+ kun`. `days_past_due > 30` is equivalent to the last three buckets (checked in `01_data_validation.sql`, section 7).

## 3. Validated headline figures

Calculated on `v_loan_status_clean` at `snapshot_date_id = 1277` (2026-06-30, `is_month_end = 1`):

| Metric | Value | Source |
|---|---:|---|
| Portfolio outstanding | 130,134,379,500 UZS | `02` §3 |
| PAR30 amount | 10,641,742,000 UZS | `03` §1 |
| PAR30 | 8.18% | `03` §1 |
| PAR90 | 7.04% | `03` §2 |
| Provisions held | 10,880,576,900 UZS | `03` §7 |
| Provision coverage (provisions ÷ PAR30 balance) | 102.2% | `03` §7 |
| Active loans (not written off) | 3,855 | `02` §5 |
| Active clients | 2,655 | `02` §5 |
| Cost of risk, trailing 12 months (2025-07-01 → 2026-06-30) | 4.52% | `03` §9 |
| Overall application approval rate | 60.1% | `06` §2 (unaffected; from `fact_application`) |

One year earlier (2025-06-30, same layer): portfolio UZS 107,866,333,000, PAR30 6.55%, active loans 3,227, active clients 2,326.

Latest PAR bucket distribution (% of outstanding):

| Bucket | Share |
|---|---:|
| Standart | 91.82% |
| 1-30 | 0.00% (no loans) |
| 31-60 | 0.55% |
| 61-90 | 0.58% |
| 90+ | 7.04% |

Exact PAR30 is 8.18%. The rounded bucket values sum to 8.17%.

Superseded raw-table values, kept for audit only: portfolio 260,268,759,000 UZS, PAR30 amount 21,249,317,300 UZS, PAR30 8.16%.

## 4. Portfolio and activity

| Metric | Definition |
|---|---|
| Disbursed | `SUM(fact_loan.principal_amount)` by disbursement date |
| Loan Count | Rows in `fact_loan` (one row per disbursed loan) |
| Avg Ticket | Disbursed ÷ Loan Count |
| Approval Rate % | Approved applications ÷ all applications (`fact_application`) |
| Portfolio Outstanding | `SUM(outstanding_principal)` at a single month-end snapshot |
| Active Loans | Distinct loans in the snapshot with outstanding principal > 0 and `is_written_off = 0` |
| Active Clients | Distinct clients holding at least one active loan |
| Disbursed YTD vs PY | Same calendar window (1 Jan → snapshot date) in both years |

## 5. Provisions, write-offs and cost of risk

| Metric | Definition |
|---|---|
| Provision Coverage | Provisions held ÷ PAR30 balance, same snapshot. Target = 100% |
| Write-off Rate | Principal written off in the period ÷ average month-end portfolio. A loan counts as written off at the **first** snapshot where `is_written_off = 1`. |
| Provision charge | Closing provision stock − opening provision stock + provisions used up by written-off loans that leave the book |
| Cost of Risk % | Provision charge in the period ÷ average month-end portfolio |

Average portfolio = mean of the month-end portfolios inside the period. Partial-year periods (2026 = January–June) must be annualised before they are compared with full years.

**Write-off treatment in the headline portfolio.** The validated portfolio figure is the plain sum of `outstanding_principal` at the latest snapshot. It therefore **includes** loans flagged `is_written_off = 1` that are still present in the snapshot. `01_data_validation.sql` §11d measures this component: 60 written-off loans with UZS 2,714,290,700 outstanding at 2026-06-30. Active Loans excludes written-off loans.

## 6. Efficiency

| Metric | Definition |
|---|---|
| Cost per Active Loan | Branch total cost (trailing 12 months) ÷ average month-end active loans |
| Operating Cost Ratio | Branch total cost (trailing 12 months) ÷ average month-end portfolio |
| Loans per Officer | Active loans ÷ officers employed at the snapshot date (`hire_date ≤ date` and `termination_date` empty or later) |
| Cost per branch-handled transaction | Branch total cost ÷ `Filial kassasi` (cash-desk) transactions only |

**Channel classification** (`fact_transaction_daily.channel`):

| Channel | Meaning | Branch-handled? | Digital? |
|---|---|---|---|
| Filial kassasi | Branch cash desk | Yes | No |
| Mobil ilova | Mobile app | No | Yes |
| Bank o'tkazmasi | Bank transfer | No | Yes |
| Agent | Agent network | No | No |

Branch cost is never divided by all-channel volume. `07_operations_analysis.sql` §4 shows the incorrect all-channel figure next to the correct one, labelled `DO_NOT_USE`, so the difference is visible.

## 7. Product economics

| Metric | Definition |
|---|---|
| Portfolio Yield % | Contractual interest due in the period (`fact_schedule.interest_due` by due date) ÷ average portfolio |
| Cost of Risk % | As in section 5, per product |
| Risk-Adjusted Yield | Portfolio Yield % − Cost of Risk % |

Products are ranked on **Risk-Adjusted Yield**, never on interest rate alone. A high nominal rate does not help if the product loses a large share of its balance to provisions.

Portfolio yield uses interest **due**, which is the yield the product is priced to earn. Interest actually collected would come from `fact_payment`. Collected yield and due yield are different measures, and the two should not be mixed.

## 8. Branch growth — like-for-like

Branch opening dates differ by years. Xiva opened 2023-02-01, inside the analysis window, while Toshkent — Chilonzor opened 2018-03-01.

- Growth is measured over a fixed window, by default the latest month-end against the same month-end one year earlier.
- A branch is **comparable** only if it was open for the whole window.
- A branch open for less than 12 months at the start of the window is flagged as **young base**, because growth from a near-zero base cannot be compared with growth at a mature branch.
- A branch that opened inside the window is **not comparable**.
- Branch trend charts exclude months before the branch's opening date.

## 9. Vintage analysis

- **Cohort** = calendar quarter of disbursement.
- **Months-on-book (MOB)** = whole months between the disbursement month and the snapshot month (MOB 0 = disbursement month).
- **PAR30 @ MOB n** = PAR30 of the cohort's loans, measured at the snapshot where those loans are *n* months old.
- Reported at MOB 6, 12 and 18. A cohort that has not yet reached MOB *n* returns NULL, meaning it is too young to judge, not zero risk.
- Primary denominator: outstanding at MOB *n*, which keeps the definition consistent with PAR30. Secondary denominator: original disbursed principal of the cohort, which does not change as loans amortise.

A PAR trend by calendar month is **not** a vintage analysis.

## 10. Officer comparison

- Approval rate is never interpreted on its own. It is read together with PAR30 of the officer's book, the average credit score of approved clients, portfolio size and application volume.
- Officers with **fewer than 40 applications** are flagged (`min_sample_flag`) and excluded from ranking queries.
- An officer is flagged as a potential concern only when all three signals point the same way: approval rate above the company average, PAR30 above the company average, and approved-client credit score below the company average.

## 11. Roll rates and stress test

- **Roll rate**: for every loan in bucket X at month-end *t-1*, the bucket it is in at *t*. A loan with no row at *t* counts as `Exited` (repaid or closed). Written-off loans are excluded from the starting population. Each loan contributes one row per snapshot.
- **Provision stress test (scenario, not a forecast)**: every loan in 61-90 DPD rolls to 90+ next month and is provisioned at the rate currently observed on the 90+ bucket. The result is the extra provision this would require.

## 12. Other data treatments

| Topic | Treatment |
|---|---|
| Loans disbursed with no payment recorded | The dataset guide states 252 such loans. They remain in the portfolio, and their risk status comes from `v_loan_status_clean`, not from the absence of payments. Count reproduced in `01_data_validation.sql` §9a. |
| Repeat borrowers | The dataset guide states 2,293 clients have more than one loan. Distribution in `02_portfolio_analysis.sql` §7. |
| Branch costs for not-yet-open branches | `fact_branch_cost` contains no rows for a branch before it opened, so it is not imputed. |
| Client privacy | Client names are never shown alongside delinquency or default status. |
