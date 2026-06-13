with orders as (

    select * from {{ ref('stg_ecom__orders') }}

),

deduped as (

    select distinct
        user_id
    from orders

),

final as (

    select
        {{ dbt_utils.generate_surrogate_key(['user_id']) }} as user_master_id
        ,user_id
    from deduped

)

select * from final
