/* =====================================================================
   PayFlow Analytics (MySQL 8 version)
   05_business_analysis.sql

   Business questions answered from the analytics layer.

     Section 1  Portfolio KPIs
     Section 2  Customers
     Section 3  Accounts and relationship depth
     Section 4  Cards
     Section 5  Loans
     Section 6  Transactions and merchants
     Section 7  Customer 360
     Section 8  Additional analysis

   Conventions used throughout
     Credit category   Low < 580, Medium 580-669, Good 670-739, Excellent 740+
     Loan size         Small <= 100K, Medium <= 200K, Large > 200K
     (the same bands are used in the Power BI model)
   ===================================================================== */

/* =====================================================================
   SECTION 1: PORTFOLIO KPIs
   ===================================================================== */

-- Q1. Headline numbers for the executive page.
SELECT
    (SELECT COUNT(*)                                   FROM payflow_analytics.customers)    AS total_customers,
    (SELECT COUNT(*)                                   FROM payflow_analytics.accounts)     AS total_accounts,
    (SELECT SUM(balance_usd)                           FROM payflow_analytics.accounts)     AS total_balance_usd,
    (SELECT CAST(AVG(balance_usd) AS DECIMAL(12, 2))   FROM payflow_analytics.accounts)     AS avg_account_balance_usd,
    (SELECT COUNT(*)                                   FROM payflow_analytics.loans)        AS total_loans,
    (SELECT SUM(loan_amount)                           FROM payflow_analytics.loans)        AS total_loan_exposure_usd,
    (SELECT COUNT(*)                                   FROM payflow_analytics.cards)        AS total_cards,
    (SELECT COUNT(*) FROM payflow_analytics.cards WHERE card_status = 'Expired')            AS expired_cards,
    (SELECT COUNT(*)                                   FROM payflow_analytics.transactions) AS total_transactions,
    (SELECT SUM(amount_usd)                            FROM payflow_analytics.transactions) AS total_transaction_value_usd,
    (SELECT CAST(AVG(amount_usd) AS DECIMAL(12, 2))    FROM payflow_analytics.transactions) AS avg_transaction_usd;

/* =====================================================================
   SECTION 2: CUSTOMERS
   ===================================================================== */

-- Q2. Credit score summary.
--     The cast keeps two decimals. (SQL Server would round AVG of an INT
--     column to a whole number; MySQL does not, but the cast is harmless.)
SELECT
    MIN(credit_score)                                              AS min_credit_score,
    MAX(credit_score)                                              AS max_credit_score,
    CAST(AVG(CAST(credit_score AS DECIMAL(10, 2))) AS DECIMAL(10, 2)) AS avg_credit_score
FROM payflow_analytics.customers;

-- Q3. How are customers spread across credit categories?
SELECT
    credit_category,
    COUNT(*)                                                       AS customers,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5, 2)) AS pct_of_customers
FROM payflow_analytics.vw_customer_summary
GROUP BY credit_category, credit_category_sort
ORDER BY credit_category_sort;

-- Q4. Customers acquired per year, with the change on the previous year.
WITH yearly AS (
    SELECT YEAR(created_at) AS acquisition_year,
           COUNT(*)         AS new_customers
    FROM payflow_analytics.customers
    GROUP BY YEAR(created_at)
)
SELECT
    acquisition_year,
    new_customers,
    new_customers - LAG(new_customers) OVER (ORDER BY acquisition_year) AS change_vs_prior_year,
    CAST(100.0 * (new_customers - LAG(new_customers) OVER (ORDER BY acquisition_year))
         / LAG(new_customers) OVER (ORDER BY acquisition_year) AS DECIMAL(6, 2)) AS pct_change
FROM yearly
ORDER BY acquisition_year;

-- Q5. Is city a useful dimension? How many cities, and how many
--     customers does a typical city have?
WITH city_counts AS (
    SELECT city, COUNT(*) AS customers
    FROM payflow_analytics.customers
    GROUP BY city
)
SELECT
    COUNT(*)                                             AS distinct_cities,
    MAX(customers)                                       AS customers_in_largest_city,
    CAST(AVG(CAST(customers AS DECIMAL(10, 2))) AS DECIMAL(10, 2)) AS avg_customers_per_city,
    SUM(CASE WHEN customers = 1 THEN 1 ELSE 0 END)       AS cities_with_one_customer
