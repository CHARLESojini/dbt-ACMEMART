{{ config(materialized="view", schema="silver") }}

with
    source as (select * from {{ source("bronze", "sales_csv") }}),

    cleaned as (

        select
            -- primary key
            transaction_id,

            -- extracted from transaction_id (composite key pattern: STORE-YYYYMMDD-SEQ)
            split_part(transaction_id, '-', 1) as store_code,
            try_to_date(
                split_part(transaction_id, '-', 2), 'YYYYMMDD'
            ) as transaction_date_from_id,
            try_cast(split_part(transaction_id, '-', 3) as integer) as daily_sequence,

            -- identifiers
            cast(customer_id as varchar) as customer_id,
            cast(store_id as varchar) as store_id,
            cast(product_id as varchar) as product_id,

            -- descriptive attributes (normalized)
            upper(trim(category)) as category,
            trim(product_name) as product_name,
            upper(trim(payment_method)) as payment_method,

            -- numeric measures
            try_cast(quantity as integer) as quantity,
            try_cast(unit_price as decimal(10, 2)) as unit_price,
            try_cast(total_amount as decimal(12, 2)) as total_amount,

            -- data quality flag
            case
                when
                    try_cast(quantity as integer)
                    * try_cast(unit_price as decimal(10, 2))
                    = try_cast(total_amount as decimal(12, 2))
                then true
                else false
            end as is_total_amount_valid,

            -- timestamps
            try_cast(transaction_timestamp as timestamp_ntz) as transaction_timestamp,
            cast(
                try_cast(transaction_timestamp as timestamp_ntz) as date
            ) as transaction_date,

            -- audit / lineage
            _airbyte_extracted_at as loaded_at,
            _ab_source_file_url as source_file_url

        from source
        where transaction_id is not null

    )

select *
from cleaned
