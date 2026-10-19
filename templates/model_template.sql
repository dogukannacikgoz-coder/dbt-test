{#
================================================================================
 MODEL    : flows/<katman>/<akış>/<model>        ->  <TARGET_TABLO>
 KAYNAK   : <Informatica workflow / ODI mapping adı>
 UC4 JOB  : <job adı>   (tag)
 ODI KM   : <seçilen IKM + opsiyonlar>
 NE YAPAR : <1-2 cümle>
 SAHİBİ   : <ekip / kişi>
================================================================================
@setup
-- target DDL (PDM'e verilecek olan)
CREATE TABLE <target> ( ... )
/
================================================================================
#}
{#
 materialized : odi_control_append | odi_incremental_update | odi_merge | odi_scd | odi_partition_exchange
 odi_flow_mode: table | existing | none
 GÜVENLİK     : --full-refresh varsayılan kapalı (gerekirse odi_allow_full_refresh = true);
                odi_delete_missing açıksa boş kaynakta model durur (odi_delete_missing_min_rows, default 1)
#}
{{ config(
    materialized       = 'odi_merge',
    alias              = '<TARGET_TABLO>',
    tags               = ['<uc4_job_tag>'],
    unique_key         = ['<key1>'],
    odi_flow_mode      = 'none',
    odi_partition      = {'column': '<tarih_kolonu>', 'value': 'param:load_date', 'strategy': 'none'},
    odi_audit_insert   = {'ins_dt': 'sysdate'},
    odi_audit_update   = {'upd_dt': 'sysdate'}
) }}

select ...
  from {{ ref('<önceki_adım>') }} a
 where {{ odi_partition_filter('a.<tarih_kolonu>') }}
