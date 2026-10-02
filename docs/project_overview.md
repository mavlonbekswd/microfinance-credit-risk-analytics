# Project Overview

## The company

**Ishonch Mikromoliya** is a fictional microfinance organisation in Uzbekistan. It is not a bank and does not take deposits.

- It **borrows wholesale** from funders.
- It **lends retail** to individuals and small businesses.
- It earns money from the **spread** between lending income and its funding, operating and credit-loss costs.

| Item | Value |
|---|---:|
| Period | 2023-01-01 to 2026-06-30 |
| Currency | UZS |
| Branches | 12 |
| Loan officers | 50 |
| Loan products | 6 |
| Clients | ~5,000 |
| Disbursed loans | 7,959 |
| Tables | 12 |
| Rows | ~315,000 |

## The problem

> **The portfolio is growing — but is that growth healthy, or is credit risk growing underneath it?**

In lending, revenue is recognised today and losses show up months later. A branch or product that is growing quickly will look strong this year because its loans have not yet had time to go bad. If a dashboard ranks branches on growth alone, it rewards whoever is being least careful.

For this reason the project never shows loan growth on its own. Growth is always read alongside:

- credit risk (PAR30, PAR90, provisions, write-offs),
- branch performance (like-for-like),
- product economics (risk-adjusted yield),
- loan officer behaviour,
- operating efficiency,
- delinquency migration (roll rates),
- portfolio maturity (vintage analysis).

## Audience

| Stakeholder | What they need |
|---|---|
| CEO / board | The state of the portfolio in one page: is growth outpacing risk? |
| Risk director | Official PAR from month-end snapshots, vintage, roll rates, provision coverage, cost of risk |
| Product committee | Which products to push and which to reprice, on a risk-adjusted basis |
| Branch / operations leadership | Which branch needs intervention, and whether cash desks still pay for themselves |

## Board benchmark

```text
PAR30 above 6% = problem threshold
```

Latest validated PAR30 (2026-06-30, cleaned loan-status layer): **8.18%** on a portfolio of UZS 130.13B.

## Deliverables

| Deliverable | Location |
|---|---|
| SQL validation and analysis scripts | [`sql/`](../sql) |
| Power BI report (template + live link) | [`powerbi/`](../powerbi) |
| DAX measure catalogue | [`dax/measures.md`](../dax/measures.md) |
| Business questions | [`business_questions.md`](business_questions.md) |
| Data dictionary and model | [`data_dictionary.md`](data_dictionary.md), [`data_model.md`](data_model.md) |
| Methodology and assumptions | [`methodology.md`](methodology.md) |
| Findings and recommendations | [`findings.md`](findings.md) |

## Data disclaimer

This project uses a fictional / synthetic microfinance dataset created for analytics and portfolio demonstration purposes. It does not contain real customer banking data.
