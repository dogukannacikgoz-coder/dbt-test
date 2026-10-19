-- GÜN 1 (load_date = 2026-10-01): ilk yükleme, hepsi temiz
INSERT INTO d_branch SELECT 'B1' FROM dual UNION ALL SELECT 'B2' FROM dual
/
INSERT INTO src_customer
SELECT 1, 'Ali',    'R', 'IST', 'ali@x.com',    'B1', 100, 'A' FROM dual UNION ALL
SELECT 2, 'Ayse',   'C', 'ANK', 'ayse@x.com',   'B2', 200, 'A' FROM dual UNION ALL
SELECT 3, 'Mehmet', 'R', 'IZM', 'mehmet@x.com', 'B1', 300, 'A' FROM dual UNION ALL
SELECT 4, 'Fatma',  'R', 'IST', 'fatma@x.com',  'B2', 400, 'A' FROM dual
/
INSERT INTO src_customer_cdc SELECT c.*, 'I' FROM src_customer c
/
INSERT INTO src_customer_snap SELECT * FROM src_customer
/
INSERT INTO src_txn
SELECT 101, 1, DATE '2026-10-01', 50 FROM dual UNION ALL
SELECT 102, 2, DATE '2026-10-01', 70 FROM dual UNION ALL
SELECT 103, 3, DATE '2026-10-01', 30 FROM dual UNION ALL
SELECT 201, 1, DATE '2026-10-02', 20 FROM dual
/
COMMIT
/
