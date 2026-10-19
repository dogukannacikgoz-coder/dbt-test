-- ============================================================================
--  00 — ÖN KONTROL (sadece okur, hiçbir şey değiştirmez)
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

PROMPT == Bu önekle başlayan nesne var mı? (BOŞ dönmeli. Dönüyorsa başka önek seç.)
SELECT object_type, object_name, created
  FROM user_objects
 WHERE SUBSTR(object_name, 1, LENGTH('&P.')) = '&P.'
    OR SUBSTR(object_name, 1, 3 + LENGTH('&P.')) IN ('I$_&P.', 'C$_&P.', 'X$_&P.', 'E$_&P.')
 ORDER BY 2;

PROMPT == Yetkiler (CREATE TABLE / CREATE SEQUENCE olmalı)
SELECT privilege FROM session_privs WHERE privilege IN ('CREATE TABLE', 'CREATE SEQUENCE', 'CREATE ANY TABLE', 'COMMENT ANY TABLE') ORDER BY 1;

PROMPT == Bağlı kullanıcı / aktif şema (ikisi aynı olmalı; farklıysa ORA_SCHEMA ver)
SELECT USER AS bagli_kullanici, SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AS aktif_sema FROM dual;
