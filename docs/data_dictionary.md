# Data Dictionary — dbt-ACMEMART

This document catalogs every table and column in the `dbt-ACMEMART` project across the bronze, silver, and gold layers. For each column it lists the data type, description, tests applied, and source.

For the visual schema, see [`docs/erd.png`](erd.png).

---

## Layer Overview

| Layer | Schema | Description |
|---|---|---|
| **Bronze** | `ACMEMART.bronze` | Raw data ingested by Airbyte from Google Drive. All columns stored as VARCHAR. |
| **Silver** | `ACMEMART.dbt_chima_silver` | Cleaned, typed, validated transactions. Materialized as a view. |
| **Gold** | `ACMEMART.dbt_chima_gold` | Star schema (fact + 4 dimensions). Materialized as tables for query performance. |

---

## Bronze Layer

### `bronze.sales_csv`

Raw sales transactions ingested from a CSV file in Google Drive via Airbyte. All business columns are stored as VARCHAR because CSV is a typeless format; type enforcement is deferred to the silver layer.

**Grain:** One row per raw transaction record.

| Column | Type | Description | Tests |
|---|---|---|---|
| `transaction_id` | VARCHAR | Composite key in format `STORE-YYYYMMDD-SEQ`. Primary key. | `not_null`, `unique` |
| `transaction_timestamp` | VARCHAR | Transaction occurrence time as raw string. Mixed formats (ISO + DD/MM/YYYY); parsed defensively in silver. | — |
| `store_id` | VARCHAR | Store identifier. | — |
| `customer_id` | VARCHAR | Purchasing customer identifier. | — |
| `product_id` | VARCHAR | Product identifier. | — |
| `product_name` | VARCHAR | Human-readable product name. May contain whitespace; trimmed in silver. | — |
| `category` | VARCHAR | Product category. Normalized to uppercase in silver. | — |
| `quantity` | VARCHAR | Units sold per transaction. Cast to INTEGER in silver. | — |
| `unit_price` | VARCHAR | Price per unit. Cast to DECIMAL(10,2) in silver. | — |
| `total_amount` | VARCHAR | Transaction total. Cast to DECIMAL(12,2) in silver; validated against `quantity * unit_price`. | — |
| `payment_method` | VARCHAR | Payment method used. Normalized to uppercase in silver. | — |
| `_airbyte_extracted_at` | TIMESTAMP_TZ | Airbyte sync timestamp. Will anchor freshness checks when contract is re-enabled. | `not_null` |
| `_airbyte_raw_id` | VARCHAR | Airbyte-assigned unique identifier for the raw record. | — |
| `_airbyte_meta` | VARIANT | Airbyte sync metadata. | — |
| `_airbyte_generation_id` | NUMBER | Airbyte generation identifier. | — |
| `_ab_source_file_url` | VARCHAR | URL of the source CSV file in Google Drive. | — |
| `_ab_source_file_last_modified` | VARCHAR | Last-modified timestamp of the source file. | — |

---

## Silver Layer

### `dbt_chima_silver.stg_sales`

Cleaned, typed, and validated sales transactions. Applies defensive type coercion, multi-format timestamp parsing, and a data quality flag. Materialized as a view.

**Grain:** One row per transaction.

