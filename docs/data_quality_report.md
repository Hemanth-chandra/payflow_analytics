# Data quality report

This report explains what the checks in `sql/03_data_quality_checks.sql` test, what they found, and what each result means for the analysis.

## How the checks work

Every check applies one rule to one table and records how many rows were tested and how many failed. Results are written to `analytics.data_quality_results`.

| Severity | Meaning | Effect |
|---|---|---|
| Critical | The data cannot be used if this fails | `04_build_analytics_layer.sql` refuses to run |
| Warning | The data is usable, but the limitation must be stated | The build continues |

| Rule type | Checks | What it tests |
|---|---:|---|
| Uniqueness | 6 | Each primary key value appears once |
| Completeness | 6 | No missing values in any column |
| Referential integrity | 5 | Every child row points at a real parent |
| Validity | 7 | Values are inside the allowed range or list |
| Identity | 1 | Email is used by only one customer |
| Date logic | 4 | Events happen in a sensible order |

## Result on the final data

24 checks pass, 5 raise warnings, none fail.

| ID | Rule type | Check | Rows tested | Rows failed | Rate | Status |
|---|---|---|---:|---:|---:|---|
| 101-106 | Uniqueness | All six primary keys are unique | 1,260,000 | 0 | 0.00% | PASS |
| 201-206 | Completeness | No missing values in any table | 1,260,000 | 0 | 0.00% | PASS |
| 301 | Referential integrity | accounts.customer_id exists in customers | 75,000 | 0 | 0.00% | PASS |
| 302 | Referential integrity | loans.customer_id exists in customers | 30,000 | 0 | 0.00% | PASS |
| 303 | Referential integrity | cards.account_id exists in accounts | 100,000 | 0 | 0.00% | PASS |
| 304 | Referential integrity | transactions.account_id exists in accounts | 1,000,000 | 0 | 0.00% | PASS |
| 305 | Referential integrity | transactions.merchant_id exists in merchants | 1,000,000 | 0 | 0.00% | PASS |
| 401-407 | Validity | Credit score, balances, amounts, rates and type lists | 1,360,000 | 0 | 0.00% | PASS |
| 501 | Identity | Email is used by only one customer | 50,000 | 7,600 | 15.20% | WARN |
| 601 | Date logic | Account opened on or after customer created | 75,000 | 37,408 | 49.88% | WARN |
| 602 | Date logic | Loan started on or after customer created | 30,000 | 15,069 | 50.23% | WARN |
| 603 | Date logic | Card expires on or after account opened | 100,000 | 923 | 0.92% | WARN |
| 604 | Date logic | Transaction dated on or after account opened | 1,000,000 | 501,669 | 50.17% | WARN |

## The reconciliation that failed first

### What happened

The first load of the project failed two Critical checks.

| Check | Rows tested | Matched | Unmatched | Match rate |
|---|---:|---:|---:|---:|
| 304: transactions to accounts | 1,000,000 | 111,885 | 888,115 | 11.19% |
| 305: transactions to merchants | 1,000,000 | 0 | 1,000,000 | 0.00% |

### How the cause was found

A match rate this low has two possible causes, and they need different fixes:

- **Bad rows.** Some transactions carry damaged or mistyped ids. Most ids would still overlap with the master table.
- **Wrong file.** The transactions come from a different version of the dataset. The ids look valid, but they belong to a different set of accounts and merchants.

Diagnosis query D1 in script 03 tells them apart by comparing distinct ids rather than rows.

| Key | Distinct ids in transactions | Distinct ids in master | Ids found in both |
|---|---:|---:|---:|
| account_id | 75,000 | 75,000 | 8,393 |
| merchant_id | 5,000 | 5,000 | 0 |

Both sides hold exactly the same number of ids, with almost no overlap. Damaged rows cannot produce that pattern. A complete, well-formed file from another generation of the dataset can.

Two further facts confirmed it:

- Every id had the correct format and length, with no blanks, so nothing was truncated or mistyped. Matching again after trimming spaces and ignoring case gave the same 111,885.
- The source package holds a second transactions extract. Tested against the same master tables, it matched 1,000,000 of 1,000,000 on both keys.

### The fix

The matching transactions extract was loaded in place of the mismatched one. Both checks now pass at 100%.

| Check | First load | After fix |
|---|---:|---:|
| Transactions matched to an account | 111,885 (11.19%) | 1,000,000 (100%) |
| Transactions matched to a merchant | 0 (0%) | 1,000,000 (100%) |
| Accounts with at least one transaction | 8,393 of 75,000 | 75,000 of 75,000 |
| Merchants with at least one transaction | 0 of 5,000 | 5,000 of 5,000 |

### What changed in the analysis

| Analysis | Before | After |
|---|---|---|
| Merchant reporting | Ids only, names unusable | Merchant names and cities available |
| Customer spending | Based on 11% of transactions | Based on all transactions |
| Top 10 accounts by value | 9 of the 10 could not be linked to an owner | All linked to account type and customer |

### What prevents a repeat

- The analytics tables carry foreign keys from transactions to accounts and merchants, so a mismatched extract fails at load time.
- Script 04 checks the results table first and stops if any Critical check failed.
- Script 02 compares loaded row counts with the expected counts for every file.

## Reading the warnings

### 501: shared emails

7,600 customers share an email with at least one other customer. They form 3,373 groups, the largest with 9 customers.

If these were the same person entered twice, the records in a group would share a name. Diagnosis query D2 shows that no group shares a name and no group shares a city. The emails are coincidental.

| | |
|---|---|
| Impact | Email cannot be used to identify, match or count customers |
| Action | Use `customer_id` as the only customer key. Do not deduplicate on email |

### 601, 602, 604: date order

About half of all accounts, loans and transactions are dated before the event that should come first.

| Check | Failure rate |
|---|---:|
| Account opened before customer created | 49.88% |
| Loan started before customer created | 50.23% |
| Transaction dated before account opened | 50.17% |

A rule that fails for 1% of rows gives a list of exceptions to investigate. A rule that fails for 50% of rows means the two dates have no relationship: either order is equally likely.

| | |
|---|---|
| Impact | Customer tenure, account age and time-to-first-transaction cannot be measured |
| Action | Use each date only within its own table (customers by creation year, transactions by month). Do not compare dates across tables |

### 603: cards expiring before the account opened

923 cards (0.92%) have an expiry date earlier than the opening date of their account. The rate is low enough that these are genuine exceptions. Diagnosis query D4 lists the worst cases.

| | |
|---|---|
| Impact | Small. These cards are counted as expired |
| Action | Review the listed cards against the card system of record |

## Reporting date

Card status is calculated as of 31 December 2025, the last transaction date in the data. On that date 12,665 cards had expired. Using the day the script is run instead would make the expired count grow every day without any change in the data.
