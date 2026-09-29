"""Tissue icon set (ICO-05 to ICO-15) and its accessibility variants.

Canon pressure on this file:

  * ICO-11 nerve cluster is "the highest-contrast element in the whole icon set".
    It gets a saturated fill, a thick dark keyline, a bright rim, and wriggle
    ticks, and it is drawn from `Flesh.nerve_*` so no one can soften it.
  * ICO-05 unknown must NOT read as identified: low contrast, no strong keyline.
  * ICO-27 / ACC-01 redraw all ten by shape and pattern only, keeping nerve
    loudest.  Colour-blind safety must not cost the canon nerve language.
  * Nothing here bakes a glyph.  ICO-05's "question mark" is a carved notch, not
    a character, because asset-list.md forbids baked text.

Every icon is built on the same 128 box with the same keyline weight, so the set
reads as one family.
"""

from __future__ import annotations

import math

import numpy as np

from . import paint as P
from . import shapes as S
from .palette import Deep, Flesh, hex_rgb, mix, tissue_palette


# --------------------------------------------------------------------------- frame
def _keyline_icon(size: int, seed: int, mass, pal, *, kl: float | None = None,
                  rim: str | None = None, keyline: str | None = None):
    """Standard icon body.

    Three deliberate departures from the clean-icon default, because a smooth
    blob inside a uniform black ring is exactly what reads as cartoon:

    * the silhouette is roughened, so tissue looks torn rather than moulded
    * the keyline is thin and allowed to break up, not an even comic outline
    * the body is never clean: grime, pigment drift and occlusion are baked in
    """
    buf = P.Buffer(size, size)
    m = np.asarray(mass, dtype=np.float32)
    kl = kl if kl is not None else max(1.2, size * 0.020)

    # torn silhouette
    m = S.roughen(m, S.value_noise(size, size, size * 0.10, seed + 41, 3), 0.55, 1.1)
    m = np.clip(m, 0.0, 1.0)

    fill = P.shade_fill(m, pal["base"], pal["light"], pal["dark"],
                        radius=size * 0.055, bump=1.15)
    # pigment drift: flesh is never one colour
    mot = P.mottling(size, size, seed + 13, 0.42, size * 0.14)
    fill = mix(fill, pal["dark"], (1.0 - mot)[..., None] * 0.45)
    buf.composite(fill, m)

    # interior contour on the shadow side, then occlusion toward the bottom
    cres = P.form_crescent(m, max(1.5, size * 0.030))
    buf.composite(pal["dark"], cres * 0.70)
    yy, _ = S.grid(size, size)
    buf.composite(pal["dark"], np.clip((yy / size - 0.45) * 1.5, 0, 1) ** 1.6 * m * 0.30)

    # grime and pores across the whole body
    buf.composite(Flesh.GRIME_DEEP, P.grime(size, size, seed + 29, 0.55) * m * 0.40)
    buf.composite(Flesh.GRIME, P.pores(size, size, seed + 37, int(size * 0.35),
                                       size * 0.008) * m * 0.35)
    # only a thin wet edge, never a glossy dome
    spec = P.specular(m, radius=size * 0.028, thresh=0.68)
    buf.composite(pal.get("light", Flesh.SKIN_WET), spec * 0.40)

    if keyline is not False:
        # No hard outer contour.  A drawn outline -- even a broken one -- is the
        # defining signal of the comic look, so ordinary tissue gets a soft dark
        # edge falloff instead and is read by its internal form shading.  Only
        # the nerve keeps a keyline, because canon demands it stay the loudest
        # thing in the set and it has to survive arbitrary backgrounds.
        if keyline in (None, Flesh.OUTLINE):
            fall = S.blur(m, size * 0.010) - S.blur(m, size * 0.022)
            buf.composite(pal["dark"], np.clip(fall, 0, 1) * 0.85)
            halo = S.dilate(m, size * 0.008) - m
            halo = S.roughen(halo, S.value_noise(size, size, size * 0.06, seed + 71, 3), 0.8, 1.0)
            buf.composite(mix(pal["dark"], "#000000", 0.45), np.clip(halo, 0, 1) * 0.55)
        else:
            klm = S.outline(m, kl)
            break_up = S.smoothstep(0.34, 0.62, S.value_noise(size, size, size * 0.07,
                                                               seed + 53, 3))
            buf.composite(keyline, klm * (0.45 + 0.55 * break_up))
            if rim:
                inner = S.dilate(m, kl) - S.dilate(m, kl * 2.4)
                buf.composite(rim, inner * 0.75)
    return buf, m


