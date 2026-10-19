# odi_dbt — dbt ile ODI tarzı ETL framework (Oracle + Trino/Iceberg)

ODI Knowledge Module mantığını (I$ / C$ / E$ / X$ work tabloları, IND_UPDATE I/U/N/D,
CKM, partition yükleme, step log) dbt custom materialization'ları olarak çalıştırır.
Tüm kullanım kılavuzu: "odi_dbt — dbt ile ODI tarzı ETL Framework Kılavuzu" dokümanı.

## Yöntemler
| materialized | ODI KM |
|---|---|
| `odi_control_append` | IKM Oracle Control Append (+ truncate / partition truncate / delete) |
| `odi_incremental_update` | IKM Oracle Incremental Update (+ insert-only / update-only, CDC delete, delete missing) |
| `odi_merge` | IKM Oracle Incremental Update (MERGE) |
| `odi_scd` | IKM Oracle Slowly Changing Dimension (+ close_missing) |
| `odi_partition_exchange` | IKM Oracle Partition Exchange Load |
Her yöntemde: `odi_lkm` (C$ staging), `odi_flow_control` (CKM + recycle), `odi_partition`, step log.

## Güvenlik (DWH şemasında çalışırken)
Framework, binlerce tablonun olduğu bir şemada kendi yaratmadığı hiçbir tabloya DROP / TRUNCATE / DELETE atamaz:
| Kural | Nasıl |
|---|---|
| Şema taraması ile drop yok | Hiçbir makro "şemadaki tüm tabloları" listeleyip silmez. |
| Work tablo drop'u sadece işaretli tabloya | `I$_/C$_/X$_` yaratılınca `COMMENT 'ODI_DBT_WORK'` alır. Drop öncesi işaret kontrol edilir; işaretsizse model fail olur, tabloya dokunulmaz (ODI'ın kendi `I$_` tabloları dahil). `E$_` otomatik drop edilmez. |
| Work tablo adı önek zorunlu | `odi_flow_table / odi_error_table / odi_exchange_table / odi_lkm_table` önekle başlamıyorsa ya da target'ın kendisiyse derlemede durur. İstisna yok. |
| `--full-refresh` opt-in | Sadece `odi_allow_full_refresh: true` olan modelde TRUNCATE yapar; diğerleri hiçbir SQL çalıştırmadan fail olur. |
| Boş kaynak koruması | `odi_delete_missing` / `close_missing` açıkken kaynak (flow) `odi_delete_missing_min_rows` (default 1) satırdan azsa target'a dokunmadan durur. |
| `odi_drop_work_tables` | `schema` zorunlu, varsayılan dry-run, sadece `ODI_DBT_WORK` işaretli tabloları görür. |
| `test_runner.py` | Sadece `ODI_TEST*` şemasında koşar; sadece kendi script'lerinde adı geçen ve `ODI_DBT_TEST` işaretli tabloları siler; sequence silmez. |

TRUNCATE / partition truncate yalnızca model config'inde açıkça istenirse (`odi_truncate`, `odi_partition.strategy: truncate`) ve yalnızca o modelin target'ına yapılır.
Work şeması dbt kullanıcısının kendi şeması değilse `COMMENT ANY TABLE` yetkisi gerekir (ya da `odi_flow_mode: existing`).
ODI ile aynı work şemasını paylaşıyorsanız önekleri ayırabilirsiniz: `vars: {odi_work_prefixes: {'I$_': 'DI$_', 'C$_': 'DC$_', 'E$_': 'DE$_', 'X$_': 'DX$_'}}`.

## Hızlı başlangıç
```bash
docker run -d --name ora -p 1521:1521 -e ORACLE_PASSWORD=sys123 \
  -e APP_USER=odi_test -e APP_USER_PASSWORD=odi_test gvenzl/oracle-free:23-slim-faststart
pip install dbt-oracle
export ORA_HOST=localhost ORA_PORT=1521 ORA_SERVICE=FREEPDB1 ORA_USER=odi_test ORA_PWD=odi_test
python test_runner.py            # 23 model, 3 günlük senaryo, 106 kontrol
```

## Trino (Iceberg)
Aynı `materialized` adları ve `odi_*` config'leri `--target trino` ile çalışır; dbt `macros/odi/trino/`
altındaki materialization'ları seçer. Upsert'ler tek MERGE'e indirgenir, work tabloları `odi_i_/odi_c_/odi_e_`
önekli, partition exchange yok. Örnekler `models/trino/`.
```bash
docker compose -f docker/trino/docker-compose.yml up -d
pip install dbt-trino
export TRINO_HOST=localhost TRINO_PORT=8080 TRINO_USER=admin TRINO_CATALOG=iceberg TRINO_SCHEMA=odi_test
python test_runner.py --engine trino   # 20 model, 75 kontrol
```

## Kendi projene almak
1. `macros/odi/` klasörünü (alt klasörleriyle) projenin `macros/` altına kopyala (packages.yml ile değil).
2. `vars: {odi_log_table: <şema>.ODI_STEP_LOG}` ekle, log tablosunu aç (`sql/00_sources.sql`).
3. Yeni model için `templates/model_template.sql`.
4. UC4: `scripts/run_job.sh <tag> <load_date> [--retry]`.

## Klasörler
```
macros/odi/          ortak framework (dispatch ile motor farkları), CKM, partition spec, ops
macros/odi/oracle/   Oracle materialization'ları
macros/odi/trino/    Trino/Iceberg materialization'ları
models/odi/          Oracle: her yöntem/opsiyon için çalışan örnek (başlıkta DDL + beklenen sonuç)
models/flows/        Oracle gerçek akış örneği: dm_cad/cust_fin_daily (tmp01 -> tmp02 -> final)
models/trino/        Trino karşılıkları
sql/, sql/trino/     test kaynakları + gün 1/2/3 verisi
docker/trino/        lokal Trino + Iceberg REST + MinIO
scripts/         run_job.sh
templates/       model şablonu
test_runner.py   uçtan uca test
```
