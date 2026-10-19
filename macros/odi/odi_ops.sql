{#
  ============================================================================
   Runtime parametre + operasyon makroları
  ============================================================================
#}

{# ---------------------------------------------------------------------------
   odi_param('LOAD_DATE', default=none)
   Öncelik: 1) --vars ile verilen değer  2) parametre tablosu (AKIS_PARAM gibi)  3) default
   Parametre tablosu dbt_project.yml vars ile tanımlanır:
     odi_param_table:      ETL.AKIS_PARAM
     odi_param_name_col:   PARAM_ADI
     odi_param_value_col:  PARAM_DEGERI
     odi_param_filter:     "AKIS_ADI = 'DM_CAD'"      (opsiyonel)
   Not: config() içindeki değerler parse anında sabitlenir. Parametre tablosundan
   okunacak değerleri config'e 'param:LOAD_DATE' diye yazın; materialization
   bunu run anında çözer. Model SQL'i içinde doğrudan {{ odi_param('LOAD_DATE') }}.
--------------------------------------------------------------------------- #}
{% macro odi_param(name, default=none) %}
  {%- set v = var(name, none) -%}
  {%- if v is not none -%}{{ return(v ~ '') }}{%- endif -%}
  {%- if not execute -%}{{ return(default if default is not none else '1900-01-01') }}{%- endif -%}
  {%- set tbl = var('odi_param_table', none) -%}
  {%- if tbl -%}
    {%- set flt = var('odi_param_filter', none) -%}
    {% call statement('odi_param_q', fetch_result=True, auto_begin=False) %}
      select {{ var('odi_param_value_col', 'PARAM_VALUE') }}
        from {{ tbl }}
       where {{ var('odi_param_name_col', 'PARAM_NAME') }} = '{{ name }}'
       {%- if flt %} and ( {{ flt }} ){% endif %}
    {% endcall %}
    {%- set rows = load_result('odi_param_q')['data'] -%}
    {%- if rows | length > 1 -%}
      {%- do exceptions.raise_compiler_error("odi_param: '" ~ name ~ "' için " ~ (rows | length) ~ " satır döndü (odi_param_filter'ı daraltın).") -%}
    {%- elif rows | length == 1 -%}
      {{ return(rows[0][0] ~ '') }}
    {%- endif -%}
  {%- endif -%}
  {%- if default is not none -%}{{ return(default) }}{%- endif -%}
  {%- do exceptions.raise_compiler_error("odi_param: '" ~ name ~ "' bulunamadı (--vars, parametre tablosu, default yok).") -%}
{% endmacro %}

{# ---------------------------------------------------------------------------
   Yarım kalmış work tablolarını temizle (unique temp names / fail olmuş run'lar)
   dbt run-operation odi_drop_work_tables --args '{schema: WRK, older_than_hours: 12}'
   dbt run-operation odi_drop_work_tables --args '{schema: WRK, dry_run: true}'
--------------------------------------------------------------------------- #}
{% macro odi_drop_work_tables(schema=none, older_than_hours=0, include_errors=false, dry_run=false) %}
  {{ return(adapter.dispatch('odi_drop_work_tables')(schema, older_than_hours, include_errors, dry_run)) }}
{% endmacro %}

{# Trino: odi_i_ / odi_c_ / odi_x_ (+ odi_e_) önekli tablolar; yaş filtresi yok (information_schema'da created yok) #}
{% macro trino__odi_drop_work_tables(schema=none, older_than_hours=0, include_errors=false, dry_run=false) %}
  {%- set sch = (schema or target.schema) | lower -%}
  {%- set prefixes = ['odi\\_i\\_%', 'odi\\_c\\_%', 'odi\\_x\\_%'] + (['odi\\_e\\_%'] if include_errors else []) -%}
  {% set q %}
    select table_name from {{ target.database }}.information_schema.tables
     where table_schema = '{{ sch }}'
       and ( {% for p in prefixes %}table_name like '{{ p }}' escape '\'{{ ' or ' if not loop.last }}{% endfor %} )
     order by 1
  {% endset %}
  {%- set names = run_query(q).columns[0].values() -%}
  {%- for n in names -%}
    {%- if dry_run -%}
      {%- do log('[dry-run] drop ' ~ sch ~ '.' ~ n, info=True) -%}
    {%- else -%}
      {%- do run_query('drop table if exists ' ~ target.database ~ '.' ~ sch ~ '.' ~ n) -%}
      {%- do log('dropped ' ~ sch ~ '.' ~ n, info=True) -%}
    {%- endif -%}
  {%- endfor -%}
  {%- do log((names | length) ~ ' work tablo ' ~ ('bulundu' if dry_run else 'silindi'), info=True) -%}
{% endmacro %}

{% macro default__odi_drop_work_tables(schema=none, older_than_hours=0, include_errors=false, dry_run=false) %}
  {%- set sch = (schema or target.schema) | upper -%}
  {%- set prefixes = ['I$\\_%', 'C$\\_%', 'X$\\_%'] + (['E$\\_%'] if include_errors else []) -%}
  {% set q %}
    select o.object_name
      from all_objects o
     where o.owner = '{{ sch }}'
       and o.object_type = 'TABLE'
       and ( {% for p in prefixes %}o.object_name like '{{ p }}' escape '\'{{ ' or ' if not loop.last }}{% endfor %} )
       and o.created < sysdate - {{ older_than_hours }} / 24
       and not exists ( select 1 from all_tables t
                         where t.owner = o.owner and t.table_name = o.object_name and t.temporary = 'Y' )
     order by 1
  {% endset %}
  {%- set names = run_query(q).columns[0].values() -%}
  {%- for n in names -%}
    {%- if dry_run -%}
      {%- do log('[dry-run] drop ' ~ sch ~ '.' ~ n, info=True) -%}
    {%- else -%}
      {%- do run_query('DROP TABLE ' ~ sch ~ '."' ~ n ~ '" PURGE') -%}
      {%- do log('dropped ' ~ sch ~ '.' ~ n, info=True) -%}
    {%- endif -%}
  {%- endfor -%}
  {%- do log((names | length) ~ ' work tablo ' ~ ('bulundu' if dry_run else 'silindi'), info=True) -%}
{% endmacro %}

{# ---------------------------------------------------------------------------
   Bir run'ın E$ hata özeti (ODI SNP_CHECK_TAB karşılığı)
   dbt run-operation odi_error_summary --args '{error_table: WRK.E$_T_IU}'
   dbt run-operation odi_error_summary --args '{error_table: WRK.E$_T_IU, sess_no: <invocation_id>}'
--------------------------------------------------------------------------- #}
{% macro odi_error_summary(error_table, sess_no=none) %}
  {% set q %}
    select odi_sess_no, cons_type, cons_name, count(*) as cnt, max(check_date) as last_check
      from {{ error_table }}
     {% if sess_no %}where odi_sess_no = '{{ sess_no }}'{% endif %}
     group by odi_sess_no, cons_type, cons_name
     order by max(check_date) desc, cnt desc
  {% endset %}
  {%- set t = run_query(q) -%}
  {%- do t.print_table(max_rows=50, max_column_width=40) -%}
{% endmacro %}