FROM city_counts;

/* =====================================================================
   SECTION 3: ACCOUNTS AND RELATIONSHIP DEPTH
   ===================================================================== */

-- Q6. Balance by account type, with each type's share of the total.
SELECT
    account_type,
    COUNT(*)                                                                  AS accounts,
    SUM(balance_usd)                                                          AS total_balance_usd,
    CAST(AVG(balance_usd) AS DECIMAL(12, 2))                                  AS avg_balance_usd,
    CAST(100.0 * SUM(balance_usd) / SUM(SUM(balance_usd)) OVER () AS DECIMAL(5, 2)) AS pct_of_balance
FROM payflow_analytics.accounts
GROUP BY account_type
ORDER BY total_balance_usd DESC;

-- Q7. How many accounts does each customer hold? Customers with no
--     account are included (they would be lost if this started from
--     the accounts table).
SELECT
    account_count,
    COUNT(*)                                                       AS customers,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5, 2)) AS pct_of_customers
FROM payflow_analytics.vw_customer_summary
GROUP BY account_count
ORDER BY account_count;

-- Q8. Top 10 customers by total balance. RANK keeps ties together.
WITH ranked AS (
    SELECT
        customer_id, first_name, last_name, account_count, total_balance,
        RANK() OVER (ORDER BY total_balance DESC) AS balance_rank
    FROM payflow_analytics.vw_customer_summary
)
SELECT balance_rank, customer_id, first_name, last_name, account_count, total_balance
FROM ranked
WHERE balance_rank <= 10
ORDER BY balance_rank, customer_id;

-- Q9. Top 3 customers by balance within each account type.
WITH by_type AS (
    SELECT
        account_type,
        customer_id,
        SUM(balance_usd) AS total_balance,
        ROW_NUMBER() OVER (PARTITION BY account_type
                           ORDER BY SUM(balance_usd) DESC, customer_id) AS row_num
    FROM payflow_analytics.accounts
    GROUP BY account_type, customer_id
)
SELECT account_type, row_num AS rank_in_type, customer_id, total_balance
FROM by_type
WHERE row_num <= 3
ORDER BY account_type, row_num;

-- Q10. How concentrated are deposits? Split account-holding customers
--      into ten equal groups by balance and show each group's share.
WITH holders AS (
    SELECT
        customer_id,
        total_balance,
        NTILE(10) OVER (ORDER BY total_balance DESC, customer_id) AS balance_decile
    FROM payflow_analytics.vw_customer_summary
    WHERE account_count > 0
)
SELECT
    balance_decile,
    COUNT(*)                                                                    AS customers,
    SUM(total_balance)                                                          AS total_balance_usd,
    CAST(100.0 * SUM(total_balance) / SUM(SUM(total_balance)) OVER () AS DECIMAL(5, 2)) AS pct_of_balance
FROM holders
GROUP BY balance_decile
ORDER BY balance_decile;

/* =====================================================================
   SECTION 4: CARDS
   ===================================================================== */

-- Q11. Card status as of the reporting date, by card type.
SELECT
    card_type,
    COUNT(*)                                                                    AS cards,
    SUM(CASE WHEN card_status = 'Expired' THEN 1 ELSE 0 END)                    AS expired_cards,
    CAST(100.0 * SUM(CASE WHEN card_status = 'Expired' THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5, 2))                                           AS pct_expired
FROM payflow_analytics.cards
GROUP BY card_type
ORDER BY card_type;

