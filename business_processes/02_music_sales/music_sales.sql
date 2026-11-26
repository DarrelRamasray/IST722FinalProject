-- =====================================================================
-- music_sales.sql · Business process: MUSIC SALES
-- IST 722 Data Warehouse, Fall 2026 · Team DIM Data · Owner: Darrel Ramasray
-- Built for Milestone 2; the shared dim_date was widened in Employee Hire.
--
-- Pipeline: Chinook (school SQL Server) -> CSV -> Snowflake RAW.CHINOOK
--   -> dbt -> ANALYTICS.DBT_DRAMASRAY_CHINOOK -> Power BI (MusicSales.pbix)
-- Star: fact_sale (one row per invoice line, 2,240 rows) with dim_date,
--   dim_customer, dim_employee, dim_invoice and dim_track (all conformed:
--   Track Playtime and Employee Hire reuse them).
-- Verified: RAW 52/52 checks PASS · dbt 6 models + 51 tests PASS
--   · star 23/23 checks PASS · Total Sales $2,328.60 in Power BI.
--
-- How to read this file: run each STEP in the tool named in its header.
-- SQL blocks (SQL Server, Snowflake, dbt models) are plain code. Blocks
-- for other tools (Snowflake CLI, dbt YAML, Power BI DAX, Python) sit
-- inside /* */ comments. It is a record of the build, not one script to
-- run top to bottom. The runnable dbt project is dbt/chinook_dw/, with
-- one models folder per process plus shared_dimensions/.
-- =====================================================================


-- =====================================================================
-- STEP 1 · Extract the 9 Chinook tables to CSV
-- Run in: VS Code (MSSQL extension) on the school SQL Server, database Chinook
-- Run one query at a time; save each result as the CSV named in its comment,
-- in Documents\chinook_extract. CONVERT(...,121) fixes the date text format
-- (2009-01-01 00:00:00.000).
-- =====================================================================
-- ---------------------------------------------------------------------
-- 1 of 9  ->  album.csv  (347 rows)
-- ---------------------------------------------------------------------
SELECT AlbumId, Title, ArtistId
FROM Chinook.dbo.Album
ORDER BY AlbumId;


-- ---------------------------------------------------------------------
-- 2 of 9  ->  artist.csv  (275 rows)
-- ---------------------------------------------------------------------
SELECT ArtistId, Name
FROM Chinook.dbo.Artist
ORDER BY ArtistId;


-- ---------------------------------------------------------------------
-- 3 of 9  ->  customer.csv  (59 rows)
-- ---------------------------------------------------------------------
SELECT CustomerId, FirstName, LastName, Company, Address, City, State,
       Country, PostalCode, Phone, Fax, Email, SupportRepId
FROM Chinook.dbo.Customer
ORDER BY CustomerId;


-- ---------------------------------------------------------------------
-- 4 of 9  ->  employee.csv  (8 rows)
-- ---------------------------------------------------------------------
SELECT EmployeeId, LastName, FirstName, Title, ReportsTo,
       CONVERT(varchar(23), BirthDate, 121) AS BirthDate,
       CONVERT(varchar(23), HireDate, 121) AS HireDate,
       Address, City, State, Country, PostalCode, Phone, Fax, Email
FROM Chinook.dbo.Employee
ORDER BY EmployeeId;


-- ---------------------------------------------------------------------
-- 5 of 9  ->  genre.csv  (25 rows)
-- ---------------------------------------------------------------------
SELECT GenreId, Name
FROM Chinook.dbo.Genre
ORDER BY GenreId;


-- ---------------------------------------------------------------------
-- 6 of 9  ->  invoice.csv  (412 rows)
-- ---------------------------------------------------------------------
SELECT InvoiceId, CustomerId,
       CONVERT(varchar(23), InvoiceDate, 121) AS InvoiceDate,
       BillingAddress, BillingCity, BillingState, BillingCountry,
       BillingPostalCode, Total
FROM Chinook.dbo.Invoice
ORDER BY InvoiceId;


-- ---------------------------------------------------------------------
-- 7 of 9  ->  invoiceline.csv  (2240 rows)
-- ---------------------------------------------------------------------
SELECT InvoiceLineId, InvoiceId, TrackId, UnitPrice, Quantity
FROM Chinook.dbo.InvoiceLine
ORDER BY InvoiceLineId;


-- ---------------------------------------------------------------------
-- 8 of 9  ->  mediatype.csv  (5 rows)
-- ---------------------------------------------------------------------
SELECT MediaTypeId, Name
FROM Chinook.dbo.MediaType
ORDER BY MediaTypeId;


-- ---------------------------------------------------------------------
-- 9 of 9  ->  track.csv  (3503 rows)
-- ---------------------------------------------------------------------
SELECT TrackId, Name, AlbumId, MediaTypeId, GenreId, Composer,
       Milliseconds, Bytes, UnitPrice
FROM Chinook.dbo.Track
ORDER BY TrackId;


-- =====================================================================
-- STEP 2 · Create the RAW database, file format, stage and 9 tables
-- Run in: Snowsight (role SYSADMIN, warehouse COMPUTE_WH)
-- Creates RAW.CHINOOK, file format CHINOOK_CSV, stage CHINOOK_STAGE and one
-- table per source table (+ _SOURCE_FILE, _LOADED_AT for lineage).
-- Warning: re-running this step EMPTIES the 9 tables (staged files stay).
-- =====================================================================
USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;

CREATE DATABASE IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS RAW.CHINOOK;
USE SCHEMA RAW.CHINOOK;

-- How Snowflake reads the nine CSV files
CREATE OR REPLACE FILE FORMAT CHINOOK_CSV
  TYPE = 'CSV'
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  ESCAPE_UNENCLOSED_FIELD = NONE      -- read \ as an ordinary character (4 track names contain it)
  NULL_IF = ('NULL', '')              -- the word NULL or an empty field becomes a real NULL
  EMPTY_FIELD_AS_NULL = TRUE
  TRIM_SPACE = FALSE                  -- keep every value exactly as extracted
  ENCODING = 'UTF8'
  TIMESTAMP_FORMAT = 'YYYY-MM-DD HH24:MI:SS.FF3'
  ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE;

-- Snowflake-managed storage for the files.
-- IF NOT EXISTS means re-running this step never deletes files already uploaded.
CREATE STAGE IF NOT EXISTS CHINOOK_STAGE;

-- One RAW table per source table: same columns, same order, data types from the
-- SQL Server schema of each source table, NOT NULL where the source column is NOT NULL.
-- _SOURCE_FILE and _LOADED_AT record which file each row came from and when it was loaded.
CREATE OR REPLACE TABLE ALBUM (
  ALBUMID       INT NOT NULL,
  TITLE         VARCHAR(160) NOT NULL,
  ARTISTID      INT NOT NULL,
  _SOURCE_FILE  VARCHAR,
  _LOADED_AT    TIMESTAMP_LTZ
);

CREATE OR REPLACE TABLE ARTIST (
  ARTISTID      INT NOT NULL,
  NAME          VARCHAR(120),
  _SOURCE_FILE  VARCHAR,
  _LOADED_AT    TIMESTAMP_LTZ
);

