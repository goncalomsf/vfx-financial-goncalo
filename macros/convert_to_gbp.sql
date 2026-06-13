{% macro convert_to_gbp(amount_column, rate_column) %}
    {{ amount_column }} * {{ rate_column }}
{% endmacro %}
