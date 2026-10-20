-- ============================================================================
--  KONTROL — GÜN 3 (dbt run'dan sonra; sadece okur)
--  Paylaşılan sandbox şeması için: TÜM nesneler DOA_ önekiyle (ör. DOA_SRC_CUSTOMER).
--  ÖNEK: büyük harf, '_' ile biten, şemada kimsenin kullanmadığı bir değer olmalı ve
--        dbt tarafındaki ODI_NAME_PREFIX ile AYNI olmalı.
--  SQL Developer: F5 (Run Script) ile çalıştır.  Bu dosya scripts/gen_sandbox_sql.py ile üretildi.
-- ============================================================================
-- PLAIN sürüm: önek DOA_, şema GLOBAL_DWH dosyaya gömülü. Script olarak çalıştır (SQL Developer F5 / DBeaver Alt+X),
-- aracında 'hata olunca dur' açık olsun. Önek/şema değişecekse: python scripts/gen_sandbox_sql.py --prefix X_ --schema Y
ALTER SESSION SET CURRENT_SCHEMA = GLOBAL_DWH;


BEGIN
  IF LENGTH('DOA_') < 3 OR SUBSTR('DOA_', -1) <> '_' OR 'DOA_' <> UPPER('DOA_') THEN
    RAISE_APPLICATION_ERROR(-20900, 'Önek hatalı: en az 3 karakter, büyük harf, _ ile bitmeli. Şu an: DOA_');
  END IF;
  IF SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') <> UPPER('GLOBAL_DWH') THEN
    RAISE_APPLICATION_ERROR(-20900, 'Aktif şema GLOBAL_DWH değil: ' || SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'));
  END IF;
END;
/


-- ================ ca_append_ckm  (DOA_T_CA_APPEND_CLEAN)
-- -- üstüne 6 satır (7 artık geçti)   ==> beklenen: 15
select count(*) from DOA_T_CA_APPEND_CLEAN;
-- -- E$ (bu run)   ==> beklenen: 6 | 8
select cust_no from "E$_DOA_T_CA_APPEND_CLEAN" where odi_sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from DOA_ODI_STEP_LOG where model_name like '%.DOA_T_CA_APPEND_CLEAN') order by 1;

-- ================ ca_truncate_insert  (DOA_T_CA_SNAPSHOT)
-- -- hâlâ 8 (her run baştan)   ==> beklenen: 8
select count(*) from DOA_T_CA_SNAPSHOT;

-- ================ iu_basic_ckm  (DOA_T_IU)
-- -- 7 girdi   ==> beklenen: 1 | 2 | 3 | 4 | 5 | 7
select cust_no from DOA_T_IU order by 1;
-- -- update yok (idempotent)   ==> beklenen: 0
select sum(rows_affected) from DOA_ODI_STEP_LOG where sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from DOA_ODI_STEP_LOG where model_name like '%.DOA_T_IU') and model_name like '%.DOA_T_IU' and step_name = 'Update existing rows';

-- ================ iu_cdc_delete  (DOA_T_IU_CDC)
-- -- 9 eklendi   ==> beklenen: 1 | 2 | 4 | 5 | 7 | 9
select cust_no from DOA_T_IU_CDC order by 1;

-- ================ iu_delete_missing_soft  (DOA_T_IU_SOFT)
-- -- hâlâ sadece 4 silinmiş   ==> beklenen: 4
select cust_no from DOA_T_IU_SOFT where is_deleted = 'Y';

-- ================ iu_gtt_no_ddl  (DOA_T_IU_GTT)
-- -- T_IU ile fark yok   ==> beklenen: 0
select count(*) from (select cust_no, city, email, status from DOA_T_IU minus select cust_no, city, email, status from DOA_T_IU_GTT);

-- ================ iu_insert_only  (DOA_T_IU_INS_ONLY)
-- -- hâlâ 8   ==> beklenen: 8
select count(*) from DOA_T_IU_INS_ONLY;

-- ================ iu_recycle_errors  (DOA_T_IU_RECYCLE)
-- -- recycle ile 7 ve yeni 9 girdi   ==> beklenen: 1 | 2 | 3 | 4 | 5 | 7 | 9
select cust_no from DOA_T_IU_RECYCLE order by 1;
-- -- E$'ta 7 kalmadı   ==> beklenen: 0
select count(*) from "E$_DOA_T_IU_RECYCLE" where cust_no = 7;

