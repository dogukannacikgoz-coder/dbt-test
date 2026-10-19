{#
  ============================================================================
   odi_dbt — Trino (Iceberg) yardımcıları
   Oracle'dan temel farklar:
     - autocommit: her statement kendi commit'i; çok statement'lı transaction yok.
       Atomik tek işlem = tek MERGE. Upsert'ler bu yüzden tek MERGE'e indirgenir.
     - ROWID yok: flow tablosuna cast(uuid() as varchar) ODI_ROW_ID kolonu eklenir (CKM için)
     - '$' Iceberg metadata ayırıcısı: work tabloları odi_i_ / odi_c_ / odi_e_ önekli
     - GTT, hint, nologging, parallel DML, partition DDL yok; Iceberg hidden partitioning
     - partition "truncate" = DELETE ... WHERE (partition'a hizalıysa metadata işlemi)
  ============================================================================
#}

{% macro odi_trn_with(props) %}
  {%- if props -%}{{ return(' with (' ~ props ~ ')') }}{%- endif -%}{{ return('') }}
{% endmacro %}

{# ---------------------------------------------------------------------------
   Work tablo (flow / LKM staging). Satır id'si (ODI_ROW_ID) her zaman eklenir.
     table    -> güvenli drop (sadece ODI_DBT_WORK işaretli) + CTAS ... COMMENT 'ODI_DBT_WORK' (tek statement)
     existing -> önceden açılmış tablo: delete + insert
--------------------------------------------------------------------------- #}
{% macro odi_trn_load_work_table(ctx, rel, src_sql, cols, label) %}
  {%- set mode = config.get('odi_flow_mode', 'table') | lower -%}
  {%- set props = config.get('odi_trino_work_table_properties', none) -%}
  {%- if mode in ['table', 'none'] -%}
    {%- do odi_safe_drop(ctx, rel, label) -%}
    {%- set q -%}
create table {{ rel }}{{ odi_trn_comment_clause() }}{{ odi_trn_with(props) }} as
select cast(uuid() as varchar) as ODI_ROW_ID,
       {{ odi_col_list(cols, 'odi_q') }}
  from ( {{ src_sql }} ) odi_q
    {%- endset -%}
    {%- do odi_exec(ctx, 'Create and load ' ~ label ~ ' table', q) -%}
  {%- elif mode == 'existing' -%}
    {%- do odi_exec(ctx, 'Delete ' ~ label ~ ' table (pre-created)', 'delete from ' ~ rel) -%}
    {%- set q -%}
insert into {{ rel }} ( ODI_ROW_ID, {{ odi_col_list(cols) }} )
select cast(uuid() as varchar), {{ odi_col_list(cols, 'odi_q') }}
  from ( {{ src_sql }} ) odi_q
    {%- endset -%}
    {%- do odi_exec(ctx, 'Insert flow into ' ~ label ~ ' table', q) -%}
  {%- else -%}
    {%- do exceptions.raise_compiler_error("odi_flow_mode '" ~ mode ~ "' geçersiz. 'table' | 'existing' | 'none'") -%}
  {%- endif -%}
  {%- if config.get('odi_analyze_flow', false) -%}
    {%- do odi_exec(ctx, 'Analyze ' ~ rel.identifier, 'analyze ' ~ rel) -%}
  {%- endif -%}
{% endmacro %}

{% macro odi_trn_cleanup(ctx, rels) %}
  {%- if config.get('odi_delete_temporary_objects', true) -%}
    {%- set mode = config.get('odi_flow_mode', 'table') | lower -%}
    {%- for r in rels -%}
      {%- if mode == 'existing' -%}
        {%- do odi_exec(ctx, 'Delete ' ~ r.identifier, 'delete from ' ~ r) -%}
      {%- else -%}
        {%- do odi_safe_drop(ctx, r, r.identifier) -%}
      {%- endif -%}
    {%- endfor -%}
  {%- endif -%}
{% endmacro %}

{# LKM: model SQL'i (ör. oracle catalog'undan okuyan) önce odi_c_<model> tablosuna #}
{% macro odi_trn_lkm_stage(ctx, src_sql) %}
  {%- if config.get('odi_lkm', false) -%}
    {%- set c_rel = odi_work_relation('C$_', 'odi_lkm_table') -%}
    {%- set cols = odi_query_columns(src_sql) -%}
    {%- do odi_trn_load_work_table(ctx, c_rel, src_sql, cols, 'C$ (LKM)') -%}
    {{ return({'sql': 'select ' ~ odi_col_list(cols) ~ ' from ' ~ c_rel, 'rel': c_rel}) }}
  {%- else -%}
    {{ return({'sql': src_sql, 'rel': none}) }}
  {%- endif -%}
{% endmacro %}

{# ---------------------------------------------------------------------------
   Target hazırlığı
     yoksa: odi_create_target_table -> CTAS (odi_trino_table_properties ile, ör. partitioning)
     --full-refresh (sadece odi_allow_full_refresh: true) / odi_truncate / odi_delete_all -> DELETE FROM
     odi_partition: truncate | delete -> DELETE ... WHERE dönem ; none -> bir şey yapma
--------------------------------------------------------------------------- #}
{% macro odi_trn_prepare_target(ctx, target, from_sql, cols, extra_cols_sql='') %}
  {%- do odi_guard_source_rows(ctx, from_sql) -%}
  {%- if not odi_table_exists(target) -%}
    {%- if config.get('odi_create_target_table', false) -%}
      {%- set q -%}
create table {{ target }}{{ odi_trn_with(config.get('odi_trino_table_properties', none)) }} as
select {{ extra_cols_sql }}{{ odi_col_list(cols, 'f') }}
       {%- for c, e in odi_audit('insert').items() if c not in cols %}, {{ e }} as {{ c }}{% endfor %}
       {%- for c, e in odi_audit('update').items() if c not in cols and c not in odi_audit('insert') %}, {{ e }} as {{ c }}{% endfor %}
  from {{ from_sql }} f
 where 1 = 0
      {%- endset -%}
      {%- do odi_exec(ctx, 'Create target table', q) -%}
    {%- else -%}
      {%- do exceptions.raise_compiler_error('Target ' ~ target ~ ' yok. Önceden açın ya da odi_create_target_table: true verin.') -%}
    {%- endif -%}
  {%- endif -%}

  {%- if should_full_refresh() or config.get('odi_truncate', false) or config.get('odi_delete_all', false) -%}
    {%- do odi_exec(ctx, 'Delete all rows (truncate)', 'delete from ' ~ target) -%}
  {%- else -%}
    {%- set s = odi_part_spec() -%}
    {%- if s is not none -%}
      {%- if s['strategy'] in ['truncate', 'delete'] -%}
        {%- set q -%}
delete from {{ target }}
 where {{ s['column'] }} >= {{ s['lo'] }} and {{ s['column'] }} < {{ s['hi'] }}
        {%- endset -%}
        {%- do odi_exec(ctx, 'Delete partition rows ' ~ s['label'], q) -%}
      {%- elif s['strategy'] == 'exchange' -%}
        {%- do exceptions.raise_compiler_error(this ~ ": Trino'da partition exchange yok; strategy='delete' kullanın.") -%}
      {%- elif s['strategy'] != 'none' -%}
        {%- do exceptions.raise_compiler_error(this ~ ": odi_partition.strategy '" ~ s['strategy'] ~ "' geçersiz (truncate|delete|none).") -%}
      {%- endif -%}
    {%- endif -%}
  {%- endif -%}
{% endmacro %}

{# ---------------------------------------------------------------------------
   Kaynakta olmayanı sil / soft delete — anti-join + MERGE (correlated DELETE yerine)
--------------------------------------------------------------------------- #}
{% macro odi_trn_delete_missing(ctx, target, keys, key_sql, e_rel=none) %}
  {%- if config.get('odi_delete_missing', false) -%}
    {%- set flt   = config.get('odi_delete_missing_filter', none) -%}
    {%- set ppred = odi_partition_predicate('t') -%}
    {%- set soft  = odi_upper_dict(config.get('odi_soft_delete', none)) -%}
    {%- set q -%}
merge into {{ target }} tt
using (
  select distinct {{ odi_col_list(keys, 't') }}
    from {{ target }} t
    left join ( select distinct {{ odi_col_list(keys) }} from ( {{ key_sql }} ) ) k
      on {{ odi_key_join(keys, 't', 'k') }}
  {%- if e_rel %}
    left join ( select distinct {{ odi_col_list(keys) }} from {{ e_rel }} where ODI_SESS_NO = '{{ invocation_id }}' ) e
      on {{ odi_key_join(keys, 't', 'e') }}
  {%- endif %}
   where k.{{ keys[0] }} is null
  {%- if e_rel %}
     and e.{{ keys[0] }} is null
  {%- endif %}
  {%- if ppred %}
     and {{ ppred }}
  {%- endif %}
  {%- if flt %}
     and ( {{ flt }} )
  {%- endif %}
) d
   on ( {{ odi_key_join(keys, 'tt', 'd') }} )
{%- if soft %}
 when matched and {{ odi_null_ne('tt.' ~ soft['COLUMN'], soft['VALUE']) }} then update set
      {{ soft['COLUMN'] }} = {{ soft['VALUE'] }}
      {%- for c, e in odi_audit('update').items() %},
      {{ c }} = {{ e }}{% endfor %}
{%- else %}
 when matched then delete
{%- endif %}
    {%- endset -%}
    {%- do odi_exec(ctx, 'Delete rows missing in source' ~ (' (soft delete)' if soft else ''), q) -%}
  {%- endif -%}
{% endmacro %}

{# ---------------------------------------------------------------------------
   Upsert çekirdeği — Trino'da hem odi_incremental_update hem odi_merge bunu kullanır.
   Oracle'daki D/U/N/I etiketleme adımları tek MERGE'in WHEN dallarına karşılık gelir:
     WHEN MATCHED AND del=1            -> DELETE (veya soft delete UPDATE)          = 'D'
     WHEN MATCHED AND del=0 AND fark   -> UPDATE                                     = 'U'
     (eşleşen, fark yok)               -> hiçbir dal çalışmaz                        = 'N'
     WHEN NOT MATCHED AND del=0        -> INSERT                                     = 'I'
--------------------------------------------------------------------------- #}
{% macro odi_trn_upsert(km_name, require_flow) %}
  {%- set ctx    = odi_ctx(km_name) -%}
  {%- set target = this.incorporate(type='table') -%}
  {%- set keys   = odi_as_list(config.get('unique_key')) -%}
  {%- if keys | length == 0 -%}
    {%- do exceptions.raise_compiler_error(this ~ ': unique_key zorunlu.') -%}
  {%- endif -%}
  {%- set flags    = odi_flags() -%}
  {%- set use_flow = (config.get('odi_flow_mode', 'table') | lower) != 'none' -%}
  {%- if require_flow and not use_flow -%}
    {%- do exceptions.raise_compiler_error(this ~ ": odi_incremental_update flow tablosu gerektirir; flow'suz upsert için odi_merge kullanın.") -%}
  {%- endif -%}
  {%- if not use_flow and config.get('odi_flow_control', false) -%}
    {%- do exceptions.raise_compiler_error(this ~ ": odi_flow_control için flow tablosu gerekir; odi_flow_mode 'none' olamaz.") -%}
  {%- endif -%}
  {%- set del_cond = config.get('odi_delete_condition', none) -%}
  {%- set soft     = odi_upper_dict(config.get('odi_soft_delete', none)) -%}
  {%- set flow     = odi_work_relation('I$_', 'odi_flow_table') -%}

  {{ run_hooks(pre_hooks) }}

  {%- set lkm = odi_trn_lkm_stage(ctx, sql) -%}
  {%- set src_sql = lkm['sql'] -%}

  {%- set cols      = odi_query_columns(src_sql) -%}
  {%- set flow_only = odi_as_list(config.get('odi_flow_only_columns', [])) -%}
  {%- set tcols     = [] -%}
  {%- for c in cols if c not in flow_only -%}{%- do tcols.append(c) -%}{%- endfor -%}
  {%- set no_upd    = odi_as_list(config.get('odi_exclude_update_columns', [])) -%}
  {%- set pspec     = odi_part_spec() -%}
  {%- if pspec is not none and pspec['column'] -%}{%- do no_upd.append(pspec['column']) -%}{%- endif -%}
  {%- set no_cmp    = odi_as_list(config.get('odi_compare_exclude', [])) -%}
  {%- set upd_cols  = [] -%}
  {%- for c in tcols if c not in keys and c not in no_upd -%}{%- do upd_cols.append(c) -%}{%- endfor -%}
  {%- set cmp_cols  = [] -%}
  {%- for c in upd_cols if c not in no_cmp -%}{%- do cmp_cols.append(c) -%}{%- endfor -%}
  {%- set aud_ins   = odi_audit('insert') -%}
  {%- set aud_upd   = odi_audit('update') -%}
  {%- set ppred     = odi_partition_predicate('t') -%}
  {%- set e_rel     = none -%}

  {%- if use_flow -%}
    {%- do odi_trn_load_work_table(ctx, flow, src_sql, cols, 'I$ (flow)') -%}
    {%- set e_rel = odi_ckm_flow_control(ctx, flow, cols, keys, has_ind=false) -%}
    {%- set base_sql = 'select ' ~ odi_col_list(cols) ~ ' from ' ~ flow -%}
  {%- else -%}
    {%- set base_sql = src_sql -%}
  {%- endif -%}
  {%- do odi_trn_prepare_target(ctx, target, '( ' ~ base_sql ~ ' )', tcols) -%}

  {%- set using_sql = 'select s0.*, ' ~ ('case when ( ' ~ del_cond ~ ' ) then 1 else 0 end' if del_cond else '0') ~ ' as ODI_DEL_FLG from ( ' ~ base_sql ~ ' ) s0' -%}
  {%- set diff = odi_any_diff(cmp_cols, 't', 's') if (config.get('odi_detect_changes', true) and cmp_cols | length > 0) else none -%}

  {%- set q -%}
merge into {{ target }} t
using ( {{ using_sql }} ) s
   on ( {{ odi_key_join(keys, 't', 's') }}{{ ' and ' ~ ppred if ppred }} )
{%- if del_cond and soft %}
 when matched and s.ODI_DEL_FLG = 1 and {{ odi_null_ne('t.' ~ soft['COLUMN'], soft['VALUE']) }} then update set
      {{ soft['COLUMN'] }} = {{ soft['VALUE'] }}
      {%- for c, e in aud_upd.items() %},
      {{ c }} = {{ e }}{% endfor %}
{%- elif del_cond %}
 when matched and s.ODI_DEL_FLG = 1 then delete
{%- endif %}
{%- if flags['update'] and (upd_cols or aud_upd) %}
 when matched and s.ODI_DEL_FLG = 0{{ ' and ( ' ~ diff ~ ' )' if diff }} then update set
      {% for c in upd_cols %}{{ c }} = s.{{ c }}{{ ',\n      ' if not loop.last }}{% endfor %}
      {%- for c, e in aud_upd.items() %}{{ ',' if upd_cols or not loop.first }}
      {{ c }} = {{ e }}{% endfor %}
{%- endif %}
{%- if flags['insert'] %}
 when not matched and s.ODI_DEL_FLG = 0 then insert
      ( {{ odi_col_list(tcols) }}{% for c in aud_ins %}, {{ c }}{% endfor %} )
      values ( {{ odi_col_list(tcols, 's') }}{% for c, e in aud_ins.items() %}, {{ e }}{% endfor %} )
{%- endif %}
  {%- endset -%}
  {%- do odi_exec(ctx, 'Merge rows', q, name='main') -%}

  {%- if config.get('odi_delete_missing', false) -%}
    {%- set key_sql = 'select ' ~ odi_col_list(keys) ~ ' from ' ~ (flow if use_flow else '( ' ~ src_sql ~ ' )') -%}
    {%- do odi_trn_delete_missing(ctx, target, keys, key_sql, e_rel) -%}
  {%- endif -%}

  {%- set tmp = [] -%}
  {%- if use_flow -%}{%- do tmp.append(flow) -%}{%- endif -%}
  {%- if lkm['rel'] is not none -%}{%- do tmp.append(lkm['rel']) -%}{%- endif -%}
  {%- do odi_trn_cleanup(ctx, tmp) -%}

  {{ run_hooks(post_hooks) }}
  {{ return({'relations': [target]}) }}
{% endmacro %}
