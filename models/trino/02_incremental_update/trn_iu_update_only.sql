{#
================================================================================
 MODEL    : trino/02_incremental_update/trn_iu_update_only   ->  t_iu_upd_only
 ODI KM   : IKM Incremental Update, INSERT = false — Trino (MERGE'te WHEN NOT MATCHED dalı yok)
 SENARYO  : target'ta 1,2,3 eski değerlerle; Gün1 üçü güncellenir, yeni eklenmez
 ÇALIŞTIR : dbt run --target trino -s trn_iu_update_only
================================================================================
@setup
CREATE TABLE t_iu_upd_only (
  cust_no bigint, cust_name varchar, segment varchar, city varchar,
  email varchar, branch_cd varchar, amount bigint, status varchar, upd_ts timestamp(6))
/
INSERT INTO t_iu_upd_only (cust_no, cust_name, city) VALUES (1, 'OLD', 'OLD'), (2, 'OLD', 'OLD'), (3, 'OLD', 'OLD')
/
@check day1
hâlâ 3 :: select count(*) from t_iu_upd_only => 3
güncellendi :: select cust_name from t_iu_upd_only where cust_no = 1 => 'Ali'
@check day2
hâlâ 3 :: select count(*) from t_iu_upd_only => 3
1'in şehri :: select city from t_iu_upd_only where cust_no = 1 => 'ANK'
================================================================================
#}
{{ config(
    materialized     = 'odi_incremental_update',
    alias            = 't_iu_upd_only',
    unique_key       = 'cust_no',
    odi_insert       = false,
    odi_audit_update = {'upd_ts': 'localtimestamp'}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status
  from {{ source('src_trn', 'src_customer') }}
