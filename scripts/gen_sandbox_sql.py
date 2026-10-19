#!/usr/bin/env python3
"""
sql/sandbox/*.sql dosyalarını model başlıklarından üretir (Oracle örnekleri).
Paylaşılan sandbox şemasında elle test için: her nesne adı &P. (SQL Developer / SQL*Plus
substitution değişkeni) önekiyle yazılır. Kullanıcı scriptlerin başında DEFINE P = <ÖNEK>_ verir.

  python scripts/gen_sandbox_sql.py
"""
import ast
import glob
import os
import re

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(HERE, "sql", "sandbox")
DAYS = {"day1": "2026-10-01", "day2": "2026-10-02", "day3": "2026-10-01"}
WORK = ["I$_", "C$_", "X$_", "E$_"]


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


def parse_models():
    models = []
    paths = sorted(glob.glob(os.path.join(HERE, "models", "odi", "**", "*.sql"), recursive=True)) + \
        sorted(glob.glob(os.path.join(HERE, "models", "flows", "**", "*.sql"), recursive=True))
    for path in paths:
        text = open(path, encoding="utf-8").read()
        m = re.search(r"\{#(.*?)#\}", text, re.S)
        alias = re.search(r"alias\s*=\s*'([^']+)'", text).group(1).upper()
        block, sec, setup, checks = m.group(1), None, [], {}
        for line in block.splitlines():
            st = line.strip()
            if st.startswith("@setup"):
                sec = "setup"; continue
            if st.startswith("@check"):
                sec = st.split()[1]; checks.setdefault(sec, []); continue
            if st.startswith("====="):
                sec = None; continue
            if sec == "setup":
                setup.append(line)
            elif sec and " :: " in st and " => " in st:
                desc, rest = st.split(" :: ", 1)
                sql, exp = rest.rsplit(" => ", 1)
                checks[sec].append((desc, sql, ast.literal_eval(exp)))
        models.append({"name": os.path.splitext(os.path.basename(path))[0], "alias": alias,
                       "setup": "\n".join(setup), "checks": checks})
    return models


models = parse_models()
src_text = open(os.path.join(HERE, "sql", "00_sources.sql"), encoding="utf-8").read()

# ---- önek alacak isimler
CREATE_RE = re.compile(r'^\s*CREATE\s+(?:GLOBAL\s+TEMPORARY\s+)?(TABLE|SEQUENCE|INDEX)\s+("?[\w$#]+"?)', re.I)
tables, seqs, names = [], [], set()
for text in [src_text] + [m["setup"] for m in models]:
    for st in split_statements(text):
        mm = CREATE_RE.match(st)
        if mm:
            n = mm.group(2).strip('"').upper()
            names.add(n)
            (tables if mm.group(1).upper() == "TABLE" else seqs if mm.group(1).upper() == "SEQUENCE" else []).append(n)
aliases = [m["alias"] for m in models]
names |= set(aliases)

# work tablo adları: I$_<alias> -> I$_&P.<alias>
work_map = {}
for a in aliases:
    for w in WORK:
        work_map[w + a] = w + "&P." + a
plain = sorted([n for n in names if n[:3] not in WORK], key=len, reverse=True)
work_names = sorted(set(work_map) | {n for n in names if n[:3] in WORK}, key=len, reverse=True)


def pfx(sql):
    out = sql
    for n in work_names:
        out = re.sub(r'(?<![\w$])' + re.escape(n) + r'(?![\w$])', (n[:3] + "&P." + n[3:]).replace("\\", "\\\\"), out, flags=re.I)
    for n in plain:
        out = re.sub(r'(?<![\w$])(?<!&P\.)' + re.escape(n) + r'(?![\w$])', "&P." + n, out, flags=re.I)
    # mg_flow_ckm kontrolündeki escape'li LIKE kalıbı
    out = out.replace(r"'I$\_T\_MG\_FLOW%'", r"'I$\_&P.T\_MG\_FLOW%'")
    return out


def stmt(s):
    s = s.rstrip()
    return s if s.endswith(";") else s + ";"


