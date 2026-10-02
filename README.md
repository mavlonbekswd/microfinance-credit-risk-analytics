# Microfinance Credit Risk & Portfolio Analytics

End-to-end PostgreSQL + Power BI analytics project focused on identifying whether portfolio growth is sustainable or hiding increasing credit risk.

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=flat&logo=postgresql&logoColor=white)
![Power BI](https://img.shields.io/badge/Power%20BI-F2C811?style=flat&logo=powerbi&logoColor=black)
![DAX](https://img.shields.io/badge/DAX-555555?style=flat)
![SQL](https://img.shields.io/badge/SQL-336791?style=flat)

### [▶ Live Power BI Dashboard](https://app.powerbi.com/view?r=eyJrIjoiMjljYjQxYjAtMjMyNy00MWU4LWI1NTAtN2JkZWZhNDRjMjZjIiwidCI6ImIxNzNiMGY3LWMyNGItNGQ3OS04NzZlLWI1ZjBhZDUxNmQ0MSIsImMiOjZ9)

<!-- TODO: add the overview screenshot once final, then uncomment:
![Executive Portfolio Overview](images/dashboard_overview.png)
-->

> This project uses a fictional / synthetic microfinance dataset created for analytics and portfolio demonstration purposes. It does not contain real customer banking data.

---

## Business Problem

> A growing loan portfolio can look healthy before delinquency has had time to emerge. This project analyses whether lending growth is creating sustainable value or increasing hidden credit risk across branches, products and loan officers.

```text
Core question:
Is the portfolio growing faster or slower than the risk inside it?
```

## About the Project

This project analyses the lending portfolio of **Ishonch Mikromoliya**, a fictional microfinance company, using PostgreSQL and Power BI. The company does not take deposits: it borrows wholesale, lends retail, and earns the spread between lending income and its funding, operating and credit-loss costs.

The goal is not simply to visualise loan growth. In lending, risk often appears after revenue has already been recognised, meaning a fast-growing branch or product can look strong before delinquency becomes visible.

The analysis therefore connects portfolio growth with credit risk, product economics, branch efficiency, loan-officer behaviour and operating cost.

## Project Scope

```text
315K+ records
12 relational tables
7,959 loans
~5,000 clients
12 branches
50 loan officers
6 loan products
2023-01-01 → 2026-06-30   (currency: UZS)
```

## Key Validated Metrics

Latest month-end snapshot: **2026-06-30** (`snapshot_date_id = 1277`). Calculated on the cleaned loan-status layer.

| KPI | 2026-06-30 | 2025-06-30 |
|---|---:|---:|
| Portfolio Outstanding | UZS 130.13B | UZS 107.87B |
| PAR30 | 8.18% | 6.55% |
| PAR30 Balance | UZS 10.64B | — |
| PAR90 | 7.04% | — |
| Provision Coverage (provisions ÷ PAR30 balance) | 102.2% | — |
| Active Loans | 3,855 | 3,227 |
| Cost of Risk (trailing 12 months) | 4.52% | — |
| Overall Approval Rate (all applications, 2023–2026) | 60.1% | |

Project benchmark: **PAR30 above 6% is considered problematic.**

PAR30 = outstanding principal of loans more than 30 days past due ÷ total outstanding principal, taken from the month-end loan-status snapshot.

### Analytical validation in practice

Checking the grain of the risk table before building any KPI showed that **every loan in the latest snapshot appeared twice** (7,830 rows for 3,915 loans). The duplicates doubled the reported portfolio, from UZS 130.13B to the UZS 260.27B quoted in the source guide. The raw data is left untouched. A cleaned view (`v_loan_status_clean`) enforces one row per loan per snapshot with a deterministic tie-break, and every analysis runs on that view. Details: [Methodology → Data-quality discovery](docs/methodology.md#data-quality-discovery--duplicated-latest-loan-status-snapshot).

## Key Analytical Challenge

A young loan portfolio often appears cleaner because loans have not had enough time to become delinquent.

For that reason, this project avoids simplistic growth rankings and uses:
- month-end loan-status snapshots,
- like-for-like branch comparisons,
- risk-adjusted product analysis,
- loan vintage analysis,
- sample-size controls for officer performance.

## Architecture / Workflow

```text
PostgreSQL
   ↓
SQL Validation & Analysis
   ↓
Power Query
   ↓
Power BI Data Model
   ↓
DAX Measures
   ↓
Interactive Executive Dashboard
   ↓
Business Findings & Recommendations
```

## Data Model

The model follows a **star / constellation** design: five shared dimensions serve seven fact tables at different grains.

| Dimensions | Facts |
|---|---|
| Date | Applications |
| Branch | Loans |
| Officer | Schedules |
| Product | Payments |
| Client | Loan Status |
| | Transactions |
| | Branch Costs |

<!-- TODO: add the Power BI model view, then uncomment:
![Data model](images/data_model.png)
-->

Full details: [data model](docs/data_model.md) · [data dictionary](docs/data_dictionary.md)

## Modelling Rules

These rules decide whether the numbers can be trusted.

| Area | Rule |
|---|---|
| **Risk / delinquency** | `fact_loan_status` is the only official source for PAR, read through the cleaned view `v_loan_status_clean` (one row per loan per snapshot). PAR is never reconstructed from schedule vs payment records. |
| **Risk trends** | Join `snapshot_date_id` to `dim_date[date_id]` and filter `dim_date[is_month_end] = 1`. Historical status rows are never summed as if they were independent loans. |
| **Branch growth** | Branch opening dates differ by years, so growth is compared like-for-like, never across periods in which a branch did not exist. |
| **Vintage analysis** | Loans are grouped by disbursement cohort and compared at the same months-on-book (6 / 12 / 18). A calendar-month PAR trend is not a vintage analysis. |
| **Officer comparison** | Approval rate is read together with PAR30, approved-client credit score, portfolio size and sample size. Officers with fewer than 40 applications are excluded or flagged. |
| **Branch transaction cost** | Branch operating cost is divided by branch-handled (cash-desk) transactions only, never by all channels including the mobile app. |

## Dashboard Pages

| # | Page | Business question |
|---|---|---|
| 1 | Executive Portfolio Overview | Is the portfolio growing faster or slower than the risk inside it? |
| 2 | Branch Performance | Which branch is growing into a problem? |
| 3 | Product & Profitability | Which product is priced as if it were safe when it is not? |
| 4 | Loan Officer Risk | Is anyone approving loans they should not be approving? |
| 5 | Channels & Operating Cost | Are we still paying for cash desks that nobody uses? |
| 6 | Advanced Risk Analysis | Vintage analysis + roll-rate / early-warning view |

Page-by-page content: [powerbi/README.md](powerbi/README.md)

<!-- TODO: add page screenshots once final, then uncomment:
| Branch Performance | Product & Profitability |
|---|---|
| ![](images/branch_analysis.png) | ![](images/product_analysis.png) |
| **Loan Officer Risk** | **Channels & Operating Cost** |
| ![](images/officer_analysis.png) | ![](images/operations_analysis.png) |
| **Vintage Analysis** | |
| ![](images/vintage_analysis.png) | |
-->

## Key Findings

Each finding follows **Name + Number + Direction** and is paired with a business recommendation. Findings are published only after the underlying number has been validated in SQL and Power BI.

| Area | Finding | Status |
|---|---|---|
| Portfolio Risk | TBD | Pending validation |
| Branch Risk | TBD | Pending validation |
| Product Economics | TBD | Pending validation |
| Loan Officer Behaviour | TBD | Pending validation |
| Operating Efficiency | TBD | Pending validation |
| Advanced Risk / Vintage | TBD | Pending validation |

Full write-up: [docs/findings.md](docs/findings.md)

## Repository Structure

```text
microfinance-credit-risk-analytics/
├── sql/        PostgreSQL scripts, one file per analytical area (01–08)
├── dax/        DAX measure catalogue with business definitions
├── powerbi/    Power BI template and page documentation
├── docs/       Overview, business questions, data dictionary, model, methodology, findings
├── images/     Dashboard and data-model screenshots
└── assets/     Repository metadata and supporting assets
```

| SQL script | Covers |
|---|---|
| [01_data_validation.sql](sql/01_data_validation.sql) | Row counts, nulls, duplicate keys, date ranges, month-end validation, referential integrity, **duplicate-snapshot audit and the cleaned `v_loan_status_clean` layer** (run first) |
| [02_portfolio_analysis.sql](sql/02_portfolio_analysis.sql) | Disbursement, loan count, average ticket, portfolio trend, active loans and clients |
| [03_credit_risk_analysis.sql](sql/03_credit_risk_analysis.sql) | PAR30, PAR90, bucket mix, provisions, write-offs, cost of risk, roll rates, stress test |
| [04_branch_analysis.sql](sql/04_branch_analysis.sql) | Branch risk, like-for-like growth, cost per active loan, operating cost ratio, loans per officer |
| [05_product_analysis.sql](sql/05_product_analysis.sql) | Product pricing, risk, portfolio yield and risk-adjusted yield |
| [06_officer_analysis.sql](sql/06_officer_analysis.sql) | Officer scorecard with sample-size control, score distribution, decline reasons |
| [07_operations_analysis.sql](sql/07_operations_analysis.sql) | Channel mix, digital share, cost per branch-handled transaction |
| [08_vintage_analysis.sql](sql/08_vintage_analysis.sql) | Quarterly cohorts, months-on-book, PAR30 at 6 / 12 / 18 MOB |

## Skills Demonstrated

```text
SQL querying and validation      Credit risk analytics
Relational data modelling        Portfolio analysis
Power Query                      Vintage analysis
Power BI semantic modelling      Business KPI design
DAX                              Dashboard design
Data storytelling                Business recommendations
```

## Tech Stack

PostgreSQL · SQL · Power BI · Power Query · DAX · Data Modelling · Credit Risk Analytics · Business Intelligence

## Documentation

- [Project overview](docs/project_overview.md)
- [Business questions](docs/business_questions.md)
- [Data dictionary](docs/data_dictionary.md)
- [Data model](docs/data_model.md)
- [Methodology](docs/methodology.md)
- [Findings](docs/findings.md)
- [DAX measures](dax/measures.md)

## Disclaimer

This project uses a fictional / synthetic microfinance dataset created for analytics and portfolio demonstration purposes. It does not contain real customer banking data. Client names are never shown alongside delinquency or default status in the dashboard.
