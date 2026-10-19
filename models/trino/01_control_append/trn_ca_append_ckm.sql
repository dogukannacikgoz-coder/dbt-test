{#
================================================================================
 MODEL    : trino/01_control_append/trn_ca_append_ckm   ->  t_ca_append_clean
 ODI KM   : IKM Control Append + CKM — Trino
 NE YAPAR : Flow tablosu (odi_i_t_ca_append_clean) CTAS ile oluşur, her satıra uuid ODI_ROW_ID verilir.
            CKM hatalıları odi_e_t_ca_append_clean'e yazar ve flow'dan ODI_ROW_ID ile siler.
 SENARYO  : Gün1 4 | Gün2 +5 = 9 (6,7,8 hata tablosunda) | Gün3 +6 = 15 (B9 eklendi)
 ÇALIŞTIR : dbt run --target trino -s trn_ca_append_ckm
================================================================================
@setup
CREATE TABLE t_ca_append_clean (
  cust_no bigint, cust_name varchar, segment varchar, city varchar,
  email varchar, branch_cd varchar, amount bigint, status varchar, load_ts timestamp(6))
/
@check day1
satır :: select count(*) from t_ca_append_clean => 4
@check day2
satır :: select count(*) from t_ca_append_clean => 9
hatalar (bu run) :: select cust_no, cons_type from odi_e_t_ca_append_clean where odi_sess_no = :sess order by 1 => [(6, 'NN'), (7, 'FK'), (8, 'CK')]
@check day3
satır :: select count(*) from t_ca_append_clean => 15
================================================================================
#}
{{ config(
    materialized       = 'odi_control_append',
    alias              = 't_ca_append_clean',
    odi_flow_control   = true,
    odi_ckm_not_null   = ['cust_name'],
    odi_ckm_conditions = {'CHK_SEGMENT': "segment in ('R','C')"},
    odi_ckm_references = {'FK_BRANCH': {'cols': ['branch_cd'], 'ref_table': 'd_branch'}},
    odi_audit_insert   = {'load_ts': 'localtimestamp'}
) }}

select cust_no, cust_name, segment, city, email, branch_cd, amount, status
  from {{ source('src_trn', 'src_customer') }}
