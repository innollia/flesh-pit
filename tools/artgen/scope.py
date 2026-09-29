"""Classify every asset in asset-list.md as 2D work or 3D work.

Emits docs/asset-scope.csv and docs/asset-scope-2d-3d.md.

The point of this file: a lot of work listed under "image asset" is actually
3D work wearing a 2D filename. A first person hand is not a PNG. A rusted
ladder is not a tileable texture. Classify before budgeting.

    python tools/artgen/scope.py
"""

from __future__ import annotations

import csv
import sys
from collections import Counter, OrderedDict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import specs  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]

# ---- classes --------------------------------------------------------------
C = OrderedDict([
    ("2D-UI", "2D image, drop straight into the UI layer"),
    ("2D-ART", "2D illustration, needs an artist, not a generator"),
    ("2D-TEX", "seamless texture that feeds a 3D material instance"),
    ("2D-FX", "sprite or flipbook for a billboard particle"),
    ("3D-MODEL", "needs geometry, a picture cannot stand in for it"),
    ("3D-RIG", "needs geometry plus a skeleton plus clips"),
    ("3D-SHADER", "custom shader work, the file is only a mask"),
    ("3D-FX", "in engine effect, the file is a helper not the asset"),
])

# ---- default class per id prefix, then explicit overrides -----------------
DEFAULT = {
    "STO": "2D-UI", "DEP": "2D-UI", "ICO": "2D-UI", "CDX": "2D-UI",
    "TUT": "2D-UI", "DTH": "2D-UI", "MNU": "2D-UI", "ACC": "2D-UI",
    "CMP": "2D-UI", "RST": "2D-UI", "BAND": "2D-ART", "LDG": "2D-ART",
    "BRD": "2D-ART", "HND": "3D-RIG", "VFX": "2D-FX", "TEX": "2D-TEX",
}

OVERRIDE = {
    # hands: three of the twenty one are genuinely 2D
    "HND-17": "2D-FX", "HND-18": "2D-UI", "HND-19": "2D-UI", "HND-21": "2D-UI",
    # canary exists in the world as a creature, not a sprite
    "CMP-14": "3D-RIG",
    # restroom clean surfaces are material inputs
    "RST-04": "2D-TEX", "RST-05": "2D-TEX", "RST-06": "2D-TEX",
    "RST-07": "2D-TEX", "RST-08": "2D-TEX", "RST-14": "2D-TEX",
    "RST-15": "2D-TEX", "RST-17": "2D-TEX",
    # world decals need a decal shader, sprites need a particle system
    "TEX-309": "3D-FX", "TEX-310": "3D-FX", "TEX-311": "3D-FX",
    "TEX-312": "3D-FX", "TEX-313": "3D-FX",
    "TEX-115": "3D-SHADER", "TEX-117": "3D-SHADER", "TEX-107": "3D-SHADER",
    "TEX-108": "3D-SHADER",
}

# ids inside a group that are a different class from their group default
GROUP_SPLIT = {
    "TEX": {
        "3D-MODEL": ["202", "203", "204", "205", "208"],   # ladder, hatch, conduit, lift, shell
        "2D-FX": ["304", "305", "306", "307", "308", "314", "315"],
    },
    "VFX": {
        "3D-FX": ["06", "11", "12", "13", "14", "15", "17", "18", "21", "22"],
    },
    "HND": {
        "3D-RIG": [f"{i:02d}" for i in range(1, 17)] + ["20"],
    },
}

# ---- who does what --------------------------------------------------------
OWNER = {
    "2D-UI": "one person, days",
    "2D-ART": "illustrator",
    "2D-TEX": "one person, a few days",
    "2D-FX": "one person, a few days",
    "3D-MODEL": "3D artist, each item is its own day or more",
    "3D-RIG": "3D artist plus animator, the single largest cost here",
    "3D-SHADER": "graphics programmer",
    "3D-FX": "graphics programmer plus 3D artist",
}

# rough share of total art effort, used only for the headline number
WEIGHT = {
    "2D-UI": 0.2, "2D-ART": 1.0, "2D-TEX": 0.4, "2D-FX": 0.4,
    "3D-MODEL": 3.0, "3D-RIG": 8.0, "3D-SHADER": 5.0, "3D-FX": 3.0,
}


def classify(a):
    if a.id in OVERRIDE:
        return OVERRIDE[a.id]
    for cls, nums in GROUP_SPLIT.get(a.group, {}).items():
        if a.num in nums:
            return cls
    return DEFAULT.get(a.group, "2D-UI")