-- ================ iu_update_only  (DOA_T_IU_UPD_ONLY)
-- -- hâlâ 3   ==> beklenen: 3
select count(*) from DOA_T_IU_UPD_ONLY;

-- ================ mg_cdc_delete  (DOA_T_MG_CDC)
-- -- 9 eklendi   ==> beklenen: 1 | 2 | 4 | 5 | 7 | 9
select cust_no from DOA_T_MG_CDC order by 1;

-- ================ mg_delete_missing  (DOA_T_MG_SNAP)
-- -- aynı   ==> beklenen: 1 | 2 | 3 | 5
select cust_no from DOA_T_MG_SNAP order by 1;

-- ================ mg_direct  (DOA_T_MG_DIRECT)
-- -- değişiklik yok   ==> beklenen: 0
select sum(rows_affected) from DOA_ODI_STEP_LOG where sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from DOA_ODI_STEP_LOG where model_name like '%.DOA_T_MG_DIRECT') and model_name like '%.DOA_T_MG_DIRECT' and step_name = 'Merge rows';

-- ================ mg_flow_ckm  (DOA_T_MG_FLOW)
-- -- aynı   ==> beklenen: 6
select count(*) from DOA_T_MG_FLOW;

-- ================ scd_close_missing  (DOA_T_SCD_SNAP)
-- -- değişmedi   ==> beklenen: 6, 4
select count(*), sum(curr_flag) from DOA_T_SCD_SNAP;

-- ================ scd_type2  (DOA_T_SCD)
-- -- değişmedi   ==> beklenen: 7, 6
select count(*), sum(curr_flag) from DOA_T_SCD;

-- ================ pt_daily_exchange  (DOA_T_TXN_DAILY_X)
-- -- toplam   ==> beklenen: 6
select count(*) from DOA_T_TXN_DAILY_X;
-- -- 102 düzeldi   ==> beklenen: 75
select amount from DOA_T_TXN_DAILY_X where txn_id = 102;

-- ================ pt_daily_truncate  (DOA_T_TXN_DAILY_TRUNC)
-- -- toplam   ==> beklenen: 6
select count(*) from DOA_T_TXN_DAILY_TRUNC;
-- -- 102 düzeldi   ==> beklenen: 75
select amount from DOA_T_TXN_DAILY_TRUNC where txn_id = 102;
-- -- 10-02 dokunulmadı   ==> beklenen: 2
select count(*) from DOA_T_TXN_DAILY_TRUNC where txn_date = date '2026-10-02';

-- ================ pt_merge_prune  (DOA_T_TXN_MERGE_PART)
-- -- satır   ==> beklenen: 6
select count(*) from DOA_T_TXN_MERGE_PART;
-- -- sadece 102 güncellendi   ==> beklenen: 102
select txn_id from DOA_T_TXN_MERGE_PART where upd_dt is not null;

-- ================ pt_monthly_delete  (DOA_T_TXN_MONTHLY)
-- -- Ekim   ==> beklenen: 6
select count(*) from DOA_T_TXN_MONTHLY;
-- -- 102 düzeldi   ==> beklenen: 75
select amount from DOA_T_TXN_MONTHLY where txn_id = 102;

-- ================ lkm_staging  (DOA_T_LKM_CUST)
-- -- satır   ==> beklenen: 8
select count(*) from DOA_T_LKM_CUST;

-- ================ cust_fin_daily  (DOA_DM_CUST_FIN_DAILY)
-- -- satır   ==> beklenen: 6
select count(*) from DOA_DM_CUST_FIN_DAILY;
-- -- 2'nin 10-01 tutarı   ==> beklenen: 75
select txn_amt from DOA_DM_CUST_FIN_DAILY where cust_no = 2 and snapshot_date = date '2026-10-01';
-- -- sadece o satır güncellendi   ==> beklenen: 2
select cust_no from DOA_DM_CUST_FIN_DAILY where upd_dt is not null;

-- ================ cust_fin_daily_tmp01  (DOA_T_CFD_TMP01)
-- -- 10-01 yeniden   ==> beklenen: 4
select count(*) from DOA_T_CFD_TMP01;