CREATE OR REPLACE TABLE CUSTOMER (
  CUSTOMERID    INT NOT NULL,
  FIRSTNAME     VARCHAR(40) NOT NULL,
  LASTNAME      VARCHAR(20) NOT NULL,
  COMPANY       VARCHAR(80),
  ADDRESS       VARCHAR(70),
  CITY          VARCHAR(40),
  STATE         VARCHAR(40),
  COUNTRY       VARCHAR(40),
  POSTALCODE    VARCHAR(10),
  PHONE         VARCHAR(24),
  FAX           VARCHAR(24),
  EMAIL         VARCHAR(60) NOT NULL,
  SUPPORTREPID  INT,
  _SOURCE_FILE  VARCHAR,
  _LOADED_AT    TIMESTAMP_LTZ
);

CREATE OR REPLACE TABLE EMPLOYEE (
  EMPLOYEEID    INT NOT NULL,
  LASTNAME      VARCHAR(20) NOT NULL,
  FIRSTNAME     VARCHAR(20) NOT NULL,
  TITLE         VARCHAR(30),
  REPORTSTO     INT,
  BIRTHDATE     TIMESTAMP_NTZ,
  HIREDATE      TIMESTAMP_NTZ,
  ADDRESS       VARCHAR(70),
  CITY          VARCHAR(40),
  STATE         VARCHAR(40),
  COUNTRY       VARCHAR(40),
  POSTALCODE    VARCHAR(10),
  PHONE         VARCHAR(24),
  FAX           VARCHAR(24),
  EMAIL         VARCHAR(60),
  _SOURCE_FILE  VARCHAR,
  _LOADED_AT    TIMESTAMP_LTZ
);

CREATE OR REPLACE TABLE GENRE (
  GENREID       INT NOT NULL,
  NAME          VARCHAR(120),
  _SOURCE_FILE  VARCHAR,
  _LOADED_AT    TIMESTAMP_LTZ
);

CREATE OR REPLACE TABLE INVOICE (
  INVOICEID          INT NOT NULL,
  CUSTOMERID         INT NOT NULL,
  INVOICEDATE        TIMESTAMP_NTZ NOT NULL,
  BILLINGADDRESS     VARCHAR(70),
  BILLINGCITY        VARCHAR(40),
  BILLINGSTATE       VARCHAR(40),
  BILLINGCOUNTRY     VARCHAR(40),
  BILLINGPOSTALCODE  VARCHAR(10),
  TOTAL              NUMBER(10,2) NOT NULL,
  _SOURCE_FILE       VARCHAR,
  _LOADED_AT         TIMESTAMP_LTZ
);

CREATE OR REPLACE TABLE INVOICELINE (
  INVOICELINEID  INT NOT NULL,
  INVOICEID      INT NOT NULL,
  TRACKID        INT NOT NULL,
  UNITPRICE      NUMBER(10,2) NOT NULL,
  QUANTITY       INT NOT NULL,
  _SOURCE_FILE   VARCHAR,
  _LOADED_AT     TIMESTAMP_LTZ
);

CREATE OR REPLACE TABLE MEDIATYPE (
  MEDIATYPEID   INT NOT NULL,
  NAME          VARCHAR(120),
  _SOURCE_FILE  VARCHAR,
  _LOADED_AT    TIMESTAMP_LTZ
);

CREATE OR REPLACE TABLE TRACK (
  TRACKID       INT NOT NULL,
  NAME          VARCHAR(200) NOT NULL,
  ALBUMID       INT,
  MEDIATYPEID   INT NOT NULL,
  GENREID       INT,
  COMPOSER      VARCHAR(220),
  MILLISECONDS  INT NOT NULL,
  BYTES         INT,
  UNITPRICE     NUMBER(10,2) NOT NULL,
  _SOURCE_FILE  VARCHAR,
  _LOADED_AT    TIMESTAMP_LTZ
);


-- =====================================================================
-- STEP 3 · Upload the 9 CSV files to the stage
-- Run in: Command Prompt, Snowflake CLI (connection my_snowflake, role SYSADMIN)
-- PUT cannot run in Snowsight. Each file should report UPLOADED.
-- =====================================================================
/* Snowflake CLI: save the PUT below as 02_upload.sql in Documents\chinook_extract, then run

cd %USERPROFILE%\Documents\chinook_extract
snow sql -f 02_upload.sql -c my_snowflake

-- 02_upload.sql
PUT 'file://C:/Users/darre/Documents/chinook_extract/*.csv'
    @RAW.CHINOOK.CHINOOK_STAGE
    AUTO_COMPRESS = TRUE
    OVERWRITE = TRUE;
*/


-- =====================================================================
-- STEP 4 · Load each staged file into its RAW table
-- Run in: Snowsight (role SYSADMIN), one statement at a time
-- A-C check the staged files; D copies each file into its table.
-- ON_ERROR = ABORT_STATEMENT loads nothing for a table if any row fails.
-- =====================================================================
USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA RAW.CHINOOK;

-- A. Confirm the nine files are on the stage (note the exact names)
LIST @CHINOOK_STAGE;

-- B. Count the data rows in each staged file before loading (header row not counted)
SELECT METADATA$FILENAME AS file_name, COUNT(*) AS data_rows
FROM @CHINOOK_STAGE (FILE_FORMAT => 'RAW.CHINOOK.CHINOOK_CSV') t
GROUP BY METADATA$FILENAME
ORDER BY file_name;

-- C. Preview the trickiest file: commas, quotes, backslashes and NULLs in track.csv
SELECT t.$1 AS trackid, t.$2 AS name, t.$6 AS composer
FROM @CHINOOK_STAGE (FILE_FORMAT => 'RAW.CHINOOK.CHINOOK_CSV',
                     PATTERN => '^(.*/)?track[.]csv([.]gz)?$') t
WHERE t.$1 IN ('1', '2', '210', '3435')
ORDER BY TO_NUMBER(t.$1);

-- D. Load each table. PATTERN picks the one file for that table, with or without .gz.
--    ON_ERROR = 'ABORT_STATEMENT' loads nothing for a table if any row fails.

-- ALBUM  <-  album.csv  (expect 347 rows)
COPY INTO ALBUM (
    ALBUMID, TITLE, ARTISTID, _SOURCE_FILE, _LOADED_AT
)
FROM (
  SELECT
    t.$1, t.$2, t.$3, METADATA$FILENAME, METADATA$START_SCAN_TIME
  FROM @CHINOOK_STAGE t
)
PATTERN = '^(.*/)?album[.]csv([.]gz)?$'
FILE_FORMAT = (FORMAT_NAME = 'RAW.CHINOOK.CHINOOK_CSV')
ON_ERROR = 'ABORT_STATEMENT';

-- ARTIST  <-  artist.csv  (expect 275 rows)
COPY INTO ARTIST (
    ARTISTID, NAME, _SOURCE_FILE, _LOADED_AT
)
FROM (
  SELECT
    t.$1, t.$2, METADATA$FILENAME, METADATA$START_SCAN_TIME
  FROM @CHINOOK_STAGE t
)
PATTERN = '^(.*/)?artist[.]csv([.]gz)?$'
FILE_FORMAT = (FORMAT_NAME = 'RAW.CHINOOK.CHINOOK_CSV')
ON_ERROR = 'ABORT_STATEMENT';

