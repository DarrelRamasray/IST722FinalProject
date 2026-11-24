-- =====================================================================
-- <process_name>.sql · Business process: <PROCESS NAME>
-- IST 722 Data Warehouse, Fall 2026 · Team DIM Data · Owner: <name>
-- Built <dates> (<milestone>).
--
-- Depends on: <files or tables this reuses, e.g. music_sales.sql STEP 2>
-- Simulated data: <none, or what was generated, how, and the seed>
-- Star: <fact table (grain, rows)> with <dimensions; mark the shared ones>
-- Verified: RAW <n/n> PASS · dbt <models> + <tests> · star <n/n> PASS
--
-- How to read this file: run each STEP in the tool named in its header.
-- SQL blocks are plain code; CLI, YAML, DAX and Python go inside /* */.
-- =====================================================================


-- =====================================================================
-- STEP 1 · Extract <tables> to CSV
-- Run in: <tool>
-- =====================================================================


-- =====================================================================
-- STEP 2 · Create the RAW tables
-- Run in: Snowsight (role <role>, warehouse <warehouse>)
-- =====================================================================


-- =====================================================================
-- STEP 3 · Upload the CSV files to the stage
-- Run in: <Snowflake CLI or Snowsight upload>
-- =====================================================================


-- =====================================================================
-- STEP 4 · Load the staged files (COPY INTO)
-- Run in: Snowsight
-- =====================================================================


-- =====================================================================
-- STEP 5 · Verify the RAW tables (<n> checks)
-- Run in: Snowsight
-- =====================================================================


-- =====================================================================
-- STEP 6 · dbt models and tests
-- Run in: dbt platform Studio IDE (project, branch)
-- =====================================================================


-- =====================================================================
-- STEP 7 · Verify the star schema (<n> checks)
-- Run in: Snowsight
-- =====================================================================


-- =====================================================================
-- STEP 8 · Power BI: model, measures and dashboard page
-- Run in: Power BI Desktop
-- =====================================================================
/* Power BI build notes: tables, relationships, page and visuals

*/
/* DAX measures

*/