| Column | Type | Description | Tests |
|---|---|---|---|
| `transaction_id` | VARCHAR | Unique identifier for each sales transaction. Primary key. | `not_null`, `unique` |
| `store_code` | VARCHAR | Store code extracted from `transaction_id` via `SPLIT_PART`. | — |
| `transaction_date_from_id` | DATE | Transaction date parsed from the date segment of `transaction_id`. | — |
| `daily_sequence` | INTEGER | Sequence number within the store-day, parsed from `transaction_id`. Defaults to 0 if parsing fails. | — |
| `customer_id` | VARCHAR | Customer identifier. | — |
| `store_id` | VARCHAR | Store identifier (raw). | — |
| `product_id` | VARCHAR | Product identifier. | — |
| `category` | VARCHAR | Product category, uppercased and trimmed. | — |
| `product_name` | VARCHAR | Product name, trimmed. | — |
| `payment_method` | VARCHAR | Payment method, uppercased and trimmed. | — |
| `quantity` | INTEGER | Units sold per transaction (cast from VARCHAR). | — |
| `unit_price` | DECIMAL(10,2) | Price per unit (cast from VARCHAR). | — |
| `total_amount` | DECIMAL(12,2) | Total transaction amount (cast from VARCHAR). | — |
| `is_total_amount_valid` | BOOLEAN | Data quality flag: `true` when `quantity * unit_price = total_amount`. | `not_null`, `accepted_values: [true, false]` |
| `transaction_timestamp` | TIMESTAMP_NTZ | Parsed transaction time. Uses `COALESCE` of multiple format attempts (ISO, DD/MM/YYYY, MM/DD/YYYY) for defensive parsing. | `not_null` |
| `transaction_date` | DATE | Date portion of `transaction_timestamp`. | `not_null` |
| `loaded_at` | TIMESTAMP_TZ | Airbyte ingestion timestamp from the source. | — |
| `source_file_url` | VARCHAR | URL of the originating CSV in Google Drive. | — |

---

## Gold Layer

### `dbt_chima_gold.fct_daily_sales`

Daily store-grain fact table. Aggregates silver transactions to one row per (date, store). Includes business KPIs and a first-class data quality metric. Materialized as a table for BI query performance.

**Grain:** One row per (`transaction_date`, `store_code`).

| Column | Type | Description | Tests |
|---|---|---|---|
| `transaction_date` | DATE | Calendar date the transactions occurred. Part of composite primary key. | `not_null` |
| `store_code` | VARCHAR | Store identifier. Part of composite primary key. Foreign key to `dim_stores`. | `not_null` |
| `transaction_count` | INTEGER | Number of distinct transactions for this store on this date. | `not_null` |
| `unique_customers` | INTEGER | Count of distinct customers transacting at this store on this date. | `not_null` |
| `total_units_sold` | INTEGER | Sum of quantities across all transactions for this store-day. | `not_null` |
| `gross_revenue` | DECIMAL(12,2) | Total revenue for this store-day. | `not_null` |
| `avg_transaction_value` | DECIMAL(10,2) | Average transaction size (basket value). | `not_null` |
| `min_transaction_value` | DECIMAL(10,2) | Smallest transaction value for this store-day. | — |
| `max_transaction_value` | DECIMAL(10,2) | Largest transaction value for this store-day. | — |
| `valid_transaction_count` | INTEGER | Count of transactions passing the `is_total_amount_valid` check. | — |
| `valid_transaction_rate_pct` | DECIMAL(5,2) | Percentage of transactions that passed validation. Data quality KPI surfaced as a business metric. | `not_null` |
| `last_loaded_at` | TIMESTAMP | Most recent Airbyte ingestion timestamp for transactions in this row. | — |

---

### `dbt_chima_gold.dim_stores`

Store dimension with lifetime activity metrics derived entirely from observed transaction data. Thin by design because source did not include store master data.

**Grain:** One row per `store_code`.

| Column | Type | Description | Tests |
|---|---|---|---|
| `store_code` | VARCHAR | Primary key. | `not_null`, `unique` |
| `first_transaction_date` | DATE | First date this store recorded a transaction. | `not_null` |
| `last_transaction_date` | DATE | Most recent date this store recorded a transaction. | `not_null` |
| `total_lifetime_transactions` | INTEGER | Total transaction count across the store's full history. | `not_null` |
| `total_lifetime_unique_customers` | INTEGER | Count of distinct customers who shopped at this store. | — |
| `total_lifetime_revenue` | DECIMAL(14,2) | Total revenue generated by this store across all time. | — |

---

### `dbt_chima_gold.dim_products`

Product dimension with attribute deduplication. Uses `ROW_NUMBER()` window functions to pick the most recent product attributes per `product_id` when the same product appears with different details across transactions.

**Grain:** One row per `product_id`.

