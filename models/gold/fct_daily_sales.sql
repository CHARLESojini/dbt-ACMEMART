{{ config(materialized="table", schema="gold") }}

-- fct_daily_sales
-- 
-- Daily fact table aggregating sales transactions to the store-day grain.
-- Built from cleaned silver-layer data. Used by downstream BI dashboards
-- and operational reporting.
--
-- Grain: one row per (transaction_date, store_code)
-- Refresh strategy: full-refresh (materialized as table for query performance)

with
    silver as (
        select *
        from {{ ref('stg_sales') }}
        where transaction_date is not null  -- exclude any residual data quality misses
    ),

    daily_aggregates as (
        select
            -- grain
            transaction_date,
            store_code,

            -- volume metrics
            count(*) as transaction_count,
            count(distinct customer_id) as unique_customers,
            sum(quantity) as total_units_sold,

            -- revenue metrics
            sum(total_amount) as gross_revenue,
            avg(total_amount) as avg_transaction_value,
            min(total_amount) as min_transaction_value,
            max(total_amount) as max_transaction_value,

            -- data quality metric
            sum(case when is_total_amount_valid then 1 else 0 end) as valid_transaction_count,
            round(
                sum(case when is_total_amount_valid then 1 else 0 end) * 100.0
                / count(*),
                2
            ) as valid_transaction_rate_pct,

            -- audit / lineage
            max(loaded_at) as last_loaded_at

        from silver
        group by transaction_date, store_code
    )

select *
from daily_aggregates
order by transaction_date desc, gross_revenue desc