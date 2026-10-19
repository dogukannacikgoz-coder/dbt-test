{#
================================================================================
 MODEL    : odi/02_incremental_update/iu_gtt_no_ddl   ->  T_IU_GTT
 ODI KM   : IKM Oracle Incremental Update + CKM, work tabloları ÖNCEDEN AÇILMIŞ (DDL yok)
 NE YAPAR : T_IU ile aynı iş, ama dbt kullanıcısının CREATE TABLE yetkisi yokmuş gibi:
            I$ = PDM ile açılmış GLOBAL TEMPORARY TABLE (session'a özel, redo az),
            E$ = PDM ile açılmış kalıcı tablo. Materialization sadece delete + insert yapar.
 NE ZAMAN : Bankadaki kurulum. Klasör bazında dbt_project.yml'den de verilebilir:
              +odi_flow_mode: existing  /  +odi_work_schema: WRK  /  +odi_ckm_create_error_table: false
 SENARYO  : Her gün T_IU ile birebir aynı sonuç; step log'da hiç Create/Drop step'i yok.
 ÇALIŞTIR : dbt run -s iu_gtt_no_ddl
================================================================================
@setup
CREATE TABLE t_iu_gtt (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  ins_dt DATE, upd_dt DATE)
/
-- I$: model SQL kolonları + IND_UPDATE
CREATE GLOBAL TEMPORARY TABLE "I$_T_IU_GTT" (
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  ind_update CHAR(1)
) ON COMMIT PRESERVE ROWS
/
-- E$: 7 meta kolon + model SQL kolonları
CREATE TABLE "E$_T_IU_GTT" (
  odi_row_id VARCHAR2(64), err_type CHAR(1), err_mess VARCHAR2(250), check_date DATE,
  cons_name VARCHAR2(128), cons_type VARCHAR2(10), odi_sess_no VARCHAR2(64),
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1))
/
@check day1
satır :: select count(*) from t_iu_gtt => 4
@check day2
T_IU ile fark yok :: select count(*) from (select cust_no, city, email, status from t_iu minus select cust_no, city, email, status from t_iu_gtt) => 0
E$ (bu run) :: select count(*) from "E$_T_IU_GTT" where odi_sess_no = :sess => 3
DDL atılmadı :: select count(*) from odi_step_log where sess_no = :sess and model_name like '%.T_IU_GTT' and (step_name like 'Create%' or step_name like 'Drop%') => 0
@check day3
T_IU ile fark yok :: select count(*) from (select cust_no, city, email, status from t_iu minus select cust_no, city, email, status from t_iu_gtt) => 0
================================================================================
#}
{{ config(
    materialized               = 'odi_incremental_update',
    alias                      = 'T_IU_GTT',
    unique_key                 = 'cust_no',
    odi_flow_mode              = 'existing',
    odi_flow_table             = 'I$_' ~ var('odi_name_prefix', '') ~ 'T_IU_GTT',
    odi_error_table            = 'E$_' ~ var('odi_name_prefix', '') ~ 'T_IU_GTT',
    odi_ckm_create_error_table = false,
    odi_flow_control           = true,
    odi_ckm_not_null           = ['cust_name'],
    odi_ckm_conditions         = {'CHK_SEGMENT': "segment in ('R','C')"},
    odi_ckm_references         = {'FK_BRANCH': {'cols': ['branch_cd'], 'ref_table': var('odi_name_prefix', '') ~ 'D_BRANCH'}},
    odi_audit_insert           = {'ins_dt': 'sysdate'},
    odi_audit_update           = {'upd_dt': 'sysdate'}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status
  from {{ source('src', 'src_customer') }}