def _wriggle_ticks(size: int, m: np.ndarray, seed: int, count: int = 5) -> np.ndarray:
    """Short ticks that read as 'this thing moves'.  Nerve and scar only."""
    rng = np.random.default_rng(seed)
    out = np.zeros((size, size), dtype=np.float32)
    yy, xx = np.indices((size, size))
    for _ in range(count * 4):
        cx, cy = rng.integers(8, size - 8, 2)
        if m[cy, cx] < 0.5:
            continue
        a = rng.random() * 2 * math.pi
        ln = size * 0.055
        out = np.maximum(out, S.capsule(size, size, cx, cy,
                                        cx + math.cos(a) * ln, cy + math.sin(a) * ln,
                                        max(1.0, size * 0.012)))
        if out.sum() > count:
            break
    return out


# --------------------------------------------------------------------------- tissue masses
def _t01_muscle(size, seed):
    """Red striated wedge, layered bands (ICO-06).

    The wedge is the recognisable silhouette; the banding is what says
    "striated" at a glance, so the mass itself carries the ridge relief and the
    detail pass only adds the colour banding.
    """
    wedge = S.polygon(size, size, [(0.16 * size, 0.80 * size), (0.34 * size, 0.22 * size),
                                   (0.72 * size, 0.26 * size), (0.86 * size, 0.78 * size)])
    m = np.maximum(wedge, S.ellipse(size, size, 0.50 * size, 0.52 * size,
                                    0.31 * size, 0.30 * size, rot=-14))
    return np.clip(m, 0.0, 1.0)


def _t02_fat(size, seed):
    """Soft yellow lobes, glossy (ICO-07)."""
    rng = np.random.default_rng(seed)
    m = np.zeros((size, size), dtype=np.float32)
    pts = [(0.36, 0.40, 0.20), (0.62, 0.36, 0.19), (0.50, 0.60, 0.22), (0.68, 0.60, 0.16),
           (0.38, 0.64, 0.17), (0.55, 0.50, 0.24)]
    for x, y, r in pts:
        m = np.maximum(m, S.ellipse(size, size, x * size, y * size,
                                    r * size * (0.9 + rng.random() * 0.25),
                                    r * size * (0.85 + rng.random() * 0.25),
                                    rot=rng.random() * 90))
    return m


def _t03_fascia(size, seed):
    """White torn strip, fibrous ends (ICO-08)."""
    body = S.rect(size, size, 0.08 * size, 0.34 * size, 0.92 * size, 0.66 * size, r=size * 0.05)
    m = body
    rng = np.random.default_rng(seed)
    for i in range(11):
        y = (0.36 + 0.28 * (i / 10.0)) * size
        side = -1 if i % 2 == 0 else 1
        x0 = (0.08 * size) if side < 0 else (0.92 * size)
        x1 = x0 + side * size * (0.09 + rng.random() * 0.09)
        m = np.maximum(m, S.capsule(size, size, x0, y, x1,
                                    y + rng.normal(0, size * 0.05), max(1.0, size * 0.012)))
    return m


