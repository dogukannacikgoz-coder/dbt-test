-- ============================================================================
--  01 — TEST TABLOLARINI YARAT (kaynaklar + step log + her modelin target'ı)
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


PROMPT == Kaynaklar + step log
CREATE TABLE &P.SRC_CUSTOMER (
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1));
CREATE TABLE &P.SRC_CUSTOMER_CDC (
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  op_type VARCHAR2(1));
CREATE TABLE &P.SRC_CUSTOMER_SNAP (
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1));
CREATE TABLE &P.SRC_TXN (
  txn_id NUMBER, cust_no NUMBER, txn_date DATE, amount NUMBER);
CREATE TABLE &P.D_BRANCH (branch_cd VARCHAR2(5) PRIMARY KEY);
CREATE TABLE &P.ODI_STEP_LOG (
  sess_no VARCHAR2(64), model_name VARCHAR2(256), km_name VARCHAR2(100), step_no NUMBER,
  step_name VARCHAR2(400), rows_affected NUMBER, duration_sec NUMBER, log_date TIMESTAMP);

PROMPT == ca_append_ckm  ->  &P.T_CA_APPEND_CLEAN
CREATE TABLE &P.T_CA_APPEND_CLEAN (
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  load_dt DATE);

PROMPT == ca_truncate_insert  ->  &P.T_CA_SNAPSHOT
CREATE TABLE &P.T_CA_SNAPSHOT (
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  load_dt DATE);

PROMPT == iu_basic_ckm  ->  &P.T_IU
CREATE TABLE &P.T_IU (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  ins_dt DATE, upd_dt DATE);

PROMPT == iu_cdc_delete  ->  &P.T_IU_CDC
CREATE TABLE &P.T_IU_CDC (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1), upd_dt DATE);

PROMPT == iu_delete_missing_soft  ->  &P.T_IU_SOFT
CREATE TABLE &P.T_IU_SOFT (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  is_deleted VARCHAR2(1), upd_dt DATE);

PROMPT == iu_gtt_no_ddl  ->  &P.T_IU_GTT
CREATE TABLE &P.T_IU_GTT (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  ins_dt DATE, upd_dt DATE);
CREATE GLOBAL TEMPORARY TABLE "I$_&P.T_IU_GTT" (
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  ind_update CHAR(1)
) ON COMMIT PRESERVE ROWS;
CREATE TABLE "E$_&P.T_IU_GTT" (
  odi_row_id VARCHAR2(64), err_type CHAR(1), err_mess VARCHAR2(250), check_date DATE,
  cons_name VARCHAR2(128), cons_type VARCHAR2(10), odi_sess_no VARCHAR2(64),
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1));

PROMPT == iu_insert_only  ->  &P.T_IU_INS_ONLY
CREATE TABLE &P.T_IU_INS_ONLY (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1), ins_dt DATE);

PROMPT == iu_recycle_errors  ->  &P.T_IU_RECYCLE
CREATE TABLE &P.T_IU_RECYCLE (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1));

PROMPT == iu_update_only  ->  &P.T_IU_UPD_ONLY
CREATE TABLE &P.T_IU_UPD_ONLY (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1), upd_dt DATE);
INSERT INTO &P.T_IU_UPD_ONLY (cust_no, cust_name, city)
SELECT 1, 'OLD', 'OLD' FROM dual UNION ALL SELECT 2, 'OLD', 'OLD' FROM dual UNION ALL SELECT 3, 'OLD', 'OLD' FROM dual;

PROMPT == mg_cdc_delete  ->  &P.T_MG_CDC
CREATE TABLE &P.T_MG_CDC (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1), upd_dt DATE);

PROMPT == mg_delete_missing  ->  &P.T_MG_SNAP
CREATE TABLE &P.T_MG_SNAP (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1));

PROMPT == mg_direct  ->  &P.T_MG_DIRECT
CREATE TABLE &P.T_MG_DIRECT (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  ins_dt DATE, upd_dt DATE);

