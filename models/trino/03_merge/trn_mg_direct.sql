{#
================================================================================
 MODEL    : trino/03_merge/trn_mg_direct   ->  t_mg_direct
 ODI KM   : IKM Incremental Update (MERGE), flow tablosu yok — Trino
 NE YAPAR : Model SQL'inden doğrudan tek MERGE. Lake'te varsayılan upsert.
 SENARYO  : Gün2: 1,2,4 update | 5-8 insert | Gün3: 0 satır
 ÇALIŞTIR : dbt run --target trino -s trn_mg_direct
================================================================================
@setup
CREATE TABLE t_mg_direct (
  cust_no bigint, cust_name varchar, segment varchar, city varchar,
  email varchar, branch_cd varchar, amount bigint, status varchar,
  ins_ts timestamp(6), upd_ts timestamp(6))
/
@check day1
satır :: select count(*) from t_mg_direct => 4
@check day2
satır :: select count(*) from t_mg_direct => 8
güncellenenler :: select cust_no from t_mg_direct where upd_ts is not null order by 1 => [(1,), (2,), (4,)]
@check day3
değişiklik yok :: select sum(rows_affected) from odi_step_log where sess_no = :sess and model_name like '%.t_mg_direct' and step_name = 'Merge rows' => 0
================================================================================
#}
{{ config(
    materialized     = 'odi_merge',
    alias            = 't_mg_direct',
    unique_key       = 'cust_no',
    odi_flow_mode    = 'none',
    odi_audit_insert = {'ins_ts': 'localtimestamp'},
    odi_audit_update = {'upd_ts': 'localtimestamp'}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status
  from {{ source('src_trn', 'src_customer') }}
