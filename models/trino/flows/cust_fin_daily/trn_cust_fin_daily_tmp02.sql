{#
================================================================================
 GERÇEK AKIŞ (Trino) : cust_fin_daily — ADIM 2/3 -> t_cfd_tmp02
================================================================================
@setup
CREATE TABLE t_cfd_tmp02 (
  snapshot_date date, cust_no bigint, cust_name varchar, segment varchar,
  branch_cd varchar, txn_cnt bigint, txn_amt bigint)
/
================================================================================
#}
{{ config(materialized='odi_control_append', alias='t_cfd_tmp02', tags=['trn_cust_fin_daily'], odi_truncate=true) }}

select a.snapshot_date, a.cust_no, c.cust_name, c.segment, c.branch_cd, a.txn_cnt, a.txn_amt
  from {{ ref('trn_cust_fin_daily_tmp01') }} a
  join {{ ref('trn_iu_basic_ckm') }} c on c.cust_no = a.cust_no
