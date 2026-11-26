-- =====================================================================
-- dim_invoice.sql
-- Location: models/chinook/01_music_sales/ (dbt platform: ist722dbt, music_sales/models/chinook/)
-- Design:  dim_invoice sheet, 1. Bus_MatrixV7_simplified.xlsx
-- Grain:   one row per invoice (412 rows)
-- Every column is copied straight from RAW.CHINOOK.INVOICE.
-- =====================================================================

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