-- CUSTOMER  <-  customer.csv  (expect 59 rows)
COPY INTO CUSTOMER (
    CUSTOMERID, FIRSTNAME, LASTNAME, COMPANY, ADDRESS, CITY, STATE, COUNTRY,
    POSTALCODE, PHONE, FAX, EMAIL, SUPPORTREPID, _SOURCE_FILE, _LOADED_AT
)
FROM (
  SELECT
    t.$1, t.$2, t.$3, t.$4, t.$5, t.$6, t.$7, t.$8, t.$9, t.$10, t.$11, t.$12,
    t.$13, METADATA$FILENAME, METADATA$START_SCAN_TIME
  FROM @CHINOOK_STAGE t
)
PATTERN = '^(.*/)?customer[.]csv([.]gz)?$'
FILE_FORMAT = (FORMAT_NAME = 'RAW.CHINOOK.CHINOOK_CSV')
ON_ERROR = 'ABORT_STATEMENT';

-- EMPLOYEE  <-  employee.csv  (expect 8 rows)
COPY INTO EMPLOYEE (
    EMPLOYEEID, LASTNAME, FIRSTNAME, TITLE, REPORTSTO, BIRTHDATE, HIREDATE,
    ADDRESS, CITY, STATE, COUNTRY, POSTALCODE, PHONE, FAX, EMAIL,
    _SOURCE_FILE, _LOADED_AT
)
FROM (
  SELECT
    t.$1, t.$2, t.$3, t.$4, t.$5,
    TO_TIMESTAMP_NTZ(t.$6, 'YYYY-MM-DD HH24:MI:SS.FF3'),
    TO_TIMESTAMP_NTZ(t.$7, 'YYYY-MM-DD HH24:MI:SS.FF3'), t.$8, t.$9, t.$10,
    t.$11, t.$12, t.$13, t.$14, t.$15, METADATA$FILENAME,
    METADATA$START_SCAN_TIME
  FROM @CHINOOK_STAGE t
)
PATTERN = '^(.*/)?employee[.]csv([.]gz)?$'
FILE_FORMAT = (FORMAT_NAME = 'RAW.CHINOOK.CHINOOK_CSV')
ON_ERROR = 'ABORT_STATEMENT';

-- GENRE  <-  genre.csv  (expect 25 rows)
COPY INTO GENRE (
    GENREID, NAME, _SOURCE_FILE, _LOADED_AT
)
FROM (
  SELECT
    t.$1, t.$2, METADATA$FILENAME, METADATA$START_SCAN_TIME
  FROM @CHINOOK_STAGE t
)
PATTERN = '^(.*/)?genre[.]csv([.]gz)?$'
FILE_FORMAT = (FORMAT_NAME = 'RAW.CHINOOK.CHINOOK_CSV')
ON_ERROR = 'ABORT_STATEMENT';

-- INVOICE  <-  invoice.csv  (expect 412 rows)
COPY INTO INVOICE (
    INVOICEID, CUSTOMERID, INVOICEDATE, BILLINGADDRESS, BILLINGCITY,
    BILLINGSTATE, BILLINGCOUNTRY, BILLINGPOSTALCODE, TOTAL, _SOURCE_FILE,
    _LOADED_AT
)
FROM (
  SELECT
    t.$1, t.$2, TO_TIMESTAMP_NTZ(t.$3, 'YYYY-MM-DD HH24:MI:SS.FF3'), t.$4,
    t.$5, t.$6, t.$7, t.$8, t.$9, METADATA$FILENAME, METADATA$START_SCAN_TIME
  FROM @CHINOOK_STAGE t
)
PATTERN = '^(.*/)?invoice[.]csv([.]gz)?$'
FILE_FORMAT = (FORMAT_NAME = 'RAW.CHINOOK.CHINOOK_CSV')
ON_ERROR = 'ABORT_STATEMENT';

-- INVOICELINE  <-  invoiceline.csv  (expect 2,240 rows)
COPY INTO INVOICELINE (
    INVOICELINEID, INVOICEID, TRACKID, UNITPRICE, QUANTITY, _SOURCE_FILE,
    _LOADED_AT
)
FROM (
  SELECT
    t.$1, t.$2, t.$3, t.$4, t.$5, METADATA$FILENAME, METADATA$START_SCAN_TIME
  FROM @CHINOOK_STAGE t
)
PATTERN = '^(.*/)?invoiceline[.]csv([.]gz)?$'
FILE_FORMAT = (FORMAT_NAME = 'RAW.CHINOOK.CHINOOK_CSV')
ON_ERROR = 'ABORT_STATEMENT';

-- MEDIATYPE  <-  mediatype.csv  (expect 5 rows)
COPY INTO MEDIATYPE (
    MEDIATYPEID, NAME, _SOURCE_FILE, _LOADED_AT
)
FROM (
  SELECT
    t.$1, t.$2, METADATA$FILENAME, METADATA$START_SCAN_TIME
  FROM @CHINOOK_STAGE t
)
PATTERN = '^(.*/)?mediatype[.]csv([.]gz)?$'
FILE_FORMAT = (FORMAT_NAME = 'RAW.CHINOOK.CHINOOK_CSV')
ON_ERROR = 'ABORT_STATEMENT';

-- TRACK  <-  track.csv  (expect 3,503 rows)
COPY INTO TRACK (
    TRACKID, NAME, ALBUMID, MEDIATYPEID, GENREID, COMPOSER, MILLISECONDS,
    BYTES, UNITPRICE, _SOURCE_FILE, _LOADED_AT
)
FROM (
  SELECT
    t.$1, t.$2, t.$3, t.$4, t.$5, t.$6, t.$7, t.$8, t.$9, METADATA$FILENAME,
    METADATA$START_SCAN_TIME
  FROM @CHINOOK_STAGE t
)
PATTERN = '^(.*/)?track[.]csv([.]gz)?$'
FILE_FORMAT = (FORMAT_NAME = 'RAW.CHINOOK.CHINOOK_CSV')
ON_ERROR = 'ABORT_STATEMENT';


-- =====================================================================
-- STEP 5 · Verify RAW.CHINOOK against the source (52 checks)
-- Run in: Snowsight (role SYSADMIN)
-- Row counts, unique keys, totals, NULL counts, tricky values and every
-- foreign key. Result: 52/52 PASS.
-- =====================================================================
-- One row per check. Expected row counts and keys come from the SQL Server source;
-- totals, NULL counts and sample values come from the CSV data.
USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA RAW.CHINOOK;

