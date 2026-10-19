{#
================================================================================
 MODEL    : trino/02_incremental_update/trn_iu_basic_ckm   ->  t_iu
 ODI KM   : IKM Incremental Update + CKM — Trino
 NE YAPAR : Flow + CKM, sonra TEK MERGE. Oracle'daki D/U/N/I etiketleme adımları
            MERGE'in WHEN dallarına karşılık gelir (U = matched + fark var, N = matched + fark yok
            -> hiçbir dal çalışmaz, I = not matched). Trino'da tek statement = atomik.
 SENARYO  : Oracle T_IU ile aynı sonuç
 ÇALIŞTIR : dbt run --target trino -s trn_iu_basic_ckm  [--vars '{max_err: 0}'] [--full-refresh]
================================================================================
@setup
CREATE TABLE t_iu (
  cust_no bigint, cust_name varchar, segment varchar, city varchar,
  email varchar, branch_cd varchar, amount bigint, status varchar,
  ins_ts timestamp(6), upd_ts timestamp(6))
/
@check day1
satır :: select count(*) from t_iu => 4
update yok :: select count(*) from t_iu where upd_ts is not null => 0
@check day2
müşteriler :: select cust_no from t_iu order by 1 => [(1,), (2,), (3,), (4,), (5,)]
güncellenenler :: select cust_no from t_iu where upd_ts is not null order by 1 => [(1,), (2,), (4,)]
hatalar (bu run) :: select cust_no, cons_type from odi_e_t_iu where odi_sess_no = :sess order by 1 => [(6, 'NN'), (7, 'FK'), (8, 'CK')]
step: Merge rows (3 update + 1 insert) :: select sum(rows_affected) from odi_step_log where sess_no = :sess and model_name like '%.t_iu' and step_name = 'Merge rows' => 4
@check day3
7 girdi :: select cust_no from t_iu order by 1 => [(1,), (2,), (3,), (4,), (5,), (7,)]
sadece 7 işlendi :: select sum(rows_affected) from odi_step_log where sess_no = :sess and model_name like '%.t_iu' and step_name = 'Merge rows' => 1
================================================================================
#}
{{ config(
    materialized       = 'odi_incremental_update',
    alias              = 't_iu',
    unique_key         = 'cust_no',
    odi_flow_control   = true,
    odi_ckm_not_null   = ['cust_name'],
    odi_ckm_conditions = {'CHK_SEGMENT': "segment in ('R','C')"},
    odi_ckm_references = {'FK_BRANCH': {'cols': ['branch_cd'], 'ref_table': 'd_branch'}},
    odi_ckm_max_errors = var('max_err', none),
    odi_allow_full_refresh = true,
    odi_audit_insert   = {'ins_ts': 'localtimestamp'},
    odi_audit_update   = {'upd_ts': 'localtimestamp'}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status
  from {{ source('src_trn', 'src_customer') }}
