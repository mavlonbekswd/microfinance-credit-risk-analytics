# Business Questions

## Core question

> **Is the portfolio growing faster or slower than the risk inside it?**

## Questions by dashboard page

| Page | Business question | Decision it supports |
|---|---|---|
| 1. Executive Portfolio Overview | Is the portfolio growing faster or slower than the risk inside it? | Board-level view of portfolio health |
| 2. Branch Performance | Which branch is growing into a problem? | Where to spend a single intervention budget |
| 3. Product & Profitability | Which product is priced as if it were safe when it is not? | Which products to push, which to reprice |
| 4. Loan Officer Risk | Is anyone approving loans they should not be approving? | Retraining, supervision, file re-audits |
| 5. Channels & Operating Cost | Are we still paying for cash desks that nobody uses? | Support or oppose closing branch cash desks |
| 6. Advanced Risk Analysis | Do newer loans perform better or worse than older loans at the same age, and where is delinquency migrating? | Underwriting policy and loss forecasting |

## Executive question bank

The questions below are the ones senior management is expected to ask. Each is mapped to the analysis that answers it. Answers are recorded in [findings.md](findings.md) only once validated.

| # | Question | Where it is answered | Answer |
|---|---|---|---|
| 1 | What is our PAR30 today, and what was it a year ago? | `03_credit_risk_analysis.sql` §6 · Page 1 | 8.18% at 2026-06-30 vs 6.55% at 2025-06-30 (SQL, cleaned layer) |
| 2 | Which branch is worst, and is it getting worse or better? | `04_branch_analysis.sql` §1, §4 · Page 2 | TBD |
| 3 | That branch is growing fast. Is the growth causing the risk, or is it separate? | `04_branch_analysis.sql` §3 · Page 2 quadrant | TBD |
| 4 | Which product loses us the most money after provisions? | `05_product_analysis.sql` §3 · Page 3 | TBD |
| 5 | Would raising that product's rate fix it, or is the problem the customer? | `05_product_analysis.sql` §5, `08_vintage_analysis.sql` §5 | TBD |
| 6 | Do loans we gave in 2024 look better or worse than the ones we gave in 2023, at the same age? | `08_vintage_analysis.sql` §3 · Page 6 | TBD |
| 7 | Which officer approves the most, and what does their portfolio look like? | `06_officer_analysis.sql` §1, §3 · Page 4 | TBD |
| 8 | What credit score do our defaults cluster around? Should we move the cut-off? | `06_officer_analysis.sql` §5 · Page 6 (optional cut-off simulator) | TBD |
| 9 | How much of the portfolio is covered by provisions right now? | `03_credit_risk_analysis.sql` §7 · Page 1 | Provisions are 102.2% of the PAR30 balance at 2026-06-30 (SQL, cleaned layer) |
| 10 | What does it cost us to service one loan, and which branch is furthest from the average? | `04_branch_analysis.sql` §5 · Page 2 | TBD |
| 11 | How many of our transactions still go through a cash desk? | `07_operations_analysis.sql` §2 · Page 5 | TBD |
| 12 | If we closed our worst branch tomorrow, what would it save and what would it cost? | `04_branch_analysis.sql` §5, `07_operations_analysis.sql` §6 | TBD |

## Advanced analysis options (Page 6)

The preferred combination is **Vintage Analysis + Roll Rate / Early Warning**.

| Option | Question | SQL |
|---|---|---|
| A. Roll rate matrix | Of loans in bucket X last month, what share moved to a worse bucket and what share cured? | `03_credit_risk_analysis.sql` §10 |
| B. Credit score cut-off simulator | If the minimum score were raised, how many loans would be declined, how much interest lost, how much default avoided? | Power BI what-if parameter (TODO) |
| C. Early warning flags | Which loans that are currently Standart look most like loans that went bad? | TODO |
| D. Repeat borrower analysis | Do second loans perform better or worse than first loans? | `02_portfolio_analysis.sql` §7 (base) |
| E. Sector concentration | Which sector is the portfolio most exposed to, and how has its PAR moved? | TODO |
| F. Officer capacity curve | Is there a caseload beyond which officer PAR rises? | `06_officer_analysis.sql` §7 |
| G. Provision adequacy stress test | If every 61-90 loan rolled to 90+, what extra provision would be needed? | `03_credit_risk_analysis.sql` §11 |

For the advanced page, record in plain text:

- **What was built:** TBD (one sentence)
- **Why the business needs it:** TBD (two sentences maximum)
- **What decision it supports:** TBD (one sentence, a real decision)
