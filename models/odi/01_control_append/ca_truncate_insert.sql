{#
================================================================================
 MODEL    : odi/01_control_append/ca_truncate_insert   ->  T_CA_SNAPSHOT
 ODI KM   : IKM Oracle Control Append  (TRUNCATE = true, FLOW_CONTROL = false)
 NE YAPAR : Her run'da target'ı boşaltır, model SQL'inin sonucunu INSERT /*+ APPEND */
            ile yazar. Karşılaştırma yok, kontrol yok, en hızlı yöntem.
 NE ZAMAN : Staging / ODS kopyası, "bugün kaynakta ne varsa o" tabloları.
 SENARYO  : Gün 2'de hatalı kayıtlar (6,7,8) dahil 8 satırın hepsi girer, çünkü kontrol yok.
 ÇALIŞTIR : dbt run -s ca_truncate_insert
================================================================================
@setup
CREATE TABLE t_ca_snapshot (
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  load_dt DATE)
/
@check day1
satır sayısı :: select count(*) from t_ca_snapshot => 4
load_dt dolu :: select count(*) from t_ca_snapshot where load_dt is null => 0
@check day2
truncate + 8 satır (hatalılar dahil) :: select count(*) from t_ca_snapshot => 8
@check day3
hâlâ 8 (her run baştan) :: select count(*) from t_ca_snapshot => 8
================================================================================
#}
{{ config(
    materialized     = 'odi_control_append',
    alias            = 'T_CA_SNAPSHOT',
    odi_truncate     = true,
    odi_audit_insert = {'load_dt': 'sysdate'}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status
  from {{ source('src', 'src_customer') }}
