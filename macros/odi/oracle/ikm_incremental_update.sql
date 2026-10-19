{#
  ============================================================================
   IKM Oracle Incremental Update   ->   materialized='odi_incremental_update'

   Step'ler:
     [LKM]  C$ stage                               (odi_lkm)
            I$ drop/create/insert, IND_UPDATE='I'  (odi_flow_mode)
            CKM flow control                       (odi_flow_control, odi_recycle_errors)
            Target: create / truncate / delete / partition hazırlığı
            Flag rows for delete     IND_UPDATE='D' (odi_delete_condition)
            Flag rows for update     IND_UPDATE='U'
            Flag useless rows        IND_UPDATE='N' (odi_detect_changes)
            Delete flagged rows                    (hard / odi_soft_delete)
            Update existing rows                   (odi_update)
            Insert new rows                        (odi_insert)      -> statement 'main'
            Delete rows missing in source          (odi_delete_missing)
            Commit / cleanup

   Zorunlu: unique_key (ODI "Update Key")
  ============================================================================
#}

{% materialization odi_incremental_update, adapter='oracle' %}
  {%- set ctx    = odi_ctx('IKM Oracle Incremental Update') -%}
  {%- set target = this.incorporate(type='table') -%}
  {%- set keys   = odi_as_list(config.get('unique_key')) -%}
  {%- if keys | length == 0 -%}
    {%- do exceptions.raise_compiler_error(this ~ ': odi_incremental_update için unique_key (update key) zorunlu.') -%}
  {%- endif -%}
  {%- if (config.get('odi_flow_mode', 'table') | lower) == 'none' -%}
    {%- do exceptions.raise_compiler_error(this ~ ": odi_incremental_update I$ gerektirir; I$'sız upsert için odi_merge kullanın.") -%}
  {%- endif -%}
  {%- set flags  = odi_flags() -%}
  {%- set flow   = odi_work_relation('I$_', 'odi_flow_table') -%}
  {%- set del_cond = config.get('odi_delete_condition', none) -%}

  {{ odi_hooks_pre(ctx) }}

  {%- set lkm = odi_lkm_stage(ctx, sql) -%}
  {%- set src_sql = lkm['sql'] -%}

  {%- set cols     = odi_query_columns(src_sql) -%}
  {#- odi_flow_only_columns: flow'da olan ama target'a yazılmayan kolonlar (ör. CDC OP_TYPE) -#}
  {%- set flow_only = odi_as_list(config.get('odi_flow_only_columns', [])) -%}
  {%- set tcols    = [] -%}
  {%- for c in cols if c not in flow_only -%}{%- do tcols.append(c) -%}{%- endfor -%}
  {%- set no_upd   = odi_as_list(config.get('odi_exclude_update_columns', [])) -%}
  {%- set no_cmp   = odi_as_list(config.get('odi_compare_exclude', [])) -%}
  {%- set upd_cols = [] -%}
  {%- for c in tcols if c not in keys and c not in no_upd -%}{%- do upd_cols.append(c) -%}{%- endfor -%}
  {%- set cmp_cols = [] -%}
  {%- for c in upd_cols if c not in no_cmp -%}{%- do cmp_cols.append(c) -%}{%- endfor -%}
  {%- set aud_ins  = odi_audit('insert') -%}
  {%- set aud_upd  = odi_audit('update') -%}
  {%- set ppred    = odi_partition_predicate('t') -%}

  {#- ---- Flow (I$) + CKM ---- -#}
  {%- do odi_load_work_table(ctx, flow, src_sql, cols, 'I$ (flow)', with_ind_update=true) -%}
  {%- set e_rel = odi_ckm_flow_control(ctx, flow, cols, keys) -%}

  {#- ---- Target ---- -#}
  {%- do odi_prepare_target(ctx, target, flow, tcols) -%}

  {#- ---- Flag rows for delete (SYNC_JRN_DELETE / CDC op flag) ---- -#}
  {%- if del_cond -%}
    {%- do odi_exec(ctx, 'Flag rows for delete', 'update ' ~ flow ~ " set IND_UPDATE = 'D' where ( " ~ del_cond ~ ' )') -%}
  {%- endif -%}

  {#- ---- Flag rows for update ---- -#}
  {%- set q -%}
update {{ flow }} f
   set f.IND_UPDATE = 'U'
 where f.IND_UPDATE = 'I'
   and exists ( select 1 from {{ target }} t
                 where {{ odi_key_join(keys) }}{{ ' and ' ~ ppred if ppred }} )
  {%- endset -%}
  {%- do odi_exec(ctx, 'Flag rows for update', q) -%}

  {#- ---- Flag useless rows ---- -#}
  {%- if flags['update'] and config.get('odi_detect_changes', true) -%}
    {%- set q -%}
update {{ flow }} f
   set f.IND_UPDATE = 'N'
 where f.IND_UPDATE = 'U'
   and exists ( select 1 from {{ target }} t
                 where {{ odi_key_join(keys) }}{{ ' and ' ~ ppred if ppred }}
                   and {{ odi_all_equal(cmp_cols) }} )
    {%- endset -%}
    {%- do odi_exec(ctx, 'Flag useless rows', q) -%}
  {%- endif -%}

  {#- ---- Delete flagged rows ---- -#}
  {%- if del_cond -%}
    {%- set w -%}
{{ odi_tuple(keys, 't') }} in ( select {{ odi_col_list(keys) }} from {{ flow }} where IND_UPDATE = 'D' ){{ ' and ' ~ ppred if ppred }}
    {%- endset -%}
    {%- do odi_delete_target_rows(ctx, target, w, 'Delete flagged rows') -%}
  {%- endif -%}

  {#- ---- Update existing rows ---- -#}
  {%- if flags['update'] and upd_cols | length > 0 -%}
    {%- if config.get('odi_update_method', 'correlated') == 'merge' -%}
      {%- set q -%}
merge {{ odi_hint(config.get('odi_update_hint', none)) }} into {{ target }} t
using ( select {{ odi_col_list(keys + upd_cols) }} from {{ flow }} where IND_UPDATE = 'U' ) f
   on ( {{ odi_key_join(keys) }}{{ ' and ' ~ ppred if ppred }} )
 when matched then update set
      {% for c in upd_cols %}t.{{ c }} = f.{{ c }}{{ ',\n      ' if not loop.last }}{% endfor %}
      {%- for c, e in aud_upd.items() %},
      t.{{ c }} = {{ e }}{% endfor %}
      {%- endset -%}
    {%- else -%}
      {%- set q -%}
update {{ odi_hint(config.get('odi_update_hint', none)) }} {{ target }} t
   set ( {{ odi_col_list(upd_cols) }} ) =
       ( select {{ odi_col_list(upd_cols, 'f') }}
           from {{ flow }} f
          where {{ odi_key_join(keys) }}
            and f.IND_UPDATE = 'U' )
       {%- for c, e in aud_upd.items() %},
       {{ c }} = {{ e }}{% endfor %}
 where {{ odi_tuple(keys, 't') }} in ( select {{ odi_col_list(keys) }} from {{ flow }} where IND_UPDATE = 'U' )
       {{- ' and ' ~ ppred if ppred }}
      {%- endset -%}
    {%- endif -%}
    {%- do odi_exec(ctx, 'Update existing rows', q, name=('odi_step' if flags['insert'] else 'main')) -%}
    {%- do odi_commit_if_parallel(ctx) -%}
  {%- endif -%}

  {#- ---- Insert new rows ---- -#}
  {%- if flags['insert'] -%}
    {%- set q -%}
insert {{ odi_hint(config.get('odi_insert_hint', 'APPEND')) }} into {{ target }}
  ( {{ odi_col_list(tcols) }}{% for c in aud_ins %}, {{ c }}{% endfor %} )
select {{ odi_col_list(tcols, 'f') }}{% for c, e in aud_ins.items() %}, {{ e }}{% endfor %}
  from {{ flow }} f
 where f.IND_UPDATE = 'I'
    {%- endset -%}
    {%- do odi_exec(ctx, 'Insert new rows', q, name='main') -%}
    {%- do odi_commit_if_parallel(ctx) -%}
  {%- endif -%}

  {#- ---- Delete rows missing in source ---- -#}
  {%- if config.get('odi_delete_missing', false) -%}
    {%- if flags['insert'] and not config.get('odi_parallel_dml', false) -%}
      {#- APPEND insert sonrası aynı transaction'da target okunamaz -#}
      {%- do odi_commit(ctx) -%}
    {%- endif -%}
    {%- do odi_delete_missing(ctx, target, keys, 'select ' ~ odi_col_list(keys) ~ ' from ' ~ flow, e_rel) -%}
  {%- endif -%}
  {%- if not flags['insert'] and upd_cols | length == 0 -%}
    {% call statement('main') %}select 1 from dual{% endcall %}
  {%- endif -%}
  {%- do odi_commit(ctx) -%}

  {%- set tmp = [flow] -%}
  {%- if lkm['rel'] is not none -%}{%- do tmp.append(lkm['rel']) -%}{%- endif -%}
  {%- do odi_cleanup(ctx, tmp) -%}

  {{ odi_hooks_post(ctx) }}
  {{ return({'relations': [target]}) }}
{% endmaterialization %}
