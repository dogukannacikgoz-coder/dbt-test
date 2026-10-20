# Paylaşılan sandbox şemasında elle test

Ekibin ortak sandbox şemasında, **başkalarının tablolarına dokunmadan** tüm örnek akışları denemek için.

## Neden güvenli
- Bütün test nesneleri senin seçtiğin bir önekle yaratılır: `DOA_SRC_CUSTOMER`, `DOA_T_IU`, `DOA_ODI_STEP_LOG`, `DOA_SEQ_T_SCD` ...
- dbt de aynı öneki kullanır (`ODI_NAME_PREFIX`). Model `DOA_T_IU`'ya yazar; work tabloları `I$_DOA_T_IU`, `E$_DOA_T_IU` olur.
- Önek verilmezse hiçbir model çalışmaz (`odi_require_name_prefix: true`). Target adı önekle başlamıyorsa model hiçbir SQL çalıştırmadan durur.
- Work tablolarının DROP'u sadece framework'ün kendi açıp `ODI_DBT_WORK` ile işaretlediği tabloya yapılır.
- `99_drop.sql` sadece adı tek tek yazılı, önekli nesneleri siler. Şema taraması ya da LIKE deseni yoktur.
- `00_precheck.sql` önekin şemada boş olduğunu doğrular. Boş değilse başka bir önek seç.

## Adımlar
Önek: büyük harf, `_` ile biten, şemada kimsenin kullanmadığı bir değer (örnekte `DOA_`).
Her `.sql` dosyasının başında iki satır var: `DEFINE P = DOA_` (önek) ve `DEFINE S = GLOBAL_DWH` (şema). Kendi değerlerinle değiştir.
Script'ler `ALTER SESSION SET CURRENT_SCHEMA = &S.` ile başlar; kendi kullanıcınla bağlansan bile her şey o şemada yaratılır, aktif şema
farklıysa script durur. SQL Developer'da **F5 (Run Script)** ile çalıştır.

| # | Ne | Nasıl |
|---|---|---|
| 0 | Ön kontrol (sadece okur) | `00_precheck.sql` → ilk sorgu **boş** dönmeli |
| 1 | Tabloları yarat | `01_create.sql` (ilk hatada durur) |
| 2 | dbt ortamı | aşağıdaki env değişkenleri + `dbt debug` |
| 3 | Gün 1 | `02_day1_data.sql` → `dbt run ... load_date: 2026-10-01` → `check_day1.sql` |
| 4 | Gün 2 | `03_day2_data.sql` → `dbt run ... load_date: 2026-10-02` → `check_day2.sql` |
| 5 | Gün 3 (geriye dönük) | `04_day3_data.sql` → `dbt run ... load_date: 2026-10-01` → `check_day3.sql` |
| 6 | Temizlik | `99_drop.sql` |

`check_dayN.sql` her kontrolün üstüne `==> beklenen: ...` yazar; çıktıyı onunla karşılaştır.

## SET DEFINE çalışmıyorsa → `plain/`
`sql/sandbox/plain/` altında aynı scriptlerin önek (`DOA_`) ve şeması (`GLOBAL_DWH`) dosyanın içine yazılı sürümü var:
`SET` / `DEFINE` / `WHENEVER` / `PROMPT` yok, her SQL aracında çalışır (DBeaver, Toad, SQL Developer).
Script olarak çalıştır ve aracında "hata olunca dur" açık olsun. Farklı önek/şema için:
`python scripts/gen_sandbox_sql.py --prefix X_ --schema Y`.

## dbt ortamı
```bash
export ORA_HOST=... ORA_PORT=1521 ORA_SERVICE=... ORA_USER=... ORA_PWD=...
export ORA_SCHEMA=<SANDBOX_ŞEMA>      # bağlandığın kullanıcı sandbox şemasının kendisiyse gerekmez
export ODI_NAME_PREFIX=DOA_           # SQL dosyalarındaki DEFINE P ile AYNI
dbt debug --profiles-dir .
dbt ls -s path:models/odi path:models/flows --output name   # 23 model
```

Bir günün tüm Oracle örnekleri (dbt `ref` sırasını kendisi kurar):
```bash
dbt run --profiles-dir . -s path:models/odi path:models/flows --vars "{load_date: '2026-10-01'}"
```
Tek tek denemek için (`cust_fin_daily_tmp02` önce `iu_basic_ckm`'in koşmasını ister):
```bash
dbt run --profiles-dir . -s ca_truncate_insert --vars "{load_date: '2026-10-01'}"
dbt run --profiles-dir . -s iu_basic_ckm       --vars "{load_date: '2026-10-01'}"
...
```
Önce ne yapacağını görmek istersen `dbt compile -s <model>`; SQL `target/compiled/` altına yazılır, veritabanına bir şey gönderilmez (materialization adımları değil, sadece model SELECT'i).

## Dikkat
- Bağlandığın kullanıcı sandbox şemasının sahibi değilse (`ORA_SCHEMA` farklıysa) work tabloları için
  `CREATE ANY TABLE` ve işaret için `COMMENT ANY TABLE` gerekir. `00_precheck.sql` yetkileri listeler.
- `odi_parallel_dml` kapalı; ortak ortamı yormamak için örnek veri küçük (onlarca satır).
- `--full-refresh` sadece `iu_basic_ckm`'de açık. Diğer modellerde model hiçbir şey yapmadan fail olur.
- `odi_drop_work_tables` run-operation'ını sandbox'ta çalıştırmana gerek yok. Temizlik `99_drop.sql` ile.
- Bu dosyalar `scripts/gen_sandbox_sql.py` ile model başlıklarından üretilir. Model başlıklarındaki
  `@setup` DDL'leri öneksizdir; sandbox'ta onları değil buradaki scriptleri kullan.
