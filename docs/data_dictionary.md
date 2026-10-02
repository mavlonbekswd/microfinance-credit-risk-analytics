# Data Dictionary

Source: `microfinance_ishonch.sql`, a synthetic PostgreSQL dump covering 2023-01-01 → 2026-06-30. All amounts are in **UZS**. Rates are stored as decimals (0.3400 = 34%).

| Table | Type | Rows | Grain |
|---|---|---:|---|
| `dim_date` | Dimension | 1,277 | One calendar day |
| `dim_branch` | Dimension | 12 | One branch |
| `dim_officer` | Dimension | 50 | One loan officer |
| `dim_product` | Dimension | 6 | One loan product |
| `dim_client` | Dimension | 5,000 | One client |
| `fact_application` | Fact | 13,320 | One loan application |
| `fact_loan` | Fact | 7,959 | One disbursed loan |
| `fact_schedule` | Fact | 144,804 | One scheduled instalment |
| `fact_payment` | Fact | 93,786 | One actual payment |
| `fact_loan_status` | Fact | 104,836 | One loan at one month-end snapshot |
| `fact_transaction_daily` | Fact | 49,332 | One day × branch × channel |
| `fact_branch_cost` | Fact | 515 | One branch × month |

---

## Dimensions

### `dim_date`

| Column | Type | Description |
|---|---|---|
| `date_id` | INTEGER (PK) | Surrogate date key, used by every fact table |
| `full_date` | DATE | Calendar date. Mark as the date column in Power BI |
| `year`, `quarter`, `month` | INTEGER | Calendar parts |
| `month_name` | VARCHAR | Month name |
| `week_of_year`, `day_of_month`, `day_of_week` | INTEGER | Calendar parts |
| `day_name` | VARCHAR | Day name |
| `is_weekend`, `is_holiday`, `is_working_day` | INTEGER (0/1) | Calendar flags |
| `is_month_end` | INTEGER (0/1) | **1 on the last day of each month.** Loan-status snapshots land only on these dates, and every risk trend filters on this flag |

### `dim_branch`

| Column | Type | Description |
|---|---|---|
| `branch_id` | INTEGER (PK) | Branch key |
| `branch_name` | VARCHAR | Branch name |
| `region`, `city` | VARCHAR | Location |
| `latitude`, `longitude` | NUMERIC | Coordinates for the branch map |
| `opened_date` | DATE | **Opening dates differ by years** (2018-03-01 to 2023-02-01). Required for like-for-like growth |
| `branch_size` | VARCHAR | Staffing category: `Katta` (large), `O'rta` (medium), `Kichik` (small) |

### `dim_officer`

| Column | Type | Description |
|---|---|---|
| `officer_id` | INTEGER (PK) | Officer key |
| `full_name` | VARCHAR | Officer name |
| `branch_id` | INTEGER (FK) | Each officer is tied to one branch |
| `hire_date` | DATE | Start date |
| `termination_date` | DATE | NULL = still employed |
| `grade` | VARCHAR | Seniority grade |
| `base_salary` | NUMERIC | Base salary |

### `dim_product`

| Column | Type | Description |
|---|---|---|
| `product_id` | INTEGER (PK) | Product key |
| `product_name` | VARCHAR | `Mikroqarz`, `Biznes qarz`, `Agro qarz`, `Iste'mol qarzi`, `Avto qarz`, `Ayollar tadbirkorligi` |
| `client_type` | VARCHAR | `Individual` or `Biznes` |
| `min_amount`, `max_amount` | NUMERIC | Amount band |
| `min_term_months`, `max_term_months` | INTEGER | Term band |
| `base_rate` | NUMERIC | Product standard annual rate. Actual loan rates vary around it |
| `collateral_type` | VARCHAR | Collateral requirement |

### `dim_client`

| Column | Type | Description |
|---|---|---|
| `client_id` | INTEGER (PK) | Client key |
| `full_name` | VARCHAR | Client name. **Never displayed alongside delinquency or default status** |
| `segment` | VARCHAR | Client segment |
| `home_branch_id` | INTEGER (FK) | Home branch |
| `region`, `city` | VARCHAR | Location |
| `sector` | VARCHAR | Economic sector, used for concentration analysis |
| `registration_date` | DATE | Client registration date |
| `latitude`, `longitude` | NUMERIC | Coordinates |
| `credit_score` | INTEGER | 280–850 |
| `years_in_business` | INTEGER | Business tenure |

---

## Facts

### `fact_application`: one row per loan application

| Column | Type | Description |
|---|---|---|
| `application_id` | INTEGER (PK) | Application key |
| `application_date_id` | INTEGER (FK → dim_date) | Date submitted |
| `decision_date_id` | INTEGER (FK → dim_date) | Date decided |
| `client_id`, `branch_id`, `officer_id`, `product_id` | INTEGER (FK) | Dimension keys |
| `requested_amount` | NUMERIC | Amount requested |
| `credit_score` | INTEGER | Client credit score at application |
| `is_approved` | INTEGER (0/1) | Decision. Overall approval rate = 60.1% |
| `decline_reason` | VARCHAR | Populated only for declined applications |

