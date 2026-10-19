{#
================================================================================
 MODEL    : odi/05_partition/pt_daily_exchange   ->  T_TXN_DAILY_X
 ODI KM   : IKM Oracle Partition Exchange Load
 NE YAPAR : Günün verisi X$_T_TXN_DAILY_X tablosunda hazırlanır (target'ın kolonlarıyla),
            sonra ALTER TABLE ... EXCHANGE PARTITION ile target partition'ıyla yer değiştirilir.
            Target'a satır yazılmaz: değişim saniyeler sürer, okuyanlar yarım veri görmez.
            Bu tablo INTERVAL değil, isimli RANGE partition: partition yoksa
            P20261001 adıyla ADD PARTITION yapılır. Local index exchange sonrası rebuild edilir.
            Model SQL'i başka günün verisini üretirse exchange YAPILMAZ (range check).
 NE ZAMAN : Büyük günlük/aylık hacim, okuma kesintisiz olmalı, yeniden yükleme sık.
 YETKİ    : Target ve X$ üzerinde ALTER (exchange). X$ için CREATE TABLE ya da
            odi_flow_mode='existing' + odi_exchange_table ile PDM'li tablo.
 SENARYO  : pt_daily_truncate ile aynı sonuç + partition'lar isimli oluşur.
            --vars '{break_filter: true}' -> model tüm günleri döndürür, range check durdurur.
 ÇALIŞTIR : dbt run -s pt_daily_exchange --vars '{load_date: 2026-10-01}'
================================================================================
@setup
CREATE TABLE t_txn_daily_x (
  txn_id NUMBER, cust_no NUMBER, txn_date DATE, amount NUMBER, load_dt DATE)
PARTITION BY RANGE (txn_date)
( PARTITION p0 VALUES LESS THAN (DATE '2026-01-01') )
/
CREATE INDEX ix_t_txn_daily_x_cust ON t_txn_daily_x (cust_no) LOCAL
/
@check day1
10-01 :: select count(*) from t_txn_daily_x where txn_date = date '2026-10-01' => 3
partition eklendi :: select count(*) from user_tab_partitions where table_name = 'T_TXN_DAILY_X' and partition_name = 'P20261001' => 1
@check day2
toplam :: select count(*) from t_txn_daily_x => 5
iki günlük partition :: select count(*) from user_tab_partitions where table_name = 'T_TXN_DAILY_X' and partition_name in ('P20261001', 'P20261002') => 2
local index usable :: select count(*) from user_ind_partitions where index_name = 'IX_T_TXN_DAILY_X_CUST' and status <> 'USABLE' => 0
@check day3
toplam :: select count(*) from t_txn_daily_x => 6
102 düzeldi :: select amount from t_txn_daily_x where txn_id = 102 => 75
================================================================================
#}
{{ config(
    materialized     = 'odi_partition_exchange',
    alias            = 'T_TXN_DAILY_X',
    odi_partition    = {
      'column':      'txn_date',
      'value':       'param:load_date',
      'granularity': 'day'
    },
    odi_analyze_flow = true,
    odi_audit_insert = {'load_dt': 'sysdate'}
) }}

select txn_id, cust_no, txn_date, amount
  from {{ source('src', 'src_txn') }}
 where {{ odi_partition_filter('txn_date') }}
 {%- if var('break_filter', false) %}
    or 1 = 1
 {%- endif %}
