-- ============================================================================
--  03 — GÜN 2 KAYNAK VERİSİ (sonra: dbt run --vars "{load_date: '2026-10-02'}")
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

TRUNCATE TABLE &P.SRC_CUSTOMER;
INSERT INTO &P.SRC_CUSTOMER
SELECT 1, 'Ali',    'R', 'ANK', 'ali@x.com',      'B1', 100, 'A' FROM dual UNION ALL
SELECT 2, 'Ayse',   'C', 'ANK', 'ayse.new@x.com', 'B2', 200, 'A' FROM dual UNION ALL
SELECT 3, 'Mehmet', 'R', 'IZM', 'mehmet@x.com',   'B1', 300, 'A' FROM dual UNION ALL
SELECT 4, 'Fatma',  'R', 'IST', 'fatma@x.com',    'B2', 400, 'X' FROM dual UNION ALL
SELECT 5, 'Can',    'R', 'BUR', 'can@x.com',      'B1', 500, 'A' FROM dual UNION ALL
SELECT 6, NULL,     'R', 'IST', 'null@x.com',     'B1', 600, 'A' FROM dual UNION ALL
SELECT 7, 'Zeynep', 'C', 'ADA', 'zeynep@x.com',   'B9', 700, 'A' FROM dual UNION ALL
SELECT 8, 'Emre',   'Z', 'IZM', 'emre@x.com',     'B2', 800, 'A' FROM dual;
TRUNCATE TABLE &P.SRC_CUSTOMER_CDC;
INSERT INTO &P.SRC_CUSTOMER_CDC
SELECT 1, 'Ali',    'R', 'ANK', 'ali@x.com',    'B1', 100, 'A', 'U' FROM dual UNION ALL
SELECT 3, 'Mehmet', 'R', 'IZM', 'mehmet@x.com', 'B1', 300, 'A', 'D' FROM dual UNION ALL
SELECT 5, 'Can',    'R', 'BUR', 'can@x.com',    'B1', 500, 'A', 'I' FROM dual UNION ALL
SELECT 7, 'Zeynep', 'C', 'ADA', 'zeynep@x.com', 'B9', 700, 'A', 'I' FROM dual;
TRUNCATE TABLE &P.SRC_CUSTOMER_SNAP;
INSERT INTO &P.SRC_CUSTOMER_SNAP
SELECT 1, 'Ali',    'R', 'ANK', 'ali@x.com',    'B1', 100, 'A' FROM dual UNION ALL
SELECT 2, 'Ayse',   'C', 'ANK', 'ayse@x.com',   'B2', 200, 'A' FROM dual UNION ALL
SELECT 3, 'Mehmet', 'R', 'IZM', 'mehmet@x.com', 'B1', 300, 'A' FROM dual UNION ALL
SELECT 5, 'Can',    'R', 'BUR', 'can@x.com',    'B1', 500, 'A' FROM dual;
INSERT INTO &P.SRC_TXN SELECT 202, 4, DATE '2026-10-02', 40 FROM dual;
COMMIT;
