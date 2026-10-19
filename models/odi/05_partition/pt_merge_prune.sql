{#
================================================================================
 MODEL    : odi/05_partition/pt_merge_prune   ->  T_TXN_MERGE_PART
 ODI KM   : IKM Oracle Incremental Update (MERGE) + partition pruning + partition içi delete missing
 NE YAPAR : strategy='none' -> partition sadece garanti edilir, truncate edilmez.
            MERGE'ün ON koşuluna partition aralığı eklenir; Oracle sadece o günün
            partition'ını tarar (milyarlık tabloda kritik). odi_delete_missing de o partition
            ile sınırlıdır: o günün kaynakta olmayan satırı silinir, diğer günlere dokunulmaz.
 NE ZAMAN : Partition'lı büyük tabloda satır bazında düzeltme (geç gelen / düzeltilen kayıt).
 SENARYO  : Gün3 10-01 geriye dönük: 102 update (upd_dt dolar), 104 insert
 ÇALIŞTIR : dbt run -s pt_merge_prune --vars '{load_date: 2026-10-01}'
================================================================================
@setup
CREATE TABLE t_txn_merge_part (
  txn_id NUMBER, cust_no NUMBER, txn_date DATE, amount NUMBER, upd_dt DATE)
PARTITION BY RANGE (txn_date) INTERVAL (NUMTODSINTERVAL(1, 'DAY'))
( PARTITION p0 VALUES LESS THAN (DATE '2026-01-01') )
/
@check day1
satır :: select count(*) from t_txn_merge_part => 3
@check day2
satır :: select count(*) from t_txn_merge_part => 5
@check day3
satır :: select count(*) from t_txn_merge_part => 6
sadece 102 güncellendi :: select txn_id from t_txn_merge_part where upd_dt is not null => 102
================================================================================
#}
{{ config(
    materialized       = 'odi_merge',
    alias              = 'T_TXN_MERGE_PART',
    unique_key         = 'txn_id',
    odi_flow_mode      = 'none',
    odi_delete_missing = true,
    odi_partition      = {
      'column':   'txn_date',
      'value':    'param:load_date',
      'strategy': 'none'
    },
    odi_audit_update   = {'upd_dt': 'sysdate'}
) }}

select txn_id, cust_no, txn_date, amount
  from {{ source('src', 'src_txn') }}
 where {{ odi_partition_filter('txn_date') }}