-- Q12. Renewal pipeline: cards expiring each year and the running total.
WITH by_year AS (
    SELECT YEAR(expiration_date) AS expiry_year,
           COUNT(*)              AS cards_expiring
    FROM payflow_analytics.cards
    GROUP BY YEAR(expiration_date)
)
SELECT
    expiry_year,
    cards_expiring,
    SUM(cards_expiring) OVER (ORDER BY expiry_year
                              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_cards
FROM by_year
ORDER BY expiry_year;

-- Q13. How many accounts have no card at all?
SELECT
    COUNT(*)                                                         AS accounts,
    SUM(CASE WHEN k.account_id IS NULL THEN 1 ELSE 0 END)            AS accounts_without_card,
    CAST(100.0 * SUM(CASE WHEN k.account_id IS NULL THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5, 2))                                AS pct_without_card
FROM payflow_analytics.accounts AS a
LEFT JOIN (SELECT DISTINCT account_id FROM payflow_analytics.cards) AS k
       ON k.account_id = a.account_id;

/* =====================================================================
   SECTION 5: LOANS
   ===================================================================== */

-- Q14. Loan book summary.
SELECT
    COUNT(*)                                     AS total_loans,
    COUNT(DISTINCT customer_id)                  AS borrowers,
    SUM(loan_amount)                             AS total_loan_exposure_usd,
    CAST(AVG(loan_amount) AS DECIMAL(12, 2))     AS avg_loan_usd,
    MIN(loan_amount)                             AS min_loan_usd,
    MAX(loan_amount)                             AS max_loan_usd,
    CAST(AVG(interest_rate) AS DECIMAL(5, 2))    AS avg_interest_rate
FROM payflow_analytics.loans;

-- Q15. Loans by size band.
WITH banded AS (
    SELECT
        loan_amount,
        CASE WHEN loan_amount <= 100000 THEN 'Small'
             WHEN loan_amount <= 200000 THEN 'Medium'
             ELSE 'Large' END AS loan_size,
        CASE WHEN loan_amount <= 100000 THEN 1
             WHEN loan_amount <= 200000 THEN 2
             ELSE 3 END       AS loan_size_sort
    FROM payflow_analytics.loans
)
SELECT
    loan_size,
    COUNT(*)                                                                    AS loans,
    SUM(loan_amount)                                                            AS total_loan_usd,
    CAST(100.0 * SUM(loan_amount) / SUM(SUM(loan_amount)) OVER () AS DECIMAL(5, 2)) AS pct_of_exposure
FROM banded
GROUP BY loan_size, loan_size_sort
ORDER BY loan_size_sort;

-- Q16. New lending per year, with the change on the previous year.
WITH yearly AS (
    SELECT YEAR(start_date) AS loan_year,
           COUNT(*)         AS loans,
           SUM(loan_amount) AS loan_amount_usd
    FROM payflow_analytics.loans
    GROUP BY YEAR(start_date)
)
SELECT
    loan_year,
    loans,
    loan_amount_usd,
    CAST(100.0 * (loan_amount_usd - LAG(loan_amount_usd) OVER (ORDER BY loan_year))
         / LAG(loan_amount_usd) OVER (ORDER BY loan_year) AS DECIMAL(6, 2)) AS pct_change
FROM yearly
ORDER BY loan_year;

-- Q17. Is lending priced for risk? If it were, the average interest
--      rate would fall as the credit category improves.
SELECT
    s.credit_category,
    COUNT(*)                                     AS loans,
    CAST(AVG(l.loan_amount) AS DECIMAL(12, 2))   AS avg_loan_usd,
    CAST(AVG(l.interest_rate) AS DECIMAL(5, 2))  AS avg_interest_rate,
    SUM(l.loan_amount)                           AS total_loan_usd
FROM payflow_analytics.loans AS l
JOIN payflow_analytics.vw_customer_summary AS s
  ON s.customer_id = l.customer_id
GROUP BY s.credit_category, s.credit_category_sort
ORDER BY s.credit_category_sort;

-- Q18. Higher-risk exposure: Low-credit customers holding Large loans.
SELECT
    COUNT(DISTINCT l.customer_id)   AS customers,
    COUNT(*)                        AS loans,
    SUM(l.loan_amount)              AS exposure_usd,
    CAST(100.0 * SUM(l.loan_amount)
         / (SELECT SUM(loan_amount) FROM payflow_analytics.loans) AS DECIMAL(5, 2)) AS pct_of_loan_book
FROM payflow_analytics.loans AS l
WHERE l.credit_score < 580
  AND l.loan_amount > 200000;

/* =====================================================================
   SECTION 6: TRANSACTIONS AND MERCHANTS
   ===================================================================== */

-- Q19. Transaction summary.
SELECT
    COUNT(*)                                   AS total_transactions,
    SUM(amount_usd)                            AS total_value_usd,
    CAST(AVG(amount_usd) AS DECIMAL(12, 2))    AS avg_transaction_usd,
    MIN(amount_usd)                            AS min_transaction_usd,
    MAX(amount_usd)                            AS max_transaction_usd,
    COUNT(DISTINCT account_id)                 AS active_accounts,
    COUNT(DISTINCT merchant_id)                AS active_merchants
FROM payflow_analytics.transactions;

-- Q20. Volume and value per year, with the change on the previous year.
WITH yearly AS (
    SELECT YEAR(transaction_date) AS transaction_year,
           COUNT(*)               AS transactions,
           SUM(amount_usd)        AS value_usd
    FROM payflow_analytics.transactions
    GROUP BY YEAR(transaction_date)
)
SELECT
    transaction_year,
    transactions,
    value_usd,
    CAST(100.0 * (transactions - LAG(transactions) OVER (ORDER BY transaction_year))
         / LAG(transactions) OVER (ORDER BY transaction_year) AS DECIMAL(6, 2)) AS pct_change_volume,
    CAST(100.0 * (value_usd - LAG(value_usd) OVER (ORDER BY transaction_year))
         / LAG(value_usd) OVER (ORDER BY transaction_year) AS DECIMAL(6, 2))    AS pct_change_value
FROM yearly
ORDER BY transaction_year;

-- Q21. Monthly value with a 3-month moving average.
WITH monthly AS (
    SELECT
        CAST(DATE_FORMAT(transaction_date, '%Y-%m-01') AS DATE) AS month_start,
        COUNT(*)        AS transactions,
        SUM(amount_usd) AS value_usd
    FROM payflow_analytics.transactions
    GROUP BY CAST(DATE_FORMAT(transaction_date, '%Y-%m-01') AS DATE)
)
SELECT
    month_start,
    transactions,
    value_usd,
    CAST(AVG(value_usd) OVER (ORDER BY month_start
                              ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS DECIMAL(14, 2)) AS value_3_month_avg
FROM monthly
ORDER BY month_start;

-- Q22. Top 10 merchants by transaction value, with names.
WITH merchant_totals AS (
    SELECT
        t.merchant_id,
        COUNT(*)          AS transactions,
        SUM(t.amount_usd) AS value_usd
    FROM payflow_analytics.transactions AS t
    GROUP BY t.merchant_id
),
ranked AS (
    SELECT
        merchant_id, transactions, value_usd,
        RANK() OVER (ORDER BY value_usd DESC)        AS value_rank,
        SUM(value_usd) OVER ()                       AS all_value_usd
    FROM merchant_totals
)
SELECT
    r.value_rank,
    r.merchant_id,
    m.merchant_name,
    m.city,
    r.transactions,
    r.value_usd,
    CAST(100.0 * r.value_usd / r.all_value_usd AS DECIMAL(6, 3)) AS pct_of_value
FROM ranked AS r
JOIN payflow_analytics.merchants AS m
  ON m.merchant_id = r.merchant_id
WHERE r.value_rank <= 10
ORDER BY r.value_rank, r.merchant_id;

-- Q23. Is transaction value concentrated in a few merchants? Compare
--      the top 10's share with the share they would hold if every
--      merchant were the same size.
WITH merchant_totals AS (
    SELECT merchant_id, SUM(amount_usd) AS value_usd
    FROM payflow_analytics.transactions
    GROUP BY merchant_id
),
ranked AS (
    SELECT value_usd,
           ROW_NUMBER() OVER (ORDER BY value_usd DESC, merchant_id) AS value_position
    FROM merchant_totals
)
SELECT
    COUNT(*)                                                                    AS merchants,
    CAST(100.0 * SUM(CASE WHEN value_position <= 10 THEN value_usd ELSE 0 END)
         / SUM(value_usd) AS DECIMAL(6, 3))                                     AS top_10_pct_of_value,
    CAST(100.0 * 10 / COUNT(*) AS DECIMAL(6, 3))                                AS pct_if_all_equal
FROM ranked;

-- Q24. Transactions by amount band.
WITH banded AS (
    SELECT
        amount_usd,
        CASE WHEN amount_usd < 2500 THEN '1. Under 2,500'
             WHEN amount_usd < 5000 THEN '2. 2,500 to 4,999'
             WHEN amount_usd < 7500 THEN '3. 5,000 to 7,499'
             ELSE '4. 7,500 and over' END AS amount_band
    FROM payflow_analytics.transactions
)
SELECT
    amount_band,
    COUNT(*)                                                         AS transactions,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5, 2))   AS pct_of_transactions,
    SUM(amount_usd)                                                  AS value_usd
