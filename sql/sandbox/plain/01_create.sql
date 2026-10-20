-- ============================================================================
--  01 — TEST TABLOLARINI YARAT (kaynaklar + step log + her modelin target'ı)
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


-- == Kaynaklar + step log
CREATE TABLE DOA_SRC_CUSTOMER (
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1));
CREATE TABLE DOA_SRC_CUSTOMER_CDC (
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  op_type VARCHAR2(1));
CREATE TABLE DOA_SRC_CUSTOMER_SNAP (
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1));
CREATE TABLE DOA_SRC_TXN (
  txn_id NUMBER, cust_no NUMBER, txn_date DATE, amount NUMBER);
CREATE TABLE DOA_D_BRANCH (branch_cd VARCHAR2(5) PRIMARY KEY);
CREATE TABLE DOA_ODI_STEP_LOG (
  sess_no VARCHAR2(64), model_name VARCHAR2(256), km_name VARCHAR2(100), step_no NUMBER,
  step_name VARCHAR2(400), rows_affected NUMBER, duration_sec NUMBER, log_date TIMESTAMP);

-- == ca_append_ckm  ->  DOA_T_CA_APPEND_CLEAN
CREATE TABLE DOA_T_CA_APPEND_CLEAN (
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  load_dt DATE);

-- == ca_truncate_insert  ->  DOA_T_CA_SNAPSHOT
CREATE TABLE DOA_T_CA_SNAPSHOT (
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  load_dt DATE);

-- == iu_basic_ckm  ->  DOA_T_IU
CREATE TABLE DOA_T_IU (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  ins_dt DATE, upd_dt DATE);

-- == iu_cdc_delete  ->  DOA_T_IU_CDC
CREATE TABLE DOA_T_IU_CDC (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1), upd_dt DATE);

-- == iu_delete_missing_soft  ->  DOA_T_IU_SOFT
CREATE TABLE DOA_T_IU_SOFT (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  is_deleted VARCHAR2(1), upd_dt DATE);

-- == iu_gtt_no_ddl  ->  DOA_T_IU_GTT
CREATE TABLE DOA_T_IU_GTT (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  ins_dt DATE, upd_dt DATE);
CREATE GLOBAL TEMPORARY TABLE "I$_DOA_T_IU_GTT" (
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  ind_update CHAR(1)
) ON COMMIT PRESERVE ROWS;
CREATE TABLE "E$_DOA_T_IU_GTT" (
  odi_row_id VARCHAR2(64), err_type CHAR(1), err_mess VARCHAR2(250), check_date DATE,
  cons_name VARCHAR2(128), cons_type VARCHAR2(10), odi_sess_no VARCHAR2(64),
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1));

-- == iu_insert_only  ->  DOA_T_IU_INS_ONLY
CREATE TABLE DOA_T_IU_INS_ONLY (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1), ins_dt DATE);

-- == iu_recycle_errors  ->  DOA_T_IU_RECYCLE
CREATE TABLE DOA_T_IU_RECYCLE (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1));

-- == iu_update_only  ->  DOA_T_IU_UPD_ONLY
CREATE TABLE DOA_T_IU_UPD_ONLY (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1), upd_dt DATE);
INSERT INTO DOA_T_IU_UPD_ONLY (cust_no, cust_name, city)
SELECT 1, 'OLD', 'OLD' FROM dual UNION ALL SELECT 2, 'OLD', 'OLD' FROM dual UNION ALL SELECT 3, 'OLD', 'OLD' FROM dual;

-- == mg_cdc_delete  ->  DOA_T_MG_CDC
CREATE TABLE DOA_T_MG_CDC (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1), upd_dt DATE);

-- == mg_delete_missing  ->  DOA_T_MG_SNAP
CREATE TABLE DOA_T_MG_SNAP (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1));

-- == mg_direct  ->  DOA_T_MG_DIRECT
CREATE TABLE DOA_T_MG_DIRECT (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  ins_dt DATE, upd_dt DATE);

