#!/usr/bin/env python3
"""
odi_dbt uçtan uca test.

Her modelin başındaki {# ... #} bloğu okunur:
  @setup          -> target / work tablo DDL'leri ('/' satırıyla ayrılmış)
  @check day1|2|3 -> "açıklama :: SQL => beklenen" satırları (:sess = o run'ın invocation id'si)

Akış:
  temizle -> sql/00_sources.sql -> tüm @setup'lar
  gün1 verisi -> dbt run (load_date 2026-10-01) -> @check day1
  gün2 verisi -> dbt run (load_date 2026-10-02) -> @check day2
  gün3 verisi -> dbt run (load_date 2026-10-01, geriye dönük) -> @check day3
  özel testler: CKM max error, exchange range check, full refresh, work tablo temizliği

Kullanım (Oracle):
  export ORA_HOST=localhost ORA_PORT=1521 ORA_SERVICE=FREEPDB1 ORA_USER=odi_test ORA_PWD=odi_test
  python test_runner.py                 # hepsi
Kullanım (Trino / Iceberg):
  docker compose -f docker/trino/docker-compose.yml up -d
  export TRINO_HOST=localhost TRINO_PORT=8080 TRINO_USER=admin TRINO_CATALOG=iceberg TRINO_SCHEMA=odi_test
  python test_runner.py --engine trino
  python test_runner.py -s tag:km_merge # sadece seçili modeller (dbt selector)
  python test_runner.py --keep          # şemayı temizlemeden (setup'ları atlar)

GÜVENLİK
  - Sadece kullanıcı / şema adı ODI_TEST ile başlıyorsa çalışır (DWH şemasında asla).
  - Şema taraması ile DROP YOK. Silinebilecek tablolar sadece:
      a) bu script'in kendi setup'larında (sql/00_sources.sql + modellerin @setup bloğu)
         ADIYLA geçen VE yaratılırken COMMENT 'ODI_DBT_TEST' ile işaretlenmiş tablolar
      b) test modellerinin work tabloları (I$_/C$_/X$_/E$_<alias>) VE COMMENT 'ODI_DBT_WORK'
    Listedeki bir isim şemada işaretsiz duruyorsa (başkasının tablosu) hiçbir şey silinmez,
    test durur. Sequence'lar hiç silinmez (varsa yeniden kullanılır).
"""
import ast
import glob
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ARGS = sys.argv[1:]
ENGINE = ARGS[ARGS.index("--engine") + 1] if "--engine" in ARGS else "oracle"
TRINO = ENGINE == "trino"
SQL_DIR = os.path.join(HERE, "sql", "trino") if TRINO else os.path.join(HERE, "sql")
TARGET_ARGS = ["--target", "trino"] if TRINO else []

if TRINO:
    import trino
    DBError = trino.exceptions.TrinoUserError
    CATALOG = os.getenv("TRINO_CATALOG", "iceberg")
    USER = os.getenv("TRINO_SCHEMA", "odi_test")          # temizlik güvenliği şema adına bakar
    conn = trino.dbapi.connect(host=os.getenv("TRINO_HOST", "localhost"), port=int(os.getenv("TRINO_PORT", "8080")),
                               user=os.getenv("TRINO_USER", "admin"), catalog=CATALOG,
                               http_scheme=os.getenv("TRINO_SCHEME", "http"))
    with conn.cursor() as _c:
        _c.execute(f"create schema if not exists {CATALOG}.{USER}"); _c.fetchall()
    conn = trino.dbapi.connect(host=os.getenv("TRINO_HOST", "localhost"), port=int(os.getenv("TRINO_PORT", "8080")),
                               user=os.getenv("TRINO_USER", "admin"), catalog=CATALOG, schema=USER,
                               http_scheme=os.getenv("TRINO_SCHEME", "http"))
else:
    import oracledb
    DBError = oracledb.DatabaseError
    USER = os.getenv("ORA_USER", "odi_test")
    conn = oracledb.connect(user=USER, password=os.getenv("ORA_PWD", "odi_test"),
                            dsn=f"{os.getenv('ORA_HOST', 'localhost')}:{os.getenv('ORA_PORT', '1521')}/{os.getenv('ORA_SERVICE', 'FREEPDB1')}")
SELECT = ARGS[ARGS.index("-s") + 1] if "-s" in ARGS else None
KEEP = "--keep" in ARGS
DAYS = {"day1": "2026-10-01", "day2": "2026-10-02", "day3": "2026-10-01"}

