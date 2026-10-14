/* =====================================================================
   PayFlow Analytics (MySQL 8 version)
   01_create_schema.sql

   Creates two databases and all tables.

     payflow_staging    raw copies of the CSV files, no constraints, so
                        that bad data can be loaded and measured before
                        it is used
     payflow_analytics  the reporting layer, with primary keys, foreign
                        keys and indexes

   Safe to re-run: it drops and recreates both databases.
   Requires MySQL 8.0.16 or later (CHECK constraints, window functions).
   ===================================================================== */

DROP DATABASE IF EXISTS payflow_analytics;
DROP DATABASE IF EXISTS payflow_staging;

CREATE DATABASE payflow_staging   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE DATABASE payflow_analytics CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

/* =====================================================================
   STAGING: one table per CSV file, same columns as the file
   ===================================================================== */
CREATE TABLE payflow_staging.customers (
    customer_id   VARCHAR(20)   NULL,
    first_name    VARCHAR(50)   NULL,
    last_name     VARCHAR(50)   NULL,
    email         VARCHAR(100)  NULL,
    city          VARCHAR(50)   NULL,
    credit_score  INT           NULL,
    created_at    DATE          NULL
);

CREATE TABLE payflow_staging.accounts (
    account_id    VARCHAR(20)    NULL,
    customer_id   VARCHAR(20)    NULL,
    account_type  VARCHAR(20)    NULL,
    balance_usd   DECIMAL(12, 2) NULL,
    open_date     DATE           NULL
);

CREATE TABLE payflow_staging.cards (
    card_id          VARCHAR(20)  NULL,
    account_id       VARCHAR(20)  NULL,
    card_type        VARCHAR(20)  NULL,
    expiration_date  DATE         NULL
);

CREATE TABLE payflow_staging.loans (
    loan_id        VARCHAR(20)    NULL,
    customer_id    VARCHAR(20)    NULL,
    loan_amount    DECIMAL(12, 2) NULL,
    interest_rate  DECIMAL(5, 2)  NULL,
    start_date     DATE           NULL
);

CREATE TABLE payflow_staging.merchants (
    merchant_id    VARCHAR(20)   NULL,
    merchant_name  VARCHAR(100)  NULL,
    city           VARCHAR(50)   NULL
);

CREATE TABLE payflow_staging.transactions (
    transaction_id    VARCHAR(25)    NULL,
    account_id        VARCHAR(20)    NULL,
    merchant_id       VARCHAR(20)    NULL,
    amount_usd        DECIMAL(12, 2) NULL,
    transaction_date  DATETIME       NULL
);

/* =====================================================================
   ANALYTICS: reporting layer
   Foreign keys mean a mismatched extract fails at load time instead
   of reaching the dashboard. InnoDB indexes every foreign key column.
   ===================================================================== */
CREATE TABLE payflow_analytics.customers (
    customer_id   VARCHAR(20)   NOT NULL,
    first_name    VARCHAR(50)   NOT NULL,
    last_name     VARCHAR(50)   NOT NULL,
    email         VARCHAR(100)  NOT NULL,
    city          VARCHAR(50)   NOT NULL,
    credit_score  INT           NOT NULL,
    created_at    DATE          NOT NULL,
    CONSTRAINT pk_customers PRIMARY KEY (customer_id),
    CONSTRAINT ck_customers_credit_score CHECK (credit_score BETWEEN 300 AND 850)
) ENGINE = InnoDB;

CREATE TABLE payflow_analytics.merchants (
    merchant_id    VARCHAR(20)   NOT NULL,
    merchant_name  VARCHAR(100)  NOT NULL,
    city           VARCHAR(50)   NOT NULL,
    CONSTRAINT pk_merchants PRIMARY KEY (merchant_id)
) ENGINE = InnoDB;

/* first_name, last_name and city are copied from customers so that
   account-level reports do not need a join. account_date_valid is 1
   when the account was opened on or after the customer was created. */
CREATE TABLE payflow_analytics.accounts (
    account_id          VARCHAR(20)    NOT NULL,
    customer_id         VARCHAR(20)    NOT NULL,
    first_name          VARCHAR(50)    NOT NULL,
    last_name           VARCHAR(50)    NOT NULL,
    city                VARCHAR(50)    NOT NULL,
    account_type        VARCHAR(20)    NOT NULL,
    balance_usd         DECIMAL(12, 2) NOT NULL,
    open_date           DATE           NOT NULL,
    account_date_valid  INT            NOT NULL,
    CONSTRAINT pk_accounts PRIMARY KEY (account_id),
    CONSTRAINT fk_accounts_customers FOREIGN KEY (customer_id)
        REFERENCES payflow_analytics.customers (customer_id)
) ENGINE = InnoDB;

/* loan_date_valid is 1 when the loan started on or after the customer
   was created. */
CREATE TABLE payflow_analytics.loans (
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
    CONSTRAINT pk_loans PRIMARY KEY (loan_id),
    CONSTRAINT fk_loans_customers FOREIGN KEY (customer_id)
        REFERENCES payflow_analytics.customers (customer_id)
) ENGINE = InnoDB;

/* card_status is 'Expired' or 'Active' as of the reporting date,
   which is the last transaction date in the data (see script 04). */
CREATE TABLE payflow_analytics.cards (
    card_id          VARCHAR(20)  NOT NULL,
    account_id       VARCHAR(20)  NOT NULL,
    card_type        VARCHAR(20)  NOT NULL,
    expiration_date  DATE         NOT NULL,
    card_status      VARCHAR(10)  NOT NULL,
    CONSTRAINT pk_cards PRIMARY KEY (card_id),
    CONSTRAINT fk_cards_accounts FOREIGN KEY (account_id)
        REFERENCES payflow_analytics.accounts (account_id)
) ENGINE = InnoDB;

CREATE TABLE payflow_analytics.transactions (
    transaction_id         VARCHAR(25)    NOT NULL,
    account_id             VARCHAR(20)    NOT NULL,
    merchant_id            VARCHAR(20)    NOT NULL,
    amount_usd             DECIMAL(12, 2) NOT NULL,
    transaction_date       DATETIME       NOT NULL,
    account_match_status   VARCHAR(10)    NOT NULL,
    merchant_match_status  VARCHAR(10)    NOT NULL,
    CONSTRAINT pk_transactions PRIMARY KEY (transaction_id),
    CONSTRAINT fk_transactions_accounts FOREIGN KEY (account_id)
        REFERENCES payflow_analytics.accounts (account_id),
    CONSTRAINT fk_transactions_merchants FOREIGN KEY (merchant_id)
        REFERENCES payflow_analytics.merchants (merchant_id)
) ENGINE = InnoDB;

CREATE INDEX ix_transactions_date ON payflow_analytics.transactions (transaction_date);

/* One row per data-quality check, written by script 03. */
CREATE TABLE payflow_analytics.data_quality_results (
    check_id     INT            NOT NULL,
    category     VARCHAR(30)    NOT NULL,
    check_name   VARCHAR(120)   NOT NULL,
    table_name   VARCHAR(40)    NOT NULL,
    severity     VARCHAR(10)    NOT NULL,   -- 'Critical' or 'Warning'
    rows_tested  INT            NOT NULL,
    rows_failed  INT            NOT NULL,
    fail_pct     DECIMAL(6, 2)  NULL,
    status       VARCHAR(10)    NULL,       -- 'PASS', 'WARN' or 'FAIL'
    CONSTRAINT pk_data_quality_results PRIMARY KEY (check_id)
) ENGINE = InnoDB;
