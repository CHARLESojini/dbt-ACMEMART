{{ config(materialized="table", schema="gold") }}

-- dim_date
--
-- Calendar dimension generated from a seed CSV. Provides date-based
-- attributes for time-series analysis and grouping in BI tools.
--
-- Grain: one row per calendar date
-- Source: seeds/dim_date_seed.csv (365 dates starting 2026-01-01)


select
    date_key,
    day_of_week,
    day_of_month,
    month_name,
    quarter,
    year,
    is_weekend
from {{ ref('dim_date_seed') }}