FAILS, PASSES = [], 0
TEST_MARK, WORK_MARK = "ODI_DBT_TEST", "ODI_DBT_WORK"
WORK_PREFIXES = ["odi_i_", "odi_c_", "odi_x_", "odi_e_"] if TRINO else ["I$_", "C$_", "X$_", "E$_"]

if not USER.upper().startswith("ODI_TEST"):
    sys.exit(f"Güvenlik: test sadece ODI_TEST* kullanıcısında/şemasında koşar (şu an {USER}). DWH şemasında çalıştırmayın.")


# ------------------------------------------------------------------ yardımcılar
def split_statements(text):
    stmts, buf = [], []
    for line in text.splitlines():
        if line.strip() == "/":
            s = "\n".join(buf).strip()
            if s:
                stmts.append(s)
            buf = []
        elif buf or (line.strip() and not line.strip().startswith("--")):
            buf.append(line)
    return stmts


def execute_all(stmts, label):
    c = conn.cursor()
    for s in stmts:
        try:
            c.execute(s)
            if TRINO:
                c.fetchall()          # trino client: sorgu sonuna kadar okunmadan tamamlanmaz
        except DBError as e:
            print(f"   ✗ {label}: {e}\n{s}\n")
            raise
    conn.commit()


def q(sql, sess=None):
    if sess is not None:
        sql = sql.replace(":sess", "'" + sess + "'")
    c = conn.cursor()
    c.execute(sql)
    return c.fetchall()


def normalize(rows):
    if len(rows) == 1 and len(rows[0]) == 1:
        return rows[0][0]
    return [tuple(r) for r in rows]


def check(name, actual, expected):
    global PASSES
    ok = actual == expected
    print(f"   {'✓' if ok else '✗'} {name}: {actual!r}" + ("" if ok else f"   (beklenen {expected!r})"))
    if ok:
        PASSES += 1
    else:
        FAILS.append(f"{name}: {actual!r} != {expected!r}")


def last_sess():
    r = q("select sess_no from odi_step_log order by log_date desc fetch first 1 row only")
    return r[0][0] if r else None


def dbt(*args, load_date, extra_vars="", expect_fail=False):
    vars_ = "{load_date: '" + load_date + "'" + (", " + extra_vars if extra_vars else "") + "}"
    cmd = ["dbt", "run", "--profiles-dir", HERE, "--project-dir", HERE, *TARGET_ARGS, "--vars", vars_, *args]
    if SELECT and "-s" not in args:
        cmd += ["-s", SELECT]
    print("   $ " + " ".join(cmd))
    p = subprocess.run(cmd, capture_output=True, text=True)
    out = p.stdout + p.stderr
    ok = p.returncode == 0
    if ok == expect_fail:
        print(out[-6000:])
        FAILS.append(f"dbt {' '.join(args)} -> rc {p.returncode} (expect_fail={expect_fail})")
        print("   ✗ dbt beklenmeyen sonuç")
    else:
        m = re.search(r"Done\. PASS=(\d+).*?ERROR=(\d+)", out)
        print(f"   ✓ dbt {'beklendiği gibi FAIL' if expect_fail else 'OK'}" + (f"  ({m.group(0)})" if m else ""))
    return out


def section(t):
    print("\n" + "=" * 80 + f"\n {t}\n" + "=" * 80)


# ------------------------------------------------------------------ model başlıklarını oku
def parse_models():
    models = []
    for path in sorted(glob.glob(os.path.join(HERE, "models", "**", "*.sql"), recursive=True)):
        text = open(path, encoding="utf-8").read()
        m = re.search(r"\{#(.*?)#\}", text, re.S)
        if not m:
            continue
        name = os.path.splitext(os.path.basename(path))[0]
        block, sec, setup, checks = m.group(1), None, [], {}
        for line in block.splitlines():
            st = line.strip()
            if st.startswith("@setup"):
                sec = "setup"
                continue
            if st.startswith("@check"):
                sec = st.split()[1]
                checks.setdefault(sec, [])
                continue
            if st.startswith("====="):
                sec = None
                continue
            if sec == "setup":
                setup.append(line)
            elif sec and " :: " in st and " => " in st:
                desc, rest = st.split(" :: ", 1)
                sql, exp = rest.rsplit(" => ", 1)
                checks[sec].append((desc, sql, ast.literal_eval(exp)))
        models.append({"name": name, "path": path, "setup": "\n".join(setup), "checks": checks})
    return models


