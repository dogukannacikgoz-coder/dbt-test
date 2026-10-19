{#
  ============================================================================
   IKM Oracle Partition Exchange Load   ->   materialized='odi_partition_exchange'

   Bir dönemin (gün/ay) tüm verisini ayrı bir tabloda (X$) hazırlar, sonra
   ALTER TABLE ... EXCHANGE PARTITION ile target partition'ıyla yer değiştirir.
   Target'a satır satır yazılmaz: değişim metadata işlemidir, saniyeler sürer,
   okuyanlar yarım veri görmez.

   Step'ler:
     [LKM]  C$ stage                               (odi_lkm)
            Ensure partition                        (interval: lock ile materialize, range/list: add)
            Validate partition granularity          (target partition'da dönem dışı satır var mı)
            X$ drop / create (target'ın kolonlarıyla) / insert APPEND
            CKM flow control on X$                  (odi_flow_control)
            Validate partition key range on X$      (model SQL'i başka dönemin verisini üretmiş mi)
            Analyze X$                              (odi_analyze_flow; stats partition'a taşınır)
            Exchange partition                      -> statement 'main' yok (DDL), satır sayısı X$ insert'ünde
            Rebuild unusable local indexes
            Cleanup X$  (içinde ESKİ partition verisi vardır; odi_delete_temporary_objects=false ile yedek kalır)

   Zorunlu: odi_partition.column + value. Target önceden partitioned olarak açılmış olmalı.
   Yetki: target ve X$ üzerinde ALTER TABLE (exchange), X$ için CREATE TABLE (veya odi_flow_mode='existing').
  ============================================================================
#}

{% materialization odi_partition_exchange, adapter='oracle' %}
  {%- set ctx    = odi_ctx('IKM Oracle Partition Exchange Load') -%}
  {%- set target = this.incorporate(type='table') -%}
  {%- set s      = odi_part_spec() -%}
  {%- if s is none or not s['column'] -%}
    {%- do exceptions.raise_compiler_error(this ~ ": odi_partition_exchange için odi_partition={'column':..., 'value':...} zorunlu.") -%}
  {%- endif -%}
  {%- if (config.get('odi_flow_mode', 'table') | lower) == 'none' -%}
    {%- do exceptions.raise_compiler_error(this ~ ": odi_partition_exchange X$ tablosu gerektirir (odi_flow_mode 'none' olamaz).") -%}
  {%- endif -%}
  {%- set x_rel  = odi_work_relation('X$_', 'odi_exchange_table') -%}

  {{ odi_hooks_pre(ctx) }}

  {%- if not odi_table_exists(target) -%}
    {%- do exceptions.raise_compiler_error('Target ' ~ target ~ ' yok. Partitioned olarak PDM ile açılmalı.') -%}
  {%- endif -%}

  {%- set lkm     = odi_lkm_stage(ctx, sql) -%}
  {%- set src_sql = lkm['sql'] -%}
  {%- set cols    = odi_query_columns(src_sql) -%}
  {%- set aud_ins = odi_audit('insert') -%}

  {#- model kolonları + insert audit kolonları = X$'a yazılacak kolonlar -#}
  {%- set xcols = cols[:] -%}
  {%- for c in aud_ins if c not in cols -%}{%- do xcols.append(c) -%}{%- endfor -%}
  {%- set x_src -%}
select odi_m.*{% for c, e in aud_ins.items() if c not in cols %}, {{ e }} as {{ c }}{% endfor %}
  from ( {{ src_sql }} ) odi_m
  {%- endset -%}

  {#- ---- Partition ---- -#}
  {%- do odi_ensure_partition(ctx, target, s) -%}
  {%- do odi_validate_partition_granularity(ctx, target, s) -%}

  {#- ---- X$ ---- -#}
  {%- do odi_load_work_table(ctx, x_rel, x_src, xcols, 'X$ (exchange)', create_from=target) -%}
  {%- do odi_ckm_flow_control(ctx, x_rel, odi_table_columns(x_rel), odi_as_list(config.get('unique_key')), has_ind=false) -%}

  {%- if config.get('odi_exchange_range_check', true) -%}
    {% call statement('odi_xrange', fetch_result=True) %}
      select count(*) from {{ x_rel }} x
       where not ( x.{{ s['column'] }} >= {{ s['lo'] }} and x.{{ s['column'] }} < {{ s['hi'] }} )
          or x.{{ s['column'] }} is null
    {% endcall %}
    {%- set outside = load_result('odi_xrange')['data'][0][0] | int -%}
    {%- do log('[' ~ ctx['km'] ~ '] ' ~ this.identifier ~ ' | Validate partition key range on X$ -> outside: ' ~ outside, info=True) -%}
    {%- if outside > 0 -%}
      {%- do exceptions.raise_compiler_error(this ~ ': X$ içinde ' ~ s['label'] ~ ' dönemi dışında ' ~ outside
            ~ " satır var. Model SQL'ine {{ odi_partition_filter(...) }} ekleyin. Exchange yapılmadı, target değişmedi.") -%}
    {%- endif -%}
  {%- endif -%}

  {#- ---- Exchange ---- -#}
  {%- set xq -%}
ALTER TABLE {{ target }}
  EXCHANGE PARTITION FOR ({{ s['lo'] }})
  WITH TABLE {{ x_rel }}
  {{ config.get('odi_exchange_indexes', 'EXCLUDING INDEXES') }}
  {{ 'WITH VALIDATION' if config.get('odi_exchange_validation', false) else 'WITHOUT VALIDATION' }}
  {{- ' UPDATE GLOBAL INDEXES' if s['ugi'] }}
  {%- endset -%}
  {%- do odi_exec(ctx, 'Exchange partition ' ~ s['label'], xq, auto_begin=False) -%}

  {%- set rb -%}
BEGIN
  EXECUTE IMMEDIATE 'ALTER TABLE {{ target }} MODIFY PARTITION FOR ({{ s["lo"] | replace("'", "''") }}) REBUILD UNUSABLE LOCAL INDEXES';
END;
  {%- endset -%}
  {%- do odi_exec(ctx, 'Rebuild unusable local indexes', rb, auto_begin=False) -%}

  {%- set tmp = [x_rel] -%}
  {%- if lkm['rel'] is not none -%}{%- do tmp.append(lkm['rel']) -%}{%- endif -%}
  {%- do odi_cleanup(ctx, tmp) -%}

  {#- dbt'nin transaction kapanışı için boş bir statement (DDL'ler zaten commit eder) -#}
  {% call statement('main') %}select 1 from dual{% endcall %}
  {{ odi_hooks_post(ctx) }}
  {{ return({'relations': [target]}) }}
{% endmaterialization %}
