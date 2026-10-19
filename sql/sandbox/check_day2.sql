-- ============================================================================
--  KONTROL — GÜN 2 (dbt run'dan sonra; sadece okur)
--  Paylaşılan sandbox şeması için: TÜM nesneler &P. önekiyle (ör. DOA_SRC_CUSTOMER).
--  ÖNEK: büyük harf, '_' ile biten, şemada kimsenin kullanmadığı bir değer olmalı ve
--        dbt tarafındaki ODI_NAME_PREFIX ile AYNI olmalı.
--  SQL Developer: F5 (Run Script) ile çalıştır.  Bu dosya scripts/gen_sandbox_sql.py ile üretildi.
-- ============================================================================
SET DEFINE ON
SET VERIFY OFF
DEFINE P = DOA_


WHENEVER SQLERROR EXIT
BEGIN
  IF LENGTH('&P.') < 3 OR SUBSTR('&P.', -1) <> '_' OR '&P.' <> UPPER('&P.') THEN
    RAISE_APPLICATION_ERROR(-20900, 'Önek hatalı: en az 3 karakter, büyük harf, _ ile bitmeli. Şu an: &P.');
  END IF;
END;
/
WHENEVER SQLERROR CONTINUE

SET PAGESIZE 200
SET LINESIZE 200

PROMPT ================ ca_append_ckm  (&P.T_CA_APPEND_CLEAN)
PROMPT -- üstüne 5 temiz satır   ==> beklenen: 9
select count(*) from &P.T_CA_APPEND_CLEAN;
PROMPT -- E$ hata tipleri (bu run)   ==> beklenen: 6, NN | 7, FK | 8, CK
select cust_no, cons_type from "E$_&P.T_CA_APPEND_CLEAN" where odi_sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from &P.ODI_STEP_LOG where model_name like '%.&P.T_CA_APPEND_CLEAN') order by 1;

PROMPT ================ ca_truncate_insert  (&P.T_CA_SNAPSHOT)
PROMPT -- truncate + 8 satır (hatalılar dahil)   ==> beklenen: 8
select count(*) from &P.T_CA_SNAPSHOT;

PROMPT ================ iu_basic_ckm  (&P.T_IU)
PROMPT -- müşteriler   ==> beklenen: 1 | 2 | 3 | 4 | 5
select cust_no from &P.T_IU order by 1;
PROMPT -- güncellenenler (upd_dt dolu)   ==> beklenen: 1 | 2 | 4
select cust_no from &P.T_IU where upd_dt is not null order by 1;
PROMPT -- 1'in şehri   ==> beklenen: ANK
select city from &P.T_IU where cust_no = 1;
PROMPT -- E$ (bu run)   ==> beklenen: 6, NN | 7, FK | 8, CK
select cust_no, cons_type from "E$_&P.T_IU" where odi_sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from &P.ODI_STEP_LOG where model_name like '%.&P.T_IU') order by 1;
PROMPT -- step: Flag useless rows   ==> beklenen: 1
select sum(rows_affected) from &P.ODI_STEP_LOG where sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from &P.ODI_STEP_LOG where model_name like '%.&P.T_IU') and model_name like '%.&P.T_IU' and step_name = 'Flag useless rows';
PROMPT -- step: Update   ==> beklenen: 3
select sum(rows_affected) from &P.ODI_STEP_LOG where sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from &P.ODI_STEP_LOG where model_name like '%.&P.T_IU') and model_name like '%.&P.T_IU' and step_name = 'Update existing rows';
PROMPT -- step: Insert   ==> beklenen: 1
select sum(rows_affected) from &P.ODI_STEP_LOG where sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from &P.ODI_STEP_LOG where model_name like '%.&P.T_IU') and model_name like '%.&P.T_IU' and step_name = 'Insert new rows';

PROMPT ================ iu_cdc_delete  (&P.T_IU_CDC)
PROMPT -- 3 silindi, 5 ve 7 eklendi   ==> beklenen: 1 | 2 | 4 | 5 | 7
select cust_no from &P.T_IU_CDC order by 1;
PROMPT -- 1 güncellendi   ==> beklenen: ANK
select city from &P.T_IU_CDC where cust_no = 1;

PROMPT ================ iu_delete_missing_soft  (&P.T_IU_SOFT)
PROMPT -- 5 satır   ==> beklenen: 5
select count(*) from &P.T_IU_SOFT;
PROMPT -- 4 soft delete   ==> beklenen: 4
select cust_no from &P.T_IU_SOFT where is_deleted = 'Y';

PROMPT ================ iu_gtt_no_ddl  (&P.T_IU_GTT)
PROMPT -- T_IU ile fark yok   ==> beklenen: 0
select count(*) from (select cust_no, city, email, status from &P.T_IU minus select cust_no, city, email, status from &P.T_IU_GTT);
PROMPT -- E$ (bu run)   ==> beklenen: 3
select count(*) from "E$_&P.T_IU_GTT" where odi_sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from &P.ODI_STEP_LOG where model_name like '%.&P.T_IU_GTT');
PROMPT -- DDL atılmadı   ==> beklenen: 0
select count(*) from &P.ODI_STEP_LOG where sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from &P.ODI_STEP_LOG where model_name like '%.&P.T_IU_GTT') and model_name like '%.&P.T_IU_GTT' and (step_name like 'Create%' or step_name like 'Drop%');

PROMPT ================ iu_insert_only  (&P.T_IU_INS_ONLY)
PROMPT -- yeniler eklendi   ==> beklenen: 8
select count(*) from &P.T_IU_INS_ONLY;
PROMPT -- var olan güncellenmedi   ==> beklenen: IST
select city from &P.T_IU_INS_ONLY where cust_no = 1;

