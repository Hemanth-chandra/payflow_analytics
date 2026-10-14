/* =====================================================================
   PayFlow Analytics
   04_build_analytics_layer.sql

   Publishes staging data to the analytics tables that Power BI reads,
   and adds the derived reporting columns:

     accounts.first_name / last_name / city   copied from customers
     accounts.account_date_valid              1 = opened on/after customer created
     loans.first_name / last_name / city / credit_score
     loans.loan_date_valid                    1 = started on/after customer created
     cards.card_status                        Expired / Active as of the reporting date
     transactions.account_match_status        Matched / Unmatched
     transactions.merchant_match_status       Matched / Unmatched

   The reporting date is the last transaction date in the data, so
   "expired" means expired at the end of the reporting period, not
   relative to the day the script happens to be run.

   Run the first batch as a whole. Safe to re-run.
   ===================================================================== */

USE PayFlowAnalytics;
GO

SET NOCOUNT ON;

/* --- gate: do not publish data that failed a Critical check ----------- */
IF NOT EXISTS (SELECT 1 FROM analytics.data_quality_results)
BEGIN
    THROW 50001, 'No data-quality results found. Run 03_data_quality_checks.sql first.', 1;
END;

IF EXISTS (SELECT 1 FROM analytics.data_quality_results WHERE status = 'FAIL')
BEGIN
    THROW 50002, 'Critical data-quality checks failed. Review analytics.data_quality_results and fix the source files first.', 1;
END;

DECLARE @AsOfDate DATE = (SELECT CAST(MAX(transaction_date) AS DATE) FROM staging.transactions);

/* --- empty the reporting tables, children first ----------------------- */
TRUNCATE TABLE analytics.transactions;
TRUNCATE TABLE analytics.cards;
TRUNCATE TABLE analytics.loans;
DELETE FROM analytics.accounts;
DELETE FROM analytics.merchants;
DELETE FROM analytics.customers;

/* --- parents ---------------------------------------------------------- */
INSERT INTO analytics.customers
    (customer_id, first_name, last_name, email, city, credit_score, created_at)
SELECT customer_id, first_name, last_name, email, city, credit_score, created_at
FROM staging.customers;

INSERT INTO analytics.merchants
    (merchant_id, merchant_name, city)
SELECT merchant_id, merchant_name, city
FROM staging.merchants;

/* --- accounts --------------------------------------------------------- */
INSERT INTO analytics.accounts
    (account_id, customer_id, first_name, last_name, city,
     account_type, balance_usd, open_date, account_date_valid)
SELECT
    a.account_id,
    a.customer_id,
    c.first_name,
    c.last_name,
    c.city,
    a.account_type,
    a.balance_usd,
    a.open_date,
    CASE WHEN a.open_date >= c.created_at THEN 1 ELSE 0 END
FROM staging.accounts AS a
JOIN staging.customers AS c
  ON c.customer_id = a.customer_id;

/* --- loans ------------------------------------------------------------ */
INSERT INTO analytics.loans
    (loan_id, customer_id, first_name, last_name, city, credit_score,
     loan_amount, interest_rate, start_date, loan_date_valid)
SELECT
    l.loan_id,
    l.customer_id,
    c.first_name,
    c.last_name,
    c.city,
    c.credit_score,
    l.loan_amount,
    l.interest_rate,
    l.start_date,
    CASE WHEN l.start_date >= c.created_at THEN 1 ELSE 0 END
FROM staging.loans AS l
JOIN staging.customers AS c
  ON c.customer_id = l.customer_id;

/* --- cards ------------------------------------------------------------ */
INSERT INTO analytics.cards
    (card_id, account_id, card_type, expiration_date, card_status)
SELECT
    k.card_id,
    k.account_id,
    k.card_type,
    k.expiration_date,
    CASE WHEN k.expiration_date <= @AsOfDate THEN 'Expired' ELSE 'Active' END
FROM staging.cards AS k;

/* --- transactions ----------------------------------------------------- */
INSERT INTO analytics.transactions
    (transaction_id, account_id, merchant_id, amount_usd, transaction_date,
     account_match_status, merchant_match_status)