def _t04_gland(size, seed):
    """Translucent sac with a fluid highlight (ICO-09).

    Irregular, not a circle: a smooth dome with a rim highlight reads as a
    balloon, which is the single most cartoon-shaped thing this set can contain.
    """
    m = S.blob(size, size, 0.50 * size, 0.54 * size, 0.36 * size, seed, lobes=4, rough=0.30,
               squash=0.92, rot=15)
    m = np.maximum(m, S.ellipse(size, size, 0.34 * size, 0.66 * size,
                                0.15 * size, 0.11 * size, rot=30))
    m = np.maximum(m, S.ellipse(size, size, 0.70 * size, 0.38 * size,
                                0.13 * size, 0.10 * size, rot=-20))
    # a neck where it attaches to the wall
    m = np.maximum(m, S.capsule(size, size, 0.80 * size, 0.22 * size,
                                0.62 * size, 0.40 * size, 0.055 * size))
    return m


def _t05_cartilage(size, seed):
    """Grey-white smooth plate with a rim (ICO-10)."""
    plate = S.rect(size, size, 0.16 * size, 0.26 * size, 0.84 * size, 0.74 * size,
                   r=size * 0.14, rot=-8)
    plate = S.roughen(plate, S.value_noise(size, size, size * 0.08, seed + 3, 3), 0.45, 1.2)
    boss = S.blob(size, size, 0.52 * size, 0.50 * size, 0.26 * size, seed + 7, lobes=3, rough=0.14)
    return np.maximum(plate, boss)


def _t06_nerve(size, seed):
    """Bright yellow, thick outline, three strands, wriggle ticks (ICO-11).

    Drawn as three explicit strands rather than a blob, because the three-strand
    read is what makes the nerve recognisable at 32 px in the world.
    """
    m = np.zeros((size, size), dtype=np.float32)
    strands = [
        [(0.30, 0.78), (0.24, 0.55), (0.36, 0.34), (0.32, 0.18)],
        [(0.52, 0.82), (0.56, 0.58), (0.48, 0.36), (0.54, 0.20)],
        [(0.72, 0.76), (0.78, 0.54), (0.70, 0.34), (0.72, 0.22)],
    ]
    w = max(2.0, size * 0.052)
    for path in strands:
        for i in range(len(path) - 1):
            (ax, ay), (bx, by) = path[i], path[i + 1]
            m = np.maximum(m, S.capsule(size, size, ax * size, ay * size, bx * size, by * size, w))
    for x, y in [(0.30, 0.78), (0.52, 0.82), (0.72, 0.76)]:
        m = np.maximum(m, S.circle(size, size, x * size, y * size, w * 1.15))
    return m


def _t07_tumor(size, seed):
    """Pale nodular mass with clustered bulbs (ICO-12)."""
    m = S.blob(size, size, 0.50 * size, 0.54 * size, 0.34 * size, seed, lobes=8, rough=0.26)
    rng = np.random.default_rng(seed + 5)
    for _ in range(11):
        a = rng.random() * 2 * math.pi
        d = rng.random() ** 0.5 * 0.30 * size
        m = np.maximum(m, S.circle(size, size, 0.50 * size + math.cos(a) * d,
                                   0.54 * size + math.sin(a) * d,
                                   size * (0.045 + rng.random() * 0.055)))
    return m


def _t08_mucosa(size, seed):
    """Translucent rippled sheet with a wet highlight (ICO-13)."""
    m = S.rect(size, size, 0.14 * size, 0.22 * size, 0.86 * size, 0.78 * size,
               r=size * 0.09, rot=6)
    yy, xx = S.grid(size, size)
    ripple = np.sin((xx * 0.10 + yy * 0.045)) * 0.5 + 0.5
    edge = np.clip(ripple * 1.4 - 0.55, 0, 1) * m
    return m


def _t09_shell(size, seed):
    """Dense bone-white barrier, heavy shadow (ICO-14)."""
    m = S.union(
        S.rect(size, size, 0.12 * size, 0.30 * size, 0.88 * size, 0.52 * size, r=size * 0.05),
        S.rect(size, size, 0.12 * size, 0.58 * size, 0.88 * size, 0.76 * size, r=size * 0.05),
    )
    return m


def _t10_scar(size, seed):
    """Fresh pink seam lines, healing grain (ICO-15)."""
    m = S.rect(size, size, 0.10 * size, 0.30 * size, 0.90 * size, 0.70 * size, r=size * 0.07)
    return m


