-- GÜN 2 (load_date = 2026-10-02): sql/day2.sql ile aynı değişiklikler
DELETE FROM src_customer
/
INSERT INTO src_customer VALUES
  (1, 'Ali',    'R', 'ANK', 'ali@x.com',      'B1', 100, 'A'),
  (2, 'Ayse',   'C', 'ANK', 'ayse.new@x.com', 'B2', 200, 'A'),
  (3, 'Mehmet', 'R', 'IZM', 'mehmet@x.com',   'B1', 300, 'A'),
  (4, 'Fatma',  'R', 'IST', 'fatma@x.com',    'B2', 400, 'X'),
  (5, 'Can',    'R', 'BUR', 'can@x.com',      'B1', 500, 'A'),
  (6, NULL,     'R', 'IST', 'null@x.com',     'B1', 600, 'A'),
  (7, 'Zeynep', 'C', 'ADA', 'zeynep@x.com',   'B9', 700, 'A'),
  (8, 'Emre',   'Z', 'IZM', 'emre@x.com',     'B2', 800, 'A')
/
DELETE FROM src_customer_cdc
/
INSERT INTO src_customer_cdc VALUES
  (1, 'Ali',    'R', 'ANK', 'ali@x.com',    'B1', 100, 'A', 'U'),
  (3, 'Mehmet', 'R', 'IZM', 'mehmet@x.com', 'B1', 300, 'A', 'D'),
  (5, 'Can',    'R', 'BUR', 'can@x.com',    'B1', 500, 'A', 'I'),
  (7, 'Zeynep', 'C', 'ADA', 'zeynep@x.com', 'B9', 700, 'A', 'I')
/
DELETE FROM src_customer_snap
/
INSERT INTO src_customer_snap VALUES
  (1, 'Ali',    'R', 'ANK', 'ali@x.com',    'B1', 100, 'A'),
  (2, 'Ayse',   'C', 'ANK', 'ayse@x.com',   'B2', 200, 'A'),
  (3, 'Mehmet', 'R', 'IZM', 'mehmet@x.com', 'B1', 300, 'A'),
  (5, 'Can',    'R', 'BUR', 'can@x.com',    'B1', 500, 'A')
/
INSERT INTO src_txn VALUES (202, 4, DATE '2026-10-02', 40)
/
