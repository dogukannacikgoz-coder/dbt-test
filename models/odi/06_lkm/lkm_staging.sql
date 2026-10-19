{#
================================================================================
 MODEL    : odi/06_lkm/lkm_staging   ->  T_LKM_CUST
 ODI KM   : LKM SQL to Oracle / LKM Oracle to Oracle (DBLINK) + IKM Control Append
 NE YAPAR : odi_lkm = true -> model SQL'i önce C$_T_LKM_CUST'a stage edilir, IKM C$'tan okur.
            Gerçekte kaynak dblink üzerindedir:
              select /*+ DRIVING_SITE(c) */ ... from core.customer@CORE_DBL c where ...
            Uzak tabloya bir kez gidilir; flow / CKM / update adımları lokal C$ üzerinde koşar.
            (Testte dblink yok, aynı şemadan okunur.)
 NE ZAMAN : Kaynak başka Oracle'da (dblink) ve IKM'in birden çok adımı kaynağı okuyacaksa.
            Farklı teknoloji (MSSQL, dosya) dbt'de mümkün değil -> ingestion katmanı.
 SENARYO  : Gün1 4 | Gün2 8 | C$ tablosu run sonunda silinmiş
 ÇALIŞTIR : dbt run -s lkm_staging
================================================================================
@setup
CREATE TABLE t_lkm_cust (
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1))
/
@check day1
satır :: select count(*) from t_lkm_cust => 4
@check day2
satır :: select count(*) from t_lkm_cust => 8
C$ silindi :: select count(*) from user_tables where table_name = 'C$_T_LKM_CUST' => 0
@check day3
satır :: select count(*) from t_lkm_cust => 8
================================================================================
#}
{{ config(
    materialized = 'odi_control_append',
    alias        = 'T_LKM_CUST',
    odi_lkm      = true,
    odi_truncate = true
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status
  from {{ source('src', 'src_customer') }}