MASSS = {
    "T01": _t01_muscle, "T02": _t02_fat, "T03": _t03_fascia, "T04": _t04_gland,
    "T05": _t05_cartilage, "T06": _t06_nerve, "T07": _t07_tumor, "T08": _t08_mucosa,
    "T09": _t09_shell, "T10": _t10_scar,
}


# --------------------------------------------------------------------------- per-tissue detail
def _detail(size, tissue, m, seed, buf):
    """Texture that makes each tissue read as itself, applied over the shaded body."""
    h, w = size, size
    if tissue == "T01":
        # ridge relief first: the banding must survive greyscale, so it is a
        # height change and not only a colour change
        band = P.striation(h, w, seed, angle=-16, thickness=size * 0.042)
        relief = np.clip(band * m, 0, 1)
        buf.composite(Flesh.MUSCLE_LIGHT, relief * 0.55)
        buf.composite(Flesh.MUSCLE_DARK, (1.0 - relief) * m * 0.30)
        buf.composite(Flesh.BLOOD_DARK, S.inner_edge(m, size * 0.030) * 0.35)
    elif tissue == "T02":
        for c in P.fibres(h, w, seed, 30, 40, size * 0.012, size * 0.10):
            buf.composite(Flesh.FAT_DARK, c * m * 0.30)
        buf.composite(Flesh.FAT_LIGHT, P.specular(m, size * 0.04, 0.45) * m * 0.6)
    elif tissue == "T03":
        ch = P.crosshatch(h, w, seed, size * 0.20, size * 0.010)
        buf.composite(Flesh.FASCIA_SHADE, ch * m * 0.38)
    elif tissue == "T04":
        inner = S.erode(m, size * 0.07)
        buf.composite(Deep.GLAND_FLUID, inner * 0.55)
        buf.composite(Flesh.MUCOSA_SHEEN, P.specular(m, size * 0.05, 0.40) * m * 0.75)
    elif tissue == "T05":
        buf.composite(Flesh.CARTILAGE_DARK, S.inner_edge(m, size * 0.045) * 0.5)
        buf.composite("#ffffff", P.specular(m, size * 0.06, 0.35) * m * 0.5)
    elif tissue == "T06":
        rim = S.dilate(m, size * 0.030) - S.dilate(m, size * 0.075)
        buf.composite(Flesh.nerve_glow(), rim * 0.85)
        ticks = _wriggle_ticks(size, S.dilate(m, size * 0.04), seed, count=6)
        buf.composite(Flesh.nerve_light(), ticks * 0.85)
    elif tissue == "T07":
        buf.composite(Flesh.TUMOR_SHADE, P.pores(size, size, seed + 3, 70, size * 0.010) * m * 0.55)
        vw = P.vein_web(h, w, seed + 11, count=6, width=size * 0.007, scale=0.8) * m
        buf.composite(Flesh.MUSCLE_DARK, vw * 0.40)
    elif tissue == "T08":
        buf.composite("#ffffff", P.specular(m, size * 0.05, 0.42) * m * 0.85)
        buf.composite(Flesh.SUB_DERMA, S.inner_edge(m, size * 0.05) * 0.30)
    elif tissue == "T09":
        buf.composite(Flesh.BONE_SHADE, P.pores(size, size, seed + 9, 90, size * 0.008) * m * 0.35)
    elif tissue == "T10":
        seam = np.zeros((h, w), dtype=np.float32)
        for i in range(4):
            y = (0.38 + 0.09 * i) * size
            seam = np.maximum(seam, S.capsule(h, w, 0.16 * size, y,
                                              0.84 * size, y + size * 0.03 * ((i % 2) * 2 - 1),
                                              size * 0.013))
        seam = np.clip(seam + S.erode(seam, size * 0.02) * 0.0, 0, 1) * m
        buf.composite(Flesh.SCAR_HEAL, seam * 0.75)
        buf.composite(Flesh.SKIN_WET, P.specular(m, size * 0.05, 0.40) * m * 0.45)
    return buf


