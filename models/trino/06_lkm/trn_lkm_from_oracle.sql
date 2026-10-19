{#
================================================================================
 MODEL    : trino/06_lkm/trn_lkm_from_oracle   ->  t_lkm_cust
 ODI KM   : LKM SQL to SQL (farklı teknoloji) + IKM Control Append — Trino
 NE YAPAR : Oracle'da dbt farklı veritabanından okuyamaz (sadece dblink). Trino'da model SQL'i
            başka bir catalog'dan okuyabilir:
                from oracle.edw.customer c          -- Trino oracle connector catalog'u
            odi_lkm = true -> önce odi_c_t_lkm_cust'a (Iceberg) stage edilir, IKM oradan okur.
            Testte oracle catalog'u yok: var('lkm_source') verilmezse aynı şemadan okur.
 ÇALIŞTIR : dbt run --target trino -s trn_lkm_from_oracle --vars '{lkm_source: oracle.edw.customer}'
================================================================================
@setup
CREATE TABLE t_lkm_cust (
  cust_no bigint, cust_name varchar, segment varchar, city varchar,
  email varchar, branch_cd varchar, amount bigint, status varchar)
/
@check day1
satır :: select count(*) from t_lkm_cust => 4
@check day2
satır :: select count(*) from t_lkm_cust => 8
C$ silindi :: select count(*) from information_schema.tables where table_schema = current_schema and table_name = 'odi_c_t_lkm_cust' => 0
================================================================================
#}
{{ config(
    materialized = 'odi_control_append',
    alias        = 't_lkm_cust',
    odi_lkm      = true,
    odi_truncate = true
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status
  from {{ var('lkm_source', source('src_trn', 'src_customer')) }}
