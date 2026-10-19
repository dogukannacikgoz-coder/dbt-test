{#
================================================================================
 MODEL    : trino/01_control_append/trn_ca_truncate_insert   ->  t_ca_snapshot  (Iceberg)
 ODI KM   : IKM Control Append (TRUNCATE = true) — Trino
 NE YAPAR : DELETE FROM target (Iceberg'de tüm tabloyu silmek metadata işlemi) + INSERT INTO.
 FARK     : Oracle'da TRUNCATE + APPEND; Trino'da iki ayrı commit -> arada okuyan boş tablo görebilir.
            Okuma kesintisi kabul edilemiyorsa partition'lı tablo + strategy='delete' kullanın.
 ÇALIŞTIR : dbt run --target trino -s trn_ca_truncate_insert
================================================================================
@setup
CREATE TABLE t_ca_snapshot (
  cust_no bigint, cust_name varchar, segment varchar, city varchar,
  email varchar, branch_cd varchar, amount bigint, status varchar, load_ts timestamp(6))
/
@check day1
satır :: select count(*) from t_ca_snapshot => 4
@check day2
8 satır (hatalılar dahil) :: select count(*) from t_ca_snapshot => 8
@check day3
hâlâ 8 :: select count(*) from t_ca_snapshot => 8
================================================================================
#}
{{ config(
    materialized     = 'odi_control_append',
    alias            = 't_ca_snapshot',
    odi_truncate     = true,
    odi_audit_insert = {'load_ts': 'localtimestamp'}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status
  from {{ source('src_trn', 'src_customer') }}
