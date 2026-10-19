{#
================================================================================
 GERÇEK AKIŞ ÖRNEĞİ : dm_cad / cust_fin_daily
 ADIM 3 / 3 (FINAL) : cust_fin_daily  ->  DM_CUST_FIN_DAILY  (günlük partition'lı DM tablosu)
 NE YAPAR           : I$ + CKM + MERGE, sadece load_date partition'ında (prune),
                      partition içinde kaynakta olmayan satırı siler (delete missing).
                      Geriye dönük bir gün yeniden koşulursa sadece o gün düzelir.
 STANDART           : temp adımlar = odi_control_append + truncate
                      final        = odi_merge (veya odi_partition_exchange) + odi_partition
                      hepsi aynı tag; UC4 sadece tag + load_date verir.
 SENARYO            : Gün1 3 | Gün2 +2 = 5 | Gün3 10-01 geriye dönük: 2'nin tutarı 75, 5 eklendi = 6
================================================================================
@setup
CREATE TABLE dm_cust_fin_daily (
  snapshot_date DATE, cust_no NUMBER, cust_name VARCHAR2(50), segment VARCHAR2(5),
  branch_cd VARCHAR2(5), txn_cnt NUMBER, txn_amt NUMBER, ins_dt DATE, upd_dt DATE)
PARTITION BY RANGE (snapshot_date) INTERVAL (NUMTODSINTERVAL(1, 'DAY'))
( PARTITION p0 VALUES LESS THAN (DATE '2026-01-01') )
/
@check day1
satır :: select count(*) from dm_cust_fin_daily => 3
@check day2
satır :: select count(*) from dm_cust_fin_daily => 5
@check day3
satır :: select count(*) from dm_cust_fin_daily => 6
2'nin 10-01 tutarı :: select txn_amt from dm_cust_fin_daily where cust_no = 2 and snapshot_date = date '2026-10-01' => 75
sadece o satır güncellendi :: select cust_no from dm_cust_fin_daily where upd_dt is not null => 2
================================================================================
#}
{{ config(
    materialized       = 'odi_merge',
    alias              = 'DM_CUST_FIN_DAILY',
    tags               = ['cust_fin_daily'],
    unique_key         = ['snapshot_date', 'cust_no'],
    odi_flow_control   = true,
    odi_ckm_not_null   = ['cust_name', 'segment'],
    odi_delete_missing = true,
    odi_partition      = {
      'column':   'snapshot_date',
      'value':    'param:load_date',
      'strategy': 'none'
    },
    odi_audit_insert   = {'ins_dt': 'sysdate'},
    odi_audit_update   = {'upd_dt': 'sysdate'}
) }}

select snapshot_date, cust_no, cust_name, segment, branch_cd, txn_cnt, txn_amt
  from {{ ref('cust_fin_daily_tmp02') }}
