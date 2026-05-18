{{ config(materialized="table", schema="gold") }}

-- dim_stores
--
-- Store dimension derived entirely from observed transaction data.
-- Each row represents one store with its lifetime activity metadata.
--
-- Grain: one row per store_code
-- 
-- NOTE: This dimension is intentionally thin because the source data does
-- not include a store master table (no name, region, city, etc.). In a
-- production setup, these attributes would be sourced from an ERP system
-- or master data system and joined in here.


with
    silver as (
        select *
        from {{ ref('stg_sales') }}
        where store_code is not null
    ),

    store_activity as (
        select
            store_code,
            min(transaction_date) as first_transaction_date,
            max(transaction_date) as last_transaction_date,
            count(*) as total_lifetime_transactions,
            count(distinct customer_id) as total_lifetime_unique_customers,
            sum(total_amount) as total_lifetime_revenue
        from silver
        group by store_code
    )

select *
from store_activity
order by store_code