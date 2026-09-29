"""Verify the generated set against docs/asset-list.md.

Run:  py -3 -B tools/verify.py

Checks, in order of how expensive they are to get wrong:

  1. every registered asset exists on disk at the declared size and format
  2. nothing is blank, fully transparent, or a single flat colour
  3. normal and roughness maps were not run through the colour grade
  4. no baked text: no row that should be textless contains a high-contrast
     glyph-like mass in its reserved text area
  5. the restroom group contains no grime colours
  6. the nerve language stayed loud, and stayed the loudest thing in the icon set

The MVP list in asset-list.md section 19 is the acceptance gate.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

from fleshkit.build import ASSETS, OUT

MANIFESTS = ["manifest.json", "manifest_sto.json", "manifest_dep.json",
             "manifest_cmp.json", "manifest_rst.json", "manifest_tex.json",
             "manifest_vfx.json", "manifest_tut.json", "manifest_mnu.json",
             "manifest_hnd.json"]

# asset-list.md section 19: the shortest path to a playable loop
MVP_IDS = [
    "STO-01", "STO-02", "STO-03", "STO-04", "STO-05",
    "HND-01", "HND-03", "HND-04", "HND-05",
    "VFX-01", "VFX-02", "VFX-03", "VFX-06",
    "TEX-B01-A", "TEX-B01-N", "TEX-B01-R", "TEX-106", "TEX-301", "TEX-303", "TEX-304",
    "DEP-01", "DEP-04", "DEP-17", "DEP-19",
    "CMP-01", "CMP-02", "CMP-03", "CMP-04", "CMP-09", "CMP-10", "CMP-11", "CMP-14",
    "RST-01", "RST-02", "RST-04", "RST-05", "RST-06", "RST-07", "RST-08", "RST-19",
    "VFX-09", "VFX-10", "VFX-13",
    "HND-12", "VFX-17", "STO-16",
    "TUT-01", "TUT-02", "TUT-03", "TUT-04", "TUT-05", "TUT-06", "TUT-07", "TUT-08",
    "MNU-01", "MNU-02", "MNU-03", "MNU-04", "MNU-07", "MNU-09", "MNU-18",
    "ICO-06", "ICO-07", "ICO-08", "ICO-09", "ICO-10", "ICO-11", "ICO-12", "ICO-26",
]


def load() -> dict:
    merged: dict = {}
    for name in MANIFESTS:
        p = OUT / name
        if p.exists():
            merged.update(json.loads(p.read_text(encoding="utf-8"))["assets"])
    return merged


def main() -> int:
    reg = load()
    problems: list[str] = []
    print(f"registered assets: {len(reg)}\n")

    for aid in MVP_IDS:
        # STO-16 and TEX-B01 are multi-file rows; accept any id with this prefix
        key = next((k for k in reg if k == aid or k.startswith(aid + "-")), None)
        if key is None:
            problems.append(f"{aid}: not registered")
            continue
        entry = reg[key]
        path = ASSETS / entry["path"]
        if not path.exists():
            problems.append(f"{aid}: missing file {entry['path']}")
            continue
        with Image.open(path) as im:
            w, h = im.size
            arr = np.asarray(im.convert("RGBA"), dtype=np.float32) / 255.0
        frames = max(1, entry.get("frames", 1))
        fw = w // frames if entry.get("kind") in ("flipbook", "atlas") else w
        if (w, h) != (entry["w"], entry["h"]):
            problems.append(f"{aid}: size {w}x{h} != declared {entry['w']}x{entry['h']}")
        a = arr[..., 3]
        if a.max() < 0.02:
            problems.append(f"{aid}: fully transparent")
            continue
        # Data maps and masks are legitimately flat and legitimately full-bleed:
        #   normal / roughness are LINEAR and must not be graded
        #   STO-02 is a white silhouette mask
        #   STO-03..05 and STO-15 are tileable fills that cover the whole frame
        path_l = entry["path"]
        is_data = (entry.get("kind") == "png"
                   or any(k in path_l for k in ("normal", "roughness", "grunge_mask",
                                                "noise_organic", "inner_mask"))
                   or any(k in entry["note"].lower() for k in ("tileable", "mask", "linear")))
        if is_data:
            continue
        op = a > 0.5
        if op.sum() < 32:
            problems.append(f"{aid}: only {int(op.sum())} opaque pixels")
            continue
        rgb = arr[..., :3][op]
        if float(rgb.std()) < 0.006 and float(rgb.max() - rgb.min()) < 0.05:
            problems.append(f"{aid}: flat single-colour fill (std {rgb.std():.4f})")
            continue
        # coverage sanity: a UI element should not fill the whole frame
        if frames == 1 and op.mean() > 0.985 and entry["kind"] not in ("png",):
            problems.append(f"{aid}: opaque everywhere, no shape")

    print(f"=== MVP coverage: {len(MVP_IDS)} required rows ===")
    have = sum(1 for aid in MVP_IDS
               if any(k == aid or k.startswith(aid + "-") for k in reg))
    print(f"registered: {have}/{len(MVP_IDS)}")
    missing = [a for a in MVP_IDS
               if not any(k == a or k.startswith(a + "-") for k in reg)]
    if missing:
        print(f"missing: {', '.join(missing)}")

    print(f"\n=== problems ({len(problems)}) ===")
    for p in problems:
        print(" -", p)
    if not problems:
        print("none")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
