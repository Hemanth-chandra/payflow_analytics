/* =====================================================================
   PayFlow Analytics
   01_create_schema.sql

   Creates the database, two schemas and all tables.

     staging    raw copies of the CSV files, no constraints, so that
                bad data can be loaded and measured before it is used
     analytics  the reporting layer that Power BI reads, with primary
                keys, foreign keys and indexes

   Safe to re-run: it drops and recreates every table.
   Requires SQL Server 2017 or later.
   ===================================================================== */

IF DB_ID(N'PayFlowAnalytics') IS NULL
    CREATE DATABASE PayFlowAnalytics;
GO

USE PayFlowAnalytics;
GO

IF SCHEMA_ID(N'staging') IS NULL
    EXEC (N'CREATE SCHEMA staging');
GO

IF SCHEMA_ID(N'analytics') IS NULL
    EXEC (N'CREATE SCHEMA analytics');
GO

/* ---------------------------------------------------------------------
   Drop existing objects (children before parents)
   --------------------------------------------------------------------- */
DROP VIEW  IF EXISTS analytics.vw_customer_summary;
DROP TABLE IF EXISTS analytics.data_quality_results;
DROP TABLE IF EXISTS analytics.transactions;
DROP TABLE IF EXISTS analytics.cards;
DROP TABLE IF EXISTS analytics.loans;
DROP TABLE IF EXISTS analytics.accounts;
DROP TABLE IF EXISTS analytics.merchants;
DROP TABLE IF EXISTS analytics.customers;

DROP TABLE IF EXISTS staging.transactions;
DROP TABLE IF EXISTS staging.cards;
DROP TABLE IF EXISTS staging.loans;
DROP TABLE IF EXISTS staging.accounts;
DROP TABLE IF EXISTS staging.merchants;
DROP TABLE IF EXISTS staging.customers;
GO

/* =====================================================================
   STAGING: one table per CSV file, same columns as the file
   ===================================================================== */
CREATE TABLE staging.customers (
    customer_id   VARCHAR(20)   NULL,
    first_name    VARCHAR(50)   NULL,
    last_name     VARCHAR(50)   NULL,
    email         VARCHAR(100)  NULL,
    city          VARCHAR(50)   NULL,
    credit_score  INT           NULL,
    created_at    DATE          NULL
);

CREATE TABLE staging.accounts (
    account_id    VARCHAR(20)    NULL,
    customer_id   VARCHAR(20)    NULL,
    account_type  VARCHAR(20)    NULL,
    balance_usd   DECIMAL(12, 2) NULL,
    open_date     DATE           NULL
);

CREATE TABLE staging.cards (
    card_id          VARCHAR(20)  NULL,
    account_id       VARCHAR(20)  NULL,
    card_type        VARCHAR(20)  NULL,
    expiration_date  DATE         NULL
);

CREATE TABLE staging.loans (
    loan_id        VARCHAR(20)    NULL,
    customer_id    VARCHAR(20)    NULL,
    loan_amount    DECIMAL(12, 2) NULL,
    interest_rate  DECIMAL(5, 2)  NULL,
    start_date     DATE           NULL
);

CREATE TABLE staging.merchants (
    merchant_id    VARCHAR(20)   NULL,
    merchant_name  VARCHAR(100)  NULL,
    city           VARCHAR(50)   NULL
);

CREATE TABLE staging.transactions (
    transaction_id    VARCHAR(25)    NULL,
    account_id        VARCHAR(20)    NULL,
    merchant_id       VARCHAR(20)    NULL,
    amount_usd        DECIMAL(12, 2) NULL,
    transaction_date  DATETIME2(0)   NULL
);
GO

/* =====================================================================
   ANALYTICS: reporting layer read by Power BI
   Foreign keys mean a mismatched extract fails at load time instead
   of reaching the dashboard.
   ===================================================================== */
CREATE TABLE analytics.customers (
    customer_id   VARCHAR(20)   NOT NULL,
    first_name    VARCHAR(50)   NOT NULL,
    last_name     VARCHAR(50)   NOT NULL,
    email         VARCHAR(100)  NOT NULL,
    city          VARCHAR(50)   NOT NULL,
    credit_score  INT           NOT NULL,
    created_at    DATE          NOT NULL,
    CONSTRAINT PK_customers PRIMARY KEY (customer_id),
    CONSTRAINT CK_customers_credit_score CHECK (credit_score BETWEEN 300 AND 850)
);

CREATE TABLE analytics.merchants (
    merchant_id    VARCHAR(20)   NOT NULL,
    merchant_name  VARCHAR(100)  NOT NULL,
    city           VARCHAR(50)   NOT NULL,
    CONSTRAINT PK_merchants PRIMARY KEY (merchant_id)
);

