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

GÜVENLİK: Şema temizliği sadece kullanıcı / şema adı ODI_TEST ile başlıyorsa yapılır.
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

if not KEEP:
    section("TEMİZLİK + SETUP")
    if not USER.upper().startswith("ODI_TEST"):
        sys.exit(f"Güvenlik: şema temizliği sadece ODI_TEST* kullanıcısında/şemasında yapılır (şu an {USER}). --keep ile setup'sız koşun.")
    if TRINO:
        tbls = [r[0] for r in q(f"select table_name from {CATALOG}.information_schema.tables where table_schema = '{USER.lower()}'")]
        execute_all([f"drop table if exists {CATALOG}.{USER}.{t}" for t in tbls], "temizlik")
    else:
      execute_all(["""
BEGIN
  FOR t IN (SELECT table_name FROM user_tables WHERE temporary = 'N' AND nested = 'NO' AND iot_type IS NULL) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE "' || t.table_name || '" CASCADE CONSTRAINTS PURGE';
  END LOOP;
  FOR t IN (SELECT table_name FROM user_tables WHERE temporary = 'Y') LOOP
    EXECUTE IMMEDIATE 'TRUNCATE TABLE "' || t.table_name || '"';
    EXECUTE IMMEDIATE 'DROP TABLE "' || t.table_name || '" PURGE';
  END LOOP;
  FOR s IN (SELECT sequence_name FROM user_sequences WHERE sequence_name NOT LIKE 'ISEQ$$%') LOOP
    EXECUTE IMMEDIATE 'DROP SEQUENCE "' || s.sequence_name || '"';
  END LOOP;
END;"""], "temizlik")
    print("   şema temizlendi")
    execute_all(split_statements(open(os.path.join(SQL_DIR, "00_sources.sql")).read()), "00_sources")
    print(f"   {os.path.relpath(SQL_DIR, HERE)}/00_sources.sql")
    for m in models:
        if m["setup"].strip():
            execute_all(split_statements(m["setup"]), m["name"])
            print(f"   @setup {m['name']}")

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

section("Work tablo temizliği — odi_drop_work_tables (dry run)")
p = subprocess.run(["dbt", "run-operation", "odi_drop_work_tables", "--profiles-dir", HERE, "--project-dir", HERE, *TARGET_ARGS,
                    "--args", "{dry_run: true}"], capture_output=True, text=True)
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
