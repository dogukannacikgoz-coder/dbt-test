{#
================================================================================
 GERÇEK AKIŞ (Trino) : cust_fin_daily — ADIM 3/3 (FINAL) -> dm_cust_fin_daily
                       (partitioning = day(snapshot_date)); flow + CKM + partition'lı MERGE
 SENARYO             : Gün1 3 | Gün2 5 | Gün3 10-01 geriye dönük: 2 -> 75, 5 eklendi = 6
================================================================================
@setup
CREATE TABLE dm_cust_fin_daily (
  snapshot_date date, cust_no bigint, cust_name varchar, segment varchar,
  branch_cd varchar, txn_cnt bigint, txn_amt bigint, ins_ts timestamp(6), upd_ts timestamp(6))
WITH (partitioning = ARRAY['day(snapshot_date)'])
/
@check day1
satır :: select count(*) from dm_cust_fin_daily => 3
@check day2
satır :: select count(*) from dm_cust_fin_daily => 5
@check day3
satır :: select count(*) from dm_cust_fin_daily => 6
2'nin 10-01 tutarı :: select txn_amt from dm_cust_fin_daily where cust_no = 2 and snapshot_date = date '2026-10-01' => 75
================================================================================
#}
{{ config(
    materialized       = 'odi_merge',
    alias              = 'dm_cust_fin_daily',
    tags               = ['trn_cust_fin_daily'],
    unique_key         = ['snapshot_date', 'cust_no'],
    odi_flow_control   = true,
    odi_ckm_not_null   = ['cust_name', 'segment'],
    odi_delete_missing = true,
    odi_partition      = {'column': 'snapshot_date', 'value': 'param:load_date', 'strategy': 'none'},
    odi_audit_insert   = {'ins_ts': 'localtimestamp'},
    odi_audit_update   = {'upd_ts': 'localtimestamp'}
) }}

select snapshot_date, cust_no, cust_name, segment, branch_cd, txn_cnt, txn_amt
  from {{ ref('trn_cust_fin_daily_tmp02') }}
