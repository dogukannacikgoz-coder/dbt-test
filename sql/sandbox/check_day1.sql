-- ============================================================================
--  KONTROL — GÜN 1 (dbt run'dan sonra; sadece okur)
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
PROMPT -- satır   ==> beklenen: 4
select count(*) from &P.T_CA_APPEND_CLEAN;

PROMPT ================ ca_truncate_insert  (&P.T_CA_SNAPSHOT)
PROMPT -- satır sayısı   ==> beklenen: 4
select count(*) from &P.T_CA_SNAPSHOT;
PROMPT -- load_dt dolu   ==> beklenen: 0
select count(*) from &P.T_CA_SNAPSHOT where load_dt is null;

PROMPT ================ iu_basic_ckm  (&P.T_IU)
PROMPT -- satır   ==> beklenen: 4
select count(*) from &P.T_IU;
PROMPT -- ilk yüklemede update yok   ==> beklenen: 0
select count(*) from &P.T_IU where upd_dt is not null;

PROMPT ================ iu_cdc_delete  (&P.T_IU_CDC)
PROMPT -- müşteriler   ==> beklenen: 1 | 2 | 3 | 4
select cust_no from &P.T_IU_CDC order by 1;

PROMPT ================ iu_delete_missing_soft  (&P.T_IU_SOFT)
PROMPT -- hepsi aktif   ==> beklenen: 4
select count(*) from &P.T_IU_SOFT where is_deleted = 'N';

PROMPT ================ iu_gtt_no_ddl  (&P.T_IU_GTT)
PROMPT -- satır   ==> beklenen: 4
select count(*) from &P.T_IU_GTT;

PROMPT ================ iu_insert_only  (&P.T_IU_INS_ONLY)
PROMPT -- satır   ==> beklenen: 4
select count(*) from &P.T_IU_INS_ONLY;

PROMPT ================ iu_recycle_errors  (&P.T_IU_RECYCLE)
PROMPT -- satır   ==> beklenen: 4
select count(*) from &P.T_IU_RECYCLE;

PROMPT ================ iu_update_only  (&P.T_IU_UPD_ONLY)
PROMPT -- hâlâ 3 satır (insert yok)   ==> beklenen: 3
select count(*) from &P.T_IU_UPD_ONLY;
PROMPT -- isimler güncellendi   ==> beklenen: Ali
select cust_name from &P.T_IU_UPD_ONLY where cust_no = 1;

PROMPT ================ mg_cdc_delete  (&P.T_MG_CDC)
PROMPT -- müşteriler   ==> beklenen: 1 | 2 | 3 | 4
select cust_no from &P.T_MG_CDC order by 1;

PROMPT ================ mg_delete_missing  (&P.T_MG_SNAP)
PROMPT -- müşteriler   ==> beklenen: 1 | 2 | 3 | 4
select cust_no from &P.T_MG_SNAP order by 1;

PROMPT ================ mg_direct  (&P.T_MG_DIRECT)
PROMPT -- satır   ==> beklenen: 4
select count(*) from &P.T_MG_DIRECT;

PROMPT ================ mg_flow_ckm  (&P.T_MG_FLOW)
PROMPT -- satır   ==> beklenen: 4
select count(*) from &P.T_MG_FLOW;

PROMPT ================ scd_close_missing  (&P.T_SCD_SNAP)
PROMPT -- toplam / current   ==> beklenen: 4, 4
select count(*), sum(curr_flag) from &P.T_SCD_SNAP;

PROMPT ================ scd_type2  (&P.T_SCD)
PROMPT -- toplam / current   ==> beklenen: 4, 4
select count(*), sum(curr_flag) from &P.T_SCD;

PROMPT ================ pt_daily_exchange  (&P.T_TXN_DAILY_X)
PROMPT -- 10-01   ==> beklenen: 3
select count(*) from &P.T_TXN_DAILY_X where txn_date = date '2026-10-01';
PROMPT -- partition eklendi   ==> beklenen: 1
select count(*) from user_tab_partitions where table_name = '&P.T_TXN_DAILY_X' and partition_name = 'P20261001';

PROMPT ================ pt_daily_truncate  (&P.T_TXN_DAILY_TRUNC)
PROMPT -- 10-01   ==> beklenen: 3
select count(*) from &P.T_TXN_DAILY_TRUNC where txn_date = date '2026-10-01';
PROMPT -- 10-02 yüklenmedi   ==> beklenen: 0
select count(*) from &P.T_TXN_DAILY_TRUNC where txn_date = date '2026-10-02';

PROMPT ================ pt_merge_prune  (&P.T_TXN_MERGE_PART)
PROMPT -- satır   ==> beklenen: 3
select count(*) from &P.T_TXN_MERGE_PART;

PROMPT ================ pt_monthly_delete  (&P.T_TXN_MONTHLY)
PROMPT -- Ekim   ==> beklenen: 4
select count(*) from &P.T_TXN_MONTHLY where txn_date_key between 20261001 and 20261031;

PROMPT ================ lkm_staging  (&P.T_LKM_CUST)
PROMPT -- satır   ==> beklenen: 4
select count(*) from &P.T_LKM_CUST;

PROMPT ================ cust_fin_daily  (&P.DM_CUST_FIN_DAILY)
PROMPT -- satır   ==> beklenen: 3
select count(*) from &P.DM_CUST_FIN_DAILY;

PROMPT ================ cust_fin_daily_tmp01  (&P.T_CFD_TMP01)
PROMPT -- 10-01 müşterileri   ==> beklenen: 3
select count(*) from &P.T_CFD_TMP01;
