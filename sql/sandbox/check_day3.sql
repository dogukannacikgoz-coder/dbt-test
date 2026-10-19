-- ============================================================================
--  KONTROL — GÜN 3 (dbt run'dan sonra; sadece okur)
--  Paylaşılan sandbox şeması için: TÜM nesneler &P. önekiyle (ör. DOA_SRC_CUSTOMER).
--  ÖNEK: büyük harf, '_' ile biten, şemada kimsenin kullanmadığı bir değer olmalı ve
--        dbt tarafındaki ODI_NAME_PREFIX ile AYNI olmalı.
--  SQL Developer: F5 (Run Script) ile çalıştır.  Bu dosya scripts/gen_sandbox_sql.py ile üretildi.
-- ============================================================================
SET DEFINE ON
SET VERIFY OFF
DEFINE P = DOA_
DEFINE S = GLOBAL_DWH
-- Tüm şemasız isimler bu şemaya gider (kendi kullanıcınla bağlansan bile). Şemanın kendisiyle bağlıysan etkisiz.
ALTER SESSION SET CURRENT_SCHEMA = &S.;


WHENEVER SQLERROR EXIT
BEGIN
  IF LENGTH('&P.') < 3 OR SUBSTR('&P.', -1) <> '_' OR '&P.' <> UPPER('&P.') THEN
    RAISE_APPLICATION_ERROR(-20900, 'Önek hatalı: en az 3 karakter, büyük harf, _ ile bitmeli. Şu an: &P.');
  END IF;
  IF SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') <> UPPER('&S.') THEN
    RAISE_APPLICATION_ERROR(-20900, 'Aktif şema &S. değil: ' || SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'));
  END IF;
END;
/
WHENEVER SQLERROR CONTINUE

SET PAGESIZE 200
SET LINESIZE 200

PROMPT ================ ca_append_ckm  (&P.T_CA_APPEND_CLEAN)
PROMPT -- üstüne 6 satır (7 artık geçti)   ==> beklenen: 15
select count(*) from &P.T_CA_APPEND_CLEAN;
PROMPT -- E$ (bu run)   ==> beklenen: 6 | 8
select cust_no from "E$_&P.T_CA_APPEND_CLEAN" where odi_sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from &P.ODI_STEP_LOG where model_name like '%.&P.T_CA_APPEND_CLEAN') order by 1;

PROMPT ================ ca_truncate_insert  (&P.T_CA_SNAPSHOT)
PROMPT -- hâlâ 8 (her run baştan)   ==> beklenen: 8
select count(*) from &P.T_CA_SNAPSHOT;

PROMPT ================ iu_basic_ckm  (&P.T_IU)
PROMPT -- 7 girdi   ==> beklenen: 1 | 2 | 3 | 4 | 5 | 7
select cust_no from &P.T_IU order by 1;
PROMPT -- update yok (idempotent)   ==> beklenen: 0
select sum(rows_affected) from &P.ODI_STEP_LOG where sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from &P.ODI_STEP_LOG where model_name like '%.&P.T_IU') and model_name like '%.&P.T_IU' and step_name = 'Update existing rows';

PROMPT ================ iu_cdc_delete  (&P.T_IU_CDC)
PROMPT -- 9 eklendi   ==> beklenen: 1 | 2 | 4 | 5 | 7 | 9
select cust_no from &P.T_IU_CDC order by 1;

PROMPT ================ iu_delete_missing_soft  (&P.T_IU_SOFT)
PROMPT -- hâlâ sadece 4 silinmiş   ==> beklenen: 4
select cust_no from &P.T_IU_SOFT where is_deleted = 'Y';

PROMPT ================ iu_gtt_no_ddl  (&P.T_IU_GTT)
PROMPT -- T_IU ile fark yok   ==> beklenen: 0
select count(*) from (select cust_no, city, email, status from &P.T_IU minus select cust_no, city, email, status from &P.T_IU_GTT);

PROMPT ================ iu_insert_only  (&P.T_IU_INS_ONLY)
PROMPT -- hâlâ 8   ==> beklenen: 8
select count(*) from &P.T_IU_INS_ONLY;

PROMPT ================ iu_recycle_errors  (&P.T_IU_RECYCLE)
PROMPT -- recycle ile 7 ve yeni 9 girdi   ==> beklenen: 1 | 2 | 3 | 4 | 5 | 7 | 9
select cust_no from &P.T_IU_RECYCLE order by 1;
PROMPT -- E$'ta 7 kalmadı   ==> beklenen: 0
select count(*) from "E$_&P.T_IU_RECYCLE" where cust_no = 7;

