{#
================================================================================
 MODEL    : trino/03_merge/trn_mg_flow_ckm   ->  t_mg_flow
 ODI KM   : IKM Incremental Update (MERGE) + flow + CKM + unique temp names — Trino
 NE YAPAR : Flow adı odi_i_t_mg_flow_<6 hane run id> olur; paralel run'lar çakışmaz.
 SENARYO  : Gün2: 6 (NN) ve 8 (CK) hata tablosuna, 7 girer
 ÇALIŞTIR : dbt run --target trino -s trn_mg_flow_ckm
================================================================================
@setup
CREATE TABLE t_mg_flow (
  cust_no bigint, cust_name varchar, segment varchar, city varchar,
  email varchar, branch_cd varchar, amount bigint, status varchar)
/
@check day2
müşteriler :: select cust_no from t_mg_flow order by 1 => [(1,), (2,), (3,), (4,), (5,), (7,)]
hatalar :: select cust_no from odi_e_t_mg_flow where odi_sess_no = :sess order by 1 => [(6,), (8,)]
flow artığı yok :: select count(*) from information_schema.tables where table_schema = current_schema and table_name like 'odi_i_t_mg_flow%' => 0
================================================================================
#}
{{ config(
    materialized          = 'odi_merge',
    alias                 = 't_mg_flow',
    unique_key            = 'cust_no',
    odi_unique_temp_names = true,
    odi_flow_control      = true,
    odi_ckm_not_null      = ['cust_name'],
    odi_ckm_conditions    = {'CHK_SEGMENT': "segment in ('R','C')"}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status
  from {{ source('src_trn', 'src_customer') }}
