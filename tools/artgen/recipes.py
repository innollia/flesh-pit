"""UI, VFX and brand recipes.

Every recipe returns a float32 RGBA array in 0..255 with shape (h, w, 4).
Horizontal flipbook strips are (h, w * frames, 4). The build step writes one
PNG per output file declared in specs.output_files.
"""

from __future__ import annotations

import numpy as np
from PIL import Image, ImageDraw

import noise as N
import palette as P

# ============================================================== helpers ====


def _finish(rgb, alpha=None):
    if alpha is None:
        alpha = np.ones(rgb.shape[:2], np.float32)
    out = np.zeros(rgb.shape[:2] + (4,), np.float32)
    out[:, :, :3] = np.clip(rgb, 0, 255)
    out[:, :, 3] = np.clip(alpha, 0, 1) * 255.0
    return out


def _rgb(h, w, c):
    return np.ones((h, w, 3), np.float32) * np.array(c, np.float32)[None, None, :]


def _grain(h, w, seed, amount=8.0, scale=6):
    rng = np.random.default_rng(seed)
    return (N.fbm(h, w, max(2, scale), 4, rng) - 0.5)[:, :, None] * amount


def _seed(a) -> int:
    return (abs(hash(a.id)) + a.index * 7919) % 99991


def _txt(a) -> str:
    return f"{a.id} {a.name} {a.look} {a.need}".lower()


def _field(h, w, seed, cells=0.35, fibre=0.15):
    def raw(hh, ww):
        rng = np.random.default_rng(seed)
        f = N.fbm(hh, ww, 4, 5, rng)
        f = f * (1 - fibre) + N.fbm(hh, ww, 8, 3, rng, aniso=(0.2, 2.2)) * fibre
        if cells:
            c = N.worley(hh, ww, max(2, int(min(hh, ww) / 40)), rng)
            f = f * (1 - cells) + (1 - c) * cells
        return f

    f = N.adaptive(h, w, raw)
    return (f - f.min()) / ((f.max() - f.min()) or 1)


def _ramp_img(f, stops):
    """Sample a colour ramp continuously. Quantising the field to 256 steps
    posterises wet flesh into flat blocks, so interpolate instead."""
    xs = np.linspace(0.0, 1.0, len(stops))
    cols = np.array([c for _, c in stops], np.float32)
    idx = np.clip(f, 0.0, 1.0)
    out = np.empty(idx.shape + (3,), np.float32)
    for ch in range(3):
        out[..., ch] = np.interp(idx, xs, cols[:, ch])
    return out


def _rounded(d: ImageDraw.ImageDraw, box, r, fill=None, outline=None, width=1):
    d.rounded_rectangle(box, radius=max(0, int(r)), fill=fill, outline=outline, width=width)


def _to_np(img: Image.Image) -> np.ndarray:
    return np.array(img.convert("RGBA"), np.float32)


def _resize(arr: np.ndarray, w: int, h: int) -> np.ndarray:
    """Resize an HxWx3 or HxWx4 float array."""
    ch = arr.shape[2] if arr.ndim == 3 else 1
    mode = "RGBA" if ch == 4 else "RGB"
    u8 = np.clip(arr, 0, 255).astype(np.uint8)
    if u8.ndim == 2:
        u8 = np.repeat(u8[:, :, None], 3, axis=2)
        mode = "RGB"
    return np.array(Image.fromarray(u8, mode).resize((w, h), Image.LANCZOS), np.float32)


# ======================================================= palette family ====

FAMILIES = {
    "clean":   [P.CLEAN_WHITE, P.TILE_WHITE, P.GROUT],
    "frost":   [P.CLEAN_WHITE, P.STEEL, P.STEEL_DARK],
    "bone":    [P.BONE, P.BONE_DEEP, P.BRASS],
    "nerve":   [P.NERVE, P.NERVE_DEEP, P.FLESH_DEEP],
    "tumor":   [P.TUMOR, P.TUMOR_DEEP, P.FLESH_MID],
    "flesh":   [P.FLESH_MID, P.FLESH_DEEP, P.FLESH_DARK],
    "ink":     [P.INK_SOFT, P.INK, P.FLESH_DARK],
    "paper":   [P.PAPER, P.PAPER_DAMP, P.FLESH_DEEP],
    "metal":   [P.STEEL, P.STEEL_DARK, P.INK],
    "water":   [P.WATER, P.FLESH_PALE, P.FLESH_MID],
    "muscle":  [P.FLESH_BRIGHT, P.FLESH_MID, P.FLESH_DEEP],
    "mucosa":  [P.MUCOSA, P.FLESH_PALE, P.FLESH_DEEP],
}

FAMILY_KEYWORDS = [
    ("nerve", "nerve"), ("yellow", "nerve"),
    ("tumor", "tumor"), ("growth", "tumor"), ("tumour", "tumor"),
    ("clean", "clean"), ("white", "clean"), ("sanitary", "clean"), ("clinical", "clean"),
    ("frost", "frost"), ("menu", "frost"), ("settings", "frost"),
    ("bone", "bone"), ("brass", "bone"), ("compass", "bone"),
    ("paper", "paper"), ("notebook", "paper"), ("page", "paper"), ("torn", "paper"),
    ("metal", "metal"), ("steel", "metal"), ("ladder", "metal"), ("conduit", "metal"),
    ("tile", "clean"), ("enamel", "clean"), ("ceramic", "clean"), ("flush", "clean"),
    ("ink", "ink"), ("dark", "ink"),
    ("mucosa", "mucosa"), ("slipper", "mucosa"),
    ("water", "water"), ("flush swirl", "water"),
]


def family(a) -> str:
    t = _txt(a)
    for kw, fam in FAMILY_KEYWORDS:
        if kw in t:
            return fam
    return "flesh"


def stops_for(a, fam=None) -> list:
    fam = fam or family(a)
    c = FAMILIES[fam]
    return [(0.0, c[0]), (0.55, c[1]), (1.0, c[2])]


# ========================================================== 9-slice panels ==

def r_nineslice(a):
    fam = family(a)
    style = {"clean": "clean", "frost": "frost", "paper": "paper", "bone": "bone"}.get(fam, "flesh")
    return _panel(a, style)


