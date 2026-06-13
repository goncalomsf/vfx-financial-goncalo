with source as (

    select * from {{ source('ecom', 'ecommerce_dataset_updated') }}

),

renamed as (

    select
        User_ID as user_id
        ,Product_ID as product_id
        ,lower(replace(Category, ' ', '_')) as product_category
        ,Price_Rs as price_usd
        ,Discount as discount_percentage
        ,Final_Price_Rs as final_price_usd
        ,lower(replace(Payment_Method, ' ', '_')) as payment_method
        ,Purchase_Date as order_date
    from source

)

select * from renamed