PROMPT == mg_flow_ckm  ->  &P.T_MG_FLOW
CREATE TABLE &P.T_MG_FLOW (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1));

PROMPT == scd_close_missing  ->  &P.T_SCD_SNAP
CREATE TABLE &P.T_SCD_SNAP (
  cust_sk NUMBER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  cust_no NUMBER, cust_name VARCHAR2(50), city VARCHAR2(20), curr_flag NUMBER(1));

PROMPT == scd_type2  ->  &P.T_SCD
CREATE SEQUENCE &P.SEQ_T_SCD;
CREATE TABLE &P.T_SCD (
  cust_sk NUMBER PRIMARY KEY, cust_no NUMBER, cust_name VARCHAR2(50), email VARCHAR2(50),
  segment VARCHAR2(5), city VARCHAR2(20), curr_flag NUMBER(1), eff_start_dt DATE, eff_end_dt DATE);

PROMPT == pt_daily_exchange  ->  &P.T_TXN_DAILY_X
CREATE TABLE &P.T_TXN_DAILY_X (
  txn_id NUMBER, cust_no NUMBER, txn_date DATE, amount NUMBER, load_dt DATE)
PARTITION BY RANGE (txn_date)
( PARTITION p0 VALUES LESS THAN (DATE '2026-01-01') );
CREATE INDEX &P.IX_T_TXN_DAILY_X_CUST ON &P.T_TXN_DAILY_X (cust_no) LOCAL;

PROMPT == pt_daily_truncate  ->  &P.T_TXN_DAILY_TRUNC
CREATE TABLE &P.T_TXN_DAILY_TRUNC (
  txn_id NUMBER, cust_no NUMBER, txn_date DATE, amount NUMBER, load_dt DATE)
PARTITION BY RANGE (txn_date) INTERVAL (NUMTODSINTERVAL(1, 'DAY'))
( PARTITION p0 VALUES LESS THAN (DATE '2026-01-01') );

PROMPT == pt_merge_prune  ->  &P.T_TXN_MERGE_PART
CREATE TABLE &P.T_TXN_MERGE_PART (
  txn_id NUMBER, cust_no NUMBER, txn_date DATE, amount NUMBER, upd_dt DATE)
PARTITION BY RANGE (txn_date) INTERVAL (NUMTODSINTERVAL(1, 'DAY'))
( PARTITION p0 VALUES LESS THAN (DATE '2026-01-01') );

PROMPT == pt_monthly_delete  ->  &P.T_TXN_MONTHLY
CREATE TABLE &P.T_TXN_MONTHLY (
  txn_id NUMBER, cust_no NUMBER, txn_date_key NUMBER(8), amount NUMBER)
PARTITION BY RANGE (txn_date_key) INTERVAL (100)
( PARTITION p0 VALUES LESS THAN (20260101) );

PROMPT == lkm_staging  ->  &P.T_LKM_CUST
CREATE TABLE &P.T_LKM_CUST (
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1));

PROMPT == cust_fin_daily  ->  &P.DM_CUST_FIN_DAILY
CREATE TABLE &P.DM_CUST_FIN_DAILY (
  snapshot_date DATE, cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5),
  branch_cd VARCHAR2(5), txn_cnt NUMBER, txn_amt NUMBER, ins_dt DATE, upd_dt DATE)
PARTITION BY RANGE (snapshot_date) INTERVAL (NUMTODSINTERVAL(1, 'DAY'))
( PARTITION p0 VALUES LESS THAN (DATE '2026-01-01') );

PROMPT == cust_fin_daily_tmp01  ->  &P.T_CFD_TMP01
CREATE TABLE &P.T_CFD_TMP01 (
  snapshot_date DATE, cust_no NUMBER, txn_cnt NUMBER, txn_amt NUMBER);

PROMPT == cust_fin_daily_tmp02  ->  &P.T_CFD_TMP02
CREATE TABLE &P.T_CFD_TMP02 (
  snapshot_date DATE, cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5),
  branch_cd VARCHAR2(5), txn_cnt NUMBER, txn_amt NUMBER);
COMMIT;
