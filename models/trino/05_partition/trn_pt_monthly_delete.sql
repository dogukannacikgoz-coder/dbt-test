{#
================================================================================
 MODEL    : trino/05_partition/trn_pt_monthly_delete   ->  t_txn_monthly  (partitioning = month(txn_date))
 ODI KM   : IKM Control Append + aylık dönem yenileme (MTD) — Trino
 SENARYO  : Ekim: Gün1 4 | Gün2 5 | Gün3 6
 ÇALIŞTIR : dbt run --target trino -s trn_pt_monthly_delete --vars '{load_date: 2026-10-02}'
================================================================================
@setup
CREATE TABLE t_txn_monthly (txn_id bigint, cust_no bigint, txn_date date, amount bigint)
WITH (partitioning = ARRAY['month(txn_date)'])
/
@check day1
Ekim :: select count(*) from t_txn_monthly => 4
@check day2
Ekim :: select count(*) from t_txn_monthly => 5
@check day3
Ekim :: select count(*) from t_txn_monthly => 6
================================================================================
#}
{{ config(
    materialized  = 'odi_control_append',
    alias         = 't_txn_monthly',
    odi_partition = {'column': 'txn_date', 'value': 'param:load_date', 'granularity': 'month', 'strategy': 'delete'}
) }}

select txn_id, cust_no, txn_date, amount
  from {{ source('src_trn', 'src_txn') }}
 where {{ odi_partition_filter('txn_date') }}
