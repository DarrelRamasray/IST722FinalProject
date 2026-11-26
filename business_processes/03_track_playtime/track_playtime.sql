-- =====================================================================
-- track_playtime.sql · Business process: TRACK PLAYTIME (play data SIMULATED)
-- IST 722 Data Warehouse, Fall 2026 · Team DIM Data · Owner: Darrel Ramasray
-- Built 12-19 Nov 2026 (Milestone 3) on top of Music Sales.
--
-- Run after music_sales.sql: it reuses the RAW stage and file format, the
--   RAW TRACK and CUSTOMER tables, and the conformed dim_date, dim_customer
--   and dim_track (their dbt code is in music_sales.sql, STEP 6).
-- Simulated data: Chinook has no play events, so trackplays.csv holds 2,000
--   plays generated with seed 722 from real customer, playlist and track IDs.
--   Every played track is on its playlist; dates fall in 2009-2013.
-- Star: fact_track_playtime (one row per play) with dim_playlist (new) and
--   the shared dim_date, dim_customer and dim_track.
-- Verified: RAW 19/19 PASS · dbt +2 models +18 tests (77 PASS in total)
--   · star 20/20 PASS · Play Count 2,000 in Power BI.
--
-- How to read this file: run each STEP in the tool named in its header.
-- SQL blocks (SQL Server, Snowflake, dbt models) are plain code. Blocks
-- for other tools (Snowflake CLI, dbt YAML, Power BI DAX, Python) sit
-- inside /* */ comments. It is a record of the build, not one script to
-- run top to bottom. The runnable dbt project is dbt/chinook_dw/, with
-- one models folder per process plus shared_dimensions/.
-- =====================================================================


-- =====================================================================
-- STEP 1 · Extract Playlist and PlaylistTrack; generate trackplays.csv
-- Run in: VS Code (MSSQL) on the school SQL Server; then Python
-- Save the results as playlist.csv (18 rows) and playlisttrack.csv (8,715 rows)
-- in Documents\chinook_extract, next to trackplays.csv.
-- =====================================================================
-- ---------------------------------------------------------------------
-- 1 of 2  ->  playlist.csv  (18 rows)
-- ---------------------------------------------------------------------
SELECT PlaylistId, Name
FROM Chinook.dbo.Playlist
ORDER BY PlaylistId;


-- ---------------------------------------------------------------------
-- 2 of 2  ->  playlisttrack.csv  (8,715 rows)
-- ---------------------------------------------------------------------
SELECT PlaylistId, TrackId
FROM Chinook.dbo.PlaylistTrack
ORDER BY PlaylistId, TrackId;

-- ---- 1B · Generator for the SIMULATED trackplays.csv (2,000 rows) ----
-- Also saved as business_processes/02_track_playtime/simulated_data/generate_trackplays.py
/* Python: generate_trackplays.py
Rules: seed 722; 2,000 plays; time uniform 2009-01-01 .. 2013-12-22;
customer uniform among 59; playlist uniform among the 14 with tracks; track
uniform on that playlist; 60% run the whole track, the rest 1 .. length-1.

import csv, random
from datetime import datetime, timedelta

SRC = './'   # the folder holding the four Chinook CSV exports
OUT = './trackplays.csv'
random.seed(722)
N = 2000

customers = [int(r['CustomerId']) for r in csv.DictReader(open(SRC + 'Chinook.dbo.Customer.csv', encoding='utf-8-sig'))]
duration = {int(r['TrackId']): (int(r['Milliseconds']) + 500) // 1000
            for r in csv.DictReader(open(SRC + 'Chinook.dbo.Track.csv', encoding='utf-8-sig'))}
tracks_on = {}
for r in csv.DictReader(open(SRC + 'Chinook.dbo.PlaylistTrack.csv', encoding='utf-8-sig')):
    tracks_on.setdefault(int(r['PlaylistId']), []).append(int(r['TrackId']))
playlists = sorted(tracks_on)          # only playlists that contain tracks
for p in playlists:
    tracks_on[p].sort()

start = datetime(2009, 1, 1, 0, 0, 0)
span = int((datetime(2013, 12, 22, 23, 59, 59) - start).total_seconds())

rows = []
for _ in range(N):
    c = random.choice(customers)
    p = random.choice(playlists)
    t = random.choice(tracks_on[p])
    when = start + timedelta(seconds=random.randint(0, span))
    d = duration[t]
    secs = d if (random.random() < 0.60 or d < 2) else random.randint(1, d - 1)
    rows.append((when, c, t, p, secs))
rows.sort(key=lambda r: (r[0], r[1], r[2]))

with open(OUT, 'w', newline='', encoding='utf-8') as f:
    w = csv.writer(f, lineterminator='\r\n')
    w.writerow(['PlayEventId', 'CustomerId', 'TrackId', 'PlaylistId', 'PlayedAt', 'SecondsPlayed'])
    for i, (when, c, t, p, secs) in enumerate(rows, start=1):
        w.writerow([i, c, t, p, when.strftime('%Y-%m-%d %H:%M:%S') + '.000', secs])
print('wrote', OUT, len(rows), 'rows; playlists used:', playlists)
*/


