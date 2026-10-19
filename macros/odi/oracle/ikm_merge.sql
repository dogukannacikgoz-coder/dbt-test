{#
  ============================================================================
   IKM Oracle Incremental Update (MERGE)   ->   materialized='odi_merge'

   Step'ler:
     [LKM]  C$ stage                               (odi_lkm)
            I$ flow (default) — odi_flow_mode: 'none' -> I$ yok, MERGE doğrudan model SQL'inden
            CKM flow control                       (I$ gerektirir)
            Target: create / truncate / partition hazırlığı
            MERGE                                  -> statement 'main'
              when matched     -> update (sadece değişenler; odi_update)
                                  + odi_delete_condition sağlayanlar silinir (veya soft delete)
              when not matched -> insert (odi_insert; delete koşulunu sağlayanlar insert edilmez)
            Delete rows missing in source          (odi_delete_missing)
            Commit / cleanup

   Zorunlu: unique_key
  ============================================================================
#}

{% materialization odi_merge, adapter='oracle' %}
  {%- set ctx    = odi_ctx('IKM Oracle Incremental Update (MERGE)') -%}
  {%- set target = this.incorporate(type='table') -%}
  {%- set keys   = odi_as_list(config.get('unique_key')) -%}
  {%- if keys | length == 0 -%}
    {%- do exceptions.raise_compiler_error(this ~ ': odi_merge için unique_key zorunlu.') -%}
  {%- endif -%}
  {%- set flags    = odi_flags() -%}
  {%- set use_flow = (config.get('odi_flow_mode', 'table') | lower) != 'none' -%}
  {%- if not use_flow and config.get('odi_flow_control', false) -%}
    {%- do exceptions.raise_compiler_error(this ~ ": odi_flow_control için I$ gerekir; odi_flow_mode 'none' olamaz.") -%}
  {%- endif -%}
  {%- set del_cond = config.get('odi_delete_condition', none) -%}
  {%- set soft     = odi_upper_dict(config.get('odi_soft_delete', none)) -%}
  {%- if del_cond and not flags['update'] -%}
    {%- do exceptions.raise_compiler_error(this ~ ': odi_merge + odi_delete_condition için odi_update true olmalı (Oracle MERGE silmeyi update dalında yapar).') -%}
  {%- endif -%}
  {%- set flow = odi_work_relation('I$_', 'odi_flow_table') -%}

  {{ odi_hooks_pre(ctx) }}

  {%- set lkm = odi_lkm_stage(ctx, sql) -%}
  {%- set src_sql = lkm['sql'] -%}

  {%- set cols     = odi_query_columns(src_sql) -%}
  {#- odi_flow_only_columns: flow'da olan ama target'a yazılmayan kolonlar (ör. CDC OP_TYPE) -#}
  {%- set flow_only = odi_as_list(config.get('odi_flow_only_columns', [])) -%}
  {%- set tcols    = [] -%}
  {%- for c in cols if c not in flow_only -%}{%- do tcols.append(c) -%}{%- endfor -%}
  {%- set no_upd   = odi_as_list(config.get('odi_exclude_update_columns', [])) -%}
  {#- partition kolonu ON koşulunda kullanılıyorsa update edilemez (ORA-38104) -#}
  {%- set pspec = odi_part_spec() -%}
  {%- if pspec is not none and pspec['column'] -%}{%- do no_upd.append(pspec['column']) -%}{%- endif -%}
  {%- set no_cmp   = odi_as_list(config.get('odi_compare_exclude', [])) -%}
  {%- set upd_cols = [] -%}
  {%- for c in tcols if c not in keys and c not in no_upd -%}{%- do upd_cols.append(c) -%}{%- endfor -%}
  {%- set cmp_cols = [] -%}
  {%- for c in upd_cols if c not in no_cmp -%}{%- do cmp_cols.append(c) -%}{%- endfor -%}
  {%- set aud_ins  = odi_audit('insert') -%}
  {%- set aud_upd  = odi_audit('update') -%}
  {%- set ppred    = odi_partition_predicate('t') -%}
  {%- set e_rel    = none -%}

  {%- if use_flow -%}
    {%- do odi_load_work_table(ctx, flow, src_sql, cols, 'I$ (flow)', with_ind_update=true) -%}
    {%- set e_rel = odi_ckm_flow_control(ctx, flow, cols, keys) -%}
    {%- set base_sql = 'select ' ~ odi_col_list(cols) ~ ' from ' ~ flow -%}
    {%- do odi_prepare_target(ctx, target, flow, tcols) -%}
  {%- else -%}
    {%- set base_sql = src_sql -%}
    {%- do odi_prepare_target(ctx, target, '( ' ~ src_sql ~ ' )', tcols) -%}
  {%- endif -%}

  {%- if del_cond -%}
    {%- set using_sql = 'select odi_s.*, case when ( ' ~ del_cond ~ ' ) then 1 else 0 end as ODI_DEL_FLG from ( ' ~ base_sql ~ ' ) odi_s' -%}
  {%- else -%}
    {%- set using_sql = base_sql -%}
  {%- endif -%}

  {%- set q -%}
merge {{ odi_hint(config.get('odi_merge_hint', none)) }} into {{ target }} t
using ( {{ using_sql }} ) s
   on ( {{ odi_key_join(keys, 't', 's') }}{{ ' and ' ~ ppred if ppred }} )
{%- if flags['update'] %}
  {%- set sets = [] -%}
  {%- if soft and del_cond -%}
    {%- do sets.append('t.' ~ soft['COLUMN'] ~ ' = case when s.ODI_DEL_FLG = 1 then ' ~ soft['VALUE'] ~ ' else t.' ~ soft['COLUMN'] ~ ' end') -%}
  {%- endif -%}
  {%- for c in upd_cols -%}
    {%- if soft and del_cond -%}
      {%- do sets.append('t.' ~ c ~ ' = case when s.ODI_DEL_FLG = 1 then t.' ~ c ~ ' else s.' ~ c ~ ' end') -%}
    {%- else -%}
      {%- do sets.append('t.' ~ c ~ ' = s.' ~ c) -%}
    {%- endif -%}
  {%- endfor -%}
  {%- for c, e in aud_upd.items() -%}{%- do sets.append('t.' ~ c ~ ' = ' ~ e) -%}{%- endfor -%}
  {%- set where_parts = [] -%}
  {%- if config.get('odi_detect_changes', true) and cmp_cols | length > 0 -%}
    {%- do where_parts.append('( ' ~ odi_any_diff(cmp_cols, 't', 's') ~ ' )') -%}
    {%- if del_cond and soft -%}
      {%- do where_parts.append('( s.ODI_DEL_FLG = 1 and decode(t.' ~ soft['COLUMN'] ~ ', ' ~ soft['VALUE'] ~ ', 1, 0) = 0 )') -%}
    {%- elif del_cond -%}
      {%- do where_parts.append('s.ODI_DEL_FLG = 1') -%}
    {%- endif -%}
  {%- endif -%}
  {%- if sets %}
 when matched then update set
      {{ sets | join(',\n      ') }}
    {%- if where_parts %}
      where {{ where_parts | join('\n         or ') }}
    {%- endif %}
    {%- if del_cond and not soft %}
      delete where s.ODI_DEL_FLG = 1
    {%- endif %}
  {%- elif del_cond -%}
    {%- do exceptions.raise_compiler_error(this ~ ': odi_delete_condition için MERGE update dalında en az bir güncellenebilir kolon gerekir.') -%}
  {%- endif %}
{%- endif %}
{%- if flags['insert'] %}
 when not matched then insert
      ( {{ odi_col_list(tcols, 't') }}{% for c in aud_ins %}, t.{{ c }}{% endfor %} )
      values ( {{ odi_col_list(tcols, 's') }}{% for c, e in aud_ins.items() %}, {{ e }}{% endfor %} )
  {%- if del_cond %}
      where s.ODI_DEL_FLG = 0
  {%- endif %}
{%- endif %}
  {%- endset -%}
  {%- do odi_exec(ctx, 'Merge rows', q, name='main') -%}

  {#- ---- Delete rows missing in source ---- -#}
  {%- if config.get('odi_delete_missing', false) -%}
    {%- do odi_commit_if_parallel(ctx) -%}
    {%- set key_sql = 'select ' ~ odi_col_list(keys) ~ ' from ' ~ (flow if use_flow else '( ' ~ src_sql ~ ' )') -%}
    {%- do odi_delete_missing(ctx, target, keys, key_sql, e_rel) -%}
  {%- endif -%}
  {%- do odi_commit(ctx) -%}

  {%- set tmp = [] -%}
  {%- if use_flow -%}{%- do tmp.append(flow) -%}{%- endif -%}
  {%- if lkm['rel'] is not none -%}{%- do tmp.append(lkm['rel']) -%}{%- endif -%}
  {%- do odi_cleanup(ctx, tmp) -%}

  {{ odi_hooks_post(ctx) }}
  {{ return({'relations': [target]}) }}
{% endmaterialization %}
