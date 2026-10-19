{#
  ============================================================================
   odi_dbt — GÜVENLİK KATMANI
   Amaç: framework, binlerce tablonun olduğu bir DWH şemasında çalışırken
   kendisinin yaratmadığı HİÇBİR tabloyu drop / truncate / delete edemesin.

   Kurallar
   1) DROP sadece work tablolarına (I$ / C$ / X$; E$ asla otomatik drop edilmez)
      ve sadece tablo üzerinde odi_dbt işareti varsa yapılır:
        Oracle : COMMENT ON TABLE ... IS 'ODI_DBT_WORK'   (CTAS'tan hemen sonra)
        Trino  : CREATE TABLE ... COMMENT 'ODI_DBT_WORK' AS ...   (CTAS içinde, atomik)
      İşaretsiz bir tablo aynı isimle varsa model FAIL olur, tabloya dokunulmaz.
      (ODI'ın kendi I$_ tabloları ya da elle açılmış bir tablo asla silinmez.)
   2) Work tablo adı mutlaka work önekiyle başlar (I$_ / C$_ / X$_ / E$_,
      Trino'da odi_i_ / odi_c_ / odi_x_ / odi_e_) ve model target'ı olamaz.
      odi_flow_table / odi_error_table / odi_exchange_table / odi_lkm_table ile
      yanlışlıkla gerçek bir tablo verilirse derleme anında durur (istisna yok;
      PDM ile açılan work tabloları da aynı önekle adlandırılır).
   3) Şema taraması yapan bir drop yok. odi_drop_work_tables sadece işaretli
      tabloları görür, şema parametresi zorunludur, varsayılanı dry-run'dır.
   4) --full-refresh (TRUNCATE target) model bazında açıkça izin verilmedikçe
      reddedilir: odi_allow_full_refresh: true. Projeyi --full-refresh ile
      seçicisiz koşmak tüm target'ları boşaltamaz.
   5) Kaynakta olmayanı sil / close_missing: kaynak (flow) boş ya da
      odi_delete_missing_min_rows'tan az satır dönerse target'a dokunulmadan durur.
  ============================================================================
#}

{% macro odi_work_marker() %}{{ return('ODI_DBT_WORK') }}{% endmacro %}