def selected_names():
    if not SELECT:
        return None
    p = subprocess.run(["dbt", "ls", "--profiles-dir", HERE, "--project-dir", HERE, *TARGET_ARGS, "-s", SELECT,
                        "--resource-type", "model", "--output", "name", "--quiet"],
                       capture_output=True, text=True)
    return set(p.stdout.split())


def run_checks(models, day, sess):
    for m in models:
        cs = m["checks"].get(day, [])
        if not cs:
            continue
        print(f"\n -- {m['name']}")
        for desc, sql, exp in cs:
            try:
                actual = normalize(q(sql, sess=sess))
            except DBError as e:
                actual = f"SQL HATASI: {e}"
            check(f"{m['name']}: {desc}", actual, exp)


# ------------------------------------------------------------------ akış
models = [m for m in parse_models()
          if (os.sep + "trino" + os.sep in m["path"]) == TRINO]
names = selected_names()
if names is not None:
    models = [m for m in models if m["name"] in names]
print(f"{len(models)} model bulundu: " + ", ".join(m["name"] for m in models))

# ------------------------------------------------------------------ güvenli temizlik
CREATE_RE = re.compile(r'^\s*CREATE\s+(?:GLOBAL\s+TEMPORARY\s+)?TABLE\s+("?[\w$#]+"?)', re.I)


def ident(raw):
    """SQL'de yazıldığı haliyle tablo adı -> sözlükteki hali"""
    if raw.startswith('"'):
        return raw.strip('"')
    return raw.lower() if TRINO else raw.upper()


def created_tables(text):
    out = []
    for st in split_statements(text):
        m = CREATE_RE.match(st)
        if m:
            out.append((ident(m.group(1)), m.group(1)))
    return out


def model_alias(m):
    a = re.search(r"alias\s*=\s*'([^']+)'", open(m["path"], encoding="utf-8").read())
    return ident(a.group(1)) if a else None


def existing_tables():
    """şemadaki tablolar + yorumları (sadece okuma)"""
    if TRINO:
        rows = q(f"""select t.table_name, c.comment
                       from {CATALOG}.information_schema.tables t
                       left join system.metadata.table_comments c
                         on c.catalog_name = '{CATALOG}' and c.schema_name = t.table_schema and c.table_name = t.table_name
                      where t.table_schema = '{USER.lower()}'""")
        return {r[0]: (r[1], "N") for r in rows}
    rows = q("""select t.table_name, c.comments, t.temporary
                  from user_tables t
                  left join user_tab_comments c on c.table_name = t.table_name""")
    return {r[0]: (r[1], r[2]) for r in rows}


def mark(raw_name):
    execute_all([f"COMMENT ON TABLE {raw_name} IS '{TEST_MARK}'"], "işaret")


src_text = open(os.path.join(SQL_DIR, "00_sources.sql")).read()
TEST_TABLES = {n for n, _ in created_tables(src_text)}
for m in models:
    TEST_TABLES |= {n for n, _ in created_tables(m["setup"])}
ALIASES = {a for a in (model_alias(m) for m in models) if a}


def is_test_work_table(name):
    for p in WORK_PREFIXES:
        pp = p.lower() if TRINO else p
        for a in ALIASES:
            if name == pp + a or re.fullmatch(re.escape(pp + a) + r"_[0-9a-fA-F]{6}", name):
                return True
    return False


def plan_cleanup():
    to_drop, foreign = [], []
    for name, (cmt, temp) in existing_tables().items():
        if name in TEST_TABLES:
            (to_drop if cmt == TEST_MARK else foreign).append((name, temp))
        elif is_test_work_table(name):
            (to_drop if cmt == WORK_MARK else foreign).append((name, temp))
        # diğer tüm tablolar: hiç dokunulmaz
    return to_drop, foreign


def assert_ours():
    """gün verisi yüklenmeden önce: test tabloları var ve hepsi test işaretli mi"""
    info = existing_tables()
    # --keep: tablolar PDM ile açılmış olabilir (işaretsiz); ODI_TEST* şema şartı zaten geçerli
    bad = [] if KEEP else [n for n in TEST_TABLES if n in info and info[n][0] != TEST_MARK]
    missing = [n for n in TEST_TABLES if n not in info]
    if bad or missing:
        sys.exit("Güvenlik: test tabloları işaretsiz ya da eksik, gün verisi YÜKLENMEDİ.\n"
                 f"  işaretsiz: {sorted(bad)}\n  eksik: {sorted(missing)}")


