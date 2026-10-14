/* =====================================================================
   PayFlow Analytics (MySQL 8 version)
   03_data_quality_checks.sql

   Tests the staging data BEFORE it is published to the analytics layer.
   Every check writes one row to payflow_analytics.data_quality_results:

     rows_tested   how many rows the rule was applied to
     rows_failed   how many of them broke the rule
     severity      Critical = the data cannot be used if this fails
                   Warning  = usable, but the limitation must be stated
     status        PASS / WARN / FAIL
                   (a check that tested 0 rows is a FAIL: empty staging
                   tables mean script 02 did not load anything)

   Script 04 refuses to build the analytics tables while any Critical
   check has status FAIL.

   Safe to re-run.
   ===================================================================== */

TRUNCATE TABLE payflow_analytics.data_quality_results;

/* =====================================================================
   1. UNIQUENESS: every primary key value appears once
   ===================================================================== */
INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 101, 'Uniqueness', 'customer_id is unique', 'customers', 'Critical',
       COUNT(*), COUNT(*) - COUNT(DISTINCT customer_id)
FROM payflow_staging.customers;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 102, 'Uniqueness', 'account_id is unique', 'accounts', 'Critical',
       COUNT(*), COUNT(*) - COUNT(DISTINCT account_id)
FROM payflow_staging.accounts;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 103, 'Uniqueness', 'card_id is unique', 'cards', 'Critical',
       COUNT(*), COUNT(*) - COUNT(DISTINCT card_id)
FROM payflow_staging.cards;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 104, 'Uniqueness', 'loan_id is unique', 'loans', 'Critical',
       COUNT(*), COUNT(*) - COUNT(DISTINCT loan_id)
FROM payflow_staging.loans;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 105, 'Uniqueness', 'merchant_id is unique', 'merchants', 'Critical',
       COUNT(*), COUNT(*) - COUNT(DISTINCT merchant_id)
FROM payflow_staging.merchants;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 106, 'Uniqueness', 'transaction_id is unique', 'transactions', 'Critical',
       COUNT(*), COUNT(*) - COUNT(DISTINCT transaction_id)
FROM payflow_staging.transactions;

/* =====================================================================
   2. COMPLETENESS: no missing values in any column
   ===================================================================== */
INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 201, 'Completeness', 'no missing values', 'customers', 'Critical',
       COUNT(*),
       COALESCE(SUM(CASE WHEN customer_id IS NULL OR first_name IS NULL OR last_name IS NULL
                           OR email IS NULL OR city IS NULL OR credit_score IS NULL
                           OR created_at IS NULL THEN 1 ELSE 0 END), 0)
FROM payflow_staging.customers;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 202, 'Completeness', 'no missing values', 'accounts', 'Critical',
       COUNT(*),
       COALESCE(SUM(CASE WHEN account_id IS NULL OR customer_id IS NULL OR account_type IS NULL
                           OR balance_usd IS NULL OR open_date IS NULL THEN 1 ELSE 0 END), 0)
FROM payflow_staging.accounts;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 203, 'Completeness', 'no missing values', 'cards', 'Critical',
       COUNT(*),
       COALESCE(SUM(CASE WHEN card_id IS NULL OR account_id IS NULL OR card_type IS NULL
                           OR expiration_date IS NULL THEN 1 ELSE 0 END), 0)
FROM payflow_staging.cards;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 204, 'Completeness', 'no missing values', 'loans', 'Critical',
       COUNT(*),
       COALESCE(SUM(CASE WHEN loan_id IS NULL OR customer_id IS NULL OR loan_amount IS NULL
                           OR interest_rate IS NULL OR start_date IS NULL THEN 1 ELSE 0 END), 0)
FROM payflow_staging.loans;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 205, 'Completeness', 'no missing values', 'merchants', 'Critical',
       COUNT(*),
       COALESCE(SUM(CASE WHEN merchant_id IS NULL OR merchant_name IS NULL OR city IS NULL
                         THEN 1 ELSE 0 END), 0)
