{#
================================================================================
 MODEL    : odi/01_control_append/ca_append_ckm   ->  T_CA_APPEND_CLEAN
 ODI KM   : IKM Oracle Control Append (TRUNCATE = false, FLOW_CONTROL = true) + CKM Oracle
 NE YAPAR : Truncate yok -> her run üstüne ekler (log / tarihçe gibi).
            Flow control açık: önce I$'a döker, CKM kontrollerini çalıştırır,
            hatalıları E$_T_CA_APPEND_CLEAN'e yazar ve I$'tan siler, kalan temizleri ekler.
 NE ZAMAN : Append-only tablolar (günlük log, hareket arşivi) + veri kalitesi kontrolü gereken yerler.
 SENARYO  : Gün1 4 | Gün2 +5 temiz (6,7,8 E$'a) = 9 | Gün3 B9 şubesi eklendi, 7 artık geçer: +6 = 15
 ÇALIŞTIR : dbt run -s ca_append_ckm
================================================================================
@setup
CREATE TABLE t_ca_append_clean (
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  load_dt DATE)
/
@check day1
satır :: select count(*) from t_ca_append_clean => 4
@check day2
üstüne 5 temiz satır :: select count(*) from t_ca_append_clean => 9
E$ hata tipleri (bu run) :: select cust_no, cons_type from "E$_T_CA_APPEND_CLEAN" where odi_sess_no = :sess order by 1 => [(6, 'NN'), (7, 'FK'), (8, 'CK')]
@check day3
üstüne 6 satır (7 artık geçti) :: select count(*) from t_ca_append_clean => 15
E$ (bu run) :: select cust_no from "E$_T_CA_APPEND_CLEAN" where odi_sess_no = :sess order by 1 => [(6,), (8,)]
================================================================================
#}
{{ config(
    materialized       = 'odi_control_append',
    alias              = 'T_CA_APPEND_CLEAN',
    odi_flow_control   = true,
    odi_ckm_not_null   = ['cust_name'],
    odi_ckm_conditions = {'CHK_SEGMENT': "segment in ('R','C')"},
    odi_ckm_references = {'FK_BRANCH': {'cols': ['branch_cd'], 'ref_table': var('odi_name_prefix', '') ~ 'D_BRANCH'}},
    odi_audit_insert   = {'load_dt': 'sysdate'}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status
  from {{ source('src', 'src_customer') }}
