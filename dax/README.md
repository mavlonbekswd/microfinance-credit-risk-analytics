# DAX

This folder documents the business measures in the Power BI semantic model.

| File | Contents |
|---|---|
| [measures.md](measures.md) | Measure catalogue: name, DAX formula, business definition, denominator / grain, snapshot logic |

## Design principles

1. **One definition per KPI.** Every page uses the same measure, so PAR30 on the executive page and PAR30 on the branch page cannot disagree.
2. **Snapshot-aware balances on a clean grain.** Portfolio, PAR and provisions come from `fact_loan_status_clean`, loaded from the SQL view `v_loan_status_clean` with one row per loan per snapshot. They always resolve to a single month-end snapshot and are never summed across months.
3. **Denominators are explicit.** Every ratio states its denominator. PAR is money-weighted, not loan-count-weighted.
4. **Flow ratios are annualised.** Cost of risk, yield, write-off rate and operating cost ratio use the average month-end portfolio and are annualised, so a half-year can be compared with a full year.
5. **Risk-adjusted, not nominal.** Products are compared on Risk-Adjusted Yield (Portfolio Yield % − Cost of Risk %), not on interest rate.

## Measure index

| Group | Measures |
|---|---|
| Volume | Disbursed, Loan Count, Avg Ticket, Approval Rate %, Disbursed YTD |
| Portfolio | Portfolio Outstanding, Active Loans, Active Clients |
| Credit risk | PAR30 %, PAR90 %, PAR Bucket Share %, Provision Coverage, Write-off Rate, Cost of Risk % |
| Efficiency | Cost per Active Loan, Operating Cost Ratio, Loans per Officer, Cost per Branch-Handled Transaction, Digital Share % |
| Product economics | Portfolio Yield %, Risk-Adjusted Yield |
| Officer analysis | Avg Approved Credit Score, Officer Sample Flag |

The SQL equivalents of these measures are in [`../sql`](../sql) and are used to validate the Power BI values.