SELECT
    t.transaction_id,
    t.account_id,
    t.merchant_id,
    t.amount_usd,
    t.transaction_date,
    CASE WHEN a.account_id  IS NULL THEN 'Unmatched' ELSE 'Matched' END,
    CASE WHEN m.merchant_id IS NULL THEN 'Unmatched' ELSE 'Matched' END
FROM staging.transactions AS t
LEFT JOIN staging.accounts  AS a ON a.account_id  = t.account_id
LEFT JOIN staging.merchants AS m ON m.merchant_id = t.merchant_id;

/* --- what was published ----------------------------------------------- */
SELECT @AsOfDate AS reporting_date;

SELECT 'customers' AS table_name, COUNT(*) AS rows_published FROM analytics.customers
UNION ALL SELECT 'accounts',     COUNT(*) FROM analytics.accounts
UNION ALL SELECT 'cards',        COUNT(*) FROM analytics.cards
UNION ALL SELECT 'loans',        COUNT(*) FROM analytics.loans
UNION ALL SELECT 'merchants',    COUNT(*) FROM analytics.merchants
UNION ALL SELECT 'transactions', COUNT(*) FROM analytics.transactions;

SELECT account_match_status, merchant_match_status, COUNT(*) AS transactions
FROM analytics.transactions
GROUP BY account_match_status, merchant_match_status;

SELECT card_status, COUNT(*) AS cards
FROM analytics.cards
GROUP BY card_status;
GO

/* =====================================================================
   analytics.vw_customer_summary
   One row per customer with everything they hold and do. Each fact is
   aggregated on its own first, so joining them cannot multiply rows.
   ===================================================================== */
CREATE OR ALTER VIEW analytics.vw_customer_summary
AS
WITH account_summary AS (
    SELECT customer_id,
           COUNT(*)         AS account_count,
           SUM(balance_usd) AS total_balance
    FROM analytics.accounts
    GROUP BY customer_id
),
loan_summary AS (
    SELECT customer_id,
           COUNT(*)           AS loan_count,
           SUM(loan_amount)   AS total_loan_amount,
           AVG(interest_rate) AS avg_interest_rate
    FROM analytics.loans
    GROUP BY customer_id
),
card_summary AS (
    SELECT a.customer_id,
           COUNT(*) AS card_count
    FROM analytics.cards AS k
    JOIN analytics.accounts AS a
      ON a.account_id = k.account_id
    GROUP BY a.customer_id
),
transaction_summary AS (
    SELECT a.customer_id,
           COUNT(*)          AS transaction_count,
           SUM(t.amount_usd) AS total_spent
    FROM analytics.transactions AS t
    JOIN analytics.accounts AS a
      ON a.account_id = t.account_id
    GROUP BY a.customer_id
)
SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    c.city,
    c.created_at,
    c.credit_score,
    CASE
        WHEN c.credit_score < 580 THEN 'Low'
        WHEN c.credit_score < 670 THEN 'Medium'
        WHEN c.credit_score < 740 THEN 'Good'
        ELSE 'Excellent'
    END                                  AS credit_category,
    CASE
        WHEN c.credit_score < 580 THEN 1
        WHEN c.credit_score < 670 THEN 2
        WHEN c.credit_score < 740 THEN 3
        ELSE 4
    END                                  AS credit_category_sort,
    COALESCE(a.account_count, 0)         AS account_count,
    COALESCE(a.total_balance, 0)         AS total_balance,
    COALESCE(l.loan_count, 0)            AS loan_count,
    COALESCE(l.total_loan_amount, 0)     AS total_loan_amount,
    l.avg_interest_rate,
    COALESCE(k.card_count, 0)            AS card_count,
    COALESCE(t.transaction_count, 0)     AS transaction_count,
    COALESCE(t.total_spent, 0)           AS total_spent
FROM analytics.customers AS c
LEFT JOIN account_summary     AS a ON a.customer_id = c.customer_id
LEFT JOIN loan_summary        AS l ON l.customer_id = c.customer_id
LEFT JOIN card_summary        AS k ON k.customer_id = c.customer_id
LEFT JOIN transaction_summary AS t ON t.customer_id = c.customer_id;
GO
