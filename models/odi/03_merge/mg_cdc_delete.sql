{#
================================================================================
 MODEL    : odi/03_merge/mg_cdc_delete   ->  T_MG_CDC
 ODI KM   : IKM Oracle Incremental Update (MERGE) + SYNC_JRN_DELETE karşılığı
 NE YAPAR : CDC kaynağı tek MERGE ile uygulanır:
              OP_TYPE='D' + target'ta var   -> silinir (MERGE ... DELETE WHERE)
              OP_TYPE='D' + target'ta yok   -> insert EDİLMEZ (not matched dalında filtre)
              diğerleri                     -> normal upsert
 NE ZAMAN : CDC beslemesi, I$ istemiyorsanız. iu_cdc_delete ile aynı sonuç, tek statement.
 SENARYO  : Gün2: 3 silinir, 1 güncellenir, 5 ve 7 eklenir | Gün3: 9 eklenir
 ÇALIŞTIR : dbt run -s mg_cdc_delete
================================================================================
@setup
CREATE TABLE t_mg_cdc (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1), upd_dt DATE)
/
@check day1
müşteriler :: select cust_no from t_mg_cdc order by 1 => [(1,), (2,), (3,), (4,)]
@check day2
3 silindi :: select cust_no from t_mg_cdc order by 1 => [(1,), (2,), (4,), (5,), (7,)]
@check day3
9 eklendi :: select cust_no from t_mg_cdc order by 1 => [(1,), (2,), (4,), (5,), (7,), (9,)]
================================================================================
#}
{{ config(
    materialized          = 'odi_merge',
    alias                 = 'T_MG_CDC',
    unique_key            = 'cust_no',
    odi_flow_mode         = 'none',
    odi_delete_condition  = "op_type = 'D'",
    odi_flow_only_columns = ['op_type'],
    odi_audit_update      = {'upd_dt': 'sysdate'}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status, op_type
  from {{ source('src', 'src_customer_cdc') }}
