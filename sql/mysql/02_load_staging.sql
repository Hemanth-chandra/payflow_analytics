/* =====================================================================
   PayFlow Analytics (MySQL 8 version)
   02_load_staging.sql

   Loads the CSV files in /data into the staging tables.

   BEFORE YOU RUN
     1. Allow local file loading on the server, once:
            SET GLOBAL local_infile = 1;
     2. In MySQL Workbench, allow it on the connection too:
            Database > Manage Connections > your connection > Advanced
            > in "Others" add the line  OPT_LOCAL_INFILE=1
        then reconnect.
        (From the command line, start mysql with --local-infile=1.)
     3. Replace every C:/PayFlow/data/ below with the path to your data
        folder (Ctrl+H in Workbench). Use forward slashes, and keep the
        slash at the end.

   Safe to re-run: every staging table is emptied first.
   ===================================================================== */

TRUNCATE TABLE payflow_staging.customers;
TRUNCATE TABLE payflow_staging.accounts;
TRUNCATE TABLE payflow_staging.cards;
TRUNCATE TABLE payflow_staging.loans;
TRUNCATE TABLE payflow_staging.merchants;
TRUNCATE TABLE payflow_staging.transactions;

/* --- master tables ---------------------------------------------------- */
LOAD DATA LOCAL INFILE 'C:/PayFlow/data/customers.csv'
INTO TABLE payflow_staging.customers
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'C:/PayFlow/data/accounts.csv'
INTO TABLE payflow_staging.accounts
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'C:/PayFlow/data/cards.csv'
INTO TABLE payflow_staging.cards
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'C:/PayFlow/data/loans.csv'
INTO TABLE payflow_staging.loans
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'C:/PayFlow/data/merchants.csv'
INTO TABLE payflow_staging.merchants
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

/* --- transactions: one file per year, 2019 to 2025 --------------------- */
LOAD DATA LOCAL INFILE 'C:/PayFlow/data/transactions/transactions_2019.csv'
INTO TABLE payflow_staging.transactions
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'C:/PayFlow/data/transactions/transactions_2020.csv'
INTO TABLE payflow_staging.transactions
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'C:/PayFlow/data/transactions/transactions_2021.csv'
INTO TABLE payflow_staging.transactions
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'C:/PayFlow/data/transactions/transactions_2022.csv'
INTO TABLE payflow_staging.transactions
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'C:/PayFlow/data/transactions/transactions_2023.csv'
INTO TABLE payflow_staging.transactions
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'C:/PayFlow/data/transactions/transactions_2024.csv'
INTO TABLE payflow_staging.transactions
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'C:/PayFlow/data/transactions/transactions_2025.csv'
INTO TABLE payflow_staging.transactions
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

/* --- confirm every file loaded completely ----------------------------- */
SELECT
    r.table_name,
    r.expected_rows,
    r.loaded_rows,
    CASE WHEN r.loaded_rows = r.expected_rows THEN 'OK' ELSE 'CHECK' END AS load_status
FROM (
    SELECT 'customers'    AS table_name,   50000 AS expected_rows, COUNT(*) AS loaded_rows FROM payflow_staging.customers
    UNION ALL
    SELECT 'accounts',       75000, COUNT(*) FROM payflow_staging.accounts
    UNION ALL
    SELECT 'cards',         100000, COUNT(*) FROM payflow_staging.cards
    UNION ALL
    SELECT 'loans',          30000, COUNT(*) FROM payflow_staging.loans
    UNION ALL
    SELECT 'merchants',       5000, COUNT(*) FROM payflow_staging.merchants
    UNION ALL
    SELECT 'transactions', 1000000, COUNT(*) FROM payflow_staging.transactions
) AS r;
