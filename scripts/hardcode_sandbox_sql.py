#!/usr/bin/env python3
"""
sql/sandbox/*.sql içindeki &P. (önek) ve &S. (şema) değişkenlerini sabit değerle değiştirir.
DEFINE / SET DEFINE çalışmayan araçlar (DBeaver, Toad, bazı SQL Developer ayarları) için.

  python scripts/hardcode_sandbox_sql.py                         # DOA_ / GLOBAL_DWH -> sql/sandbox/plain/
  python scripts/hardcode_sandbox_sql.py --prefix ABC_ --schema GLOBAL_DWH
  python scripts/hardcode_sandbox_sql.py --inplace               # sql/sandbox/*.sql dosyalarının ÜZERİNE yazar

Yapılanlar:
  &P.  -> önek     (örn. DOA_)
  &S.  -> şema     (örn. GLOBAL_DWH)
  SET DEFINE / SET VERIFY / SET PAGESIZE / SET LINESIZE / DEFINE P|S / WHENEVER SQLERROR satırları silinir
  PROMPT ...  ->  -- ...   (yorum)
Sonuçta dosyada '&' kalırsa hata verir ve o dosyayı yazmaz.
Sadece dosyaları değiştirir; veritabanına bağlanmaz.
"""
import argparse
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(HERE, "sql", "sandbox")

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--prefix", default="DOA_", help="tablo öneki (varsayılan DOA_)")
ap.add_argument("--schema", default="GLOBAL_DWH", help="şema (varsayılan GLOBAL_DWH)")
ap.add_argument("--inplace", action="store_true", help="sql/sandbox/*.sql dosyalarının üzerine yaz")
ap.add_argument("--out", default=os.path.join(SRC, "plain"), help="çıktı klasörü (varsayılan sql/sandbox/plain)")
a = ap.parse_args()

P, S = a.prefix.strip().upper(), a.schema.strip().upper()
if not re.fullmatch(r"[A-Z][A-Z0-9_]+_", P) or len(P) < 3:
    sys.exit(f"Önek hatalı: {P!r}  (büyük harf, en az 3 karakter, '_' ile bitmeli, örn. DOA_)")
if not re.fullmatch(r"[A-Z][A-Z0-9_$#]*", S):
    sys.exit(f"Şema adı hatalı: {S!r}")

out_dir = SRC if a.inplace else a.out
os.makedirs(out_dir, exist_ok=True)

DROP = re.compile(r"^\s*(SET\s+(DEFINE|VERIFY|PAGESIZE|LINESIZE|SERVEROUTPUT)\b|DEFINE\s+[PS]\s*=|WHENEVER\s+SQLERROR)", re.I)

files = sorted(glob.glob(os.path.join(SRC, "*.sql")))
if not files:
    sys.exit(f"{SRC} altında .sql yok")

ok = 0
for path in files:
    text = open(path, encoding="utf-8").read()
    lines = []
    for line in text.split("\n"):
        if DROP.match(line):
            continue
        if re.match(r"^\s*PROMPT\b", line, re.I):
            line = "-- " + re.sub(r"^\s*PROMPT\s?", "", line, flags=re.I)
        lines.append(line.replace("&P.", P).replace("&S.", S))
    new = "\n".join(lines)
    if "&" in new:
        bad = [l for l in new.split("\n") if "&" in l][:3]
        print(f"ATLANDI {os.path.basename(path)}: hâlâ '&' var -> {bad}")
        continue
    with open(os.path.join(out_dir, os.path.basename(path)), "w", encoding="utf-8") as f:
        f.write(new)
    ok += 1
    print(f"ok  {os.path.relpath(os.path.join(out_dir, os.path.basename(path)), HERE)}")

print(f"\n{ok}/{len(files)} dosya yazıldı  (önek={P}, şema={S})")
print("dbt tarafında da aynısı olmalı:  ODI_NAME_PREFIX=" + P + "   ORA_SCHEMA=" + S)
