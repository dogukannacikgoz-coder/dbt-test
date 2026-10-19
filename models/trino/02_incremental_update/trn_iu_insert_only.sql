{#
================================================================================
 MODEL    : trino/02_incremental_update/trn_iu_insert_only   ->  t_iu_ins_only
 ODI KM   : IKM Incremental Update, UPDATE = false — Trino (MERGE'te WHEN MATCHED dalı yok)
 SENARYO  : Gün1 4 | Gün2 8, 1'in şehri hâlâ IST
 ÇALIŞTIR : dbt run --target trino -s trn_iu_insert_only
================================================================================
@setup
CREATE TABLE t_iu_ins_only (
  cust_no bigint, cust_name varchar, segment varchar, city varchar,
  email varchar, branch_cd varchar, amount bigint, status varchar, ins_ts timestamp(6))
/
@check day1
satır :: select count(*) from t_iu_ins_only => 4
@check day2
satır :: select count(*) from t_iu_ins_only => 8
güncellenmedi :: select city from t_iu_ins_only where cust_no = 1 => 'IST'
================================================================================
#}
{{ config(
    materialized     = 'odi_incremental_update',
    alias            = 't_iu_ins_only',
    unique_key       = 'cust_no',
    odi_update       = false,
    odi_audit_insert = {'ins_ts': 'localtimestamp'}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status
  from {{ source('src_trn', 'src_customer') }}
