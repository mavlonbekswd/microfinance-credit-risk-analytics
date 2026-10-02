# DAX Measures

Business measures used in the Power BI semantic model. Each entry lists the **business definition**, the **denominator / grain**, any **special snapshot logic**, and the **DAX formula**.

> **TODO before final publication:** reconcile each formula with the published `.pbix`. Then confirm the measure values match the SQL validation on the cleaned layer (`sql/03_credit_risk_analysis.sql` §1 at 2026-06-30: portfolio UZS 130,134,379,500, PAR30 UZS 10,641,742,000 = 8.18%).

## Conventions

- Table and column names match the PostgreSQL source (see [data dictionary](../docs/data_dictionary.md)).
- `dim_date` is marked as the date table on `dim_date[full_date]`.
- **Cleaned loan-status table.** Every loan-status measure reads **`fact_loan_status_clean`**. That model table is loaded from the SQL view `v_loan_status_clean`, not from the raw `fact_loan_status`. It has exactly one row per (`snapshot_date_id`, `loan_id`), keeping the highest `status_id` when the source has duplicates. The raw table contains every loan twice in the 2026-06-30 snapshot ([data-quality discovery](../docs/methodology.md#data-quality-discovery--duplicated-latest-loan-status-snapshot)).
- **Snapshot logic.** `fact_loan_status_clean` is a periodic snapshot. Its balances can be added across loans, branches and products, but **never across time**. Every balance measure first resolves the latest month-end snapshot inside the current filter context, then sums only that snapshot.
- Power Query additions referenced below:
  - `fact_loan_status_clean[client_id]`: merged from `fact_loan` on `loan_id`
  - `fact_loan_status_clean[is_first_write_off]`: 1 on the first snapshot where a loan is written off
  - `fact_provision_utilised`: one row per written-off loan that leaves the book, holding its last `provision_amount`, keyed to the following month-end `date_id`

---

## Helper measures

### Snapshot ID

| | |
|---|---|
| **Business definition** | The latest month-end loan-status snapshot visible in the current filter context |
| **Grain** | Single `date_id` |
| **Snapshot logic** | Restricted to `is_month_end = 1`. When a year or quarter is selected, it returns that period's last month-end |

```DAX
Snapshot ID =
CALCULATE (
    MAX ( fact_loan_status_clean[snapshot_date_id] ),
    dim_date[is_month_end] = 1
)
```

### Avg Portfolio

| | |
|---|---|
| **Business definition** | Average of month-end outstanding portfolios in the period. Used as the denominator for flow ratios (cost of risk, yield, write-offs, operating cost) |
| **Grain** | Month-end snapshots in context |
| **Snapshot logic** | Iterates month-ends, sums each snapshot separately, then averages |

```DAX
Avg Portfolio =
AVERAGEX (
    CALCULATETABLE ( VALUES ( dim_date[date_id] ), dim_date[is_month_end] = 1 ),
    CALCULATE ( SUM ( fact_loan_status_clean[outstanding_principal] ) )
)
```

### Annualisation Factor

| | |
|---|---|
| **Business definition** | Converts a flow over N months to an annual rate (12 / N) so partial periods such as 2026 YTD can be compared with full years |
| **Grain** | Month-ends with snapshot data in context |

```DAX
Annualisation Factor =
VAR _months =
    CALCULATE (
        DISTINCTCOUNT ( fact_loan_status_clean[snapshot_date_id] ),
        dim_date[is_month_end] = 1
    )
RETURN
    DIVIDE ( 12, _months )
```

---

## Volume

### Disbursed

| | |
|---|---|
| **Business definition** | Principal disbursed to clients |
| **Denominator / grain** | `fact_loan`, by disbursement date |
| **Snapshot logic** | None (flow measure) |

```DAX
Disbursed = SUM ( fact_loan[principal_amount] )
```

### Loan Count

| | |
|---|---|
| **Business definition** | Number of disbursed loans |
| **Denominator / grain** | One row per loan in `fact_loan` |
| **Snapshot logic** | None |

```DAX
Loan Count = COUNTROWS ( fact_loan )
```

### Avg Ticket

| | |
|---|---|
| **Business definition** | Average disbursed principal per loan |
| **Denominator / grain** | Loan Count |
| **Snapshot logic** | None |

```DAX
Avg Ticket = DIVIDE ( [Disbursed], [Loan Count] )
```

### Approval Rate %

| | |
|---|---|
| **Business definition** | Share of applications that were approved. Validated overall: 60.1% |
| **Denominator / grain** | All applications in `fact_application` (approved + declined) |
| **Snapshot logic** | None. Filtered by application date |

```DAX
Approval Rate % =
DIVIDE (
    CALCULATE ( COUNTROWS ( fact_application ), fact_application[is_approved] = 1 ),
    COUNTROWS ( fact_application )
)
```

### Disbursed YTD / Disbursed PY YTD

| | |
|---|---|
| **Business definition** | Year-to-date disbursement and the same calendar window one year earlier |
| **Denominator / grain** | `fact_loan` by disbursement date |

```DAX
Disbursed YTD = TOTALYTD ( [Disbursed], dim_date[full_date] )

Disbursed PY YTD = CALCULATE ( [Disbursed YTD], SAMEPERIODLASTYEAR ( dim_date[full_date] ) )
```

---

## Portfolio

### Portfolio Outstanding

| | |
|---|---|
| **Business definition** | Principal still owed by clients at the snapshot date. Validated at 2026-06-30 (cleaned layer): UZS 130,134,379,500 |
| **Denominator / grain** | `fact_loan_status_clean`, single month-end snapshot |
| **Snapshot logic** | Sums only the snapshot returned by `[Snapshot ID]` |

```DAX
Portfolio Outstanding =
VAR _snap = [Snapshot ID]
RETURN
    CALCULATE (
        SUM ( fact_loan_status_clean[outstanding_principal] ),
        fact_loan_status_clean[snapshot_date_id] = _snap
    )
```

### Active Loans

| | |
|---|---|
| **Business definition** | Loans on book with outstanding principal and not written off. Validated at 2026-06-30 (cleaned layer): 3,855 |
| **Denominator / grain** | Distinct `loan_id` at a single snapshot |
| **Snapshot logic** | Latest snapshot in context. The cleaned table already has one row per loan; `DISTINCTCOUNT` keeps the measure correct if that ever breaks |

```DAX
Active Loans =
VAR _snap = [Snapshot ID]
RETURN
    CALCULATE (
        DISTINCTCOUNT ( fact_loan_status_clean[loan_id] ),
        fact_loan_status_clean[snapshot_date_id] = _snap,
        fact_loan_status_clean[is_written_off] = 0,
        fact_loan_status_clean[outstanding_principal] > 0
    )
```

### Active Clients

| | |
|---|---|
| **Business definition** | Distinct clients holding at least one active loan. Validated at 2026-06-30 (cleaned layer): 2,655 |
| **Denominator / grain** | Distinct `client_id` at a single snapshot |
| **Snapshot logic** | Same as Active Loans. Requires `client_id` merged into `fact_loan_status_clean` in Power Query |

```DAX
Active Clients =
VAR _snap = [Snapshot ID]
RETURN
    CALCULATE (
        DISTINCTCOUNT ( fact_loan_status_clean[client_id] ),
        fact_loan_status_clean[snapshot_date_id] = _snap,
        fact_loan_status_clean[is_written_off] = 0,
        fact_loan_status_clean[outstanding_principal] > 0
    )
```

### Portfolio Outstanding PY

| | |
|---|---|
| **Business definition** | Portfolio at the equivalent snapshot one year earlier (for KPI-card comparisons) |
| **Snapshot logic** | Shifts the date context back one year, then resolves that period's latest month-end |

```DAX
Portfolio Outstanding PY =
CALCULATE ( [Portfolio Outstanding], SAMEPERIODLASTYEAR ( dim_date[full_date] ) )
```

---

## Credit risk

### PAR30 Amount

| | |
|---|---|
| **Business definition** | Outstanding principal of loans more than 30 days past due. Validated at 2026-06-30 (cleaned layer): UZS 10,641,742,000 |
| **Denominator / grain** | Single month-end snapshot |
| **Snapshot logic** | Latest snapshot in context |

```DAX
PAR30 Amount =
VAR _snap = [Snapshot ID]
RETURN
    CALCULATE (
        SUM ( fact_loan_status_clean[outstanding_principal] ),
        fact_loan_status_clean[snapshot_date_id] = _snap,
        fact_loan_status_clean[days_past_due] > 30
    )
```

### PAR30 %

| | |
|---|---|
| **Business definition** | Share of the outstanding portfolio more than 30 days late. Validated at 2026-06-30 (cleaned layer): **8.18%**. Board threshold: 6% |
| **Denominator / grain** | Portfolio Outstanding at the same snapshot. **Money-weighted, not loan count** |
| **Snapshot logic** | Numerator and denominator use the same snapshot |

```DAX
PAR30 % = DIVIDE ( [PAR30 Amount], [Portfolio Outstanding] )
```

### PAR90 %

| | |
|---|---|
| **Business definition** | Share of the outstanding portfolio more than 90 days late. Validated at 2026-06-30 (cleaned layer): 7.04% |
| **Denominator / grain** | Portfolio Outstanding at the same snapshot |
| **Snapshot logic** | Latest snapshot in context |

```DAX
PAR90 % =
VAR _snap = [Snapshot ID]
VAR _par90 =
    CALCULATE (
        SUM ( fact_loan_status_clean[outstanding_principal] ),
        fact_loan_status_clean[snapshot_date_id] = _snap,
        fact_loan_status_clean[days_past_due] > 90
    )
RETURN
    DIVIDE ( _par90, [Portfolio Outstanding] )
```

### PAR Bucket Share %

| | |
|---|---|
| **Business definition** | Share of the portfolio in each PAR bucket. Used with `par_bucket` on the legend for the stacked composition chart |
| **Denominator / grain** | Total portfolio at the snapshot, across all buckets |
| **Snapshot logic** | Latest snapshot in context. The denominator removes the bucket filter |

```DAX
PAR Bucket Share % =
DIVIDE (
    [Portfolio Outstanding],
    CALCULATE ( [Portfolio Outstanding], REMOVEFILTERS ( fact_loan_status_clean[par_bucket] ) )
)
```

### Provision Coverage

| | |
|---|---|
| **Business definition** | Provisions held relative to the PAR30 balance. Target = 100%. Validated at 2026-06-30 (cleaned layer): 102.2% (UZS 10,880,576,900 ÷ UZS 10,641,742,000) |
| **Denominator / grain** | PAR30 Amount at the same snapshot |
| **Snapshot logic** | Latest snapshot in context |

```DAX
Provisions Held =
VAR _snap = [Snapshot ID]
RETURN
    CALCULATE (
        SUM ( fact_loan_status_clean[provision_amount] ),
        fact_loan_status_clean[snapshot_date_id] = _snap
    )

Provision Coverage = DIVIDE ( [Provisions Held], [PAR30 Amount] )
```

### Write-off Rate

| | |
|---|---|
| **Business definition** | Principal written off in the period relative to the average portfolio, annualised |
| **Denominator / grain** | Avg Portfolio over the month-ends in context |
| **Snapshot logic** | A loan counts once, at its **first** written-off snapshot (`is_first_write_off = 1`) |

```DAX
Written-off Principal =
CALCULATE (
    SUM ( fact_loan_status_clean[outstanding_principal] ),
    fact_loan_status_clean[is_first_write_off] = 1,
    dim_date[is_month_end] = 1
)

Write-off Rate =
DIVIDE ( [Written-off Principal], [Avg Portfolio] ) * [Annualisation Factor]
```

### Cost of Risk %

| | |
|---|---|
| **Business definition** | Provision charge for the period relative to the average portfolio, annualised. Provision charge = closing provision stock − opening provision stock + provisions used up by written-off loans that leave the book. Validated, trailing 12 months to 2026-06-30 (cleaned layer): 4.52% |
| **Denominator / grain** | Avg Portfolio over the month-ends in context |
| **Snapshot logic** | Opening stock = month-end immediately before the first month-end in context. Closing stock = latest month-end in context |

```DAX
Provision Charge =
VAR _firstMonthEnd =
    CALCULATE ( MIN ( dim_date[full_date] ), dim_date[is_month_end] = 1 )
VAR _openingDate = EOMONTH ( _firstMonthEnd, -1 )
VAR _openingStock =
    CALCULATE (
        SUM ( fact_loan_status_clean[provision_amount] ),
        REMOVEFILTERS ( dim_date ),
        dim_date[full_date] = _openingDate
    )
VAR _utilised = SUM ( fact_provision_utilised[provision_amount] )
RETURN
    [Provisions Held] - _openingStock + _utilised

Cost of Risk % =
DIVIDE ( [Provision Charge], [Avg Portfolio] ) * [Annualisation Factor]
```

---

## Efficiency

### Cost per Active Loan

| | |
|---|---|
| **Business definition** | Branch operating cost per active loan serviced, annualised |
| **Denominator / grain** | Average month-end active loans in the period |
| **Snapshot logic** | Active loans averaged across month-ends. Cost summed across months |

```DAX
Avg Active Loans =
AVERAGEX (
    CALCULATETABLE ( VALUES ( dim_date[date_id] ), dim_date[is_month_end] = 1 ),
    CALCULATE (
        DISTINCTCOUNT ( fact_loan_status_clean[loan_id] ),
        fact_loan_status_clean[is_written_off] = 0
    )
)

Branch Cost = SUM ( fact_branch_cost[total_cost] )

Cost per Active Loan =
DIVIDE ( [Branch Cost], [Avg Active Loans] ) * [Annualisation Factor]
```

### Operating Cost Ratio

| | |
|---|---|
| **Business definition** | Operating cost relative to the average portfolio, annualised |
| **Denominator / grain** | Avg Portfolio |
| **Snapshot logic** | As Avg Portfolio |

```DAX
Operating Cost Ratio =
DIVIDE ( [Branch Cost], [Avg Portfolio] ) * [Annualisation Factor]
```

### Loans per Officer

| | |
|---|---|
| **Business definition** | Active loans per loan officer employed at the snapshot date |
| **Denominator / grain** | Officers with `hire_date` ≤ snapshot date and no termination, or termination after that date |
| **Snapshot logic** | Latest snapshot in context |

```DAX
Active Officers =
VAR _snap = [Snapshot ID]
VAR _snapDate =
    CALCULATE ( MAX ( dim_date[full_date] ), REMOVEFILTERS ( dim_date ), dim_date[date_id] = _snap )
RETURN
    COUNTROWS (
        FILTER (
            dim_officer,
            dim_officer[hire_date] <= _snapDate
                && ( ISBLANK ( dim_officer[termination_date] )
                     || dim_officer[termination_date] > _snapDate )
        )
    )

Loans per Officer = DIVIDE ( [Active Loans], [Active Officers] )
```

### Cost per Branch-Handled Transaction

| | |
|---|---|
| **Business definition** | Branch operating cost per cash-desk transaction |
| **Denominator / grain** | `Filial kassasi` transactions only. **Never all channels** |
| **Snapshot logic** | None (flow) |

```DAX
Branch-Handled Transactions =
CALCULATE (
    SUM ( fact_transaction_daily[transaction_count] ),
    fact_transaction_daily[channel] = "Filial kassasi"
)

Cost per Branch-Handled Transaction =
DIVIDE ( [Branch Cost], [Branch-Handled Transactions] )
```

### Digital Share %

| | |
|---|---|
| **Business definition** | Share of transactions through mobile app or bank transfer |
| **Denominator / grain** | All transactions in `fact_transaction_daily` |

```DAX
Digital Share % =
DIVIDE (
    CALCULATE (
        SUM ( fact_transaction_daily[transaction_count] ),
        fact_transaction_daily[channel] IN { "Mobil ilova", "Bank o'tkazmasi" }
    ),
    SUM ( fact_transaction_daily[transaction_count] )
)
```

---

## Product economics

### Portfolio Yield %

| | |
|---|---|
| **Business definition** | Contractual interest due in the period relative to the average portfolio, annualised |
| **Denominator / grain** | Avg Portfolio |
| **Snapshot logic** | Interest by `fact_schedule[due_date_id]`. Portfolio averaged across month-ends |

```DAX
Interest Due = SUM ( fact_schedule[interest_due] )

Portfolio Yield % =
DIVIDE ( [Interest Due], [Avg Portfolio] ) * [Annualisation Factor]
```

### Risk-Adjusted Yield

| | |
|---|---|
| **Business definition** | What the portfolio earns after credit losses. **Products are ranked on this measure, not on interest rate** |
| **Denominator / grain** | Both components share the Avg Portfolio denominator |
| **Snapshot logic** | Inherits from Portfolio Yield % and Cost of Risk % |

```DAX
Risk-Adjusted Yield = [Portfolio Yield %] - [Cost of Risk %]
```

---

## Officer analysis helpers

### Avg Approved Credit Score

```DAX
Avg Approved Credit Score =
CALCULATE ( AVERAGE ( fact_application[credit_score] ), fact_application[is_approved] = 1 )
```

### Officer Sample Flag

| | |
|---|---|
| **Business definition** | Flags officers with fewer than 40 applications. Their ratios are noise and must not be used to name a problem officer |

```DAX
Applications = COUNTROWS ( fact_application )

Officer Sample Flag =
IF ( [Applications] < 40, "Below 40 applications", "OK" )
```
