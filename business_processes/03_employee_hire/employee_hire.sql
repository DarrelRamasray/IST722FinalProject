-- =====================================================================
-- employee_hire.sql · Business process: EMPLOYEE HIRE (salary SIMULATED)
-- IST 722 Data Warehouse, Fall 2026 · Team DIM Data · Owner: Darrel Ramasray
-- Built 22-23 Nov 2026 (Milestone 3) on top of Music Sales.
--
-- Run after music_sales.sql: it reuses RAW.CHINOOK.EMPLOYEE (loaded there)
--   and the conformed dim_employee and dim_date.
-- Simulated data: Chinook has no salaries, so employeesalary.csv holds one
--   starting salary (CAD) per employee, drawn with seed 722 inside a fixed
--   range per title. Hire dates, birth dates and titles are real.
-- Star: fact_employee (one row per hire, 8 rows) with the shared
--   dim_employee and dim_date. dim_date was widened to 2002-2013 here,
--   because hires (2002-2004) come before the first invoice (2009).
-- Verified: RAW 11/11 PASS · dbt +1 model +10 tests (88 PASS in total)
--   · star 21/21 PASS (Music Sales still 23/23) · Hires 8 in Power BI.
--
-- How to read this file: run each STEP in the tool named in its header.
-- SQL blocks (SQL Server, Snowflake, dbt models) are plain code. Blocks
-- for other tools (Snowflake CLI, dbt YAML, Power BI DAX, Python) sit
-- inside /* */ comments. It is a record of the build, not one script to
-- run top to bottom. The runnable dbt project is dbt/chinook_dw/, with
-- one models folder per process plus shared_dimensions/.
-- =====================================================================


-- =====================================================================
-- STEP 1 · Generate employeesalary.csv (SIMULATED)
-- Run in: Python; input = the employee.csv extracted in music_sales.sql STEP 1
-- Result (EmployeeId: salary): 1: 132000, 2: 87000, 3: 45000, 4: 47500,
-- 5: 45000, 6: 89000, 7: 62500, 8: 61000 (sum 569,000).
-- =====================================================================
-- Also saved as business_processes/03_employee_hire/simulated_data/generate_employeesalary.py
/* Python: generate_employeesalary.py
Rules: seed 722; one salary per employee, uniform inside its title range,
rounded to the nearest 500 (CAD): General Manager 120,000-140,000; Sales
Manager and IT Manager 85,000-99,500; IT Staff 55,000-65,000; Sales Support
Agent 42,000-52,000.

import csv, random, sys

SRC = sys.argv[1] if len(sys.argv) > 1 else './Chinook.dbo.Employee.csv'
OUT = sys.argv[2] if len(sys.argv) > 2 else './employeesalary.csv'
RANGES = {
    'General Manager': (120000, 140000),
    'Sales Manager': (85000, 99500),
    'IT Manager': (85000, 99500),
    'IT Staff': (55000, 65000),
    'Sales Support Agent': (42000, 52000),
}
random.seed(722)
rows = sorted(csv.DictReader(open(SRC, encoding='utf-8-sig')), key=lambda r: int(r['EmployeeId']))
with open(OUT, 'w', newline='', encoding='utf-8') as f:
    w = csv.writer(f, lineterminator='\r\n')
    w.writerow(['EmployeeId', 'StartingSalary'])
    for r in rows:
        lo, hi = RANGES[r['Title']]
        salary = int(round(random.uniform(lo, hi) / 500.0)) * 500
        w.writerow([int(r['EmployeeId']), salary])
print('wrote', OUT, len(rows), 'rows')
*/


-- =====================================================================
-- STEP 2 · Create the RAW table
-- Run in: Snowsight (role SYSADMIN, warehouse COMPUTE_WH)
-- Re-running empties only EMPLOYEESALARY. RAW.CHINOOK now holds 13 tables.
-- =====================================================================
USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA RAW.CHINOOK;

