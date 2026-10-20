-- ============================================================================
--  02 — GÜN 1 KAYNAK VERİSİ (sonra: dbt run --vars "{load_date: '2026-10-01'}")
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

INSERT INTO DOA_D_BRANCH SELECT 'B1' FROM dual UNION ALL SELECT 'B2' FROM dual;
INSERT INTO DOA_SRC_CUSTOMER
SELECT 1, 'Ali',    'R', 'IST', 'ali@x.com',    'B1', 100, 'A' FROM dual UNION ALL
SELECT 2, 'Ayse',   'C', 'ANK', 'ayse@x.com',   'B2', 200, 'A' FROM dual UNION ALL
SELECT 3, 'Mehmet', 'R', 'IZM', 'mehmet@x.com', 'B1', 300, 'A' FROM dual UNION ALL
SELECT 4, 'Fatma',  'R', 'IST', 'fatma@x.com',  'B2', 400, 'A' FROM dual;
INSERT INTO DOA_SRC_CUSTOMER_CDC SELECT c.*, 'I' FROM DOA_SRC_CUSTOMER c;
INSERT INTO DOA_SRC_CUSTOMER_SNAP SELECT * FROM DOA_SRC_CUSTOMER;
INSERT INTO DOA_SRC_TXN
SELECT 101, 1, DATE '2026-10-01', 50 FROM dual UNION ALL
SELECT 102, 2, DATE '2026-10-01', 70 FROM dual UNION ALL
SELECT 103, 3, DATE '2026-10-01', 30 FROM dual UNION ALL
SELECT 201, 1, DATE '2026-10-02', 20 FROM dual;
COMMIT;
