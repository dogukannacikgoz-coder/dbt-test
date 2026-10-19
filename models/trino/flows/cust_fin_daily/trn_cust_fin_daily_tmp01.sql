{#
================================================================================
 GERÇEK AKIŞ (Trino) : cust_fin_daily — ADIM 1/3 -> t_cfd_tmp01
 ÇALIŞTIR            : dbt build --target trino -s tag:trn_cust_fin_daily --vars '{load_date: 2026-10-02}'
================================================================================
@setup
CREATE TABLE t_cfd_tmp01 (snapshot_date date, cust_no bigint, txn_cnt bigint, txn_amt bigint)
/
@check day1
10-01 :: select count(*) from t_cfd_tmp01 => 3
@check day2
10-02 :: select count(*) from t_cfd_tmp01 => 2
================================================================================
#}
{{ config(materialized='odi_control_append', alias='t_cfd_tmp01', tags=['trn_cust_fin_daily'], odi_truncate=true) }}

select date '{{ odi_param("load_date") }}' as snapshot_date,
       t.cust_no, count(*) as txn_cnt, sum(t.amount) as txn_amt
  from {{ source('src_trn', 'src_txn') }} t
 where t.txn_date = date '{{ odi_param("load_date") }}'
 group by t.cust_no