-- Chinook has no salary data, so this table holds SIMULATED values.
CREATE OR REPLACE TABLE EMPLOYEESALARY (
  EMPLOYEEID      INT NOT NULL,
  STARTINGSALARY  INT NOT NULL,
  _SOURCE_FILE    VARCHAR,
  _LOADED_AT      TIMESTAMP_LTZ
)
COMMENT = 'SIMULATED annual starting salary (CAD) per employee for the Employee Hire process. Chinook has no salary data. Generated 2026-11-22 (seed 722) from real Chinook EmployeeId and Title values, inside a fixed range per title.';

-- Check: 13 tables (9 Music Sales + 3 Track Playtime + EMPLOYEESALARY)
SHOW TABLES IN SCHEMA RAW.CHINOOK;


-- =====================================================================
-- STEP 3 · Upload the CSV file
-- Run in: Command Prompt, Snowflake CLI (connection my_snowflake)
-- =====================================================================
/* Snowflake CLI

chcp 65001
cd %USERPROFILE%\Documents\chinook_extract
snow sql -c my_snowflake -q "PUT 'file://C:/Users/darre/Documents/chinook_extract/employeesalary.csv' @RAW.CHINOOK.CHINOOK_STAGE AUTO_COMPRESS=TRUE OVERWRITE=TRUE"
*/


-- =====================================================================
-- STEP 4 · Load the staged file
-- Run in: Snowsight (role SYSADMIN), one statement at a time
-- =====================================================================
USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA RAW.CHINOOK;

-- A. The stage should now list 13 files, including employeesalary.csv.gz
LIST @CHINOOK_STAGE;

-- B. Preview the staged file: 8 rows, salaries 132000, 87000, 45000,
--    47500, 45000, 89000, 62500, 61000 for employees 1 to 8
SELECT t.$1 AS employeeid, t.$2 AS startingsalary
FROM @CHINOOK_STAGE (FILE_FORMAT => 'RAW.CHINOOK.CHINOOK_CSV',
                     PATTERN => '^(.*/)?employeesalary[.]csv([.]gz)?$') t
ORDER BY TO_NUMBER(t.$1);

-- C. Load. ON_ERROR = 'ABORT_STATEMENT' loads nothing if any row fails.
-- EMPLOYEESALARY  <-  employeesalary.csv  (expect 8 rows, SIMULATED)
COPY INTO EMPLOYEESALARY (
    EMPLOYEEID, STARTINGSALARY, _SOURCE_FILE, _LOADED_AT
)
FROM (
  SELECT
    t.$1, t.$2, METADATA$FILENAME, METADATA$START_SCAN_TIME
  FROM @CHINOOK_STAGE t
)
PATTERN = '^(.*/)?employeesalary[.]csv([.]gz)?$'
FILE_FORMAT = (FORMAT_NAME = 'RAW.CHINOOK.CHINOOK_CSV')
ON_ERROR = 'ABORT_STATEMENT';

-- D. Row count after loading: expect 8
SELECT COUNT(*) AS row_count FROM EMPLOYEESALARY;


-- =====================================================================
-- STEP 5 · Verify the salary table and the EMPLOYEE columns used (11 checks)
-- Run in: Snowsight (role SYSADMIN)
-- Salaries inside their title ranges, every employee has one, hire and
-- birth dates present. Result: 11/11 PASS.
-- =====================================================================
USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA RAW.CHINOOK;

