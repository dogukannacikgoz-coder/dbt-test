{#
================================================================================
 MODEL    : trino/03_merge/trn_mg_delete_missing   ->  t_mg_snap
 ODI KM   : IKM Incremental Update (MERGE) + kaynakta yoksa hard delete — Trino
 SENARYO  : Gün2: 4 silindi, 5 eklendi
 ÇALIŞTIR : dbt run --target trino -s trn_mg_delete_missing
================================================================================
@setup
CREATE TABLE t_mg_snap (
  cust_no bigint, cust_name varchar, segment varchar, city varchar,
  email varchar, branch_cd varchar, amount bigint, status varchar)
/
@check day1
müşteriler :: select cust_no from t_mg_snap order by 1 => [(1,), (2,), (3,), (4,)]
@check day2
müşteriler :: select cust_no from t_mg_snap order by 1 => [(1,), (2,), (3,), (5,)]
================================================================================
#}
{{ config(
    materialized       = 'odi_merge',
    alias              = 't_mg_snap',
    unique_key         = 'cust_no',
    odi_flow_mode      = 'none',
    odi_delete_missing = true
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status
  from {{ source('src_trn', 'src_customer_snap') }}
