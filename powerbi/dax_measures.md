# Power BI model and DAX

`PayFlow_Analytics.pbix` imports seven tables from the `PayFlowAnalytics` database on SQL Server, plus one table entered in the report. Table names below are the names used in the model.

## Tables

| Table | Source | Used for |
|---|---|---|
| `analytics customers` | `analytics.customers` | Customers, credit categories |
| `analytics accounts` | `analytics.accounts` | Deposit accounts and balances |
| `analytics cards` | `analytics.cards` | Cards and card status |
| `analytics loans` | `analytics.loans` | Loans and interest rates |
| `analytics merchants` | `analytics.merchants` | Merchant names |
| `analytics transactions` | `analytics.transactions` | Payments |
| `analytics data_quality_results` | `analytics.data_quality_results` | The 29-check scorecard |
| `Reconciliation` | Entered in the report | First load vs after fix |
| `Business Impact` | DAX table | Issues, impact and actions |
| `Customer Email Quality` | DAX table | Unique vs shared emails |
| `Data Quality Exceptions` | DAX table | Axis for the date-order chart |

## Relationships

All are many-to-one, single direction, filtering from the "one" side to the "many" side.

| From (many) | To (one) |
|---|---|
| `analytics accounts[customer_id]` | `analytics customers[customer_id]` |
| `analytics loans[customer_id]` | `analytics customers[customer_id]` |
| `analytics cards[account_id]` | `analytics accounts[account_id]` |
| `analytics transactions[account_id]` | `analytics accounts[account_id]` |
| `analytics transactions[merchant_id]` | `analytics merchants[merchant_id]` |

There is no shared date table. The Year slicer on the first two pages selects customers by the year they joined (`created_at`); the transactions page filters by transaction year.

## Calculated columns

```dax
-- analytics customers
Credit Category =
SWITCH (
    TRUE (),
    'analytics customers'[credit_score] < 580, "Low",
    'analytics customers'[credit_score] < 670, "Medium",
    'analytics customers'[credit_score] < 740, "Good",
    "Excellent"
)
```

```dax
-- analytics customers: Credit Category is sorted by this column.
-- It is built from credit_score, not from Credit Category, because a
-- column cannot be sorted by a column derived from itself.
Credit Category Sort =
SWITCH (
    TRUE (),
    'analytics customers'[credit_score] < 580, 1,
    'analytics customers'[credit_score] < 670, 2,
    'analytics customers'[credit_score] < 740, 3,
    4
)
```

```dax
-- analytics customers: accounts held, 0 for customers with none
Accounts Held =
COUNTROWS ( RELATEDTABLE ( 'analytics accounts' ) ) + 0
```

```dax
-- analytics customers
Customer Year = YEAR ( 'analytics customers'[created_at] )
```

```dax
-- analytics accounts: transactions made from each account
Transaction Count =
COUNTROWS ( RELATEDTABLE ( 'analytics transactions' ) ) + 0
```

```dax
-- analytics merchants: names repeat (4,557 names for 5,000 merchants),
-- so the label adds the end of the id to keep merchants separate
Merchant Label =
'analytics merchants'[merchant_name] & " ("
    & RIGHT ( 'analytics merchants'[merchant_id], 5 ) & ")"
```

```dax
-- analytics transactions
Transaction Year = YEAR ( 'analytics transactions'[transaction_date] )
```

```dax
-- analytics transactions
Transaction Month Date =
DATE (
    YEAR ( 'analytics transactions'[transaction_date] ),
    MONTH ( 'analytics transactions'[transaction_date] ),
    1
)
```

```dax
-- Business Impact
Priority =
SWITCH (
    'Business Impact'[Issue],
    "Transaction Account Mismatch", "Resolved",
    "Merchant Mapping Failure", "Resolved",
    "Card Date Exceptions", "Low",
    "Medium"
)
```

## Measures

### Executive Overview

