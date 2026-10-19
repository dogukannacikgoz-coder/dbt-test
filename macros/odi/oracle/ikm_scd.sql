{#
  ============================================================================
   IKM Oracle Slowly Changing Dimension   →   materialized='odi_scd'

   ODI'da attribute'lara verilen "SCD Behavior" burada odi_scd config'idir:
     Surrogate Key            → surrogate_key (+ surrogate_expr: "SEQ.NEXTVAL";
                                 boşsa identity/trigger varsayılır, insert'e konmaz)
     Natural Key              → natural_key
     Overwrite on Change      → overwrite_on_change   (SCD1)
     Add Row on Change        → add_row_on_change     (SCD2; boşsa kalan tüm kolonlar)
     Current Record Flag      → current_flag (+ current_value / history_value)
     Starting Timestamp       → start_date   (+ start_expr, default SYSDATE)
     Ending Timestamp         → end_date     (+ end_expr_on_close, max_end_date)
     (ek) close_missing: true → kaynakta artık gelmeyen NK'nın current kaydı kapatılır
                                (end_expr_missing, default SYSDATE). Sadece full extract'ta!

   Model SQL'i SK/flag/tarih kolonlarını DÖNDÜRMEZ — onları IKM doldurur.

   Step'ler:
     I$ flow → CKM (default unique: natural key) → Create/Truncate target
     → Flag rows for update (SCD2 kolonları aynı = 'U')
     → Flag useless rows   (SCD1 kolonları da aynı = 'N')
     → Update existing rows (SCD1 overwrite)
     → Historize old rows   (flag=history, end_date=close)
     → Insert new rows / new versions (statement 'main')
     → Commit → Drop I$
  ============================================================================
#}

{% materialization odi_scd, adapter='oracle' %}
  {%- set ctx    = odi_ctx('IKM Oracle Slowly Changing Dimension') -%}
  {%- set target = this.incorporate(type='table') -%}
  {%- set scd    = config.get('odi_scd') -%}
  {%- if not scd -%}
    {%- do exceptions.raise_compiler_error(this ~ ': odi_scd config zorunlu.') -%}
  {%- endif -%}
  {%- if (config.get('odi_flow_mode', 'table') | lower) == 'none' -%}
    {%- do exceptions.raise_compiler_error(this ~ ": odi_scd I$ tablosu gerektirir (odi_flow_mode 'none' olamaz).") -%}
  {%- endif -%}

  {%- set sk        = (scd.get('surrogate_key') or '') | upper -%}
  {%- set sk_expr   = scd.get('surrogate_expr') -%}
  {%- set nk        = odi_as_list(scd.get('natural_key')) -%}
  {%- set ow        = odi_as_list(scd.get('overwrite_on_change', [])) -%}
  {%- set flag      = (scd.get('current_flag') or '') | upper -%}
  {%- set cur_val   = scd.get('current_value', '1') | string -%}
  {%- set hist_val  = scd.get('history_value', '0') | string -%}
  {%- set sd        = (scd.get('start_date') or '') | upper -%}
  {%- set ed        = (scd.get('end_date') or '') | upper -%}
  {%- set start_ex  = scd.get('start_expr', 'SYSDATE') -%}
  {%- set close_ex  = scd.get('end_expr_on_close', start_ex) -%}
  {%- set max_dt    = scd.get('max_end_date', "TO_DATE('2400-01-01','YYYY-MM-DD')") -%}
  {%- set ow_all    = scd.get('overwrite_all_versions', false) -%}

  {%- if nk | length == 0 -%}
    {%- do exceptions.raise_compiler_error(this ~ ': odi_scd.natural_key zorunlu.') -%}
  {%- endif -%}
  {%- if not flag and not ed -%}
    {%- do exceptions.raise_compiler_error(this ~ ': current_flag veya end_date en az biri verilmeli (current kaydı bulmak için).') -%}
  {%- endif -%}

  {%- set flow = odi_work_relation('I$_', 'odi_flow_table') -%}

  {{ odi_hooks_pre(ctx) }}

  {%- set lkm     = odi_lkm_stage(ctx, sql) -%}
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

  {#- current kayıt koşulu -#}
  {%- set cur_cond -%}
    {%- if flag -%}t.{{ flag }} = {{ cur_val }}{%- else -%}t.{{ ed }} = {{ max_dt }}{%- endif -%}
  {%- endset -%}

  {#- ---- Flow + CKM ---- -#}
  {%- do odi_load_work_table(ctx, flow, src_sql, cols, 'I$ (flow)', with_ind_update=true) -%}
  {%- set e_rel = odi_ckm_flow_control(ctx, flow, cols, nk) -%}

  {#- ---- Target (yoksa ve izin varsa SCD kolonlarıyla açılır) ---- -#}
  {%- set extra -%}
    {%- if sk %}cast(null as number) as {{ sk }}, {% endif -%}
    {%- if flag %}{{ cur_val }} as {{ flag }}, {% endif -%}
    {%- if sd %}cast(null as date) as {{ sd }}, {% endif -%}
    {%- if ed %}cast(null as date) as {{ ed }}, {% endif -%}
  {%- endset -%}
  {%- do odi_prepare_target(ctx, target, flow, cols, extra) -%}

  {#- ---- Flag rows for update: NK var ve SCD2 kolonları aynı → 'U' ---- -#}
  {%- set q -%}
update {{ flow }} f
   set f.IND_UPDATE = 'U'
 where exists ( select 1 from {{ target }} t
                 where {{ odi_key_join(nk) }}
                   and {{ cur_cond }}
                   and {{ odi_all_equal(ar) }} )
  {%- endset -%}
  {%- do odi_exec(ctx, 'Flag rows for update', q) -%}

  {#- ---- Flag useless rows: SCD1 kolonları da aynı → 'N' ---- -#}
  {%- set q -%}
update {{ flow }} f
   set f.IND_UPDATE = 'N'
 where f.IND_UPDATE = 'U'
   and exists ( select 1 from {{ target }} t
                 where {{ odi_key_join(nk) }}
                   and {{ cur_cond }}
                   and {{ odi_all_equal(ow) }} )
  {%- endset -%}
  {%- do odi_exec(ctx, 'Flag useless rows', q) -%}

  {#- ---- Update existing rows (SCD1 overwrite) ---- -#}
  {%- if ow | length > 0 -%}
    {%- set q -%}
update {{ odi_hint(config.get('odi_update_hint', none)) }} {{ target }} t
   set ( {{ odi_col_list(ow) }} ) =
       ( select {{ odi_col_list(ow, 'f') }}
           from {{ flow }} f
          where {{ odi_key_join(nk) }}
            and f.IND_UPDATE = 'U' )
 where {{ odi_tuple(nk, 't') }} in ( select {{ odi_col_list(nk) }} from {{ flow }} where IND_UPDATE = 'U' )
   {%- if not ow_all %}
   and {{ cur_cond }}
   {%- endif %}
    {%- endset -%}
    {%- do odi_exec(ctx, 'Update existing rows (overwrite on change)', q) -%}
  {%- endif -%}

  {#- ---- Historize old rows (SCD2) ---- -#}
  {%- set q -%}
update {{ target }} t
   set {% if flag %}t.{{ flag }} = {{ hist_val }}{% endif %}
       {%- if flag and ed %},
       {% endif -%}
       {%- if ed %}t.{{ ed }} = ( select {{ close_ex }}
                     from {{ flow }} f
                    where {{ odi_key_join(nk) }}
                      and f.IND_UPDATE = 'I' ){% endif %}
 where {{ cur_cond }}
   and {{ odi_tuple(nk, 't') }} in ( select {{ odi_col_list(nk) }} from {{ flow }} where IND_UPDATE = 'I' )
  {%- endset -%}
  {%- do odi_exec(ctx, 'Historize old rows', q) -%}

  {#- ---- (ek) Close rows missing in source ---- -#}
  {%- if scd.get('close_missing', false) -%}
    {%- set q -%}
update {{ target }} t
   set {% if flag %}t.{{ flag }} = {{ hist_val }}{% endif %}{% if flag and ed %}, {% endif %}{% if ed %}t.{{ ed }} = {{ scd.get('end_expr_missing', 'SYSDATE') }}{% endif %}
 where {{ cur_cond }}
   and not exists ( select 1 from {{ flow }} f where {{ odi_key_join(nk) }} )
   {%- if e_rel %}
   and not exists ( select 1 from {{ e_rel }} e where e.ODI_SESS_NO = '{{ invocation_id }}' and {{ odi_key_join(nk, 't', 'e') }} )
   {%- endif %}
    {%- endset -%}
    {%- do odi_exec(ctx, 'Close rows missing in source', q) -%}
  {%- endif -%}

  {#- ---- Insert new rows / new versions ---- -#}
  {%- set ins_sk = sk and sk_expr -%}
  {%- set q -%}
insert {{ odi_hint(config.get('odi_insert_hint', 'APPEND')) }} into {{ target }}
  ( {% if ins_sk %}{{ sk }}, {% endif %}{{ odi_col_list(cols) }}
    {%- if flag %}, {{ flag }}{% endif %}{% if sd %}, {{ sd }}{% endif %}{% if ed %}, {{ ed }}{% endif %} )
select {% if ins_sk %}{{ sk_expr }}, {% endif %}{{ odi_col_list(cols, 'f') }}
    {%- if flag %}, {{ cur_val }}{% endif %}{% if sd %}, {{ start_ex }}{% endif %}{% if ed %}, {{ max_dt }}{% endif %}
  from {{ flow }} f
 where f.IND_UPDATE = 'I'
  {%- endset -%}
  {%- do odi_exec(ctx, 'Insert new rows', q, name='main') -%}
  {%- do odi_commit(ctx) -%}

  {%- set tmp = [flow] -%}
  {%- if lkm['rel'] is not none -%}{%- do tmp.append(lkm['rel']) -%}{%- endif -%}
  {%- do odi_cleanup(ctx, tmp) -%}

  {{ odi_hooks_post(ctx) }}
  {{ return({'relations': [target]}) }}
{% endmaterialization %}