WITH checks AS (
    SELECT 1 AS n, 'EMPLOYEESALARY row count' AS check_name, 8 AS expected,
           (SELECT COUNT(*) FROM EMPLOYEESALARY) AS actual

    UNION ALL SELECT 2, 'EMPLOYEESALARY distinct EMPLOYEEID', 8,
           (SELECT COUNT(DISTINCT EMPLOYEEID) FROM EMPLOYEESALARY)

    UNION ALL SELECT 3, 'EMPLOYEESALARY.EMPLOYEEID values missing from EMPLOYEE', 0,
           (SELECT COUNT(*) FROM EMPLOYEESALARY s
             WHERE NOT EXISTS (SELECT 1 FROM EMPLOYEE e WHERE e.EMPLOYEEID = s.EMPLOYEEID))

    UNION ALL SELECT 4, 'EMPLOYEE rows with no salary', 0,
           (SELECT COUNT(*) FROM EMPLOYEE e
             WHERE NOT EXISTS (SELECT 1 FROM EMPLOYEESALARY s WHERE s.EMPLOYEEID = e.EMPLOYEEID))

    UNION ALL SELECT 5, 'Salaries outside the range for the employee''s title', 0,
           (SELECT COUNT(*) FROM EMPLOYEESALARY s
              JOIN EMPLOYEE e ON e.EMPLOYEEID = s.EMPLOYEEID
             WHERE NOT (
                   (e.TITLE = 'General Manager'     AND s.STARTINGSALARY BETWEEN 120000 AND 140000)
                OR (e.TITLE = 'Sales Manager'       AND s.STARTINGSALARY BETWEEN  85000 AND  99500)
                OR (e.TITLE = 'IT Manager'          AND s.STARTINGSALARY BETWEEN  85000 AND  99500)
                OR (e.TITLE = 'IT Staff'            AND s.STARTINGSALARY BETWEEN  55000 AND  65000)
                OR (e.TITLE = 'Sales Support Agent' AND s.STARTINGSALARY BETWEEN  42000 AND  52000)))

    UNION ALL SELECT 6, 'Sum of EMPLOYEESALARY.STARTINGSALARY', 569000,
           (SELECT SUM(STARTINGSALARY) FROM EMPLOYEESALARY)

    UNION ALL SELECT 7, 'EMPLOYEE row count (unchanged since Milestone 2)', 8,
           (SELECT COUNT(*) FROM EMPLOYEE)

    UNION ALL SELECT 8, 'EMPLOYEE rows with no HIREDATE', 0,
           (SELECT COUNT(*) FROM EMPLOYEE WHERE HIREDATE IS NULL)

    UNION ALL SELECT 9, 'EMPLOYEE rows with no BIRTHDATE', 0,
           (SELECT COUNT(*) FROM EMPLOYEE WHERE BIRTHDATE IS NULL)

    UNION ALL SELECT 10, 'Hire dates between 2002-01-01 and 2004-12-31', 8,
           (SELECT COUNT(*) FROM EMPLOYEE
             WHERE CAST(HIREDATE AS DATE) BETWEEN '2002-01-01' AND '2004-12-31')

    UNION ALL SELECT 11, 'EMPLOYEESALARY rows missing _SOURCE_FILE or _LOADED_AT', 0,
           (SELECT COUNT(*) FROM EMPLOYEESALARY
             WHERE _SOURCE_FILE IS NULL OR _LOADED_AT IS NULL)
)
SELECT n, check_name, expected, actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS result
FROM checks
ORDER BY n;


-- =====================================================================
-- STEP 6 · dbt: widen dim_date, add fact_employee
-- Run in: dbt platform Studio IDE, branch employee-hire (merged to main by pull request)
-- Run: dbt build -> 9 models + 79 tests = 88 PASS. The existing
-- relationships tests confirm every invoice and play date is still in dim_date.
-- =====================================================================

-- ---- 6A · Lines added to models/chinook/_chinook__sources.yml --------
/* YAML added under sources > chinook > tables

- name: employeesalary
  description: "SIMULATED annual starting salary (CAD) per employee (Chinook has no salary data). Generated with seed 722 inside a fixed range per title."
*/

-- ---- 6B · models/chinook/shared_dimensions/dim_date.sql (CHANGED) · full years from the first to the last invoice or hire date ---
-- 2002-01-01 .. 2013-12-31, 4,383 days. Only the eventdates and bounds CTEs changed.
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

-- ---- 6C · shared_dimensions/_shared_dimensions__models.yml (CHANGED) · dim_date description only ---
/* YAML changed in _shared_dimensions__models.yml

- name: dim_date
  description: "One row per calendar day, for every full calendar year from the earliest invoice or hire date to the latest (2002-01-01 to 2013-12-31 today)."
*/

-- ---- 6D · models/chinook/03_employee_hire/fact_employee.sql · one row per hire (8) ---
-- ageathire = whole years on the hire date; salaryband from the simulated salary.
{{ config(materialized='table') }}

with stg_employee as (
    select * from {{ source('chinook', 'employee') }}
),