def main():
    assets = specs.parse(ROOT / "docs" / "asset-list.md")
    rows = []
    for a in assets:
        cls = classify(a)
        rows.append({
            "id": a.id, "group": a.group, "name": a.name, "pri": a.pri,
            "class": cls, "meaning": C[cls], "owner": OWNER[cls],
            "artgen_covers": "yes" if a.group != "TEX" or a.id in (
                "TEX-106", "TEX-114", "TEX-116", "TEX-117", "TEX-115", "TEX-107",
                "TEX-108", "TEX-309", "TEX-310", "TEX-311", "TEX-312", "TEX-313",
                "TEX-304", "TEX-305", "TEX-306", "TEX-307", "TEX-308", "TEX-314",
                "TEX-315") else "no",
        })

    out = ROOT / "docs" / "asset-scope.csv"
    with out.open("w", newline="", encoding="utf-8") as fh:
        wtr = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        wtr.writeheader()
        wtr.writerows(rows)

    by_class = Counter(r["class"] for r in rows)
    by_group = {}
    for r in rows:
        by_group.setdefault(r["group"], Counter())[r["class"]] += 1

    effort = sum(by_class[c] * WEIGHT[c] for c in by_class)
    two_d = sum(v for c, v in by_class.items() if c.startswith("2D"))
    three_d = sum(v for c, v in by_class.items() if c.startswith("3D"))

    print(f"rows       : {len(rows)}")
    print(f"2D rows    : {two_d}  ({two_d / len(rows) * 100:.0f}%)")
    print(f"3D rows    : {three_d}  ({three_d / len(rows) * 100:.0f}%)")
    print("by class   :", dict(by_class))
    print(f"effort skew: 2D {100 * sum(by_class[c] * WEIGHT[c] for c in by_class if c.startswith('2D')) / effort:.0f}%"
          f" / 3D {100 * sum(by_class[c] * WEIGHT[c] for c in by_class if c.startswith('3D')) / effort:.0f}%")
    print(f"csv        : {out.relative_to(ROOT)}")

    # markdown
    md = ["# 2D and 3D split", "",
          "Generated by `tools/artgen/scope.py` from [asset-list.md](asset-list.md).",
          "Machine readable twin: [asset-scope.csv](asset-scope.csv).", "",
          "## The point", "",
          "Most of the list is cheap 2D work. A small slice of it is 3D work that a PNG",
          "cannot stand in for, and that slice is most of the cost. Budgeting them as one",
          "bucket is how a project ends up with finished icons and one unusable hand.", "",
          "| Class | Rows | Share | What it means | Owner |",
          "| --- | --- | --- | --- | --- |"]
    for c, n in sorted(by_class.items(), key=lambda kv: -kv[1]):
        md.append(f"| `{c}` | {n} | {n / len(rows) * 100:.0f}% | {C[c]} | {OWNER[c]} |")
    md += ["", f"2D rows {two_d}, 3D rows {three_d}. Weighted by realistic effort the 3D slice is",
           f"roughly {100 * sum(by_class[c] * WEIGHT[c] for c in by_class if c.startswith('3D')) / effort:.0f}% of the work.", "",
           "## Per group", "",
           "| Group | Rows | 2D | 3D | Note |", "| --- | --- | --- | --- | --- |"]
    NOTE = {
        "HND": "the big one. 17 of 21 are rigged first person hands, not images",
        "CMP": "HUD chrome is 2D, the canary is a creature that needs a mesh",
        "RST": "the white exception is a material set, plus props that are not in this list",
        "TEX": "mixed: surfaces and maps are 2D, embedded infrastructure is geometry",
        "VFX": "half are honest sprite strips, half want to be in engine effects",
        "BAND": "pure illustration, but the promise should come from 3D first",
        "BRD": "pure 2D marketing art",
        "ICO": "the cheapest and highest value work in the whole project",
    }
    for g, cnt in by_group.items():
        t = sum(v for c, v in cnt.items() if c.startswith("2D"))
        h = sum(v for c, v in cnt.items() if c.startswith("3D"))
        md.append(f"| {g} | {sum(cnt.values())} | {t} | {h} | {NOTE.get(g, '')} |")

    md += ["", "## 3D work wearing a 2D filename", "",
           "These are the rows where the picture is a decoy. The PNG helps, it does not finish.", "",
           "| Id | Looks like | Actually is |", "| --- | --- | --- |",
           "| HND-01 to HND-16, HND-20 | 20 hand pictures | 1 rigged hand mesh with 5 poses and 6 mutation blends |",
           "| CMP-14 | canary sprite | canary mesh, 6 frame wing cycle, tether attachment |",
           "| TEX-202, 203, 204, 205, 208 | 5 seamless textures | 5 hard surface props embedded in flesh |",
           "| TEX-201 | enamel sign tile | decal projected onto a 3D surface |",
           "| TEX-115, 117 | alpha masks | dissolve and mucus growth shader graphs |",
           "| TEX-107, 108 | emissive and flow maps | nerve shader: wriggle, glow, direction |",
           "| TEX-309 to 313 | 5 decal images | decal material plus a projection system |",
           "| VFX-06, 11, 12, 13, 14, 15, 17, 18 | 8 flipbook strips | in engine effects: contraction, regrowth, vignette, bloom, pulse, surge, band entry, wipes |",
           "| RST-01, 09, 16 | toilet and lever prompts | the actual props are geometry and are not on this list |",
           "",
           "## Not on this list at all", "",
           "- the player body below the hands, and its mutation blends",
           "- every restroom prop except the wall, floor and steel",
           "- tunnel geometry, the digging tool models, drop beacons",
           "- the toilet interior that the player looks into while vomiting",
           "- all audio, which the design core already lists separately",
           "", "## How the two renderers fit", "",
           "`tools/artgen/` reads this table and covers the 2D rows. It is a generator, so it",
           "produces correct sizes, names, channels and seamless tiling, not final illustration.",
           "The 3D rows are marked `artgen_covers=no` in the CSV and are not generated at all,",
           "because a generated image for them would be misleading.", ""]
    (ROOT / "docs" / "asset-scope-2d-3d.md").write_text("\n".join(md), encoding="utf-8")
    print(f"markdown   : docs/asset-scope-2d-3d.md")


if __name__ == "__main__":
    main()
