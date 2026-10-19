-- ============================================================================
--  04 — GÜN 3 KAYNAK VERİSİ (sonra: dbt run --vars "{load_date: '2026-10-01'}")
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

INSERT INTO &P.D_BRANCH SELECT 'B9' FROM dual;
TRUNCATE TABLE &P.SRC_CUSTOMER_CDC;
INSERT INTO &P.SRC_CUSTOMER_CDC
SELECT 9, 'Selin', 'R', 'IST', 'selin@x.com', 'B1', 900, 'A', 'I' FROM dual;
UPDATE &P.SRC_TXN SET amount = 75 WHERE txn_id = 102;
INSERT INTO &P.SRC_TXN SELECT 104, 5, DATE '2026-10-01', 10 FROM dual;
COMMIT;