WITH checks AS (
    SELECT 1 AS n, 'ALBUM row count' AS check_name, 347 AS expected,
           (SELECT COUNT(*)
              FROM ALBUM) AS actual

    UNION ALL SELECT 2, 'ARTIST row count', 275,
           (SELECT COUNT(*)
              FROM ARTIST)

    UNION ALL SELECT 3, 'CUSTOMER row count', 59,
           (SELECT COUNT(*)
              FROM CUSTOMER)

    UNION ALL SELECT 4, 'EMPLOYEE row count', 8,
           (SELECT COUNT(*)
              FROM EMPLOYEE)

    UNION ALL SELECT 5, 'GENRE row count', 25,
           (SELECT COUNT(*)
              FROM GENRE)

    UNION ALL SELECT 6, 'INVOICE row count', 412,
           (SELECT COUNT(*)
              FROM INVOICE)

    UNION ALL SELECT 7, 'INVOICELINE row count', 2240,
           (SELECT COUNT(*)
              FROM INVOICELINE)

    UNION ALL SELECT 8, 'MEDIATYPE row count', 5,
           (SELECT COUNT(*)
              FROM MEDIATYPE)

    UNION ALL SELECT 9, 'TRACK row count', 3503,
           (SELECT COUNT(*)
              FROM TRACK)

    UNION ALL SELECT 10, 'Duplicate ALBUMID values in ALBUM', 0,
           (SELECT COUNT(*) - COUNT(DISTINCT ALBUMID)
              FROM ALBUM)

    UNION ALL SELECT 11, 'Duplicate ARTISTID values in ARTIST', 0,
           (SELECT COUNT(*) - COUNT(DISTINCT ARTISTID)
              FROM ARTIST)

    UNION ALL SELECT 12, 'Duplicate CUSTOMERID values in CUSTOMER', 0,
           (SELECT COUNT(*) - COUNT(DISTINCT CUSTOMERID)
              FROM CUSTOMER)

    UNION ALL SELECT 13, 'Duplicate EMPLOYEEID values in EMPLOYEE', 0,
           (SELECT COUNT(*) - COUNT(DISTINCT EMPLOYEEID)
              FROM EMPLOYEE)

    UNION ALL SELECT 14, 'Duplicate GENREID values in GENRE', 0,
           (SELECT COUNT(*) - COUNT(DISTINCT GENREID)
              FROM GENRE)

    UNION ALL SELECT 15, 'Duplicate INVOICEID values in INVOICE', 0,
           (SELECT COUNT(*) - COUNT(DISTINCT INVOICEID)
              FROM INVOICE)

    UNION ALL SELECT 16, 'Duplicate INVOICELINEID values in INVOICELINE', 0,
           (SELECT COUNT(*) - COUNT(DISTINCT INVOICELINEID)
              FROM INVOICELINE)

    UNION ALL SELECT 17, 'Duplicate MEDIATYPEID values in MEDIATYPE', 0,
           (SELECT COUNT(*) - COUNT(DISTINCT MEDIATYPEID)
              FROM MEDIATYPE)

    UNION ALL SELECT 18, 'Duplicate TRACKID values in TRACK', 0,
           (SELECT COUNT(*) - COUNT(DISTINCT TRACKID)
              FROM TRACK)

    UNION ALL SELECT 19, 'Sum of INVOICELINE UnitPrice x Quantity', 2328.60,
           (SELECT SUM(UNITPRICE * QUANTITY)
              FROM INVOICELINE)

    UNION ALL SELECT 20, 'Sum of INVOICE Total', 2328.60,
           (SELECT SUM(TOTAL)
              FROM INVOICE)

    UNION ALL SELECT 21, 'NULLs in CUSTOMER.COMPANY', 49,
           (SELECT COUNT(*)
              FROM CUSTOMER
             WHERE COMPANY IS NULL)

    UNION ALL SELECT 22, 'NULLs in CUSTOMER.STATE', 29,
           (SELECT COUNT(*)
              FROM CUSTOMER
             WHERE STATE IS NULL)

    UNION ALL SELECT 23, 'NULLs in CUSTOMER.POSTALCODE', 4,
           (SELECT COUNT(*)
              FROM CUSTOMER
             WHERE POSTALCODE IS NULL)

    UNION ALL SELECT 24, 'NULLs in CUSTOMER.PHONE', 1,
           (SELECT COUNT(*)
              FROM CUSTOMER
             WHERE PHONE IS NULL)

    UNION ALL SELECT 25, 'NULLs in CUSTOMER.FAX', 47,
           (SELECT COUNT(*)
              FROM CUSTOMER
             WHERE FAX IS NULL)

    UNION ALL SELECT 26, 'NULLs in EMPLOYEE.REPORTSTO', 1,
           (SELECT COUNT(*)
              FROM EMPLOYEE
             WHERE REPORTSTO IS NULL)

    UNION ALL SELECT 27, 'NULLs in INVOICE.BILLINGSTATE', 202,
           (SELECT COUNT(*)
              FROM INVOICE
             WHERE BILLINGSTATE IS NULL)

    UNION ALL SELECT 28, 'NULLs in INVOICE.BILLINGPOSTALCODE', 28,
           (SELECT COUNT(*)
              FROM INVOICE
             WHERE BILLINGPOSTALCODE IS NULL)

    UNION ALL SELECT 29, 'NULLs in TRACK.COMPOSER', 978,
           (SELECT COUNT(*)
              FROM TRACK
             WHERE COMPOSER IS NULL)

    UNION ALL SELECT 30, 'CUSTOMER 49 first name is ''Stanisław''', 1,
           (SELECT COUNT(*)
              FROM CUSTOMER
             WHERE CUSTOMERID = 49
               AND FIRSTNAME = 'Stanisław')

    UNION ALL SELECT 31, 'CUSTOMER 54 city length, trailing space kept', 10,
           (SELECT LENGTH(CITY)
              FROM CUSTOMER
             WHERE CUSTOMERID = 54)

    UNION ALL SELECT 32, 'TRACK 210 name keeps its double quotes', 1,
           (SELECT COUNT(*)
              FROM TRACK
             WHERE TRACKID = 210
               AND NAME = 'Texto "Verdade Tropical"')

    UNION ALL SELECT 33, 'TRACK 3435 name keeps both backslashes', 2,
           (SELECT LENGTH(NAME) - LENGTH(REPLACE(NAME, CHR(92), ''))
              FROM TRACK
             WHERE TRACKID = 3435)

    UNION ALL SELECT 34, 'First invoice date is 2009-01-01', 1,
           (SELECT IFF(MIN(INVOICEDATE) = TO_TIMESTAMP_NTZ('2009-01-01 00:00:00'), 1, 0)
              FROM INVOICE)

    UNION ALL SELECT 35, 'Last invoice date is 2013-12-22', 1,
           (SELECT IFF(MAX(INVOICEDATE) = TO_TIMESTAMP_NTZ('2013-12-22 00:00:00'), 1, 0)
              FROM INVOICE)

    UNION ALL SELECT 36, 'INVOICELINE.INVOICEID values missing from INVOICE', 0,
           (SELECT COUNT(*)
              FROM INVOICELINE c
             WHERE c.INVOICEID IS NOT NULL
               AND c.INVOICEID NOT IN (SELECT INVOICEID FROM INVOICE))

    UNION ALL SELECT 37, 'INVOICELINE.TRACKID values missing from TRACK', 0,
           (SELECT COUNT(*)
              FROM INVOICELINE c
             WHERE c.TRACKID IS NOT NULL
               AND c.TRACKID NOT IN (SELECT TRACKID FROM TRACK))

    UNION ALL SELECT 38, 'INVOICE.CUSTOMERID values missing from CUSTOMER', 0,
           (SELECT COUNT(*)
              FROM INVOICE c
             WHERE c.CUSTOMERID IS NOT NULL
               AND c.CUSTOMERID NOT IN (SELECT CUSTOMERID FROM CUSTOMER))

    UNION ALL SELECT 39, 'CUSTOMER.SUPPORTREPID values missing from EMPLOYEE', 0,
           (SELECT COUNT(*)
              FROM CUSTOMER c
             WHERE c.SUPPORTREPID IS NOT NULL
               AND c.SUPPORTREPID NOT IN (SELECT EMPLOYEEID FROM EMPLOYEE))

    UNION ALL SELECT 40, 'TRACK.ALBUMID values missing from ALBUM', 0,
           (SELECT COUNT(*)
              FROM TRACK c
             WHERE c.ALBUMID IS NOT NULL
               AND c.ALBUMID NOT IN (SELECT ALBUMID FROM ALBUM))

    UNION ALL SELECT 41, 'TRACK.GENREID values missing from GENRE', 0,
           (SELECT COUNT(*)
              FROM TRACK c
             WHERE c.GENREID IS NOT NULL
               AND c.GENREID NOT IN (SELECT GENREID FROM GENRE))

    UNION ALL SELECT 42, 'TRACK.MEDIATYPEID values missing from MEDIATYPE', 0,
           (SELECT COUNT(*)
              FROM TRACK c
             WHERE c.MEDIATYPEID IS NOT NULL
               AND c.MEDIATYPEID NOT IN (SELECT MEDIATYPEID FROM MEDIATYPE))

    UNION ALL SELECT 43, 'ALBUM.ARTISTID values missing from ARTIST', 0,
           (SELECT COUNT(*)
              FROM ALBUM c
             WHERE c.ARTISTID IS NOT NULL
               AND c.ARTISTID NOT IN (SELECT ARTISTID FROM ARTIST))

    UNION ALL SELECT 44, 'ALBUM rows missing _SOURCE_FILE or _LOADED_AT', 0,
           (SELECT COUNT(*)
              FROM ALBUM
             WHERE _SOURCE_FILE IS NULL OR _LOADED_AT IS NULL)

    UNION ALL SELECT 45, 'ARTIST rows missing _SOURCE_FILE or _LOADED_AT', 0,
           (SELECT COUNT(*)
              FROM ARTIST
             WHERE _SOURCE_FILE IS NULL OR _LOADED_AT IS NULL)

    UNION ALL SELECT 46, 'CUSTOMER rows missing _SOURCE_FILE or _LOADED_AT', 0,
           (SELECT COUNT(*)
              FROM CUSTOMER
             WHERE _SOURCE_FILE IS NULL OR _LOADED_AT IS NULL)

    UNION ALL SELECT 47, 'EMPLOYEE rows missing _SOURCE_FILE or _LOADED_AT', 0,
           (SELECT COUNT(*)
              FROM EMPLOYEE
             WHERE _SOURCE_FILE IS NULL OR _LOADED_AT IS NULL)

    UNION ALL SELECT 48, 'GENRE rows missing _SOURCE_FILE or _LOADED_AT', 0,
           (SELECT COUNT(*)
              FROM GENRE
             WHERE _SOURCE_FILE IS NULL OR _LOADED_AT IS NULL)

    UNION ALL SELECT 49, 'INVOICE rows missing _SOURCE_FILE or _LOADED_AT', 0,
           (SELECT COUNT(*)
              FROM INVOICE
             WHERE _SOURCE_FILE IS NULL OR _LOADED_AT IS NULL)

    UNION ALL SELECT 50, 'INVOICELINE rows missing _SOURCE_FILE or _LOADED_AT', 0,
           (SELECT COUNT(*)
              FROM INVOICELINE
             WHERE _SOURCE_FILE IS NULL OR _LOADED_AT IS NULL)

    UNION ALL SELECT 51, 'MEDIATYPE rows missing _SOURCE_FILE or _LOADED_AT', 0,
           (SELECT COUNT(*)
              FROM MEDIATYPE
             WHERE _SOURCE_FILE IS NULL OR _LOADED_AT IS NULL)

    UNION ALL SELECT 52, 'TRACK rows missing _SOURCE_FILE or _LOADED_AT', 0,
           (SELECT COUNT(*)
              FROM TRACK
             WHERE _SOURCE_FILE IS NULL OR _LOADED_AT IS NULL)
)
SELECT n, check_name, expected, actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS result
FROM checks
ORDER BY n;