FROM banded
GROUP BY amount_band
ORDER BY amount_band;

-- Q25. Top 10 accounts by transaction value, with the owner.
WITH account_totals AS (
    SELECT account_id,
           COUNT(*)        AS transactions,
           SUM(amount_usd) AS value_usd
    FROM payflow_analytics.transactions
    GROUP BY account_id
),
ranked AS (
    SELECT account_id, transactions, value_usd,
           RANK() OVER (ORDER BY value_usd DESC) AS value_rank
    FROM account_totals
)
SELECT
    r.value_rank, r.account_id, a.account_type, a.customer_id,
    a.first_name, a.last_name, r.transactions, r.value_usd
FROM ranked AS r
JOIN payflow_analytics.accounts AS a
  ON a.account_id = r.account_id
WHERE r.value_rank <= 10
ORDER BY r.value_rank, r.account_id;

/* =====================================================================
   SECTION 7: CUSTOMER 360
   ===================================================================== */

-- Q26. Which products does each customer hold?
WITH holdings AS (
    SELECT
        CASE
            WHEN account_count > 0 AND loan_count > 0 THEN '1. Deposit account and loan'
            WHEN account_count > 0                    THEN '2. Deposit account only'
            WHEN loan_count > 0                       THEN '3. Loan only'
            ELSE '4. No product'
        END AS product_holding
    FROM payflow_analytics.vw_customer_summary
)
SELECT
    product_holding,
    COUNT(*)                                                       AS customers,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5, 2)) AS pct_of_customers
