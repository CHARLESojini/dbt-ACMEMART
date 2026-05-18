{{ config(materialized="table", schema="gold") }}

-- dim_customers
--
-- Customer dimension with behavioral segmentation derived from purchase data.
--
-- Customer segments are bucketed by lifetime spend:
--   - high_value:     >= $500 lifetime
--   - regular:        $100 - $499 lifetime
--   - occasional:     < $100 lifetime
--
-- Grain: one row per customer_id

with
    silver as (
        select *
        from {{ ref('stg_sales') }}
        where customer_id is not null
    ),

    customer_metrics as (
        select
            customer_id,
            min(transaction_date) as first_purchase_date,
            max(transaction_date) as last_purchase_date,
            count(*) as total_lifetime_transactions,
            sum(quantity) as total_lifetime_units_purchased,
            sum(total_amount) as total_lifetime_spend,
            avg(total_amount) as avg_transaction_value,
            count(distinct store_code) as distinct_stores_visited
        from silver
        group by customer_id
    ),

    with_segmentation as (
        select
            *,
            case
                when total_lifetime_spend >= 500 then 'high_value'
                when total_lifetime_spend >= 100 then 'regular'
                else 'occasional'
            end as customer_segment,
            datediff('day', first_purchase_date, last_purchase_date) as customer_lifespan_days
        from customer_metrics
    )

select *
from with_segmentation
order by customer_id