```dax
Total Customers = DISTINCTCOUNT ( 'analytics customers'[customer_id] )
```

```dax
Total Bank Balance = SUM ( 'analytics accounts'[balance_usd] )
```

```dax
Total Loan Exposure = SUM ( 'analytics loans'[loan_amount] )
```

```dax
Total Transactions = DISTINCTCOUNT ( 'analytics transactions'[transaction_id] )
```

```dax
Total Transaction Value = SUM ( 'analytics transactions'[amount_usd] )
```

```dax
-- card_status is set in SQL as of the reporting date, 31 December 2025
Expired Cards =
CALCULATE (
    DISTINCTCOUNT ( 'analytics cards'[card_id] ),
    'analytics cards'[card_status] = "Expired"
)
```

### Customer and Account Insights

```dax
Average Account Balance = AVERAGE ( 'analytics accounts'[balance_usd] )
```

```dax
-- Across all customers, including the 11,162 with no account
Avg Accounts per Customer =
DIVIDE (
    COUNTROWS ( 'analytics accounts' ),
    COUNTROWS ( 'analytics customers' )
)
```

```dax
Customers Multiple Accounts =
COUNTROWS (
    FILTER (
        VALUES ( 'analytics accounts'[customer_id] ),
        CALCULATE ( COUNT ( 'analytics accounts'[account_id] ) ) > 1
    )
)
```

### Transaction and Merchant Performance

```dax
Transaction Volume = DISTINCTCOUNT ( 'analytics transactions'[transaction_id] )
```

```dax
Average Transaction Value = AVERAGE ( 'analytics transactions'[amount_usd] )
```

```dax
Highest Transaction Value = MAX ( 'analytics transactions'[amount_usd] )
```

```dax
Active Transaction Accounts = DISTINCTCOUNT ( 'analytics transactions'[account_id] )
```

```dax
Unique Merchants = DISTINCTCOUNT ( 'analytics transactions'[merchant_id] )
```

```dax
-- Used with Accounts Held on the axis
Transaction Value per Customer =
DIVIDE ( [Total Transaction Value], [Total Customers] )
```

### Data Quality and Business Risk

`REMOVEFILTERS ()` keeps the match rates the same whatever slicers are selected elsewhere in the report.

```dax
DQ Account Match % =
DIVIDE (
    CALCULATE (
        COUNTROWS ( 'analytics transactions' ),
        REMOVEFILTERS (),
        'analytics transactions'[account_match_status] = "Matched"
    ),
    CALCULATE ( COUNTROWS ( 'analytics transactions' ), REMOVEFILTERS () )
)
```

```dax
DQ Merchant Match % =
DIVIDE (
    CALCULATE (
        COUNTROWS ( 'analytics transactions' ),
        REMOVEFILTERS (),
        'analytics transactions'[merchant_match_status] = "Matched"
    ),
    CALCULATE ( COUNTROWS ( 'analytics transactions' ), REMOVEFILTERS () )
)
```

```dax
-- Emails used by more than one customer
Duplicate Email Groups =
COUNTROWS (
    FILTER (
        VALUES ( 'analytics customers'[email] ),
        CALCULATE ( COUNTROWS ( 'analytics customers' ) ) > 1
    )
)
```

```dax
Account Date Exceptions =
COUNTROWS (
    FILTER (
        'analytics accounts',
        'analytics accounts'[open_date]
            < LOOKUPVALUE (
                'analytics customers'[created_at],
                'analytics customers'[customer_id], 'analytics accounts'[customer_id]
            )
    )
)
```

```dax
Loan Date Exceptions =
COUNTROWS (
    FILTER (
        'analytics loans',
        'analytics loans'[start_date]
            < LOOKUPVALUE (
                'analytics customers'[created_at],
                'analytics customers'[customer_id], 'analytics loans'[customer_id]
            )
    )
)
```

