# IST 722 Data Warehouse · Team DIM Data

Syracuse University, Fall 2026
Team: Darrel Ramasray, Insha Maniyar, Melanie Thomas.

A Kimball-style data warehouse for the Chinook digital music store. It uses a bus matrix, conformed dimensions and one star schema per business process, built in Snowflake with dbt and reported in Power BI.

**Pipeline:** Chinook (school SQL Server) → CSV → Snowflake `RAW.CHINOOK` → dbt → `ANALYTICS.DBT_DRAMASRAY_CHINOOK` → Power BI (`MusicSales.pbix`)

## Business processes

| # | Process | Owner | Star schema | Code |
| --- | --- | --- | --- | --- |
| 01 | Employee Hire (salary simulated) | Darrel | `fact_employee` + the shared `dim_employee`, `dim_date` | [employee_hire.sql](business_processes/03_employee_hire/employee_hire.sql) |
| 02 | Music Sales | Darrel | `fact_sale` + `dim_date`, `dim_customer`, `dim_employee`, `dim_invoice`, `dim_track` | [music_sales.sql](business_processes/01_music_sales/music_sales.sql) |
| 03 | Track Playtime (plays simulated) | Darrel | `fact_track_playtime` + `dim_playlist` and the shared `dim_date`, `dim_customer`, `dim_track` | [track_playtime.sql](business_processes/02_track_playtime/track_playtime.sql) |
| 04+ | Teammates' processes | Insha, Melanie | To be added | `business_processes/04_<name>/` |

Each `.sql` file is a complete, self-contained record of one process, written as 8 steps: extract, create RAW tables, upload, load, verify RAW, dbt models and tests, verify the star, and Power BI. Each step names the tool it runs in.

## Verified results (23 November 2026)

| Process | RAW checks | dbt | Star checks | Key figures |
| --- | --- | --- | --- | --- |
| Employee Hire | 11/11 PASS | 1 model, 10 tests | 21/21 PASS | 8 hires, average age at hire 37.9 |
| Music Sales | 52/52 PASS | 6 models, 51 tests | 23/23 PASS | 2,240 sale lines, Total Sales $2,328.60 |
| Track Playtime | 19/19 PASS | 2 models, 18 tests | 20/20 PASS | 2,000 plays, 81.2% completion |
| All together | | `dbt build`: 9 models + 79 tests = 88 PASS | | |

## Repository layout

```
business_processes/
  01_employee_hire/employee_hire.sql
  01_employee_hire/simulated_data/      employeesalary.csv + generate_employeesalary.py
  02_music_sales/music_sales.sql
  03_track_playtime/track_playtime.sql
  03_track_playtime/simulated_data/     trackplays.csv + generate_trackplays.py
  _template/process_template.sql        starting point for a new process
dbt/chinook_dw/                         the runnable dbt project for processes 01-03
  models/chinook/shared_dimensions/     dim_date, dim_customer, dim_employee, dim_track (conformed)
  models/chinook/01_employee_hire/      fact_employee
  models/chinook/02_music_sales/        fact_sale, dim_invoice
  models/chinook/03_track_playtime/     fact_track_playtime, dim_playlist
powerbi/                                theme, every DAX measure, report file
docs/                                   bus matrix workbook, decks, project document
```

## Simulated data

Chinook has no play events and no salaries, so two sources are generated with a fixed seed (722) and labelled as simulated everywhere they appear:

- **`employeesalary.csv`** (8 salaries) draws each salary inside a fixed range for the employee's real job title.
- **`trackplays.csv`** (2,000 plays) uses real customer, playlist and track IDs, and every track played is on its playlist.

The generators are next to each file, so the data can be recreated exactly.

## Conformed dimensions

`dim_date`, `dim_customer`, `dim_track` and `dim_employee` are built once, in `dbt/chinook_dw/models/chinook/shared_dimensions/`, and shared by the fact tables. This is what lets the reports drill across processes:

- hire facts beside sales by employee, through `dim_employee`
- Total Sales beside Play Count by genre, through `dim_track`

`dim_date` covers every full calendar year from the first hire (2002) to the last invoice (2013): 4,383 days.

## Security

No private keys, passwords or connection files are stored in this repository, and `.gitignore` blocks them. Snowflake and dbt sign in with key-pair authentication, configured outside the repository.

## Adding a business process (teammates)

1. Copy `business_processes/_template/process_template.sql` to `business_processes/NN_<process_name>/<process_name>.sql`, using the next number.
2. Fill in its 8 steps with the scripts you ran, keeping comments short.
3. Put any generated data in a `simulated_data/` folder next to it, with its generator.
4. Add your row to the two tables above.
