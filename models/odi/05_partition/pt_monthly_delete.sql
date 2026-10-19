{#
================================================================================
 MODEL    : odi/05_partition/pt_monthly_delete   ->  T_TXN_MONTHLY
 ODI KM   : IKM Oracle Control Append + dönem DELETE (DDL'siz partition yenileme)
 NE YAPAR : Aylık dönem: load_date hangi aydaysa (2026-10-02 -> Ekim) target'tan o ayın
            satırları DELETE ile silinir, ayın başından bugüne verisi yeniden yazılır.
            DDL yok -> TRUNCATE/ALTER yetkisi gerekmez (bankadaki PDM ortamı).
            Partition key NUMBER YYYYMMDD (bankalarda yaygın): key_type='number'.
            Kaynak kolon DATE olduğu için filtrede key_type='date' ile override edilir.
 NE ZAMAN : Ay-içi kümülatif (MTD) tablolar, DDL yetkisi olmayan ortamda dönem yenileme.
 SENARYO  : Gün1 Ekim 4 | Gün2 Ekim 5 | Gün3 Ekim 6 (102 = 75)
 ÇALIŞTIR : dbt run -s pt_monthly_delete --vars '{load_date: 2026-10-02}'
================================================================================
@setup
CREATE TABLE t_txn_monthly (
  txn_id NUMBER, cust_no NUMBER, txn_date_key NUMBER(8), amount NUMBER)
PARTITION BY RANGE (txn_date_key) INTERVAL (100)
( PARTITION p0 VALUES LESS THAN (20260101) )
/
@check day1
Ekim :: select count(*) from t_txn_monthly where txn_date_key between 20261001 and 20261031 => 4
@check day2
Ekim :: select count(*) from t_txn_monthly => 5
@check day3
Ekim :: select count(*) from t_txn_monthly => 6
102 düzeldi :: select amount from t_txn_monthly where txn_id = 102 => 75
================================================================================
#}
{{ config(
    materialized  = 'odi_control_append',
    alias         = 'T_TXN_MONTHLY',
    odi_partition = {
      'column':      'txn_date_key',
      'value':       'param:load_date',
      'granularity': 'month',
      'key_type':    'number',
      'format':      '%Y%m%d',
      'strategy':    'delete'
    }
) }}

select txn_id, cust_no, to_number(to_char(txn_date, 'YYYYMMDD')) as txn_date_key, amount
  from {{ source('src', 'src_txn') }}
 where {{ odi_partition_filter('txn_date', key_type='date') }}
