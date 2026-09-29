"""Build runner: save assets, emit a manifest, and verify the whole set.

Every asset is produced by a function registered here with its ID, so
``build.py`` can rebuild the entire 333-file set from scratch, or any subset,
and ``verify.py`` can check the result against docs/asset-list.md without
anyone having to eyeball 333 files.

Determinism: each asset gets a seed derived from its ID, so a rebuild is
byte-identical unless the recipe changed.  That is what makes it safe for four
sessions to write into these folders at once.
"""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets"
OUT = ROOT / "tools" / "out"
MANIFEST = OUT / "manifest.json"

# id -> (relative path under assets/, spec string, priority)
REGISTRY: dict[str, dict] = {}


def seed_of(asset_id: str) -> int:
    """Stable per-asset seed from the ID, so rebuilds are reproducible."""
    return int(hashlib.sha256(asset_id.encode("utf-8")).hexdigest()[:8], 16) % (2 ** 31)


@dataclass
class Asset:
    id: str
    path: str                      # relative to assets/
    w: int
    h: int
    pri: str = "P1"
    kind: str = "png32"            # png32 | png | atlas | flipbook
    frames: int = 1
    note: str = ""
    files: list[str] = field(default_factory=list)
    extra: dict = field(default_factory=dict)


def register(asset_id: str, path: str, w: int, h: int, pri: str = "P1",
             kind: str = "png32", frames: int = 1, note: str = "", **extra) -> None:
    if asset_id in REGISTRY:
        raise KeyError(f"duplicate asset id {asset_id}")
    REGISTRY[asset_id] = Asset(id=asset_id, path=path, w=w, h=h, pri=pri, kind=kind,
                               frames=frames, note=note, extra=extra)


def save(img: Image.Image, rel_path: str, *, grade: bool = True, seed: int = 0) -> list[str]:
    """Write one image, creating parent folders.  Returns the written paths.

    ``grade`` applies the house look (``fleshkit.mood``) on the way out, so every
    group shares one response curve instead of each re-deciding it.  Pass
    ``grade=False`` for data, not pictures: normal maps, roughness maps, and
    white masks.  Grading those would corrupt them.
    """
    out = ASSETS / rel_path
    out.parent.mkdir(parents=True, exist_ok=True)
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    if grade:
        from .mood import to_image as _graded
        img = _graded(np.asarray(img, dtype=np.float32) / 255.0, seed=seed)
    img.save(out, format="PNG", optimize=True)
    return [str(out.relative_to(ROOT)).replace("\\", "/")]


def save_atlas(arr: np.ndarray, rel_path: str, *, grade: bool = True, seed: int = 0) -> list[str]:
    """Write an (h, w, 4) float or uint array as a PNG-32.

    Default ``grade=False``: atlases in this project are masks and data (grunge
    alpha, colour-blind sheets are exempt and pass grade=True explicitly).
    """
    a = np.clip(arr, 0.0, 1.0) if arr.dtype != np.uint8 else arr
    if a.dtype != np.uint8:
        a = (a * 255.0 + 0.5).astype(np.uint8)
    return save(Image.fromarray(np.ascontiguousarray(a), "RGBA"), rel_path,
                grade=grade, seed=seed)


def save_flipbook(frames: list[Image.Image], rel_path: str) -> list[str]:
    """Horizontal strip, plus one PNG per frame.  Both ship; the strip is the runtime asset."""
    paths: list[str] = []
    stem = rel_path.rsplit(".", 1)[0]
    w = max(f.width for f in frames)
    h = max(f.height for f in frames)
    strip = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        if f.mode != "RGBA":
            f = f.convert("RGBA")
        strip.paste(f, (i * w, 0))
        paths += save(f, f"{stem}_f{i:02d}.png")
    paths.append(save(strip, rel_path)[0])
    return paths


def tileable(img: Image.Image) -> Image.Image:
    """Make a texture seamless by mirroring, for maps that repeat on a wall."""
    w, h = img.size
    half_w, half_h = w // 2, h // 2
    tl, tr = img.crop((0, 0, half_w, half_h)), img.crop((half_w, 0, w, half_h))
    bl, br = img.crop((0, half_h, half_w, h)), img.crop((half_w, half_h, w, h))
    out = Image.new("RGBA", (w, h))
    out.paste(tl, (0, 0))
    out.paste(tr, (half_w, 0))
    out.paste(bl, (0, half_h))
    out.paste(br, (half_w, half_h))
    return out


def normal_from_height(height: np.ndarray, strength: float = 2.4) -> np.ndarray:
    """Sobel a height field into an OpenGL +Y-up tangent-space normal map.

    One convention for the whole project (asset-list.md section 0): Unity-style,
    OpenGL, green up.  Every normal map in the set goes through this function so
    the convention cannot drift between sessions.
    """
    gx = np.gradient(height.astype(np.float32), axis=1) * strength
    gy = np.gradient(height.astype(np.float32), axis=0) * strength
    nx, ny, nz = -gx, gy, np.ones_like(gx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.dstack([nx / ln, ny / ln, nz / ln])
    out = rgb * 0.5 + 0.5
    out = np.where((out[..., 2:3] < 1e-6), np.array([0.5, 0.5, 1.0], np.float32), out)
    return out.astype(np.float32)


def write_manifest(name: str = "manifest.json") -> Path:
    """Write the registry for one build group.

    Groups are written to separate files because several sessions generate
    different prefixes concurrently; a single shared file would be a lost-update
    race and would make it impossible to tell which group is actually complete.
    ``verify.py`` merges them.
    """
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    prev: dict = {}
    if path.exists():
        try:
            prev = json.loads(path.read_text(encoding="utf-8")).get("assets", {})
        except Exception:
            prev = {}
    merged = {**prev, **{k: _as_dict(v) for k, v in REGISTRY.items()}}
    data = {
        "tool_version": __import__("fleshkit").TOOL_VERSION,
        "count": len(merged),
        "assets": dict(sorted(merged.items())),
    }
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    return path


def _as_dict(v) -> dict:
    return {"path": v.path, "w": v.w, "h": v.h, "pri": v.pri, "kind": v.kind,
            "frames": v.frames, "note": v.note, "files": v.files, **v.extra}


_SAFE = re.compile(r"[^a-z0-9_]+")


def _slug(p: str) -> str:
    return _SAFE.sub("_", str(p).lower()).strip("_")


def fname(folders: str | list[str], *parts: str) -> str:
    """asset-list.md filename grammar: lowercase, underscores only.

    ``folders`` is the relative path under assets/, e.g. ``"ui/icons"`` or
    ``["textures", "flesh"]``.  Folder separators are preserved as real
    directories; only the filename itself is slugged.
    """
    dirs = [folders] if isinstance(folders, str) else list(folders)
    bits = [b for b in (_slug(p) for p in parts) if b]
    return "/".join(d.strip("/") for d in dirs) + "/" + "_".join(bits) + ".png"
