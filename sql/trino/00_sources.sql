-- ============================================================================
--  Trino (Iceberg) ortak kaynak tablolar + step log. iceberg.odi_test şemasında.
--  Her statement '/' satırıyla biter. Model'e özel target'lar modellerin @setup bloğunda.
-- ============================================================================
CREATE TABLE src_customer (
  cust_no bigint, cust_name varchar, segment varchar, city varchar,
  email varchar, branch_cd varchar, amount bigint, status varchar)
/
CREATE TABLE src_customer_cdc (
  cust_no bigint, cust_name varchar, segment varchar, city varchar,
  email varchar, branch_cd varchar, amount bigint, status varchar, op_type varchar)
/
CREATE TABLE src_customer_snap (
  cust_no bigint, cust_name varchar, segment varchar, city varchar,
  email varchar, branch_cd varchar, amount bigint, status varchar)
/
CREATE TABLE src_txn (txn_id bigint, cust_no bigint, txn_date date, amount bigint)
/
CREATE TABLE d_branch (branch_cd varchar)
/
-- Iceberg'de her step bir küçük dosya üretir. Prod'da log tablosunu bir RDBMS catalog'una
-- (postgresql / oracle connector) koyun: vars.odi_log_table: pg.etl.odi_step_log
CREATE TABLE odi_step_log (
  sess_no varchar, model_name varchar, km_name varchar, step_no integer,
  step_name varchar, rows_affected bigint, duration_sec double, log_date timestamp(6))
/
