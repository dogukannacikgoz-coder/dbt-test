{#
================================================================================
 MODEL    : trino/04_scd/trn_scd_type2   ->  t_scd
 ODI KM   : IKM Slowly Changing Dimension — Trino
 NE YAPAR : MERGE #1: current kayıtta SCD2 kolonu farklıysa kapat (flag=0, end=now),
                      sadece SCD1 farklıysa üzerine yaz.
            INSERT  : current kaydı olmayan NK'lar (yeni + yeni versiyon).
            SK: surrogate_expr yok -> max(cust_sk) + row_number() (Iceberg'de sequence yok).
 FARK     : 2 statement, tek transaction değil; arada fail olursa tekrar koşmak güvenli.
 SENARYO  : Oracle T_SCD ile aynı
 ÇALIŞTIR : dbt run --target trino -s trn_scd_type2
================================================================================
@setup
CREATE TABLE t_scd (
  cust_sk bigint, cust_no bigint, cust_name varchar, email varchar, segment varchar, city varchar,
  curr_flag integer, eff_start_ts timestamp(6), eff_end_ts timestamp(6))
/
@check day1
toplam / current :: select count(*), sum(curr_flag) from t_scd => [(4, 4)]
SK'lar tekil :: select count(distinct cust_sk) from t_scd => 4
@check day2
toplam / current :: select count(*), sum(curr_flag) from t_scd => [(7, 6)]
1'in versiyonları :: select city, curr_flag from t_scd where cust_no = 1 order by cust_sk => [('IST', 0), ('ANK', 1)]
2 tek satır, yeni email :: select count(*), max(email) from t_scd where cust_no = 2 => [(1, 'ayse.new@x.com')]
SK'lar tekil :: select count(distinct cust_sk) from t_scd => 7
@check day3
değişmedi :: select count(*), sum(curr_flag) from t_scd => [(7, 6)]
================================================================================
#}
{{ config(
    materialized       = 'odi_scd',
    alias              = 't_scd',
    odi_flow_control   = true,
    odi_ckm_not_null   = ['cust_name'],
    odi_ckm_conditions = {'CHK_SEGMENT': "segment in ('R','C')"},
    odi_scd = {
      'surrogate_key':       'cust_sk',
      'natural_key':         ['cust_no'],
      'overwrite_on_change': ['cust_name', 'email'],
      'add_row_on_change':   ['segment', 'city'],
      'current_flag':        'curr_flag',
      'start_date':          'eff_start_ts',
      'end_date':            'eff_end_ts'
    }
) }}

select cust_no, cust_name, email, segment, city
  from {{ source('src_trn', 'src_customer') }}