-- =====================================================================
-- STEP 2 · Create the 3 RAW tables
-- Run in: Snowsight (role SYSADMIN, warehouse COMPUTE_WH)
-- Reuses CHINOOK_CSV and CHINOOK_STAGE. Re-running empties only these 3 tables.
-- Never re-run music_sales.sql STEP 2: it empties the Music Sales tables.
-- =====================================================================
USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA RAW.CHINOOK;

-- Types from the SQL Server schema: PlaylistId int NOT NULL,
-- Name nvarchar(120) NULL; PlaylistTrack has two NOT NULL int columns.
CREATE OR REPLACE TABLE PLAYLIST (
  PLAYLISTID    INT NOT NULL,
  NAME          VARCHAR(120),
  _SOURCE_FILE  VARCHAR,
  _LOADED_AT    TIMESTAMP_LTZ
);

CREATE OR REPLACE TABLE PLAYLISTTRACK (
  PLAYLISTID    INT NOT NULL,
  TRACKID       INT NOT NULL,
  _SOURCE_FILE  VARCHAR,
  _LOADED_AT    TIMESTAMP_LTZ
);

-- Chinook has no play-event table, so this one holds SIMULATED rows.
CREATE OR REPLACE TABLE TRACKPLAYS (
  PLAYEVENTID    INT NOT NULL,
  CUSTOMERID     INT NOT NULL,
  TRACKID        INT NOT NULL,
  PLAYLISTID     INT NOT NULL,
  PLAYEDAT       TIMESTAMP_NTZ NOT NULL,
  SECONDSPLAYED  INT NOT NULL,
  _SOURCE_FILE   VARCHAR,
  _LOADED_AT     TIMESTAMP_LTZ
)
COMMENT = 'SIMULATED play events for the Track Playtime process. Chinook has no play-event table. Generated 2026-11-12 (seed 722) from real Chinook CustomerId, PlaylistId and TrackId values; every track is on the playlist it was played from.';

-- Check: 12 tables (the 9 from Milestone 2 plus these 3)
SHOW TABLES IN SCHEMA RAW.CHINOOK;


-- =====================================================================
-- STEP 3 · Upload the 3 CSV files
-- Run in: Command Prompt, Snowflake CLI (connection my_snowflake)
-- chcp 65001 keeps the curly apostrophe in 90’s Music. Each PUT reports UPLOADED.
-- =====================================================================
/* Snowflake CLI

chcp 65001
cd %USERPROFILE%\Documents\chinook_extract
snow sql -c my_snowflake -q "PUT 'file://C:/Users/darre/Documents/chinook_extract/playlist.csv' @RAW.CHINOOK.CHINOOK_STAGE AUTO_COMPRESS=TRUE OVERWRITE=TRUE"
snow sql -c my_snowflake -q "PUT 'file://C:/Users/darre/Documents/chinook_extract/playlisttrack.csv' @RAW.CHINOOK.CHINOOK_STAGE AUTO_COMPRESS=TRUE OVERWRITE=TRUE"
snow sql -c my_snowflake -q "PUT 'file://C:/Users/darre/Documents/chinook_extract/trackplays.csv' @RAW.CHINOOK.CHINOOK_STAGE AUTO_COMPRESS=TRUE OVERWRITE=TRUE"
*/


