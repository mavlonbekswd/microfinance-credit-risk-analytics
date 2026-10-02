# Key Findings

> **Status: pending validation.** No analytical finding is published until its number has been calculated, validated in SQL and reconciled with the Power BI report. Fields marked `TBD` are deliberately empty rather than estimated.

**Format rule:** every finding states a **Name + Number + Direction**, for example *"[Branch Name] PAR30 reached X.X%, up from Y.Y% one year earlier."* Every finding is paired with a business recommendation.

**Baseline (validated in SQL on the cleaned layer `v_loan_status_clean`):** at 2026-06-30, company PAR30 is **8.18%**, above the **6%** board threshold, on a portfolio of UZS 130.13B. See the [validation log](#validation-log) and the [data-quality discovery](methodology.md#data-quality-discovery--duplicated-latest-loan-status-snapshot).

---

## 1. Portfolio Risk

**Finding:** TBD

**Evidence:** TBD. Source: `sql/03_credit_risk_analysis.sql` §4 and §6, Power BI page 1.

**Direction:** TBD

**Business implication:** TBD

**Recommendation:** TBD

---

## 2. Branch Risk

**Finding:** TBD

**Evidence:** TBD. Source: `sql/04_branch_analysis.sql` §1, §3 and §5, Power BI page 2.

**Direction:** TBD

**Business implication:** TBD

**Recommendation:** TBD

> Check before publishing: risk and efficiency must be read on the same chart, and growth must be like-for-like.

---

## 3. Product Economics

**Finding:** TBD

**Evidence:** TBD. Source: `sql/05_product_analysis.sql` §2 and §3, Power BI page 3.

**Direction:** TBD

**Business implication:** TBD

**Recommendation:** TBD

> Check before publishing: products are ranked on risk-adjusted yield, not on interest rate.

---

## 4. Loan Officer Behaviour

**Finding:** TBD

**Evidence:** TBD. Source: `sql/06_officer_analysis.sql` §1 and §3, Power BI page 4.

**Direction:** TBD

**Business implication:** TBD

**Recommendation:** TBD

> Check before publishing: the officer has at least 40 applications, and approval rate, PAR30 and approved credit score all point the same way.

---

## 5. Operating Efficiency

**Finding:** TBD

**Evidence:** TBD. Source: `sql/07_operations_analysis.sql` §2, §4 and §6, Power BI page 5.

**Direction:** TBD

**Business implication:** TBD

**Recommendation:** TBD

> Check before publishing: cost per transaction uses branch-handled transactions only, and digital share is stated with start and end figures.

---

## 6. Advanced Risk / Vintage

**Finding:** TBD

**Evidence:** TBD. Source: `sql/08_vintage_analysis.sql` §3, `sql/03_credit_risk_analysis.sql` §10 and §11, Power BI page 6.

**Direction:** TBD

**Business implication:** TBD

**Recommendation:** TBD

> Check before publishing: cohorts are compared at equal months-on-book, and cohorts too young to reach a given MOB are excluded.

---

## Validation log

Record each number here before it appears anywhere else in the repository.

| # | Metric | Value (cleaned layer) | SQL source | Power BI reconciled | Date validated |
|---|---|---:|---|---|---|
| 1 | Latest snapshot | 2026-06-30 (id 1277) | `01_data_validation.sql` §5 | TBD | 2026-10-02 (SQL) |
| 2 | Portfolio outstanding | 130,134,379,500 UZS | `02_portfolio_analysis.sql` §3 | TBD | 2026-10-02 (SQL) |
| 3 | PAR30 amount | 10,641,742,000 UZS | `03_credit_risk_analysis.sql` §1 | TBD | 2026-10-02 (SQL) |
| 4 | PAR30 % | 8.18% | `03_credit_risk_analysis.sql` §1 | TBD | 2026-10-02 (SQL) |
| 5 | PAR90 % | 7.04% | `03_credit_risk_analysis.sql` §2 | TBD | 2026-10-02 (SQL) |
| 6 | Provision coverage | 102.2% | `03_credit_risk_analysis.sql` §7 | TBD | 2026-10-02 (SQL) |
| 7 | PAR30 % one year earlier (2025-06-30) | 6.55% | `03_credit_risk_analysis.sql` §6 | TBD | 2026-10-02 (SQL) |
| 8 | Portfolio one year earlier (2025-06-30) | 107,866,333,000 UZS | `03_credit_risk_analysis.sql` §6 | TBD | 2026-10-02 (SQL) |
| 9 | Active loans / active clients | 3,855 / 2,655 | `02_portfolio_analysis.sql` §5 | TBD | 2026-10-02 (SQL) |
| 10 | Cost of risk, trailing 12 months | 4.52% | `03_credit_risk_analysis.sql` §9 | TBD | 2026-10-02 (SQL) |
| 11 | Overall approval rate | 60.1% | `06_officer_analysis.sql` §2 | TBD | 2026-10-02 (SQL) |

Superseded (raw table, duplicated snapshot, audit only): portfolio 260,268,759,000 UZS · PAR30 amount 21,249,317,300 UZS · PAR30 8.16%.
