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
{{ config(
    materialized       = 'odi_merge',                 {# odi_control_append | odi_incremental_update | odi_merge | odi_scd | odi_partition_exchange #}
    alias              = '<TARGET_TABLO>',
    tags               = ['<uc4_job_tag>'],
    unique_key         = ['<key1>'],
    odi_flow_mode      = 'none',                      {# table | existing | none #}
    odi_partition      = {'column': '<tarih_kolonu>', 'value': 'param:load_date', 'strategy': 'none'},
    odi_audit_insert   = {'ins_dt': 'sysdate'},
    odi_audit_update   = {'upd_dt': 'sysdate'}
) }}

select ...
  from {{ ref('<önceki_adım>') }} a
 where {{ odi_partition_filter('a.<tarih_kolonu>') }}
