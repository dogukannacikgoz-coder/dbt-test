{#
  ============================================================================
   Partition yardımcıları
   Model config:
     odi_partition = {
       'column':       'TXN_DATE',          # target partition key kolonu
       'value':        'param:LOAD_DATE',   # '2026-10-01' | '20261001' | '2026-10' | '202610' | var(...)
       'granularity':  'day',               # day | month | year
       'key_type':     'date',              # date | timestamp | number | string
       'format':       '%Y%m%d',            # number/string key için literal formatı
       'strategy':     'truncate',          # truncate | delete | exchange | none
       'name_format':  'P%Y%m%d',           # RANGE/LIST'te eklenecek partition adı
       'create':       true,                # partition yoksa ekle (interval'da otomatik materialize)
       'update_global_indexes': true,
       'validate_granularity': true         # partition'da periyot dışı satır varsa dur
     }
  ============================================================================
#}

{# Partition config'inden dönem bilgisi: lo/hi literal'leri, partition adı #}
{% macro odi_part_spec(pcfg=none) %}
  {%- set p = odi_upper_dict(pcfg if pcfg is not none else config.get('odi_partition', none)) -%}
  {%- if not p -%}{{ return(none) }}{%- endif -%}
  {%- set raw = odi_resolve(p.get('VALUE')) -%}
  {%- if raw is none -%}
    {%- do exceptions.raise_compiler_error(this ~ ': odi_partition.value boş (var / param verilmedi).') -%}
  {%- endif -%}
  {%- set digits = (raw ~ '') | replace('-', '') | replace('/', '') | replace('.', '') -%}
  {%- set digits = digits[:8] -%}
  {%- set gran = (p.get('GRANULARITY', 'day') | lower) -%}
  {%- set dt = modules.datetime -%}
  {%- if digits | length == 8 -%}
    {%- set d = dt.date(digits[:4] | int, digits[4:6] | int, digits[6:8] | int) -%}
  {%- elif digits | length == 6 -%}
    {%- set d = dt.date(digits[:4] | int, digits[4:6] | int, 1) -%}
  {%- elif digits | length == 4 -%}
    {%- set d = dt.date(digits | int, 1, 1) -%}
  {%- else -%}
    {%- do exceptions.raise_compiler_error(this ~ ": odi_partition.value '" ~ raw ~ "' anlaşılmadı (YYYY-MM-DD / YYYYMMDD / YYYY-MM).") -%}
  {%- endif -%}

  {%- if gran == 'day' -%}
    {%- set start = d -%}
    {%- set nxt = d + dt.timedelta(days=1) -%}
    {%- set def_fmt = '%Y%m%d' -%}
  {%- elif gran == 'month' -%}
    {%- set start = dt.date(d.year, d.month, 1) -%}
    {%- set nxt = dt.date(d.year + (1 if d.month == 12 else 0), 1 if d.month == 12 else d.month + 1, 1) -%}
    {%- set def_fmt = '%Y%m' -%}
  {%- elif gran == 'year' -%}
    {%- set start = dt.date(d.year, 1, 1) -%}
    {%- set nxt = dt.date(d.year + 1, 1, 1) -%}
    {%- set def_fmt = '%Y' -%}
  {%- else -%}
    {%- do exceptions.raise_compiler_error(this ~ ": odi_partition.granularity '" ~ gran ~ "' geçersiz (day|month|year).") -%}
  {%- endif -%}

  {%- set kt = p.get('KEY_TYPE', 'date') | lower -%}
  {%- set fmt = p.get('FORMAT', '%Y%m%d' if kt == 'number' else '%Y-%m-%d') -%}
  {%- set lits = [] -%}
  {%- for x in [start, nxt] -%}
    {%- if kt == 'date' -%}
      {%- do lits.append("DATE '" ~ x.strftime('%Y-%m-%d') ~ "'") -%}
    {%- elif kt == 'timestamp' -%}
      {%- do lits.append("TIMESTAMP '" ~ x.strftime('%Y-%m-%d') ~ " 00:00:00'") -%}
    {%- elif kt == 'number' -%}
      {%- do lits.append(x.strftime(fmt)) -%}
    {%- elif kt == 'string' -%}
      {%- do lits.append("'" ~ x.strftime(fmt) ~ "'") -%}
    {%- else -%}
      {%- do exceptions.raise_compiler_error(this ~ ": odi_partition.key_type '" ~ kt ~ "' geçersiz.") -%}
    {%- endif -%}
  {%- endfor -%}

  {{ return({
      'column': (p.get('COLUMN') or '') | upper,
      'lo': lits[0], 'hi': lits[1],
      'name': start.strftime(p.get('NAME_FORMAT', 'P' ~ def_fmt)) | upper,
      'strategy': p.get('STRATEGY', 'none') | lower,
      'create': p.get('CREATE', true),
      'ugi': p.get('UPDATE_GLOBAL_INDEXES', true),
      'validate': p.get('VALIDATE_GRANULARITY', true),
      'label': start.isoformat() ~ ' (' ~ gran ~ ')'
  }) }}
{% endmacro %}

{# Model SQL'i içinde kaynak filtresi:
     where {{ odi_partition_filter('t.ISLEM_TARIHI') }}
   -> t.ISLEM_TARIHI >= DATE '2026-10-01' and t.ISLEM_TARIHI < DATE '2026-10-02'
   Kaynak kolon tipi target'tan farklıysa key_type / format ile override edilir. #}
{% macro odi_partition_filter(column=none, key_type=none, format=none, granularity=none) %}
  {%- if not execute -%}{{ return('1 = 1') }}{%- endif -%}
  {%- set base = odi_upper_dict(config.get('odi_partition', {})) -%}
  {%- set p = {} -%}
  {%- for k, v in base.items() -%}{%- do p.update({k: v}) -%}{%- endfor -%}
  {%- if key_type -%}{%- do p.update({'KEY_TYPE': key_type}) -%}{%- endif -%}
  {%- if format -%}{%- do p.update({'FORMAT': format}) -%}{%- endif -%}
  {%- if granularity -%}{%- do p.update({'GRANULARITY': granularity}) -%}{%- endif -%}
  {%- set s = odi_part_spec(p) -%}
  {%- set col = column or s['column'] -%}
  {{ return(col ~ ' >= ' ~ s['lo'] ~ ' and ' ~ col ~ ' < ' ~ s['hi']) }}
{% endmacro %}

{# Target üzerinde partition aralığı predicate'i (prune için) — partition yoksa none #}
{% macro odi_partition_predicate(alias='t') %}
  {%- set s = odi_part_spec() -%}
  {%- if s is none -%}{{ return(none) }}{%- endif -%}
  {{ return(alias ~ '.' ~ s['column'] ~ ' >= ' ~ s['lo'] ~ ' and ' ~ alias ~ '.' ~ s['column'] ~ ' < ' ~ s['hi']) }}
{% endmacro %}
