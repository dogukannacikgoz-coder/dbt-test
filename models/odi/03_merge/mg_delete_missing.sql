{#
================================================================================
 MODEL    : odi/03_merge/mg_delete_missing   ->  T_MG_SNAP
 ODI KM   : IKM Oracle Incremental Update (MERGE) + "kaynakta yoksa sil" (hard delete)
 NE YAPAR : MERGE ile upsert, ardından kaynakta (full snapshot) olmayan target satırlarını siler.
            Böylece target her zaman kaynağın aynası olur, ama değişmeyen satırlara dokunulmaz
            (truncate-insert'ten farkı: index/redo/upd_dt korunur).
 DİKKAT   : Sadece full extract. odi_flow_mode='none' iken model SQL'i iki kez çalışır
            (MERGE + silme anahtarları); ağır SQL'de I$ kullanın.
 SENARYO  : Gün2: 4 kaynakta yok -> silinir, 5 eklenir
 ÇALIŞTIR : dbt run -s mg_delete_missing
================================================================================
@setup
CREATE TABLE t_mg_snap (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1))
/
@check day1
müşteriler :: select cust_no from t_mg_snap order by 1 => [(1,), (2,), (3,), (4,)]
@check day2
4 silindi, 5 eklendi :: select cust_no from t_mg_snap order by 1 => [(1,), (2,), (3,), (5,)]
@check day3
aynı :: select cust_no from t_mg_snap order by 1 => [(1,), (2,), (3,), (5,)]
================================================================================
#}
{{ config(
    materialized       = 'odi_merge',
    alias              = 'T_MG_SNAP',
    unique_key         = 'cust_no',
    odi_flow_mode      = 'none',
    odi_delete_missing = true
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status
  from {{ source('src', 'src_customer_snap') }}