-- =====================================================================
-- STEP 6 · Build the star schema with dbt
-- Run in: dbt platform Studio IDE (project ddramasr, repo DarrelRamasray/ist722dbt)
-- Setup: Project subdirectory = music_sales. Development credentials use
-- role ACCOUNTADMIN, warehouse TRANSFORMING, database ANALYTICS, schema
-- dbt_dramasray, with key-pair sign-in (the private key is never stored
-- in a repository). +schema: chinook puts every table in
-- ANALYTICS.DBT_DRAMASRAY_CHINOOK.
-- Layout: this repo groups the same files by process in dbt/chinook_dw/;
-- the dbt platform copy keeps them all in music_sales/models/chinook/.
-- Run: dbt build. Music Sales alone is 6 models + 51 tests.
-- Today, with all three processes: 9 models + 79 tests = 88 PASS.
-- =====================================================================

-- ---- 6A · Check dbt's role can read RAW and build in ANALYTICS (Snowsight) ---
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE TRANSFORMING;
SELECT COUNT(*) AS invoiceline_rows FROM RAW.CHINOOK.INVOICELINE;  -- expect 2240
SHOW GRANTS ON DATABASE ANALYTICS;  -- ACCOUNTADMIN owns ANALYTICS, so no extra grants were needed

-- ---- 6B · dbt_project.yml and models/chinook/_chinook__sources.yml ---
/* dbt_project.yml

name: 'chinook_dw'
version: '1.0.0'

# The dbt platform supplies the connection, so this name isn't used there.
profile: 'default'

model-paths: ["models"]

clean-targets:
  - "target"
  - "dbt_packages"

models:
  chinook_dw:
    chinook:
      # Every model under models/chinook, in every subfolder, is built as a
      # table in <dev schema>_CHINOOK, e.g. DBT_DRAMASRAY_CHINOOK.
      +materialized: table
      +schema: chinook
*/
/* models/chinook/_chinook__sources.yml (Music Sales tables; Track Playtime and Employee Hire add theirs)

version: 2

sources:
  - name: chinook
    description: "Chinook tables copied unchanged from the school SQL Server."
    database: RAW
    schema: CHINOOK
    tables:
      - name: album
      - name: artist
      - name: customer
      - name: employee
      - name: genre
      - name: invoice
      - name: invoiceline
      - name: mediatype
      - name: track
*/

-- ---- 6C · models/chinook/shared_dimensions/dim_customer.sql · one row per customer (59) ---
{{ config(materialized='table') }}

with stg_customer as (
    select * from {{ source('chinook', 'customer') }}
)

select
    customerid     as customerkey,
    customerid     as customerid,
    firstname      as firstname,
    lastname       as lastname,
    company        as company,
    address        as address,
    city           as city,
    state          as state,
    country        as country,
    postalcode     as postalcode,
    phone          as phone,
    fax            as fax,
    email          as email,
    supportrepid   as supportrepid

