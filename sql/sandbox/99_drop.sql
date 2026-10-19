-- ============================================================================
--  99 — TEMİZLİK: sadece bu testin yarattığı, ADI TEK TEK YAZILI nesneleri siler
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


-- Şema taraması / LIKE deseni YOK. Aşağıdaki liste dışında hiçbir şeye dokunulmaz.
-- Hepsi &P. önekli: başka birinin tablosu bu isimlerle eşleşemez (00_precheck boş döndüyse).
DECLARE
  PROCEDURE drop_tab(p_name VARCHAR2, p_gtt BOOLEAN DEFAULT FALSE) IS
  BEGIN
    IF p_gtt THEN
      BEGIN EXECUTE IMMEDIATE 'TRUNCATE TABLE "' || p_name || '"';
      EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
    END IF;
    EXECUTE IMMEDIATE 'DROP TABLE "' || p_name || '" PURGE';
    DBMS_OUTPUT.PUT_LINE('dropped ' || p_name);
  EXCEPTION WHEN OTHERS THEN
    IF SQLCODE != -942 THEN RAISE; END IF;   -- yoksa geç
  END;
BEGIN
  drop_tab('I$_&P.T_IU_GTT', TRUE);
  drop_tab('E$_&P.T_IU_GTT', TRUE);
  drop_tab('I$_&P.T_CA_APPEND_CLEAN');
  drop_tab('C$_&P.T_CA_APPEND_CLEAN');
  drop_tab('X$_&P.T_CA_APPEND_CLEAN');
  drop_tab('E$_&P.T_CA_APPEND_CLEAN');
  drop_tab('I$_&P.T_CA_SNAPSHOT');
  drop_tab('C$_&P.T_CA_SNAPSHOT');
  drop_tab('X$_&P.T_CA_SNAPSHOT');
  drop_tab('E$_&P.T_CA_SNAPSHOT');
  drop_tab('I$_&P.T_IU');
  drop_tab('C$_&P.T_IU');
  drop_tab('X$_&P.T_IU');
  drop_tab('E$_&P.T_IU');
  drop_tab('I$_&P.T_IU_CDC');
  drop_tab('C$_&P.T_IU_CDC');
  drop_tab('X$_&P.T_IU_CDC');
  drop_tab('E$_&P.T_IU_CDC');
  drop_tab('I$_&P.T_IU_SOFT');
  drop_tab('C$_&P.T_IU_SOFT');
  drop_tab('X$_&P.T_IU_SOFT');
  drop_tab('E$_&P.T_IU_SOFT');
  drop_tab('C$_&P.T_IU_GTT');
  drop_tab('X$_&P.T_IU_GTT');
  drop_tab('I$_&P.T_IU_INS_ONLY');
  drop_tab('C$_&P.T_IU_INS_ONLY');
  drop_tab('X$_&P.T_IU_INS_ONLY');
  drop_tab('E$_&P.T_IU_INS_ONLY');
  drop_tab('I$_&P.T_IU_RECYCLE');
  drop_tab('C$_&P.T_IU_RECYCLE');
  drop_tab('X$_&P.T_IU_RECYCLE');
  drop_tab('E$_&P.T_IU_RECYCLE');
  drop_tab('I$_&P.T_IU_UPD_ONLY');
  drop_tab('C$_&P.T_IU_UPD_ONLY');
  drop_tab('X$_&P.T_IU_UPD_ONLY');
  drop_tab('E$_&P.T_IU_UPD_ONLY');
  drop_tab('I$_&P.T_MG_CDC');
  drop_tab('C$_&P.T_MG_CDC');
  drop_tab('X$_&P.T_MG_CDC');
  drop_tab('E$_&P.T_MG_CDC');
  drop_tab('I$_&P.T_MG_SNAP');
  drop_tab('C$_&P.T_MG_SNAP');
  drop_tab('X$_&P.T_MG_SNAP');
  drop_tab('E$_&P.T_MG_SNAP');
  drop_tab('I$_&P.T_MG_DIRECT');
  drop_tab('C$_&P.T_MG_DIRECT');
  drop_tab('X$_&P.T_MG_DIRECT');
  drop_tab('E$_&P.T_MG_DIRECT');
  drop_tab('I$_&P.T_MG_FLOW');
  drop_tab('C$_&P.T_MG_FLOW');
  drop_tab('X$_&P.T_MG_FLOW');
  drop_tab('E$_&P.T_MG_FLOW');
  drop_tab('I$_&P.T_SCD_SNAP');
  drop_tab('C$_&P.T_SCD_SNAP');
  drop_tab('X$_&P.T_SCD_SNAP');
  drop_tab('E$_&P.T_SCD_SNAP');
  drop_tab('I$_&P.T_SCD');
  drop_tab('C$_&P.T_SCD');
  drop_tab('X$_&P.T_SCD');
  drop_tab('E$_&P.T_SCD');
  drop_tab('I$_&P.T_TXN_DAILY_X');
  drop_tab('C$_&P.T_TXN_DAILY_X');
  drop_tab('X$_&P.T_TXN_DAILY_X');
  drop_tab('E$_&P.T_TXN_DAILY_X');
  drop_tab('I$_&P.T_TXN_DAILY_TRUNC');
  drop_tab('C$_&P.T_TXN_DAILY_TRUNC');
  drop_tab('X$_&P.T_TXN_DAILY_TRUNC');
  drop_tab('E$_&P.T_TXN_DAILY_TRUNC');
  drop_tab('I$_&P.T_TXN_MERGE_PART');
  drop_tab('C$_&P.T_TXN_MERGE_PART');
  drop_tab('X$_&P.T_TXN_MERGE_PART');
  drop_tab('E$_&P.T_TXN_MERGE_PART');
  drop_tab('I$_&P.T_TXN_MONTHLY');
  drop_tab('C$_&P.T_TXN_MONTHLY');
  drop_tab('X$_&P.T_TXN_MONTHLY');
  drop_tab('E$_&P.T_TXN_MONTHLY');
  drop_tab('I$_&P.T_LKM_CUST');
  drop_tab('C$_&P.T_LKM_CUST');
  drop_tab('X$_&P.T_LKM_CUST');
  drop_tab('E$_&P.T_LKM_CUST');
  drop_tab('I$_&P.DM_CUST_FIN_DAILY');
  drop_tab('C$_&P.DM_CUST_FIN_DAILY');
  drop_tab('X$_&P.DM_CUST_FIN_DAILY');
  drop_tab('E$_&P.DM_CUST_FIN_DAILY');
  drop_tab('I$_&P.T_CFD_TMP01');
  drop_tab('C$_&P.T_CFD_TMP01');
  drop_tab('X$_&P.T_CFD_TMP01');
  drop_tab('E$_&P.T_CFD_TMP01');
  drop_tab('I$_&P.T_CFD_TMP02');
  drop_tab('C$_&P.T_CFD_TMP02');
  drop_tab('X$_&P.T_CFD_TMP02');
  drop_tab('E$_&P.T_CFD_TMP02');
  drop_tab('&P.SRC_CUSTOMER');
  drop_tab('&P.SRC_CUSTOMER_CDC');
  drop_tab('&P.SRC_CUSTOMER_SNAP');
  drop_tab('&P.SRC_TXN');
  drop_tab('&P.D_BRANCH');
  drop_tab('&P.ODI_STEP_LOG');
  drop_tab('&P.T_CA_APPEND_CLEAN');
  drop_tab('&P.T_CA_SNAPSHOT');
  drop_tab('&P.T_IU');
  drop_tab('&P.T_IU_CDC');
  drop_tab('&P.T_IU_SOFT');
  drop_tab('&P.T_IU_GTT');
  drop_tab('&P.T_IU_INS_ONLY');
  drop_tab('&P.T_IU_RECYCLE');
  drop_tab('&P.T_IU_UPD_ONLY');
  drop_tab('&P.T_MG_CDC');
  drop_tab('&P.T_MG_SNAP');
  drop_tab('&P.T_MG_DIRECT');
  drop_tab('&P.T_MG_FLOW');
  drop_tab('&P.T_SCD_SNAP');
  drop_tab('&P.T_SCD');
  drop_tab('&P.T_TXN_DAILY_X');
  drop_tab('&P.T_TXN_DAILY_TRUNC');
  drop_tab('&P.T_TXN_MERGE_PART');
  drop_tab('&P.T_TXN_MONTHLY');
  drop_tab('&P.T_LKM_CUST');
  drop_tab('&P.DM_CUST_FIN_DAILY');
  drop_tab('&P.T_CFD_TMP01');
  drop_tab('&P.T_CFD_TMP02');
END;
/
BEGIN EXECUTE IMMEDIATE 'DROP SEQUENCE "&P.SEQ_T_SCD"';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -2289 THEN RAISE; END IF; END;
/

PROMPT == Kalan (olmamalı; mg_flow_ckm fail olduysa I$_&P.T_MG_FLOW_xxxxxx kalabilir, elle drop et)
SELECT object_type, object_name FROM user_objects
 WHERE SUBSTR(object_name, 1, LENGTH('&P.')) = '&P.'
    OR SUBSTR(object_name, 1, 3 + LENGTH('&P.')) IN ('I$_&P.', 'C$_&P.', 'X$_&P.', 'E$_&P.')
 ORDER BY 2;
