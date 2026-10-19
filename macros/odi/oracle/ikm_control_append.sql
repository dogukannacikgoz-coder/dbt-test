{#
  ============================================================================
   IKM Oracle Control Append   ->   materialized='odi_control_append'

   Step'ler:
     [LKM]  C$ stage                               (odi_lkm)
            FLOW_CONTROL=false -> I$ yok, doğrudan target'a INSERT /*+ APPEND */
            FLOW_CONTROL=true  -> I$ + CKM, sonra I$'tan target'a insert
            Target: create / truncate / delete_all / partition (truncate|delete)
            Insert new rows                        -> statement 'main'
            Commit / cleanup

   Tipik kullanım: staging, snapshot, günlük partition yenileme (truncate partition + append)
  ============================================================================
#}

{% materialization odi_control_append, adapter='oracle' %}
  {%- set ctx    = odi_ctx('IKM Oracle Control Append') -%}
  {%- set target = this.incorporate(type='table') -%}
  {%- set fc     = config.get('odi_flow_control', false) -%}
  {%- set flow   = odi_work_relation('I$_', 'odi_flow_table') -%}

  {{ odi_hooks_pre(ctx) }}

  {%- set lkm = odi_lkm_stage(ctx, sql) -%}
  {%- set src_sql = lkm['sql'] -%}
  {%- set cols    = odi_query_columns(src_sql) -%}
  {%- set aud_ins = odi_audit('insert') -%}
  {%- set tmp     = [] -%}

  {%- if fc -%}
    {%- do odi_load_work_table(ctx, flow, src_sql, cols, 'I$ (flow)') -%}
    {%- do odi_ckm_flow_control(ctx, flow, cols, odi_as_list(config.get('unique_key')), has_ind=false) -%}
    {%- do odi_prepare_target(ctx, target, flow, cols) -%}
    {%- set from_sql = flow -%}
    {%- do tmp.append(flow) -%}
  {%- else -%}
    {%- do odi_prepare_target(ctx, target, '( ' ~ src_sql ~ ' )', cols) -%}
    {%- set from_sql = '( ' ~ src_sql ~ ' )' -%}
  {%- endif -%}

  {%- set q -%}
insert {{ odi_hint(config.get('odi_insert_hint', 'APPEND')) }} into {{ target }}
  ( {{ odi_col_list(cols) }}{% for c in aud_ins %}, {{ c }}{% endfor %} )
select {{ odi_hint(config.get('odi_flow_select_hint', none)) }}
       {{ odi_col_list(cols, 'f') }}{% for c, e in aud_ins.items() %}, {{ e }}{% endfor %}
  from {{ from_sql }} f
  {%- endset -%}
  {%- do odi_exec(ctx, 'Insert new rows', q, name='main') -%}
  {%- do odi_commit(ctx) -%}

  {%- if lkm['rel'] is not none -%}{%- do tmp.append(lkm['rel']) -%}{%- endif -%}
  {%- do odi_cleanup(ctx, tmp) -%}

  {{ odi_hooks_post(ctx) }}
  {{ return({'relations': [target]}) }}
{% endmaterialization %}