-- =====================================================================
-- STEP 4 · Load the 3 staged files
-- Run in: Snowsight (role SYSADMIN), one statement at a time
-- =====================================================================
USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA RAW.CHINOOK;

-- A. The stage should now list 12 files: the 9 from Milestone 2 plus
--    playlist.csv.gz, playlisttrack.csv.gz and trackplays.csv.gz
LIST @CHINOOK_STAGE;

-- B. Data rows in the three new files (header not counted).
--    Expect playlist 18, playlisttrack 8715, trackplays 2000.
SELECT METADATA$FILENAME AS file_name, COUNT(*) AS data_rows
FROM @CHINOOK_STAGE (FILE_FORMAT => 'RAW.CHINOOK.CHINOOK_CSV',
                     PATTERN => '^(.*/)?(playlist|playlisttrack|trackplays)[.]csv([.]gz)?$') t
GROUP BY METADATA$FILENAME
ORDER BY file_name;

-- C. Preview: the curly apostrophe in playlist 5 must read 90’s Music
SELECT t.$1 AS playlistid, t.$2 AS name
FROM @CHINOOK_STAGE (FILE_FORMAT => 'RAW.CHINOOK.CHINOOK_CSV',
                     PATTERN => '^(.*/)?playlist[.]csv([.]gz)?$') t
ORDER BY TO_NUMBER(t.$1);

-- D. Load each table. ON_ERROR = 'ABORT_STATEMENT' loads nothing if any row fails.

-- PLAYLIST  <-  playlist.csv  (expect 18 rows)
COPY INTO PLAYLIST (
    PLAYLISTID, NAME, _SOURCE_FILE, _LOADED_AT
)
FROM (
  SELECT
    t.$1, t.$2, METADATA$FILENAME, METADATA$START_SCAN_TIME
  FROM @CHINOOK_STAGE t
)
PATTERN = '^(.*/)?playlist[.]csv([.]gz)?$'
FILE_FORMAT = (FORMAT_NAME = 'RAW.CHINOOK.CHINOOK_CSV')
ON_ERROR = 'ABORT_STATEMENT';

-- PLAYLISTTRACK  <-  playlisttrack.csv  (expect 8,715 rows)
COPY INTO PLAYLISTTRACK (
    PLAYLISTID, TRACKID, _SOURCE_FILE, _LOADED_AT
)
FROM (
  SELECT
    t.$1, t.$2, METADATA$FILENAME, METADATA$START_SCAN_TIME
  FROM @CHINOOK_STAGE t
)
PATTERN = '^(.*/)?playlisttrack[.]csv([.]gz)?$'
FILE_FORMAT = (FORMAT_NAME = 'RAW.CHINOOK.CHINOOK_CSV')
ON_ERROR = 'ABORT_STATEMENT';

-- TRACKPLAYS  <-  trackplays.csv  (expect 2,000 rows, SIMULATED)
COPY INTO TRACKPLAYS (
    PLAYEVENTID, CUSTOMERID, TRACKID, PLAYLISTID, PLAYEDAT, SECONDSPLAYED,
    _SOURCE_FILE, _LOADED_AT
)
FROM (
  SELECT
    t.$1, t.$2, t.$3, t.$4, t.$5, t.$6, METADATA$FILENAME, METADATA$START_SCAN_TIME
  FROM @CHINOOK_STAGE t
)
PATTERN = '^(.*/)?trackplays[.]csv([.]gz)?$'
FILE_FORMAT = (FORMAT_NAME = 'RAW.CHINOOK.CHINOOK_CSV')
ON_ERROR = 'ABORT_STATEMENT';