from stg_customer

-- ---- 6D · models/chinook/shared_dimensions/dim_employee.sql · one row per employee (8) ---
{{ config(materialized='table') }}

with stg_employee as (
    select * from {{ source('chinook', 'employee') }}
)

select
    employeeid   as employeekey,
    employeeid   as employeeid,
    lastname     as lastname,
    firstname    as firstname,
    title        as title,
    reportsto    as reportsto,
    birthdate    as birthdate,
    hiredate     as hiredate,
    address      as address,
    city         as city,
    state        as state,
    country      as country,
    postalcode   as postalcode,
    phone        as phone,
    fax          as fax,
    email        as email

from stg_employee

-- ---- 6E · models/chinook/01_music_sales/dim_invoice.sql · one row per invoice (412) ---
{{ config(materialized='table') }}

with stg_invoice as (
    select * from {{ source('chinook', 'invoice') }}
)

select
    invoiceid           as invoicekey,
    invoiceid           as invoiceid,
    customerid          as customerid,
    invoicedate         as invoicedate,
    billingaddress      as billingaddress,
    billingcity         as billingcity,
    billingstate        as billingstate,
    billingcountry      as billingcountry,
    billingpostalcode   as billingpostalcode,
    total               as total

from stg_invoice

-- ---- 6F · models/chinook/shared_dimensions/dim_track.sql · one row per track (3,503), joins album, artist, genre, media type ---
{{ config(materialized='table') }}

with stg_track as (
    select * from {{ source('chinook', 'track') }}
),

stg_album as (
    select * from {{ source('chinook', 'album') }}
),

stg_artist as (
    select * from {{ source('chinook', 'artist') }}
),

stg_genre as (
    select * from {{ source('chinook', 'genre') }}
),

stg_mediatype as (
    select * from {{ source('chinook', 'mediatype') }}
)

select
    t.trackid        as trackkey,
    t.trackid        as trackid,
    t.name           as trackname,
    al.title         as album,
    a.name           as artist,
    m.name           as mediatype,
    g.name           as genre,
    t.composer       as composer,
    t.milliseconds   as lengthms,
    t.bytes          as sizebytes,
    t.unitprice      as unitprice

from stg_track as t

left join stg_mediatype as m
    on t.mediatypeid = m.mediatypeid

left join stg_genre as g
    on t.genreid = g.genreid

left join stg_album as al
    on al.albumid = t.albumid

left join stg_artist as a
    on a.artistid = al.artistid

-- ---- 6G · models/chinook/shared_dimensions/dim_date.sql · one row per day, full years from first to last event date ---
-- Current version: Employee Hire widened the range to 2002-01-01 .. 2013-12-31
-- (4,383 days). Built for Milestone 2 from invoice dates only (2009-2013).
{{ config(materialized='table') }}

with eventdates as (
    select cast(invoicedate as date) as d
    from {{ source('chinook', 'invoice') }}

    union all

    select cast(hiredate as date) as d
    from {{ source('chinook', 'employee') }}
    where hiredate is not null
),

bounds as (
    select
        date_from_parts(year(min(d)), 1, 1)   as firstdate,
        date_from_parts(year(max(d)), 12, 31) as lastdate
    from eventdates
),

-- 10,000 candidate days (about 27 years); the WHERE clause at the bottom
-- keeps only the days up to the last date
spine as (
    select
        dateadd(day, row_number() over (order by seq4()) - 1, b.firstdate) as d,
        b.lastdate
    from table(generator(rowcount => 10000))
    cross join bounds as b
)

select
    d                                         as datekey,
    cast(year(d) as int)                      as year,
    cast(quarter(d) as int)                   as quarter,
    cast(month(d) as int)                     as month,
    cast(
        case month(d)
            when 1  then 'January'
            when 2  then 'February'
            when 3  then 'March'
            when 4  then 'April'
            when 5  then 'May'
            when 6  then 'June'
            when 7  then 'July'
            when 8  then 'August'
            when 9  then 'September'
            when 10 then 'October'
            when 11 then 'November'
            else 'December'
        end as varchar(9))                    as monthname,
    cast(day(d) as int)                       as dayofmonth,
    cast(dayofweekiso(d) as int)              as dayofweek,
    cast(
        case dayofweekiso(d)
            when 1 then 'Monday'
            when 2 then 'Tuesday'
            when 3 then 'Wednesday'
            when 4 then 'Thursday'
            when 5 then 'Friday'
            when 6 then 'Saturday'
            else 'Sunday'
        end as varchar(9))                    as dayname

from spine
where d <= lastdate

-- ---- 6H · models/chinook/01_music_sales/fact_sale.sql · one row per invoice line (2,240) ---
{{ config(materialized='table') }}

with stg_invoiceline as (
    select * from {{ source('chinook', 'invoiceline') }}
),

stg_invoice as (
    select * from {{ source('chinook', 'invoice') }}
),

stg_customer as (
    select * from {{ source('chinook', 'customer') }}
)

select
    il.invoicelineid                                   as invoicelineid,
    il.invoiceid                                       as invoiceid,
    il.invoiceid                                       as invoicekey,
    il.trackid                                         as trackkey,
    i.customerid                                       as customerkey,
    c.supportrepid                                     as employeekey,
    cast(i.invoicedate as date)                        as invoicedatekey,
    il.unitprice                                       as unitprice,
    il.quantity                                        as quantity,
    cast(il.unitprice * il.quantity as number(21, 2))  as saleamount

from stg_invoiceline as il

-- Inner joins lose no rows: InvoiceLine.InvoiceId and Invoice.CustomerId
-- are NOT NULL with enforced foreign keys in the SQL Server source
inner join stg_invoice as i
    on i.invoiceid = il.invoiceid

inner join stg_customer as c
    on c.customerid = i.customerid

