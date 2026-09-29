"""World texture materials.

Each material produces albedo + height + roughness from the same fields, so
the normal map and the roughness map always agree with the albedo. Everything
is tileable, because the tunnel is a wrapping surface.
"""

from __future__ import annotations

import numpy as np

import palette as P
import noise as N

OUT = {
    "albedo": "albedo",
    "normal": "normal",
    "rough": "rough",
    "mask": "mask",
    "flow": "flow",
    "decal": "albedo",
    "particle": "albedo",
    "grad": "grad",
    "glow": "glow",
    "sign": "albedo",
}


# ---------------------------------------------------------------------------
# surface recipe table
#   stops  : colour ramp sampled by the base field
#   fibre  : weight of anisotropic grain (muscle, fascia)
#   cell   : weight of cellular lumpiness (fat, gland, tumour)
#   ridge  : weight of ridged fibre relief
#   vein   : weight of thin bright filaments
#   rib    : periodic ribs across the tile (corridor only)
#   gloss  : 0 matte .. 1 wet
#   bump   : normal map strength
# ---------------------------------------------------------------------------
SURFACES: dict[str, dict] = {
    "epithelium": dict(
        stops=[(0.0, P.FLESH_DARK), (0.35, P.FLESH_MID), (0.7, P.FLESH_BRIGHT), (1.0, P.FLESH_PALE)],
        fibre=0.25, cell=0.45, ridge=0.10, vein=0.20, gloss=0.55, bump=0.9, seed=101),
    "dermal": dict(
        stops=[(0.0, P.FLESH_DEEP), (0.3, P.FLESH_MID), (0.55, P.FAT_DEEP), (0.8, P.FAT), (1.0, P.FLESH_PALE)],
        fibre=0.15, cell=0.85, ridge=0.05, vein=0.30, gloss=0.60, bump=1.1, seed=102),
    "fascia": dict(
        stops=[(0.0, P.FLESH_DEEP), (0.25, P.MUCOSA), (0.6, P.BONE), (1.0, P.CLEAN_WHITE)],
        fibre=0.85, cell=0.05, ridge=0.70, vein=0.10, gloss=0.20, bump=1.5, seed=103),
    "muscle": dict(
        stops=[(0.0, P.FLESH_DARK), (0.35, P.FLESH_DEEP), (0.7, P.FLESH_MID), (1.0, P.FLESH_BRIGHT)],
        fibre=0.95, cell=0.10, ridge=0.55, vein=0.35, gloss=0.30, bump=1.6, seed=104),
    "glandular": dict(
        stops=[(0.0, P.FLESH_DEEP), (0.3, P.FLESH_PALE), (0.65, P.MUCOSA), (1.0, P.CLEAN_WHITE)],
        fibre=0.05, cell=0.95, ridge=0.05, vein=0.25, gloss=0.75, bump=1.3, seed=105),
    "nerve": dict(
        stops=[(0.0, P.FLESH_DEEP), (0.2, P.NERVE_DEEP), (0.55, P.NERVE), (1.0, P.NERVE_HOT)],
        fibre=0.90, cell=0.25, ridge=0.80, vein=0.55, gloss=0.45, bump=1.8, seed=106),
    "cavity": dict(
        stops=[(0.0, P.FLESH_DARK), (0.5, P.FLESH_DEEP), (0.85, P.FLESH_MID), (1.0, P.FLESH_GREY)],
        fibre=0.10, cell=0.15, ridge=0.05, vein=0.08, gloss=0.65, bump=0.5, seed=107),
    "corridor": dict(
        stops=[(0.0, P.FLESH_DARK), (0.3, P.FLESH_DEEP), (0.65, P.FLESH_MID), (1.0, P.FLESH_PALE)],
        fibre=0.35, cell=0.20, ridge=0.30, vein=0.30, gloss=0.55, bump=1.2, seed=108, rib=7),

    "muscle_detail": dict(
        stops=[(0.0, P.FLESH_DEEP), (0.5, P.FLESH_MID), (1.0, P.FLESH_BRIGHT)],
        fibre=1.0, cell=0.05, ridge=0.85, vein=0.45, gloss=0.25, bump=2.0, seed=201),
    "fat": dict(
        stops=[(0.0, P.FLESH_DEEP), (0.4, P.FAT_DEEP), (0.8, P.FAT), (1.0, P.BONE_WHITE)],
        fibre=0.05, cell=1.0, ridge=0.05, vein=0.10, gloss=0.70, bump=1.4, seed=202),
    "fascia_detail": dict(
        stops=[(0.0, P.FLESH_DEEP), (0.3, P.MUCOSA), (0.7, P.BONE), (1.0, P.CLEAN_WHITE)],
        fibre=1.0, cell=0.0, ridge=0.95, vein=0.15, gloss=0.15, bump=2.2, seed=203),
    "gland_detail": dict(
        stops=[(0.0, P.FLESH_DEEP), (0.35, P.FLESH_PALE), (0.75, P.MUCOSA), (1.0, P.CLEAN_WHITE)],
        fibre=0.0, cell=1.0, ridge=0.0, vein=0.20, gloss=0.80, bump=1.5, seed=204),
    "cartilage": dict(
        stops=[(0.0, P.CARTILAGE_DEEP), (0.5, P.CARTILAGE), (1.0, P.CLEAN_WHITE)],
        fibre=0.20, cell=0.30, ridge=0.10, vein=0.05, gloss=0.45, bump=0.9, seed=205),
    "nerve_detail": dict(
        stops=[(0.0, P.FLESH_DEEP), (0.15, P.NERVE_DEEP), (0.5, P.NERVE), (0.85, P.NERVE_HOT), (1.0, P.CLEAN_WHITE)],
        fibre=1.0, cell=0.30, ridge=1.0, vein=0.65, gloss=0.40, bump=2.4, seed=206),
    "tumor_a": dict(
        stops=[(0.0, P.TUMOR_DEEP), (0.45, P.TUMOR), (1.0, P.CLEAN_WHITE)],
        fibre=0.05, cell=0.95, ridge=0.15, vein=0.35, gloss=0.35, bump=1.6, seed=207),
    "tumor_b": dict(
        stops=[(0.0, P.FLESH_DEEP), (0.35, P.TUMOR_DEEP), (0.75, P.TUMOR), (1.0, P.FLESH_PALE)],
        fibre=0.10, cell=1.0, ridge=0.20, vein=0.60, gloss=0.30, bump=1.8, seed=208),
    "tumor_c": dict(
        stops=[(0.0, P.TUMOR_DEEP), (0.4, P.TUMOR), (0.8, P.BONE), (1.0, P.CLEAN_WHITE)],
        fibre=0.05, cell=1.0, ridge=0.35, vein=0.20, gloss=0.40, bump=2.2, seed=209),
    "mucosa": dict(
        stops=[(0.0, P.FLESH_MID), (0.5, P.MUCOSA), (1.0, P.CLEAN_WHITE)],
        fibre=0.10, cell=0.30, ridge=0.25, vein=0.15, gloss=0.85, bump=0.8, seed=210),
    "shell": dict(
        stops=[(0.0, P.CARTILAGE_DEEP), (0.35, P.CARTILAGE), (0.8, P.BONE), (1.0, P.CLEAN_WHITE)],
        fibre=0.10, cell=0.45, ridge=0.15, vein=0.05, gloss=0.20, bump=1.0, seed=211),
    "scar": dict(
        stops=[(0.0, P.FLESH_BRIGHT), (0.4, P.SCAR), (0.8, P.FLESH_PALE), (1.0, P.MUCOSA)],
        fibre=0.70, cell=0.20, ridge=0.85, vein=0.40, gloss=0.50, bump=1.4, seed=212),
    "vascular": dict(
        stops=[(0.0, P.FLESH_DEEP), (0.5, P.FLESH_MID), (1.0, P.FLESH_PALE)],
        fibre=0.30, cell=0.20, ridge=0.20, vein=0.85, gloss=0.40, bump=0.9, seed=213),
    "deep_shell": dict(
        stops=[(0.0, P.FLESH_DARK), (0.4, P.FLESH_DEEP), (0.8, P.FLESH_MID), (1.0, P.BONE)],
        fibre=0.45, cell=0.55, ridge=0.45, vein=0.25, gloss=0.25, bump=1.6, seed=214),
    "noise_base": dict(
        stops=[(0.0, P.FLESH_DARK), (1.0, P.FLESH_PALE)], fibre=0.2, cell=0.3,
        ridge=0.2, vein=0.0, gloss=0.0, bump=0.0, seed=301, grey=True),
    "flow_flesh": dict(
        stops=[(0.0, P.FLESH_DARK), (1.0, P.FLESH_PALE)], fibre=0.6, cell=0.2,
        ridge=0.4, vein=0.0, gloss=0.0, bump=0.0, seed=302, grey=True),
}