if not KEEP:
    section("TEMİZLİK + SETUP")
    to_drop, foreign = plan_cleanup()
    if foreign:
        sys.exit("Güvenlik: aşağıdaki tablolar test isimleriyle aynı ama test/odi_dbt işareti YOK "
                 "(başkasının tablosu olabilir). HİÇBİR ŞEY SİLİNMEDİ:\n  " + "\n  ".join(n for n, _ in foreign))
    stmts = []
    for name, temp in to_drop:
        if TRINO:
            stmts.append(f'drop table {CATALOG}.{USER}."{name}"')
        else:
            if temp == "Y":
                stmts.append(f'TRUNCATE TABLE "{name}"')
            stmts.append(f'DROP TABLE "{name}" PURGE')
    execute_all(stmts, "temizlik")
    print(f"   {len(to_drop)} test tablosu silindi (sadece isim listesindeki + işaretli olanlar)")

    def run_setup(text, label):
        for st in split_statements(text):
            if re.match(r"\s*CREATE\s+SEQUENCE", st, re.I):
                try:
                    execute_all([st], label)
                except DBError as e:
                    if "ORA-00955" not in str(e):
                        raise
                    print("   (sequence zaten var, yeniden kullanılıyor)")
                continue
            execute_all([st], label)
            m = CREATE_RE.match(st)
            if m:
                mark(m.group(1))

    run_setup(src_text, "00_sources")
    print(f"   {os.path.relpath(SQL_DIR, HERE)}/00_sources.sql")
    for m in models:
        if m["setup"].strip():
            run_setup(m["setup"], m["name"])
            print(f"   @setup {m['name']}")

assert_ours()

for day in ["day1", "day2", "day3"]:
    section(f"{day.upper()} — load_date {DAYS[day]}")
    execute_all(split_statements(open(os.path.join(SQL_DIR, f"{day}.sql")).read()), day)
    print(f"   sql/{day}.sql yüklendi")
    dbt(load_date=DAYS[day])
    run_checks(models, day, last_sess())

names_set = {m["name"] for m in models}

IU = "trn_iu_basic_ckm" if TRINO else "iu_basic_ckm"
UPD = "upd_ts" if TRINO else "upd_dt"
if IU in names_set:
    section(f"CKM max error — {IU}, max_err=0 -> FAIL beklenir, target değişmemeli")
    before = q(f"select cust_no, {UPD} from t_iu order by 1")
    dbt("-s", IU, load_date=DAYS["day3"], extra_vars="max_err: 0", expect_fail=True)
    check("t_iu değişmedi", q(f"select cust_no, {UPD} from t_iu order by 1"), before)

if "pt_daily_exchange" in names_set:
    section("Exchange range check — model tüm günleri döndürür -> FAIL, target değişmemeli")
    before = q("select txn_id, amount from t_txn_daily_x order by 1")
    dbt("-s", "pt_daily_exchange", load_date=DAYS["day3"], extra_vars="break_filter: true", expect_fail=True)
    check("t_txn_daily_x değişmedi", q("select txn_id, amount from t_txn_daily_x order by 1"), before)

if IU in names_set:
    section(f"FULL REFRESH — {IU}: truncate + hepsi insert")
    dbt("-s", IU, "--full-refresh", load_date=DAYS["day3"])
    check("t_iu satır", normalize(q("select count(*) from t_iu")), 6)
    check("t_iu update kolonu hepsi boş", normalize(q(f"select count(*) from t_iu where {UPD} is not null")), 0)

section("Work tablo temizliği — odi_drop_work_tables (dry run, sadece işaretli tablolar)")
p = subprocess.run(["dbt", "run-operation", "odi_drop_work_tables", "--profiles-dir", HERE, "--project-dir", HERE, *TARGET_ARGS,
                    "--args", "{schema: " + USER + ", older_than_hours: 0}"], capture_output=True, text=True)
print("   " + "\n   ".join(l for l in p.stdout.splitlines() if "work tablo" in l or "dry-run" in l))
check("run-operation çalıştı", p.returncode, 0)

section("SONUÇ")
print(f" ✓ {PASSES} kontrol geçti")
if FAILS:
    print(f" ✗ {len(FAILS)} kontrol başarısız:")
    for f in FAILS:
        print("   - " + f)
    sys.exit(1)
print(" tüm kontroller geçti")
