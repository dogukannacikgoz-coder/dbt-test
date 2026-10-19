{#
================================================================================
 MODEL    : odi/02_incremental_update/iu_basic_ckm   ->  T_IU
 ODI KM   : IKM Oracle Incremental Update + CKM Oracle (FLOW_CONTROL = true)
 NE YAPAR : 1) Model SQL'i I$_T_IU'ya dökülür, her satır IND_UPDATE='I'
            2) CKM: NN / CK / FK kontrolleri, hatalılar E$_T_IU'ya, I$'tan silinir
            3) Target'ta key'i olanlar 'U', U'lardan hiçbir kolonu değişmeyenler 'N'
            4) 'U' satırlar update, 'I' satırlar insert edilir. 'N'ye dokunulmaz.
 NE ZAMAN : Kayıt güncellenir ama tarihçe tutulmaz (EDW / DM tabloları), adım adım
            log ve debug istendiğinde, kaynak kalitesi şüpheliyse.
 SENARYO  : Gün2: 1,2,4 update | 3 değişmedi (N, upd_dt boş kalır) | 5 insert | 6,7,8 E$
            Gün3: B9 şubesi eklendi, kaynak 7'yi tekrar gönderdiği için 7 girer
 ÇALIŞTIR : dbt run -s iu_basic_ckm
            dbt run -s iu_basic_ckm --vars '{max_err: 0}'   -> hata eşiği aşılır, model fail, target değişmez
            dbt run -s iu_basic_ckm --full-refresh          -> truncate + hepsi insert
                                                               (odi_allow_full_refresh: true olduğu için izinli;
                                                                bu config yoksa --full-refresh reddedilir)
================================================================================
@setup
CREATE TABLE t_iu (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  ins_dt DATE, upd_dt DATE)
/
@check day1
satır :: select count(*) from t_iu => 4
ilk yüklemede update yok :: select count(*) from t_iu where upd_dt is not null => 0
@check day2
müşteriler :: select cust_no from t_iu order by 1 => [(1,), (2,), (3,), (4,), (5,)]
güncellenenler (upd_dt dolu) :: select cust_no from t_iu where upd_dt is not null order by 1 => [(1,), (2,), (4,)]
1'in şehri :: select city from t_iu where cust_no = 1 => 'ANK'
E$ (bu run) :: select cust_no, cons_type from "E$_T_IU" where odi_sess_no = :sess order by 1 => [(6, 'NN'), (7, 'FK'), (8, 'CK')]
step: Flag useless rows :: select sum(rows_affected) from odi_step_log where sess_no = :sess and model_name like '%.T_IU' and step_name = 'Flag useless rows' => 1
step: Update :: select sum(rows_affected) from odi_step_log where sess_no = :sess and model_name like '%.T_IU' and step_name = 'Update existing rows' => 3
step: Insert :: select sum(rows_affected) from odi_step_log where sess_no = :sess and model_name like '%.T_IU' and step_name = 'Insert new rows' => 1
@check day3
7 girdi :: select cust_no from t_iu order by 1 => [(1,), (2,), (3,), (4,), (5,), (7,)]
update yok (idempotent) :: select sum(rows_affected) from odi_step_log where sess_no = :sess and model_name like '%.T_IU' and step_name = 'Update existing rows' => 0
================================================================================
#}
{{ config(
    materialized       = 'odi_incremental_update',
    alias              = 'T_IU',
    unique_key         = 'cust_no',
    odi_flow_control   = true,
    odi_ckm_not_null   = ['cust_name'],
    odi_ckm_conditions = {'CHK_SEGMENT': "segment in ('R','C')"},
    odi_ckm_references = {'FK_BRANCH': {'cols': ['branch_cd'], 'ref_table': 'D_BRANCH'}},
    odi_ckm_max_errors = var('max_err', none),
    odi_allow_full_refresh = true,
    odi_audit_insert   = {'ins_dt': 'sysdate'},
    odi_audit_update   = {'upd_dt': 'sysdate'}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status
  from {{ source('src', 'src_customer') }}
