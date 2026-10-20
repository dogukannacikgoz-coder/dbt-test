-- ============================================================================
--  KONTROL — GÜN 2 (dbt run'dan sonra; sadece okur)
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
-- -- üstüne 5 temiz satır   ==> beklenen: 9
select count(*) from DOA_T_CA_APPEND_CLEAN;
-- -- E$ hata tipleri (bu run)   ==> beklenen: 6, NN | 7, FK | 8, CK
select cust_no, cons_type from "E$_DOA_T_CA_APPEND_CLEAN" where odi_sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from DOA_ODI_STEP_LOG where model_name like '%.DOA_T_CA_APPEND_CLEAN') order by 1;

-- ================ ca_truncate_insert  (DOA_T_CA_SNAPSHOT)
-- -- truncate + 8 satır (hatalılar dahil)   ==> beklenen: 8
select count(*) from DOA_T_CA_SNAPSHOT;

-- ================ iu_basic_ckm  (DOA_T_IU)
-- -- müşteriler   ==> beklenen: 1 | 2 | 3 | 4 | 5
select cust_no from DOA_T_IU order by 1;
-- -- güncellenenler (upd_dt dolu)   ==> beklenen: 1 | 2 | 4
select cust_no from DOA_T_IU where upd_dt is not null order by 1;
-- -- 1'in şehri   ==> beklenen: ANK
select city from DOA_T_IU where cust_no = 1;
-- -- E$ (bu run)   ==> beklenen: 6, NN | 7, FK | 8, CK
select cust_no, cons_type from "E$_DOA_T_IU" where odi_sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from DOA_ODI_STEP_LOG where model_name like '%.DOA_T_IU') order by 1;
-- -- step: Flag useless rows   ==> beklenen: 1
select sum(rows_affected) from DOA_ODI_STEP_LOG where sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from DOA_ODI_STEP_LOG where model_name like '%.DOA_T_IU') and model_name like '%.DOA_T_IU' and step_name = 'Flag useless rows';
-- -- step: Update   ==> beklenen: 3
select sum(rows_affected) from DOA_ODI_STEP_LOG where sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from DOA_ODI_STEP_LOG where model_name like '%.DOA_T_IU') and model_name like '%.DOA_T_IU' and step_name = 'Update existing rows';
-- -- step: Insert   ==> beklenen: 1
select sum(rows_affected) from DOA_ODI_STEP_LOG where sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from DOA_ODI_STEP_LOG where model_name like '%.DOA_T_IU') and model_name like '%.DOA_T_IU' and step_name = 'Insert new rows';

-- ================ iu_cdc_delete  (DOA_T_IU_CDC)
-- -- 3 silindi, 5 ve 7 eklendi   ==> beklenen: 1 | 2 | 4 | 5 | 7
select cust_no from DOA_T_IU_CDC order by 1;
-- -- 1 güncellendi   ==> beklenen: ANK
select city from DOA_T_IU_CDC where cust_no = 1;

-- ================ iu_delete_missing_soft  (DOA_T_IU_SOFT)
-- -- 5 satır   ==> beklenen: 5
select count(*) from DOA_T_IU_SOFT;
-- -- 4 soft delete   ==> beklenen: 4
select cust_no from DOA_T_IU_SOFT where is_deleted = 'Y';

-- ================ iu_gtt_no_ddl  (DOA_T_IU_GTT)
-- -- T_IU ile fark yok   ==> beklenen: 0
select count(*) from (select cust_no, city, email, status from DOA_T_IU minus select cust_no, city, email, status from DOA_T_IU_GTT);
-- -- E$ (bu run)   ==> beklenen: 3
select count(*) from "E$_DOA_T_IU_GTT" where odi_sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from DOA_ODI_STEP_LOG where model_name like '%.DOA_T_IU_GTT');
-- -- DDL atılmadı   ==> beklenen: 0
select count(*) from DOA_ODI_STEP_LOG where sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from DOA_ODI_STEP_LOG where model_name like '%.DOA_T_IU_GTT') and model_name like '%.DOA_T_IU_GTT' and (step_name like 'Create%' or step_name like 'Drop%');

-- ================ iu_insert_only  (DOA_T_IU_INS_ONLY)
-- -- yeniler eklendi   ==> beklenen: 8
select count(*) from DOA_T_IU_INS_ONLY;
-- -- var olan güncellenmedi   ==> beklenen: IST
select city from DOA_T_IU_INS_ONLY where cust_no = 1;

-- ================ iu_recycle_errors  (DOA_T_IU_RECYCLE)
-- -- 7 girmedi   ==> beklenen: 1 | 2 | 3 | 4 | 5
select cust_no from DOA_T_IU_RECYCLE order by 1;
-- -- 7 E$'ta   ==> beklenen: 1
select count(*) from "E$_DOA_T_IU_RECYCLE" where cust_no = 7;

-- ================ iu_update_only  (DOA_T_IU_UPD_ONLY)
-- -- hâlâ 3   ==> beklenen: 3
select count(*) from DOA_T_IU_UPD_ONLY;
-- -- 1'in şehri   ==> beklenen: ANK
select city from DOA_T_IU_UPD_ONLY where cust_no = 1;

