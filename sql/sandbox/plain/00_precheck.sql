-- ============================================================================
--  00 — ÖN KONTROL (sadece okur, hiçbir şey değiştirmez)
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

-- == Bu önekle başlayan nesne var mı? (BOŞ dönmeli. Dönüyorsa başka önek seç.)
SELECT object_type, object_name, created
  FROM all_objects
 WHERE owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
   AND (SUBSTR(object_name, 1, LENGTH('DOA_')) = 'DOA_'
    OR SUBSTR(object_name, 1, 3 + LENGTH('DOA_')) IN ('I$_DOA_', 'C$_DOA_', 'X$_DOA_', 'E$_DOA_'))
 ORDER BY 2;

-- == Yetkiler (CREATE TABLE / CREATE SEQUENCE olmalı)
SELECT privilege FROM session_privs WHERE privilege IN ('CREATE TABLE', 'CREATE SEQUENCE', 'CREATE ANY TABLE', 'COMMENT ANY TABLE') ORDER BY 1;

-- == Bağlı kullanıcı / aktif şema (aktif şema GLOBAL_DWH olmalı; kullanıcı farklıysa dbt'de ORA_SCHEMA=GLOBAL_DWH ver)
SELECT USER AS bagli_kullanici, SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AS aktif_sema FROM dual;
