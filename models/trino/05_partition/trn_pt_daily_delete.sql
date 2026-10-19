{#
================================================================================
 MODEL    : trino/05_partition/trn_pt_daily_delete   ->  t_txn_daily  (partitioning = day(txn_date))
 ODI KM   : IKM Control Append + dönem yenileme — Trino
 NE YAPAR : DELETE ... WHERE txn_date dönemi -> INSERT. Iceberg tablosu day(txn_date) ile
            partition'lı olduğu için DELETE tüm data dosyalarını düşüren metadata işlemidir.
            Partition'ı önceden açmak gerekmez (hidden partitioning). Exchange yok.
 SENARYO  : Gün1 3 | Gün2 5 | Gün3 10-01 geriye dönük -> 6, 102 = 75
 ÇALIŞTIR : dbt run --target trino -s trn_pt_daily_delete --vars '{load_date: 2026-10-01}'
================================================================================
@setup
CREATE TABLE t_txn_daily (txn_id bigint, cust_no bigint, txn_date date, amount bigint, load_ts timestamp(6))
WITH (partitioning = ARRAY['day(txn_date)'])
/
@check day1
10-01 :: select count(*) from t_txn_daily where txn_date = date '2026-10-01' => 3
@check day2
toplam :: select count(*) from t_txn_daily => 5
@check day3
toplam :: select count(*) from t_txn_daily => 6
102 düzeldi :: select amount from t_txn_daily where txn_id = 102 => 75
10-02 dokunulmadı :: select count(*) from t_txn_daily where txn_date = date '2026-10-02' => 2
================================================================================
#}
{{ config(
    materialized     = 'odi_control_append',
    alias            = 't_txn_daily',
    odi_partition    = {'column': 'txn_date', 'value': 'param:load_date', 'granularity': 'day', 'strategy': 'delete'},
    odi_audit_insert = {'load_ts': 'localtimestamp'}
) }}

select txn_id, cust_no, txn_date, amount
  from {{ source('src_trn', 'src_txn') }}
 where {{ odi_partition_filter('txn_date') }}
