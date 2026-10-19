{#
================================================================================
 MODEL    : odi/04_scd/scd_type2   ->  T_SCD
 ODI KM   : IKM Oracle Slowly Changing Dimension + CKM
 NE YAPAR : Kolonlara SCD rolü verilir:
              natural_key          CUST_NO
              overwrite_on_change  CUST_NAME, EMAIL  (SCD1: aynı satırın üzerine yaz)
              add_row_on_change    SEGMENT, CITY     (SCD2: eskiyi kapat, yeni versiyon aç)
              surrogate_key        CUST_SK  <- SEQ_T_SCD.NEXTVAL
              current_flag / start_date / end_date -> IKM doldurur, model SQL'i döndürmez
 NE ZAMAN : Müşteri / ürün / şube boyutları; "o tarihte hangi segmentteydi" sorulacaksa.
 SENARYO  : Gün2: 1'in şehri değişti -> 2 satır (IST kapandı, ANK current)
                   2'nin email'i değişti -> aynı satır güncellendi
                   6 (NN) ve 8 (CK) E$'a; 7'de FK kontrolü yok -> girer
 ÇALIŞTIR : dbt run -s scd_type2
================================================================================
@setup
CREATE SEQUENCE seq_t_scd
/
CREATE TABLE t_scd (
  cust_sk NUMBER PRIMARY KEY, cust_no NUMBER, cust_name VARCHAR2(50), email VARCHAR2(50),
  segment VARCHAR2(5), city VARCHAR2(20), curr_flag NUMBER(1), eff_start_dt DATE, eff_end_dt DATE)
/
@check day1
toplam / current :: select count(*), sum(curr_flag) from t_scd => [(4, 4)]
@check day2
toplam / current :: select count(*), sum(curr_flag) from t_scd => [(7, 6)]
1'in versiyonları :: select city, curr_flag from t_scd where cust_no = 1 order by eff_start_dt, cust_sk => [('IST', 0), ('ANK', 1)]
eski versiyon kapandı :: select count(*) from t_scd where cust_no = 1 and curr_flag = 0 and eff_end_dt < date '2400-01-01' => 1
2 tek satır, yeni email :: select count(*), max(email) from t_scd where cust_no = 2 => [(1, 'ayse.new@x.com')]
@check day3
değişmedi :: select count(*), sum(curr_flag) from t_scd => [(7, 6)]
================================================================================
#}
{{ config(
    materialized       = 'odi_scd',
    alias              = 'T_SCD',
    odi_flow_control   = true,
    odi_ckm_not_null   = ['cust_name'],
    odi_ckm_conditions = {'CHK_SEGMENT': "segment in ('R','C')"},
    odi_scd = {
      'surrogate_key':       'cust_sk',
      'surrogate_expr':      'SEQ_T_SCD.NEXTVAL',
      'natural_key':         ['cust_no'],
      'overwrite_on_change': ['cust_name', 'email'],
      'add_row_on_change':   ['segment', 'city'],
      'current_flag':        'curr_flag',
      'start_date':          'eff_start_dt',
      'end_date':            'eff_end_dt',
      'start_expr':          'sysdate',
      'end_expr_on_close':   'sysdate'
    }
) }}

select cust_no, cust_name, email, segment, city
  from {{ source('src', 'src_customer') }}
