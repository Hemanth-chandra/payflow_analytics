/* =====================================================================
   PayFlow Analytics (MySQL 8 version)
   04_build_analytics_layer.sql

   Publishes staging data to the analytics tables and adds the derived
   reporting columns:

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

   MySQL can only stop a script with an error from inside a stored
   procedure, so the build is a procedure: it refuses to run while any
   Critical data-quality check has status FAIL.

   Run the whole script. Safe to re-run.
   ===================================================================== */

DROP PROCEDURE IF EXISTS payflow_analytics.build_analytics_layer;

DELIMITER $$

CREATE PROCEDURE payflow_analytics.build_analytics_layer()
BEGIN
    DECLARE as_of_date DATE;

    /* --- gate: do not publish data that failed a Critical check ------- */
    IF (SELECT COUNT(*) FROM payflow_analytics.data_quality_results) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No data-quality results found. Run 03_data_quality_checks.sql first.';
    END IF;

    IF EXISTS (SELECT 1 FROM payflow_analytics.data_quality_results WHERE status = 'FAIL') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Critical data-quality checks failed. Review payflow_analytics.data_quality_results and fix the source files first.';
    END IF;

    SELECT CAST(MAX(transaction_date) AS DATE) INTO as_of_date
    FROM payflow_staging.transactions;

    /* --- empty the reporting tables ----------------------------------- */
    /* TRUNCATE is refused on tables that foreign keys point at, so the
       checks are paused while emptying and switched back on before any
       data goes in. */
    SET FOREIGN_KEY_CHECKS = 0;
    TRUNCATE TABLE payflow_analytics.transactions;
    TRUNCATE TABLE payflow_analytics.cards;
    TRUNCATE TABLE payflow_analytics.loans;
    TRUNCATE TABLE payflow_analytics.accounts;
    TRUNCATE TABLE payflow_analytics.merchants;
    TRUNCATE TABLE payflow_analytics.customers;
    SET FOREIGN_KEY_CHECKS = 1;

    /* --- parents ------------------------------------------------------ */
    INSERT INTO payflow_analytics.customers
        (customer_id, first_name, last_name, email, city, credit_score, created_at)
    SELECT customer_id, first_name, last_name, email, city, credit_score, created_at
    FROM payflow_staging.customers;

    INSERT INTO payflow_analytics.merchants
        (merchant_id, merchant_name, city)
    SELECT merchant_id, merchant_name, city
    FROM payflow_staging.merchants;

    /* --- accounts ----------------------------------------------------- */
    INSERT INTO payflow_analytics.accounts
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
    FROM payflow_staging.accounts AS a
    JOIN payflow_staging.customers AS c
      ON c.customer_id = a.customer_id;

    /* --- loans -------------------------------------------------------- */
    INSERT INTO payflow_analytics.loans
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
    FROM payflow_staging.loans AS l
    JOIN payflow_staging.customers AS c
      ON c.customer_id = l.customer_id;

    /* --- cards -------------------------------------------------------- */
    INSERT INTO payflow_analytics.cards
        (card_id, account_id, card_type, expiration_date, card_status)
    SELECT
        k.card_id,
        k.account_id,
        k.card_type,
        k.expiration_date,
        CASE WHEN k.expiration_date <= as_of_date THEN 'Expired' ELSE 'Active' END
    FROM payflow_staging.cards AS k;

    /* --- transactions ------------------------------------------------- */
    INSERT INTO payflow_analytics.transactions
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
    FROM payflow_staging.transactions AS t
    LEFT JOIN payflow_staging.accounts  AS a ON a.account_id  = t.account_id
    LEFT JOIN payflow_staging.merchants AS m ON m.merchant_id = t.merchant_id;

    /* --- what was published ------------------------------------------- */
    SELECT as_of_date AS reporting_date;

    SELECT 'customers' AS table_name, COUNT(*) AS rows_published FROM payflow_analytics.customers
    UNION ALL SELECT 'accounts',     COUNT(*) FROM payflow_analytics.accounts
    UNION ALL SELECT 'cards',        COUNT(*) FROM payflow_analytics.cards
    UNION ALL SELECT 'loans',        COUNT(*) FROM payflow_analytics.loans
    UNION ALL SELECT 'merchants',    COUNT(*) FROM payflow_analytics.merchants
    UNION ALL SELECT 'transactions', COUNT(*) FROM payflow_analytics.transactions;

    SELECT account_match_status, merchant_match_status, COUNT(*) AS transactions
    FROM payflow_analytics.transactions
    GROUP BY account_match_status, merchant_match_status;

    SELECT card_status, COUNT(*) AS cards
    FROM payflow_analytics.cards
    GROUP BY card_status;
END$$

DELIMITER ;

/* =====================================================================
   payflow_analytics.vw_customer_summary
   One row per customer with everything they hold and do. Each fact is
   aggregated on its own first, so joining them cannot multiply rows.
   ===================================================================== */
CREATE OR REPLACE VIEW payflow_analytics.vw_customer_summary AS
WITH account_summary AS (
    SELECT customer_id,
           COUNT(*)         AS account_count,
           SUM(balance_usd) AS total_balance
    FROM payflow_analytics.accounts
    GROUP BY customer_id
),
loan_summary AS (
    SELECT customer_id,
           COUNT(*)           AS loan_count,
           SUM(loan_amount)   AS total_loan_amount,
           AVG(interest_rate) AS avg_interest_rate
    FROM payflow_analytics.loans
    GROUP BY customer_id
),
card_summary AS (
    SELECT a.customer_id,
           COUNT(*) AS card_count
    FROM payflow_analytics.cards AS k
    JOIN payflow_analytics.accounts AS a
      ON a.account_id = k.account_id
    GROUP BY a.customer_id
),
transaction_summary AS (
    SELECT a.customer_id,
           COUNT(*)          AS transaction_count,
           SUM(t.amount_usd) AS total_spent
    FROM payflow_analytics.transactions AS t
    JOIN payflow_analytics.accounts AS a
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
FROM payflow_analytics.customers AS c
LEFT JOIN account_summary     AS a ON a.customer_id = c.customer_id
LEFT JOIN loan_summary        AS l ON l.customer_id = c.customer_id
LEFT JOIN card_summary        AS k ON k.customer_id = c.customer_id
LEFT JOIN transaction_summary AS t ON t.customer_id = c.customer_id;

/* =====================================================================
   Build
   ===================================================================== */
CALL payflow_analytics.build_analytics_layer();