PROMPT ================ iu_update_only  (&P.T_IU_UPD_ONLY)
PROMPT -- hâlâ 3   ==> beklenen: 3
select count(*) from &P.T_IU_UPD_ONLY;

PROMPT ================ mg_cdc_delete  (&P.T_MG_CDC)
PROMPT -- 9 eklendi   ==> beklenen: 1 | 2 | 4 | 5 | 7 | 9
select cust_no from &P.T_MG_CDC order by 1;

PROMPT ================ mg_delete_missing  (&P.T_MG_SNAP)
PROMPT -- aynı   ==> beklenen: 1 | 2 | 3 | 5
select cust_no from &P.T_MG_SNAP order by 1;

PROMPT ================ mg_direct  (&P.T_MG_DIRECT)
PROMPT -- değişiklik yok   ==> beklenen: 0
select sum(rows_affected) from &P.ODI_STEP_LOG where sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from &P.ODI_STEP_LOG where model_name like '%.&P.T_MG_DIRECT') and model_name like '%.&P.T_MG_DIRECT' and step_name = 'Merge rows';

PROMPT ================ mg_flow_ckm  (&P.T_MG_FLOW)
PROMPT -- aynı   ==> beklenen: 6
select count(*) from &P.T_MG_FLOW;

PROMPT ================ scd_close_missing  (&P.T_SCD_SNAP)
PROMPT -- değişmedi   ==> beklenen: 6, 4
select count(*), sum(curr_flag) from &P.T_SCD_SNAP;

PROMPT ================ scd_type2  (&P.T_SCD)
PROMPT -- değişmedi   ==> beklenen: 7, 6
select count(*), sum(curr_flag) from &P.T_SCD;

PROMPT ================ pt_daily_exchange  (&P.T_TXN_DAILY_X)
PROMPT -- toplam   ==> beklenen: 6
select count(*) from &P.T_TXN_DAILY_X;
PROMPT -- 102 düzeldi   ==> beklenen: 75
select amount from &P.T_TXN_DAILY_X where txn_id = 102;

PROMPT ================ pt_daily_truncate  (&P.T_TXN_DAILY_TRUNC)
PROMPT -- toplam   ==> beklenen: 6
select count(*) from &P.T_TXN_DAILY_TRUNC;
PROMPT -- 102 düzeldi   ==> beklenen: 75
select amount from &P.T_TXN_DAILY_TRUNC where txn_id = 102;
PROMPT -- 10-02 dokunulmadı   ==> beklenen: 2
select count(*) from &P.T_TXN_DAILY_TRUNC where txn_date = date '2026-10-02';

PROMPT ================ pt_merge_prune  (&P.T_TXN_MERGE_PART)
PROMPT -- satır   ==> beklenen: 6
select count(*) from &P.T_TXN_MERGE_PART;
PROMPT -- sadece 102 güncellendi   ==> beklenen: 102
select txn_id from &P.T_TXN_MERGE_PART where upd_dt is not null;

PROMPT ================ pt_monthly_delete  (&P.T_TXN_MONTHLY)
PROMPT -- Ekim   ==> beklenen: 6
select count(*) from &P.T_TXN_MONTHLY;
PROMPT -- 102 düzeldi   ==> beklenen: 75
select amount from &P.T_TXN_MONTHLY where txn_id = 102;

PROMPT ================ lkm_staging  (&P.T_LKM_CUST)
PROMPT -- satır   ==> beklenen: 8
select count(*) from &P.T_LKM_CUST;

PROMPT ================ cust_fin_daily  (&P.DM_CUST_FIN_DAILY)
PROMPT -- satır   ==> beklenen: 6
select count(*) from &P.DM_CUST_FIN_DAILY;
PROMPT -- 2'nin 10-01 tutarı   ==> beklenen: 75
select txn_amt from &P.DM_CUST_FIN_DAILY where cust_no = 2 and snapshot_date = date '2026-10-01';
PROMPT -- sadece o satır güncellendi   ==> beklenen: 2
select cust_no from &P.DM_CUST_FIN_DAILY where upd_dt is not null;

PROMPT ================ cust_fin_daily_tmp01  (&P.T_CFD_TMP01)
PROMPT -- 10-01 yeniden   ==> beklenen: 4
select count(*) from &P.T_CFD_TMP01;