stg_employeesalary as (
    select * from {{ source('chinook', 'employeesalary') }}
),

hires as (
    select
        e.employeeid,
        cast(e.hiredate as date)   as hiredate,
        cast(e.birthdate as date)  as birthdate,
        s.startingsalary
    from stg_employee as e

    -- Every employee has a salary row (STEP 5, check 4),
    -- so the inner join loses no one.
    inner join stg_employeesalary as s
        on s.employeeid = e.employeeid

    -- The grain is one row per employee HIRED: an employee with no hire
    -- date is not a hire. None today (STEP 5, check 8).
    where e.hiredate is not null
)

select
    h.employeeid                                           as employeeid,
    h.employeeid                                           as employeekey,
    h.hiredate                                             as hiredatekey,
    cast(1 as int)                                         as hirecount,

    -- whole years between birth date and hire date: count the year
    -- boundaries crossed, minus 1 if the birthday had not yet come that
    -- year. NULL if the birth date is NULL (Employee.BirthDate allows it).
    cast(
        datediff(year, h.birthdate, h.hiredate)
        - iff(dateadd(year, datediff(year, h.birthdate, h.hiredate), h.birthdate) > h.hiredate, 1, 0)
        as int)                                            as ageathire,

    cast(h.startingsalary as int)                          as startingsalary,
    cast(
        case
            when h.startingsalary < 50000  then '1: Under 50K'
            when h.startingsalary < 75000  then '2: 50K to 75K'
            when h.startingsalary < 100000 then '3: 75K to 100K'
            else '4: 100K and over'
        end as varchar(20))                                as salaryband

from hires as h

-- ---- 6E · models/chinook/03_employee_hire/_employee_hire__models.yml · 10 tests ---
/* models/chinook/03_employee_hire/_employee_hire__models.yml

version: 2

models:
  - name: fact_employee
    description: "One row per employee hired; each row is unique by employeeid. Starting salary and salary band are SIMULATED: Chinook has no salary data."
    columns:
      - name: employeeid
        description: "Source key of the employee; used for drill-through"
        data_tests:
          - unique
          - not_null
      - name: employeekey
        description: "Dimension FK for dim_employee; the employee hired"
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('dim_employee')
                field: employeekey
      - name: hiredatekey
        description: "Dimension FK for dim_date; the hire date"
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('dim_date')
                field: datekey
      - name: hirecount
        description: "So hires can be counted; Always 1; Additive"
        data_tests:
          - not_null
      - name: ageathire
        description: "Age in whole years on the hire date; Non-additive (average it); NULL if the birth date is NULL"
      - name: startingsalary
        description: "Annual starting salary in CAD; Additive; SIMULATED"
        data_tests:
          - not_null
      - name: salaryband
        description: "Band of the starting salary; Degenerate; SIMULATED"
        data_tests:
          - not_null
          - accepted_values:
              arguments:
                values: ['1: Under 50K', '2: 50K to 75K', '3: 75K to 100K', '4: 100K and over']
*/


-- =====================================================================
-- STEP 7 · Verify the Employee Hire star (21 checks)
-- Run in: Snowsight (role ACCOUNTADMIN, warehouse TRANSFORMING)
-- Also re-run the Music Sales star checks (music_sales.sql STEP 7): checks
-- 6, 16 and 17 now expect 4,383 days, 2002-01-01 and 2013-12-31 -> 23/23 PASS.
-- Result here: 21/21 PASS, including the drill-across to FACT_SALE (1,495.56).
-- =====================================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE TRANSFORMING;
USE SCHEMA ANALYTICS.DBT_DRAMASRAY_CHINOOK;

