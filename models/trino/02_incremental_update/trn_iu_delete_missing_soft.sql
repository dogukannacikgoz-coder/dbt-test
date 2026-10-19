{#
================================================================================
 MODEL    : trino/02_incremental_update/trn_iu_delete_missing_soft   ->  t_iu_soft
 ODI KM   : IKM Incremental Update + kaynakta yoksa soft delete — Trino
 NE YAPAR : Upsert MERGE'ünden sonra ikinci bir MERGE: target LEFT JOIN flow anti-join
            ile kaynakta olmayan key'ler bulunur, is_deleted='Y' yapılır.
 DİKKAT   : Sadece full extract.
 SENARYO  : Gün2: 4 soft delete, 5 eklendi
 ÇALIŞTIR : dbt run --target trino -s trn_iu_delete_missing_soft
================================================================================
@setup
CREATE TABLE t_iu_soft (
  cust_no bigint, cust_name varchar, segment varchar, city varchar,
  email varchar, branch_cd varchar, amount bigint, status varchar,
  is_deleted varchar, upd_ts timestamp(6))
/
@check day1
hepsi aktif :: select count(*) from t_iu_soft where is_deleted = 'N' => 4
@check day2
satır :: select count(*) from t_iu_soft => 5
4 soft delete :: select cust_no from t_iu_soft where is_deleted = 'Y' => 4
@check day3
hâlâ sadece 4 :: select cust_no from t_iu_soft where is_deleted = 'Y' => 4
================================================================================
#}
{{ config(
    materialized       = 'odi_incremental_update',
    alias              = 't_iu_soft',
    unique_key         = 'cust_no',
    odi_delete_missing = true,
    odi_soft_delete    = {'column': 'is_deleted', 'value': "'Y'"},
    odi_audit_update   = {'upd_ts': 'localtimestamp'}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status,
       'N' as is_deleted
  from {{ source('src_trn', 'src_customer_snap') }}
