"""Parse docs/asset-list.md into normalised asset records.

The markdown is the single source of truth. If a row is added there, this
module will hand it to the renderer automatically.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

ID_RE = re.compile(r"^([A-Z]+)-([0-9A-Za-z]+)")

TIER = {"512": 512, "1K": 1024, "2K": 2048}

# Rows that expand into more than one file, keyed by id -> list of (suffix, mapkind)
EXPAND = {
    "TEX-B01": ("A", "N", "R"),
    "TEX-B02": ("A", "N", "R"),
    "TEX-B03": ("A", "N", "R"),
    "TEX-B04": ("A", "N", "R"),
    "TEX-B05": ("A", "N", "R"),
    "TEX-B06": ("A", "N", "R"),
    "TEX-B07": ("A", "N", "R"),
    "TEX-B08": ("A", "N", "R"),
}

# ids that emit a fixed list of extra sizes instead of the parsed spec
MULTISIZE = {
    "ACC-02": [(128, 128), (64, 64), (32, 32)],
    "ACC-12": [(1024, 1024), (512, 512)],
}

# ids whose spec is "matched": a rescale of another asset's panel
RESCALE_OF = {"ACC-06": "MNU-05", "ACC-07": "MNU-05"}

# huge strips get downscaled so a single file stays reasonable
SCALE_OVERRIDE = {
    "VFX-18": 0.25,   # 8 bands x 10 frames of 1024 would be 80 x 4 MB
    "VFX-09": 0.75,   # 24-frame vertical stream
    "VFX-10": 0.5,
    "VFX-11": 0.5,
    "VFX-12": 0.5,
    "VFX-13": 0.5,
    "VFX-14": 0.5,
    "VFX-15": 0.5,
    "VFX-16": 0.5,
    "VFX-17": 0.5,
    "VFX-05": 0.5,
    "VFX-20": 0.5,
    "HND-01": 0.5,
    "HND-03": 0.5,
    "HND-04": 0.5,
    "HND-05": 0.5,
    "HND-12": 0.5,
    "HND-13": 0.5,
    "HND-14": 0.5,
    "HND-06": 0.5,
    "HND-07": 0.5,
    "HND-08": 0.5,
    "HND-09": 0.5,
    "HND-10": 0.5,
    "HND-11": 0.5,
    "HND-15": 0.5,
    "HND-16": 0.5,
    "HND-17": 0.5,
    "HND-20": 0.5,
    "BRD-11": 0.5,
    "BRD-23": 0.5,
    "TEX-B01-N": 0.5,
    "TEX-B01-R": 0.5,
    "TEX-B02-N": 0.5,
    "TEX-B02-R": 0.5,
    "TEX-B06-N": 0.5,
    "TEX-B06-R": 0.5,
    "TEX-B08-N": 0.5,
    "TEX-B08-R": 0.5,
}


@dataclass
class Asset:
    id: str
    section: str
    name: str
    look: str
    spec: str
    fmt: str
    pri: str
    need: str
    w: int = 1024
    h: int = 1024
    frames: int = 1
    border: int = 0
    nineslice: bool = False
    mapkind: str = ""          # A / N / R for band expansions
    extra_sizes: list = field(default_factory=list)
    index: int = 0
    source_row: str = ""

    # ---- derived helpers -------------------------------------------------
    @property
    def group(self) -> str:
        m = ID_RE.match(self.id)
        return m.group(1) if m else "X"

    @property
    def num(self) -> str:
        m = ID_RE.match(self.id)
        return m.group(2) if m else "00"

    @property
    def kind(self) -> str:
        f = (self.fmt + " " + self.spec).lower()
        if "flipbook" in f:
            return "strip"
        if "atlas" in f:
            return "atlas"
        if "pair sheet" in f:
            return "pair"
        if self.frames > 1:
            return "multi"
        return "single"

    @property
    def tileable(self) -> bool:
        return "tileable" in self.spec.lower()

    def slug(self) -> str:
        s = re.sub(r"[^a-z0-9]+", "_", self.name.lower()).strip("_")
        words = [w for w in s.split("_") if w not in {"and", "or", "of", "the", "a", "with", "for"}]
        return "_".join(words[:5]) or "asset"


def _resolve_dims(spec: str) -> tuple[int, int, int]:
    """Spec column -> (w, h, frames)."""
    spec = spec.strip()
    m = re.search(r"(\d+)\s*x\s*(\d+)", spec)
    frames = 1
    if m:
        w, h = int(m.group(1)), int(m.group(2))
        tail = spec[m.end():]
        fm = re.search(r"\bx(\d+)\b", tail)
        if fm:
            frames = int(fm.group(1))
    else:
        tok = spec.split(",")[0].strip().upper()
        w = h = TIER.get(tok, 1024)
    return w, h, frames


def _border(spec: str, fmt: str, w: int, h: int) -> tuple[bool, int]:
    blob = f"{spec} {fmt}".lower()
    if "9-slice" not in blob:
        return False, 0
    m = re.search(r"9-slice\s+(\d+)", blob)
    b = int(m.group(1)) if m else max(6, min(w, h) // 8)
    return True, max(2, min(b, min(w, h) // 3))


def parse(md_path: Path) -> list[Asset]:
    out: list[Asset] = []
    section = ""
    for line in md_path.read_text(encoding="utf-8").splitlines():
        if line.startswith("## "):
            section = line[3:].strip()
        if not re.match(r"^\|\s*[A-Z]+-", line):
            continue
        cells = [c.strip() for c in line.split("|")[1:-1]]
        idc = cells[0]
        m = ID_RE.match(idc)
        if not m:
            continue
        if len(cells) == 6:          # band rows: ID | Name | Spec | Format | Pri | Need
            name, spec, fmt, pri, need = cells[1], cells[2], cells[3], cells[4], cells[5]
            look = ""
        else:
            name, look, spec, fmt, pri, need = cells[1], cells[2], cells[3], cells[4], cells[5], cells[6]

        # TEX-B01-A / N / R  ->  three assets sharing the row
        band = EXPAND.get(idc.split()[0])
        if band and "/" in idc:
            w, h, frames = _resolve_dims(spec)
            for kind in band:
                a = Asset(
                    id=f"{idc.split()[0]}-{kind}", section=section,
                    name=name, look=look, spec=spec, fmt=fmt, pri=pri, need=need,
                    w=w, h=h, frames=frames, mapkind=kind, source_row=line,
                )
                a.nineslice, a.border = _border(spec, fmt, a.w, a.h)
                a.w, a.h = _apply_scale(a)
                out.append(a)
            continue

        a = Asset(id=idc, section=section, name=name, look=look, spec=spec,
                  fmt=fmt, pri=pri, need=need, source_row=line)
        a.w, a.h, a.frames = _resolve_dims(spec)
        a.nineslice, a.border = _border(spec, fmt, a.w, a.h)
        a.extra_sizes = MULTISIZE.get(a.id, [])
        a.w, a.h = _apply_scale(a)
        out.append(a)
    return out


def _apply_scale(a: Asset) -> tuple[int, int]:
    k = SCALE_OVERRIDE.get(a.id, 1.0)
    if k == 1.0:
        return a.w, a.h
    a.frames = a.frames  # frames are a design value, keep the row honest
    return max(16, int(a.w * k)), max(16, int(a.h * k))


def output_files(a: Asset) -> list[tuple[str, int, int]]:
    """(filename_stem, w, h) for every PNG this asset emits."""
    stem = f"{a.group.lower()}_{a.num}_{a.slug()}"
    if a.id in RESCALE_OF:
        k = 1.25 if a.id.endswith("06") else 1.5
        return [(stem, int(a.w * k), int(a.h * k))]
    if a.extra_sizes:
        return [(f"{stem}_{w}", w, h) for w, h in a.extra_sizes]
    if a.kind == "multi":
        return [(f"{stem}_{i + 1:02d}", a.w, a.h) for i in range(a.frames)]
    return [(stem, a.w, a.h)]
