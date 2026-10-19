{#
================================================================================
 MODEL    : odi/02_incremental_update/iu_update_only   ->  T_IU_UPD_ONLY
 ODI KM   : IKM Oracle Incremental Update, INSERT = false
 NE YAPAR : Sadece target'ta zaten var olan kayıtları günceller; yeni kayıt eklemez.
 NE ZAMAN : "Ana kaydı başka süreç açar, ben sadece alanlarını zenginleştiririm"
            (ör. müşteri tablosuna risk skoru / segment güncellemesi).
 SENARYO  : Target'ta 1,2,3 eski değerlerle hazır. Gün1: üçü güncellenir, 4 eklenmez.
            Gün2: 1'in şehri ANK olur; 5 yeni ama eklenmez.
 ÇALIŞTIR : dbt run -s iu_update_only
================================================================================
@setup
CREATE TABLE t_iu_upd_only (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1), upd_dt DATE)
/
INSERT INTO t_iu_upd_only (cust_no, cust_name, city)
SELECT 1, 'OLD', 'OLD' FROM dual UNION ALL SELECT 2, 'OLD', 'OLD' FROM dual UNION ALL SELECT 3, 'OLD', 'OLD' FROM dual
/
@check day1
hâlâ 3 satır (insert yok) :: select count(*) from t_iu_upd_only => 3
isimler güncellendi :: select cust_name from t_iu_upd_only where cust_no = 1 => 'Ali'
@check day2
hâlâ 3 :: select count(*) from t_iu_upd_only => 3
1'in şehri :: select city from t_iu_upd_only where cust_no = 1 => 'ANK'
@check day3
hâlâ 3 :: select count(*) from t_iu_upd_only => 3
================================================================================
#}
{{ config(
    materialized     = 'odi_incremental_update',
    alias            = 'T_IU_UPD_ONLY',
    unique_key       = 'cust_no',
    odi_insert       = false,
    odi_audit_update = {'upd_dt': 'sysdate'}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status
  from {{ source('src', 'src_customer') }}