FROM holdings
GROUP BY product_holding
ORDER BY product_holding;

-- Q27. Top 10 customers by total transaction value.
WITH ranked AS (
    SELECT
        customer_id, first_name, last_name, credit_category,
        account_count, transaction_count, total_spent,
        RANK() OVER (ORDER BY total_spent DESC) AS spend_rank
    FROM payflow_analytics.vw_customer_summary
)
SELECT spend_rank, customer_id, first_name, last_name, credit_category,
       account_count, transaction_count, total_spent
FROM ranked
WHERE spend_rank <= 10
ORDER BY spend_rank, customer_id;

-- Q28. Balances, borrowing and spending by credit category.
SELECT
    credit_category,
    COUNT(*)                                                         AS customers,
    CAST(AVG(total_balance) AS DECIMAL(14, 2))                       AS avg_balance_per_customer,
    CAST(AVG(total_loan_amount) AS DECIMAL(14, 2))                   AS avg_loans_per_customer,
    CAST(AVG(total_spent) AS DECIMAL(14, 2))                         AS avg_spend_per_customer,
    CAST(100.0 * SUM(total_spent) / SUM(SUM(total_spent)) OVER () AS DECIMAL(5, 2)) AS pct_of_spend
FROM payflow_analytics.vw_customer_summary
GROUP BY credit_category, credit_category_sort
ORDER BY credit_category_sort;

-- Q29. Does spending rise with the number of accounts held?
SELECT
    account_count,
    COUNT(*)                                             AS customers,
    CAST(AVG(CAST(transaction_count AS DECIMAL(12, 2))) AS DECIMAL(12, 2)) AS avg_transactions_per_customer,
    CAST(AVG(total_spent) AS DECIMAL(14, 2))             AS avg_spend_per_customer
FROM payflow_analytics.vw_customer_summary
WHERE account_count > 0
GROUP BY account_count
ORDER BY account_count;

-- Q30. Customers whose balance is above the average customer balance.
WITH holders AS (
    SELECT customer_id, total_balance,
           AVG(total_balance) OVER () AS avg_customer_balance
    FROM payflow_analytics.vw_customer_summary
    WHERE account_count > 0
)
SELECT
    COUNT(*)                                                           AS account_holders,
    CAST(MAX(avg_customer_balance) AS DECIMAL(14, 2))                  AS avg_customer_balance,
    SUM(CASE WHEN total_balance > avg_customer_balance THEN 1 ELSE 0 END) AS customers_above_average,
    CAST(100.0 * SUM(CASE WHEN total_balance > avg_customer_balance THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5, 2))                                  AS pct_above_average
