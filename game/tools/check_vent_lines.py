"""W06 check: every vent line id used in code exists in the line data, and
every data line's text is really in docs/content/vent-lines.md.
Run from the repo root: python game/tools/check_vent_lines.py  (exit 0 = ok)
"""
import json, re, sys, pathlib

root = pathlib.Path(__file__).resolve().parents[2]
data = json.loads((root / "game/main/data/vent_lines.json").read_text(encoding="utf-8"))
doc = (root / "docs/content/vent-lines.md").read_text(encoding="utf-8")
code = (root / "game/main/scripts/fp_vent.gd").read_text(encoding="utf-8")

ids = {l["id"] for l in data["lines"]}
bad = 0
prefixes = sorted({i.split(".")[0] for i in ids})
pat = re.compile(r'"((?:%s)\.[a-z0-9_%%]+)"' % "|".join(prefixes))
used = set()
for m in pat.finditer(code):
    i = m.group(1)
    if "%d" in i:
        for n in range(2, 6):
            used.add(i.replace("%d", str(n)))
    else:
        used.add(i)
for i in sorted(used - ids):
    print("MISSING in data:", i); bad += 1
for i in sorted(ids - used):
    print("unused in code:", i); bad += 1
norm = lambda t: re.sub(r"\s+", "", t)
ndoc = norm(doc)
for l in data["lines"]:
    for chunk in re.split(r"\([^)]*\)", l["ko"]):
        c = norm(chunk)
        if len(c) >= 2 and c not in ndoc:
            print("TEXT not in vent-lines.md:", l["id"], chunk.strip()); bad += 1
print("vent lines: %d ids, %d used in code, %d problems" % (len(ids), len(used), bad))
sys.exit(1 if bad else 0)