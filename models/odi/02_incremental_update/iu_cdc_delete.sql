{#
================================================================================
 MODEL    : odi/02_incremental_update/iu_cdc_delete   ->  T_IU_CDC
 ODI KM   : IKM Oracle Incremental Update + SYNC_JRN_DELETE karşılığı
 NE YAPAR : Kaynak sadece değişenleri OP_TYPE (I/U/D) ile gönderir (CDC / journal).
            odi_delete_condition = "op_type = 'D'" -> bu satırlar I$'ta 'D' flag'lenir,
            target'tan silinir ve insert edilmez.
            odi_flow_only_columns = ['op_type'] -> OP_TYPE flow'da var, target'a yazılmaz.
 NE ZAMAN : GoldenGate / Debezium / journal tablosundan beslenen tablolar.
            Soft delete isterseniz: odi_soft_delete = {'column': 'IS_DELETED', 'value': "'Y'"}
 SENARYO  : Gün2: 1 güncellenir (ANK), 3 silinir, 5 ve 7 eklenir | Gün3: 9 eklenir
 ÇALIŞTIR : dbt run -s iu_cdc_delete
================================================================================
@setup
CREATE TABLE t_iu_cdc (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1), upd_dt DATE)
/
@check day1
müşteriler :: select cust_no from t_iu_cdc order by 1 => [(1,), (2,), (3,), (4,)]
@check day2
3 silindi, 5 ve 7 eklendi :: select cust_no from t_iu_cdc order by 1 => [(1,), (2,), (4,), (5,), (7,)]
1 güncellendi :: select city from t_iu_cdc where cust_no = 1 => 'ANK'
@check day3
9 eklendi :: select cust_no from t_iu_cdc order by 1 => [(1,), (2,), (4,), (5,), (7,), (9,)]
================================================================================
#}
{{ config(
    materialized          = 'odi_incremental_update',
    alias                 = 'T_IU_CDC',
    unique_key            = 'cust_no',
    odi_delete_condition  = "op_type = 'D'",
    odi_flow_only_columns = ['op_type'],
    odi_audit_update      = {'upd_dt': 'sysdate'}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status, op_type
  from {{ source('src', 'src_customer_cdc') }}
