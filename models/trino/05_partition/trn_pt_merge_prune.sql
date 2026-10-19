{#
================================================================================
 MODEL    : trino/05_partition/trn_pt_merge_prune   ->  t_txn_merge_part
 ODI KM   : IKM Incremental Update (MERGE) + partition pruning + partition içi delete missing — Trino
 NE YAPAR : MERGE'ün ON koşuluna dönem aralığı eklenir, Iceberg sadece o günün dosyalarını okur.
 SENARYO  : Gün3 10-01: 102 update, 104 insert
 ÇALIŞTIR : dbt run --target trino -s trn_pt_merge_prune --vars '{load_date: 2026-10-01}'
================================================================================
@setup
CREATE TABLE t_txn_merge_part (txn_id bigint, cust_no bigint, txn_date date, amount bigint, upd_ts timestamp(6))
WITH (partitioning = ARRAY['day(txn_date)'])
/
@check day1
satır :: select count(*) from t_txn_merge_part => 3
@check day2
satır :: select count(*) from t_txn_merge_part => 5
@check day3
satır :: select count(*) from t_txn_merge_part => 6
sadece 102 güncellendi :: select txn_id from t_txn_merge_part where upd_ts is not null => 102
================================================================================
#}
{{ config(
    materialized       = 'odi_merge',
    alias              = 't_txn_merge_part',
    unique_key         = 'txn_id',
    odi_flow_mode      = 'none',
    odi_delete_missing = true,
    odi_partition      = {'column': 'txn_date', 'value': 'param:load_date', 'strategy': 'none'},
    odi_audit_update   = {'upd_ts': 'localtimestamp'}
) }}

select txn_id, cust_no, txn_date, amount
  from {{ source('src_trn', 'src_txn') }}
 where {{ odi_partition_filter('txn_date') }}