FROM payflow_staging.merchants;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 206, 'Completeness', 'no missing values', 'transactions', 'Critical',
       COUNT(*),
       COALESCE(SUM(CASE WHEN transaction_id IS NULL OR account_id IS NULL OR merchant_id IS NULL
                           OR amount_usd IS NULL OR transaction_date IS NULL THEN 1 ELSE 0 END), 0)
FROM payflow_staging.transactions;

/* =====================================================================
   3. REFERENTIAL INTEGRITY: every child row points at a real parent
   This is the check that caught the mismatched transactions extract
   (see docs/data_quality_report.md).
   ===================================================================== */
INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 301, 'Referential integrity', 'accounts.customer_id exists in customers', 'accounts', 'Critical',
       COUNT(*),
       COALESCE(SUM(CASE WHEN c.customer_id IS NULL THEN 1 ELSE 0 END), 0)
FROM payflow_staging.accounts AS a
LEFT JOIN (SELECT DISTINCT customer_id FROM payflow_staging.customers) AS c
       ON c.customer_id = a.customer_id;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 302, 'Referential integrity', 'loans.customer_id exists in customers', 'loans', 'Critical',
       COUNT(*),
       COALESCE(SUM(CASE WHEN c.customer_id IS NULL THEN 1 ELSE 0 END), 0)
FROM payflow_staging.loans AS l
LEFT JOIN (SELECT DISTINCT customer_id FROM payflow_staging.customers) AS c
       ON c.customer_id = l.customer_id;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 303, 'Referential integrity', 'cards.account_id exists in accounts', 'cards', 'Critical',
       COUNT(*),
       COALESCE(SUM(CASE WHEN a.account_id IS NULL THEN 1 ELSE 0 END), 0)
FROM payflow_staging.cards AS k
LEFT JOIN (SELECT DISTINCT account_id FROM payflow_staging.accounts) AS a
       ON a.account_id = k.account_id;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 304, 'Referential integrity', 'transactions.account_id exists in accounts', 'transactions', 'Critical',
       COUNT(*),
       COALESCE(SUM(CASE WHEN a.account_id IS NULL THEN 1 ELSE 0 END), 0)
FROM payflow_staging.transactions AS t
LEFT JOIN (SELECT DISTINCT account_id FROM payflow_staging.accounts) AS a
       ON a.account_id = t.account_id;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 305, 'Referential integrity', 'transactions.merchant_id exists in merchants', 'transactions', 'Critical',
       COUNT(*),
       COALESCE(SUM(CASE WHEN m.merchant_id IS NULL THEN 1 ELSE 0 END), 0)
FROM payflow_staging.transactions AS t
LEFT JOIN (SELECT DISTINCT merchant_id FROM payflow_staging.merchants) AS m
       ON m.merchant_id = t.merchant_id;

/* =====================================================================
   4. VALIDITY: values fall inside the allowed range or list
   ===================================================================== */
INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 401, 'Validity', 'credit_score is between 300 and 850', 'customers', 'Critical',
       COUNT(*),
       COALESCE(SUM(CASE WHEN credit_score BETWEEN 300 AND 850 THEN 0 ELSE 1 END), 0)
FROM payflow_staging.customers;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 402, 'Validity', 'balance_usd is not negative', 'accounts', 'Warning',
       COUNT(*),
       COALESCE(SUM(CASE WHEN balance_usd >= 0 THEN 0 ELSE 1 END), 0)
FROM payflow_staging.accounts;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 403, 'Validity', 'account_type is Checking, Savings or Business', 'accounts', 'Warning',
       COUNT(*),
       COALESCE(SUM(CASE WHEN account_type IN ('Checking', 'Savings', 'Business') THEN 0 ELSE 1 END), 0)
FROM payflow_staging.accounts;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 404, 'Validity', 'card_type is Debit or Credit', 'cards', 'Warning',
       COUNT(*),
       COALESCE(SUM(CASE WHEN card_type IN ('Debit', 'Credit') THEN 0 ELSE 1 END), 0)
