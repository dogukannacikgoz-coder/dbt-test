{#
  ============================================================================
   Oracle partition işlemleri: ensure (interval lock / range-list add),
   granularity doğrulama, truncate / delete stratejileri.
   Ortak spec / filtre makroları: macros/odi/odi_partition.sql
  ============================================================================
#}

{# ---------------------------------------------------------------------------
   Partition'ı garanti et
     INTERVAL      -> LOCK TABLE ... PARTITION FOR (lo) ile materialize edilir
     RANGE         -> lo'yu kapsayan partition yoksa ADD PARTITION <name> VALUES LESS THAN (hi)
     LIST          -> lo değerini içeren partition yoksa ADD PARTITION <name> VALUES (lo)
--------------------------------------------------------------------------- #}
{% macro odi_ensure_partition(ctx, target, s) %}
  {%- set lo_q = s['lo'] | replace("'", "''") -%}
  {%- set hi_q = s['hi'] | replace("'", "''") -%}
  {%- set q -%}
DECLARE
  v_type  VARCHAR2(30);
  v_int   VARCHAR2(1000);
  v_hv    VARCHAR2(32767);
  v_ok    NUMBER := 0;
  v_eq    NUMBER := 0;
  v_r     NUMBER;
BEGIN
  SELECT partitioning_type, interval INTO v_type, v_int
    FROM all_part_tables
   WHERE owner = '{{ target.schema | upper }}' AND table_name = '{{ target.identifier | upper }}';

  IF v_int IS NOT NULL THEN
    EXECUTE IMMEDIATE 'LOCK TABLE {{ target }} PARTITION FOR ({{ lo_q }}) IN SHARE MODE';
    RETURN;
  END IF;

  FOR p IN ( SELECT partition_name, high_value FROM all_tab_partitions
              WHERE table_owner = '{{ target.schema | upper }}' AND table_name = '{{ target.identifier | upper }}' ) LOOP
    v_hv := p.high_value;
    IF v_hv IN ('MAXVALUE', 'DEFAULT') THEN v_ok := 1; EXIT; END IF;
    IF v_type = 'RANGE' THEN
      EXECUTE IMMEDIATE 'SELECT CASE WHEN {{ lo_q }} < ' || v_hv || ' THEN 1 WHEN {{ lo_q }} = ' || v_hv || ' THEN 2 ELSE 0 END FROM dual' INTO v_r;
      IF v_r = 2 THEN v_eq := 1; v_r := 0; END IF;
    ELSE
      EXECUTE IMMEDIATE 'SELECT CASE WHEN {{ lo_q }} IN (' || v_hv || ') THEN 1 ELSE 0 END FROM dual' INTO v_r;
    END IF;
    IF v_r = 1 THEN v_ok := 1; EXIT; END IF;
  END LOOP;

  IF v_ok = 0 THEN
    {%- if s['create'] %}
    IF v_type = 'RANGE' THEN
      -- son partition dönemin başında bitmiyorsa arayı ayrı bir boşluk partition'ı kapatır,
      -- böylece eklenen partition tam olarak [lo, hi) olur
      IF v_eq = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE {{ target }} ADD PARTITION {{ ("GAP_" ~ s["name"])[:128] }} VALUES LESS THAN ({{ lo_q }})';
      END IF;
      EXECUTE IMMEDIATE 'ALTER TABLE {{ target }} ADD PARTITION {{ s["name"] }} VALUES LESS THAN ({{ hi_q }})';
    ELSIF v_type = 'LIST' THEN
      EXECUTE IMMEDIATE 'ALTER TABLE {{ target }} ADD PARTITION {{ s["name"] }} VALUES ({{ lo_q }})';
    ELSE
      RAISE_APPLICATION_ERROR(-20001, 'odi_partition: desteklenmeyen partition tipi ' || v_type);
    END IF;
    {%- else %}
    RAISE_APPLICATION_ERROR(-20002, 'odi_partition: {{ s["label"] }} için partition yok ve create=false');
    {%- endif %}
  END IF;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20003, 'odi_partition: {{ target }} partitioned tablo değil');
END;
  {%- endset -%}
  {%- do odi_exec(ctx, 'Ensure partition ' ~ s['label'], q, auto_begin=False) -%}
  {%- do odi_commit(ctx) -%}
{% endmacro %}

{# Partition'da hedef dönem dışında satır varsa (ör. aylık partition'a günlük truncate) dur #}
{% macro odi_validate_partition_granularity(ctx, target, s) %}
  {%- if s['validate'] -%}
    {% call statement('odi_pgran', fetch_result=True) %}
      select count(*) from {{ target }} partition for ({{ s['lo'] }}) t
       where not ( t.{{ s['column'] }} >= {{ s['lo'] }} and t.{{ s['column'] }} < {{ s['hi'] }} )
         and rownum = 1
    {% endcall %}
    {%- if load_result('odi_pgran')['data'][0][0] | int > 0 -%}
      {%- do exceptions.raise_compiler_error(
          this ~ ': ' ~ s['label'] ~ ' partition\'ı dönem dışı satır içeriyor (partition granularity config ile uyuşmuyor). '
          ~ "Truncate/exchange bu satırları silerdi. granularity'yi düzeltin ya da strategy='delete' kullanın.") -%}
    {%- endif -%}
  {%- endif -%}
{% endmacro %}

{# Target hazırlığında çağrılır: strategy truncate | delete | none (exchange kendi materialization'ında) #}
{% macro odi_partition_prepare(ctx, target) %}
  {%- set s = odi_part_spec() -%}
  {%- if s is none -%}{{ return(none) }}{%- endif -%}
  {%- if s['strategy'] == 'delete' -%}
    {%- set q -%}
delete {{ odi_hint(config.get('odi_delete_hint', none)) }} from {{ target }} t
 where t.{{ s['column'] }} >= {{ s['lo'] }} and t.{{ s['column'] }} < {{ s['hi'] }}
    {%- endset -%}
    {%- do odi_exec(ctx, 'Delete partition rows ' ~ s['label'], q) -%}
  {%- elif s['strategy'] == 'exchange' -%}
    {%- do exceptions.raise_compiler_error(this ~ ": strategy='exchange' için materialized='odi_partition_exchange' kullanın.") -%}
  {%- elif s['strategy'] in ['truncate', 'none'] -%}
    {%- do odi_ensure_partition(ctx, target, s) -%}
    {%- if s['strategy'] == 'truncate' -%}
      {%- do odi_validate_partition_granularity(ctx, target, s) -%}
      {%- do odi_exec(ctx, 'Truncate partition ' ~ s['label'],
            'ALTER TABLE ' ~ target ~ ' TRUNCATE PARTITION FOR (' ~ s['lo'] ~ ')' ~ (' UPDATE GLOBAL INDEXES' if s['ugi'] else ''),
            auto_begin=False) -%}
    {%- endif -%}
  {%- else -%}
    {%- do exceptions.raise_compiler_error(this ~ ": odi_partition.strategy '" ~ s['strategy'] ~ "' geçersiz (truncate|delete|exchange|none).") -%}
  {%- endif -%}
{% endmacro %}
