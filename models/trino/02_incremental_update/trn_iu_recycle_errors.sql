{#
================================================================================
 MODEL    : trino/02_incremental_update/trn_iu_recycle_errors   ->  t_iu_recycle
 ODI KM   : IKM Incremental Update + CKM + RECYCLE_ERRORS — Trino
 SENARYO  : Gün2: 7 (B9) hata tablosuna | Gün3: B9 eklendi, recycle ile 7 ve yeni 9 girer
 ÇALIŞTIR : dbt run --target trino -s trn_iu_recycle_errors
================================================================================
@setup
CREATE TABLE t_iu_recycle (
  cust_no bigint, cust_name varchar, segment varchar, city varchar,
  email varchar, branch_cd varchar, amount bigint, status varchar)
/
@check day1
satır :: select count(*) from t_iu_recycle => 4
@check day2
7 girmedi :: select cust_no from t_iu_recycle order by 1 => [(1,), (2,), (3,), (4,), (5,)]
7 hata tablosunda :: select count(*) from odi_e_t_iu_recycle where cust_no = 7 => 1
@check day3
7 ve 9 girdi :: select cust_no from t_iu_recycle order by 1 => [(1,), (2,), (3,), (4,), (5,), (7,), (9,)]
hata tablosunda 7 kalmadı :: select count(*) from odi_e_t_iu_recycle where cust_no = 7 => 0
================================================================================
#}
{{ config(
    materialized       = 'odi_incremental_update',
    alias              = 't_iu_recycle',
    unique_key         = 'cust_no',
    odi_flow_control   = true,
    odi_recycle_errors = true,
    odi_ckm_references = {'FK_BRANCH': {'cols': ['branch_cd'], 'ref_table': 'd_branch'}}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status
  from {{ source('src_trn', 'src_customer_cdc') }}
 where op_type in ('I', 'U')