# --------------------------------------------------------------------------- public
def tissue_icon(tissue: str, size: int = 128, seed: int = 0):
    """One tissue icon, fully detailed.  Returns an RGBA Image."""
    pal = tissue_palette(tissue)
    mass = MASSS[tissue](size, seed)
    mass = np.clip(mass, 0.0, 1.0)
    is_nerve = tissue == "T06"
    buf, m = _keyline_icon(
        size, seed, mass, pal,
        # thick keyline is canon for the nerve, but it is roughened and broken
        # like every other silhouette so it does not read as a comic outline
        kl=max(2.2, size * 0.034) if is_nerve else max(1.2, size * 0.020),
        rim=Flesh.nerve_glow() if is_nerve else None,
        keyline=Flesh.nerve_keyline() if is_nerve else Flesh.OUTLINE,
    )
    _detail(size, tissue, m, seed, buf)
    if is_nerve:
        # canon: the nerve keyline goes on last so nothing eats it
        buf.composite(Flesh.nerve_keyline(), S.outline(m, max(2.2, size * 0.034)))
    return buf.to_image()


def unknown_icon(size: int = 128, seed: int = 0):
    """ICO-05.  Deliberately low contrast: unknowns must not read as identified."""
    buf = P.Buffer(size, size)
    m = S.blob(size, size, 0.50 * size, 0.52 * size, 0.34 * size, seed, lobes=7, rough=0.30)
    pal = {"base": "#8a5a58", "light": "#a5766f", "dark": "#5e3a3a"}
    buf.composite(P.shade_fill(m, pal["base"], pal["light"], pal["dark"], size * 0.07), m * 0.85)
    buf.composite(pal["dark"], P.form_crescent(m, size * 0.04) * 0.4)
    # a carved notch, not a glyph: no baked text anywhere in this project
    carve = S.ring(size, size, 0.5 * size, 0.42 * size, size * 0.075, size * 0.050, 200, 340)
    dot = S.circle(size, size, 0.5 * size, 0.60 * size, size * 0.028)
    q = np.clip(carve + dot, 0, 1) * m
    buf.composite("#4a2c2c", q)
    buf.composite(pal["light"], S.outline(q, size * 0.012) * 0.5)
    # weak keyline on purpose
    buf.composite("#4e3232", S.outline(m, max(1.5, size * 0.022)) * 0.6)
    return buf.to_image()


# --------------------------------------------------------------------------- accessibility
_SHAPE_ONLY = {
    # shape + pattern differ per tissue; colour is not required to tell them apart
    "T01": ("wedge with parallel bands", 0),
    "T02": ("round lobes, glossy", 1),
    "T03": ("torn strip with frayed ends", 2),
    "T04": ("single sac with inner highlight", 3),
    "T05": ("smooth plate with rim", 4),
    "T06": ("three strands, thickest keyline", 5),
    "T07": ("bulb cluster, many bumps", 6),
    "T08": ("rippled sheet, thin", 7),
    "T09": ("two stacked bars, heavy", 8),
    "T10": ("seam lines across a slab", 9),
}

_CB_FILL = ["#cf5a4a", "#e0b23c", "#ece4d2", "#a8788c", "#b9bdb6", "#f2d21a",
            "#ded3bb", "#c98fa0", "#e6ded0", "#e08a86"]


