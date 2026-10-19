{#
  ============================================================================
   Trino (Iceberg) materialization'ları — Oracle'dakilerle AYNI isim ve config'ler.
   dbt, target tipi trino olduğunda bunları seçer.
  ============================================================================
#}

{# ---------------------------------------------------------------------------
   odi_control_append (Trino)
     (delete all / partition delete) + INSERT INTO ; flow control açıksa flow + CKM
--------------------------------------------------------------------------- #}
{% materialization odi_control_append, adapter='trino' %}
  {%- set ctx    = odi_ctx('IKM Control Append (Trino)') -%}
  {%- set target = this.incorporate(type='table') -%}
  {%- set fc     = config.get('odi_flow_control', false) -%}
  {%- set flow   = odi_work_relation('I$_', 'odi_flow_table') -%}

  {{ run_hooks(pre_hooks) }}

  {%- set lkm     = odi_trn_lkm_stage(ctx, sql) -%}
  {%- set src_sql = lkm['sql'] -%}
  {%- set cols    = odi_query_columns(src_sql) -%}
  {%- set aud_ins = odi_audit('insert') -%}
  {%- set tmp     = [] -%}

  {%- if fc -%}
    {%- do odi_trn_load_work_table(ctx, flow, src_sql, cols, 'I$ (flow)') -%}
    {%- do odi_ckm_flow_control(ctx, flow, cols, odi_as_list(config.get('unique_key')), has_ind=false) -%}
    {%- set from_sql = '( select ' ~ odi_col_list(cols) ~ ' from ' ~ flow ~ ' )' -%}
    {%- do tmp.append(flow) -%}
  {%- else -%}
    {%- set from_sql = '( ' ~ src_sql ~ ' )' -%}
  {%- endif -%}
  {%- do odi_trn_prepare_target(ctx, target, from_sql, cols) -%}

  {%- set q -%}
insert into {{ target }}
  ( {{ odi_col_list(cols) }}{% for c in aud_ins %}, {{ c }}{% endfor %} )
select {{ odi_col_list(cols, 'f') }}{% for c, e in aud_ins.items() %}, {{ e }}{% endfor %}
  from {{ from_sql }} f
  {%- endset -%}
  {%- do odi_exec(ctx, 'Insert new rows', q, name='main') -%}

  {%- if lkm['rel'] is not none -%}{%- do tmp.append(lkm['rel']) -%}{%- endif -%}
  {%- do odi_trn_cleanup(ctx, tmp) -%}

  {{ run_hooks(post_hooks) }}
  {{ return({'relations': [target]}) }}
{% endmaterialization %}

{# ---------------------------------------------------------------------------
   odi_incremental_update (Trino): flow + CKM + tek MERGE (atomik)
   odi_merge (Trino): aynı, flow opsiyonel (odi_flow_mode='none')
--------------------------------------------------------------------------- #}
{% materialization odi_incremental_update, adapter='trino' %}
  {{ return(odi_trn_upsert('IKM Incremental Update (Trino)', true)) }}
{% endmaterialization %}

{% materialization odi_merge, adapter='trino' %}
  {{ return(odi_trn_upsert('IKM Incremental Update MERGE (Trino)', false)) }}
{% endmaterialization %}

{# ---------------------------------------------------------------------------
   odi_partition_exchange (Trino): yok
--------------------------------------------------------------------------- #}
{% materialization odi_partition_exchange, adapter='trino' %}
  {%- do exceptions.raise_compiler_error(this ~ ": Trino/Iceberg'de EXCHANGE PARTITION yok. "
        ~ "materialized='odi_control_append' + odi_partition strategy='delete' kullanın "
        ~ "(DELETE partition'a hizalıysa metadata işlemidir).") -%}
{% endmaterialization %}

{# ---------------------------------------------------------------------------
   odi_scd (Trino)
     flow + CKM
     MERGE #1  (current kayıtlar):
        WHEN MATCHED AND SCD2 kolonlarından biri farklı -> historize (flag / end_date)
        WHEN MATCHED AND SCD1 kolonlarından biri farklı -> overwrite
     MERGE #2  close_missing (anti-join)
     INSERT    current kaydı olmayan NK'lar (yeni + historize edilenler) -> yeni versiyon
   SK: surrogate_expr verilmezse max(SK) + row_number() (Iceberg'de identity yok)
   NOT: 2-3 statement, Trino'da tek transaction değil. Arada fail olursa tekrar koşmak güvenli:
        historize edilmiş ama insert edilmemiş NK, sonraki run'da "current yok" sayılıp insert edilir.
--------------------------------------------------------------------------- #}
{% materialization odi_scd, adapter='trino' %}
  {%- set ctx    = odi_ctx('IKM Slowly Changing Dimension (Trino)') -%}
  {%- set target = this.incorporate(type='table') -%}
  {%- set scd    = config.get('odi_scd') -%}
  {%- if not scd -%}
    {%- do exceptions.raise_compiler_error(this ~ ': odi_scd config zorunlu.') -%}
  {%- endif -%}
  {%- set sk       = (scd.get('surrogate_key') or '') | upper -%}
  {%- set nk       = odi_as_list(scd.get('natural_key')) -%}
  {%- set ow       = odi_as_list(scd.get('overwrite_on_change', [])) -%}
  {%- set flag     = (scd.get('current_flag') or '') | upper -%}
  {%- set cur_val  = scd.get('current_value', '1') | string -%}
  {%- set hist_val = scd.get('history_value', '0') | string -%}
  {%- set sd       = (scd.get('start_date') or '') | upper -%}
  {%- set ed       = (scd.get('end_date') or '') | upper -%}
  {%- set start_ex = scd.get('start_expr', 'localtimestamp') -%}
  {%- set close_ex = scd.get('end_expr_on_close', start_ex) -%}
  {%- set max_dt   = scd.get('max_end_date', "TIMESTAMP '2400-01-01 00:00:00'") -%}
  {%- set ow_all   = scd.get('overwrite_all_versions', false) -%}
  {%- if nk | length == 0 -%}
    {%- do exceptions.raise_compiler_error(this ~ ': odi_scd.natural_key zorunlu.') -%}
  {%- endif -%}
  {%- if not flag and not ed -%}
    {%- do exceptions.raise_compiler_error(this ~ ': current_flag veya end_date en az biri verilmeli.') -%}
  {%- endif -%}
  {%- if (config.get('odi_flow_mode', 'table') | lower) == 'none' -%}
    {%- do exceptions.raise_compiler_error(this ~ ": odi_scd flow tablosu gerektirir.") -%}
  {%- endif -%}
  {%- set flow = odi_work_relation('I$_', 'odi_flow_table') -%}

  {{ run_hooks(pre_hooks) }}

  {%- set lkm     = odi_trn_lkm_stage(ctx, sql) -%}
  {%- set src_sql = lkm['sql'] -%}
  {%- set cols    = odi_query_columns(src_sql) -%}
  {%- for c in [sk, flag, sd, ed] if c and c in cols -%}
    {%- do exceptions.raise_compiler_error(this ~ ': ' ~ c ~ ' kolonu model SQL içinde olmamalı, IKM dolduruyor.') -%}
  {%- endfor -%}
  {%- set ar_cfg = scd.get('add_row_on_change') -%}
  {%- if ar_cfg -%}
    {%- set ar = odi_as_list(ar_cfg) -%}
  {%- else -%}
    {%- set ar = [] -%}
    {%- for c in cols if c not in nk and c not in ow -%}{%- do ar.append(c) -%}{%- endfor -%}
  {%- endif -%}
  {%- set cur_cond -%}
    {%- if flag -%}t.{{ flag }} = {{ cur_val }}{%- else -%}t.{{ ed }} = {{ max_dt }}{%- endif -%}
  {%- endset -%}
  {%- set hist_sets = [] -%}
  {%- if flag -%}{%- do hist_sets.append(flag ~ ' = ' ~ hist_val) -%}{%- endif -%}
  {%- if ed -%}{%- do hist_sets.append(ed ~ ' = ' ~ close_ex) -%}{%- endif -%}

  {#- ---- flow + CKM ---- -#}
  {%- do odi_trn_load_work_table(ctx, flow, src_sql, cols, 'I$ (flow)') -%}
  {%- set e_rel = odi_ckm_flow_control(ctx, flow, cols, nk, has_ind=false) -%}

  {#- ---- target ---- -#}
  {%- set extra -%}
    {%- if sk %}cast(null as bigint) as {{ sk }}, {% endif -%}
    {%- if flag %}cast({{ cur_val }} as integer) as {{ flag }}, {% endif -%}
    {%- if sd %}cast(null as timestamp(6)) as {{ sd }}, {% endif -%}
    {%- if ed %}cast(null as timestamp(6)) as {{ ed }}, {% endif -%}
  {%- endset -%}
  {%- do odi_trn_prepare_target(ctx, target, '( select ' ~ odi_col_list(cols) ~ ' from ' ~ flow ~ ' )', cols, extra) -%}

  {#- ---- MERGE #1: historize (SCD2) + overwrite (SCD1) ---- -#}
  {%- if ar or ow -%}
    {%- set q -%}
merge into {{ target }} t
using ( select {{ odi_col_list(cols) }} from {{ flow }} ) f
   on ( {{ odi_key_join(nk) }} )
{%- if ar %}
 when matched and {{ cur_cond }} and ( {{ odi_any_diff(ar, 't', 'f') }} ) then update set
      {{ hist_sets | join(',\n      ') }}
{%- endif %}
{%- if ow %}
 when matched{{ ' and ' ~ cur_cond if not ow_all }} and ( {{ odi_any_diff(ow, 't', 'f') }} ) then update set
      {% for c in ow %}{{ c }} = f.{{ c }}{{ ',\n      ' if not loop.last }}{% endfor %}
{%- endif %}
    {%- endset -%}
    {%- do odi_exec(ctx, 'Historize changed rows / overwrite on change', q) -%}
  {%- endif -%}

  {#- ---- MERGE #2: close rows missing in source ---- -#}
  {%- if scd.get('close_missing', false) -%}
    {%- set miss_sets = [] -%}
    {%- if flag -%}{%- do miss_sets.append(flag ~ ' = ' ~ hist_val) -%}{%- endif -%}
    {%- if ed -%}{%- do miss_sets.append(ed ~ ' = ' ~ scd.get('end_expr_missing', 'localtimestamp')) -%}{%- endif -%}
    {%- set q -%}
merge into {{ target }} tt
using (
  select distinct {{ odi_col_list(nk, 't') }}
    from {{ target }} t
    left join ( select distinct {{ odi_col_list(nk) }} from {{ flow }} ) f on {{ odi_key_join(nk, 't', 'f') }}
  {%- if e_rel %}
    left join ( select distinct {{ odi_col_list(nk) }} from {{ e_rel }} where ODI_SESS_NO = '{{ invocation_id }}' ) e
      on {{ odi_key_join(nk, 't', 'e') }}
  {%- endif %}
   where {{ cur_cond }}
     and f.{{ nk[0] }} is null
  {%- if e_rel %}
     and e.{{ nk[0] }} is null
  {%- endif %}
) d
   on ( {{ odi_key_join(nk, 'tt', 'd') }} )
 when matched and {{ cur_cond | replace('t.', 'tt.') }} then update set
      {{ miss_sets | join(',\n      ') }}
    {%- endset -%}
    {%- do odi_exec(ctx, 'Close rows missing in source', q) -%}
  {%- endif -%}

  {#- ---- INSERT: yeni NK'lar + yeni versiyonlar ---- -#}
  {%- set sk_expr = scd.get('surrogate_expr') or ('coalesce((select max(' ~ sk ~ ') from ' ~ target ~ '), 0) + row_number() over (order by ' ~ odi_col_list(nk, 'f') ~ ')') -%}
  {%- set q -%}
insert into {{ target }}
  ( {% if sk %}{{ sk }}, {% endif %}{{ odi_col_list(cols) }}
    {%- if flag %}, {{ flag }}{% endif %}{% if sd %}, {{ sd }}{% endif %}{% if ed %}, {{ ed }}{% endif %} )
select {% if sk %}{{ sk_expr }}, {% endif %}{{ odi_col_list(cols, 'f') }}
    {%- if flag %}, {{ cur_val }}{% endif %}{% if sd %}, {{ start_ex }}{% endif %}{% if ed %}, {{ max_dt }}{% endif %}
  from {{ flow }} f
 where not exists ( select 1 from {{ target }} t where {{ odi_key_join(nk) }} and {{ cur_cond }} )
  {%- endset -%}
  {%- do odi_exec(ctx, 'Insert new rows / new versions', q, name='main') -%}

  {%- set tmp = [flow] -%}
  {%- if lkm['rel'] is not none -%}{%- do tmp.append(lkm['rel']) -%}{%- endif -%}
  {%- do odi_trn_cleanup(ctx, tmp) -%}

  {{ run_hooks(post_hooks) }}
  {{ return({'relations': [target]}) }}
{% endmaterialization %}
