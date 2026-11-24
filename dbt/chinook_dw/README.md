# dbt project: chinook_dw

This one dbt project builds all three of Darrel's business processes from `RAW.CHINOOK`, grouped so each process's models sit together:

```
models/chinook/
  _chinook__sources.yml        the 13 RAW tables (2 simulated)
  shared_dimensions/           conformed: used by two or more processes
    dim_date  dim_customer  dim_employee  dim_track   + 29 tests
  01_music_sales/
    fact_sale  dim_invoice                            + 22 tests
  02_track_playtime/
    fact_track_playtime  dim_playlist                 + 18 tests
  03_employee_hire/
    fact_employee                                     + 10 tests
```

- **Which process uses which dimension:**
  - Music Sales: `dim_date`, `dim_customer`, `dim_employee`, `dim_track`, `dim_invoice`
  - Track Playtime: `dim_date`, `dim_customer`, `dim_track`, `dim_playlist`
  - Employee Hire: `dim_date`, `dim_employee`
- **Run:** `dbt build`, which gives 9 models and 79 tests, all passing. `dbt_project.yml` builds every model under `models/chinook` (all subfolders) as a table in `<dev schema>_CHINOOK`, for example `ANALYTICS.DBT_DRAMASRAY_CHINOOK`.
- **dbt platform copy:** the live project is in repository `DarrelRamasray/ist722dbt`, folder `music_sales` (its Milestone 2 name). There, all these files sit in one `models/chinook` folder and the Music Sales and shared-dimension tests are one file, `_chinook__models.yml`. The models, tests and tables are the same; only the folders differ.
