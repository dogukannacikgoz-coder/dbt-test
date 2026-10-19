{#
================================================================================
 MODEL    : trino/04_scd/trn_scd_close_missing   ->  t_scd_snap
 ODI KM   : IKM Slowly Changing Dimension + close_missing — Trino
 SENARYO  : Gün2: 1 yeni versiyon, 4 kapandı, 5 yeni -> 6 satır / 4 current
 ÇALIŞTIR : dbt run --target trino -s trn_scd_close_missing
================================================================================
@setup
CREATE TABLE t_scd_snap (
  cust_sk bigint, cust_no bigint, cust_name varchar, city varchar, curr_flag integer)
/
@check day1
toplam / current :: select count(*), sum(curr_flag) from t_scd_snap => [(4, 4)]
@check day2
toplam / current :: select count(*), sum(curr_flag) from t_scd_snap => [(6, 4)]
4 kapandı :: select curr_flag from t_scd_snap where cust_no = 4 => 0
================================================================================
#}
{{ config(
    materialized = 'odi_scd',
    alias        = 't_scd_snap',
    odi_scd = {
      'surrogate_key':       'cust_sk',
      'natural_key':         ['cust_no'],
      'overwrite_on_change': ['cust_name'],
      'add_row_on_change':   ['city'],
      'current_flag':        'curr_flag',
      'close_missing':       true
    }
) }}

select cust_no, cust_name, city
  from {{ source('src_trn', 'src_customer_snap') }}
