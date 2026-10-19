{#
================================================================================
 MODEL    : trino/02_incremental_update/trn_iu_cdc_delete   ->  t_iu_cdc
 ODI KM   : IKM Incremental Update + SYNC_JRN_DELETE — Trino
 NE YAPAR : WHEN MATCHED AND op_type='D' THEN DELETE ; WHEN NOT MATCHED AND op_type<>'D' THEN INSERT
 SENARYO  : Gün2: 3 silinir, 1 güncellenir, 5 ve 7 eklenir | Gün3: 9
 ÇALIŞTIR : dbt run --target trino -s trn_iu_cdc_delete
================================================================================
@setup
CREATE TABLE t_iu_cdc (
  cust_no bigint, cust_name varchar, segment varchar, city varchar,
  email varchar, branch_cd varchar, amount bigint, status varchar, upd_ts timestamp(6))
/
@check day1
müşteriler :: select cust_no from t_iu_cdc order by 1 => [(1,), (2,), (3,), (4,)]
@check day2
müşteriler :: select cust_no from t_iu_cdc order by 1 => [(1,), (2,), (4,), (5,), (7,)]
1 güncellendi :: select city from t_iu_cdc where cust_no = 1 => 'ANK'
@check day3
9 eklendi :: select cust_no from t_iu_cdc order by 1 => [(1,), (2,), (4,), (5,), (7,), (9,)]
================================================================================
#}
{{ config(
    materialized          = 'odi_incremental_update',
    alias                 = 't_iu_cdc',
    unique_key            = 'cust_no',
    odi_delete_condition  = "op_type = 'D'",
    odi_flow_only_columns = ['op_type'],
    odi_audit_update      = {'upd_ts': 'localtimestamp'}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status, op_type
  from {{ source('src_trn', 'src_customer_cdc') }}