FROM payflow_staging.cards;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 405, 'Validity', 'loan_amount is greater than zero', 'loans', 'Critical',
       COUNT(*),
       COALESCE(SUM(CASE WHEN loan_amount > 0 THEN 0 ELSE 1 END), 0)
FROM payflow_staging.loans;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 406, 'Validity', 'interest_rate is between 0 and 100', 'loans', 'Critical',
       COUNT(*),
       COALESCE(SUM(CASE WHEN interest_rate BETWEEN 0 AND 100 THEN 0 ELSE 1 END), 0)
FROM payflow_staging.loans;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 407, 'Validity', 'amount_usd is greater than zero', 'transactions', 'Critical',
       COUNT(*),
       COALESCE(SUM(CASE WHEN amount_usd > 0 THEN 0 ELSE 1 END), 0)
FROM payflow_staging.transactions;

/* =====================================================================
   5. IDENTITY: is email usable as a customer identifier?
   rows_failed = customers whose email is also used by another customer
   ===================================================================== */
INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 501, 'Identity', 'email is used by only one customer', 'customers', 'Warning',
       COUNT(*),
       COALESCE(SUM(CASE WHEN e.customers_with_email > 1 THEN 1 ELSE 0 END), 0)
FROM payflow_staging.customers AS c
JOIN (
    SELECT email, COUNT(*) AS customers_with_email
    FROM payflow_staging.customers
    GROUP BY email
) AS e
  ON e.email = c.email;

/* =====================================================================
   6. DATE LOGIC: events happen in a sensible order
   ===================================================================== */
INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 601, 'Date logic', 'account opened on or after customer created', 'accounts', 'Warning',
       COUNT(*),
       COALESCE(SUM(CASE WHEN a.open_date < c.created_at THEN 1 ELSE 0 END), 0)
FROM payflow_staging.accounts AS a
JOIN payflow_staging.customers AS c
  ON c.customer_id = a.customer_id;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 602, 'Date logic', 'loan started on or after customer created', 'loans', 'Warning',
       COUNT(*),
       COALESCE(SUM(CASE WHEN l.start_date < c.created_at THEN 1 ELSE 0 END), 0)
FROM payflow_staging.loans AS l
JOIN payflow_staging.customers AS c
  ON c.customer_id = l.customer_id;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 603, 'Date logic', 'card expires on or after account opened', 'cards', 'Warning',
       COUNT(*),
       COALESCE(SUM(CASE WHEN k.expiration_date < a.open_date THEN 1 ELSE 0 END), 0)
FROM payflow_staging.cards AS k
JOIN payflow_staging.accounts AS a
  ON a.account_id = k.account_id;

INSERT INTO payflow_analytics.data_quality_results (check_id, category, check_name, table_name, severity, rows_tested, rows_failed)
SELECT 604, 'Date logic', 'transaction dated on or after account opened', 'transactions', 'Warning',
       COUNT(*),
       COALESCE(SUM(CASE WHEN CAST(t.transaction_date AS DATE) < a.open_date THEN 1 ELSE 0 END), 0)
FROM payflow_staging.transactions AS t
JOIN payflow_staging.accounts AS a
  ON a.account_id = t.account_id;

/* =====================================================================
   Score every check
   ===================================================================== */
UPDATE payflow_analytics.data_quality_results
SET fail_pct = CAST(100.0 * rows_failed / NULLIF(rows_tested, 0) AS DECIMAL(6, 2)),
    status   = CASE
                   WHEN rows_tested = 0         THEN 'FAIL'   -- nothing loaded: never a pass
                   WHEN rows_failed = 0         THEN 'PASS'
                   WHEN severity = 'Critical'   THEN 'FAIL'
                   ELSE 'WARN'
               END
WHERE check_id > 0;   -- a key column in WHERE keeps Workbench safe-update mode happy

/* =====================================================================
   RESULT 1: the scorecard
   ===================================================================== */
