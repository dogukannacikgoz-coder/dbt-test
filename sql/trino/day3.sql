-- GÜN 3 (load_date = 2026-10-01, geriye dönük): sql/day3.sql ile aynı
INSERT INTO d_branch VALUES ('B9')
/
DELETE FROM src_customer_cdc
/
INSERT INTO src_customer_cdc VALUES (9, 'Selin', 'R', 'IST', 'selin@x.com', 'B1', 900, 'A', 'I')
/
UPDATE src_txn SET amount = 75 WHERE txn_id = 102
/
INSERT INTO src_txn VALUES (104, 5, DATE '2026-10-01', 10)
/
