# Assets

Supporting material for presenting the repository.

## GitHub "About" description

```text
End-to-end PostgreSQL + Power BI credit risk and portfolio analytics project using 315K+ microfinance records.
```

## GitHub topics

```text
power-bi
postgresql
sql
dax
data-analytics
business-intelligence
credit-risk
portfolio-analysis
fintech
data-visualization
```

## Website field

Use the live Power BI dashboard URL:

```text
https://app.powerbi.com/view?r=eyJrIjoiMjljYjQxYjAtMjMyNy00MWU4LWI1NTAtN2JkZWZhNDRjMjZjIiwidCI6ImIxNzNiMGY3LWMyNGItNGQ3OS04NzZlLWI1ZjBhZDUxNmQ0MSIsImMiOjZ9
```

## CV project description

Metrics come from the cleaned loan-status layer (`v_loan_status_clean`), validated in SQL at 2026-06-30.

```text
Microfinance Credit Risk & Portfolio Analytics | PostgreSQL, Power BI, DAX
GitHub | Live Dashboard

• Built an end-to-end credit risk and portfolio analytics solution on 315K+ records across 12 relational tables, covering 7,959 loans, ~5,000 clients, 12 branches and 50 loan officers.
• Developed a Power BI semantic model and DAX measures for Portfolio Outstanding, PAR30/PAR90, Approval Rate, Provision Coverage, Cost of Risk, Portfolio Yield and Risk-Adjusted Yield, validating a UZS 130.13B portfolio with 8.18% PAR30 at the latest snapshot.
• Detected a duplicated month-end loan-status snapshot (7,830 rows for 3,915 loans) that doubled reported balances; built a de-duplicated analytical layer enforcing one row per loan per snapshot without altering source data.
• Designed executive dashboards combining portfolio growth with credit risk, including vintage analysis, like-for-like branch comparisons, product profitability, loan-officer performance and operational efficiency to support lending and risk-management decisions.
```

Before using the PAR30 or portfolio figures on the CV, confirm the live dashboard shows the same values (see `powerbi/README.md`).

## Source data

The synthetic PostgreSQL dump (`microfinance_ishonch.sql`, 12 tables, ~315,000 rows) is not committed to this repository. To reproduce the SQL results, load the dump into a local PostgreSQL database and run the scripts in `sql/` in numeric order. `01_data_validation.sql` creates the `v_loan_status_clean` view that scripts 02–08 depend on. Keep connection details in a local, git-ignored `.env` file. Never put them in the scripts.
