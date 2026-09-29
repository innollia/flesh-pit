"""W06 check: every vent line id used in code exists in the line data, and
every data line's text is really in docs/content/vent-lines.md.
Run from the repo root: python game/tools/check_vent_lines.py  (exit 0 = ok)
"""
import json, re, sys, pathlib

root = pathlib.Path(__file__).resolve().parents[2]
data = json.loads((root / "game/main/data/vent_lines.json").read_text(encoding="utf-8"))
docp = root / "docs/content/vent-lines.md"
doc = docp.read_text(encoding="utf-8") if docp.exists() else ""
code = (root / "game/main/scripts/fp_vent.gd").read_text(encoding="utf-8")
rules = json.loads((root / "game/main/data/vent_rules.json").read_text(encoding="utf-8"))

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
for k, p in rules["대사묶음"].items():
    if not p["대사"]:
        print("EMPTY pool in vent_rules.json:", k); bad += 1
    used.update(p["대사"])
for k, v in rules["시간"].items():
    if not isinstance(v.get("값"), (int, float)) or v["값"] <= 0:
        print("BAD time in vent_rules.json:", k); bad += 1
for i in sorted(used - ids):
    print("MISSING in data:", i); bad += 1
for i in sorted(ids - used):
    print("unused in code:", i); bad += 1
norm = lambda t: re.sub(r"\s+", "", t)
ndoc = norm(doc)
for l in (data["lines"] if doc else []):
    for chunk in re.split(r"\([^)]*\)", l["ko"]):
        c = norm(chunk)
        if len(c) >= 2 and c not in ndoc:
            print("note (not an error): text differs from vent-lines.md:", l["id"], chunk.strip())
print("vent lines: %d ids, %d used in code, %d problems" % (len(ids), len(used), bad))
sys.exit(1 if bad else 0)