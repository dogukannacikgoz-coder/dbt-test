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
   Yarım kalmış work tablolarını temizle (fail olmuş run'lardan / unique temp names'ten kalan)
   GÜVENLİK:
     - Şema taraması YOK: sadece COMMENT = 'ODI_DBT_WORK' işaretli VE work önekli
       (I$_ / C$_ / X$_, include_errors ile E$_) tablolar listelenir. odi_dbt'nin
       yaratmadığı hiçbir tablo (ODI'ın kendi I$_'ları dahil) bu listeye giremez.
     - schema zorunlu (target.schema'ya düşmez).
     - Varsayılan dry_run: true -> sadece listeler. Silmek için dry_run: false verin.
     - Her drop yine odi_safe_drop ile işaret kontrolünden geçer.
   dbt run-operation odi_drop_work_tables --args '{schema: WRK}'                          # sadece listele
   dbt run-operation odi_drop_work_tables --args '{schema: WRK, older_than_hours: 12, dry_run: false}'
--------------------------------------------------------------------------- #}
{% macro odi_drop_work_tables(schema=none, older_than_hours=24, include_errors=false, dry_run=true) %}
  {%- if not schema -%}
    {%- do exceptions.raise_compiler_error("odi_drop_work_tables: schema parametresi zorunlu (ör. --args '{schema: WRK}').") -%}
  {%- endif -%}
  {%- set kinds = ['I$_', 'C$_', 'X$_'] + (['E$_'] if include_errors else []) -%}
  {%- set prefixes = [] -%}
  {%- for k in kinds -%}{%- do prefixes.append(odi_work_prefix(k)) -%}{%- endfor -%}
  {%- set names = adapter.dispatch('odi_list_marked_work_tables')(schema, prefixes, older_than_hours | int) -%}
  {%- set ctx = {'km': 'odi_drop_work_tables', 'step': 0} -%}
  {%- for n in names -%}
    {%- if dry_run -%}
      {%- do log('[dry-run] drop ' ~ schema ~ '.' ~ n, info=True) -%}
    {%- else -%}
      {%- set rel = api.Relation.create(database=target.database, schema=odi_ident(schema), identifier=n, type='table') -%}
      {%- do adapter.dispatch('odi_drop_marked_table')(rel) -%}
      {%- do log('dropped ' ~ schema ~ '.' ~ n, info=True) -%}
    {%- endif -%}
  {%- endfor -%}
  {%- do log((names | length) ~ ' işaretli work tablo ' ~ ('bulundu (dry-run, silinmedi)' if dry_run else 'silindi'), info=True) -%}
{% endmacro %}

{% macro default__odi_list_marked_work_tables(schema, prefixes, older_than_hours) %}
  {% set q %}
    select t.table_name
      from all_tables t
      join all_tab_comments c on c.owner = t.owner and c.table_name = t.table_name
      join all_objects o      on o.owner = t.owner and o.object_name = t.table_name and o.object_type = 'TABLE'
     where t.owner = '{{ schema | upper }}'
       and t.temporary = 'N'
       and c.comments = '{{ odi_work_marker() }}'
       and ( {% for p in prefixes %}substr(t.table_name, 1, {{ p | length }}) = '{{ p | upper }}'{{ ' or ' if not loop.last }}{% endfor %} )
       and o.created < sysdate - {{ older_than_hours }} / 24
     order by 1
  {% endset %}
  {{ return(run_query(q).columns[0].values() | list) }}
{% endmacro %}

{# Trino: oluşturma zamanı information_schema'da yok -> yaş filtresi uygulanmaz #}
{% macro trino__odi_list_marked_work_tables(schema, prefixes, older_than_hours) %}
  {% set q %}
    select c.table_name
      from system.metadata.table_comments c
     where c.catalog_name = '{{ target.database | lower }}'
       and c.schema_name  = '{{ schema | lower }}'
       and c.comment      = '{{ odi_work_marker() }}'
       and ( {% for p in prefixes %}substr(c.table_name, 1, {{ p | length }}) = '{{ p | lower }}'{{ ' or ' if not loop.last }}{% endfor %} )
     order by 1
  {% endset %}
  {{ return(run_query(q).columns[0].values() | list) }}
{% endmacro %}

{# run-operation'da config/this yok; işaret kontrolü yine yapılır #}
{% macro default__odi_drop_marked_table(rel) %}
  {%- set o = rel.schema | upper -%}
  {%- set t = rel.identifier | upper -%}
  {% set q %}
DECLARE
  v_cmt VARCHAR2(4000);
BEGIN
  SELECT MAX(comments) INTO v_cmt FROM all_tab_comments WHERE owner = '{{ o }}' AND table_name = '{{ t }}';
  IF v_cmt IS NULL OR v_cmt <> '{{ odi_work_marker() }}' THEN
    RAISE_APPLICATION_ERROR(-20901, 'odi_dbt: {{ o }}.{{ t }} isaretsiz, DROP EDILMEDI.');
  END IF;
  EXECUTE IMMEDIATE 'DROP TABLE "{{ o }}"."{{ t }}" PURGE';
END;
  {% endset %}
  {%- do run_query(q) -%}
{% endmacro %}

{% macro trino__odi_drop_marked_table(rel) %}
  {%- if odi_trn_table_comment(rel) != odi_work_marker() -%}
    {%- do exceptions.raise_compiler_error('odi_dbt: ' ~ rel ~ ' işaretsiz, DROP EDİLMEDİ.') -%}
  {%- endif -%}
  {%- do run_query('drop table ' ~ rel) -%}
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
