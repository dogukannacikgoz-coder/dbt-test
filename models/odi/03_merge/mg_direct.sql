{#
================================================================================
 MODEL    : odi/03_merge/mg_direct   ->  T_MG_DIRECT
 ODI KM   : IKM Oracle Incremental Update (MERGE), I$ YOK (odi_flow_mode = 'none')
 NE YAPAR : Tek bir MERGE: key eşleşen ve en az bir kolonu değişmiş satır update,
            eşleşmeyen insert. Hiç work tablo yok -> DDL yetkisi gerekmez, en yalın upsert.
 NE ZAMAN : Kaynak temiz, flow control gerekmiyor, hız önemli. Bankada varsayılan upsert.
 DİKKAT   : Kaynakta aynı key iki kez gelirse ORA-30926. Kaynağı tekilleştirin.
 SENARYO  : Gün2: 1,2,4 update | 3 değişmedi (upd_dt boş) | 5,6,7,8 insert (kontrol yok)
 ÇALIŞTIR : dbt run -s mg_direct
================================================================================
@setup
CREATE TABLE t_mg_direct (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  ins_dt DATE, upd_dt DATE)
/
@check day1
satır :: select count(*) from t_mg_direct => 4
@check day2
satır :: select count(*) from t_mg_direct => 8
güncellenenler :: select cust_no from t_mg_direct where upd_dt is not null order by 1 => [(1,), (2,), (4,)]
@check day3
değişiklik yok :: select sum(rows_affected) from odi_step_log where sess_no = :sess and model_name like '%.T_MG_DIRECT' and step_name = 'Merge rows' => 0
================================================================================
#}
{{ config(
    materialized     = 'odi_merge',
    alias            = 'T_MG_DIRECT',
    unique_key       = 'cust_no',
    odi_flow_mode    = 'none',
    odi_audit_insert = {'ins_dt': 'sysdate'},
    odi_audit_update = {'upd_dt': 'sysdate'}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status
  from {{ source('src', 'src_customer') }}