def _panel(a, style) -> np.ndarray:
    w, h, b = a.w, a.h, max(3, a.border)
    conf = {
        "clean": ([(0.0, P.CLEAN_WHITE), (0.55, P.TILE_WHITE), (1.0, P.GROUT)], P.TILE_WHITE, P.STEEL_DARK),
        "frost": ([(0.0, P.CLEAN_WHITE), (0.55, P.STEEL), (1.0, P.STEEL_DARK)], P.CLEAN_WHITE, P.STEEL_DARK),
        "bone":  ([(0.0, P.BONE), (0.55, P.BONE_DEEP), (1.0, P.BRASS_DARK)], P.BONE, P.BRASS_DARK),
        "paper": ([(0.0, P.CLEAN_WHITE), (0.55, P.PAPER), (1.0, P.PAPER_DAMP)], P.PAPER, P.FLESH_DEEP),
        "flesh": ([(0.0, P.FLESH_MID), (0.55, P.FLESH_DEEP), (1.0, P.FLESH_DARK)], P.FLESH_DEEP, P.FLESH_DARK),
    }[style]
    stops, base, edge = conf
    f = _field(h, w, _seed(a), cells=0.28, fibre=0.22)
    cleanish = style in ("clean", "frost")
    img = _ramp_img(f, stops) + _grain(h, w, _seed(a) + 1, 4 if cleanish else 9)

    m = np.zeros((h, w), np.float32)
    d = ImageDraw.Draw(Image.fromarray((m * 255).astype(np.uint8), "L"))
    d.rectangle([b, b, w - 1 - b, h - 1 - b], fill=255)
    mi = np.array(m, np.float32) / 255.0
    img = img * (1 - mi[:, :, None]) + np.array(base, np.float32)[None, None, :] * mi[:, :, None] * 0.9

    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    ed = np.minimum.reduce([xx, yy, w - 1 - xx, h - 1 - yy]).astype(np.int32)
    t = np.clip(ed / max(1.0, b), 0, 1)
    hl = np.clip((yy / max(1.0, h - 1)) * 0.5 + (xx / max(1.0, w - 1)) * 0.5, 0, 1)
    rim = (1.0 - t)
    light = (rim * hl)[:, :, None] * 0.40
    dark = (rim * (1 - hl))[:, :, None] * 0.50
    img = img * (1 - light) + np.array(P.BONE_WHITE, np.float32) * light
    img = img * (1 - dark) + np.array(edge, np.float32) * dark
    return _finish(img, N.rounded_rect(w, h, max(2, b // 2)))


def r_card(a):
    """Torn organic card, ragged edge, damp paper or dark flesh."""
    w, h = a.w, a.h
    seed = _seed(a)
    rng = np.random.default_rng(seed)
    fam = family(a)
    pad = max(2, int(min(w, h) * 0.05))
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    per = 22
    pts = []
    for i in range(per):
        t = i / per
        j = (rng.random() - 0.5) * pad * 0.8
        pts.append((pad + t * (w - 2 * pad), pad + j))
    for i in range(per):
        t = i / per
        j = (rng.random() - 0.5) * pad * 0.8
        pts.append((w - pad - j, pad + t * (h - 2 * pad)))
    for i in range(per):
        t = i / per
        j = (rng.random() - 0.5) * pad * 0.8
        pts.append((w - pad - t * (w - 2 * pad), h - pad + j))
    for i in range(per):
        t = i / per
        j = (rng.random() - 0.5) * pad * 0.8
        pts.append((pad + j, h - pad - t * (h - 2 * pad)))
    d.polygon(pts, fill=255)
    mask = np.array(m, np.float32) / 255.0

    base = P.PAPER if fam == "paper" else P.FLESH_DEEP
    f = _field(h, w, seed, cells=0.3, fibre=0.35)
    img = _ramp_img(f, stops_for(a)) + _grain(h, w, seed + 3, 12)
    if fam == "paper":
        stain = N.radial_mask(h, w, 0.72, 0.3, 0.55, 2.0) * 0.35
        img = img * (1 - stain[:, :, None]) + np.array(P.FLESH_DEEP, np.float32) * stain[:, :, None]
        for i in range(4):
            y = int(h * (0.28 + i * 0.15))
            d2 = ImageDraw.Draw(Image.fromarray((mask * 255).astype(np.uint8), "L"))
            img[y:y + 1, int(w * .12):int(w * .88)] *= 0.86
    return _finish(img, mask)


# ============================================================== gauges =====

def r_gauge_frame(a):
    """STO-01: organic ribbed bezel with a transparent centre."""
    w, h = a.w, a.h
    seed = _seed(a)
    f = _field(h, w, seed, cells=0.55, fibre=0.10)
    img = _ramp_img(f, [(0.0, P.FLESH_DARK), (0.4, P.FLESH_DEEP), (0.75, P.FLESH_MID), (1.0, P.FLESH_BRIGHT)])
    inner = N.rounded_rect(w, h, max(6, h // 6), inset=int(h * 0.20))
    outer = N.rounded_rect(w, h, max(6, h // 6), inset=int(h * 0.02))
    ring_m = np.clip(outer - inner, 0, 1)
    ribs = 0.5 + 0.5 * np.sin(np.linspace(0, np.pi * 18, w, dtype=np.float32))[None, :]
    img = img * (1 - 0.35 * ribs[:, :, None] * ring_m[:, :, None]) + \
        np.array(P.FLESH_DARK, np.float32) * (0.35 * ribs[:, :, None] * ring_m[:, :, None])
    top = np.clip(1.0 - np.mgrid[0:h, 0:w][0] / (h * 0.25), 0, 1)
    img = img * (1 - 0.5 * top[:, :, None]) + np.array(P.BONE_WHITE, np.float32) * (0.5 * top[:, :, None])
    return _finish(img, outer)


def r_gauge_mask(a):
    return _finish(_rgb(a.h, a.w, P.FLESH_PALE), N.rounded_rect(a.w, a.h, max(6, a.h // 6)))


def r_gauge_fill(a):
    """Tileable-Y stomach fill. STO-03..05 read as thin / full / congested."""
    w, h = a.w, a.h
    seed = _seed(a)
    f = _field(h, w, seed, cells=0.5, fibre=0.25)
    level = {"STO-03": 0.30, "STO-04": 0.65, "STO-05": 0.95}.get(a.id, 0.5)
    fam = {"STO-03": [(0, P.MUCOSA), (0.6, P.FLESH_PALE), (1, P.CLEAN_WHITE)],
           "STO-04": [(0, P.FLESH_MID), (0.5, P.FLESH_BRIGHT), (1, P.MUCOSA)],
           "STO-05": [(0, P.FLESH_DEEP), (0.5, P.FLESH_DARK), (1, P.FLESH_MID)],
           "STO-15": [(0, P.FLESH_MID), (0.5, P.FLESH_PALE), (1, P.CLEAN_WHITE)]}.get(a.id, stops_for(a))
    img = _ramp_img(f * 0.6 + 0.4 * level, fam) + _grain(h, w, seed + 7, 12)
    if a.id == "STO-05":
        v = N.ridged(h, w, 4, 3, np.random.default_rng(seed + 9))
        veins = np.clip((v - 0.86) / 0.14, 0, 1)[:, :, None]
        img = img * (1 - veins * 0.7) + np.array(P.FLESH_BRIGHT, np.float32) * veins * 0.7
    return _finish(img)


def r_progress_ring(a):
    w, h = a.w, a.h
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = int(min(w, h) * 0.06)
    d.ellipse([pad, pad, w - pad, h - pad], outline=P.BONE_DEEP + (255,), width=max(2, int(min(w, h) * 0.05)))
    im = _to_np(img)
    f = _field(h, w, _seed(a), cells=0.2, fibre=0.4)
    tint = _ramp_img(f, stops_for(a))
    return _finish(im[:, :, :3] * (im[:, :, 3:] / 255.0) + tint * (1 - im[:, :, 3:] / 255.0), im[:, :, 3] / 255.0)


# ============================================================== overlays ===

def r_vignette(a):
    t = _txt(a)
    if "nausea" in t or "bile" in t:
        col, r_, f_ = P.BILE, 0.95, 2.2
    elif "clean" in t or "safe" in t or "white" in t:
        col, r_, f_ = P.CLEAN_WHITE, 0.85, 1.6
    elif "pulse" in t or "heartbeat" in t or "tint" in t or "overfull" in t:
        col, r_, f_ = P.FLESH_BRIGHT, 0.95, 2.0
    elif "cracked" in t:
        col, r_, f_ = P.STEEL, 0.8, 1.4
    else:
        col, r_, f_ = P.FLESH_DEEP, 0.9, 1.8
    m = N.radial_mask(a.h, a.w, 0.5, 0.5, r_, f_)
    m = 1.0 - m
    if "spotlight" in t or "highlight" in t:
        m = 1.0 - m
    img = _rgb(a.h, a.w, col) + _grain(a.h, a.w, _seed(a), 10)
    return _finish(img, np.clip(m, 0, 1) * 0.92)


def r_glow(a):
    m = N.radial_mask(a.h, a.w, 0.5, 0.5, 0.5, 1.8)
    col = P.NERVE_HOT if "nerve" in _txt(a) else P.CLEAN_WHITE
    return _finish(_rgb(a.h, a.w, col), m)


def r_wipe(a):
    """TEX-314: soft black-to-transparent wipe."""
    g = N.linear_grad(a.h, a.w, P.INK, P.INK, 0.0)
    al = np.linspace(1, 0, a.w, dtype=np.float32)[None, :] if a.w >= a.h else \
        np.linspace(1, 0, a.h, dtype=np.float32)[:, None]
    return _finish(g, np.broadcast_to(al, (a.h, a.w)).copy())


def r_arc_gauge(a):
    w, h = a.w, a.h
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = int(min(w, h) * 0.08)
    d.arc([pad, pad, w - pad, h - pad], 30, 340, fill=P.BONE_DEEP + (255,), width=max(2, int(min(w, h) * 0.07)))
    return _to_np(img)


# =============================================================== digits ====

SEG = {
    "0": "abcdef", "1": "bc", "2": "abdeg", "3": "abcdg", "4": "bcfg",
    "5": "acdfg", "6": "acdefg", "7": "abc", "8": "abcdefg", "9": "abcdfg",
    "-": "g", "m": "ce", "%": "bdefg", ".": "j",
}
SEGMAP = {
    "a": (0.10, 0.00, 0.90, 0.06), "b": (0.90, 0.10, 0.96, 0.50), "c": (0.90, 0.50, 0.96, 0.90),
    "d": (0.10, 0.94, 0.90, 1.00), "e": (0.04, 0.50, 0.10, 0.90), "f": (0.04, 0.10, 0.10, 0.50),
    "g": (0.10, 0.47, 0.90, 0.53), "i": (0.47, 0.00, 0.53, 0.06), "j": (0.47, 0.94, 0.53, 1.00),
}


def r_digit_atlas(a):
    w, h = a.w, a.h
    glyphs = list("0123456789")
    if "m" in a.need.lower() or "metre" in a.need.lower() or "depth" in _txt(a):
        glyphs += ["m", "-"]
    if "percent" in _txt(a) or "fullness" in _txt(a):
        glyphs += ["%"]
    # fit the grid inside the atlas: never clip the last row
    n = len(glyphs)
    fit = max(1, w // max(1, h))
    cols = max(1, min(n, fit))
    rows = int(np.ceil(n / cols))
    cw, ch = max(1, w // cols), max(1, h // rows)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    col = P.BONE_WHITE if "stomach" in _txt(a) else P.CLEAN_WHITE
    for i, gch in enumerate(glyphs):
        ox, oy = (i % cols) * cw, (i // cols) * ch
        for seg in SEG.get(gch, ""):
            x0, y0, x1, y1 = SEGMAP[seg]
            d.rectangle([ox + x0 * cw, oy + y0 * ch, ox + x1 * cw, oy + y1 * ch], fill=col + (255,))
    return _to_np(img)


# ================================================================ icons ====

def _icon_draw(kind, s, halo=False):
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(7)
    if halo:
        d.ellipse([1, 1, s - 2, s - 2], fill=P.CLEAN_WHITE + (240,))
    if kind == "muscle":
        for y in np.linspace(0.24, 0.80, 6):
            d.ellipse([s * .16, s * y, s * .84, s * (y + .08)], fill=P.FLESH_MID + (255,))
            d.line([s * .2, s * y, s * .8, s * (y + .03)], fill=P.FLESH_BRIGHT + (255,), width=max(1, s // 70))
    elif kind == "fat":
        for _ in range(7):
            x, y, r = rng.uniform(.2, .8) * s, rng.uniform(.2, .8) * s, rng.uniform(.07, .15) * s
            d.ellipse([x - r, y - r, x + r, y + r], fill=P.FAT + (255,),
                      outline=P.FAT_DEEP + (255,), width=max(1, s // 50))
    elif kind == "fascia":
        d.polygon([(s * .18, s * .2), (s * .82, s * .14), (s * .86, s * .8), (s * .2, s * .86)], fill=P.BONE + (255,))
        for i in range(8):
            y = s * (.22 + i * .085)
            d.line([s * .2, y, s * .84, y + rng.uniform(-4, 4)], fill=P.CARTILAGE_DEEP + (200,))
        for i in range(9):
            x = s * (.2 + i * .075)
            d.line([x, s * .2, x + rng.uniform(-5, 5), s * .84], fill=P.CLEAN_WHITE + (140,))
    elif kind == "gland":
        d.ellipse([s * .2, s * .22, s * .8, s * .78], fill=P.MUCOSA + (235,),
                  outline=P.FLESH_PALE + (255,), width=max(1, s // 40))
        d.ellipse([s * .34, s * .32, s * .56, s * .48], fill=P.CLEAN_WHITE + (190,))
    elif kind == "cartilage":
        _rounded(d, [s * .16, s * .26, s * .84, s * .74], s * .10, P.CARTILAGE + (255,),
                 P.CARTILAGE_DEEP + (255,), max(1, s // 40))
        d.line([s * .24, s * .38, s * .76, s * .38], fill=P.CLEAN_WHITE + (170,), width=max(1, s // 60))
    elif kind == "nerve":
        d.line([(s * .18, s * .78), (s * .32, s * .5), (s * .52, s * .5), (s * .68, s * .26), (s * .86, s * .3)],
               fill=P.NERVE + (255,), width=max(3, int(s * .12)), joint="curve")
        d.line([(s * .2, s * .3), (s * .4, s * .3), (s * .6, s * .5), (s * .82, s * .5)],
               fill=P.NERVE_HOT + (255,), width=max(3, int(s * .08)), joint="curve")
        for x, y, r in ((.86, .3, .07), (.82, .5, .05), (.32, .5, .05)):
            d.ellipse([s * (x - r), s * (y - r), s * (x + r), s * (y + r)], fill=P.NERVE + (255,))
        for i in range(4):
            x = s * (.3 + i * .14)
            d.arc([x, s * .12, x + s * .1, s * .26], 200, 340, fill=P.NERVE + (230,), width=max(1, s // 60))
    elif kind == "tumor":
        for _ in range(9):
            x, y, r = rng.uniform(.24, .76) * s, rng.uniform(.26, .74) * s, rng.uniform(.06, .12) * s
            d.ellipse([x - r, y - r, x + r, y + r], fill=P.TUMOR + (255,),
                      outline=P.TUMOR_DEEP + (255,), width=max(1, s // 60))
    elif kind == "mucosa":
        d.polygon([(s * .2, s * .3), (s * .8, s * .24), (s * .84, s * .76), (s * .16, s * .7)], fill=P.MUCOSA + (215,))
        for i in range(4):
            y = s * (.34 + i * .11)
            d.arc([s * .18, y - s * .08, s * .86, y + s * .08], 200, 340, fill=P.CLEAN_WHITE + (200,), width=max(1, s // 50))
    elif kind == "shell":
        _rounded(d, [s * .16, s * .2, s * .84, s * .8], s * .06, P.BONE + (255,), P.CARTILAGE_DEEP + (255,), max(1, s // 40))
        d.polygon([(s * .16, s * .8), (s * .84, s * .8), (s * .7, s * .9), (s * .3, s * .9)], fill=(0, 0, 0, 70))
    elif kind == "scar":
        d.line([(s * .16, s * .74), (s * .84, s * .3)], fill=P.SCAR + (255,), width=max(3, int(s * .09)))
        for i in range(6):
            t = i / 5
            x, y = s * (.2 + t * .6), s * (.72 - t * .4)
            d.line([x - s * .05, y + s * .06, x + s * .05, y - s * .06], fill=P.FLESH_PALE + (220,), width=max(1, s // 50))
    elif kind == "arrow_up":
        d.polygon([(s * .5, s * .16), (s * .84, s * .58), (s * .62, s * .58), (s * .62, s * .84),
                   (s * .38, s * .84), (s * .38, s * .58), (s * .16, s * .58)], fill=P.CLEAN_WHITE + (255,))
    elif kind == "arrow_down":
        d.polygon([(s * .5, s * .84), (s * .84, s * .42), (s * .62, s * .42), (s * .62, s * .16),
                   (s * .38, s * .16), (s * .38, s * .42), (s * .16, s * .42)], fill=P.NERVE + (255,))
    elif kind == "hand":
        _hand_shape(d, s, 1.0)
    elif kind == "toilet":
        d.rounded_rectangle([s * .30, s * .18, s * .70, s * .40], radius=int(s * .05),
                            fill=P.CLEAN_WHITE + (255,), outline=P.STEEL_DARK + (255,), width=max(1, s // 40))
        d.ellipse([s * .18, s * .42, s * .82, s * .78], fill=P.CLEAN_WHITE + (255,),
                  outline=P.STEEL_DARK + (255,), width=max(1, s // 40))
        d.rounded_rectangle([s * .40, s * .78, s * .60, s * .90], radius=int(s * .03), fill=P.STEEL + (255,))
    elif kind == "check":
        d.line([s * .22, s * .52, s * .42, s * .72], fill=P.CLEAN_WHITE + (255,), width=max(2, int(s * .10)))
        d.line([s * .42, s * .72, s * .8, s * .28], fill=P.CLEAN_WHITE + (255,), width=max(2, int(s * .10)))
    elif kind == "cross":
        d.line([s * .26, s * .26, s * .74, s * .74], fill=P.FLESH_BRIGHT + (255,), width=max(2, int(s * .10)))
        d.line([s * .74, s * .26, s * .26, s * .74], fill=P.FLESH_BRIGHT + (255,), width=max(2, int(s * .10)))
    elif kind == "notebook":
        _rounded(d, [s * .22, s * .14, s * .78, s * .86], s * .05, P.PAPER + (255,), P.FLESH_DEEP + (255,), max(1, s // 40))
        for i in range(5):
            y = s * (.28 + i * .12)
            d.line([s * .3, y, s * .7, y], fill=P.PAPER_DAMP + (255,), width=max(1, s // 70))
        d.rectangle([s * .22, s * .14, s * .28, s * .86], fill=P.FLESH_DEEP + (255,))
    elif kind == "ring":
        d.ellipse([s * .12, s * .12, s * .88, s * .88], outline=P.BONE_WHITE + (255,), width=max(2, int(s * .07)))
    elif kind == "star":
        pts = []
        for i in range(10):
            ang = np.pi / 2 + i * np.pi / 5
            r = s * (0.42 if i % 2 == 0 else 0.18)
            pts.append((s / 2 + np.cos(ang) * r, s / 2 - np.sin(ang) * r))
        d.polygon(pts, fill=P.NERVE + (255,))
    elif kind == "unknown":
        d.ellipse([s * .26, s * .3, s * .74, s * .7], fill=P.FLESH_GREY + (150,))
        d.ellipse([s * .34, s * .36, s * .48, s * .46], fill=P.FLESH_DEEP + (110,))
    return img


def r_icon(a):
    t = _txt(a)
    kind = "unknown"
    for kw, k in (("nerve", "nerve"), ("muscle", "muscle"), ("fat", "fat"), ("fascia", "fascia"),
                  ("cartilage", "cartilage"), ("gland", "gland"), ("tumour", "tumor"), ("tumor", "tumor"),
                  ("mucosa", "mucosa"), ("shell", "shell"), ("scar", "scar"), ("surface direction", "arrow_up"),
                  ("danger hint", "arrow_down"), ("surface arrow", "arrow_up"), ("home", "arrow_up"),
                  ("toilet", "toilet"), ("flush", "toilet"), ("vomit", "toilet"), ("notebook", "notebook"),
                  ("codex", "notebook"), ("full block", "cross"), ("cannot eat", "cross"),
                  ("unknown", "unknown"), ("milestone", "star"), ("seal", "star"), ("tend", "ring")):
        if kw in t:
            kind = k
            break
    s = max(a.w, a.h)
    img = _icon_draw(kind, s)
    if s != a.w or s != a.h:
        img = img.resize((a.w, a.h), Image.LANCZOS)
    return _to_np(img)


TISSUE_ICON = {
    "ICO-06": "muscle", "ICO-07": "fat", "ICO-08": "fascia", "ICO-09": "gland",
    "ICO-10": "cartilage", "ICO-11": "nerve", "ICO-12": "tumor", "ICO-13": "mucosa",
    "ICO-14": "shell", "ICO-15": "scar", "ICO-05": "unknown",
    "ICO-28": "nerve", "ACC-02": "nerve", "ACC-01": "nerve",
}


# ================================================================ hands ====

def _finger(d, x, y, L, ang, w, col, curl_step=0.0, tip=None):
    """Tapered two joint finger. Returns the tip position."""
    import math
    cx_, cy_, a = x, y, ang
    for i, f in enumerate((0.46, 0.34, 0.20)):
        ls = L * f
        x2 = cx_ + math.sin(a) * ls
        y2 = cy_ - math.cos(a) * ls
        d.line([(cx_, cy_), (x2, y2)], fill=col, width=max(2, int(w * (1 - 0.22 * i))))
        cx_, cy_ = x2, y2
        a += curl_step
    if tip == "claw":
        d.line([(cx_, cy_), (cx_ + math.sin(a) * L * 0.22, cy_ - math.cos(a) * L * 0.22)],
               fill=P.NERVE_DEEP + (255,), width=max(2, int(w * 0.55)))
    return cx_, cy_


def _hand_shape(d, s, curl=0.35, clawed=False, plated=False, wrapped=False, polyp=False):
    """A stylised first person hand, drawn upright inside an s x s box."""
    cx = s * 0.5
    wrist_y = s * 0.93
    palm_top = s * 0.40
    palm_w = s * 0.26
    skin = P.FLESH_PALE if not wrapped else P.CLEAN_WHITE
    line = P.FLESH_DEEP

    # forearm / wrist taper
    d.polygon([(cx - s * .12, s * 1.02), (cx - s * .155, wrist_y),
               (cx + s * .155, wrist_y), (cx + s * .12, s * 1.02)], fill=skin + (255,))
    # palm
    _rounded(d, [cx - palm_w, palm_top, cx + palm_w, wrist_y], s * 0.09,
             skin + (255,), line + (170,), max(1, int(s * 0.008)))
    # four fingers
    fx = (-0.205, -0.072, 0.072, 0.205)
    fl = (0.29, 0.335, 0.315, 0.255)
    for i, (ox, L) in enumerate(zip(fx, fl)):
        ang = (i - 1.5) * 0.10 + curl * 0.10
        _finger(d, cx + s * ox, palm_top + s * 0.015, s * L, ang, s * 0.072,
                skin + (255,), curl_step=0.42 + curl * 0.55, tip="claw" if clawed else None)
    # thumb
    _finger(d, cx - palm_w * 0.92, wrist_y - s * 0.11, s * 0.22,
            -1.05 - curl * 0.12, s * 0.085, skin + (255,), curl_step=0.30 + curl * 0.4)
    # knuckle plates, stage 4+
    if plated:
        for i in range(4):
            d.ellipse([cx + s * fx[i] - s * .036, palm_top - s * .012,
                       cx + s * fx[i] + s * .036, palm_top + s * .05], fill=P.NERVE_DEEP + (255,))
    if polyp:
        for i in range(4):
            x = cx + s * fx[i] * 0.8
            y = wrist_y - s * (0.10 + 0.05 * (i % 2))
            r = s * 0.026
            d.ellipse([x - r, y - r, x + r, y + r], fill=P.TUMOR + (255,), outline=P.TUMOR_DEEP + (255,))
    if wrapped:
        d.polygon([(cx - s * .17, s * .80), (cx + s * .17, s * .80),
                   (cx + s * .15, s * 1.02), (cx - s * .15, s * 1.02)], fill=P.CLEAN_WHITE + (255,))


# pose -> (rotation degrees, x offset, y offset, scale, curl, flags)
HAND_POSE = {
    "HND-02": dict(rot=-18, dx=0.00, dy=0.10),
    "HND-03": dict(rot=-48, dx=0.10, dy=0.26, curl=0.12),
    "HND-04": dict(rot=16, dx=0.00, dy=0.02, curl=0.75),
    "HND-05": dict(rot=-26, dx=-0.06, dy=0.16, curl=0.55),
    "HND-06": dict(rot=-14, dy=0.04, curl=0.5),
    "HND-07": dict(rot=-10, dy=0.04, curl=0.55),
    "HND-08": dict(rot=-6, dy=0.04, curl=0.5),
    "HND-09": dict(rot=-4, dy=0.04, curl=0.5, plated=True),
    "HND-10": dict(rot=-2, dy=0.04, curl=0.5, clawed=True),
    "HND-11": dict(rot=0, dy=0.04, curl=0.5, polyp=True),
    "HND-12": dict(rot=-72, dy=0.28, curl=0.15),
    "HND-13": dict(rot=-8, dy=0.22, curl=0.65),
    "HND-14": dict(rot=30, dy=0.14, curl=0.85),
    "HND-15": dict(rot=-10, dy=0.06, curl=0.35),
    "HND-16": dict(rot=-12, dy=0.04, curl=0.45, wrapped=True),
    "HND-18": dict(rot=-8, curl=0.45),
    "HND-19": dict(rot=-8, curl=0.45),
    "HND-20": dict(rot=74, dy=0.20, curl=0.9),
}


def r_hand(a):
    w, h = a.w, a.h
    p = HAND_POSE.get(a.id, {})
    curl = p.get("curl", 0.4)
    flags = {k: p.get(k, False) for k in ("plated", "clawed", "wrapped", "polyp")}
    rot, dx, dy = p.get("rot", 0), p.get("dx", 0.0), p.get("dy", 0.0)

    def layer(box):
        s = int(min(box) * 0.98)
        im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        _hand_shape(ImageDraw.Draw(im), s, curl=curl, **flags)
        if rot:
            im = im.rotate(rot, resample=Image.BICUBIC, expand=False)
        return im

    if a.id == "HND-01" or "pair" in a.spec.lower():
        out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        half = h // 2
        box = (half, half)
        for i, flip in enumerate((0, 1)):
            im = layer(box)
            if flip:
                im = im.transpose(Image.FLIP_LEFT_RIGHT)
            out.paste(im, (int(half * 0.06) if not flip else int(w - half * 1.06), i * half), im)
        return _to_np(out)

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    im = layer((min(w, h), min(w, h)))
    out.paste(im, (int(w / 2 - im.width / 2 + dx * w), int(h - im.height + dy * h)), im)
    arr = _to_np(out)

    if a.id == "HND-17":                      # reusable dirt layer
        f = _field(h, w, _seed(a), cells=0.5, fibre=0.2)
        arr[:, :, :3] = _ramp_img(f, [(0, P.FLESH_DEEP), (1, P.FLESH_MID)])
    if a.id == "HND-21":                      # belly silhouette at the frame bottom
        belly = np.zeros((h, w), np.float32)
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        e = ((xx - w * .5) / (w * .52)) ** 2 + ((yy - h * 1.15) / (h * .55)) ** 2
        belly = np.clip(1.05 - e, 0, 1) * np.clip((yy - h * .72) / (h * .12), 0, 1)
        img = _ramp_img(_field(h, w, _seed(a)), [(0, P.FLESH_DEEP), (1, P.FLESH_PALE)])
        al = arr[:, :, 3] / 255.0
        rgb = img * (1 - al[:, :, None]) + arr[:, :, :3] * al[:, :, None]
        m = np.clip(al + belly, 0, 1)
        return _finish(rgb, m)
    return arr


# ============================================================= key art =====

BAND_ART = {
    "B01": (P.FLESH_MID, P.FLESH_BRIGHT, 0.2), "B02": (P.FLESH_MID, P.FAT, 0.3),
    "B03": (P.BONE, P.FLESH_PALE, 0.5), "B04": (P.FLESH_DEEP, P.FLESH_MID, 0.4),
    "B05": (P.FLESH_PALE, P.MUCOSA, 0.35), "B06": (P.NERVE, P.FLESH_DEEP, 0.45),
    "B07": (P.FLESH_DARK, P.FLESH_DEEP, 0.6), "B08": (P.FLESH_DEEP, P.FLESH_DARK, 0.55),
}


def _band_signature(band, h, w, seed, rr):
    """Per band overlay -> (mask 0..1, rgb). This is what makes the eight
    band cards read as eight different places rather than one red tunnel."""
    if band is None:
        return None
    rng = np.random.default_rng(seed + 11)
    fall = np.clip(1.0 - rr / 1.0, 0, 1)          # fades toward the light
    if band == "B01":                              # follicle pits
        m = np.clip((N.worley(h, w, max(3, int(min(h, w) / 34)), rng) - 0.15) * 3.0, 0, 1) ** 2
        return m * fall, P.FLESH_DARK
    if band == "B02":                              # fat lobes
        m = np.clip((1.0 - N.worley(h, w, max(3, int(min(h, w) / 40)), rng)) * 1.5, 0, 1) ** 1.4
        return m * 0.75 * fall, P.FAT
    if band == "B03":                              # white crosshatch sheets
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        weave = 0.5 + 0.5 * np.sin(xx / w * 34.0) * np.sin(yy / h * 26.0)
        return np.clip(weave * 1.3 - 0.35, 0, 1) * 0.7 * fall, P.CLEAN_WHITE
    if band == "B04":                              # heavy striation
        fib = N.fbm(h, w, 6, 3, rng, aniso=(0.06, 3.4))
        return np.clip(np.abs(fib - 0.5) * 3.2, 0, 1) * 0.55 * fall, P.FLESH_DARK
    if band == "B05":                              # translucent sacs
        m = np.clip((N.worley(h, w, max(3, int(min(h, w) / 28)), rng) - 0.1) * 2.0, 0, 1) ** 1.6
        return m * 0.6 * fall, P.MUCOSA
    if band == "B06":                              # yellow strand thicket
        fib = N.ridged(h, w, 5, 4, rng)
        return np.clip((fib - 0.72) * 3.4, 0, 1) ** 1.2 * fall * 0.95, P.NERVE
    if band == "B07":                              # near empty vault
        m = np.clip((N.fbm(h, w, 3, 4, rng) - 0.55) * 2.2, 0, 1) * fall
        return m * 0.5, P.FLESH_DEEP
    if band == "B08":                              # rhythmic ribs
        y = np.arange(h, dtype=np.float32)[:, None] / h
        rib = np.clip(0.5 + 0.5 * np.sin(2 * np.pi * 9.0 * y), 0, 1) ** 3
        return rib * 0.8 * fall, P.FLESH_DARK
    return None


def r_keyart(a):
    """Receding flesh tunnel with a distant point of light."""
    w, h = a.w, a.h
    seed = _seed(a)
    band = f"B{a.num}" if a.id.startswith("BAND") else None
    if band in BAND_ART:
        near, far, depth = BAND_ART[band]
    else:
        near, far, depth = P.FLESH_MID, P.FLESH_DARK, 0.45
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = w * 0.5, h * 0.52
    dx = (xx - cx) / max(1.0, w * 0.5)
    dy = (yy - cy) / max(1.0, h * 0.5)
    r = np.sqrt(dx * dx + dy * dy)
    rng = np.random.default_rng(seed)
    warp = N.fbm(h, w, 5, 4, rng) - 0.5
    rr = np.clip(r * (1.0 + warp * 0.45), 0, 2)

    # tunnel wall shading
    wall = np.clip(1.0 - rr / (0.6 + depth), 0, 1)
    fib = N.fbm(h, w, 7, 4, rng, aniso=(0.15, 2.4))
    img = _ramp_img(np.clip(wall * 0.7 + fib * 0.4, 0, 1), [(0.0, P.FLESH_DARK), (0.45, near), (1.0, far)])
    # receding rings
    rings = np.abs(np.sin(rr * 9.0))
    img = img * (1 - 0.35 * (rings ** 3)[:, :, None]) + np.array(P.FLESH_DARK, np.float32) * (0.35 * (rings ** 3)[:, :, None])
    # distant light
    glow = N.radial_mask(h, w, 0.5, 0.52, 0.09, 2.0)
    light = P.CLEAN_WHITE if ("restroom" in _txt(a) or "contrast" in _txt(a) or a.id == "BRD-06") else P.BONE_WHITE
    img = img * (1 - glow[:, :, None]) + np.array(light, np.float32) * glow[:, :, None]
    img = img + _grain(h, w, seed + 5, 14)

    # per band signature layer, this is what makes the eight cards read apart
    sig = _band_signature(band, h, w, seed, rr)
    if sig is not None:
        sm, sc = sig
        sm = np.clip(sm, 0, 1)[:, :, None]
        img = img * (1 - sm) + np.array(sc, np.float32)[None, None, :] * sm

    if "contrast" in _txt(a) or a.id == "BRD-06" or a.id in ("MNU-01", "MNU-19"):
        if a.id == "BRD-06":
            clean = np.clip((xx / w - 0.5) * 2.0, 0, 1) ** 1.5
        else:
            # main menu: clean light spilling from one side, not a white block
            clean = np.clip((xx / w - 0.45) * 1.6, 0, 1) ** 2.2 * 0.85
        white_img = _ramp_img(np.ones((h, w), np.float32) * 0.5, [(0, P.CLEAN_WHITE), (1, P.TILE_WHITE)])
        img = img * (1 - clean[:, :, None]) + white_img * clean[:, :, None]
    if "close-up" in _txt(a) or "teeth" in _txt(a):
        img = _ramp_img(np.ones((h, w), np.float32), [(0, P.FLESH_MID), (1, P.FLESH_PALE)])
        teeth = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        dt = ImageDraw.Draw(teeth)
        for i in range(9):
            x = w * (0.06 + i * 0.11)
            dt.polygon([(x, 0), (x + w * .08, 0), (x + w * .04, h * .42)],
                       fill=P.CLEAN_WHITE + (255,), outline=P.BONE_DEEP + (255,))
        for i in range(9):
            x = w * (0.02 + i * 0.11)
            dt.polygon([(x, h), (x + w * .08, h), (x + w * .04, h * .60)],
                       fill=P.CARTILAGE + (255,), outline=P.BONE_DEEP + (255,))
        tarr = _to_np(teeth)
        al = tarr[:, :, 3:] / 255.0
        img = tarr[:, :, :3] * al + img * (1 - al)
    return _finish(img, np.ones((h, w), np.float32))


# ============================================================== brand ======

def r_logo(a):
    w, h = a.w, a.h
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    size = int(h * 0.62)
    font = N.load_font(size, bold=True)
    txt = "FLESH PIT"
    bbox = d.textbbox((0, 0), txt, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    ox, oy = (w - tw) // 2 - bbox[0], (h - th) // 2 - bbox[1]
    d.text((ox, oy), txt, font=font, fill=P.FLESH_BRIGHT + (255,))
    if "lockup" in _txt(a):
        bite = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        db = ImageDraw.Draw(bite)
        br = int(size * .30)
        db.ellipse([ox + tw * .52, oy - th * .15, ox + tw * .52 + br, oy - th * .15 + br], fill=(0, 0, 0, 255))
        arr = _to_np(img)
        m = np.array(bite)[:, :, 3] / 255.0
        img = Image.fromarray((arr * (1 - m[:, :, None])).astype(np.uint8), "RGBA")
    return _to_np(img)


def r_achievement(a):
    w, h = a.w, a.h
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([w * .04, h * .04, w * .96, h * .96], radius=int(w * .12),
                        fill=P.CLEAN_WHITE + (255,), outline=P.BONE_DEEP + (255,), width=max(1, w // 48))
    kind = "ring"
    for kw, k in (("first bite", "muscle"), ("return", "toilet"), ("mutation", "hand"),
                  ("codex", "notebook"), ("nerve", "nerve"), ("belongings", "notebook"),
                  ("deep", "arrow_down"), ("band", "arrow_down")):
        if kw in _txt(a):
            kind = k
            break
    ic = _icon_draw(kind, int(min(w, h) * 0.62))
    img.paste(ic, (int(w * .19), int(h * .19)), ic)
    return _to_np(img)


def r_capsule(a):
    """Store art: a crop of the tunnel art, centre kept clear for the logo."""
    w, h = a.w, a.h
    band = {"BRD-07": "B04", "BRD-08": "B04", "BRD-09": "B06", "BRD-10": "B06",
            "BRD-11": "B08", "BRD-12": "B02"}.get(a.id, "B04")
    art = _resize(r_keyart(_shim(band)), w, h)
    if "page background" in _txt(a):
        art = _rgb(h, w, P.FLESH_DARK) + _grain(h, w, _seed(a), 26)
    return art


class _shim:
    """Minimal stand-in so a recipe can be reused for another band."""

    def __init__(self, num):
        self.id, self.num, self.name, self.look = f"BAND-{num}", num, "band", ""
        self.need, self.spec, self.fmt, self.section, self.mapkind = "", "", "", "", ""
        self.w, self.h, self.frames, self.border, self.index = 1920, 1080, 1, 0, 0

    def __getattr__(self, k):
        return ""


# ============================================================== flipbook ===

def _fb_strip(a, frame_fn, fs=1.0):
    w, h, n = a.w, a.h, max(1, a.frames)
    frames = []
    for i in range(n):
        t = i / n
        frames.append(frame_fn(t, w, h))
    strip = np.concatenate(frames, axis=1)
    if fs != 1.0:
        strip = np.array(Image.fromarray(_to_np(_finish(strip)).astype(np.uint8))
                         .resize((int(strip.shape[1] * fs), int(strip.shape[0] * fs)), Image.LANCZOS), np.float32)
    return strip


def r_flipbook(a):
    t = _txt(a)
    seed = _seed(a)
    rng = np.random.default_rng(seed)

    if "tear burst" in t or "spray" in t:
        def f(t_, w, h):
            img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            d = ImageDraw.Draw(img)
            r0 = w * (0.12 + t_ * 0.5)
            for _ in range(34):
                ang = rng.random() * 2 * np.pi
                dist = w * rng.random() * 0.5 * t_
                x, y = w / 2 + np.cos(ang) * dist, h / 2 + np.sin(ang) * dist
                s = max(1, int(w * rng.uniform(.02, .07) * (1 - t_ * .5)))
                col = P.FLESH_BRIGHT if rng.random() > .35 else P.FAT
                d.ellipse([x - s, y - s, x + s, y + s], fill=col + (int(255 * (1 - t_)),))
            d.ellipse([w / 2 - r0 * .3, h / 2 - r0 * .3, w / 2 + r0 * .3, h / 2 + r0 * .3],
                      outline=P.FLESH_BRIGHT + (int(200 * (1 - t_)),), width=max(1, int(w * .02)))
            return _to_np(img)
    elif "chew" in t or "puff" in t:
        def f(t_, w, h):
            m = N.radial_mask(h, w, .5, .55, .15 + t_ * .45, 1.6) * (1 - t_) ** .6
            fld = _field(h, w, seed, cells=.6, fibre=.1)
            return _finish(_ramp_img(fld * .4, [(0, P.MUCOSA), (1, P.FLESH_PALE)]), m * .95)
    elif "strand" in t or "stretch" in t:
        def f(t_, w, h):
            img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            d = ImageDraw.Draw(img)
            k = t_ if t_ < .7 else 1 - (t_ - .7) / .3
            for i in range(3):
                y = h * (.35 + i * .15)
                d.line([(0, y), (w, y)], fill=P.FLESH_PALE + (200,), width=max(1, int(h * .02)))
                if t_ < .8:
                    d.line([(0, y), (w * (.5 + k * .5), y)], fill=P.BONE_WHITE + (255,), width=max(2, int(h * .035 * k)))
            return _to_np(img)
    elif "saliva" in t or "drip" in t or "arc" in t:
        def f(t_, w, h):
            img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            d = ImageDraw.Draw(img)
            x = w * t_
            y = h * (0.2 + 0.6 * (1 - (1 - t_) ** 2))
            s = max(2, int(w * .05))
            d.ellipse([x - s, y - s * 1.3, x + s, y + s * 1.3], fill=P.WATER + (220,),
                      outline=P.CLEAN_WHITE + (180,))
            if a.frames > 4:
                d.line([(x - s, y - s * 1.3), (w * max(0, t_ - .2), h * (0.2 + 0.6 * (1 - (1 - max(0, t_ - .2)) ** 2)) - s)],
                       fill=P.WATER + (140,), width=max(1, int(s * .6)))
            return _to_np(img)
    elif "splatter" in t:
        def f(t_, w, h):
            img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            d = ImageDraw.Draw(img)
            for _ in range(26):
                ang = rng.random() * 2 * np.pi
                dist = w * .5 * (t_ ** .6) * rng.random()
                x, y = w / 2 + np.cos(ang) * dist, h / 2 + np.sin(ang) * dist
                s = max(1, int(w * rng.uniform(.02, .09) * (1 - t_ * .4)))
                d.ellipse([x - s, y - s, x + s, y + s], fill=P.FLESH_PALE + (int(230 * (1 - t_ * .6)),))
            return _to_np(img)
    elif "shockwave" in t or "contraction" in t or "surge" in t or "transition" in t or "bloom" in t:
        clean = "clean" in t or "bloom" in t or "room" in t
        col = P.CLEAN_WHITE if clean else (P.NERVE if "nerve" in t or "contraction" in t else P.FLESH_BRIGHT)

        def f(t_, w, h):
            img = _rgb(h, w, col)
            al = np.zeros((h, w), np.float32)
            for k in range(3):
                rr = N.ring(h, w, t_ * 0.95 - k * 0.06, 0.05 + k * .02)
                al = np.maximum(al, rr * (1 - t_) * (1 - k * .28))
            core = N.radial_mask(h, w, .5, .5, .12 + t_ * .5, 1.6) * (1 - t_)
            al = np.clip(al + core, 0, 1) * .95
            return _finish(img, al)
    elif "shimmer" in t or "reveal" in t:
        def f(t_, w, h):
            fld = _field(h, w, seed, cells=.8, fibre=.2)
            img = _ramp_img(fld, [(0, P.TUMOR_DEEP), (1, P.CLEAN_WHITE)])
            band = N.linear_grad(h, w, (0, 0, 0), (0, 0, 0), 55.0)
            bt = (band[:, :, 0] / 255.0)
            line = np.clip(1 - np.abs(((bt + t_) % 1.0) - .5) * 8, 0, 1)
            img = img + line[:, :, None] * 90
            return _finish(img, line * .55)
    elif "creep" in t or "regrowth" in t or "close vignette" in t or "vomit" in t or "swirl" in t:
        def f(t_, w, h):
            fld = _field(h, w, seed, cells=.5, fibre=.2)
            img = _ramp_img(fld, stops_for(a))
            if "swirl" in t:
                yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
                ang = np.arctan2(yy - h / 2, xx - w / 2)
                rad = np.hypot(yy - h / 2, xx - w / 2) / max(1.0, w / 2)
                m = np.clip(1 - np.abs(np.sin(ang * 2 + rad * 10 - t_ * 2 * np.pi)), 0, 1) * (1 - rad)
            elif "vomit" in t:
                xx = np.arange(w, dtype=np.float32)[None, :] / w
                m = np.clip(1 - np.abs(xx - (0.5 + 0.18 * np.sin(t_ * 2 * np.pi))) * 3.2, 0, 1)
                m = np.broadcast_to(m, (h, w)).copy()
            else:
                m = N.edge_mask(h, w, 1.3)
                m = np.clip(1 - (m - t_ * 1.35) * 2.4, 0, 1)
                m = np.maximum(m, 0)
                m = (m * (0.55 + 0.45 * fld)) * (1 - t_ * .35)
            return _finish(img, np.clip(m, 0, 1))
    elif "pulse" in t or "heartbeat" in t:
        def f(t_, w, h):
            m = (np.sin(t_ * 2 * np.pi) * .5 + .5) ** 2
            al = np.full((h, w), m * .5, np.float32)
            return _finish(_rgb(h, w, P.FLESH_BRIGHT), al)
    elif "flash" in t or "heal" in t:
        def f(t_, w, h):
            k = np.sin(np.clip(t_, 0, 1) * np.pi)
            return _finish(_rgb(h, w, P.BONE_WHITE), np.full((h, w), k * .8, np.float32))
    elif "wipe" in t:
        def f(t_, w, h):
            fld = _field(h, w, seed, cells=.4, fibre=.4)
            img = _ramp_img(fld, stops_for(a))
            m = N.edge_mask(h, w, 1.0) if t_ < .5 else N.edge_mask(h, w, 1.0)
            m = np.clip(1 - (m - (1 - abs(t_ - .5) * 2) * 1.4) * 2.2, 0, 1)
            return _finish(img, np.clip(m, 0, 1))
    elif "spark" in t:
        def f(t_, w, h):
            img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            d = ImageDraw.Draw(img)
            r0 = w * .48 * t_
            for i in range(8):
                ang = i * np.pi / 4 + t_
                d.line([(w / 2, h / 2),
                        (w / 2 + np.cos(ang) * r0, h / 2 + np.sin(ang) * r0)],
                       fill=P.NERVE_HOT + (int(255 * (1 - t_)),), width=max(1, int(w * .03 * (1 - t_))))
            return _to_np(img)
    elif "bubble" in t or "slosh" in t or "digest" in t:
        def f(t_, w, h):
            img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            d = ImageDraw.Draw(img)
            for i in range(12):
                ph = (t_ + i / 12) % 1
                x = w * (0.15 + 0.7 * ((i * 37 % 100) / 100))
                y = h * (1 - ph)
                s = max(1, int(w * .04 * (1 - ph * .5)))
                d.ellipse([x - s, y - s, x + s, y + s], outline=P.MUCOSA + (180,), width=1)
            return _to_np(img)
    elif "mote" in t:
        def f(t_, w, h):
            img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            d = ImageDraw.Draw(img)
            for i in range(6):
                x = w * ((i * 61 % 100) / 100 + t_ * .05) % w
                y = h * ((i * 37 % 100) / 100 + t_ * .08) % h
                s = max(1, int(w * .06))
                d.ellipse([x - s, y - s, x + s, y + s], fill=P.FLESH_PALE + (90,))
            return _to_np(img)
    else:
        def f(t_, w, h):
            fld = _field(h, w, seed, cells=.5, fibre=.3)
            m = N.radial_mask(h, w, .5, .5, .2 + t_ * .7, 1.5) * (1 - t_)
            return _finish(_ramp_img(fld, stops_for(a)), m * .9)

    return _fb_strip(a, f)


# ------------------------------------------------- multi state atlases ----

# how many cells each atlas holds; an atlas rendered as one squashed icon is
# useless, so these drive a real strip
ATLAS_CELLS = {
    "ICO-27": 10, "ICO-28": 1, "ACC-01": 10, "ACC-02": 1,
    "HND-18": 6, "HND-19": 6, "CMP-13": 2, "CDX-13": 1,
    "MNU-04": 4, "MNU-06": 10, "MNU-07": 3, "MNU-08": 5, "MNU-09": 2,
    "MNU-10": 4, "MNU-11": 3, "MNU-14": 8, "MNU-18": 6,
    "ICO-02": 1, "ICO-03": 1, "ICO-04": 1,
}

ATLAS_ICON_SET = {
    "ICO-27": ["muscle", "fat", "fascia", "gland", "cartilage", "nerve", "tumor", "mucosa", "shell", "scar"],
    "ACC-01": ["muscle", "fat", "fascia", "gland", "cartilage", "nerve", "tumor", "mucosa", "shell", "scar"],
    "ICO-28": ["nerve"],
    "ACC-02": ["nerve"],
    "HND-18": ["hand"] * 6,
    "HND-19": ["hand"] * 6,
    "CMP-13": ["star", "ring"],
    "MNU-14": ["ring", "check", "cross", "arrow_up", "arrow_down", "star", "notebook", "toilet"],
}

WIDGET_SET = {
    "MNU-07": ["check_off", "check_hover", "check_on"],
    "MNU-08": ["t_off", "t_off_h", "t_on", "t_on_h", "t_dis"],
    "MNU-10": ["knob", "knob_h", "knob_d", "knob_alt"],
    "MNU-11": ["arr_up", "arr_down", "arr_dis"],
    "MNU-04": ["btn", "btn_h", "btn_p", "btn_d"],
    "MNU-06": ["tab"] * 10,
}


def _widget(d, kind, s):
    lw = max(2, int(s * 0.09))
    if kind == "check_off":
        _rounded(d, [s * .1, s * .1, s * .9, s * .9], s * .12, None, P.STEEL, lw)
    elif kind == "check_hover":
        _rounded(d, [s * .1, s * .1, s * .9, s * .9], s * .12, None, P.CLEAN_WHITE, lw)
    elif kind == "check_on":
        _rounded(d, [s * .1, s * .1, s * .9, s * .9], s * .12, P.CLEAN_WHITE + (255,), P.CLEAN_WHITE, lw)
        d.line([s * .28, s * .52, s * .44, s * .7], fill=P.INK + (255,), width=lw)
        d.line([s * .44, s * .7, s * .74, s * .3], fill=P.INK + (255,), width=lw)
    elif kind.startswith("t_"):
        on = kind in ("t_on", "t_on_h")
        dis = kind == "t_dis"
        track = P.GROUT if dis else (P.STEEL if not on else P.CLEAN_WHITE)
        _rounded(d, [s * .05, s * .3, s * .95, s * .7], s * .2, track + (255,), None)
        kx = s * .68 if on else s * .12
        knob = P.STEEL_DARK if dis else (P.CLEAN_WHITE if on else P.BONE)
        d.ellipse([kx, s * .32, kx + s * .36, s * .68], fill=knob + (255,),
                  outline=P.STEEL_DARK + (255,), width=max(1, lw // 2))
    elif kind.startswith("knob"):
        alt = kind.endswith("alt")
        shp = (s * .18) if not alt else (s * .1)
        if kind.endswith("d"):
            d.ellipse([s * .5 - shp, s * .5 - shp, s * .5 + shp, s * .5 + shp],
                      fill=P.BRASS + (255,), outline=P.BRASS_DARK + (255,), width=lw)
        else:
            d.rectangle([s * .5 - shp, s * .5 - shp, s * .5 + shp, s * .5 + shp],
                        fill=P.BONE + (255,), outline=P.BRASS_DARK + (255,), width=lw)
    elif kind.startswith("arr_"):
        col = P.STEEL_DARK if kind != "arr_up" else P.STEEL
        if kind == "arr_dis":
            col = P.GROUT
        if kind in ("arr_down", "arr_dis"):
            d.polygon([(s * .2, s * .38), (s * .8, s * .38), (s * .5, s * .72)], fill=col + (255,))
        else:
            d.polygon([(s * .2, s * .62), (s * .8, s * .62), (s * .5, s * .28)], fill=col + (255,))
    elif kind == "btn":
        _rounded(d, [s * .06, s * .2, s * .94, s * .8], s * .1, P.FLESH_DEEP + (255,), P.STEEL_DARK + (255,), lw)
    elif kind == "btn_h":
        _rounded(d, [s * .06, s * .2, s * .94, s * .8], s * .1, P.FLESH_MID + (255,), P.CLEAN_WHITE + (255,), lw)
    elif kind == "btn_p":
        _rounded(d, [s * .06, s * .2, s * .94, s * .8], s * .1, P.FLESH_BRIGHT + (255,), P.CLEAN_WHITE + (255,), lw)
    elif kind == "btn_d":
        _rounded(d, [s * .06, s * .2, s * .94, s * .8], s * .1, P.INK_SOFT + (255,), P.INK + (255,), lw)
    elif kind == "tab":
        _rounded(d, [s * .04, s * .3, s * .96, s * .9], s * .06, P.FLESH_DEEP + (255,), P.STEEL_DARK + (255,), lw)
        d.rectangle([s * .1, s * .78, s * .9, s * .88], fill=P.CLEAN_WHITE + (120,))
    elif kind == "glyph":
        d.rounded_rectangle([s * .12, s * .3, s * .88, s * .7], radius=int(s * .06),
                            outline=P.BONE_WHITE + (255,), width=lw)


def r_atlas(a):
    """A strip of N icons or N widget states, not one stretched icon.

    When ``build.py`` is already tiling the atlas it sets frames=1 and
    index=i, in which case this must draw exactly one cell.
    """
    tiled = a.frames <= 1
    w, h = a.w, a.h

    if a.id in WIDGET_SET:
        kinds = WIDGET_SET[a.id]
        if tiled:
            k = kinds[a.index % len(kinds)]
            im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            side = int(min(w, h))
            sub = Image.new("RGBA", (side, side), (0, 0, 0, 0))
            _widget(ImageDraw.Draw(sub), k, side)
            im.paste(sub, ((w - side) // 2, (h - side) // 2), sub)
            return _to_np(im)
        n = ATLAS_CELLS.get(a.id, 1)
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        cw = w / max(1, n)
        side = int(min(cw, h))
        for i, k in enumerate(kinds[:n]):
            # draw square then centre it: a 256x64 strip of 10 tabs would
            # otherwise squash every widget into a 25x25 blob
            sub = Image.new("RGBA", (side, side), (0, 0, 0, 0))
            _widget(ImageDraw.Draw(sub), k, side)
            img.paste(sub, (int(i * cw + (cw - side) / 2), (h - side) // 2), sub)
        return _to_np(img)

    if a.id == "MNU-18":
        return r_digit_atlas(a)

    kinds = ATLAS_ICON_SET.get(a.id) or ["ring"]
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    if tiled:
        k = kinds[a.index % len(kinds)]
        s = int(min(w, h) * 0.92)
        ic = _icon_draw(k, s)
        img.paste(ic, ((w - s) // 2, (h - s) // 2), ic)
        return _to_np(img)
    n = ATLAS_CELLS.get(a.id, max(1, a.frames))
    cell = int(min(w // max(1, n), h) * 0.92)
    for i, k in enumerate(kinds[:n]):
        ic = _icon_draw(k, cell)
        img.paste(ic, (int(i * (w / max(1, n)) + (w / max(1, n) - cell) / 2),
                        (h - cell) // 2), ic)
    return _to_np(img)


def r_legend_card(a):
    """Legend card: nineslice card + a tissue swatch bar + corner icon."""
    w, h = a.w, a.h
    tissue = {
        "ICO-16": ("muscle", P.FLESH_MID), "ICO-17": ("fat", P.FAT),
        "ICO-18": ("fascia", P.BONE), "ICO-19": ("gland", P.MUCOSA),
        "ICO-20": ("cartilage", P.CARTILAGE), "ICO-21": ("nerve", P.NERVE),
        "ICO-22": ("tumor", P.TUMOR), "ICO-23": ("mucosa", P.MUCOSA),
        "ICO-24": ("shell", P.BONE), "ICO-25": ("scar", P.SCAR),
    }.get(a.id, ("ring", P.FLESH_MID))
    kind, swatch = tissue
    base = _panel(a, "flesh")
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    img.paste(Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGBA"), (0, 0))
    d = ImageDraw.Draw(img)
    bar = int(h * 0.10)
    d.rectangle([bar, bar, bar * 2, h - bar], fill=swatch + (255,))
    ic = int(h * 0.42)
    icon = _icon_draw(kind, ic)
    img.paste(icon, (bar * 3, (h - ic) // 2), icon)
    for i in range(4):                      # ruled lines for the font layer
        y = int(h * (0.26 + i * 0.17))
        d.rectangle([bar * 3 + ic + bar, y, w - bar, y + max(1, h // 64)], fill=P.BONE_WHITE + (90,))
    return _to_np(img)




def r_decal(a):
    w, h = a.w, a.h
    seed = _seed(a)
    t = _txt(a)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(seed)
    if "tooth" in t:
        for i in range(5):
            x = w * (0.16 + i * 0.17)
            d.polygon([(x, h * .18), (x + w * .11, h * .18), (x + w * .055, h * .70)],
                      fill=P.FLESH_DARK + (150,))
    elif "claw" in t:
        for i in range(4):
            y = h * (0.2 + i * 0.18)
            d.line([(w * .14, y), (w * .84, y + float(rng.uniform(-6, 6)))],
                   fill=P.FLESH_DARK + (150,), width=max(2, int(h * .06)))
    elif "handprint" in t:
        _hand_shape(d, h, scale=1.0, curl=.25)
        arr = _to_np(img)
    elif "scuff" in t:
        d.ellipse([w * .25, h * .35, w * .75, h * .75], fill=P.FLESH_DEEP + (110,))
    else:
        for _ in range(14):
            x, y = rng.uniform(0, w), rng.uniform(0, h)
            r = rng.uniform(w * .03, w * .12)
            d.ellipse([x - r, y - r, x + r, y + r], fill=P.FLESH_DEEP + (120,))
    arr = _to_np(img)
    fld = _field(h, w, seed, cells=.7, fibre=.2)
    tint = _ramp_img(fld, [(0, P.FLESH_DARK), (1, P.FLESH_MID)])
    al = arr[:, :, 3:] / 255.0
    return _finish(tint, al[:, :, 0] * .95)


def r_particle(a):
    w, h = a.w, a.h
    t = _txt(a)
    seed = _seed(a)
    if "chunk" in t:
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        rng = np.random.default_rng(seed)
        pts = [(w / 2, h / 2)]
        for _ in range(9):
            a_ = rng.random() * 2 * np.pi
            r = rng.uniform(w * .18, w * .44)
            pts.append((w / 2 + np.cos(a_) * r, h / 2 + np.sin(a_) * r))
        d.polygon(pts, fill=P.FLESH_MID + (255,))
        d.ellipse([w * .38, h * .40, w * .58, h * .56], fill=P.FAT + (255,))
        return _to_np(img)
    m = N.radial_mask(h, w, .5, .5, .5, 1.4)
    col = {"saliva": P.WATER, "spark": P.CLEAN_WHITE, "mucus": P.MUCOSA}.get(
        next((k for k in ("saliva", "spark", "mucus") if k in t), ""), P.FLESH_PALE)
    return _finish(_rgb(h, w, col), m)


def r_texture(a):
    """RST surfaces and TEX infra props, generated as seamless-ish plates."""
    w, h = a.w, a.h
    seed = _seed(a)
    t = _txt(a)
    fam = family(a)
    if "tile" in t and ("white" in t or "restroom" in t or a.id in ("RST-04", "RST-05", "RST-06", "RST-07")):
        cells = max(2, int(w / 128))
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        gx = np.abs(((xx / w * cells) % 1.0) - 0.5)
        gy = np.abs(((yy / h * cells) % 1.0) - 0.5)
        grout = np.clip(1 - np.minimum(gx, gy) * 22, 0, 1)
        grout = 1 - grout
        fld = _field(h, w, seed, cells=.1, fibre=.05)
        img = _ramp_img(fld * .25 + .35, [(0, P.GROUT), (0.3, P.TILE_WHITE), (1, P.CLEAN_WHITE)])
        img = img * (1 - grout[:, :, None]) + np.array(P.GROUT, np.float32) * grout[:, :, None]
        chips = np.clip((_field(h, w, seed + 5, cells=.05, fibre=0) - .82) * 6, 0, 1)
        img = img * (1 - chips[:, :, None] * .6) + np.array(P.CARTILAGE_DEEP, np.float32) * chips[:, :, None] * .6
        if a.id == "RST-05":
            return N.sobel_normal(1.0 - grout * .8, 3.0).astype(np.float32)
        if a.id == "RST-06":
            rough = np.clip(0.12 + (1 - grout) * .18 + fld * .12, 0, 1) * 255
            return rough.astype(np.float32)
        return img + _grain(h, w, seed, 6)
    if a.id.startswith("RST"):
        return _finish(_ramp_img(_field(h, w, seed), stops_for(a)), np.ones((h, w), np.float32))
    # narrow match: "sign" alone also hits the claw decal, whose need text
    # says "mutation sign on the world"
    if a.id in ("TEX-201", "TEX-205", "RST-10", "RST-16") or "enamel sign" in t or "sign plate" in t:
        base_arr = np.clip(
            _ramp_img(_field(h, w, seed, cells=.3), [(0, P.CLEAN_WHITE), (1, P.FLESH_PALE)]), 0, 255
        ).astype(np.uint8)
        plate = Image.fromarray(base_arr, "RGB").convert("RGBA")
        d2 = ImageDraw.Draw(plate)
        lw = max(2, int(h * .06))
        d2.rectangle([w * .10, h * .30, w * .45, h * .70], outline=P.STEEL_DARK + (200,), width=lw)
        d2.ellipse([w * .55, h * .34, w * .90, h * .66], outline=P.STEEL_DARK + (200,), width=lw)
        d2.line([w * .12, h * .84, w * .88, h * .84], fill=P.STEEL_DARK + (140,), width=max(1, lw // 2))
        return _to_np(plate)
    return _finish(_ramp_img(_field(h, w, seed), stops_for(a)), np.ones((h, w), np.float32))


def r_generic(a):
    """Keyword driven fallback so every asset still lands on palette."""
    w, h = a.w, a.h
    seed = _seed(a)
    t = _txt(a)
    if a.nineslice:
        return _panel(a, {"clean": "clean", "frost": "frost", "paper": "paper", "bone": "bone"}.get(family(a), "flesh"))
    if a.tileable or a.group == "TEX":
        f = _field(h, w, seed, cells=.5, fibre=.3)
        return _finish(_ramp_img(f, stops_for(a)))
    if "frame" in t or "bezel" in t or "housing" in t:
        return _panel(a, "flesh" if family(a) in ("flesh", "ink", "mucosa", "muscle") else family(a))
    if "vignette" in t or "overlay" in t or "flash" in t or "tint" in t:
        return r_vignette(a)
    if "glow" in t or "bloom" in t:
        return r_glow(a)
    if a.w >= a.h * 2 or a.h >= a.w * 2:
        f = _field(h, w, seed, cells=.2, fibre=.4)
        return _finish(_ramp_img(f, stops_for(a)))
    if a.w <= 160 and a.h <= 160:
        return r_icon(a)
    if a.w >= 900 and a.h >= 500:
        return r_keyart(a)
    return _panel(a, "flesh")


# ============================================================== registry ===

RECIPES = {
    "nineslice": r_nineslice,
    "card": r_card,
    "gauge_frame": r_gauge_frame,
    "gauge_mask": r_gauge_mask,
    "gauge_fill": r_gauge_fill,
    "ring": r_progress_ring,
    "vignette": r_vignette,
    "glow": r_glow,
    "wipe": r_wipe,
    "arc": r_arc_gauge,
    "digits": r_digit_atlas,
    "icon": r_icon,
    "hand": r_hand,
    "keyart": r_keyart,
    "logo": r_logo,
    "achievement": r_achievement,
    "capsule": r_capsule,
    "flipbook": r_flipbook,
    "decal": r_decal,
    "particle": r_particle,
    "texture": r_texture,
    "atlas": r_atlas,
    "legend": r_legend_card,
    "generic": r_generic,
}

# id -> recipe. Anything not listed here is routed by the rules below.
BY_ID: dict[str, str] = {
    # stomach
    "STO-01": "gauge_frame", "STO-02": "gauge_mask", "STO-03": "gauge_fill",
    "STO-04": "gauge_fill", "STO-05": "gauge_fill", "STO-06": "gauge_frame",
    "STO-11": "ring", "STO-16": "gauge_mask", "STO-17": "digits",
    "STO-09": "vignette", "STO-18": "vignette", "STO-10": "gauge_mask", "STO-12": "icon",
    "STO-13": "icon", "STO-14": "gauge_frame", "STO-15": "gauge_fill",
    "STO-07": "generic", "STO-08": "gauge_frame",
    # hands
    **{f"HND-{i:02d}": "hand" for i in range(1, 22)},
    "HND-18": "atlas", "HND-19": "atlas",
    # depth
    "DEP-17": "digits", "DEP-19": "icon", "DEP-21": "icon", "DEP-20": "generic",
    "DEP-13": "card", "DEP-15": "card", "DEP-16": "icon", "DEP-18": "icon",
    "DEP-22": "generic", "DEP-14": "generic",
    **{f"DEP-{i:02d}": "generic" for i in range(5, 13)},
    # compass / canary
    "CMP-01": "nineslice", "CMP-02": "generic", "CMP-03": "icon", "CMP-04": "icon",
    "CMP-05": "ring", "CMP-06": "vignette", "CMP-07": "vignette", "CMP-09": "nineslice",
    "CMP-10": "generic", "CMP-11": "generic", "CMP-12": "generic", "CMP-14": "flipbook",
    "CMP-16": "icon", "CMP-17": "nineslice", "CMP-18": "icon", "CMP-15": "generic",
    "CMP-13": "atlas",
    # icons + legend
    "ICO-01": "nineslice", "ICO-26": "nineslice",
    "ICO-27": "atlas", "ICO-28": "atlas",
    **{f"ICO-{i:02d}": "icon" for i in range(5, 16)},
    **{f"ICO-{i:02d}": "legend" for i in range(16, 26)},
    # codex
    "CDX-01": "generic", "CDX-02": "generic", "CDX-03": "nineslice", "CDX-16": "generic",
    "CDX-18": "generic", "CDX-14": "nineslice", "CDX-11": "icon", "CDX-12": "icon",
    "CDX-13": "icon", "CDX-21": "generic", "CDX-22": "generic", "CDX-23": "generic",
    "CDX-19": "generic", "CDX-20": "flipbook",
    **{f"CDX-{i:02d}": "icon" for i in range(4, 11)},
    "CDX-15": "nineslice", "CDX-17": "ring",
    # restroom
    "RST-01": "icon", "RST-02": "nineslice", "RST-03": "vignette", "RST-04": "texture",
    "RST-05": "texture", "RST-06": "texture", "RST-07": "texture", "RST-08": "texture",
    "RST-09": "nineslice", "RST-10": "texture", "RST-11": "generic", "RST-12": "vignette",
    "RST-13": "vignette", "RST-14": "texture", "RST-15": "texture", "RST-16": "icon",
    "RST-17": "texture", "RST-18": "generic", "RST-19": "vignette",
    # band cards
    "BAND-01": "nineslice", "BAND-10": "generic",
    **{f"BAND-{i:02d}": "keyart" for i in range(2, 10)},
    # menu
    "MNU-01": "keyart", "MNU-19": "keyart", "MNU-04": "atlas", "MNU-07": "atlas",
    "MNU-10": "atlas", "MNU-16": "nineslice", "MNU-18": "atlas", "MNU-02": "logo",
    "MNU-17": "keyart", "MNU-08": "atlas", "MNU-09": "nineslice", "MNU-11": "atlas",
    "MNU-14": "atlas", "MNU-15": "icon", "MNU-20": "nineslice",
    "MNU-03": "nineslice", "MNU-05": "nineslice", "MNU-06": "atlas", "MNU-12": "vignette",
    "MNU-13": "nineslice",
    # death
    "DTH-01": "vignette", "DTH-02": "card", "DTH-03": "icon", "DTH-04": "icon",
    "DTH-05": "nineslice", "DTH-06": "glow", "DTH-07": "vignette", "DTH-08": "icon",
    "DTH-09": "vignette",
    # tutorial
    "TUT-01": "icon", "TUT-02": "ring", "TUT-03": "icon", "TUT-04": "icon",
    "TUT-05": "icon", "TUT-06": "icon", "TUT-07": "nineslice", "TUT-08": "icon",
    "TUT-09": "icon", "TUT-10": "nineslice", "TUT-11": "vignette", "TUT-12": "nineslice",
    "TUT-13": "nineslice", "TUT-14": "nineslice",
    # loading
    "LDG-01": "keyart", "LDG-03": "flipbook", "LDG-04": "flipbook", "LDG-07": "generic",
    "LDG-06": "nineslice", "LDG-05": "nineslice",
    # brand
    "BRD-01": "logo", "BRD-02": "logo", "BRD-25": "logo",    "BRD-03": "keyart", "BRD-04": "keyart", "BRD-05": "keyart", "BRD-06": "keyart",
    "BRD-07": "capsule", "BRD-08": "capsule", "BRD-09": "capsule", "BRD-10": "capsule",
    "BRD-11": "capsule", "BRD-12": "capsule", "BRD-13": "nineslice", "BRD-14": "nineslice",
    "BRD-23": "keyart", "BRD-24": "logo", "BRD-26": "nineslice",
    **{f"BRD-{i:02d}": "achievement" for i in range(15, 23)},
    # accessibility
    "ACC-01": "atlas", "ACC-02": "atlas", "ACC-03": "vignette", "ACC-04": "vignette",
    "ACC-05": "flipbook", "ACC-10": "icon", "ACC-11": "nineslice", "ACC-12": "generic",
    # particles and decals live in the TEX group but are sprites, not surfaces
    **{f"TEX-{i:03d}": "particle" for i in range(304, 309)},
    **{f"TEX-{i:03d}": "decal" for i in range(309, 314)},
}
# remove the placeholder I typed above
BY_ID.pop("TEX-B01-A", None)


def pick_recipe(a) -> str:
    if a.id in BY_ID:
        return BY_ID[a.id]
    if a.group == "TEX":
        return "texture"
    if a.group == "VFX":
        return "flipbook"
    if a.group == "ACC":
        return "generic"
    return "generic"