def _pattern_overlay(size: int, tissue: str, m: np.ndarray, seed: int, kind: int) -> np.ndarray:
    """A distinct hatch/dot/stipple per tissue, so shape alone carries the meaning."""
    h, w = size, size
    out = np.zeros((h, w), dtype=np.float32)
    if kind == 0:      # parallel bands
        out = P.striation(h, w, seed, angle=14, thickness=size * 0.045)
    elif kind == 1:    # concentric soft rings
        yy, xx = S.grid(h, w)
        d = np.sqrt((xx - 0.5 * size) ** 2 + (yy - 0.5 * size) ** 2)
        out = 0.5 + 0.5 * np.sin(d / max(1.0, size * 0.075) * math.pi)
    elif kind == 2:    # fine crosshatch
        out = P.crosshatch(h, w, seed, size * 0.13, size * 0.008)
    elif kind == 3:    # one big centre highlight dot
        out = S.circle(h, w, 0.5 * size, 0.5 * size, size * 0.17)
    elif kind == 4:    # single inner rim
        out = S.ring(h, w, 0.5 * size, 0.5 * size, size * 0.40, size * 0.36)
    elif kind == 5:    # wriggle ticks only
        out = _wriggle_ticks(size, m, seed, count=8)
    elif kind == 6:    # dense stipple
        out = S.circle(h, w, *np.unravel_index(
            np.argmax(P.pores(h, w, seed, 400, size * 0.012)), (h, w)), size * 0.02) * 0
        rng = np.random.default_rng(seed)
        for _ in range(160):
            out = np.maximum(out, S.circle(h, w, rng.random() * size, rng.random() * size,
                                           size * 0.012))
    elif kind == 7:    # wavy ripple
        yy, xx = S.grid(h, w)
        out = 0.5 + 0.5 * np.sin(yy / max(1.0, size * 0.05) + np.sin(xx / max(1.0, size * 0.09)))
    elif kind == 8:    # heavy solid inner bar
        out = S.rect(h, w, 0.24 * size, 0.42 * size, 0.76 * size, 0.58 * size, r=size * 0.03)
    else:              # dashed seam
        for i in range(3):
            y = (0.40 + 0.10 * i) * size
            for j in range(6):
                x0 = (0.16 + j * 0.115) * size
                out = np.maximum(out, S.capsule(h, w, x0, y, x0 + size * 0.07, y, size * 0.014))
    return np.clip(out, 0.0, 1.0) * m


def tissue_icon_colourblind(tissue: str, size: int = 128, seed: int = 0):
    """ACC-01 / ICO-27.  Shape and pattern carry the meaning, not colour."""
    kind = _SHAPE_ONLY[tissue][1]
    mass = MASSS[tissue](size, seed)
    mass = np.clip(mass, 0.0, 1.0)
    base = _CB_FILL[kind]
    buf = P.Buffer(size, size)
    is_nerve = tissue == "T06"
    kl = max(3.0, size * 0.058) if is_nerve else max(2.0, size * 0.044)

    buf.composite(P.shade_fill(mass, base, mix(base, "#ffffff", 0.30),
                               mix(base, "#000000", 0.38), size * 0.06), mass)
    pat = _pattern_overlay(size, tissue, mass, seed, kind)
    buf.composite(mix(base, "#000000", 0.55), pat * mass * (0.85 if is_nerve else 0.62))
    buf.composite(mix(base, "#ffffff", 0.65), (1.0 - pat) * mass * 0.14)
    if is_nerve:
        buf.composite(Flesh.nerve_light(),
                      (S.dilate(mass, size * 0.028) - S.dilate(mass, size * 0.070)) * mass)
    buf.composite("#101010" if not is_nerve else Flesh.nerve_keyline(), S.outline(mass, kl))
    return buf.to_image()


def nerve_icon_high_contrast(size: int = 128, seed: int = 0):
    """ACC-02 / ICO-28.  White halo, hard black keyline: readable on any background."""
    m = np.clip(_t06_nerve(size, seed), 0.0, 1.0)
    buf = P.Buffer(size, size)
    halo = S.outline(m, size * 0.085)
    buf.composite("#ffffff", halo)
    buf.composite("#000000", S.outline(m, size * 0.050))
    buf.composite(P.shade_fill(m, Flesh.nerve_base(), Flesh.nerve_light(),
                               Flesh.nerve_deep(), size * 0.05), m)
    buf.composite(Flesh.nerve_glow(), S.dilate(m, size * 0.022) - S.dilate(m, size * 0.055))
    buf.composite(Flesh.nerve_light(), _wriggle_ticks(size, m, seed, count=6) * 0.9)
    return buf.to_image()
