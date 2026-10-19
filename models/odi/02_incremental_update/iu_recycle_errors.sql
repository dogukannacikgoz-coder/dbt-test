{#
================================================================================
 MODEL    : odi/02_incremental_update/iu_recycle_errors   ->  T_IU_RECYCLE
 ODI KM   : IKM Oracle Incremental Update + CKM + RECYCLE_ERRORS
 NE YAPAR : Kaynak sadece değişenleri gönderir (CDC). Bir kayıt CKM'e takılırsa E$'a düşer
            ve kaynak onu bir daha GÖNDERMEZ. odi_recycle_errors = true her run'da önceki
            run'ların E$ satırlarını I$'a geri koyar; artık geçiyorsa target'a girer ve E$'tan
            silinir, hâlâ hatalıysa bu run'ın session'ıyla tekrar E$'a yazılır.
 NE ZAMAN : Delta kaynak + referans verisi sonradan gelen (şube, ürün kodu) akışlar.
 SENARYO  : Gün2: 7 numara (şube B9) FK'ya takılır, E$'a düşer.
            Gün3: B9 eklendi, kaynakta sadece 9 var -> recycle ile 7 de girer, E$'ta 7 kalmaz.
 ÇALIŞTIR : dbt run -s iu_recycle_errors
================================================================================
@setup
CREATE TABLE t_iu_recycle (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1))
/
@check day1
satır :: select count(*) from t_iu_recycle => 4
@check day2
7 girmedi :: select cust_no from t_iu_recycle order by 1 => [(1,), (2,), (3,), (4,), (5,)]
7 E$'ta :: select count(*) from "E$_T_IU_RECYCLE" where cust_no = 7 => 1
@check day3
recycle ile 7 ve yeni 9 girdi :: select cust_no from t_iu_recycle order by 1 => [(1,), (2,), (3,), (4,), (5,), (7,), (9,)]
E$'ta 7 kalmadı :: select count(*) from "E$_T_IU_RECYCLE" where cust_no = 7 => 0
================================================================================
#}
{{ config(
    materialized       = 'odi_incremental_update',
    alias              = 'T_IU_RECYCLE',
    unique_key         = 'cust_no',
    odi_flow_control   = true,
    odi_recycle_errors = true,
    odi_ckm_references = {'FK_BRANCH': {'cols': ['branch_cd'], 'ref_table': target.schema ~ '.' ~ var('odi_name_prefix', '') ~ 'D_BRANCH'}}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status
  from {{ source('src', 'src_customer_cdc') }}
 where op_type in ('I', 'U')