Contains both approved and declined applications.

### `fact_loan`: one row per disbursed loan

| Column | Type | Description |
|---|---|---|
| `loan_id` | INTEGER (PK) | Loan key |
| `application_id` | INTEGER (FK → fact_application) | Every loan has exactly one application; not every application has a loan |
| `client_id`, `branch_id`, `officer_id`, `product_id` | INTEGER (FK) | Dimension keys |
| `disbursement_date_id` | INTEGER (FK → dim_date) | Disbursement date |
| `principal_amount` | NUMERIC | Disbursed principal |
| `annual_rate` | NUMERIC | Granted annual rate |
| `term_months` | INTEGER | Loan term |
| `collateral_type` | VARCHAR | Collateral held |

### `fact_schedule`: one row per scheduled instalment (what the client **should** pay)

| Column | Type | Description |
|---|---|---|
| `schedule_id` | INTEGER (PK) | Instalment key |
| `loan_id` | INTEGER (FK) | Loan |
| `installment_no` | INTEGER | Instalment sequence |
| `due_date_id` | INTEGER (FK → dim_date) | Due date |
| `principal_due`, `interest_due`, `total_due` | NUMERIC | Amounts due |
| `balance_after` | NUMERIC | Scheduled balance after this instalment |

Generated at disbursement. Used for contractual portfolio yield (`interest_due`).

### `fact_payment`: one row per actual payment (what the client **actually** paid)

| Column | Type | Description |
|---|---|---|
| `payment_id` | INTEGER (PK) | Payment key |
| `loan_id` | INTEGER (FK) | Loan |
| `payment_date_id` | INTEGER (FK → dim_date) | Payment date |
| `installment_no` | INTEGER | Instalment being paid |
| `amount_paid` | NUMERIC | Amount received |
| `days_late` | INTEGER | Days after due date |
| `channel` | VARCHAR | `Filial kassasi`, `Mobil ilova`, `Bank o'tkazmasi`, `Agent` |

Schedule rows with no matching payment are missed instalments. Payments are a cross-check only; they are **not** the source for official PAR.

### `fact_loan_status`: one row per loan per month-end snapshot (**official risk table**)

| Column | Type | Description |
|---|---|---|
| `status_id` | INTEGER (PK) | Row key |
| `snapshot_date_id` | INTEGER (FK → dim_date) | Month-end snapshot date (`is_month_end = 1`) |
| `loan_id` | INTEGER (FK) | Loan |
| `branch_id`, `officer_id`, `product_id` | INTEGER (FK) | Dimension keys |
| `outstanding_principal` | NUMERIC | Principal outstanding at the snapshot |
| `days_past_due` | INTEGER | Days past due at the snapshot |
| `par_bucket` | VARCHAR | `Standart`, `1-30 kun`, `31-60 kun`, `61-90 kun`, `90+ kun` |
| `provision_amount` | NUMERIC | Provision held against the loan |
| `is_written_off` | INTEGER (0/1) | Write-off flag |

**Data-quality issue:** snapshot 1277 (2026-06-30) contains 7,830 rows for 3,915 loans, so every loan appears twice. The raw table is left unchanged. All analysis reads the cleaned view below. See [methodology](methodology.md#data-quality-discovery--duplicated-latest-loan-status-snapshot).

### `v_loan_status_clean`: cleaned analytical layer (view, created in `sql/01_data_validation.sql` §11)

Same columns as `fact_loan_status`, with the intended grain enforced: exactly one row per (`snapshot_date_id`, `loan_id`). Rule: `ROW_NUMBER() OVER (PARTITION BY snapshot_date_id, loan_id ORDER BY status_id DESC) = 1`. 100,921 rows (raw: 104,836).

### `fact_transaction_daily`: one row per day × branch × channel

| Column | Type | Description |
|---|---|---|
| `tx_id` | INTEGER (PK) | Row key |
| `date_id` | INTEGER (FK → dim_date) | Transaction date |
| `branch_id` | INTEGER (FK) | Branch |
| `channel` | VARCHAR | `Filial kassasi` (branch cash desk, the only branch-handled channel), `Mobil ilova` (mobile app), `Bank o'tkazmasi` (bank transfer), `Agent` |
| `transaction_count` | INTEGER | Number of transactions |
| `transaction_value` | NUMERIC | Value of transactions |

### `fact_branch_cost`: one row per branch per month

| Column | Type | Description |
|---|---|---|
| `cost_id` | INTEGER (PK) | Row key |
| `month_end_date_id` | INTEGER (FK → dim_date) | Month-end date |
| `branch_id` | INTEGER (FK) | Branch |
| `headcount` | INTEGER | Branch staff |
| `salary_cost`, `rent_cost`, `other_cost` | NUMERIC | Cost components |
| `total_cost` | NUMERIC | Total monthly operating cost |
