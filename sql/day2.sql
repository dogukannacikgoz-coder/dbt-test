-- GÜN 2 (load_date = 2026-10-02)
--  src_customer (tam liste):
--    1 şehir IST->ANK | 2 email değişti | 3 aynı | 4 status A->X | 5 yeni
--    6 isim NULL (NN hatası) | 7 şube B9 (FK hatası) | 8 segment Z (CK hatası)
TRUNCATE TABLE src_customer
/
INSERT INTO src_customer
SELECT 1, 'Ali',    'R', 'ANK', 'ali@x.com',      'B1', 100, 'A' FROM dual UNION ALL
SELECT 2, 'Ayse',   'C', 'ANK', 'ayse.new@x.com', 'B2', 200, 'A' FROM dual UNION ALL
SELECT 3, 'Mehmet', 'R', 'IZM', 'mehmet@x.com',   'B1', 300, 'A' FROM dual UNION ALL
SELECT 4, 'Fatma',  'R', 'IST', 'fatma@x.com',    'B2', 400, 'X' FROM dual UNION ALL
SELECT 5, 'Can',    'R', 'BUR', 'can@x.com',      'B1', 500, 'A' FROM dual UNION ALL
SELECT 6, NULL,     'R', 'IST', 'null@x.com',     'B1', 600, 'A' FROM dual UNION ALL
SELECT 7, 'Zeynep', 'C', 'ADA', 'zeynep@x.com',   'B9', 700, 'A' FROM dual UNION ALL
SELECT 8, 'Emre',   'Z', 'IZM', 'emre@x.com',     'B2', 800, 'A' FROM dual
/
--  src_customer_cdc (sadece değişenler): 1 U (ANK) | 3 D (silindi) | 5 I | 7 I (şube B9)
TRUNCATE TABLE src_customer_cdc
/
INSERT INTO src_customer_cdc
SELECT 1, 'Ali',    'R', 'ANK', 'ali@x.com',    'B1', 100, 'A', 'U' FROM dual UNION ALL
SELECT 3, 'Mehmet', 'R', 'IZM', 'mehmet@x.com', 'B1', 300, 'A', 'D' FROM dual UNION ALL
SELECT 5, 'Can',    'R', 'BUR', 'can@x.com',    'B1', 500, 'A', 'I' FROM dual UNION ALL
SELECT 7, 'Zeynep', 'C', 'ADA', 'zeynep@x.com', 'B9', 700, 'A', 'I' FROM dual
/
--  src_customer_snap: 1 şehir ANK | 4 kaynakta silindi (artık gelmiyor) | 5 yeni
TRUNCATE TABLE src_customer_snap
/
INSERT INTO src_customer_snap
SELECT 1, 'Ali',    'R', 'ANK', 'ali@x.com',    'B1', 100, 'A' FROM dual UNION ALL
SELECT 2, 'Ayse',   'C', 'ANK', 'ayse@x.com',   'B2', 200, 'A' FROM dual UNION ALL
SELECT 3, 'Mehmet', 'R', 'IZM', 'mehmet@x.com', 'B1', 300, 'A' FROM dual UNION ALL
SELECT 5, 'Can',    'R', 'BUR', 'can@x.com',    'B1', 500, 'A' FROM dual
/
--  src_txn: 10-02'ye yeni işlem
INSERT INTO src_txn SELECT 202, 4, DATE '2026-10-02', 40 FROM dual
/
COMMIT
/