/* first_name, last_name and city are copied from customers so that
   account-level reports do not need a join. account_date_valid is 1
   when the account was opened on or after the customer was created. */
CREATE TABLE analytics.accounts (
    account_id          VARCHAR(20)    NOT NULL,
    customer_id         VARCHAR(20)    NOT NULL,
    first_name          VARCHAR(50)    NOT NULL,
    last_name           VARCHAR(50)    NOT NULL,
    city                VARCHAR(50)    NOT NULL,
    account_type        VARCHAR(20)    NOT NULL,
    balance_usd         DECIMAL(12, 2) NOT NULL,
    open_date           DATE           NOT NULL,
    account_date_valid  INT            NOT NULL,
    CONSTRAINT PK_accounts PRIMARY KEY (account_id),
    CONSTRAINT FK_accounts_customers FOREIGN KEY (customer_id)
        REFERENCES analytics.customers (customer_id)
);

/* loan_date_valid is 1 when the loan started on or after the customer
   was created. */
CREATE TABLE analytics.loans (
    loan_id          VARCHAR(20)    NOT NULL,
    customer_id      VARCHAR(20)    NOT NULL,
    first_name       VARCHAR(50)    NOT NULL,
    last_name        VARCHAR(50)    NOT NULL,
    city             VARCHAR(50)    NOT NULL,
    credit_score     INT            NOT NULL,
    loan_amount      DECIMAL(12, 2) NOT NULL,
    interest_rate    DECIMAL(5, 2)  NOT NULL,
    start_date       DATE           NOT NULL,
    loan_date_valid  INT            NOT NULL,
    CONSTRAINT PK_loans PRIMARY KEY (loan_id),
    CONSTRAINT FK_loans_customers FOREIGN KEY (customer_id)
        REFERENCES analytics.customers (customer_id)
);

/* card_status is 'Expired' or 'Active' as of the reporting date,
   which is the last transaction date in the data (see script 04). */
CREATE TABLE analytics.cards (
    card_id          VARCHAR(20)  NOT NULL,
    account_id       VARCHAR(20)  NOT NULL,
    card_type        VARCHAR(20)  NOT NULL,
    expiration_date  DATE         NOT NULL,
    card_status      VARCHAR(10)  NOT NULL,
    CONSTRAINT PK_cards PRIMARY KEY (card_id),
    CONSTRAINT FK_cards_accounts FOREIGN KEY (account_id)
        REFERENCES analytics.accounts (account_id)
);

CREATE TABLE analytics.transactions (
    transaction_id         VARCHAR(25)    NOT NULL,
    account_id             VARCHAR(20)    NOT NULL,
    merchant_id            VARCHAR(20)    NOT NULL,
    amount_usd             DECIMAL(12, 2) NOT NULL,
    transaction_date       DATETIME2(0)   NOT NULL,
    account_match_status   VARCHAR(10)    NOT NULL,
    merchant_match_status  VARCHAR(10)    NOT NULL,
    CONSTRAINT PK_transactions PRIMARY KEY (transaction_id),
    CONSTRAINT FK_transactions_accounts FOREIGN KEY (account_id)
        REFERENCES analytics.accounts (account_id),
    CONSTRAINT FK_transactions_merchants FOREIGN KEY (merchant_id)
        REFERENCES analytics.merchants (merchant_id)
);

/* One row per data-quality check, written by script 03. */
CREATE TABLE analytics.data_quality_results (
    check_id     INT            NOT NULL,
    category     VARCHAR(30)    NOT NULL,
    check_name   VARCHAR(120)   NOT NULL,
    table_name   VARCHAR(40)    NOT NULL,
    severity     VARCHAR(10)    NOT NULL,   -- 'Critical' or 'Warning'
    rows_tested  INT            NOT NULL,
    rows_failed  INT            NOT NULL,
    fail_pct     DECIMAL(6, 2)  NULL,
    status       VARCHAR(10)    NULL,       -- 'PASS', 'WARN' or 'FAIL'
    CONSTRAINT PK_data_quality_results PRIMARY KEY (check_id)
);
GO

/* ---------------------------------------------------------------------
   Indexes on the join and filter columns
   --------------------------------------------------------------------- */
CREATE INDEX IX_accounts_customer_id      ON analytics.accounts (customer_id);
CREATE INDEX IX_loans_customer_id         ON analytics.loans (customer_id);
CREATE INDEX IX_cards_account_id          ON analytics.cards (account_id);
CREATE INDEX IX_transactions_account_id   ON analytics.transactions (account_id);
CREATE INDEX IX_transactions_merchant_id  ON analytics.transactions (merchant_id);
CREATE INDEX IX_transactions_date         ON analytics.transactions (transaction_date);
GO