-- E. Row counts after loading: expect 18, 8715, 2000
SELECT 'PLAYLIST' AS table_name, COUNT(*) AS row_count FROM PLAYLIST
UNION ALL SELECT 'PLAYLISTTRACK', COUNT(*) FROM PLAYLISTTRACK
UNION ALL SELECT 'TRACKPLAYS', COUNT(*) FROM TRACKPLAYS;


-- =====================================================================
-- STEP 5 · Verify the 3 RAW tables (19 checks)
-- Run in: Snowsight (role SYSADMIN)
-- Counts, keys, every play on its playlist, seconds within track length,
-- dates inside dim_date. Result: 19/19 PASS.
-- =====================================================================
USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA RAW.CHINOOK;

WITH checks AS (
    SELECT 1 AS n, 'PLAYLIST row count' AS check_name, 18 AS expected,
           (SELECT COUNT(*) FROM PLAYLIST) AS actual

    UNION ALL SELECT 2, 'PLAYLIST distinct PLAYLISTID', 18,
           (SELECT COUNT(DISTINCT PLAYLISTID) FROM PLAYLIST)

    UNION ALL SELECT 3, 'PLAYLIST 5 name is 90’s Music (curly apostrophe kept)', 1,
           (SELECT COUNT(*) FROM PLAYLIST WHERE PLAYLISTID = 5 AND NAME = '90’s Music')

    UNION ALL SELECT 4, 'PLAYLISTTRACK row count', 8715,
           (SELECT COUNT(*) FROM PLAYLISTTRACK)

    UNION ALL SELECT 5, 'PLAYLISTTRACK distinct (PLAYLISTID, TRACKID) pairs', 8715,
           (SELECT COUNT(*) FROM (SELECT DISTINCT PLAYLISTID, TRACKID FROM PLAYLISTTRACK))

    UNION ALL SELECT 6, 'PLAYLISTTRACK.PLAYLISTID values missing from PLAYLIST', 0,
           (SELECT COUNT(*) FROM PLAYLISTTRACK pt
             WHERE NOT EXISTS (SELECT 1 FROM PLAYLIST p WHERE p.PLAYLISTID = pt.PLAYLISTID))

    UNION ALL SELECT 7, 'PLAYLISTTRACK.TRACKID values missing from TRACK', 0,
           (SELECT COUNT(*) FROM PLAYLISTTRACK pt
             WHERE NOT EXISTS (SELECT 1 FROM TRACK t WHERE t.TRACKID = pt.TRACKID))

    UNION ALL SELECT 8, 'TRACKPLAYS row count', 2000,
           (SELECT COUNT(*) FROM TRACKPLAYS)

    UNION ALL SELECT 9, 'TRACKPLAYS distinct PLAYEVENTID', 2000,
           (SELECT COUNT(DISTINCT PLAYEVENTID) FROM TRACKPLAYS)

    UNION ALL SELECT 10, 'TRACKPLAYS.CUSTOMERID values missing from CUSTOMER', 0,
           (SELECT COUNT(*) FROM TRACKPLAYS tp
             WHERE NOT EXISTS (SELECT 1 FROM CUSTOMER c WHERE c.CUSTOMERID = tp.CUSTOMERID))

    UNION ALL SELECT 11, 'TRACKPLAYS.TRACKID values missing from TRACK', 0,
           (SELECT COUNT(*) FROM TRACKPLAYS tp
             WHERE NOT EXISTS (SELECT 1 FROM TRACK t WHERE t.TRACKID = tp.TRACKID))

    UNION ALL SELECT 12, 'TRACKPLAYS.PLAYLISTID values missing from PLAYLIST', 0,
           (SELECT COUNT(*) FROM TRACKPLAYS tp
             WHERE NOT EXISTS (SELECT 1 FROM PLAYLIST p WHERE p.PLAYLISTID = tp.PLAYLISTID))

    UNION ALL SELECT 13, 'Plays whose track is not on that playlist (PLAYLISTTRACK)', 0,
           (SELECT COUNT(*) FROM TRACKPLAYS tp
             WHERE NOT EXISTS (SELECT 1 FROM PLAYLISTTRACK pt
                                WHERE pt.PLAYLISTID = tp.PLAYLISTID
                                  AND pt.TRACKID = tp.TRACKID))

    UNION ALL SELECT 14, 'Plays with SECONDSPLAYED outside 1 to the track length', 0,
           (SELECT COUNT(*) FROM TRACKPLAYS tp
              JOIN TRACK t ON t.TRACKID = tp.TRACKID
             WHERE tp.SECONDSPLAYED < 1
                OR tp.SECONDSPLAYED > ROUND(t.MILLISECONDS / 1000))

    UNION ALL SELECT 15, 'Sum of TRACKPLAYS.SECONDSPLAYED', 934348,
           (SELECT SUM(SECONDSPLAYED) FROM TRACKPLAYS)

    UNION ALL SELECT 16, 'Plays dated outside 2009-01-01 to 2013-12-22 (the generator range)', 0,
           (SELECT COUNT(*) FROM TRACKPLAYS
             WHERE CAST(PLAYEDAT AS DATE) NOT BETWEEN '2009-01-01' AND '2013-12-22')

    UNION ALL SELECT 17, 'Distinct customers who played something', 59,
           (SELECT COUNT(DISTINCT CUSTOMERID) FROM TRACKPLAYS)

    UNION ALL SELECT 18, 'Distinct playlists played from (4 playlists have no tracks)', 14,
           (SELECT COUNT(DISTINCT PLAYLISTID) FROM TRACKPLAYS)

    UNION ALL SELECT 19, 'Rows missing _SOURCE_FILE or _LOADED_AT (3 tables)', 0,
           (SELECT (SELECT COUNT(*) FROM PLAYLIST WHERE _SOURCE_FILE IS NULL OR _LOADED_AT IS NULL)
                 + (SELECT COUNT(*) FROM PLAYLISTTRACK WHERE _SOURCE_FILE IS NULL OR _LOADED_AT IS NULL)
                 + (SELECT COUNT(*) FROM TRACKPLAYS WHERE _SOURCE_FILE IS NULL OR _LOADED_AT IS NULL))
)
SELECT n, check_name, expected, actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS result
FROM checks
ORDER BY n;