HEADER = """-- ============================================================================
--  {title}
--  Paylaşılan sandbox şeması için: TÜM nesneler &P. önekiyle (ör. DOA_SRC_CUSTOMER).
--  ÖNEK: büyük harf, '_' ile biten, şemada kimsenin kullanmadığı bir değer olmalı ve
--        dbt tarafındaki ODI_NAME_PREFIX ile AYNI olmalı.
--  SQL Developer: F5 (Run Script) ile çalıştır.  Bu dosya scripts/gen_sandbox_sql.py ile üretildi.
-- ============================================================================
SET DEFINE ON
SET VERIFY OFF
DEFINE P = DOA_
DEFINE S = GLOBAL_DWH
-- Tüm şemasız isimler bu şemaya gider (kendi kullanıcınla bağlansan bile). Şemanın kendisiyle bağlıysan etkisiz.
ALTER SESSION SET CURRENT_SCHEMA = &S.;
"""

GUARD = """
WHENEVER SQLERROR EXIT
BEGIN
  IF LENGTH('&P.') < 3 OR SUBSTR('&P.', -1) <> '_' OR '&P.' <> UPPER('&P.') THEN
    RAISE_APPLICATION_ERROR(-20900, 'Önek hatalı: en az 3 karakter, büyük harf, _ ile bitmeli. Şu an: &P.');
  END IF;
  IF SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') <> UPPER('&S.') THEN
    RAISE_APPLICATION_ERROR(-20900, 'Aktif şema &S. değil: ' || SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'));
  END IF;
END;
/
WHENEVER SQLERROR CONTINUE
"""
# create / veri scriptlerinde ilk hatada dur (ör. tablo zaten varsa ORA-00955 -> devam etme)
GUARD_STOP = GUARD.replace("WHENEVER SQLERROR CONTINUE\n", "")

os.makedirs(OUT, exist_ok=True)
files = {}

# ---- 00 precheck
files["00_precheck.sql"] = HEADER.format(title="00 — ÖN KONTROL (sadece okur, hiçbir şey değiştirmez)") + GUARD + """
PROMPT == Bu önekle başlayan nesne var mı? (BOŞ dönmeli. Dönüyorsa başka önek seç.)
SELECT object_type, object_name, created
  FROM all_objects
 WHERE owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
   AND (SUBSTR(object_name, 1, LENGTH('&P.')) = '&P.'
    OR SUBSTR(object_name, 1, 3 + LENGTH('&P.')) IN ('I$_&P.', 'C$_&P.', 'X$_&P.', 'E$_&P.'))
 ORDER BY 2;

PROMPT == Yetkiler (CREATE TABLE / CREATE SEQUENCE olmalı)
SELECT privilege FROM session_privs WHERE privilege IN ('CREATE TABLE', 'CREATE SEQUENCE', 'CREATE ANY TABLE', 'COMMENT ANY TABLE') ORDER BY 1;

PROMPT == Bağlı kullanıcı / aktif şema (aktif şema &S. olmalı; kullanıcı farklıysa dbt'de ORA_SCHEMA=&S. ver)
SELECT USER AS bagli_kullanici, SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AS aktif_sema FROM dual;
"""

# ---- 01 create
body = [HEADER.format(title="01 — TEST TABLOLARINI YARAT (kaynaklar + step log + her modelin target'ı)"), GUARD_STOP]
body.append("\nPROMPT == Kaynaklar + step log")
for st in split_statements(src_text):
    body.append(stmt(pfx(st)))
for m in models:
    if m["setup"].strip():
        body.append(f"\nPROMPT == {m['name']}  ->  &P.{m['alias']}")
        for st in split_statements(m["setup"]):
            body.append(stmt(pfx(st)))
body.append("COMMIT;")
files["01_create.sql"] = "\n".join(body) + "\n"

# ---- gün verileri
for i, day in enumerate(["day1", "day2", "day3"], start=2):
    t = open(os.path.join(HERE, "sql", f"{day}.sql"), encoding="utf-8").read()
    body = [HEADER.format(title=f"0{i} — GÜN {day[-1]} KAYNAK VERİSİ (sonra: dbt run --vars \"{{load_date: '{DAYS[day]}'}}\")"), GUARD_STOP]
    for st in split_statements(t):
        body.append(stmt(pfx(st)))
    files[f"0{i}_{day}_data.sql"] = "\n".join(body) + "\n"


