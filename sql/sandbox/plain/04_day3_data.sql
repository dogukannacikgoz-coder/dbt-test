-- ============================================================================
--  04 — GÜN 3 KAYNAK VERİSİ (sonra: dbt run --vars "{load_date: '2026-10-01'}")
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

INSERT INTO DOA_D_BRANCH SELECT 'B9' FROM dual;
TRUNCATE TABLE DOA_SRC_CUSTOMER_CDC;
INSERT INTO DOA_SRC_CUSTOMER_CDC
SELECT 9, 'Selin', 'R', 'IST', 'selin@x.com', 'B1', 900, 'A', 'I' FROM dual;
UPDATE DOA_SRC_TXN SET amount = 75 WHERE txn_id = 102;
INSERT INTO DOA_SRC_TXN SELECT 104, 5, DATE '2026-10-01', 10 FROM dual;
COMMIT;
