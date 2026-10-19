-- GÜN 3 (load_date = 2026-10-01 -> GERİYE DÖNÜK DÜZELTME / backfill)
--  d_branch: B9 artık var  -> önceki run'da FK'dan düşen 7 numara recycle ile girer
--  src_customer, src_customer_snap: DEĞİŞMEDİ (idempotency: tekrar koşunca bir şey değişmemeli)
--  src_customer_cdc: sadece 9 numara yeni
--  src_txn: 10-01'de 102'nin tutarı düzeltildi (70 -> 75) ve 104 eklendi
INSERT INTO d_branch SELECT 'B9' FROM dual
/
TRUNCATE TABLE src_customer_cdc
/
INSERT INTO src_customer_cdc
SELECT 9, 'Selin', 'R', 'IST', 'selin@x.com', 'B1', 900, 'A', 'I' FROM dual
/
UPDATE src_txn SET amount = 75 WHERE txn_id = 102
/
INSERT INTO src_txn SELECT 104, 5, DATE '2026-10-01', 10 FROM dual
/
COMMIT
/
