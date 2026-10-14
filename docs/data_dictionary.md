# Data dictionary

All tables below are in the `analytics` schema, which is what Power BI reads. The `staging` schema holds the same data as loaded from the CSV files, without the derived columns.

Columns marked **derived** are calculated in `sql/04_build_analytics_layer.sql`. Everything else comes straight from the source files.

## customers

One row per customer. 50,000 rows.

| Column | Type | Description |
|---|---|---|
| customer_id | VARCHAR(20) | Primary key |
| first_name | VARCHAR(50) | |
| last_name | VARCHAR(50) | |
| email | VARCHAR(100) | Not unique: 7,600 customers share an email with someone else |
| city | VARCHAR(50) | 25,169 distinct values, so too granular to group by |
| credit_score | INT | 300 to 850 |
| created_at | DATE | Date the customer record was created, 2019 to 2025 |

## accounts

One row per deposit account. 75,000 rows.

| Column | Type | Description |
|---|---|---|
| account_id | VARCHAR(20) | Primary key |
| customer_id | VARCHAR(20) | Foreign key to customers |
| first_name | VARCHAR(50) | **Derived.** Copied from customers |
| last_name | VARCHAR(50) | **Derived.** Copied from customers |
| city | VARCHAR(50) | **Derived.** Copied from customers |
| account_type | VARCHAR(20) | Checking, Savings or Business |
| balance_usd | DECIMAL(12,2) | Balance at the reporting date. A single snapshot, no history |
| open_date | DATE | Date the account was opened, 2019 to 2025 |
| account_date_valid | INT | **Derived.** 1 if `open_date` is on or after the customer's `created_at`, otherwise 0 |

## cards

One row per card. 100,000 rows.

| Column | Type | Description |
|---|---|---|
| card_id | VARCHAR(20) | Primary key |
| account_id | VARCHAR(20) | Foreign key to accounts |
| card_type | VARCHAR(20) | Debit or Credit |
| expiration_date | DATE | 2025 to 2032 |
| card_status | VARCHAR(10) | **Derived.** Expired if `expiration_date` is on or before the reporting date (31 December 2025), otherwise Active |

## loans

One row per loan. 30,000 rows.

| Column | Type | Description |
|---|---|---|
| loan_id | VARCHAR(20) | Primary key |
| customer_id | VARCHAR(20) | Foreign key to customers |
| first_name | VARCHAR(50) | **Derived.** Copied from customers |
| last_name | VARCHAR(50) | **Derived.** Copied from customers |
| city | VARCHAR(50) | **Derived.** Copied from customers |
| credit_score | INT | **Derived.** Copied from customers |
| loan_amount | DECIMAL(12,2) | Original loan amount in USD |
| interest_rate | DECIMAL(5,2) | Annual rate in percent, 2.00 to 15.00 |
| start_date | DATE | Date the loan started, 2019 to 2025 |
| loan_date_valid | INT | **Derived.** 1 if `start_date` is on or after the customer's `created_at`, otherwise 0 |

## merchants

One row per merchant. 5,000 rows.

| Column | Type | Description |
|---|---|---|
| merchant_id | VARCHAR(20) | Primary key |
| merchant_name | VARCHAR(100) | |
| city | VARCHAR(50) | |

## transactions

One row per payment. 1,000,000 rows.

| Column | Type | Description |
|---|---|---|
| transaction_id | VARCHAR(25) | Primary key |
| account_id | VARCHAR(20) | Foreign key to accounts |
| merchant_id | VARCHAR(20) | Foreign key to merchants |
| amount_usd | DECIMAL(12,2) | 1.02 to 9,999.98 |
| transaction_date | DATETIME2(0) | Date and time of the payment, 2019 to 2025 |
| account_match_status | VARCHAR(10) | **Derived.** Matched if `account_id` exists in accounts, otherwise Unmatched |
| merchant_match_status | VARCHAR(10) | **Derived.** Matched if `merchant_id` exists in merchants, otherwise Unmatched |

## data_quality_results

One row per data-quality check. 29 rows. Written by `sql/03_data_quality_checks.sql`.

| Column | Type | Description |
|---|---|---|
| check_id | INT | Primary key. The first digit is the rule type |
| category | VARCHAR(30) | Uniqueness, Completeness, Referential integrity, Validity, Identity or Date logic |
| check_name | VARCHAR(120) | The rule being tested |
| table_name | VARCHAR(40) | Table the rule applies to |
| severity | VARCHAR(10) | Critical or Warning |
| rows_tested | INT | Rows the rule was applied to |
| rows_failed | INT | Rows that broke the rule |
| fail_pct | DECIMAL(6,2) | `rows_failed` as a percentage of `rows_tested` |
| status | VARCHAR(10) | PASS, WARN or FAIL |

## vw_customer_summary (view)

One row per customer, 50,000 rows, with everything the customer holds and does.

| Column | Description |
|---|---|
| customer_id, first_name, last_name, city, created_at, credit_score | From customers |
| credit_category | Low (under 580), Medium (580 to 669), Good (670 to 739), Excellent (740 and over) |
| credit_category_sort | 1 to 4, for ordering the categories |
| account_count | Number of deposit accounts. 0 if none |
| total_balance | Sum of balances across the customer's accounts |
| loan_count | Number of loans. 0 if none |
| total_loan_amount | Sum of the customer's loan amounts |
| avg_interest_rate | Average rate across the customer's loans. NULL if the customer has no loan |
| card_count | Number of cards across the customer's accounts |
| transaction_count | Number of transactions across the customer's accounts |
| total_spent | Sum of transaction amounts across the customer's accounts |

## Conventions

| Term | Definition |
|---|---|
| Reporting date | 31 December 2025, the last transaction date in the data |
| Credit category | Low under 580, Medium 580 to 669, Good 670 to 739, Excellent 740 and over |
| Loan size | Small up to $100,000, Medium up to $200,000, Large over $200,000 |
