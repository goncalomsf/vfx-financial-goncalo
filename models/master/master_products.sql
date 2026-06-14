with orders as (

    select * from {{ ref('stg_ecom__orders') }}

),

deduped as (

    select distinct
        product_id
        ,product_category
        ,price_usd
    from orders

),

final as (

    select
        {{ dbt_utils.generate_surrogate_key(['product_id']) }} as product_master_id
        ,product_id
        ,product_category
        ,price_usd as product_price_usd
    from deduped

)

select * from final
