{#
  ============================================================================
   PAYLAŞILAN SANDBOX ŞEMASI İÇİN İSİM ÖNEKİ (sadece bu test projesine ait;
   framework'ü kendi projene taşırken bu dosyayı taşımak zorunda değilsin)

   export ODI_NAME_PREFIX=DOA_      ->  T_IU modeli DOA_T_IU tablosuna yazar,
                                         work tabloları I$_DOA_T_IU, E$_DOA_T_IU olur,
                                         kaynaklar DOA_SRC_CUSTOMER, log DOA_ODI_STEP_LOG.
   Böylece aynı şemadaki ekip arkadaşlarının tablolarıyla isim çakışması olamaz.
   vars.odi_require_name_prefix: true iken önek verilmeden hiçbir model çalışmaz.
  ============================================================================
#}
{% macro generate_alias_name(custom_alias_name=none, node=none) -%}
  {%- set base = (custom_alias_name | trim) if custom_alias_name else node.name -%}
  {%- set p = var('odi_name_prefix', '') -%}
  {%- if p and not (base | upper).startswith(p | upper) -%}
    {%- set base = p ~ base -%}
  {%- endif -%}
  {{ base }}
{%- endmacro %}
