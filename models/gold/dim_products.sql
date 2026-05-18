{{ config(materialized="table", schema="gold") }}

-- dim_products
--
-- Product dimension with deduplication. Uses ROW_NUMBER to pick the most
-- recent attribute values per product_id in case the same product appears
-- with different names/categories/prices across transactions (a common
-- real-world data integrity issue).
--
-- Grain: one row per product_id


with
    silver as (
        select *
        from {{ ref('stg_sales') }}
        where product_id is not null
    ),

    -- Window-function deduplication: pick the latest known attributes per product
    ranked as (
        select
            product_id,
            product_name,
            category,
            unit_price,
            transaction_date,
            row_number() over (
                partition by product_id 
                order by transaction_date desc
            ) as recency_rank
        from silver
    ),

    latest_attributes as (
        select
            product_id,
            product_name,
            category,
            unit_price as current_unit_price
        from ranked
        where recency_rank = 1
    ),

    lifetime_metrics as (
        select
            product_id,
            min(transaction_date) as first_sold_date,
            max(transaction_date) as last_sold_date,
            count(*) as total_lifetime_sales,
            sum(quantity) as total_lifetime_units_sold,
            sum(total_amount) as total_lifetime_revenue
        from silver
        group by product_id
    )

select
    l.product_id,
    l.product_name,
    l.category,
    l.current_unit_price,
    m.first_sold_date,
    m.last_sold_date,
    m.total_lifetime_sales,
    m.total_lifetime_units_sold,
    m.total_lifetime_revenue
from latest_attributes l
left join lifetime_metrics m on l.product_id = m.product_id
order by l.product_id