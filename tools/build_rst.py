"""RST: restroom UI and clean-white surface art, MVP rows.

MVP scope: RST-01, RST-02, RST-04, RST-05, RST-06, RST-07, RST-08, RST-19.

THE RULE: the restroom is clean and white.  It is the one deliberate visual
exception in an otherwise red, dirty biological world, and it is the emotional
reset between excursions (design-core.md section 8).  If it picks up grime the
game loses its contrast and the loop loses its punctuation.

So this module never calls ``P.grime``, ``P.mottling`` or ``P.pores`` on a
restroom surface.  Cleanliness is a material property here, not a colour: the
roughness map (RST-06) carries the story, and the albedo stays bright.

Rows: docs/asset-list.md section 8.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

from fleshkit import build as B
from fleshkit import paint as P
from fleshkit import shapes as S
from fleshkit import widgets as W
from fleshkit.palette import Flesh, Restroom, mix

PANELS = "ui/panels"
TEX = "textures/restroom"


def tile_grid(size, pitch, grout_w, base, alt, deep, *, jitter=0.02, seed=0):
    """A clean ceramic tile field.  Returns (albedo, height).

    ``height`` is what the normal map and the roughness map are derived from, so
    grout reads as real depth in the engine rather than as a painted line.

    Per-tile tint is deliberately tiny (``jitter`` defaults near zero) and the
    pattern is a checker, not a random draw: a strongly randomised tint on a
    regular grid reads as a repeating checkerboard once the texture tiles, which
    is exactly the failure asset-list.md's lessons-learned section warns about.
    """
    h = w = size
    albedo = np.zeros((h, w, 3), dtype=np.float32)
    albedo[:] = hex3(Restroom.GROUT)
    height = np.full((h, w), 0.72, dtype=np.float32)
    rng = np.random.default_rng(seed)
    n = int(math.ceil(size / pitch))
    for iy in range(n):
        for ix in range(n):
            x0, y0 = ix * pitch, iy * pitch
            x1, y1 = x0 + pitch, y0 + pitch
            # subtle per-tile variation, well under the visible threshold
            t = float(rng.normal(0.0, jitter))
            tile_col = mix(base, alt, 0.5 + 3.0 * t)
            gx0, gy0 = x0 + grout_w // 2, y0 + grout_w // 2
            gx1, gy1 = x0 + pitch - grout_w // 2, y0 + pitch - grout_w // 2
            x0c, y0c = max(0, gx0), max(0, gy0)
            x1c, y1c = min(w, gx1), min(h, gy1)
            if x1c <= x0c or y1c <= y0c:
                continue
            albedo[y0c:y1c, x0c:x1c] = tile_col
            # a soft in-tile gradient so each tile has a lit corner
            yy, xx = np.mgrid[y0c:y1c, x0c:x1c]
            g = ((xx - x0c) + (yy - y0c)) / max(1.0, float((x1c - x0c + y1c - y0c)))
            albedo[y0c:y1c, x0c:x1c] *= (1.03 - 0.06 * g)[..., None]
            height[y0c:y1c, x0c:x1c] = 0.90
    return np.clip(albedo, 0.0, 1.0), np.clip(height, 0.0, 1.0)


def hex3(c) -> np.ndarray:
    from fleshkit.palette import hex_rgb
    return hex_rgb(c)[:3]


def save_rgb(arr: np.ndarray, rel: str, *, linear: bool = False) -> None:
    """Write a non-alpha map.  Albedo is sRGB and gets the house grade; normal,
    roughness and mask maps are LINEAR data and must never be graded."""
    a = np.clip(arr, 0.0, 1.0)
    if a.ndim == 2:
        a = np.dstack([a, a, a])
    if a.shape[2] == 3:
        a = np.dstack([a, np.ones_like(a[..., :1])])
    img = Image.fromarray(np.ascontiguousarray((a * 255.0 + 0.5).astype(np.uint8)), "RGBA")
    B.save(img, rel, grade=not linear)
    if linear:
        # record the colour space next to the file so nobody has to guess
        (B.ASSETS / rel).with_suffix(".linear.txt").write_text(
            "linear\n", encoding="utf-8")


def main() -> int:
    n = 0

    # ------------------------------------------------------------- RST-01 toilet prompt
    buf = P.Buffer(128, 128)
    # a clean white outline icon: tank, bowl, pedestal, plus an arrow above
    tank = S.rect(128, 128, 34, 22, 74, 50, r=6)
    bowl = S.polygon(128, 128, [(28, 50), (80, 50), (70, 76), (38, 76)])
    ped = S.polygon(128, 128, [(48, 76), (60, 76), (56, 98), (52, 98)])
    base = S.rect(128, 128, 34, 98, 74, 104, r=4)
    body = S.union(tank, bowl, ped, base)
    ring = np.clip(S.outline(body, 4.0), 0, 1)
    buf.composite(Restroom.CERAMIC, ring)
    buf.composite(Restroom.ENAMEL_EDGE, S.outline(body, 6.0) * 0.0)
    # arrow above, pointing down at the toilet
    arr = S.capsule(128, 128, 64, 6, 64, 16, 3.5)
    arr = np.maximum(arr, S.chevron(128, 128, 64, 18, 14, 3.5, down=True))
    buf.composite(Restroom.CERAMIC, arr)
    p = B.fname(PANELS, "rst", "toilet_prompt_128x128")
    B.register("RST-01", p, 128, 128, "MVP", note="clean white outline, no text, arrow above")
    B.save(buf.to_image(), p)
    n += 1

    # ------------------------------------------------------------- RST-02 bowl fill gauge
    w_, h_ = 512, 256
    buf = P.Buffer(w_, h_)
    rim = S.ellipse(h_, w_, w_ / 2, h_ * 0.44, w_ * 0.42, h_ * 0.34)
    buf.composite(P.shade_fill(rim, Restroom.CERAMIC, "#ffffff", Restroom.CERAMIC_SHADE,
                               w_ * 0.018), rim)
    bowl = S.ellipse(h_, w_, w_ / 2, h_ * 0.46, w_ * 0.33, h_ * 0.25)
    buf.composite(P.shade_fill(bowl, Restroom.CERAMIC_SHADE, Restroom.WATER,
                               Restroom.GROUT, w_ * 0.014), bowl)
    # pale chewed flesh filling the bowl
    chew = S.ellipse(h_, w_, w_ / 2, h_ * 0.52, w_ * 0.29, h_ * 0.18)
    buf.composite(P.shade_fill(chew, Flesh.SKIN_PINK, Flesh.SKIN_WET,
                               Flesh.SKIN_PINK_DARK, w_ * 0.010), chew)
    buf.composite(Flesh.BLOOD, P.vein_web(h_, w_, 2, count=5, width=w_ * 0.004) * chew * 0.5)
    buf.composite(Restroom.ENAMEL_EDGE, S.outline(rim, 3.0) * 0.8)
    p = B.fname(PANELS, "rst", "bowl_fill_gauge_9s")
    B.register("RST-02", p, w_, h_, "MVP", "9slice", note="cross-section filling with pale chewed flesh")
    B.save(buf.to_image(), p)
    n += 1

    # ------------------------------------------------------------- RST-04 wall tile albedo
    size = 2048
    albedo, height = tile_grid(size, 256, 8, Restroom.WALL_TILE, Restroom.WALL_TILE_ALT,
                               Restroom.WALL_TILE_DEEP, seed=4)
    # a few chips, so the tile is not factory-perfect
    rng = np.random.default_rng(44)
    for _ in range(26):
        x, y = int(rng.random() * size), int(rng.random() * size)
        r = int(6 + rng.random() * 16)
        yy, xx = np.mgrid[max(0, y - r):y + r, max(0, x - r):x + r]
        chip = S.circle(2 * r, 2 * r, r, r, r * (0.5 + rng.random() * 0.5))
        y0, x0 = max(0, y - r), max(0, x - r)
        y1, x1 = min(size, y + r), min(size, x + r)
        sub = albedo[y0:y1, x0:x1]
        albedo[y0:y1, x0:x1] = mix(sub, hex3(Restroom.WALL_TILE_DEEP),
                                   chip[:y1 - y0, :x1 - x0] * 0.8)
    p = B.fname(TEX, "wall_tile_albedo_2k")
    B.register("RST-04", p, size, size, "MVP", "png", note="clean glazed white tile, faint grout variation, a few chips")
    save_rgb(albedo, p)
    n += 1

    # ------------------------------------------------------------- RST-05 tile grout normal
    # Recessed grout: height 0.85 in the gap, 0.90 on the tile, slightly uneven.
    _, height = tile_grid(size, 256, 8, Restroom.WALL_TILE, Restroom.WALL_TILE_ALT,
                          Restroom.WALL_TILE_DEEP, seed=4)
    uneven = S.blur(S.value_noise(size, size, 320.0, 5, 2), 3.0) * 0.03
    height = np.clip(height + uneven, 0.0, 1.0)
    nrm = B.normal_from_height(height, strength=1.6)
    p = B.fname(TEX, "tile_grout_normal_2k")
    B.register("RST-05", p, size, size, "MVP", "png", note="recessed grout, slightly uneven; OpenGL +Y up")
    save_rgb(nrm, p, linear=True)
    n += 1

    # ------------------------------------------------------------- RST-06 tile roughness
    # Near-uniform gloss, faint dulling near the floor (bottom of the map).
    # Glazed restroom tile is glossy, so the base value stays low; only the grout
    # and the floor-ward band are rougher.
    rough = np.full((size, size), 0.30, dtype=np.float32)
    yy = np.linspace(0.0, 1.0, size, dtype=np.float32)[:, None]
    rough = rough + np.clip(yy - 0.72, 0, 1) * 0.34          # duller low down
    rough = rough + S.blur(S.value_noise(size, size, 260.0, 6, 2), 4.0) * 0.06
    _, height = tile_grid(size, 256, 8, Restroom.WALL_TILE, Restroom.WALL_TILE_ALT,
                          Restroom.WALL_TILE_DEEP, seed=4)
    # grout is always much rougher than glaze
    rough = np.clip(rough + (1.0 - height) * 1.10, 0.0, 1.0)
    p = B.fname(TEX, "tile_roughness_2k")
    B.register("RST-06", p, size, size, "MVP", "png",
               note="near-uniform gloss, faint dulling near the floor; LINEAR")
    save_rgb(rough, p, linear=True)
    n += 1

    # ------------------------------------------------------------- RST-07 floor tile albedo
    albedo, _ = tile_grid(size, 192, 7, Restroom.FLOOR_TILE, Restroom.FLOOR_TILE_ALT,
                          Restroom.GROUT, jitter=0.03, seed=7)
    p = B.fname(TEX, "floor_tile_albedo_2k")
    B.register("RST-07", p, size, size, "MVP", "png", note="smaller pale grey matte tile")
    save_rgb(albedo, p)
    n += 1

    # ------------------------------------------------------------- RST-08 stainless fixture
    size2 = 1024
    buf = P.Buffer(size2, size2)
    base = np.full((size2, size2, 3), 0.0, dtype=np.float32)
    base[:] = hex3(Restroom.STEEL)
    # brushed grain: long horizontal streaks
    brush = P.fibres(size2, size2, 8, 0.0, 260, size2 * 0.0018, size2 * 0.9)
    base = base * (0.90 + 0.16 * brush)[..., None]
    # faint water marks
    marks = np.zeros((size2, size2), dtype=np.float32)
    rng = np.random.default_rng(88)
    for _ in range(40):
        x, y = rng.random() * size2, rng.random() * size2
        rr = 30 + rng.random() * 120
        marks = np.maximum(marks, S.circle(size2, size2, x, y, rr) * 0.25)
    base = mix(base, hex3(Restroom.STEEL_DARK), S.blur(marks, 6.0) * 0.5)
    p = B.fname(TEX, "stainless_fixture_albedo_1k")
    B.register("RST-08", p, size2, size2, "MVP", "png", note="brushed steel, faint water marks")
    save_rgb(base, p)
    n += 1

    # ------------------------------------------------------------- RST-19 clean transition
    S_ = 1024
    buf = P.Buffer(S_, S_)
    yy, xx = S.grid(S_, S_)
    # a white wash that fills the screen: brightest at centre, no hard edge
    a = np.clip(1.0 - np.sqrt(((xx / S_) - .5) ** 2 + ((yy / S_) - .5) ** 2) / .7071, 0, 1)
    a = S.blur(a ** 0.7, 18.0) * 0.96
    buf.composite("#ffffff", a)
    buf.composite(Restroom.FLUORESCENT, P.radial_mask(S_, S_, 0.5, 0.5, 0.55, 1.4) * 0.5)
    p = B.fname(PANELS, "rst", "clean_transition_1024x1024")
    B.register("RST-19", p, S_, S_, "MVP", note="white wash on entering the base: the strongest colour event")
    B.save(buf.to_image(), p)
    n += 1

    print(f"RST MVP: {n} files")
    print(B.write_manifest("manifest_rst.json"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