-- =====================================================================
-- STEP 6 · dbt: dim_playlist and fact_track_playtime
-- Run in: dbt platform Studio IDE, branch track-playtime (merged to main by pull request)
-- Reuses dim_date, dim_customer and dim_track unchanged. Run: dbt build
-- -> 8 models + 69 tests = 77 PASS.
-- =====================================================================

-- ---- 6A · Lines added to models/chinook/_chinook__sources.yml --------
/* YAML added under sources > chinook > tables

- name: playlist
- name: playlisttrack
- name: trackplays
  description: "SIMULATED play events (Chinook has no play-event table). Generated with seed 722 from real customer, playlist and track IDs."
*/

-- ---- 6B · models/chinook/02_track_playtime/dim_playlist.sql · one row per playlist (18); names repeat, so group by playlistkey ---
{{ config(materialized='table') }}

with stg_playlist as (
    select * from {{ source('chinook', 'playlist') }}
)

select
    p.playlistid    as playlistkey,
    p.playlistid    as playlistid,
    p.name          as playlistname

from stg_playlist as p

-- ---- 6C · models/chinook/02_track_playtime/fact_track_playtime.sql · one row per play (2,000) ---
{{ config(materialized='table') }}

with stg_trackplays as (
    select * from {{ source('chinook', 'trackplays') }}
),

stg_track as (
    select * from {{ source('chinook', 'track') }}
)

select
    tp.playeventid                                  as playeventid,
    tp.playlistid                                   as playlistkey,
    tp.trackid                                      as trackkey,
    tp.customerid                                   as customerkey,
    cast(tp.playedat as date)                       as playdatekey,
    tp.playedat                                     as playedat,
    tp.secondsplayed                                as secondsplayed,
    cast(round(t.milliseconds / 1000) as int)       as trackdurationseconds,
    cast(1 as int)                                  as playcount