SELECT check_id, category, check_name, table_name, severity,
       rows_tested, rows_failed, fail_pct, status
FROM payflow_analytics.data_quality_results
ORDER BY check_id;

/* =====================================================================
   RESULT 2: diagnosis queries
   These explain a failure or warning rather than just counting it.
   ===================================================================== */

-- D1. If transactions do not match accounts, is it a few bad rows or the
--     wrong file? Compare how many DISTINCT ids each side has and how
--     many overlap. Bad rows: almost all ids overlap. Wrong file: both
--     sides have a similar number of ids but few overlap.
SELECT
    'account_id'                                         AS key_column,
    (SELECT COUNT(DISTINCT account_id) FROM payflow_staging.transactions) AS distinct_ids_in_transactions,
    (SELECT COUNT(DISTINCT account_id) FROM payflow_staging.accounts)     AS distinct_ids_in_master,
    (SELECT COUNT(*)
     FROM (SELECT DISTINCT account_id FROM payflow_staging.transactions) AS t
     JOIN (SELECT DISTINCT account_id FROM payflow_staging.accounts)     AS a
       ON a.account_id = t.account_id)                   AS ids_found_in_both
UNION ALL
SELECT
    'merchant_id',
    (SELECT COUNT(DISTINCT merchant_id) FROM payflow_staging.transactions),
    (SELECT COUNT(DISTINCT merchant_id) FROM payflow_staging.merchants),
    (SELECT COUNT(*)
     FROM (SELECT DISTINCT merchant_id FROM payflow_staging.transactions) AS t
     JOIN (SELECT DISTINCT merchant_id FROM payflow_staging.merchants)    AS m
       ON m.merchant_id = t.merchant_id);

-- D2. Are customers who share an email the same person entered twice?
--     If they were, they would share a name. Here no group does, so the
--     emails are coincidental and email must not be used to merge or
--     identify customers.
WITH shared_email AS (
    SELECT
        email,
        COUNT(*)                                      AS customers_with_email,
        COUNT(DISTINCT CONCAT(first_name, '|', last_name)) AS distinct_names,
        COUNT(DISTINCT city)                          AS distinct_cities
    FROM payflow_staging.customers
    GROUP BY email
    HAVING COUNT(*) > 1
)
SELECT
    COUNT(*)                                                 AS shared_email_groups,
    SUM(customers_with_email)                                AS customers_in_those_groups,
    MAX(customers_with_email)                                AS largest_group,
    SUM(CASE WHEN distinct_names = 1 THEN 1 ELSE 0 END)      AS groups_with_one_name,
    SUM(CASE WHEN distinct_cities = 1 THEN 1 ELSE 0 END)     AS groups_with_one_city
FROM shared_email;

-- D3. Date-logic failure rates side by side. A rate near 50% means the
--     two dates were generated independently, so the rule is not an
--     "exception" list to clean up: it means tenure and lifecycle
--     analysis cannot be done with these columns.
SELECT check_name, rows_tested, rows_failed, fail_pct,
       CASE
           WHEN rows_tested = 0 THEN 'No rows tested: run 02_load_staging.sql first'
           WHEN fail_pct >= 40 THEN 'Dates are unrelated: do not use for lifecycle analysis'
           WHEN fail_pct > 0   THEN 'Genuine exceptions: review the listed rows'
           ELSE 'Rule holds'
       END AS interpretation
FROM payflow_analytics.data_quality_results
WHERE category = 'Date logic'
ORDER BY check_id;

-- D4. A real exception list: the 20 cards that expired longest before
--     their account was opened.
SELECT
    k.card_id, k.account_id, k.card_type, k.expiration_date, a.open_date,
    DATEDIFF(a.open_date, k.expiration_date) AS days_expired_before_opening
FROM payflow_staging.cards AS k
JOIN payflow_staging.accounts AS a
  ON a.account_id = k.account_id
WHERE k.expiration_date < a.open_date
ORDER BY days_expired_before_opening DESC, k.card_id
LIMIT 20;