-- ================ mg_cdc_delete  (DOA_T_MG_CDC)
-- -- 3 silindi   ==> beklenen: 1 | 2 | 4 | 5 | 7
select cust_no from DOA_T_MG_CDC order by 1;

-- ================ mg_delete_missing  (DOA_T_MG_SNAP)
-- -- 4 silindi, 5 eklendi   ==> beklenen: 1 | 2 | 3 | 5
select cust_no from DOA_T_MG_SNAP order by 1;

-- ================ mg_direct  (DOA_T_MG_DIRECT)
-- -- satır   ==> beklenen: 8
select count(*) from DOA_T_MG_DIRECT;
-- -- güncellenenler   ==> beklenen: 1 | 2 | 4
select cust_no from DOA_T_MG_DIRECT where upd_dt is not null order by 1;

-- ================ mg_flow_ckm  (DOA_T_MG_FLOW)
-- -- müşteriler   ==> beklenen: 1 | 2 | 3 | 4 | 5 | 7
select cust_no from DOA_T_MG_FLOW order by 1;
-- -- E$ (bu run)   ==> beklenen: 6 | 8
select cust_no from "E$_DOA_T_MG_FLOW" where odi_sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from DOA_ODI_STEP_LOG where model_name like '%.DOA_T_MG_FLOW') order by 1;
-- -- I$ artığı kalmadı   ==> beklenen: 0
select count(*) from all_tables where owner = sys_context('USERENV', 'CURRENT_SCHEMA') and table_name like 'I$\_DOA_T\_MG\_FLOW%' escape '\';

-- ================ scd_close_missing  (DOA_T_SCD_SNAP)
-- -- toplam / current   ==> beklenen: 6, 4
select count(*), sum(curr_flag) from DOA_T_SCD_SNAP;
-- -- 4 kapandı   ==> beklenen: 0
select curr_flag from DOA_T_SCD_SNAP where cust_no = 4;

-- ================ scd_type2  (DOA_T_SCD)
-- -- toplam / current   ==> beklenen: 7, 6
select count(*), sum(curr_flag) from DOA_T_SCD;
-- -- 1'in versiyonları   ==> beklenen: IST, 0 | ANK, 1
select city, curr_flag from DOA_T_SCD where cust_no = 1 order by eff_start_dt, cust_sk;
-- -- eski versiyon kapandı   ==> beklenen: 1
select count(*) from DOA_T_SCD where cust_no = 1 and curr_flag = 0 and eff_end_dt < date '2400-01-01';
-- -- 2 tek satır, yeni email   ==> beklenen: 1, ayse.new@x.com
select count(*), max(email) from DOA_T_SCD where cust_no = 2;

-- ================ pt_daily_exchange  (DOA_T_TXN_DAILY_X)
-- -- toplam   ==> beklenen: 5
select count(*) from DOA_T_TXN_DAILY_X;
-- -- iki günlük partition   ==> beklenen: 2
select count(*) from all_tab_partitions where table_owner = sys_context('USERENV', 'CURRENT_SCHEMA') and table_name = 'DOA_T_TXN_DAILY_X' and partition_name in ('P20261001', 'P20261002');
-- -- local index usable   ==> beklenen: 0
select count(*) from all_ind_partitions where index_owner = sys_context('USERENV', 'CURRENT_SCHEMA') and index_name = 'DOA_IX_T_TXN_DAILY_X_CUST' and status <> 'USABLE';

-- ================ pt_daily_truncate  (DOA_T_TXN_DAILY_TRUNC)
-- -- toplam   ==> beklenen: 5
select count(*) from DOA_T_TXN_DAILY_TRUNC;

-- ================ pt_merge_prune  (DOA_T_TXN_MERGE_PART)
-- -- satır   ==> beklenen: 5
select count(*) from DOA_T_TXN_MERGE_PART;

-- ================ pt_monthly_delete  (DOA_T_TXN_MONTHLY)
-- -- Ekim   ==> beklenen: 5
select count(*) from DOA_T_TXN_MONTHLY;

-- ================ lkm_staging  (DOA_T_LKM_CUST)
-- -- satır   ==> beklenen: 8
select count(*) from DOA_T_LKM_CUST;
-- -- C$ silindi   ==> beklenen: 0
select count(*) from all_tables where owner = sys_context('USERENV', 'CURRENT_SCHEMA') and table_name = 'C$_DOA_T_LKM_CUST';

-- ================ cust_fin_daily  (DOA_DM_CUST_FIN_DAILY)
-- -- satır   ==> beklenen: 5
select count(*) from DOA_DM_CUST_FIN_DAILY;

-- ================ cust_fin_daily_tmp01  (DOA_T_CFD_TMP01)
-- -- 10-02 müşterileri   ==> beklenen: 2
select count(*) from DOA_T_CFD_TMP01;

-- ================ cust_fin_daily_tmp02  (DOA_T_CFD_TMP02)
-- -- zenginleşti   ==> beklenen: 2
select count(*) from DOA_T_CFD_TMP02 where cust_name is not null;
