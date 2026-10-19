{#
  ============================================================================
   CKM — Flow Control (Oracle + Trino; motor farkları dispatch ile)
   I$ (veya X$) tablosundaki hatalı satırları E$ tablosuna yazar ve flow'dan siler.
   Target'a sadece temiz satır gider.

   Opsiyonlar (model config):
     odi_flow_control: true
     odi_ckm_not_null: [COL1, COL2]
     odi_ckm_unique_key: [K1, K2]          (default: unique_key / SCD natural key)
     odi_ckm_conditions: {CHK_NAME: "AMOUNT >= 0", ...}
     odi_ckm_references: {FK_NAME: {cols: [CUST_NO], ref_table: "EDW.D_CUSTOMER", ref_cols: [CUST_NO]}}
     odi_ckm_max_errors: 0                 (aşılırsa model fail, target'a dokunulmaz)
     odi_recycle_errors: true              (önceki run'ların E$ satırlarını tekrar dene; key gerekir)
     odi_error_table: "WRK.E$_XXX"         (verilmezse <work_schema>.E$_<model>)
     odi_ckm_create_error_table: true      (E$ yoksa yarat; PDM ortamında false + önceden açın)
  ============================================================================
#}

{# ---- motor farkları ---- #}
{% macro odi_ckm_row_id(alias) %}{{ return(adapter.dispatch('odi_ckm_row_id')(alias)) }}{% endmacro %}
{% macro default__odi_ckm_row_id(alias) %}{{ return('rowidtochar(' ~ alias ~ '.rowid)') }}{% endmacro %}
{% macro trino__odi_ckm_row_id(alias) %}{{ return(alias ~ '.ODI_ROW_ID') }}{% endmacro %}

{# flow'a sonradan satır eklenirken (recycle) motorun satır id kolonu #}
{% macro odi_flow_rowid_cols() %}{{ return(adapter.dispatch('odi_flow_rowid_cols')()) }}{% endmacro %}
{% macro default__odi_flow_rowid_cols() %}{{ return({'cols': '', 'vals': ''}) }}{% endmacro %}
{% macro trino__odi_flow_rowid_cols() %}{{ return({'cols': ', ODI_ROW_ID', 'vals': ', cast(uuid() as varchar)'}) }}{% endmacro %}

{% macro odi_ckm_create_error_sql(e_rel, flow_rel, cols) %}{{ return(adapter.dispatch('odi_ckm_create_error_sql')(e_rel, flow_rel, cols)) }}{% endmacro %}
{% macro default__odi_ckm_create_error_sql(e_rel, flow_rel, cols) %}
create table {{ e_rel }} as
select cast(null as varchar2(64))   as ODI_ROW_ID,
       cast(null as char(1))        as ERR_TYPE,
       cast(null as varchar2(250))  as ERR_MESS,
       cast(null as date)           as CHECK_DATE,
       cast(null as varchar2(128))  as CONS_NAME,
       cast(null as varchar2(10))   as CONS_TYPE,
       cast(null as varchar2(64))   as ODI_SESS_NO,
       {{ odi_col_list(cols, 'f') }}
  from {{ flow_rel }} f
 where 1 = 0
{% endmacro %}
{% macro trino__odi_ckm_create_error_sql(e_rel, flow_rel, cols) %}
create table {{ e_rel }}{{ odi_trn_comment_clause() }} as
select cast(null as varchar)       as ODI_ROW_ID,
       cast(null as varchar)       as ERR_TYPE,
       cast(null as varchar)       as ERR_MESS,
       cast(null as timestamp(6))  as CHECK_DATE,
       cast(null as varchar)       as CONS_NAME,
       cast(null as varchar)       as CONS_TYPE,
       cast(null as varchar)       as ODI_SESS_NO,
       {{ odi_col_list(cols, 'f') }}
  from {{ flow_rel }} f
 where 1 = 0
{% endmacro %}

{% macro odi_ckm_delete_errors_sql(flow_rel, e_rel, sess) %}{{ return(adapter.dispatch('odi_ckm_delete_errors_sql')(flow_rel, e_rel, sess)) }}{% endmacro %}
{% macro default__odi_ckm_delete_errors_sql(flow_rel, e_rel, sess) %}
delete from {{ flow_rel }}
 where rowid in ( select chartorowid(ODI_ROW_ID)
                    from {{ e_rel }}
                   where ODI_SESS_NO = '{{ sess }}' )
{% endmacro %}
{% macro trino__odi_ckm_delete_errors_sql(flow_rel, e_rel, sess) %}
delete from {{ flow_rel }}
 where ODI_ROW_ID in ( select ODI_ROW_ID
                         from {{ e_rel }}
                        where ODI_SESS_NO = '{{ sess }}' )
{% endmacro %}

{% macro odi_ckm_error_relation() %}
  {{ return(odi_work_relation('E$_', 'odi_error_table')) }}
{% endmacro %}

{% macro odi_ckm_flow_control(ctx, flow_rel, cols, default_uk=[], has_ind=true) %}
  {%- if not config.get('odi_flow_control', false) -%}
    {{ return(none) }}
  {%- endif -%}

  {%- set e_rel  = odi_ckm_error_relation() -%}
  {%- set nn     = odi_as_list(config.get('odi_ckm_not_null', [])) -%}
  {%- set uk     = odi_as_list(config.get('odi_ckm_unique_key', default_uk)) -%}
  {%- set conds  = odi_upper_dict(config.get('odi_ckm_conditions', {})) -%}
  {%- set refs   = odi_upper_dict(config.get('odi_ckm_references', {})) -%}
  {%- set sess   = invocation_id -%}
  {%- set meta   = 'ODI_ROW_ID, ERR_TYPE, ERR_MESS, CHECK_DATE, CONS_NAME, CONS_TYPE, ODI_SESS_NO' -%}

  {#- 1) E$ tablosu -#}
  {%- if not odi_table_exists(e_rel) -%}
    {%- if config.get('odi_ckm_create_error_table', true) -%}
      {%- set ce = odi_ckm_create_error_sql(e_rel, flow_rel, cols) -%}
      {%- do odi_exec(ctx, 'Create error table', ce, auto_begin=False) -%}
      {%- do odi_mark_work_table(ctx, e_rel, 'E$ (error)') -%}
    {%- else -%}
      {%- do exceptions.raise_compiler_error('Error tablosu ' ~ e_rel ~ ' yok (odi_ckm_create_error_table=false).') -%}
    {%- endif -%}
  {%- endif -%}

  {#- 2) RECYCLE_ERRORS: önceki run'ların hatalı satırlarını flow'a geri koy -#}
  {%- if config.get('odi_recycle_errors', false) -%}
    {%- if uk | length == 0 -%}
      {%- do exceptions.raise_compiler_error(this ~ ': odi_recycle_errors için unique_key / odi_ckm_unique_key gerekli.') -%}
    {%- endif -%}
    {%- set q -%}
{%- set rx = odi_flow_rowid_cols() %}
insert into {{ flow_rel }} ( {{ odi_col_list(cols) }}{{ ', IND_UPDATE' if has_ind }}{{ rx['cols'] }} )
select {{ odi_col_list(cols) }}{{ ", 'I'" if has_ind }}{{ rx['vals'] }}
  from ( select e.*,
                row_number() over (partition by {{ odi_col_list(uk, 'e') }}
                                   order by e.CHECK_DATE desc, e.ODI_ROW_ID) as ODI_RN
           from {{ e_rel }} e
          where e.ODI_SESS_NO <> '{{ sess }}'
            and not exists ( select 1 from {{ flow_rel }} f where {{ odi_key_join(uk, 'f', 'e') }} ) )
 where ODI_RN = 1
    {%- endset -%}
    {%- do odi_exec(ctx, 'Recycle previous errors into flow', q) -%}
    {%- set q -%}
delete from {{ e_rel }} e
 where e.ODI_SESS_NO <> '{{ sess }}'
   and exists ( select 1 from {{ flow_rel }} f where {{ odi_key_join(uk, 'f', 'e') }} )
    {%- endset -%}
    {%- do odi_exec(ctx, 'Remove recycled rows from error table', q) -%}
  {%- endif -%}

  {%- set ins_head = 'insert into ' ~ e_rel ~ ' (' ~ meta ~ ', ' ~ odi_col_list(cols) ~ ')' -%}

  {#- 3) NOT NULL -#}
  {%- for c in nn -%}
    {%- set q -%}
{{ ins_head }}
select {{ odi_ckm_row_id('f') }}, 'F', 'Column {{ c }} cannot be null', {{ odi_now() }},
       '{{ ("NN_" ~ c)[:128] }}', 'NN', '{{ sess }}', {{ odi_col_list(cols, 'f') }}
  from {{ flow_rel }} f
 where f.{{ c }} is null
    {%- endset -%}
    {%- do odi_exec(ctx, 'Check not null ' ~ c, q) -%}
  {%- endfor -%}

  {#- 4) PK / AK tekillik -#}
  {%- if uk | length > 0 -%}
    {%- set q -%}
{{ ins_head }}
select {{ odi_ckm_row_id('f') }}, 'F', 'Duplicate key ({{ uk | join(", ") }})', {{ odi_now() }},
       '{{ ("PK_" ~ this.identifier | upper)[:128] }}', 'PK', '{{ sess }}', {{ odi_col_list(cols, 'f') }}
  from {{ flow_rel }} f
 where exists (
         select 1
           from ( select {{ odi_col_list(uk) }}
                    from {{ flow_rel }}
                   group by {{ odi_col_list(uk) }}
                  having count(*) > 1 ) d
          where {{ odi_key_join(uk, 'd', 'f') }} )
    {%- endset -%}
    {%- do odi_exec(ctx, 'Check unique key', q) -%}
  {%- endif -%}

  {#- 5) Condition (CK) -#}
  {%- for name, cond in conds.items() -%}
    {%- set q -%}
{{ ins_head }}
select {{ odi_ckm_row_id('f') }}, 'F', 'Condition {{ name }} violated', {{ odi_now() }},
       '{{ name }}', 'CK', '{{ sess }}', {{ odi_col_list(cols, 'f') }}
  from {{ flow_rel }} f
 where not ( {{ cond }} )
    {%- endset -%}
    {%- do odi_exec(ctx, 'Check condition ' ~ name, q) -%}
  {%- endfor -%}

  {#- 6) Referans (FK) -#}
  {%- for name, r in refs.items() -%}
    {%- set fc = odi_as_list(r['cols']) -%}
    {%- set rc = odi_as_list(r.get('ref_cols', r['cols'])) -%}
    {%- set q -%}
{{ ins_head }}
select {{ odi_ckm_row_id('f') }}, 'F', 'Reference {{ name }} not found in {{ r["ref_table"] }}', {{ odi_now() }},
       '{{ name }}', 'FK', '{{ sess }}', {{ odi_col_list(cols, 'f') }}
  from {{ flow_rel }} f
 where {% for c in fc %}f.{{ c }} is not null{{ ' and ' if not loop.last }}{% endfor %}
   and not exists (
         select 1 from {{ r['ref_table'] }} rt
          where {% for i in range(fc | length) %}rt.{{ rc[i] }} = f.{{ fc[i] }}{{ ' and ' if not loop.last }}{% endfor %} )
    {%- endset -%}
    {%- do odi_exec(ctx, 'Check reference ' ~ name, q) -%}
  {%- endfor -%}

  {#- 7) Hatalıları flow'dan sil -#}
  {%- set d = odi_ckm_delete_errors_sql(flow_rel, e_rel, sess) -%}
  {%- do odi_exec(ctx, 'Delete errors from flow table', d) -%}
  {%- do odi_commit(ctx) -%}

  {#- 8) Hata sayısı / threshold -#}
  {% call statement('odi_err_cnt', fetch_result=True) %}
    select count(distinct ODI_ROW_ID) from {{ e_rel }} where ODI_SESS_NO = '{{ sess }}'
  {% endcall %}
  {%- set errs = load_result('odi_err_cnt')['data'][0][0] | int -%}
  {%- do log('      -> CKM: ' ~ errs ~ ' hatalı satır ' ~ e_rel ~ ' tablosuna yazıldı', info=True) -%}
  {%- set max_err = config.get('odi_ckm_max_errors', none) -%}
  {%- if max_err is not none and errs > max_err | int -%}
    {%- do exceptions.raise_compiler_error('CKM: hata sayısı (' ~ errs ~ ') odi_ckm_max_errors (' ~ max_err ~ ') değerini aştı. Detay: ' ~ e_rel ~ " where ODI_SESS_NO='" ~ sess ~ "'") -%}
  {%- endif -%}
  {{ return(e_rel) }}
{% endmacro %}
