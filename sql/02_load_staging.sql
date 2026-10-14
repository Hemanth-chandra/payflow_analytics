/* =====================================================================
   PayFlow Analytics
   02_load_staging.sql

   Bulk-loads the CSV files in /data into the staging tables.

   BEFORE YOU RUN
     1. Copy the repo's data folder somewhere the SQL Server service
        can read, for example C:\PayFlow\data\
        (a Desktop, Downloads or OneDrive folder usually fails with
        "Operating system error code 5 (Access is denied)").
     2. Set @DataPath below to that folder. Keep the trailing backslash.

   Run the whole script as one batch.
   Safe to re-run: every staging table is emptied first.
   ===================================================================== */

USE PayFlowAnalytics;
GO

SET NOCOUNT ON;

DECLARE @DataPath NVARCHAR(260) = N'C:\PayFlow\data\';   -- <<< change this

DECLARE @Options NVARCHAR(400) =
    N' WITH (FORMAT = ''CSV'', FIRSTROW = 2, FIELDQUOTE = ''"'', '
  + N'FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', TABLOCK);';

DECLARE @sql NVARCHAR(MAX);

TRUNCATE TABLE staging.customers;
TRUNCATE TABLE staging.accounts;
TRUNCATE TABLE staging.cards;
TRUNCATE TABLE staging.loans;
TRUNCATE TABLE staging.merchants;
TRUNCATE TABLE staging.transactions;

/* --- master tables ---------------------------------------------------- */
SET @sql = N'BULK INSERT staging.customers FROM ''' + @DataPath + N'customers.csv''' + @Options;
EXEC sys.sp_executesql @sql;

SET @sql = N'BULK INSERT staging.accounts FROM ''' + @DataPath + N'accounts.csv''' + @Options;
EXEC sys.sp_executesql @sql;

SET @sql = N'BULK INSERT staging.cards FROM ''' + @DataPath + N'cards.csv''' + @Options;
EXEC sys.sp_executesql @sql;

SET @sql = N'BULK INSERT staging.loans FROM ''' + @DataPath + N'loans.csv''' + @Options;
EXEC sys.sp_executesql @sql;

SET @sql = N'BULK INSERT staging.merchants FROM ''' + @DataPath + N'merchants.csv''' + @Options;
EXEC sys.sp_executesql @sql;

/* --- transactions: one file per year, 2019 to 2025 --------------------- */
DECLARE @Year INT = 2019;

WHILE @Year <= 2025
BEGIN
    SET @sql = N'BULK INSERT staging.transactions FROM ''' + @DataPath
             + N'transactions\transactions_' + CAST(@Year AS NVARCHAR(4)) + N'.csv''' + @Options;
    EXEC sys.sp_executesql @sql;

    SET @Year = @Year + 1;
END;

/* --- confirm every file loaded completely ----------------------------- */
SELECT
    r.table_name,
    r.expected_rows,
    r.loaded_rows,
    CASE WHEN r.loaded_rows = r.expected_rows THEN 'OK' ELSE 'CHECK' END AS load_status
FROM (
    SELECT 'customers'    AS table_name,   50000 AS expected_rows, COUNT(*) AS loaded_rows FROM staging.customers
    UNION ALL
    SELECT 'accounts',       75000, COUNT(*) FROM staging.accounts
    UNION ALL
    SELECT 'cards',         100000, COUNT(*) FROM staging.cards
    UNION ALL
    SELECT 'loans',          30000, COUNT(*) FROM staging.loans
    UNION ALL
    SELECT 'merchants',       5000, COUNT(*) FROM staging.merchants
    UNION ALL
    SELECT 'transactions', 1000000, COUNT(*) FROM staging.transactions
) AS r;
GO