from stg_trackplays as tp

-- The inner join loses no rows: every TRACKPLAYS.TRACKID exists in TRACK
-- (STEP 5, check 11).
inner join stg_track as t
    on t.trackid = tp.trackid

-- ---- 6D · models/chinook/02_track_playtime/_track_playtime__models.yml · 18 tests ---
/* models/chinook/02_track_playtime/_track_playtime__models.yml

version: 2

models:
  - name: dim_playlist
    description: "One row per playlist."
    columns:
      - name: playlistkey
        description: "Dimension key (the source PlaylistId)"
        data_tests:
          - unique
          - not_null
      - name: playlistid
        description: "Primary key of the source system table"
        data_tests:
          - unique
          - not_null
      - name: playlistname
        description: "Name of the playlist; can be NULL in the source (Playlist.Name allows NULL)"

  - name: fact_track_playtime
    description: "One row per track played; each row is unique by playeventid. SIMULATED source: Chinook has no play-event table."
    columns:
      - name: playeventid
        description: "Source key of the play event; used for drill-through"
        data_tests:
          - unique
          - not_null
      - name: playlistkey
        description: "Dimension FK for dim_playlist; the playlist the track was played from"
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('dim_playlist')
                field: playlistkey
      - name: trackkey
        description: "Dimension FK for dim_track; Gives name, genre, media type, artist, album"
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('dim_track')
                field: trackkey
      - name: customerkey
        description: "Dimension FK for dim_customer; the customer who played the track"
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('dim_customer')
                field: customerkey
      - name: playdatekey
        description: "Dimension FK for dim_date; the play date"
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('dim_date')
                field: datekey
      - name: playedat
        description: "Date and time of the play; degenerate (there is no time dimension)"
        data_tests:
          - not_null
      - name: secondsplayed
        description: "Seconds of the track that were played; Additive"
        data_tests:
          - not_null
      - name: trackdurationseconds
        description: "Full length of the track in seconds; Additive; divide secondsplayed by it for the completion rate"
        data_tests:
          - not_null
      - name: playcount
        description: "So plays can be counted; Always 1; Additive"
        data_tests:
          - not_null
*/


-- =====================================================================
-- STEP 7 · Verify the Track Playtime star (20 checks)
-- Run in: Snowsight (role ACCOUNTADMIN, warehouse TRANSFORMING)
-- Includes the conformed keys, drill-across counts through DIM_DATE and
-- DIM_TRACK, and FACT_SALE unchanged. Result: 20/20 PASS.
-- =====================================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE TRANSFORMING;
USE SCHEMA ANALYTICS.DBT_DRAMASRAY_CHINOOK;