# ---------------------------------------------------------------------------
# id -> (surface, output)
# ---------------------------------------------------------------------------
TEX_MAP: dict[str, tuple[str, str]] = {}

_BANDS = ["epithelium", "dermal", "fascia", "muscle", "glandular", "nerve", "cavity", "corridor"]
for _i, _s in enumerate(_BANDS, start=1):
    for _k, _o in (("A", "albedo"), ("N", "normal"), ("R", "rough")):
        TEX_MAP[f"TEX-B0{_i}-{_k}"] = (_s, _o)

_DETAIL = {
    "TEX-101": "muscle_detail", "TEX-102": "fat", "TEX-103": "fascia_detail",
    "TEX-104": "gland_detail", "TEX-105": "cartilage", "TEX-106": "nerve_detail",
    "TEX-109": "tumor_a", "TEX-110": "tumor_b", "TEX-111": "tumor_c",
    "TEX-112": "mucosa", "TEX-113": "shell", "TEX-114": "scar",
    "TEX-116": "vascular", "TEX-208": "deep_shell", "TEX-301": "noise_base",
    "TEX-302": "flow_flesh",
}
for _k, _s in _DETAIL.items():
    TEX_MAP[_k] = (_s, "albedo")
TEX_MAP["TEX-107"] = ("nerve_detail", "mask")
TEX_MAP["TEX-108"] = ("nerve_detail", "flow")
TEX_MAP["TEX-115"] = ("scar", "mask")
TEX_MAP["TEX-117"] = ("mucosa", "mask")


