-- ============================================================================
--  Ortak kaynak tablolar + step log. ODI_TEST* şemasında çalıştır.
--  Her statement '/' satırıyla biter (SQL*Plus / SQLcl / test_runner.py uyumlu).
--  Model'e özel target / work tabloları her modelin başındaki @setup bloğunda.
-- ============================================================================

-- kaynak: müşteri tam liste (her gün tamamı gelir)
CREATE TABLE src_customer (
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1))
/
-- kaynak: müşteri CDC (sadece değişenler gelir, OP_TYPE = I/U/D)
CREATE TABLE src_customer_cdc (
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1),
  op_type VARCHAR2(1))
/
-- kaynak: müşteri snapshot (kaynakta silinen kayıt artık gelmez)
CREATE TABLE src_customer_snap (
  cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1))
/
-- kaynak: işlemler (partition örnekleri)
CREATE TABLE src_txn (
  txn_id NUMBER, cust_no NUMBER, txn_date DATE, amount NUMBER)
/
-- referans: şube (CKM FK kontrolü)
CREATE TABLE d_branch (branch_cd VARCHAR2(5) PRIMARY KEY)
/
-- ODI Operator karşılığı: her step'in satır sayısı ve süresi
CREATE TABLE odi_step_log (
  sess_no VARCHAR2(64), model_name VARCHAR2(256), km_name VARCHAR2(100), step_no NUMBER,
  step_name VARCHAR2(400), rows_affected NUMBER, duration_sec NUMBER, log_date TIMESTAMP)
/
