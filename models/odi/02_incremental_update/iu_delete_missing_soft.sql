{#
================================================================================
 MODEL    : odi/02_incremental_update/iu_delete_missing_soft   ->  T_IU_SOFT
 ODI KM   : IKM Oracle Incremental Update + "kaynakta yoksa sil" (soft delete)
 NE YAPAR : Kaynak her gün TAM listeyi gönderir. Target'ta olup kaynakta artık olmayan
            kayıtlar silinmez, IS_DELETED = 'Y' yapılır (odi_soft_delete).
            Model SQL'i 'N' as is_deleted döndürdüğü için kayıt geri gelirse 'N'ye döner.
            Hard delete için odi_soft_delete'i kaldırın.
            odi_delete_missing_filter = "t.status <> 'K'" gibi silme kapsamı daraltılabilir.
 DİKKAT   : SADECE full extract'ta kullanın. Model SQL'i incremental filtre içeriyorsa
            filtre dışında kalan her şey "kaynakta yok" sayılıp silinir.
 SENARYO  : Gün2'de 4 kaynakta yok -> IS_DELETED='Y'; 5 yeni eklenir
 ÇALIŞTIR : dbt run -s iu_delete_missing_soft
================================================================================
@setup
CREATE TABLE t_iu_soft (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  is_deleted VARCHAR2(1), upd_dt DATE)
/
@check day1
hepsi aktif :: select count(*) from t_iu_soft where is_deleted = 'N' => 4
@check day2
5 satır :: select count(*) from t_iu_soft => 5
4 soft delete :: select cust_no from t_iu_soft where is_deleted = 'Y' => 4
@check day3
hâlâ sadece 4 silinmiş :: select cust_no from t_iu_soft where is_deleted = 'Y' => 4
================================================================================
#}
{{ config(
    materialized       = 'odi_incremental_update',
    alias              = 'T_IU_SOFT',
    unique_key         = 'cust_no',
    odi_delete_missing = true,
    odi_soft_delete    = {'column': 'is_deleted', 'value': "'Y'"},
    odi_audit_update   = {'upd_dt': 'sysdate'}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status,
       'N' as is_deleted
  from {{ source('src', 'src_customer_snap') }}
