{#
  ============================================================================
   odi_dbt — ODI Knowledge Module mantığını dbt-oracle içinde çalıştıran framework
   Ortak yardımcılar: opsiyonlar, I$/C$/E$/X$ isimlendirme, step log, LKM,
   target hazırlığı, silme yardımcıları, parallel DML
  ============================================================================
#}

{# ---------------------------------------------------------------------------
   Liste / sözlük / değer yardımcıları
--------------------------------------------------------------------------- #}
{% macro odi_as_list(v) %}
  {%- if v is none -%}
    {{ return([]) }}
  {%- elif v is string -%}
    {{ return(v.split(',') | map('trim') | reject('equalto', '') | map('upper') | list) }}
  {%- else -%}
    {{ return(v | map('upper') | list) }}
  {%- endif -%}
{% endmacro %}

{% macro odi_upper_dict(d) %}
  {%- set out = {} -%}
  {%- for k, v in (d or {}).items() -%}
    {%- do out.update({k | upper: v}) -%}
  {%- endfor -%}
  {{ return(out) }}
{% endmacro %}

{# ---------------------------------------------------------------------------
   Motor farkları (adapter.dispatch, macro_namespace verilmeden -> root projede aranır):
   default__*  = Oracle davranışı,  trino__* = Trino (Iceberg) davranışı
--------------------------------------------------------------------------- #}
{% macro odi_hint(h) %}{{ return(adapter.dispatch('odi_hint')(h)) }}{% endmacro %}
{% macro default__odi_hint(h) %}{%- if h -%}{{ return('/*+ ' ~ h ~ ' */') }}{%- endif -%}{{ return('') }}{% endmacro %}
{% macro trino__odi_hint(h) %}{{ return('') }}{% endmacro %}

{# identifier harf düzeni: Oracle büyük, Trino küçük harf saklar #}
{% macro odi_ident(s) %}{{ return(adapter.dispatch('odi_ident')(s)) }}{% endmacro %}
{% macro default__odi_ident(s) %}{{ return(s | upper) }}{% endmacro %}
{% macro trino__odi_ident(s) %}{{ return(s | lower) }}{% endmacro %}

{# work tablo önekleri: Trino/Iceberg'de '$' metadata tablosu ayırıcısıdır (t$snapshots), kullanılamaz.
   ODI'ın kendi I$_/E$_ tablolarıyla aynı şemayı paylaşıyorsanız önekleri değiştirebilirsiniz:
     vars: {odi_work_prefixes: {'I$_': 'DI$_', 'C$_': 'DC$_', 'E$_': 'DE$_', 'X$_': 'DX$_'}} #}
{% macro odi_work_prefix(p) %}{{ return(adapter.dispatch('odi_work_prefix')(p)) }}{% endmacro %}
{% macro default__odi_work_prefix(p) %}{{ return(var('odi_work_prefixes', {}).get(p, p)) }}{% endmacro %}
{% macro trino__odi_work_prefix(p) %}
  {{ return(var('odi_work_prefixes', {}).get(p, {'I$_': 'odi_i_', 'C$_': 'odi_c_', 'E$_': 'odi_e_', 'X$_': 'odi_x_'}.get(p, p))) }}
{% endmacro %}

{# şimdiki zaman: E$ CHECK_DATE ve step log #}
{% macro odi_now() %}{{ return(adapter.dispatch('odi_now')()) }}{% endmacro %}
{% macro default__odi_now() %}{{ return('sysdate') }}{% endmacro %}
{% macro trino__odi_now() %}{{ return('localtimestamp') }}{% endmacro %}

{# null-safe eşit / farklı #}
{% macro odi_null_eq(a, b) %}{{ return(adapter.dispatch('odi_null_eq')(a, b)) }}{% endmacro %}
{% macro default__odi_null_eq(a, b) %}{{ return('decode(' ~ a ~ ', ' ~ b ~ ', 1, 0) = 1') }}{% endmacro %}
{% macro trino__odi_null_eq(a, b) %}{{ return(a ~ ' is not distinct from ' ~ b) }}{% endmacro %}
{% macro odi_null_ne(a, b) %}{{ return(adapter.dispatch('odi_null_ne')(a, b)) }}{% endmacro %}
{% macro default__odi_null_ne(a, b) %}{{ return('decode(' ~ a ~ ', ' ~ b ~ ', 1, 0) = 0') }}{% endmacro %}
{% macro trino__odi_null_ne(a, b) %}{{ return(a ~ ' is distinct from ' ~ b) }}{% endmacro %}

{# 'param:LOAD_DATE' -> odi_param('LOAD_DATE'); diğer değerler olduğu gibi #}
{% macro odi_resolve(v) %}
  {%- if v is string and v.startswith('param:') -%}
    {{ return(odi_param(v[6:])) }}
  {%- else -%}
    {{ return(v) }}
  {%- endif -%}
{% endmacro %}

{% macro odi_ctx(km_name) %}
  {%- do odi_preflight() -%}
  {{ return({'km': km_name, 'step': 0}) }}
{% endmacro %}

{% macro odi_flags() %}
  {%- set ins = config.get('odi_insert', true) -%}
  {%- set upd = config.get('odi_update', true) -%}
  {%- if not ins and not upd -%}
    {%- do exceptions.raise_compiler_error(this ~ ': odi_insert ve odi_update ikisi birden false olamaz.') -%}
  {%- endif -%}
  {{ return({'insert': ins, 'update': upd}) }}
{% endmacro %}

{# ---------------------------------------------------------------------------
   Work tablo isimleri: I$_ (flow) / C$_ (LKM) / E$_ (hata) / X$_ (exchange)
   odi_unique_temp_names: true  -> I$_<MODEL>_<6 hane run id>  (paralel run çakışmasın)
--------------------------------------------------------------------------- #}
{% macro odi_work_relation(prefix, override_cfg=none) %}
  {%- set ws = config.get('odi_work_schema', this.schema) -%}
  {%- set explicit = config.get(override_cfg) if override_cfg else none -%}
  {%- set maxlen = config.get('odi_max_identifier_length', 128) | int -%}
  {%- if explicit -%}
    {%- set parts = explicit.split('.') -%}
    {%- if parts | length == 2 -%}
      {%- set ws = parts[0] -%}
      {%- set ident = parts[1] -%}
    {%- else -%}
      {%- set ident = explicit -%}
    {%- endif -%}
  {%- else -%}
    {%- set suffix = ('_' ~ local_md5(invocation_id)[:6]) if (config.get('odi_unique_temp_names', false) and prefix != 'E$_') else '' -%}
    {%- set ident = (odi_work_prefix(prefix) ~ this.identifier)[:maxlen - (suffix | length)] ~ suffix -%}
  {%- endif -%}
  {%- do odi_check_work_name(prefix, ws, ident) -%}
  {{ return(this.incorporate(path={'schema': odi_ident(ws), 'identifier': odi_ident(ident)}, type='table')) }}
{% endmacro %}

{% macro odi_table_exists(rel) %}{{ return(adapter.dispatch('odi_table_exists')(rel)) }}{% endmacro %}
{% macro trino__odi_table_exists(rel) %}
  {% call statement('odi_exists', fetch_result=True, auto_begin=False) %}
    select count(*) from {{ rel.database }}.information_schema.tables
     where table_schema = '{{ rel.schema | lower }}'
       and table_name = '{{ rel.identifier | lower }}'
  {% endcall %}
  {{ return(load_result('odi_exists')['data'][0][0] | int > 0) }}
{% endmacro %}
{% macro default__odi_table_exists(rel) %}
  {% call statement('odi_exists', fetch_result=True, auto_begin=False) %}
    select count(*) from all_tables
     where owner = '{{ rel.schema | upper }}'
       and table_name = '{{ rel.identifier | upper }}'
  {% endcall %}
  {{ return(load_result('odi_exists')['data'][0][0] | int > 0) }}
{% endmacro %}

{# Model SQL'inin (mapping) kolonları — ODI target datastore attribute listesi gibi #}
{% macro odi_query_columns(src_sql) %}
  {% call statement('odi_get_cols', fetch_result=True, auto_begin=False) %}
    select * from ( {{ src_sql }} ) odi_q where 1 = 0
  {% endcall %}
  {{ return(load_result('odi_get_cols')['table'].column_names | map('upper') | list) }}
{% endmacro %}

{% macro odi_table_columns(rel) %}{{ return(adapter.dispatch('odi_table_columns')(rel)) }}{% endmacro %}
{% macro trino__odi_table_columns(rel) %}
  {% call statement('odi_get_tcols', fetch_result=True, auto_begin=False) %}
    select column_name from {{ rel.database }}.information_schema.columns
     where table_schema = '{{ rel.schema | lower }}'
       and table_name = '{{ rel.identifier | lower }}'
     order by ordinal_position
  {% endcall %}
  {{ return(load_result('odi_get_tcols')['data'] | map(attribute=0) | map('upper') | list) }}
{% endmacro %}
{% macro default__odi_table_columns(rel) %}
  {% call statement('odi_get_tcols', fetch_result=True, auto_begin=False) %}
    select column_name from all_tab_columns
     where owner = '{{ rel.schema | upper }}'
       and table_name = '{{ rel.identifier | upper }}'
     order by column_id
  {% endcall %}
  {{ return(load_result('odi_get_tcols')['data'] | map(attribute=0) | map('upper') | list) }}
{% endmacro %}

{# ---------------------------------------------------------------------------
   SQL parça üreticileri
--------------------------------------------------------------------------- #}
{% macro odi_key_join(keys, a='t', b='f') %}
  {%- for k in keys -%}{{ a }}.{{ k }} = {{ b }}.{{ k }}{{ ' and ' if not loop.last }}{%- endfor -%}
{% endmacro %}

{# null-safe eşitlik: DECODE null = null'u eşit kabul eder #}
{% macro odi_all_equal(cols, a='t', b='f') %}
  {%- if cols | length == 0 -%}1 = 1{%- else -%}
  {%- for c in cols -%}{{ odi_null_eq(a ~ '.' ~ c, b ~ '.' ~ c) }}{{ ' and ' if not loop.last }}{%- endfor -%}
  {%- endif -%}
{% endmacro %}

{% macro odi_any_diff(cols, a='t', b='s') %}
  {%- for c in cols -%}{{ odi_null_ne(a ~ '.' ~ c, b ~ '.' ~ c) }}{{ ' or ' if not loop.last }}{%- endfor -%}
{% endmacro %}

{% macro odi_col_list(cols, alias=none) %}
  {%- for c in cols -%}{{ alias ~ '.' if alias }}{{ c }}{{ ', ' if not loop.last }}{%- endfor -%}
{% endmacro %}

{% macro odi_tuple(cols, alias=none) %}
  {%- if cols | length == 1 -%}{{ alias ~ '.' if alias }}{{ cols[0] }}{%- else -%}({{ odi_col_list(cols, alias) }}){%- endif -%}
{% endmacro %}

{# ---------------------------------------------------------------------------
   Step çalıştırıcı — ODI session step log'u gibi: console + opsiyonel log tablosu
--------------------------------------------------------------------------- #}
{% macro odi_exec(ctx, title, step_sql, name='odi_step', auto_begin=True) %}
  {%- do ctx.update({'step': ctx['step'] + 1}) -%}
  {%- set started = modules.datetime.datetime.now() -%}
  {%- do log('[' ~ ctx['km'] ~ '] ' ~ this.identifier ~ ' | ' ~ ctx['step'] ~ ' - ' ~ title, info=True) -%}
  {% call statement(name, auto_begin=auto_begin) -%}
    {{ step_sql }}
  {%- endcall %}
  {%- set res = load_result(name) -%}
  {%- set rows = none -%}
  {%- if res and res['response'] is not none and res['response'].rows_affected is not none -%}
    {%- set rows = res['response'].rows_affected -%}
  {%- endif -%}
  {%- set secs = (modules.datetime.datetime.now() - started).total_seconds() -%}
  {%- do log('      -> rows: ' ~ (rows if rows is not none and rows >= 0 else '-') ~ ' | ' ~ secs ~ 's', info=True) -%}
  {%- do odi_write_log(ctx, title, rows, secs) -%}
  {{ return(rows) }}
{% endmacro %}

{# var('odi_log_table') verilirse her step ODI SNP_SESS_TASK_LOG benzeri tabloya yazılır #}
{% macro odi_write_log(ctx, title, rows, secs) %}
  {%- set log_table = var('odi_log_table', none) -%}
  {%- if log_table -%}
    {#- şemasız verilirse model şemasında aranır (kendi kullanıcınla başka şemaya yazarken de doğru tabloya gider) -#}
    {%- set log_table = log_table if '.' in log_table else this.schema ~ '.' ~ log_table -%}
    {% call statement('odi_log', auto_begin=True) %}
      insert into {{ log_table }}
        (sess_no, model_name, km_name, step_no, step_name, rows_affected, duration_sec, log_date)
      values
        ('{{ invocation_id }}', '{{ this.schema ~ "." ~ this.identifier }}', '{{ ctx["km"] }}', {{ ctx['step'] }},
         '{{ title | replace("'", "''") }}', {{ rows if rows is not none else 'null' }}, {{ secs }}, {{ odi_now() }})
    {% endcall %}
  {%- endif -%}
{% endmacro %}

{% macro odi_commit(ctx) %}{{ return(adapter.dispatch('odi_commit')(ctx)) }}{% endmacro %}
{% macro default__odi_commit(ctx) %}
  {%- do odi_exec(ctx, 'Commit transaction', 'COMMIT', name='odi_commit') -%}
{% endmacro %}
{# Trino autocommit: her statement kendi commit'i #}
{% macro trino__odi_commit(ctx) %}{% endmacro %}

{# DROP sadece odi_safe_drop ile (odi_safety.sql): işaretsiz tabloya dokunmaz #}

{% macro odi_gather_stats(ctx, rel, force=false) %}
  {%- if force or config.get('odi_analyze_flow', false) -%}
    {%- set gs -%}
BEGIN
  DBMS_STATS.GATHER_TABLE_STATS(ownname => '{{ rel.schema | upper }}', tabname => '{{ rel.identifier | upper }}',
                                estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE, no_invalidate => FALSE);
END;
    {%- endset -%}
    {%- do odi_exec(ctx, 'Analyze ' ~ rel.identifier, gs, auto_begin=False) -%}
  {%- endif -%}
{% endmacro %}

{# ---------------------------------------------------------------------------
   Parallel DML (ALTER SESSION). Connection thread bazında tekrar kullanıldığı için
   her ODI modeli başında açık/kapalı durumu set edilir, sonda kapatılır.
--------------------------------------------------------------------------- #}
{% macro odi_session_start(ctx) %}
  {%- if config.get('odi_parallel_dml', false) -%}
    {%- do odi_exec(ctx, 'Enable parallel DML', 'ALTER SESSION ENABLE PARALLEL DML', auto_begin=False) -%}
  {%- else -%}
    {% call statement('odi_pdml_off', auto_begin=False) %}ALTER SESSION DISABLE PARALLEL DML{% endcall %}
  {%- endif -%}
{% endmacro %}

{% macro odi_session_end(ctx) %}
  {%- if config.get('odi_parallel_dml', false) -%}
    {% call statement('odi_pdml_off2', auto_begin=False) %}ALTER SESSION DISABLE PARALLEL DML{% endcall %}
  {%- endif -%}
{% endmacro %}

{# parallel DML sonrası aynı tabloyu okumak ORA-12838 verir -> araya commit #}
{% macro odi_commit_if_parallel(ctx) %}
  {%- if config.get('odi_parallel_dml', false) -%}{%- do odi_commit(ctx) -%}{%- endif -%}
{% endmacro %}

{# ---------------------------------------------------------------------------
   Work tablo yükleyici (C$ / I$ / X$ için ortak)
   odi_flow_mode:
     'table'    -> ODI default: drop + create + insert (work şemada CREATE TABLE yetkisi ister)
                   drop sadece ODI_DBT_WORK işaretli tabloya yapılır (odi_safe_drop)
     'existing' -> PDM ile önceden açılmış tablo (permanent veya GTT ON COMMIT PRESERVE ROWS):
                   delete + insert; DDL yok
     'none'     -> (sadece odi_merge) I$ kullanılmaz; diğer work tabloları 'table' gibi davranır
--------------------------------------------------------------------------- #}
{% macro odi_work_mode() %}
  {%- set m = config.get('odi_flow_mode', 'table') | lower -%}
  {{ return('table' if m == 'none' else m) }}
{% endmacro %}

{% macro odi_load_work_table(ctx, rel, src_sql, cols, label, with_ind_update=false, create_from=none) %}
  {%- set mode = odi_work_mode() -%}
  {%- set ins_hint = config.get('odi_flow_insert_hint', 'APPEND') -%}
  {%- set sel_hint = config.get('odi_flow_select_hint', none) -%}
  {%- set nolog = config.get('odi_flow_table_options', 'nologging' if config.get('odi_flow_nologging', true) else '') -%}

  {%- if mode == 'table' -%}
    {%- do odi_safe_drop(ctx, rel, label) -%}
    {%- set create_sql -%}
create table {{ rel }} {{ nolog }} as
{%- if create_from %}
select * from {{ create_from }} where 1 = 0
{%- else %}
select odi_q.*{{ ", cast('I' as char(1)) as IND_UPDATE" if with_ind_update }}
  from ( {{ src_sql }} ) odi_q
 where 1 = 0
{%- endif %}
    {%- endset -%}
    {%- do odi_exec(ctx, 'Create ' ~ label ~ ' table', create_sql, auto_begin=False) -%}
    {%- do odi_mark_work_table(ctx, rel, label) -%}
  {%- elif mode == 'existing' -%}
    {%- do odi_exec(ctx, 'Delete ' ~ label ~ ' table (pre-created)', 'delete from ' ~ rel) -%}
  {%- else -%}
    {%- do exceptions.raise_compiler_error("odi_flow_mode '" ~ mode ~ "' geçersiz. 'table' | 'existing' | 'none'") -%}
  {%- endif -%}

  {%- set ins_sql -%}
insert {{ odi_hint(ins_hint) }} into {{ rel }}
  ( {{ odi_col_list(cols) }}{{ ', IND_UPDATE' if with_ind_update }} )
select {{ odi_hint(sel_hint) }}
       {{ odi_col_list(cols, 'odi_q') }}{{ ", 'I'" if with_ind_update }}
  from ( {{ src_sql }} ) odi_q
  {%- endset -%}
  {%- do odi_exec(ctx, 'Insert flow into ' ~ label ~ ' table', ins_sql) -%}
  {#- APPEND sonrası aynı transaction'da okuma ORA-12838 verir; ODI de burada commit eder -#}
  {%- do odi_commit(ctx) -%}
  {%- do odi_gather_stats(ctx, rel) -%}
{% endmacro %}

{% macro odi_cleanup(ctx, rels) %}
  {%- if config.get('odi_delete_temporary_objects', true) -%}
    {%- set mode = odi_work_mode() -%}
    {%- for r in rels -%}
      {%- if mode == 'table' -%}
        {%- do odi_safe_drop(ctx, r, r.identifier) -%}
      {%- else -%}
        {%- do odi_exec(ctx, 'Delete ' ~ r.identifier, 'delete from ' ~ r) -%}
        {%- do odi_commit(ctx) -%}
      {%- endif -%}
    {%- endfor -%}
  {%- endif -%}
{% endmacro %}

{# ---------------------------------------------------------------------------
   LKM: odi_lkm: true ise model SQL'i önce C$_ tablosuna stage edilir
   (LKM SQL to Oracle / LKM Oracle to Oracle (DBLINK) mantığı)
--------------------------------------------------------------------------- #}
{% macro odi_lkm_stage(ctx, src_sql) %}
  {%- if config.get('odi_lkm', false) -%}
    {%- set c_rel = odi_work_relation('C$_', 'odi_lkm_table') -%}
    {%- set cols = odi_query_columns(src_sql) -%}
    {%- do odi_load_work_table(ctx, c_rel, src_sql, cols, 'C$ (LKM)') -%}
    {{ return({'sql': 'select * from ' ~ c_rel, 'rel': c_rel}) }}
  {%- else -%}
    {{ return({'sql': src_sql, 'rel': none}) }}
  {%- endif -%}
{% endmacro %}

{# ---------------------------------------------------------------------------
   Target hazırlığı:
     - yoksa ve odi_create_target_table: true ise yarat (from_sql'in kolonları + audit kolonları)
     - --full-refresh (sadece odi_allow_full_refresh: true) / odi_truncate  -> TRUNCATE
     - odi_delete_missing / close_missing açıksa önce kaynak boş mu kontrolü
     - odi_delete_all                 -> DELETE
     - odi_partition                  -> partition'ı garanti et + strategy (truncate/delete/none)
   from_sql: tablo adı veya '( select ... )'
--------------------------------------------------------------------------- #}
{% macro odi_prepare_target(ctx, target, from_sql, cols, extra_cols_sql='') %}
  {%- do odi_guard_source_rows(ctx, from_sql) -%}
  {%- if not odi_table_exists(target) -%}
    {%- if config.get('odi_create_target_table', false) -%}
      {%- set ct -%}
create table {{ target }} as
select {{ extra_cols_sql }}{{ odi_col_list(cols, 'f') }}
       {%- for c, e in odi_audit('insert').items() if c not in cols %}, {{ e }} as {{ c }}{% endfor %}
       {%- for c, e in odi_audit('update').items() if c not in cols and c not in odi_audit('insert') %}, {{ e }} as {{ c }}{% endfor %}
  from {{ from_sql }} f
 where 1 = 0
      {%- endset -%}
      {%- do odi_exec(ctx, 'Create target table', ct, auto_begin=False) -%}
    {%- else -%}
      {%- do exceptions.raise_compiler_error(
            'Target ' ~ target ~ ' yok. PDM ile açın ya da odi_create_target_table: true verin.') -%}
    {%- endif -%}
  {%- endif -%}

  {%- if should_full_refresh() or config.get('odi_truncate', false) -%}
    {%- do odi_exec(ctx, 'Truncate target table', 'truncate table ' ~ target, auto_begin=False) -%}
  {%- elif config.get('odi_delete_all', false) -%}
    {%- do odi_exec(ctx, 'Delete target table', 'delete from ' ~ target) -%}
  {%- else -%}
    {%- do odi_partition_prepare(ctx, target) -%}
  {%- endif -%}
{% endmacro %}

{# ---------------------------------------------------------------------------
   Target'tan satır silme: hard delete ya da odi_soft_delete ile işaretleme
     odi_soft_delete: {'column': 'IS_DELETED', 'value': '1'}  (+ odi_audit_update uygulanır)
   where_sql: "t.<key> in (...)" gibi, target alias'ı t
--------------------------------------------------------------------------- #}
{% macro odi_delete_target_rows(ctx, target, where_sql, title) %}
  {%- set soft = odi_upper_dict(config.get('odi_soft_delete', none)) -%}
  {%- if soft -%}
    {%- set q -%}
update {{ target }} t
   set t.{{ soft['COLUMN'] }} = {{ soft['VALUE'] }}
       {%- for c, e in odi_audit('update').items() %},
       t.{{ c }} = {{ e }}{% endfor %}
 where {{ where_sql }}
   and decode(t.{{ soft['COLUMN'] }}, {{ soft['VALUE'] }}, 1, 0) = 0
    {%- endset -%}
    {%- do odi_exec(ctx, title ~ ' (soft delete)', q) -%}
  {%- else -%}
    {%- set q -%}
delete {{ odi_hint(config.get('odi_delete_hint', none)) }} from {{ target }} t
 where {{ where_sql }}
    {%- endset -%}
    {%- do odi_exec(ctx, title, q) -%}
  {%- endif -%}
{% endmacro %}

{# ---------------------------------------------------------------------------
   Kaynakta olmayanı sil (full snapshot karşılaştırma)
     odi_delete_missing: true
     odi_delete_missing_filter: "t.SOURCE_SYS = 'CORE'"   (silme kapsamını daralt)
   Partition tanımlıysa kapsam otomatik o partition ile sınırlanır.
   key_sql: flow'daki tüm key'leri dönen SQL. Hatalı (E$) satırların key'leri silinmez.
--------------------------------------------------------------------------- #}
{% macro odi_delete_missing(ctx, target, keys, key_sql, e_rel=none) %}
  {%- if config.get('odi_delete_missing', false) -%}
    {%- set flt = config.get('odi_delete_missing_filter', none) -%}
    {%- set ppred = odi_partition_predicate('t') -%}
    {%- set w -%}
not exists ( select 1 from ( {{ key_sql }} ) k where {{ odi_key_join(keys, 't', 'k') }} )
{%- if e_rel %}
   and not exists ( select 1 from {{ e_rel }} e
                     where e.ODI_SESS_NO = '{{ invocation_id }}' and {{ odi_key_join(keys, 't', 'e') }} )
{%- endif %}
{%- if ppred %}
   and {{ ppred }}
{%- endif %}
{%- if flt %}
   and ( {{ flt }} )
{%- endif %}
    {%- endset -%}
    {%- do odi_delete_target_rows(ctx, target, w, 'Delete rows missing in source') -%}
  {%- endif -%}
{% endmacro %}

{# ---------------------------------------------------------------------------
   Model içinde "incremental mı" kontrolü. dbt'nin is_incremental() makrosu sadece
   materialized='incremental' için true döner; ODI materialization'larında bunu kullanın.
--------------------------------------------------------------------------- #}
{% macro odi_is_incremental() %}
  {%- if not execute -%}{{ return(false) }}{%- endif -%}
  {%- if should_full_refresh() -%}{{ return(false) }}{%- endif -%}
  {{ return(odi_table_exists(this)) }}
{% endmacro %}

{% macro odi_audit(kind) %}
  {{ return(odi_upper_dict(config.get('odi_audit_' ~ kind, {}))) }}
{% endmacro %}

{% macro odi_hooks_pre(ctx) %}
  {{ run_hooks(pre_hooks, inside_transaction=False) }}
  {%- do odi_session_start(ctx) -%}
  {{ run_hooks(pre_hooks, inside_transaction=True) }}
{% endmacro %}

{% macro odi_hooks_post(ctx) %}
  {{ run_hooks(post_hooks, inside_transaction=True) }}
  {% do adapter.commit() %}
  {%- do odi_session_end(ctx) -%}
  {{ run_hooks(post_hooks, inside_transaction=False) }}
{% endmacro %}
