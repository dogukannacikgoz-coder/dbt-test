{#
================================================================================
 GERÇEK AKIŞ ÖRNEĞİ : dm_cad / cust_fin_daily
 ADIM 2 / 3         : cust_fin_daily_tmp02  ->  T_CFD_TMP02
 NE YAPAR           : Adım 1'i müşteri boyutuyla (T_IU) zenginleştirir.
                      ref() kullanıldığı için dbt sırayı ve lineage'ı kendisi kurar;
                      T_IU başka klasörde (başka job) olsa da bağımlılık görünür.
 NOT                : tag:cust_fin_daily ile seçince T_IU'yu yeniden ÇALIŞTIRMAZ, sadece okur.
================================================================================
@setup
CREATE TABLE t_cfd_tmp02 (
  snapshot_date DATE, cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5),
  branch_cd VARCHAR2(5), txn_cnt NUMBER, txn_amt NUMBER)
/
@check day2
zenginleşti :: select count(*) from t_cfd_tmp02 where cust_name is not null => 2
================================================================================
#}
{{ config(
    materialized = 'odi_control_append',
    alias        = 'T_CFD_TMP02',
    tags         = ['cust_fin_daily'],
    odi_truncate = true
) }}

select a.snapshot_date, a.cust_no, c.cust_name, c.segment, c.branch_cd, a.txn_cnt, a.txn_amt
  from {{ ref('cust_fin_daily_tmp01') }} a
  join {{ ref('iu_basic_ckm') }} c
    on c.cust_no = a.cust_no