-- == mg_flow_ckm  ->  DOA_T_MG_FLOW
CREATE TABLE DOA_T_MG_FLOW (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1));

-- == scd_close_missing  ->  DOA_T_SCD_SNAP
CREATE TABLE DOA_T_SCD_SNAP (
  cust_sk NUMBER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  cust_no NUMBER, cust_name VARCHAR2(50), city VARCHAR2(20), curr_flag NUMBER(1));

-- == scd_type2  ->  DOA_T_SCD
CREATE SEQUENCE DOA_SEQ_T_SCD;
CREATE TABLE DOA_T_SCD (
  cust_sk NUMBER PRIMARY KEY, cust_no NUMBER, cust_name VARCHAR2(50), email VARCHAR2(50),
  segment VARCHAR2(5), city VARCHAR2(20), curr_flag NUMBER(1), eff_start_dt DATE, eff_end_dt DATE);

-- == pt_daily_exchange  ->  DOA_T_TXN_DAILY_X
CREATE TABLE DOA_T_TXN_DAILY_X (
  txn_id NUMBER, cust_no NUMBER, txn_date DATE, amount NUMBER, load_dt DATE)
PARTITION BY RANGE (txn_date)
( PARTITION p0 VALUES LESS THAN (DATE '2026-01-01') );
CREATE INDEX DOA_IX_T_TXN_DAILY_X_CUST ON DOA_T_TXN_DAILY_X (cust_no) LOCAL;

-- == pt_daily_truncate  ->  DOA_T_TXN_DAILY_TRUNC
CREATE TABLE DOA_T_TXN_DAILY_TRUNC (
  txn_id NUMBER, cust_no NUMBER, txn_date DATE, amount NUMBER, load_dt DATE)
PARTITION BY RANGE (txn_date) INTERVAL (NUMTODSINTERVAL(1, 'DAY'))
( PARTITION p0 VALUES LESS THAN (DATE '2026-01-01') );

-- == pt_merge_prune  ->  DOA_T_TXN_MERGE_PART
CREATE TABLE DOA_T_TXN_MERGE_PART (
  txn_id NUMBER, cust_no NUMBER, txn_date DATE, amount NUMBER, upd_dt DATE)
PARTITION BY RANGE (txn_date) INTERVAL (NUMTODSINTERVAL(1, 'DAY'))
( PARTITION p0 VALUES LESS THAN (DATE '2026-01-01') );

-- == pt_monthly_delete  ->  DOA_T_TXN_MONTHLY
CREATE TABLE DOA_T_TXN_MONTHLY (
  txn_id NUMBER, cust_no NUMBER, txn_date_key NUMBER(8), amount NUMBER)
PARTITION BY RANGE (txn_date_key) INTERVAL (100)
( PARTITION p0 VALUES LESS THAN (20260101) );

-- == lkm_staging  ->  DOA_T_LKM_CUST
CREATE TABLE DOA_T_LKM_CUST (
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1));

-- == cust_fin_daily  ->  DOA_DM_CUST_FIN_DAILY
CREATE TABLE DOA_DM_CUST_FIN_DAILY (
  snapshot_date DATE, cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5),
  branch_cd VARCHAR2(5), txn_cnt NUMBER, txn_amt NUMBER, ins_dt DATE, upd_dt DATE)
PARTITION BY RANGE (snapshot_date) INTERVAL (NUMTODSINTERVAL(1, 'DAY'))
( PARTITION p0 VALUES LESS THAN (DATE '2026-01-01') );

-- == cust_fin_daily_tmp01  ->  DOA_T_CFD_TMP01
CREATE TABLE DOA_T_CFD_TMP01 (
  snapshot_date DATE, cust_no NUMBER, txn_cnt NUMBER, txn_amt NUMBER);

-- == cust_fin_daily_tmp02  ->  DOA_T_CFD_TMP02
CREATE TABLE DOA_T_CFD_TMP02 (
  snapshot_date DATE, cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5),
  branch_cd VARCHAR2(5), txn_cnt NUMBER, txn_amt NUMBER);
COMMIT;
