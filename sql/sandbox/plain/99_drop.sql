-- ============================================================================
--  99 — TEMİZLİK: sadece bu testin yarattığı, ADI TEK TEK YAZILI nesneleri siler
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


-- Şema taraması / LIKE deseni YOK. Aşağıdaki liste dışında hiçbir şeye dokunulmaz.
-- Hepsi DOA_ önekli: başka birinin tablosu bu isimlerle eşleşemez (00_precheck boş döndüyse).
DECLARE
  PROCEDURE drop_tab(p_name VARCHAR2, p_gtt BOOLEAN DEFAULT FALSE) IS
  BEGIN
    IF p_gtt THEN
      BEGIN EXECUTE IMMEDIATE 'TRUNCATE TABLE "GLOBAL_DWH"."' || p_name || '"';
      EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
    END IF;
    EXECUTE IMMEDIATE 'DROP TABLE "GLOBAL_DWH"."' || p_name || '" PURGE';
    DBMS_OUTPUT.PUT_LINE('dropped ' || p_name);
  EXCEPTION WHEN OTHERS THEN
    IF SQLCODE != -942 THEN RAISE; END IF;   -- yoksa geç
  END;
BEGIN
  drop_tab('I$_DOA_T_IU_GTT', TRUE);
  drop_tab('E$_DOA_T_IU_GTT', TRUE);
  drop_tab('I$_DOA_T_CA_APPEND_CLEAN');
  drop_tab('C$_DOA_T_CA_APPEND_CLEAN');
  drop_tab('X$_DOA_T_CA_APPEND_CLEAN');
  drop_tab('E$_DOA_T_CA_APPEND_CLEAN');
  drop_tab('I$_DOA_T_CA_SNAPSHOT');
  drop_tab('C$_DOA_T_CA_SNAPSHOT');
  drop_tab('X$_DOA_T_CA_SNAPSHOT');
  drop_tab('E$_DOA_T_CA_SNAPSHOT');
  drop_tab('I$_DOA_T_IU');
  drop_tab('C$_DOA_T_IU');
  drop_tab('X$_DOA_T_IU');
  drop_tab('E$_DOA_T_IU');
  drop_tab('I$_DOA_T_IU_CDC');
  drop_tab('C$_DOA_T_IU_CDC');
  drop_tab('X$_DOA_T_IU_CDC');
  drop_tab('E$_DOA_T_IU_CDC');
  drop_tab('I$_DOA_T_IU_SOFT');
  drop_tab('C$_DOA_T_IU_SOFT');
  drop_tab('X$_DOA_T_IU_SOFT');
  drop_tab('E$_DOA_T_IU_SOFT');
  drop_tab('C$_DOA_T_IU_GTT');
  drop_tab('X$_DOA_T_IU_GTT');
  drop_tab('I$_DOA_T_IU_INS_ONLY');
  drop_tab('C$_DOA_T_IU_INS_ONLY');
  drop_tab('X$_DOA_T_IU_INS_ONLY');
  drop_tab('E$_DOA_T_IU_INS_ONLY');
  drop_tab('I$_DOA_T_IU_RECYCLE');
  drop_tab('C$_DOA_T_IU_RECYCLE');
  drop_tab('X$_DOA_T_IU_RECYCLE');
  drop_tab('E$_DOA_T_IU_RECYCLE');
  drop_tab('I$_DOA_T_IU_UPD_ONLY');
  drop_tab('C$_DOA_T_IU_UPD_ONLY');
  drop_tab('X$_DOA_T_IU_UPD_ONLY');
  drop_tab('E$_DOA_T_IU_UPD_ONLY');
  drop_tab('I$_DOA_T_MG_CDC');
  drop_tab('C$_DOA_T_MG_CDC');
  drop_tab('X$_DOA_T_MG_CDC');
  drop_tab('E$_DOA_T_MG_CDC');
  drop_tab('I$_DOA_T_MG_SNAP');
  drop_tab('C$_DOA_T_MG_SNAP');
  drop_tab('X$_DOA_T_MG_SNAP');
  drop_tab('E$_DOA_T_MG_SNAP');
  drop_tab('I$_DOA_T_MG_DIRECT');
  drop_tab('C$_DOA_T_MG_DIRECT');
  drop_tab('X$_DOA_T_MG_DIRECT');
  drop_tab('E$_DOA_T_MG_DIRECT');
  drop_tab('I$_DOA_T_MG_FLOW');
  drop_tab('C$_DOA_T_MG_FLOW');
  drop_tab('X$_DOA_T_MG_FLOW');
  drop_tab('E$_DOA_T_MG_FLOW');
  drop_tab('I$_DOA_T_SCD_SNAP');
  drop_tab('C$_DOA_T_SCD_SNAP');
  drop_tab('X$_DOA_T_SCD_SNAP');
  drop_tab('E$_DOA_T_SCD_SNAP');
  drop_tab('I$_DOA_T_SCD');
  drop_tab('C$_DOA_T_SCD');
  drop_tab('X$_DOA_T_SCD');
  drop_tab('E$_DOA_T_SCD');
  drop_tab('I$_DOA_T_TXN_DAILY_X');
  drop_tab('C$_DOA_T_TXN_DAILY_X');
  drop_tab('X$_DOA_T_TXN_DAILY_X');
  drop_tab('E$_DOA_T_TXN_DAILY_X');
  drop_tab('I$_DOA_T_TXN_DAILY_TRUNC');
  drop_tab('C$_DOA_T_TXN_DAILY_TRUNC');
  drop_tab('X$_DOA_T_TXN_DAILY_TRUNC');
  drop_tab('E$_DOA_T_TXN_DAILY_TRUNC');
  drop_tab('I$_DOA_T_TXN_MERGE_PART');
  drop_tab('C$_DOA_T_TXN_MERGE_PART');
  drop_tab('X$_DOA_T_TXN_MERGE_PART');
  drop_tab('E$_DOA_T_TXN_MERGE_PART');
  drop_tab('I$_DOA_T_TXN_MONTHLY');
  drop_tab('C$_DOA_T_TXN_MONTHLY');
  drop_tab('X$_DOA_T_TXN_MONTHLY');
  drop_tab('E$_DOA_T_TXN_MONTHLY');
  drop_tab('I$_DOA_T_LKM_CUST');
  drop_tab('C$_DOA_T_LKM_CUST');
  drop_tab('X$_DOA_T_LKM_CUST');
  drop_tab('E$_DOA_T_LKM_CUST');
  drop_tab('I$_DOA_DM_CUST_FIN_DAILY');
  drop_tab('C$_DOA_DM_CUST_FIN_DAILY');
  drop_tab('X$_DOA_DM_CUST_FIN_DAILY');
  drop_tab('E$_DOA_DM_CUST_FIN_DAILY');
  drop_tab('I$_DOA_T_CFD_TMP01');
  drop_tab('C$_DOA_T_CFD_TMP01');
  drop_tab('X$_DOA_T_CFD_TMP01');
  drop_tab('E$_DOA_T_CFD_TMP01');
  drop_tab('I$_DOA_T_CFD_TMP02');
  drop_tab('C$_DOA_T_CFD_TMP02');
  drop_tab('X$_DOA_T_CFD_TMP02');
  drop_tab('E$_DOA_T_CFD_TMP02');
  drop_tab('DOA_SRC_CUSTOMER');
  drop_tab('DOA_SRC_CUSTOMER_CDC');
  drop_tab('DOA_SRC_CUSTOMER_SNAP');
  drop_tab('DOA_SRC_TXN');
  drop_tab('DOA_D_BRANCH');
  drop_tab('DOA_ODI_STEP_LOG');
  drop_tab('DOA_T_CA_APPEND_CLEAN');
  drop_tab('DOA_T_CA_SNAPSHOT');
  drop_tab('DOA_T_IU');
  drop_tab('DOA_T_IU_CDC');
  drop_tab('DOA_T_IU_SOFT');
  drop_tab('DOA_T_IU_GTT');
  drop_tab('DOA_T_IU_INS_ONLY');
  drop_tab('DOA_T_IU_RECYCLE');
  drop_tab('DOA_T_IU_UPD_ONLY');
  drop_tab('DOA_T_MG_CDC');
  drop_tab('DOA_T_MG_SNAP');
  drop_tab('DOA_T_MG_DIRECT');
  drop_tab('DOA_T_MG_FLOW');
  drop_tab('DOA_T_SCD_SNAP');
  drop_tab('DOA_T_SCD');
  drop_tab('DOA_T_TXN_DAILY_X');
  drop_tab('DOA_T_TXN_DAILY_TRUNC');
  drop_tab('DOA_T_TXN_MERGE_PART');
  drop_tab('DOA_T_TXN_MONTHLY');
  drop_tab('DOA_T_LKM_CUST');
  drop_tab('DOA_DM_CUST_FIN_DAILY');
  drop_tab('DOA_T_CFD_TMP01');
  drop_tab('DOA_T_CFD_TMP02');
END;
/
BEGIN EXECUTE IMMEDIATE 'DROP SEQUENCE "GLOBAL_DWH"."DOA_SEQ_T_SCD"';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -2289 THEN RAISE; END IF; END;
/

-- == Kalan (olmamalı; mg_flow_ckm fail olduysa I$_DOA_T_MG_FLOW_xxxxxx kalabilir, elle drop et)
SELECT object_type, object_name FROM all_objects
 WHERE owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
   AND (SUBSTR(object_name, 1, LENGTH('DOA_')) = 'DOA_'
    OR SUBSTR(object_name, 1, 3 + LENGTH('DOA_')) IN ('I$_DOA_', 'C$_DOA_', 'X$_DOA_', 'E$_DOA_'))
 ORDER BY 2;