{# ---------------------------------------------------------------------------
   Model başında (odi_ctx içinden) çalışan ön kontroller — hiçbir SQL çalışmadan önce
--------------------------------------------------------------------------- #}
{% macro odi_preflight() %}
  {%- if execute and should_full_refresh() and not config.get('odi_allow_full_refresh', false) -%}
    {%- do exceptions.raise_compiler_error(
          this ~ ": --full-refresh bu modelde kapalı (TRUNCATE target olurdu). "
          ~ "Gerçekten isteniyorsa modele odi_allow_full_refresh: true verin ve sadece o modeli seçin. "
          ~ "Hiçbir tabloya dokunulmadı.") -%}
  {%- endif -%}
{% endmacro %}

{# ---------------------------------------------------------------------------
   Work tablo adı kontrolü (odi_work_relation içinden çağrılır)
--------------------------------------------------------------------------- #}
{% macro odi_check_work_name(prefix, schema, ident) %}
  {%- set expect = odi_work_prefix(prefix) | upper -%}
  {%- if not (ident | upper).startswith(expect) -%}
    {%- do exceptions.raise_compiler_error(
          this ~ ": work tablo adı '" ~ schema ~ "." ~ ident ~ "' '" ~ expect ~ "' ile başlamıyor. "
          ~ "Work tablolar drop / delete edildiği için gerçek bir tablonun work tablo olarak "
          ~ "verilmesini engellemek adına durduruldu. PDM ile açılan work tabloları da bu önekle adlandırın.") -%}
  {%- endif -%}
  {%- if (schema | upper) == (this.schema | upper) and (ident | upper) == (this.identifier | upper) -%}
    {%- do exceptions.raise_compiler_error(this ~ ': work tablo model target tablosunun kendisi olamaz.') -%}
  {%- endif -%}
{% endmacro %}

{# ---------------------------------------------------------------------------
   Work tabloyu işaretle (yeni yaratıldıktan hemen sonra)
--------------------------------------------------------------------------- #}
{% macro odi_mark_work_table(ctx, rel, label) %}{{ return(adapter.dispatch('odi_mark_work_table')(ctx, rel, label)) }}{% endmacro %}
{% macro default__odi_mark_work_table(ctx, rel, label) %}
  {%- do odi_exec(ctx, 'Mark ' ~ label ~ ' table', "COMMENT ON TABLE " ~ rel ~ " IS '" ~ odi_work_marker() ~ "'", auto_begin=False) -%}
{% endmacro %}
{# Trino: işaret CTAS içinde verilir (odi_trn_comment_clause), ayrı adım yok #}
{% macro trino__odi_mark_work_table(ctx, rel, label) %}{% endmacro %}
{% macro odi_trn_comment_clause() %}{{ return(" comment '" ~ odi_work_marker() ~ "'") }}{% endmacro %}

{# ---------------------------------------------------------------------------
   Güvenli DROP: tablo yoksa bir şey yapma; varsa ve işaretliyse drop et;
   varsa ama işaretsizse HATA ver ve dokunma.
--------------------------------------------------------------------------- #}
{% macro odi_safe_drop(ctx, rel, label) %}{{ return(adapter.dispatch('odi_safe_drop')(ctx, rel, label)) }}{% endmacro %}

{% macro default__odi_safe_drop(ctx, rel, label) %}
  {%- set o = rel.schema | upper -%}
  {%- set t = rel.identifier | upper -%}
  {%- set q -%}
DECLARE
  v_cnt NUMBER;
  v_cmt VARCHAR2(4000);
BEGIN
  SELECT COUNT(*) INTO v_cnt FROM all_tables WHERE owner = '{{ o }}' AND table_name = '{{ t }}';
  IF v_cnt > 0 THEN
    SELECT MAX(comments) INTO v_cmt FROM all_tab_comments WHERE owner = '{{ o }}' AND table_name = '{{ t }}';
    IF v_cmt IS NULL OR v_cmt <> '{{ odi_work_marker() }}' THEN
      RAISE_APPLICATION_ERROR(-20901, 'odi_dbt: {{ o }}.{{ t }} odi_dbt work tablosu degil (COMMENT={{ odi_work_marker() }} yok). DROP EDILMEDI. Tabloyu kontrol edin.');
    END IF;
    EXECUTE IMMEDIATE 'DROP TABLE "{{ o }}"."{{ t }}" PURGE';
  END IF;
END;
  {%- endset -%}
  {%- do odi_exec(ctx, 'Drop ' ~ label ~ ' table', q, auto_begin=False) -%}
{% endmacro %}

{% macro trino__odi_safe_drop(ctx, rel, label) %}
  {%- if odi_table_exists(rel) -%}
    {%- set cmt = odi_trn_table_comment(rel) -%}
    {%- if cmt != odi_work_marker() -%}
      {%- do exceptions.raise_compiler_error('odi_dbt: ' ~ rel ~ " odi_dbt work tablosu değil (comment='"
            ~ cmt ~ "'). DROP EDİLMEDİ. Tabloyu kontrol edin.") -%}
    {%- endif -%}
    {%- do odi_exec(ctx, 'Drop ' ~ label ~ ' table', 'drop table ' ~ rel) -%}
  {%- endif -%}
{% endmacro %}

{% macro odi_trn_table_comment(rel) %}
  {% call statement('odi_trn_cmt', fetch_result=True, auto_begin=False) %}
    select comment from system.metadata.table_comments
     where catalog_name = '{{ rel.database | lower }}'
       and schema_name  = '{{ rel.schema | lower }}'
       and table_name   = '{{ rel.identifier | lower }}'
  {% endcall %}
  {%- set rows = load_result('odi_trn_cmt')['data'] -%}
  {{ return(rows[0][0] if rows | length > 0 and rows[0][0] is not none else '') }}
{% endmacro %}

{# ---------------------------------------------------------------------------
   Kaynakta olmayanı sil / close_missing öncesi: flow boşsa dur.
   Target hazırlığından ÖNCE çağrılır -> fail olursa target'a hiç dokunulmamış olur.
     odi_delete_missing_min_rows: 1   (default; 0 verilirse kontrol kapanır)
--------------------------------------------------------------------------- #}
{% macro odi_guard_source_rows(ctx, from_sql) %}
  {%- set scd = config.get('odi_scd', none) or {} -%}
  {%- if not (config.get('odi_delete_missing', false) or scd.get('close_missing', false)) -%}
    {{ return(none) }}
  {%- endif -%}
  {%- set min_rows = config.get('odi_delete_missing_min_rows', 1) | int -%}
  {%- if min_rows <= 0 -%}{{ return(none) }}{%- endif -%}
  {% call statement('odi_src_rows', fetch_result=True) %}
    select count(*) as odi_src_rows from {{ from_sql }} odi_k
  {% endcall %}
  {%- set n = load_result('odi_src_rows')['data'][0][0] | int -%}
  {%- do log('[' ~ ctx['km'] ~ '] ' ~ this.identifier ~ ' | Source row guard -> ' ~ n ~ ' satır (min ' ~ min_rows ~ ')', info=True) -%}
  {%- if n < min_rows -%}
    {%- do exceptions.raise_compiler_error(
          this ~ ': kaynak/flow ' ~ n ~ ' satır döndü (odi_delete_missing_min_rows=' ~ min_rows ~ '). '
          ~ "Kaynakta olmayanı sil / close_missing target'ı boşaltırdı; durduruldu, target'a dokunulmadı.") -%}
  {%- endif -%}
{% endmacro %}
