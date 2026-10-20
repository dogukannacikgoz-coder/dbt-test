-- ============================================================================
--  KONTROL — GÜN 1 (dbt run'dan sonra; sadece okur)
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
-- -- satır   ==> beklenen: 4
select count(*) from DOA_T_CA_APPEND_CLEAN;

-- ================ ca_truncate_insert  (DOA_T_CA_SNAPSHOT)
-- -- satır sayısı   ==> beklenen: 4
select count(*) from DOA_T_CA_SNAPSHOT;
-- -- load_dt dolu   ==> beklenen: 0
select count(*) from DOA_T_CA_SNAPSHOT where load_dt is null;

-- ================ iu_basic_ckm  (DOA_T_IU)
-- -- satır   ==> beklenen: 4
select count(*) from DOA_T_IU;
-- -- ilk yüklemede update yok   ==> beklenen: 0
select count(*) from DOA_T_IU where upd_dt is not null;

-- ================ iu_cdc_delete  (DOA_T_IU_CDC)
-- -- müşteriler   ==> beklenen: 1 | 2 | 3 | 4
select cust_no from DOA_T_IU_CDC order by 1;

-- ================ iu_delete_missing_soft  (DOA_T_IU_SOFT)
-- -- hepsi aktif   ==> beklenen: 4
select count(*) from DOA_T_IU_SOFT where is_deleted = 'N';

-- ================ iu_gtt_no_ddl  (DOA_T_IU_GTT)
-- -- satır   ==> beklenen: 4
select count(*) from DOA_T_IU_GTT;

-- ================ iu_insert_only  (DOA_T_IU_INS_ONLY)
-- -- satır   ==> beklenen: 4
select count(*) from DOA_T_IU_INS_ONLY;

-- ================ iu_recycle_errors  (DOA_T_IU_RECYCLE)
-- -- satır   ==> beklenen: 4
select count(*) from DOA_T_IU_RECYCLE;

-- ================ iu_update_only  (DOA_T_IU_UPD_ONLY)
-- -- hâlâ 3 satır (insert yok)   ==> beklenen: 3
select count(*) from DOA_T_IU_UPD_ONLY;
-- -- isimler güncellendi   ==> beklenen: Ali
select cust_name from DOA_T_IU_UPD_ONLY where cust_no = 1;

-- ================ mg_cdc_delete  (DOA_T_MG_CDC)
-- -- müşteriler   ==> beklenen: 1 | 2 | 3 | 4
select cust_no from DOA_T_MG_CDC order by 1;

-- ================ mg_delete_missing  (DOA_T_MG_SNAP)
-- -- müşteriler   ==> beklenen: 1 | 2 | 3 | 4
select cust_no from DOA_T_MG_SNAP order by 1;

-- ================ mg_direct  (DOA_T_MG_DIRECT)
-- -- satır   ==> beklenen: 4
select count(*) from DOA_T_MG_DIRECT;

-- ================ mg_flow_ckm  (DOA_T_MG_FLOW)
-- -- satır   ==> beklenen: 4
select count(*) from DOA_T_MG_FLOW;

-- ================ scd_close_missing  (DOA_T_SCD_SNAP)
-- -- toplam / current   ==> beklenen: 4, 4
select count(*), sum(curr_flag) from DOA_T_SCD_SNAP;

-- ================ scd_type2  (DOA_T_SCD)
-- -- toplam / current   ==> beklenen: 4, 4
select count(*), sum(curr_flag) from DOA_T_SCD;

-- ================ pt_daily_exchange  (DOA_T_TXN_DAILY_X)
-- -- 10-01   ==> beklenen: 3
select count(*) from DOA_T_TXN_DAILY_X where txn_date = date '2026-10-01';
-- -- partition eklendi   ==> beklenen: 1
select count(*) from all_tab_partitions where table_owner = sys_context('USERENV', 'CURRENT_SCHEMA') and table_name = 'DOA_T_TXN_DAILY_X' and partition_name = 'P20261001';

-- ================ pt_daily_truncate  (DOA_T_TXN_DAILY_TRUNC)
-- -- 10-01   ==> beklenen: 3
select count(*) from DOA_T_TXN_DAILY_TRUNC where txn_date = date '2026-10-01';
-- -- 10-02 yüklenmedi   ==> beklenen: 0
select count(*) from DOA_T_TXN_DAILY_TRUNC where txn_date = date '2026-10-02';

-- ================ pt_merge_prune  (DOA_T_TXN_MERGE_PART)
-- -- satır   ==> beklenen: 3
select count(*) from DOA_T_TXN_MERGE_PART;

-- ================ pt_monthly_delete  (DOA_T_TXN_MONTHLY)
-- -- Ekim   ==> beklenen: 4
select count(*) from DOA_T_TXN_MONTHLY where txn_date_key between 20261001 and 20261031;

-- ================ lkm_staging  (DOA_T_LKM_CUST)
-- -- satır   ==> beklenen: 4
select count(*) from DOA_T_LKM_CUST;

-- ================ cust_fin_daily  (DOA_DM_CUST_FIN_DAILY)
-- -- satır   ==> beklenen: 3
select count(*) from DOA_DM_CUST_FIN_DAILY;

-- ================ cust_fin_daily_tmp01  (DOA_T_CFD_TMP01)
-- -- 10-01 müşterileri   ==> beklenen: 3
select count(*) from DOA_T_CFD_TMP01;
