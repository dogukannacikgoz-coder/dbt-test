{#
================================================================================
 MODEL    : odi/05_partition/pt_daily_truncate   ->  T_TXN_DAILY_TRUNC
 ODI KM   : IKM Oracle Control Append + TRUNCATE PARTITION
 NE YAPAR : Günlük partition yenileme: load_date'in partition'ı garanti edilir
            (INTERVAL tabloda LOCK TABLE ... PARTITION FOR ile oluşturulur),
            sadece o partition truncate edilir, o günün verisi APPEND ile yazılır.
            Diğer günlerin partition'larına dokunulmaz.
            Model SQL'i {{ odi_partition_filter('txn_date') }} ile aynı dönemi filtreler.
 NE ZAMAN : Günlük/aylık snapshot ve hareket tabloları; geriye dönük tek gün yeniden yükleme.
 YETKİ    : TRUNCATE PARTITION tablo sahibi (veya DROP ANY TABLE) ister. Yetki yoksa
            strategy='delete' kullanın (pt_monthly_delete).
 SENARYO  : Gün1 (10-01) 3 satır | Gün2 (10-02) +2 = 5 | Gün3 10-01 geriye dönük:
            sadece 10-01 yenilenir (102 düzeltildi, 104 eklendi) = 6, 10-02 aynı kalır
 ÇALIŞTIR : dbt run -s pt_daily_truncate --vars '{load_date: 2026-10-01}'
================================================================================
@setup
CREATE TABLE t_txn_daily_trunc (
  txn_id NUMBER, cust_no NUMBER, txn_date DATE, amount NUMBER, load_dt DATE)
PARTITION BY RANGE (txn_date) INTERVAL (NUMTODSINTERVAL(1, 'DAY'))
( PARTITION p0 VALUES LESS THAN (DATE '2026-01-01') )
/
@check day1
10-01 :: select count(*) from t_txn_daily_trunc where txn_date = date '2026-10-01' => 3
10-02 yüklenmedi :: select count(*) from t_txn_daily_trunc where txn_date = date '2026-10-02' => 0
@check day2
toplam :: select count(*) from t_txn_daily_trunc => 5
@check day3
toplam :: select count(*) from t_txn_daily_trunc => 6
102 düzeldi :: select amount from t_txn_daily_trunc where txn_id = 102 => 75
10-02 dokunulmadı :: select count(*) from t_txn_daily_trunc where txn_date = date '2026-10-02' => 2
================================================================================
#}
{{ config(
    materialized     = 'odi_control_append',
    alias            = 'T_TXN_DAILY_TRUNC',
    odi_partition    = {
      'column':      'txn_date',
      'value':       'param:load_date',
      'granularity': 'day',
      'strategy':    'truncate'
    },
    odi_audit_insert = {'load_dt': 'sysdate'}
) }}

select txn_id, cust_no, txn_date, amount
  from {{ source('src', 'src_txn') }}
 where {{ odi_partition_filter('txn_date') }}
