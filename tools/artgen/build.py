"""Generate every image asset described in docs/asset-list.md.

    python tools/artgen/build.py                 # everything
    python tools/artgen/build.py --only STO,HND  # one group
    python tools/artgen/build.py --contact       # contact sheets + index
    python tools/artgen/build.py --report        # list assets on the fallback
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import time
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

import materials  # noqa: E402
import noise as N  # noqa: E402
import palette as P  # noqa: E402
import recipes  # noqa: E402
import scope  # noqa: E402
import specs  # noqa: E402

OUT = ROOT / "assets"
INDEX = ROOT / "docs" / "asset-manifest.csv"
CONTACT = ROOT / "tools" / "artgen" / "contact"

FOLDER = {
    "STO": "ui/hud", "DEP": "ui/hud", "CMP": "ui/hud", "DTH": "ui/panels",
    "ICO": "ui/icons", "CDX": "ui/codex", "MNU": "ui/menu", "TUT": "ui/prompts",
    "ACC": "ui/acc", "LDG": "art/loading", "BAND": "art/band-cards",
    "HND": "art/hands", "VFX": "vfx", "BRD": "brand",
}
RESTROOM_TEX = {"RST-04", "RST-05", "RST-06", "RST-07", "RST-08", "RST-14", "RST-15", "RST-17"}

# the pre-migration layout, needed once by --migrate
FOLDER_OLD = {
    "STO": "ui/hud", "DEP": "ui/hud", "CMP": "ui/hud", "DTH": "ui/panels",
    "ICO": "ui/icons", "CDX": "ui/codex", "MNU": "ui/menu", "TUT": "ui/prompts",
    "ACC": "ui/acc", "LDG": "art/loading", "BAND": "art/band-cards",
    "HND": "art/hands", "VFX": "vfx", "BRD": "brand",
}


def folder_old(a) -> str:
    g, n = a.group, a.num
    if g == "TEX":
        if n.startswith("B"):
            return "textures/flesh"
        if n.startswith("1"):
            return "textures/tissue"
        if n.startswith("2"):
            return "textures/infra"
        return "textures/utility"
    if g == "RST":
        return "textures/restroom" if a.id in RESTROOM_TEX else "ui/panels"
    if g == "CDX" and n in ("21", "22", "23"):
        return "art/codex"
    return FOLDER_OLD.get(g, "misc")


def is_pending_3d(a) -> bool:
    """True when the row needs geometry, a rig or a shader.

    The generator must not emit a picture for these. A procedural PNG of a
    rigged hand is worse than nothing, because it looks finished.
    """
    return scope.classify(a).startswith("3D")


def folder_for(a) -> str:
    """Destination path under assets/.

    The top level is the pipeline split from tools/artgen/scope.py:
      2d/  2D pipeline, sprite and UI work
      3d/  3D pipeline, anything a 3D material, mesh or shader consumes
    2D-TEX files are produced as flat images but belong under 3d/textures
    because that is where they are consumed.
    """
    cls = scope.classify(a)
    g, n = a.group, a.num

    if cls == "3D-RIG":
        return "3d/models/characters"
    if cls == "3D-MODEL":
        return "3d/models/props"
    if cls == "3D-SHADER":
        return "3d/materials"
    if cls == "3D-FX":
        return "3d/fx/decals" if g == "TEX" else "3d/fx/effects"
    if cls == "2D-TEX":
        kind = {"RST": "restroom"}.get(g)
        if kind is None:
            kind = ("shells" if n.startswith("B") else "tissue" if n.startswith("1")
                    else "infra" if n.startswith("2") else "utility")
        return f"3d/textures/{kind}"

    if cls == "2D-FX":
        return "2d/fx"
    if cls == "2D-ART":
        return {"BAND": "2d/art/depth", "LDG": "2d/art/loading", "BRD": "2d/brand"}.get(g, "2d/art")
    # 2D-UI
    if g == "CDX" and n in ("21", "22", "23"):
        return "2d/art/codex"
    return {
        "STO": "2d/ui/hud", "DEP": "2d/ui/hud", "CMP": "2d/ui/hud",
        "ICO": "2d/ui/icons", "CDX": "2d/ui/codex", "MNU": "2d/ui/menu",
        "TUT": "2d/ui/prompts", "DTH": "2d/ui/panels", "ACC": "2d/ui/acc",
        "HND": "2d/ui/hud/hands", "RST": "2d/ui/panels", "VFX": "2d/fx",
    }.get(g, "2d/art")


def _as_rgba(arr: np.ndarray) -> np.ndarray:
    """Keep alpha. Recipes return RGBA; texture maps are opaque."""
    if arr.ndim == 2:
        arr = np.repeat(arr[:, :, None], 3, axis=2)
    if arr.shape[2] == 3:
        out = np.full(arr.shape[:2] + (4,), 255.0, np.float32)
        out[:, :, :3] = arr
        return out
    return arr.astype(np.float32)


def render(a) -> np.ndarray:
    """-> float RGBA array for the whole asset (strips are wide)."""
    if a.group == "TEX" and a.id in materials.TEX_MAP:
        key, out = materials.TEX_MAP[a.id]
        rgb = materials.render(key, out, a.h, a.w)
        if rgb.ndim == 2:
            rgb = np.repeat(rgb[:, :, None], 3, axis=2)
        return rgb
    fn = recipes.RECIPES[recipes.pick_recipe(a)]
    return _as_rgba(fn(a))


def render_outputs(a) -> list[tuple[str, np.ndarray]]:
    """-> [(filename_stem, rgba uint8 array)] for every PNG this asset emits."""
    files = specs.output_files(a)
    out: list[tuple[str, np.ndarray]] = []

    if len(files) == 1 and a.frames > 1 and a.kind == "atlas":
        cols = min(a.frames, max(1, int(np.ceil(np.sqrt(a.frames)))))
        rows = int(np.ceil(a.frames / cols))
        keep_w, keep_h, keep_frames = a.w, a.h, a.frames
        a.frames = 1
        tiles = []
        for i in range(keep_frames):
            a.index = i
            tiles.append(render(a))
        a.frames, a.index = keep_frames, 0
        ch = tiles[0].shape[2]
        sheet = np.zeros((rows * keep_h, cols * keep_w, ch), np.float32)
        for i, t in enumerate(tiles):
            r, c = divmod(i, cols)
            sheet[r * keep_h:(r + 1) * keep_h, c * keep_w:(c + 1) * keep_w] = t
        out.append((files[0][0], sheet))
        return out

    for i, (stem, w, h) in enumerate(files):
        if len(files) > 1:
            a.index = i
        a.w, a.h = w, h
        out.append((stem, render(a)))
    a.index = 0
    return out


def save(arr: np.ndarray, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img = np.clip(arr, 0, 255).astype(np.uint8)
    if img.ndim == 2:
        Image.fromarray(img, "L").save(path, optimize=True)
    elif img.shape[2] == 4:
        Image.fromarray(img, "RGBA").save(path, optimize=True)
    else:
        Image.fromarray(img, "RGB").save(path, optimize=True)
    return img.shape[1], img.shape[0]


# ------------------------------------------------------------- contact ----

def _checker(w, h, size=10, a=(58, 46, 48), b=(44, 34, 36)):
    yy, xx = np.mgrid[0:h, 0:w]
    m = ((xx // size + yy // size) % 2).astype(bool)
    img = np.where(m[..., None], np.array(b, np.float32), np.array(a, np.float32))
    return Image.fromarray(img.astype(np.uint8), "RGB")


def contact_sheets(records, by_id):
    CONTACT.mkdir(parents=True, exist_ok=True)
    font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 13)
    groups: dict[str, list] = {}
    for r in records:
        groups.setdefault(r["group"], []).append(r)

    all_thumbs = []
    for g, rows in groups.items():
        rows.sort(key=lambda r: r["id"])
        cols = 6
        cell, pad, lab = 150, 10, 20
        n = len(rows)
        r_n = int(np.ceil(n / cols))
        sheet = Image.new("RGB", (cols * (cell + pad) + pad,
                                  r_n * (cell + pad + lab) + pad), (28, 22, 24))
        d = ImageDraw.Draw(sheet)
        for i, r in enumerate(rows):
            rr, cc = divmod(i, cols)
            x = pad + cc * (cell + pad)
            y = pad + rr * (cell + pad + lab)
            tile = None
            for stem, rel_path, _, _ in r["files"]:
                p = OUT / rel_path
                if p.exists():
                    tile = Image.open(p).convert("RGBA")
                    break
            if tile is None:
                continue
            tile.thumbnail((cell, cell), Image.LANCZOS)
            box = _checker(cell, cell)
            if tile.mode == "RGBA":
                box.paste(tile, ((cell - tile.width) // 2, (cell - tile.height) // 2), tile)
            else:
                box.paste(tile.convert("RGB"), ((cell - tile.width) // 2, (cell - tile.height) // 2))
            sheet.paste(box, (x, y))
            d.text((x, y + cell + 3), f"{r['id']} {r['pri']}", font=font, fill=(226, 214, 200))
            all_thumbs.append(box.resize((64, 64), Image.LANCZOS))
        sheet.save(CONTACT / f"{g}.png", optimize=True)

    if all_thumbs:
        cols = 16
        r_n = int(np.ceil(len(all_thumbs) / cols))
        master = Image.new("RGB", (cols * 66 + 8, r_n * 66 + 8), (20, 16, 17))
        for i, t in enumerate(all_thumbs):
            rr, cc = divmod(i, cols)
            master.paste(t, (8 + cc * 66, 8 + rr * 66))
        master.save(CONTACT / "_all.png", optimize=True)
    return len(groups)


# ---------------------------------------------------------------- main ----

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--contact", action="store_true")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--clean", action="store_true")
    ap.add_argument("--contact-only", action="store_true",
                    help="rebuild contact sheets from the last manifest, no rendering")
    ap.add_argument("--index-only", action="store_true",
                    help="rewrite the manifest from disk, no rendering")
    ap.add_argument("--migrate", action="store_true",
                    help="move artgen files into the current folder scheme")
    ap.add_argument("--dry-run", action="store_true",
                    help="with --migrate, report the moves without doing them")
    args = ap.parse_args()

    if args.migrate:
        assets = specs.parse(ROOT / "docs" / "asset-list.md")
        # index every existing artgen png by stem, so a file can be moved from
        # wherever it currently sits. This makes --migrate idempotent and lets
        # it converge after folder_for() changes, which a fixed "old path"
        # table cannot do.
        by_stem = {}
        for dp, _, fns in os.walk(OUT):
            if "concept" in dp:
                continue
            for fn in fns:
                if fn.lower().endswith(".png"):
                    by_stem.setdefault(Path(fn).stem, Path(dp) / fn)

        moves, seen, collisions, already = [], {}, [], 0
        for a in assets:
            if is_pending_3d(a):
                continue
            dest_dir = OUT / folder_for(a)
            for stem, _, _ in specs.output_files(a):
                dest = dest_dir / f"{stem}.png"
                rel = dest.relative_to(OUT).as_posix()
                key = rel.lower()
                if key in seen:
                    collisions.append((seen[key], a.id))
                seen[key] = a.id
                if dest.exists():
                    already += 1
                    continue
                src = by_stem.get(stem)
                if src is None:
                    continue
                moves.append((src, dest))

        print(f"files indexed    : {len(by_stem)}")
        print(f"already in place : {already}")
        print(f"moves planned    : {len(moves)}")
        print(f"collisions       : {len(collisions)}")
        for a_, b_ in collisions[:10]:
            print(f"   COLLIDE {a_} vs {b_}")
        for (src, dst), n in sorted(Counter(
                (os.path.dirname(str(src)), os.path.dirname(str(dst))) for src, dst in moves).items()):
            print(f"   {src}  ->  {dst}   {n}")
        if args.dry_run:
            print("dry run, nothing moved")
            return
        for src, dst in moves:
            dst.parent.mkdir(parents=True, exist_ok=True)
            src.replace(dst)
        print("moved. run --index-only to refresh the manifest.")
        return

    if args.contact_only:
        records = json.loads((ROOT / "docs" / "asset-manifest.json").read_text(encoding="utf-8"))
        n = contact_sheets(records, {})
        print(f"contact sheets  : {n + 1} -> tools/artgen/contact/")
        return

    if args.index_only:
        md = ROOT / "docs" / "asset-list.md"
        records = []
        missing = 0
        # --migrate is one shot, so the expected path can be stale. Resolve by
        # stem first and fall back to wherever the file actually sits, so the
        # manifest heals itself instead of reporting phantom misses.
        by_stem = {}
        for dp, _, fns in os.walk(OUT):
            for fn in fns:
                if fn.lower().endswith(".png") and "concept" not in dp:
                    by_stem.setdefault(Path(fn).stem, os.path.join(dp, fn))
        for a in specs.parse(md):
            if is_pending_3d(a):
                continue
            rel = folder_for(a)
            written = []
            for stem, w, h in specs.output_files(a):
                p = OUT / rel / f"{stem}.png"
                if not p.exists() and stem in by_stem:
                    p = Path(by_stem[stem])
                if p.exists():
                    with Image.open(p) as im:
                        w, h = im.size
                else:
                    missing += 1
                written.append((stem, p.relative_to(OUT).as_posix(), w, h))
            records.append({
                "id": a.id, "group": a.group, "pri": a.pri,
                "recipe": recipes.pick_recipe(a), "section": a.section,
                "path": rel.replace("\\", "/"), "files": written,
            })
        with INDEX.open("w", newline="", encoding="utf-8") as fh:
            wtr = csv.writer(fh)
            wtr.writerow(["id", "group", "pri", "recipe", "file", "w", "h"])
            for r in records:
                for stem, path, w, h in r["files"]:
                    wtr.writerow([r["id"], r["group"], r["pri"], r["recipe"], path, w, h])
        (ROOT / "docs" / "asset-manifest.json").write_text(json.dumps(records, indent=1), encoding="utf-8")
        print(f"assets indexed  : {len(records)}")
        print(f"files           : {sum(len(r['files']) for r in records)}")
        print(f"missing on disk : {missing}")
        if args.contact:
            print(f"contact sheets  : {contact_sheets(records, {}) + 1}")
        return

    md = ROOT / "docs" / "asset-list.md"
    assets = specs.parse(md)
    if args.only:
        want = {s.strip().upper() for s in args.only.split(",")}
        assets = [a for a in assets if a.group in want]

    if args.clean and OUT.exists():
        import shutil
        shutil.rmtree(OUT)

    t0 = time.time()
    records = []
    by_id = {}
    fallback = []
    pending = [a for a in assets if is_pending_3d(a)]
    assets = [a for a in assets if not is_pending_3d(a)]
    for a in assets:
        by_id[a.id] = a
        if recipes.pick_recipe(a) == "generic" and a.group != "TEX":
            fallback.append(a.id)
        rel = folder_for(a)
        written = []
        for stem, arr in render_outputs(a):
            w, h = save(arr, OUT / rel / f"{stem}.png")
            written.append((stem, str(Path(rel) / f"{stem}.png"), w, h))
        records.append({
            "id": a.id, "group": a.group, "pri": a.pri, "recipe": recipes.pick_recipe(a),
            "section": a.section, "path": rel.replace("\\", "/"),
            "files": written,
        })

    el = time.time() - t0
    total_files = sum(len(r["files"]) for r in records)
    print(f"assets parsed   : {len(assets)}"
          f"  (+{len(pending)} rows held for 3D work, deliberately not generated)")
    print(f"png files written: {total_files}")
    print(f"elapsed         : {el:.1f}s")

    INDEX.parent.mkdir(parents=True, exist_ok=True)
    with INDEX.open("w", newline="", encoding="utf-8") as fh:
        wtr = csv.writer(fh)
        wtr.writerow(["id", "group", "pri", "recipe", "file", "w", "h"])
        for r in records:
            for stem, path, w, h in r["files"]:
                wtr.writerow([r["id"], r["group"], r["pri"], r["recipe"], path, w, h])
    print(f"manifest        : {INDEX.relative_to(ROOT)}")

    (ROOT / "docs" / "asset-manifest.json").write_text(
        json.dumps(records, indent=1), encoding="utf-8")

    if args.report:
        print(f"\nfallback recipes ({len(fallback)}):")
        print("  " + ", ".join(fallback))
    if args.contact:
        n = contact_sheets(records, by_id)
        print(f"contact sheets  : {n + 1} -> tools/artgen/contact/")


if __name__ == "__main__":
    main()