WITH checks AS (
    SELECT 1 AS n, 'FACT_EMPLOYEE row count' AS check_name, 8 AS expected,
           (SELECT COUNT(*) FROM FACT_EMPLOYEE) AS actual

    UNION ALL SELECT 2, 'FACT_EMPLOYEE distinct EMPLOYEEID', 8,
           (SELECT COUNT(DISTINCT EMPLOYEEID) FROM FACT_EMPLOYEE)

    UNION ALL SELECT 3, 'Sum of HIRECOUNT', 8,
           (SELECT SUM(HIRECOUNT) FROM FACT_EMPLOYEE)

    UNION ALL SELECT 4, 'EMPLOYEEKEY values missing from DIM_EMPLOYEE (conformed)', 0,
           (SELECT COUNT(*) FROM FACT_EMPLOYEE f
             WHERE NOT EXISTS (SELECT 1 FROM DIM_EMPLOYEE d WHERE d.EMPLOYEEKEY = f.EMPLOYEEKEY))

    UNION ALL SELECT 5, 'HIREDATEKEY values missing from DIM_DATE (conformed)', 0,
           (SELECT COUNT(*) FROM FACT_EMPLOYEE f
             WHERE NOT EXISTS (SELECT 1 FROM DIM_DATE d WHERE d.DATEKEY = f.HIREDATEKEY))

    UNION ALL SELECT 6, 'DIM_DATE row count (2002-01-01 to 2013-12-31)', 4383,
           (SELECT COUNT(*) FROM DIM_DATE)

    UNION ALL SELECT 7, 'DIM_DATE first day is 2002-01-01', 1,
           (SELECT IFF(MIN(DATEKEY) = TO_DATE('2002-01-01'), 1, 0) FROM DIM_DATE)

    UNION ALL SELECT 8, 'DIM_DATE last day is 2013-12-31', 1,
           (SELECT IFF(MAX(DATEKEY) = TO_DATE('2013-12-31'), 1, 0) FROM DIM_DATE)

    UNION ALL SELECT 9, 'DIM_DATE has no missing days', 1,
           (SELECT IFF(COUNT(*) = DATEDIFF(day, MIN(DATEKEY), MAX(DATEKEY)) + 1, 1, 0)
              FROM DIM_DATE)

    UNION ALL SELECT 10, 'Hires in 2002, through DIM_DATE', 3,
           (SELECT COUNT(*) FROM FACT_EMPLOYEE f
              JOIN DIM_DATE d ON d.DATEKEY = f.HIREDATEKEY
             WHERE d.YEAR = 2002)

    UNION ALL SELECT 11, 'Hires in 2003, through DIM_DATE', 3,
           (SELECT COUNT(*) FROM FACT_EMPLOYEE f
              JOIN DIM_DATE d ON d.DATEKEY = f.HIREDATEKEY
             WHERE d.YEAR = 2003)

    UNION ALL SELECT 12, 'Hires in 2004, through DIM_DATE', 2,
           (SELECT COUNT(*) FROM FACT_EMPLOYEE f
              JOIN DIM_DATE d ON d.DATEKEY = f.HIREDATEKEY
             WHERE d.YEAR = 2004)

    UNION ALL SELECT 13, 'Sum of AGEATHIRE (average 37.875)', 303,
           (SELECT SUM(AGEATHIRE) FROM FACT_EMPLOYEE)

    UNION ALL SELECT 14, 'Margaret Park was 55 when hired (birthday 19 Sep, hired 3 May 2003)', 1,
           (SELECT COUNT(*) FROM FACT_EMPLOYEE f
              JOIN DIM_EMPLOYEE d ON d.EMPLOYEEKEY = f.EMPLOYEEKEY
             WHERE d.LASTNAME = 'Park' AND f.AGEATHIRE = 55)

    UNION ALL SELECT 15, 'Sum of STARTINGSALARY (same as RAW)', 569000,
           (SELECT SUM(STARTINGSALARY) FROM FACT_EMPLOYEE)

    UNION ALL SELECT 16, 'Salary bands that do not match the salary', 0,
           (SELECT COUNT(*) FROM FACT_EMPLOYEE
             WHERE SALARYBAND <> CASE
                     WHEN STARTINGSALARY < 50000  THEN '1: Under 50K'
                     WHEN STARTINGSALARY < 75000  THEN '2: 50K to 75K'
                     WHEN STARTINGSALARY < 100000 THEN '3: 75K to 100K'
                     ELSE '4: 100K and over' END)

    UNION ALL SELECT 17, 'Hires in band 1: Under 50K', 3,
           (SELECT COUNT(*) FROM FACT_EMPLOYEE WHERE SALARYBAND = '1: Under 50K')

    UNION ALL SELECT 18, 'Drill-across: Total Sales of reps hired in 2003 (Park + Johnson)', 1495.56,
           (SELECT SUM(s.SALEAMOUNT)
              FROM FACT_SALE s
              JOIN FACT_EMPLOYEE f ON f.EMPLOYEEKEY = s.EMPLOYEEKEY
              JOIN DIM_DATE d      ON d.DATEKEY = f.HIREDATEKEY
             WHERE d.YEAR = 2003)

    UNION ALL SELECT 19, 'FACT_SALE still has 2,240 rows (Music Sales unchanged)', 2240,
           (SELECT COUNT(*) FROM FACT_SALE)

    UNION ALL SELECT 20, 'FACT_TRACK_PLAYTIME still has 2,000 rows (Track Playtime unchanged)', 2000,
           (SELECT COUNT(*) FROM FACT_TRACK_PLAYTIME)

    UNION ALL SELECT 21, 'FACT_EMPLOYEE.HIREDATEKEY type is DATE (same as DIM_DATE.DATEKEY)', 1,
           (SELECT IFF(DATA_TYPE = 'DATE', 1, 0)
              FROM INFORMATION_SCHEMA.COLUMNS
             WHERE TABLE_SCHEMA = CURRENT_SCHEMA()
               AND TABLE_NAME = 'FACT_EMPLOYEE'
               AND COLUMN_NAME = 'HIREDATEKEY')
)
SELECT n, check_name, expected, actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS result
FROM checks
ORDER BY n;