PROMPT ================ iu_recycle_errors  (&P.T_IU_RECYCLE)
PROMPT -- 7 girmedi   ==> beklenen: 1 | 2 | 3 | 4 | 5
select cust_no from &P.T_IU_RECYCLE order by 1;
PROMPT -- 7 E$'ta   ==> beklenen: 1
select count(*) from "E$_&P.T_IU_RECYCLE" where cust_no = 7;

PROMPT ================ iu_update_only  (&P.T_IU_UPD_ONLY)
PROMPT -- hâlâ 3   ==> beklenen: 3
select count(*) from &P.T_IU_UPD_ONLY;
PROMPT -- 1'in şehri   ==> beklenen: ANK
select city from &P.T_IU_UPD_ONLY where cust_no = 1;

PROMPT ================ mg_cdc_delete  (&P.T_MG_CDC)
PROMPT -- 3 silindi   ==> beklenen: 1 | 2 | 4 | 5 | 7
select cust_no from &P.T_MG_CDC order by 1;

PROMPT ================ mg_delete_missing  (&P.T_MG_SNAP)
PROMPT -- 4 silindi, 5 eklendi   ==> beklenen: 1 | 2 | 3 | 5
select cust_no from &P.T_MG_SNAP order by 1;

PROMPT ================ mg_direct  (&P.T_MG_DIRECT)
PROMPT -- satır   ==> beklenen: 8
select count(*) from &P.T_MG_DIRECT;
PROMPT -- güncellenenler   ==> beklenen: 1 | 2 | 4
select cust_no from &P.T_MG_DIRECT where upd_dt is not null order by 1;

PROMPT ================ mg_flow_ckm  (&P.T_MG_FLOW)
PROMPT -- müşteriler   ==> beklenen: 1 | 2 | 3 | 4 | 5 | 7
select cust_no from &P.T_MG_FLOW order by 1;
PROMPT -- E$ (bu run)   ==> beklenen: 6 | 8
select cust_no from "E$_&P.T_MG_FLOW" where odi_sess_no = (select max(sess_no) keep (dense_rank last order by log_date) from &P.ODI_STEP_LOG where model_name like '%.&P.T_MG_FLOW') order by 1;
PROMPT -- I$ artığı kalmadı   ==> beklenen: 0
select count(*) from user_tables where table_name like 'I$\_&P.T\_MG\_FLOW%' escape '\';

PROMPT ================ scd_close_missing  (&P.T_SCD_SNAP)
PROMPT -- toplam / current   ==> beklenen: 6, 4
select count(*), sum(curr_flag) from &P.T_SCD_SNAP;
PROMPT -- 4 kapandı   ==> beklenen: 0
select curr_flag from &P.T_SCD_SNAP where cust_no = 4;

PROMPT ================ scd_type2  (&P.T_SCD)
PROMPT -- toplam / current   ==> beklenen: 7, 6
select count(*), sum(curr_flag) from &P.T_SCD;
PROMPT -- 1'in versiyonları   ==> beklenen: IST, 0 | ANK, 1
select city, curr_flag from &P.T_SCD where cust_no = 1 order by eff_start_dt, cust_sk;
PROMPT -- eski versiyon kapandı   ==> beklenen: 1
select count(*) from &P.T_SCD where cust_no = 1 and curr_flag = 0 and eff_end_dt < date '2400-01-01';
PROMPT -- 2 tek satır, yeni email   ==> beklenen: 1, ayse.new@x.com
select count(*), max(email) from &P.T_SCD where cust_no = 2;

PROMPT ================ pt_daily_exchange  (&P.T_TXN_DAILY_X)
PROMPT -- toplam   ==> beklenen: 5
select count(*) from &P.T_TXN_DAILY_X;
PROMPT -- iki günlük partition   ==> beklenen: 2
select count(*) from user_tab_partitions where table_name = '&P.T_TXN_DAILY_X' and partition_name in ('P20261001', 'P20261002');
PROMPT -- local index usable   ==> beklenen: 0
select count(*) from user_ind_partitions where index_name = '&P.IX_T_TXN_DAILY_X_CUST' and status <> 'USABLE';

PROMPT ================ pt_daily_truncate  (&P.T_TXN_DAILY_TRUNC)
PROMPT -- toplam   ==> beklenen: 5
select count(*) from &P.T_TXN_DAILY_TRUNC;

PROMPT ================ pt_merge_prune  (&P.T_TXN_MERGE_PART)
PROMPT -- satır   ==> beklenen: 5
select count(*) from &P.T_TXN_MERGE_PART;

PROMPT ================ pt_monthly_delete  (&P.T_TXN_MONTHLY)
PROMPT -- Ekim   ==> beklenen: 5
select count(*) from &P.T_TXN_MONTHLY;

PROMPT ================ lkm_staging  (&P.T_LKM_CUST)
PROMPT -- satır   ==> beklenen: 8
select count(*) from &P.T_LKM_CUST;
PROMPT -- C$ silindi   ==> beklenen: 0
select count(*) from user_tables where table_name = 'C$_&P.T_LKM_CUST';

PROMPT ================ cust_fin_daily  (&P.DM_CUST_FIN_DAILY)
PROMPT -- satır   ==> beklenen: 5
select count(*) from &P.DM_CUST_FIN_DAILY;

PROMPT ================ cust_fin_daily_tmp01  (&P.T_CFD_TMP01)
PROMPT -- 10-02 müşterileri   ==> beklenen: 2
select count(*) from &P.T_CFD_TMP01;

PROMPT ================ cust_fin_daily_tmp02  (&P.T_CFD_TMP02)
PROMPT -- zenginleşti   ==> beklenen: 2
select count(*) from &P.T_CFD_TMP02 where cust_name is not null;
