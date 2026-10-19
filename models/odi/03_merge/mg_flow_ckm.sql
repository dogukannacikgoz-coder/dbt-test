{#
================================================================================
 MODEL    : odi/03_merge/mg_flow_ckm   ->  T_MG_FLOW
 ODI KM   : IKM Oracle Incremental Update (MERGE) + I$ + CKM + unique temp names
 NE YAPAR : Önce I$'a döker, CKM ile temizler, sonra I$'tan tek MERGE.
            odi_unique_temp_names = true -> I$ adı I$_T_MG_FLOW_<6 hane run id> olur;
            aynı model aynı anda iki kez koşsa (backfill + günlük) birbirinin I$'ını ezmez.
 NE ZAMAN : Flow control + MERGE hızı birlikte isteniyorsa.
 SENARYO  : Gün2: 6 (NN) ve 8 (CK) E$'a; 7'de FK kontrolü yok -> girer
 ÇALIŞTIR : dbt run -s mg_flow_ckm
================================================================================
@setup
CREATE TABLE t_mg_flow (
  cust_no NUMBER PRIMARY KEY, cust_name VARCHAR2(50), segment VARCHAR2(5), city VARCHAR2(20),
  email VARCHAR2(50), branch_cd VARCHAR2(5), amount NUMBER, status VARCHAR2(1))
/
@check day1
satır :: select count(*) from t_mg_flow => 4
@check day2
müşteriler :: select cust_no from t_mg_flow order by 1 => [(1,), (2,), (3,), (4,), (5,), (7,)]
E$ (bu run) :: select cust_no from "E$_T_MG_FLOW" where odi_sess_no = :sess order by 1 => [(6,), (8,)]
I$ artığı kalmadı :: select count(*) from user_tables where table_name like 'I$\_T\_MG\_FLOW%' escape '\' => 0
@check day3
aynı :: select count(*) from t_mg_flow => 6
================================================================================
#}
{{ config(
    materialized          = 'odi_merge',
    alias                 = 'T_MG_FLOW',
    unique_key            = 'cust_no',
    odi_unique_temp_names = true,
    odi_flow_control      = true,
    odi_ckm_not_null      = ['cust_name'],
    odi_ckm_conditions    = {'CHK_SEGMENT': "segment in ('R','C')"}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status
  from {{ source('src', 'src_customer') }}
