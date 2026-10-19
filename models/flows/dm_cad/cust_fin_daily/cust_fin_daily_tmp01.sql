{#
================================================================================
 GERÇEK AKIŞ ÖRNEĞİ : dm_cad / cust_fin_daily   (UC4'teki 1 job = bu klasör = tag:cust_fin_daily)
 ADIM 1 / 3         : cust_fin_daily_tmp01  ->  T_CFD_TMP01
 NE YAPAR           : load_date gününün işlemlerini müşteri bazında toplar.
                      Temp tablo = Control Append + truncate (Informatica'daki ara tablo gibi).
 PARAMETRE          : load_date -> odi_param(): önce --vars, yoksa AKIS_PARAM tablosu
 ÇALIŞTIR           : dbt build -s tag:cust_fin_daily --vars '{load_date: 2026-10-02}'
                      scripts/run_job.sh cust_fin_daily 2026-10-02
                      (fail sonrası kaldığı yerden: scripts/run_job.sh cust_fin_daily 2026-10-02 --retry)
================================================================================
@setup
CREATE TABLE t_cfd_tmp01 (
  snapshot_date DATE, cust_no NUMBER, txn_cnt NUMBER, txn_amt NUMBER)
/
@check day1
10-01 müşterileri :: select count(*) from t_cfd_tmp01 => 3
@check day2
10-02 müşterileri :: select count(*) from t_cfd_tmp01 => 2
@check day3
10-01 yeniden :: select count(*) from t_cfd_tmp01 => 4
================================================================================
#}
{{ config(
    materialized = 'odi_control_append',
    alias        = 'T_CFD_TMP01',
    tags         = ['cust_fin_daily'],
    odi_truncate = true
) }}

select to_date('{{ odi_param("load_date") }}', 'YYYY-MM-DD') as snapshot_date,
       t.cust_no,
       count(*)      as txn_cnt,
       sum(t.amount) as txn_amt
  from {{ source('src', 'src_txn') }} t
 where t.txn_date = to_date('{{ odi_param("load_date") }}', 'YYYY-MM-DD')
 group by t.cust_no