-- ---- 6I · Tests: 51 (29 on the shared dimensions + 22 on Music Sales) ---
-- In the dbt platform these two files are one, _chinook__models.yml.
/* models/chinook/shared_dimensions/_shared_dimensions__models.yml

version: 2

models:
  - name: dim_date
    description: "One row per calendar day, for every full calendar year from the earliest invoice or hire date to the latest (2002-01-01 to 2013-12-31 today)."
    columns:
      - name: datekey
        description: "Dimension key; the calendar date"
        data_tests:
          - unique
          - not_null
      - name: year
        description: "Calendar year"
        data_tests:
          - not_null
      - name: quarter
        description: "Calendar quarter (1-4)"
        data_tests:
          - not_null
      - name: month
        description: "Month number (1-12)"
        data_tests:
          - not_null
      - name: monthname
        description: "Month name"
        data_tests:
          - not_null
      - name: dayofmonth
        description: "Day of the month"
        data_tests:
          - not_null
      - name: dayofweek
        description: "Day of the week (1 = Monday)"
        data_tests:
          - not_null
      - name: dayname
        description: "Day name"
        data_tests:
          - not_null

  - name: dim_employee
    description: "One row per employee."
    columns:
      - name: employeekey
        description: "Dimension key"
        data_tests:
          - unique
          - not_null
      - name: employeeid
        description: "Primary key of the source system table"
        data_tests:
          - unique
          - not_null
      - name: lastname
        description: "Employee's last name"
        data_tests:
          - not_null
      - name: firstname
        description: "Employee's first name"
        data_tests:
          - not_null
      - name: title
        description: "Employee's job title"
      - name: reportsto
        description: "Employee ID of the employee's manager"
      - name: birthdate
        description: "Employee's birth date"
      - name: hiredate
        description: "Employee's hire date"
      - name: address
        description: "Employee's street address"
      - name: city
        description: "Employee's city"
      - name: state
        description: "Employee's state or province"
      - name: country
        description: "Employee's country"
      - name: postalcode
        description: "Employee's postal code"
      - name: phone
        description: "Employee's phone number"
      - name: fax
        description: "Employee's fax number"
      - name: email
        description: "Employee's email address"

  - name: dim_customer
    description: "One row per customer."
    columns:
      - name: customerkey
        description: "Dimension key"
        data_tests:
          - unique
          - not_null
      - name: customerid
        description: "Primary key of the source system table"
        data_tests:
          - unique
          - not_null
      - name: firstname
        description: "Customer's first name"
        data_tests:
          - not_null
      - name: lastname
        description: "Customer's last name"
        data_tests:
          - not_null
      - name: company
        description: "Customer's company"
      - name: address
        description: "Customer's street address"
      - name: city
        description: "Customer's city"
      - name: state
        description: "Customer's state or province"
      - name: country
        description: "Customer's country"
      - name: postalcode
        description: "Customer's postal code"
      - name: phone
        description: "Customer's phone number"
      - name: fax
        description: "Customer's fax number"
      - name: email
        description: "Customer's email address"
        data_tests:
          - not_null
      - name: supportrepid
        description: "Employee ID of the customer's support rep"

  - name: dim_track
    description: "One row per track."
    columns:
      - name: trackkey
        description: "Dimension key"
        data_tests:
          - unique
          - not_null
      - name: trackid
        description: "Primary key of the source system table"
        data_tests:
          - unique
          - not_null
      - name: trackname
        description: "Name of the track"
        data_tests:
          - not_null
      - name: album
        description: "Album the track belongs to"
      - name: artist
        description: "Artist of the track"
      - name: mediatype
        description: "Track's media type"
      - name: genre
        description: "Track's genre"
      - name: composer
        description: "Composer of the track"
      - name: lengthms
        description: "Length of track in milliseconds"
        data_tests:
          - not_null
      - name: sizebytes
        description: "Size of track in bytes"
      - name: unitprice
        description: "Price of the track"
        data_tests:
          - not_null
*/
/* models/chinook/01_music_sales/_music_sales__models.yml

version: 2

models:
  - name: fact_sale
    description: "One row per track sold on an invoice line; each row is unique by invoicelineid."
    columns:
      - name: invoicelineid
        description: "Source key used for drill-through"
        data_tests:
          - unique
          - not_null
      - name: invoiceid
        description: "Degenerate dimension; the invoice number"
        data_tests:
          - not_null
      - name: invoicekey
        description: "Dimension FK for dim_invoice"
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('dim_invoice')
                field: invoicekey
      - name: trackkey
        description: "Dimension FK for dim_track; Gives name, genre, media type, artist, album"
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('dim_track')
                field: trackkey
      - name: customerkey
        description: "Dimension FK for dim_customer"
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('dim_customer')
                field: customerkey
      - name: employeekey
        description: "Dimension FK for dim_employee; the customer's support rep"
        data_tests:
          - relationships:
              arguments:
                to: ref('dim_employee')
                field: employeekey
      - name: invoicedatekey
        description: "Dimension FK for dim_date; the invoice date"
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('dim_date')
                field: datekey
      - name: unitprice
        description: "Unit price of the track; Non-additive; Unit price is used for averaging."
        data_tests:
          - not_null
      - name: quantity
        description: "Number of units sold; Additive"
        data_tests:
          - not_null
      - name: saleamount
        description: "Unit price * quantity; Additive"
        data_tests:
          - not_null

  - name: dim_invoice
    description: "One row per invoice."
    columns:
      - name: invoicekey
        description: "Dimension key"
        data_tests:
          - unique
          - not_null
      - name: invoiceid
        description: "Primary key of the source system table"
        data_tests:
          - unique
          - not_null
      - name: customerid
        description: "Customer ID of the customer billed"
        data_tests:
          - not_null
      - name: invoicedate
        description: "Date of the invoice"
        data_tests:
          - not_null
      - name: billingaddress
        description: "Billing street address"
      - name: billingcity
        description: "Billing city"
      - name: billingstate
        description: "Billing state or province"
      - name: billingcountry
        description: "Billing country"
      - name: billingpostalcode
        description: "Billing postal code"
      - name: total
        description: "Invoice total"
        data_tests:
          - not_null
*/


-- =====================================================================
-- STEP 7 · Verify the star schema (23 checks)
-- Run in: Snowsight (role ACCOUNTADMIN, warehouse TRANSFORMING)
-- Row counts, totals, orphan keys and data types against RAW.
-- Checks 6, 16 and 17 were updated for the widened dim_date. Result: 23/23 PASS.
-- =====================================================================
USE ROLE ACCOUNTADMIN;
SHOW TABLES LIKE 'FACT_SALE' IN ACCOUNT;   -- expect ANALYTICS.DBT_DRAMASRAY_CHINOOK
USE WAREHOUSE TRANSFORMING;
USE SCHEMA ANALYTICS.DBT_DRAMASRAY_CHINOOK;