WITH checks AS (
    SELECT 1 AS n, 'DIM_PLAYLIST row count' AS check_name, 18 AS expected,
           (SELECT COUNT(*) FROM DIM_PLAYLIST) AS actual

    UNION ALL SELECT 2, 'FACT_TRACK_PLAYTIME row count', 2000,
           (SELECT COUNT(*) FROM FACT_TRACK_PLAYTIME)

    UNION ALL SELECT 3, 'FACT_TRACK_PLAYTIME distinct PLAYEVENTID', 2000,
           (SELECT COUNT(DISTINCT PLAYEVENTID) FROM FACT_TRACK_PLAYTIME)

    UNION ALL SELECT 4, 'Sum of PLAYCOUNT', 2000,
           (SELECT SUM(PLAYCOUNT) FROM FACT_TRACK_PLAYTIME)

    UNION ALL SELECT 5, 'Sum of SECONDSPLAYED (same as RAW)', 934348,
           (SELECT SUM(SECONDSPLAYED) FROM FACT_TRACK_PLAYTIME)

    UNION ALL SELECT 6, 'Sum of TRACKDURATIONSECONDS', 1150714,
           (SELECT SUM(TRACKDURATIONSECONDS) FROM FACT_TRACK_PLAYTIME)

    UNION ALL SELECT 7, 'Full plays (SECONDSPLAYED = TRACKDURATIONSECONDS)', 1210,
           (SELECT COUNT(*) FROM FACT_TRACK_PLAYTIME
             WHERE SECONDSPLAYED = TRACKDURATIONSECONDS)

    UNION ALL SELECT 8, 'Plays with SECONDSPLAYED outside 1 to TRACKDURATIONSECONDS', 0,
           (SELECT COUNT(*) FROM FACT_TRACK_PLAYTIME
             WHERE SECONDSPLAYED < 1 OR SECONDSPLAYED > TRACKDURATIONSECONDS)

    UNION ALL SELECT 9, 'PLAYLISTKEY values missing from DIM_PLAYLIST', 0,
           (SELECT COUNT(*) FROM FACT_TRACK_PLAYTIME f
             WHERE NOT EXISTS (SELECT 1 FROM DIM_PLAYLIST d WHERE d.PLAYLISTKEY = f.PLAYLISTKEY))

    UNION ALL SELECT 10, 'TRACKKEY values missing from DIM_TRACK (conformed)', 0,
           (SELECT COUNT(*) FROM FACT_TRACK_PLAYTIME f
             WHERE NOT EXISTS (SELECT 1 FROM DIM_TRACK d WHERE d.TRACKKEY = f.TRACKKEY))

    UNION ALL SELECT 11, 'CUSTOMERKEY values missing from DIM_CUSTOMER (conformed)', 0,
           (SELECT COUNT(*) FROM FACT_TRACK_PLAYTIME f
             WHERE NOT EXISTS (SELECT 1 FROM DIM_CUSTOMER d WHERE d.CUSTOMERKEY = f.CUSTOMERKEY))

    UNION ALL SELECT 12, 'PLAYDATEKEY values missing from DIM_DATE (conformed)', 0,
           (SELECT COUNT(*) FROM FACT_TRACK_PLAYTIME f
             WHERE NOT EXISTS (SELECT 1 FROM DIM_DATE d WHERE d.DATEKEY = f.PLAYDATEKEY))

    UNION ALL SELECT 13, 'Plays whose track is not on that playlist (RAW PLAYLISTTRACK)', 0,
           (SELECT COUNT(*) FROM FACT_TRACK_PLAYTIME f
             WHERE NOT EXISTS (SELECT 1 FROM RAW.CHINOOK.PLAYLISTTRACK pt
                                WHERE pt.PLAYLISTID = f.PLAYLISTKEY
                                  AND pt.TRACKID = f.TRACKKEY))

    UNION ALL SELECT 14, 'Distinct customers', 59,
           (SELECT COUNT(DISTINCT CUSTOMERKEY) FROM FACT_TRACK_PLAYTIME)

    UNION ALL SELECT 15, 'Distinct tracks played', 688,
           (SELECT COUNT(DISTINCT TRACKKEY) FROM FACT_TRACK_PLAYTIME)

    UNION ALL SELECT 16, 'Distinct playlists played from', 14,
           (SELECT COUNT(DISTINCT PLAYLISTKEY) FROM FACT_TRACK_PLAYTIME)

    UNION ALL SELECT 17, 'Plays in 2013, through the conformed DIM_DATE', 388,
           (SELECT COUNT(*) FROM FACT_TRACK_PLAYTIME f
              JOIN DIM_DATE d ON d.DATEKEY = f.PLAYDATEKEY
             WHERE d.YEAR = 2013)

    UNION ALL SELECT 18, 'Classical plays, through the conformed DIM_TRACK', 596,
           (SELECT COUNT(*) FROM FACT_TRACK_PLAYTIME f
              JOIN DIM_TRACK d ON d.TRACKKEY = f.TRACKKEY
             WHERE d.GENRE = 'Classical')

    UNION ALL SELECT 19, 'FACT_SALE still has 2,240 rows (Music Sales unchanged)', 2240,
           (SELECT COUNT(*) FROM FACT_SALE)

    UNION ALL SELECT 20, 'FACT_TRACK_PLAYTIME.PLAYDATEKEY type is DATE (same as DIM_DATE.DATEKEY)', 1,
           (SELECT IFF(DATA_TYPE = 'DATE', 1, 0)
              FROM INFORMATION_SCHEMA.COLUMNS
             WHERE TABLE_SCHEMA = CURRENT_SCHEMA()
               AND TABLE_NAME = 'FACT_TRACK_PLAYTIME'
               AND COLUMN_NAME = 'PLAYDATEKEY')
)
SELECT n, check_name, expected, actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS result
FROM checks
ORDER BY n;