FROM holders;

/* =====================================================================
   SECTION 8: ADDITIONAL ANALYSIS
   ===================================================================== */

-- Q31. How many transactions does each account make?
--      (Accounts by Number of Transactions chart)
WITH per_account AS (
    SELECT a.account_id,
           COUNT(t.transaction_id) AS transactions
    FROM payflow_analytics.accounts AS a
    LEFT JOIN payflow_analytics.transactions AS t
           ON t.account_id = a.account_id
    GROUP BY a.account_id
)
SELECT
    transactions                                                    AS transactions_per_account,
    COUNT(*)                                                        AS accounts,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5, 2))  AS pct_of_accounts
FROM per_account
GROUP BY transactions
ORDER BY transactions;

-- Q32. The 10 largest individual transactions, with owner and merchant.
SELECT
    t.transaction_id,
    t.transaction_date,
    t.amount_usd,
    a.customer_id,
    a.first_name,
    a.last_name,
    a.account_type,
    m.merchant_name
FROM payflow_analytics.transactions AS t
JOIN payflow_analytics.accounts  AS a ON a.account_id  = t.account_id
JOIN payflow_analytics.merchants AS m ON m.merchant_id = t.merchant_id
ORDER BY t.amount_usd DESC, t.transaction_id
LIMIT 10;

-- Q33. Customers with both balances and loans above $100,000:
--      how many, and the 10 largest by combined size.
WITH both_high AS (
    SELECT
        customer_id, first_name, last_name, credit_category,
        total_balance, total_loan_amount,
        total_balance + total_loan_amount AS combined_usd,
        COUNT(*) OVER ()                  AS customers_meeting_both
    FROM payflow_analytics.vw_customer_summary
    WHERE total_balance > 100000
      AND total_loan_amount > 100000
),
ranked AS (
    SELECT customer_id, first_name, last_name, credit_category,
           total_balance, total_loan_amount, combined_usd, customers_meeting_both,
           ROW_NUMBER() OVER (ORDER BY combined_usd DESC, customer_id) AS top_position
    FROM both_high
)
SELECT top_position, customers_meeting_both, customer_id, first_name, last_name,
       credit_category, total_balance, total_loan_amount, combined_usd
FROM ranked
WHERE top_position <= 10
ORDER BY top_position;

-- Q34. Accounts holding the most cards. RANK keeps ties, so more than
--      10 rows can return when several accounts share a card count.
WITH card_counts AS (
    SELECT k.account_id,
           COUNT(*) AS cards
    FROM payflow_analytics.cards AS k
    GROUP BY k.account_id
),
ranked AS (
    SELECT account_id, cards,
           RANK() OVER (ORDER BY cards DESC) AS card_rank
    FROM card_counts
)
SELECT r.card_rank, r.account_id, a.account_type, a.customer_id,
       a.first_name, a.last_name, r.cards
FROM ranked AS r
JOIN payflow_analytics.accounts AS a
  ON a.account_id = r.account_id
WHERE r.card_rank <= 10
ORDER BY r.card_rank, r.account_id;

-- Q35. Each customer's share of all spending, with the running total
--      share, for the 10 biggest spenders.
WITH shares AS (
    SELECT
        customer_id, first_name, last_name, total_spent,
        100.0 * total_spent / SUM(total_spent) OVER () AS pct_of_spend,
        ROW_NUMBER() OVER (ORDER BY total_spent DESC, customer_id) AS spend_position
    FROM payflow_analytics.vw_customer_summary
)
SELECT
    spend_position,
    customer_id,
    first_name,
    last_name,
    total_spent,
    CAST(pct_of_spend AS DECIMAL(8, 4))                                   AS pct_of_spend,
    CAST(SUM(pct_of_spend) OVER (ORDER BY spend_position
                                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
         AS DECIMAL(8, 4))                                                AS cumulative_pct
FROM shares
WHERE spend_position <= 10
ORDER BY spend_position;