```dax
Card Date Exceptions =
COUNTROWS (
    FILTER (
        'analytics cards',
        'analytics cards'[expiration_date]
            < LOOKUPVALUE (
                'analytics accounts'[open_date],
                'analytics accounts'[account_id], 'analytics cards'[account_id]
            )
    )
)
```

```dax
-- Failure rate for the date-order chart, one bar per table
Data Quality Exception % =
SWITCH (
    SELECTEDVALUE ( 'Data Quality Exceptions'[Entity] ),
    "Accounts", DIVIDE ( [Account Date Exceptions], COUNTROWS ( 'analytics accounts' ) ),
    "Loans", DIVIDE ( [Loan Date Exceptions], COUNTROWS ( 'analytics loans' ) ),
    "Cards", DIVIDE ( [Card Date Exceptions], COUNTROWS ( 'analytics cards' ) )
)
```

## Calculated tables

```dax
-- One row per distinct email, marked Unique or Shared
Customer Email Quality =
VAR Emails =
    DISTINCT (
        SELECTCOLUMNS (
            FILTER ( 'analytics customers', NOT ISBLANK ( 'analytics customers'[email] ) ),
            "Email", 'analytics customers'[email]
        )
    )
RETURN
    ADDCOLUMNS (
        Emails,
        "EmailCount",
            VAR CurrentEmail = [Email]
            RETURN CALCULATE ( COUNTROWS ( 'analytics customers' ), 'analytics customers'[email] = CurrentEmail ),
        "EmailStatus",
            VAR CurrentEmail = [Email]
            VAR EmailCount =
                CALCULATE ( COUNTROWS ( 'analytics customers' ), 'analytics customers'[email] = CurrentEmail )
            RETURN IF ( EmailCount = 1, "Unique", "Shared" )
    )
```

```dax
Data Quality Exceptions =
DATATABLE ( "Entity", STRING, { { "Accounts" }, { "Loans" }, { "Cards" } } )
```

```dax
Business Impact =
DATATABLE (
    "Issue", STRING,
    "Business Impact", STRING,
    "Recommended Action", STRING,
    {
        { "Transaction Account Mismatch",
          "Resolved. The first load matched 11.19% because the transactions file came from a different dataset version",
          "Foreign keys now stop a mismatched file at load" },
        { "Merchant Mapping Failure",
          "Resolved. The first load matched 0% for the same reason",
          "Foreign keys now stop a mismatched file at load" },
        { "Duplicate Customer Emails",
          "7,600 customers share an email but none share a name, so they are different people",
          "Use customer_id as the customer key. Do not merge on email" },
        { "Account Date Exceptions",
          "49.9% of accounts predate the customer record, so the two dates are unrelated",
          "Do not report customer tenure or account age" },
        { "Loan Date Exceptions",
          "50.2% of loans predate the customer record, so the two dates are unrelated",
          "Do not report time to first loan" },
        { "Card Date Exceptions",
          "923 cards (0.9%) expire before their account opened",
          "Review these cards against the card system" }
    }
)
```

## Expected values

With no slicer selected, the report matches the SQL layer:

| Measure | Value |
|---|---:|
| Total Customers | 50,000 |
| Total Bank Balance | 7,513,629,141.07 |
| Average Account Balance | 100,181.72 |
| Avg Accounts per Customer | 1.50 |
| Customers Multiple Accounts | 22,221 |
| Expired Cards | 12,665 |
| Total Loan Exposure | 4,502,670,498.10 |
| Total Transactions | 1,000,000 |
| Total Transaction Value | 5,000,821,759.71 |
| Average Transaction Value | 5,000.82 |
| Highest Transaction Value | 9,999.98 |
| Active Transaction Accounts | 75,000 |
| Unique Merchants | 5,000 |
| DQ Account Match % | 100% |
| DQ Merchant Match % | 100% |
| Duplicate Email Groups | 3,373 |
| Account Date Exceptions | 37,408 |
| Loan Date Exceptions | 15,069 |
| Card Date Exceptions | 923 |
