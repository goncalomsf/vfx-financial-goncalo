with orders as (

    select * from {{ ref('stg_ecom__orders') }}

),

fx_rates as (

    select
        date as fx_rate_date
        ,usd_to_gbp_rate
    from {{ ref('usd_to_gbp_rate') }}

),

joined as (

    select
        orders.user_id
        ,orders.product_id
        ,orders.discount_percentage
        ,orders.final_price_usd
        ,orders.payment_method
        ,orders.order_date
        ,fx_rates.usd_to_gbp_rate
    from orders
    left join fx_rates
        on orders.order_date = fx_rates.fx_rate_date

),

final as (

    select
        {{ dbt_utils.generate_surrogate_key(['user_id', 'product_id', 'order_date']) }} as order_master_id
        ,{{ dbt_utils.generate_surrogate_key(['user_id']) }} as user_master_id
        ,{{ dbt_utils.generate_surrogate_key(['product_id']) }} as product_master_id
        ,discount_percentage
        ,final_price_usd
        ,{{ convert_to_gbp('final_price_usd', 'usd_to_gbp_rate') }} as final_price_gbp
        ,payment_method
        ,order_date
    from joined

)

select * from final
