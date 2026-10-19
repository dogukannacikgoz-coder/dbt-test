-- GÜN 1 (load_date = 2026-10-01): Oracle senaryosuyla aynı veri
INSERT INTO d_branch VALUES ('B1'), ('B2')
/
INSERT INTO src_customer VALUES
  (1, 'Ali',    'R', 'IST', 'ali@x.com',    'B1', 100, 'A'),
  (2, 'Ayse',   'C', 'ANK', 'ayse@x.com',   'B2', 200, 'A'),
  (3, 'Mehmet', 'R', 'IZM', 'mehmet@x.com', 'B1', 300, 'A'),
  (4, 'Fatma',  'R', 'IST', 'fatma@x.com',  'B2', 400, 'A')
/
INSERT INTO src_customer_cdc SELECT c.*, 'I' FROM src_customer c
/
INSERT INTO src_customer_snap SELECT * FROM src_customer
/
INSERT INTO src_txn VALUES
  (101, 1, DATE '2026-10-01', 50),
  (102, 2, DATE '2026-10-01', 70),
  (103, 3, DATE '2026-10-01', 30),
  (201, 1, DATE '2026-10-02', 20)
/
