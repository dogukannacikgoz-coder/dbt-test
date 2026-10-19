{#
================================================================================
 MODEL    : odi/02_incremental_update/iu_insert_only   ->  T_IU_INS_ONLY
 ODI KM   : IKM Oracle Incremental Update, UPDATE = false  (+ parallel DML)
 NE YAPAR : Target'ta olmayan key'leri ekler, var olanlara DOKUNMAZ (ilk gelen değer kalır).
            Control Append'den farkı: duplicate key oluşturmaz.
 NE ZAMAN : "İlk açılış bilgisi" tabloları (ilk müşteri olma tarihi, ilk kanal),
            değişmeyen referans kayıtları.
 EK       : odi_parallel_dml = true -> ALTER SESSION ENABLE PARALLEL DML; hint'lerle paralel yazar.
 SENARYO  : Gün1 4 | Gün2 5,6,7,8 eklenir (kontrol yok) = 8, 1'in şehri hâlâ IST
 ÇALIŞTIR : dbt run -s iu_insert_only
================================================================================
@setup
CREATE TABLE t_iu_ins_only (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1), ins_dt DATE)
/
@check day1
satır :: select count(*) from t_iu_ins_only => 4
@check day2
yeniler eklendi :: select count(*) from t_iu_ins_only => 8
var olan güncellenmedi :: select city from t_iu_ins_only where cust_no = 1 => 'IST'
@check day3
hâlâ 8 :: select count(*) from t_iu_ins_only => 8
================================================================================
#}
{{ config(
    materialized     = 'odi_incremental_update',
    alias            = 'T_IU_INS_ONLY',
    unique_key       = 'cust_no',
    odi_update       = false,
    odi_parallel_dml = true,
    odi_insert_hint  = 'APPEND PARALLEL(4)',
    odi_audit_insert = {'ins_dt': 'sysdate'}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status
  from {{ source('src', 'src_customer') }}