WITH checks AS (
    SELECT 1 AS n, 'FACT_SALE row count' AS check_name, 2240 AS expected,
           (SELECT COUNT(*)
              FROM FACT_SALE) AS actual

    UNION ALL SELECT 2, 'DIM_INVOICE row count', 412,
           (SELECT COUNT(*)
              FROM DIM_INVOICE)

    UNION ALL SELECT 3, 'DIM_CUSTOMER row count', 59,
           (SELECT COUNT(*)
              FROM DIM_CUSTOMER)

    UNION ALL SELECT 4, 'DIM_EMPLOYEE row count', 8,
           (SELECT COUNT(*)
              FROM DIM_EMPLOYEE)

    UNION ALL SELECT 5, 'DIM_TRACK row count', 3503,
           (SELECT COUNT(*)
              FROM DIM_TRACK)

    UNION ALL SELECT 6, 'DIM_DATE row count (2002-01-01 to 2013-12-31)', 4383,
           (SELECT COUNT(*)
              FROM DIM_DATE)

    UNION ALL SELECT 7, 'Sum of FACT_SALE.SALEAMOUNT', 2328.60,
           (SELECT SUM(SALEAMOUNT)
              FROM FACT_SALE)

    UNION ALL SELECT 8, 'Sum of FACT_SALE.QUANTITY', 2240,
           (SELECT SUM(QUANTITY)
              FROM FACT_SALE)

    UNION ALL SELECT 9, 'FACT_SALE.INVOICEKEY values missing from DIM_INVOICE', 0,
           (SELECT COUNT(*)
              FROM FACT_SALE f
             WHERE f.INVOICEKEY NOT IN (SELECT INVOICEKEY FROM DIM_INVOICE))

    UNION ALL SELECT 10, 'FACT_SALE.TRACKKEY values missing from DIM_TRACK', 0,
           (SELECT COUNT(*)
              FROM FACT_SALE f
             WHERE f.TRACKKEY NOT IN (SELECT TRACKKEY FROM DIM_TRACK))

    UNION ALL SELECT 11, 'FACT_SALE.CUSTOMERKEY values missing from DIM_CUSTOMER', 0,
           (SELECT COUNT(*)
              FROM FACT_SALE f
             WHERE f.CUSTOMERKEY NOT IN (SELECT CUSTOMERKEY FROM DIM_CUSTOMER))

    UNION ALL SELECT 12, 'FACT_SALE.EMPLOYEEKEY values missing from DIM_EMPLOYEE', 0,
           (SELECT COUNT(*)
              FROM FACT_SALE f
             WHERE f.EMPLOYEEKEY IS NOT NULL
               AND f.EMPLOYEEKEY NOT IN (SELECT EMPLOYEEKEY FROM DIM_EMPLOYEE))

    UNION ALL SELECT 13, 'FACT_SALE.INVOICEDATEKEY values missing from DIM_DATE', 0,
           (SELECT COUNT(*)
              FROM FACT_SALE f
             WHERE f.INVOICEDATEKEY NOT IN (SELECT DATEKEY FROM DIM_DATE))

    UNION ALL SELECT 14, 'FACT_SALE rows with no EMPLOYEEKEY', 0,
           (SELECT COUNT(*)
              FROM FACT_SALE
             WHERE EMPLOYEEKEY IS NULL)

    UNION ALL SELECT 15, 'Distinct invoice dates in FACT_SALE', 354,
           (SELECT COUNT(DISTINCT INVOICEDATEKEY)
              FROM FACT_SALE)

    UNION ALL SELECT 16, 'DIM_DATE first day is 2002-01-01', 1,
           (SELECT IFF(MIN(DATEKEY) = TO_DATE('2002-01-01'), 1, 0)
              FROM DIM_DATE)

    UNION ALL SELECT 17, 'DIM_DATE last day is 2013-12-31', 1,
           (SELECT IFF(MAX(DATEKEY) = TO_DATE('2013-12-31'), 1, 0)
              FROM DIM_DATE)

    UNION ALL SELECT 18, 'DIM_DATE has no missing days', 1,
           (SELECT IFF(COUNT(*) = DATEDIFF(day, MIN(DATEKEY), MAX(DATEKEY)) + 1, 1, 0)
              FROM DIM_DATE)

    UNION ALL SELECT 19, '2009-01-01 is a Thursday (dayofweek 4)', 1,
           (SELECT COUNT(*)
              FROM DIM_DATE
             WHERE DATEKEY = TO_DATE('2009-01-01')
               AND DAYOFWEEK = 4
               AND DAYNAME = 'Thursday')

    UNION ALL SELECT 20, '2013-12-22 is a Sunday (dayofweek 7)', 1,
           (SELECT COUNT(*)
              FROM DIM_DATE
             WHERE DATEKEY = TO_DATE('2013-12-22')
               AND DAYOFWEEK = 7
               AND DAYNAME = 'Sunday')

    UNION ALL SELECT 21, 'DIM_TRACK 1 artist is AC/DC', 1,
           (SELECT COUNT(*)
              FROM DIM_TRACK
             WHERE TRACKKEY = 1
               AND ARTIST = 'AC/DC')

    UNION ALL SELECT 22, 'FACT_SALE.SALEAMOUNT type is NUMBER(21,2)', 1,
           (SELECT IFF(NUMERIC_PRECISION = 21 AND NUMERIC_SCALE = 2, 1, 0)
              FROM INFORMATION_SCHEMA.COLUMNS
             WHERE TABLE_SCHEMA = CURRENT_SCHEMA()
               AND TABLE_NAME = 'FACT_SALE'
               AND COLUMN_NAME = 'SALEAMOUNT')

    UNION ALL SELECT 23, 'FACT_SALE.INVOICEDATEKEY type is DATE', 1,
           (SELECT IFF(DATA_TYPE = 'DATE', 1, 0)
              FROM INFORMATION_SCHEMA.COLUMNS
             WHERE TABLE_SCHEMA = CURRENT_SCHEMA()
               AND TABLE_NAME = 'FACT_SALE'
               AND COLUMN_NAME = 'INVOICEDATEKEY')
)
SELECT n, check_name, expected, actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS result
FROM checks
ORDER BY n;


-- =====================================================================
-- STEP 8 · Power BI: model, measures and the Music Sales dashboard
-- Run in: Power BI Desktop (MusicSales.pbix)
-- =====================================================================
/* Power BI build notes

Connect: Get data > Snowflake; Server <account>.snowflakecomputing.com,
  Warehouse TRANSFORMING; Advanced: Role ACCOUNTADMIN, Database ANALYTICS;
  key-pair sign-in; Import mode.
Tables: FACT_SALE, DIM_DATE, DIM_CUSTOMER, DIM_EMPLOYEE, DIM_INVOICE, DIM_TRACK
  from ANALYTICS.DBT_DRAMASRAY_CHINOOK. DIM_DATE marked as the date table.
Relationships (many-to-one, single direction, active):
  FACT_SALE[INVOICEKEY]     -> DIM_INVOICE[INVOICEKEY]
  FACT_SALE[TRACKKEY]       -> DIM_TRACK[TRACKKEY]
  FACT_SALE[CUSTOMERKEY]    -> DIM_CUSTOMER[CUSTOMERKEY]
  FACT_SALE[EMPLOYEEKEY]    -> DIM_EMPLOYEE[EMPLOYEEKEY]
  FACT_SALE[INVOICEDATEKEY] -> DIM_DATE[DATEKEY]
Dashboard page "Music Sales" (theme powerbi/IST722_DIM_Data_Theme.json,
page 1280 x 720):
  - Year tile slicer (visual filter: Total Sales is not blank -> 2009-2013)
  - KPI tiles: $2,328.60 | 412 invoices | 2,240 units | 59 customers | $5.65
  - Sales by year, drill down to quarter (column chart)
  - Sales by support rep (donut): Jane 35.8%, Margaret 33.3%, Steve 30.9%
  - Sales by customer country (treemap, gradient): USA $523.06 first
  - Top 10 artists by sales (bar, Top N filter): Iron Maiden $138.60 first
*/
/* DAX measures (home table FACT_SALE)

// Expected: 2,328.60
Total Sales = SUM ( FACT_SALE[SALEAMOUNT] )

// Expected: 2,240
Units Sold = SUM ( FACT_SALE[QUANTITY] )

// Expected: 1.04  (unit price is non-additive, so it is averaged, not summed)
Average Unit Price = AVERAGE ( FACT_SALE[UNITPRICE] )

// Expected: 412
Invoice Count = DISTINCTCOUNT ( FACT_SALE[INVOICEID] )

// Expected: 59
Customers With Sales = DISTINCTCOUNT ( FACT_SALE[CUSTOMERKEY] )

// Expected: $5.65  (added for the dashboard; Total Sales and this one use Currency format)
Average Invoice Value = DIVIDE ( [Total Sales], [Invoice Count] )
*/

-- End of music_sales.sql