def build_surface(key: str, h: int, w: int):
    """-> (albedo h x w x 3 float, height h x w float, rough h x w float)"""
    cfg = SURFACES[key]
    rng = np.random.default_rng(cfg["seed"])

    base = N.adaptive(h, w, lambda a, b: N.fbm(a, b, 4, 5, rng))
    if cfg["fibre"]:
        fib = N.adaptive(h, w, lambda a, b: N.fbm(a, b, 8, 4, rng, aniso=(0.12, 2.6)))
        base = base * (1.0 - cfg["fibre"]) + fib * cfg["fibre"]
    if cfg["cell"]:
        c = N.adaptive(h, w, lambda a, b: N.worley(a, b, max(2, int(min(a, b) / 26)), rng))
        base = base * (1.0 - cfg["cell"]) + (1.0 - c) * cfg["cell"]
    if cfg.get("rib"):
        y = np.arange(h, dtype=np.float32) / h
        rib = 0.5 + 0.5 * np.sin(2.0 * np.pi * cfg["rib"] * y)
        base = base * 0.55 + rib * 0.45

    base = np.clip((base - base.min()) / ((base.max() - base.min()) or 1.0), 0.0, 1.0)

    height = base.copy()
    if cfg["ridge"]:
        r = N.adaptive(h, w, lambda a, b: N.ridged(a, b, 6, 4, rng))
        height += cfg["ridge"] * 0.35 * r
    if cfg["vein"]:
        v = N.adaptive(h, w, lambda a, b: N.ridged(a, b, 3, 4, rng))
        veins = np.clip((v - 0.84) / 0.16, 0.0, 1.0) ** 1.5
        veins *= cfg["vein"]
        height += veins * 0.30

    stops = cfg["stops"]
    if cfg.get("grey"):
        stops = [(0.0, (0, 0, 0)), (1.0, (255, 255, 255))]

    idx = np.clip(height / max(1e-6, height.max() * 1.25), 0.0, 1.0)
    xs = np.linspace(0.0, 1.0, len(stops))
    cols = np.array([c for _, c in stops], np.float32)
    albedo = np.empty(idx.shape + (3,), np.float32)
    for ch in range(3):
        albedo[..., ch] = np.interp(idx, xs, cols[:, ch])

    if cfg["vein"]:
        v = N.adaptive(h, w, lambda a, b: N.ridged(a, b, 3, 4, rng))
        veins = np.clip((v - 0.84) / 0.16, 0.0, 1.0)[:, :, None] * cfg["vein"] * 0.55
        vein_col = np.array(P.FLESH_BRIGHT if not cfg.get("grey") else (255, 255, 255), np.float32)
        albedo = albedo * (1 - veins) + vein_col[None, None, :] * veins

    g = float(cfg["gloss"])
    rough = np.clip(0.95 - g * 0.55 - np.clip(height, 0, 3) * 0.10, 0.05, 1.0)
    return albedo, height, rough


def render(key: str, out: str, h: int, w: int) -> np.ndarray:
    albedo, height, rough = build_surface(key, h, w)
    if out == "albedo":
        return np.clip(albedo, 0, 255)
    if out == "normal":
        return N.sobel_normal(height, 2.2)
    if out == "rough":
        return np.clip(rough * 255.0, 0, 255)
    if out == "mask":
        return np.clip(np.clip(height, 0, 2) / 2.0 * 255.0, 0, 255)
    if out == "flow":
        hgt, wid = height.shape
        gy, gx = np.gradient(height.astype(np.float32))
        gx = -gx
        ang = (np.arctan2(gy, gx) / (2 * np.pi) + 1.0) % 1.0
        return np.stack([ang * 255, np.clip(np.hypot(gx, gy) * 6, 0, 1) * 255,
                         np.zeros_like(ang)], -1)
    raise ValueError(out)