# ---- kontroller
def fmt(v):
    if isinstance(v, list):
        return " | ".join(", ".join(str(x) for x in r) for r in v)
    return str(v)


for day in ["day1", "day2", "day3"]:
    body = [HEADER.format(title=f"KONTROL — GÜN {day[-1]} (dbt run'dan sonra; sadece okur)"), GUARD]
    body.append("SET PAGESIZE 200\nSET LINESIZE 200")
    for m in models:
        cs = m["checks"].get(day, [])
        if not cs:
            continue
        body.append(f"\nPROMPT ================ {m['name']}  (&P.{m['alias']})")
        sess = (f"(select max(sess_no) keep (dense_rank last order by log_date) from &P.ODI_STEP_LOG "
                f"where model_name like '%.&P.{m['alias']}')")
        for desc, sql, exp in cs:
            q = pfx(sql).replace(":sess", sess)
            own = "owner = sys_context('USERENV', 'CURRENT_SCHEMA') and "
            q = (q.replace("from user_tables where ", "from all_tables where " + own)
                  .replace("from user_tab_partitions where ", "from all_tab_partitions where table_" + own)
                  .replace("from user_ind_partitions where ", "from all_ind_partitions where index_" + own))
            body.append(f"PROMPT -- {desc}   ==> beklenen: {fmt(exp)}")
            body.append(stmt(q))
    files[f"check_{day}.sql"] = "\n".join(body) + "\n"

# ---- 99 drop: SADECE açık isim listesi, desen/şema taraması yok
drops = []
gtt = [n for n in tables if n.startswith("I$_") or n.startswith("E$_")]
all_tables = [n for n in tables if n not in gtt]
body = [HEADER.format(title="99 — TEMİZLİK: sadece bu testin yarattığı, ADI TEK TEK YAZILI nesneleri siler"), GUARD]
body.append("""
-- Şema taraması / LIKE deseni YOK. Aşağıdaki liste dışında hiçbir şeye dokunulmaz.
-- Hepsi &P. önekli: başka birinin tablosu bu isimlerle eşleşemez (00_precheck boş döndüyse).
DECLARE
  PROCEDURE drop_tab(p_name VARCHAR2, p_gtt BOOLEAN DEFAULT FALSE) IS
  BEGIN
    IF p_gtt THEN
      BEGIN EXECUTE IMMEDIATE 'TRUNCATE TABLE "&S."."' || p_name || '"';
      EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
    END IF;
    EXECUTE IMMEDIATE 'DROP TABLE "&S."."' || p_name || '" PURGE';
    DBMS_OUTPUT.PUT_LINE('dropped ' || p_name);
  EXCEPTION WHEN OTHERS THEN
    IF SQLCODE != -942 THEN RAISE; END IF;   -- yoksa geç
  END;
BEGIN""")
for n in gtt:
    body.append(f"  drop_tab('{n[:3]}&P.{n[3:]}', TRUE);")
gtt_set = {n[:3] + "&P." + n[3:] for n in gtt}
for a in aliases:
    for w in WORK:
        if w + "&P." + a not in gtt_set:
            body.append(f"  drop_tab('{w}&P.{a}');")
for n in all_tables:
    body.append(f"  drop_tab('&P.{n}');")
body.append("""END;
/""")
for s in seqs:
    body.append(f"""BEGIN EXECUTE IMMEDIATE 'DROP SEQUENCE "&S."."&P.{s}"';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -2289 THEN RAISE; END IF; END;
/""")
body.append("""
PROMPT == Kalan (olmamalı; mg_flow_ckm fail olduysa I$_&P.T_MG_FLOW_xxxxxx kalabilir, elle drop et)
SELECT object_type, object_name FROM all_objects
 WHERE owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
   AND (SUBSTR(object_name, 1, LENGTH('&P.')) = '&P.'
    OR SUBSTR(object_name, 1, 3 + LENGTH('&P.')) IN ('I$_&P.', 'C$_&P.', 'X$_&P.', 'E$_&P.'))
 ORDER BY 2;""")
files["99_drop.sql"] = "\n".join(body) + "\n"

for fn, content in files.items():
    with open(os.path.join(OUT, fn), "w", encoding="utf-8") as f:
        f.write(content)
print("\n".join(sorted(files)))