-- =====================================================================
-- STEP 8 · Power BI: model, measures and the Employee Hire dashboard
-- Run in: Power BI Desktop (MusicSales.pbix, same file)
-- =====================================================================
/* Power BI build notes

Home > Refresh first: DIM_DATE grows to 4,383 rows (2002-2013).
Table added: FACT_EMPLOYEE (Import). Don't summarize on EMPLOYEEID,
  EMPLOYEEKEY and AGEATHIRE.
Relationships (many-to-one, single direction, active; 11 in the file):
  FACT_EMPLOYEE[EMPLOYEEKEY] -> DIM_EMPLOYEE[EMPLOYEEKEY]  (shared with FACT_SALE)
  FACT_EMPLOYEE[HIREDATEKEY] -> DIM_DATE[DATEKEY]          (shared)
  Power BI proposes one-to-one for the first, because both columns are
  unique; it was set to many-to-one, single, to match the design.
Dashboard page "Employee Hire (salary simulated)", 1280 x 720:
  - Header: "Employee Hire / Salaries simulated; hires and ages are real"
  - Job-title tile slicer (filters both facts through DIM_EMPLOYEE)
  - KPI tiles: 8 hires | 37.9 average age | 569,000 total | 71,125 average salary
  - Hires by year and job title (stacked bar): 2002: 3, 2003: 3, 2004: 2
  - Hires by starting-salary band (donut): 3 / 2 / 2 / 1
  - Who was hired (treemap: TITLE, FIRSTNAME, Hires)
  - Drill-across table: First, Last, Title, Age at hire, Salary (FACT_EMPLOYEE)
    beside Sales (FACT_SALE) through DIM_EMPLOYEE; totals 37.9, 569,000,
    $2,328.60. Only the 3 Sales Support Agents have sales.
  - Edit interactions: the year chart and the band donut are set to None
    on the drill-across table (hire attributes must not filter sales).
*/
/* DAX measures (home table FACT_EMPLOYEE)

// Expected: 8   (format: Whole number)
Hires = SUM ( FACT_EMPLOYEE[HIRECOUNT] )

// Expected: 37.9   (37.875; format: Decimal number, 1 decimal place)
Average Age at Hire = AVERAGE ( FACT_EMPLOYEE[AGEATHIRE] )

// Expected: 569,000   (format: Whole number)
Total Starting Salary = SUM ( FACT_EMPLOYEE[STARTINGSALARY] )

// Expected: 71,125   (format: Whole number)
Average Starting Salary = DIVIDE ( [Total Starting Salary], [Hires] )
*/

-- End of employee_hire.sql