-- =====================================================================
-- STEP 8 · Power BI: model, measures and the Track Playtime dashboard
-- Run in: Power BI Desktop (MusicSales.pbix, same file as Music Sales)
-- =====================================================================
/* Power BI build notes

Tables added: DIM_PLAYLIST, FACT_TRACK_PLAYTIME (Import). Don't summarize on
  PLAYEVENTID, PLAYLISTKEY, TRACKKEY and CUSTOMERKEY.
Relationships (many-to-one, single direction, active; 9 in the file):
  FACT_TRACK_PLAYTIME[PLAYLISTKEY] -> DIM_PLAYLIST[PLAYLISTKEY]
  FACT_TRACK_PLAYTIME[TRACKKEY]    -> DIM_TRACK[TRACKKEY]        (shared)
  FACT_TRACK_PLAYTIME[CUSTOMERKEY] -> DIM_CUSTOMER[CUSTOMERKEY]  (shared)
  FACT_TRACK_PLAYTIME[PLAYDATEKEY] -> DIM_DATE[DATEKEY]          (shared)
Dashboard page "Track Playtime (simulated)", 1280 x 720:
  - Header text: "Play data is simulated; Chinook has no play events."
  - Year tile slicer (copied from Music Sales, not synced)
  - KPI tiles: 2,000 plays | 259.54 hours | 467.17 s per play | 1,210 full | 59 listeners
  - Plays by quarter (area chart, sorted by YEAR QUARTER): low 72, high 114 (2010)
  - Completion rate gauge (min 0, max 1): 81.2%
  - Drill-across table by DIM_TRACK[GENRE]: Total Sales (FACT_SALE) beside
    Play Count (FACT_TRACK_PLAYTIME), data bars. Rock $826.65 / 351;
    Classical $40.59 / 596 (Classical's lead is a simulation artefact).
  - Plays by playlist (bar, colour = Completion Rate): Music 296, TV Shows 296
*/
/* DAX measures (home table FACT_TRACK_PLAYTIME)

// Expected: 2,000
Play Count = SUM ( FACT_TRACK_PLAYTIME[PLAYCOUNT] )

// Expected: 934,348
Total Seconds Played = SUM ( FACT_TRACK_PLAYTIME[SECONDSPLAYED] )

// Expected: 259.54
Total Hours Played = DIVIDE ( [Total Seconds Played], 3600 )

// Expected: 467.17
Average Seconds per Play = DIVIDE ( [Total Seconds Played], [Play Count] )

// Expected: 0.81 (format as a percentage: 81.2%)
Completion Rate = DIVIDE ( SUM ( FACT_TRACK_PLAYTIME[SECONDSPLAYED] ), SUM ( FACT_TRACK_PLAYTIME[TRACKDURATIONSECONDS] ) )

// Expected: 1,210
Full Plays = CALCULATE ( [Play Count], FILTER ( FACT_TRACK_PLAYTIME, FACT_TRACK_PLAYTIME[SECONDSPLAYED] = FACT_TRACK_PLAYTIME[TRACKDURATIONSECONDS] ) )

// Expected: 59
Listeners = DISTINCTCOUNT ( FACT_TRACK_PLAYTIME[CUSTOMERKEY] )
*/

-- End of track_playtime.sql
