{#
  ============================================================================
   ŞEMA SEVİYESİ SİLMEYİ KİLİTLE
   dbt-oracle'ın kendi drop_schema makrosu şemadaki TÜM tablo/view/sequence/...
   nesnelerini siler (normal dbt run çağırmaz; run-operation / paket / test
   altyapısı çağırabilir). Paylaşılan şemada bunun hiçbir koşulda çalışmaması için
   root projede eziliyor: çağrılırsa SQL göndermeden hata verir.
  ============================================================================
#}
{% macro oracle__drop_schema(relation) -%}
  {%- do exceptions.raise_compiler_error("drop_schema bu projede kapalı: şemadaki tüm nesneleri silerdi (" ~ relation ~ "). Hiçbir şey silinmedi.") -%}
{%- endmacro %}

{% macro trino__drop_schema(relation) -%}
  {%- do exceptions.raise_compiler_error("drop_schema bu projede kapalı (" ~ relation ~ "). Hiçbir şey silinmedi.") -%}
{%- endmacro %}

{% macro default__drop_schema(relation) -%}
  {%- do exceptions.raise_compiler_error("drop_schema bu projede kapalı (" ~ relation ~ "). Hiçbir şey silinmedi.") -%}
{%- endmacro %}