| Column | Type | Description | Tests |
|---|---|---|---|
| `product_id` | VARCHAR | Primary key. | `not_null`, `unique` |
| `product_name` | VARCHAR | Most recent observed product name. | `not_null` |
| `category` | VARCHAR | Most recent observed product category. | `not_null` |
| `current_unit_price` | DECIMAL(10,2) | Most recent observed unit price. | `not_null` |
| `first_sold_date` | DATE | First date this product appeared in transactions. | — |
| `last_sold_date` | DATE | Most recent date this product appeared in transactions. | — |
| `total_lifetime_sales` | INTEGER | Total number of transactions involving this product. | — |
| `total_lifetime_units_sold` | INTEGER | Total units sold across this product's history. | — |
| `total_lifetime_revenue` | DECIMAL(14,2) | Total revenue generated by this product. | — |

---

### `dbt_chima_gold.dim_customers`

Customer dimension with behavioral segmentation derived from purchase history.

**Grain:** One row per `customer_id`.

| Column | Type | Description | Tests |
|---|---|---|---|
| `customer_id` | VARCHAR | Primary key. | `not_null`, `unique` |
| `first_purchase_date` | DATE | First date this customer made a purchase. | — |
| `last_purchase_date` | DATE | Most recent date this customer made a purchase. | — |
| `total_lifetime_transactions` | INTEGER | Total transaction count for this customer. | — |
| `total_lifetime_units_purchased` | INTEGER | Total units purchased across all transactions. | — |
| `total_lifetime_spend` | DECIMAL(14,2) | Cumulative customer revenue contribution. | `not_null` |
| `avg_transaction_value` | DECIMAL(10,2) | Average size of this customer's transactions. | — |
| `distinct_stores_visited` | INTEGER | Number of distinct stores this customer transacted at. | — |
| `customer_segment` | VARCHAR | Behavioral segment derived from lifetime spend: `high_value` (≥ $500), `regular` ($100–$499), `occasional` (< $100). | `not_null`, `accepted_values: ['high_value', 'regular', 'occasional']` |
| `customer_lifespan_days` | INTEGER | Days between first and last purchase. | — |

---

### `dbt_chima_gold.dim_date`

Calendar dimension covering one year of dates. Reference data sourced from a seed CSV — calendar facts are static and well-suited to seed-based materialization.

**Grain:** One row per calendar date.
**Coverage:** 2026-01-01 through 2026-12-31 (365 rows).

| Column | Type | Description | Tests |
|---|---|---|---|
| `date_key` | DATE | Primary key. | `not_null`, `unique` |
| `day_of_week` | VARCHAR | Day name (e.g., `Monday`). | `not_null` |
| `day_of_month` | INTEGER | Day of the month (1–31). | — |
| `month_name` | VARCHAR | Full month name (e.g., `January`). | — |
| `quarter` | INTEGER | Calendar quarter (1–4). | — |
| `year` | INTEGER | Four-digit year. | `not_null` |
| `is_weekend` | BOOLEAN | `true` for Saturday/Sunday. | `not_null` |

---

## Relationships

The gold-layer star schema uses these relationships:

| Fact / Source Table | Column | Reference | Reason |
|---|---|---|---|
| `fct_daily_sales` | `store_code` | `dim_stores.store_code` | Each daily-store row belongs to one store. |
| `fct_daily_sales` | `transaction_date` | `dim_date.date_key` | Each daily-store row belongs to one date. |
| `stg_sales` | `customer_id` | `dim_customers.customer_id` | Transactions link to customers via id. |
| `stg_sales` | `product_id` | `dim_products.product_id` | Transactions link to products via id. |

Note: dimensions are conformed (each entity has one canonical row across the warehouse), enabling consistent joins across multiple fact tables in the future.

---

## Testing Summary

The project ships with **37 automated tests** spanning three layers:

| Layer | Count | Examples |
|---|---|---|
| **Source** | 3 | `not_null` on bronze `transaction_id`, `_airbyte_extracted_at`; `unique` on bronze `transaction_id` |
| **Model** | 26 | Column-level `not_null`, `unique` across silver and gold tables |
| **Contract** | 8 | `accepted_values` on `is_total_amount_valid` and `customer_segment` |

All tests pass on every build. The test suite runs in the same `dbt build` command as model materialization, so test failures block downstream model execution by default.

---

*Last updated: May 18, 2026. To regenerate auto-documentation, run `dbt docs generate && dbt docs serve`.*