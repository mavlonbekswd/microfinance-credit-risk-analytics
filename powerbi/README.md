# Power BI Report

The Power BI report connects the analytical model to executive decision-making.

Main areas:
- portfolio growth,
- credit risk,
- branch performance,
- product economics,
- officer behaviour,
- operating efficiency,
- vintage / advanced risk analysis.

### [▶ Live Power BI Dashboard](https://app.powerbi.com/view?r=eyJrIjoiMjljYjQxYjAtMjMyNy00MWU4LWI1NTAtN2JkZWZhNDRjMjZjIiwidCI6ImIxNzNiMGY3LWMyNGItNGQ3OS04NzZlLWI1ZjBhZDUxNmQ0MSIsImMiOjZ9)

## Files

| File | Status |
|---|---|
| `microfinance_dashboard.pbit` | **TODO:** export from Power BI Desktop (*File → Export → Power BI template*) and add to this folder. A template contains the model, measures and visuals but no data and no credentials. |

## Data source for loan status

The report loads loan-status data from the cleaned SQL view **`v_loan_status_clean`** (model table `fact_loan_status_clean`), **not** from the raw `fact_loan_status`. The raw table contains every loan twice in the 2026-06-30 snapshot, which doubles balances ([data-quality discovery](../docs/methodology.md#data-quality-discovery--duplicated-latest-loan-status-snapshot)).

**TODO:** repoint the published report at `v_loan_status_clean` (or apply the same de-duplication in Power Query), refresh, and confirm the KPI cards match the SQL validation at 2026-06-30: portfolio UZS 130.13B, PAR30 8.18%, PAR30 balance UZS 10.64B, PAR90 7.04%, provision coverage 102.2%. Until then the live dashboard may still show the superseded UZS 260.27B portfolio.

The `.pbix` is not committed: it embeds data and can be large. Screenshots are in [`../images`](../images) and the measures are documented in [`../dax/measures.md`](../dax/measures.md).

Before committing the template, confirm it contains **no** saved database credentials, server addresses or local IP addresses. Power BI templates prompt for connection parameters on open.

---

## Report pages

### Page 1 — Executive Portfolio Overview

**Question:** Is the portfolio growing faster or slower than the risk inside it?

- KPI cards with prior-year comparison: Portfolio Outstanding, Disbursed YTD, Active Loans, Active Clients, PAR30 %, Cost of Risk %
- Portfolio Outstanding by month with PAR30 % on the same trend view (secondary axis)
- PAR bucket composition over time, as % of portfolio
- Portfolio and PAR30 by branch, sorted by PAR30, with the company-average PAR30 reference line
- Provision Coverage with a target line at 100%

### Page 2 — Branch Performance

**Question:** Which branch is growing into a problem?

- Branch table: portfolio, disbursed YTD, active loans, PAR30, PAR90, cost per active loan, operating cost ratio, loans per officer, with conditional formatting on risk columns
- Growth vs PAR30 quadrant scatter (bubble size = portfolio), with quadrants labelled in words
- PAR30 trend by branch
- Branch map sized by portfolio, coloured by PAR30
- Cost per active loan vs branch size

Growth is **like-for-like**: branches are only compared over periods in which they existed.

### Page 3 — Product & Profitability

**Question:** Which product is priced as if it were safe when it is not?

- Product table: loan count, average ticket, average rate, portfolio, PAR30, provision %, portfolio yield, **risk-adjusted yield**
- Disbursement mix by product over time (100% stacked)
- Interest rate vs PAR30 scatter (bubble size = portfolio)
- Vintage analysis: PAR30 at 6, 12 and 18 months-on-book by disbursement cohort
- Approval rate and requested vs approved amount by product

### Page 4 — Loan Officer Risk

**Question:** Is anyone approving loans they should not be approving?

- Officer table: applications handled, approval rate, loans disbursed, portfolio, PAR30, average approved credit score, average granted rate
- Approval rate vs PAR30 scatter (bubble size = portfolio) with company-average reference lines on both axes
- Decline reason mix
- Approved credit-score distribution by officer
- Officer portfolio growth over the latest 12 months

Officers with **fewer than 40 applications** are excluded or flagged.

### Page 5 — Channels & Operating Cost

**Question:** Are we still paying for cash desks that nobody uses?

- Transaction count by channel over time, and channel share of total
- Cashier transactions per branch employee
- Branch cost per **branch-handled** transaction
- Payment channel mix by branch
- Headcount vs transaction volume, latest 12 months

### Page 6 — Advanced Risk Analysis

Preferred: **Vintage Analysis + Roll Rate / Early Warning**.

- Vintage curves: PAR30 by months-on-book, one line per disbursement cohort
- Roll-rate matrix: month-to-month migration between delinquency buckets
- TODO: confirm the final option set used in the published report

---

## Presentation rules

- Every risk percentage has its denominator stated on the page.
- No page has more than seven visuals.
- Risk trends use month-end snapshots only.
- Client names are never displayed alongside delinquency or default status.
