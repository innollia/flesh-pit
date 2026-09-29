"""DEP: depth and anatomical position UI, DEP-01 to DEP-22.

Canon: depth is the objective and it is the score.  Two macro-progress displays
must coexist -- depth and player capability -- so the meter is a long vertical
housing and the band ladder is its separate menu-scale summary.

Every band label row (DEP-05..DEP-12) is a BLANK enamel plate.  The band name is
font text at runtime; baking it would violate the no-baked-text rule.

Rows: docs/asset-list.md section 4.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np

from fleshkit import build as B
from fleshkit import paint as P
from fleshkit import shapes as S
from fleshkit import widgets as W
from fleshkit.palette import Flesh, Restroom, mix, ramp

HUD = "ui/hud"
PANEL = {"base": Flesh.UI_PANEL, "light": Flesh.UI_PANEL_LIGHT, "dark": Flesh.UI_EDGE}


def main() -> int:
    n = 0
    W_, H_ = 256, 1024

    # ---------------------------------------------------------------- DEP-01 meter frame
    buf = P.Buffer(W_, H_)
    body = S.rect(H_, W_, 26, 18, W_ - 26, H_ - 18, r=22)
    buf.composite(P.shade_fill(body, Flesh.BRASS, Flesh.BRASS_LIGHT, Flesh.RUST_DARK,
                               W_ * 0.05), body)
    buf.composite(Flesh.RUST, P.grime(H_, W_, 3, 0.55) * body * 0.75)
    buf.composite(Flesh.RUST_DARK, P.form_crescent(body, W_ * 0.05) * 0.55)
    # soiled edges, heavier at top and bottom
    edge = (S.inner_edge(body, 26) * (S.value_noise(H_, W_, 60, 7, 3) * 0.9 + 0.1))
    buf.composite(Flesh.RUST_DARK, edge * 0.6)
    # bone inlay strips down both sides
    for x in (44, W_ - 44):
        strip = S.rect(H_, W_, x - 6, 44, x + 6, H_ - 44, r=6)
        buf.composite(P.shade_fill(strip, Flesh.BONE, "#ffffff", Flesh.BONE_SHADE, 8.0), strip)
    # the transparent rail the fill strip shows through
    rail = S.rect(H_, W_, 96, 46, W_ - 96, H_ - 46, r=14)
    buf.composite(Flesh.SHADOW, rail * 0.85)
    buf.composite(Flesh.OUTLINE, S.outline(rail, 3.0))
    buf.composite(Flesh.OUTLINE, S.outline(body, 4.0))
    p = B.fname(HUD, "dep", "meter", "frame_9s")
    B.register("DEP-01", p, W_, H_, "MVP", "9slice", note="9-slice 32/960/32, brass and bone")
    B.save(buf.to_image(), p)
    n += 1

    # ---------------------------------------------------------------- DEP-02 fill strip
    S_ = 1024
    buf = P.Buffer(64, S_)
    grad = P.linear_gradient(S_, 64, [Flesh.BONE, "#e8d8b8", Flesh.SKIN_PINK_DARK,
                                      Flesh.BLOOD, Flesh.CONGESTED], angle=90.0)
    buf.composite(grad, np.ones((S_, 64), dtype=np.float32))
    buf.composite(Flesh.BLOOD_DARK, P.grime(S_, 64, 9, 0.30) * 0.35)
    p = B.fname(HUD, "dep", "meter", "fill_strip_64x1024")
    B.register("DEP-02", p, 64, S_, "MVP", note="bone-white to deep red, tileable Y")
    B.save(buf.to_image(), p)
    n += 1

    # ---------------------------------------------------------------- DEP-03 tick texture
    S_ = 512
    buf = P.Buffer(64, S_)
    ticks = np.zeros((S_, 64), dtype=np.float32)
    for i in range(51):
        y = 8 + i * (S_ - 16) / 50.0
        long_ = (i % 5 == 0)
        ln = 30 if long_ else 16
        ticks = np.maximum(ticks, S.capsule(S_, 64, 6, y, 6 + ln, y, 1.6))
    buf.composite(P.shade_fill(ticks, Flesh.BONE, "#ffffff", Flesh.BONE_SHADE, 5.0), ticks)
    buf.composite(Flesh.OUTLINE, S.outline(ticks, 1.2) * 0.7)
    p = B.fname(HUD, "dep", "meter", "tick_texture_64x512")
    B.register("DEP-03", p, 64, S_, "P1", note="minor ticks at 10 m, major every 50 m")
    B.save(buf.to_image(), p)
    n += 1

    # ---------------------------------------------------------------- DEP-04 band divider
    buf = P.Buffer(64, 32)
    bar = S.rect(32, 64, 4, 12, 60, 20, r=4)
    buf.composite(P.shade_fill(bar, Flesh.BONE, "#ffffff", Flesh.BONE_SHADE, 5.0), bar)
    buf.composite(Flesh.OUTLINE, S.outline(bar, 1.6) * 0.8)
    for x in (20, 44):
        notch = S.rect(32, 64, x - 3, 12, x + 3, 26, r=2)
        buf.composite(Flesh.OUTLINE, notch * 0.9)
        buf.composite(Flesh.BONE, notch * 0.25)
    p = B.fname(HUD, "dep", "band", "divider_marker_64x32")
    B.register("DEP-04", p, 64, 32, "MVP", note="bone bar with two notches, used 8x")
    B.save(buf.to_image(), p)
    n += 1

    # ---------------------------------------------------------------- DEP-05..12 band plates
    for k in range(8):
        w_, h_ = 512, 128
        buf = P.Buffer(w_, h_)
        W.plate(buf, w_, h_, 14, Flesh.BONE, "#ffffff", Flesh.BONE_SHADE,
                seed=40 + k, worn=0.42)
        # two rivets and a blank centre: the name is font text at runtime
        for x in (34, w_ - 34):
            r = S.circle(h_, w_, x, h_ / 2, 9)
            buf.composite(P.shade_fill(r, Flesh.IRON_LIGHT, "#c9c5c2", Flesh.IRON, 5.0), r)
            buf.composite(Flesh.OUTLINE, S.outline(r, 1.6) * 0.8)
        p = B.fname(HUD, "dep", "band", f"label_b{k + 1:02d}_512x128")
        B.register(f"DEP-{5 + k:02d}", p, w_, h_, "MVP" if k < 3 else "P1",
                   note="BLANK enamel plate, no baked text: band name is font-rendered")
        B.save(buf.to_image(), p)
        n += 1

    # ---------------------------------------------------------------- DEP-13 banner frame
    w_, h_ = 1024, 256
    buf = P.Buffer(w_, h_)
    body = W.banner(buf, w_, h_, 0, PANEL, seed=13)
    ruled = W.torn_edge(h_, w_, h_ * 0.86, seed=14, down=True)
    body = np.clip(body - ruled, 0, 1)
    buf.composite(Flesh.OUTLINE, S.outline(body, 4.0))
    p = B.fname(HUD, "dep", "band", "change_banner_9s")
    B.register("DEP-13", p, w_, h_, "MVP", "9slice", note="torn flesh banner, top band reserved for text")
    B.save(buf.to_image(), p)
    n += 1

    # ---------------------------------------------------------------- DEP-14 accent sweep
    w_, h_ = 512, 64
    buf = P.Buffer(w_, h_)
    grad = P.linear_gradient(h_, w_, [Flesh.BLOOD_DARK, Flesh.BLOOD, Flesh.SKIN_PINK,
                                      "#ffffff", Flesh.SKIN_PINK, Flesh.BLOOD,
                                      Flesh.BLOOD_DARK], angle=0.0)
    # soft top and bottom edges so the wipe has no hard seam
    vert = 1.0 - np.abs(np.linspace(-1, 1, h_, dtype=np.float32))[:, None]
    buf.composite(grad, S.blur(vert, 4.0) * 0.95)
    p = B.fname(HUD, "dep", "band", "accent_sweep_512x64")
    B.register("DEP-14", p, w_, h_, "P1", note="soft red-to-white horizontal wipe")
    B.save(buf.to_image(), p)
    n += 1

    # ---------------------------------------------------------------- DEP-15 milestone frame
    w_, h_ = 512, 256
    buf = P.Buffer(w_, h_)
    body = S.rect(h_, w_, 30, 26, w_ - 30, h_ - 26, r=16)
    buf.composite(P.shade_fill(body, Flesh.BONE, "#ffffff", Flesh.BONE_SHADE,
                               w_ * 0.03), body)
    buf.composite(Flesh.GRIME, P.grime(h_, w_, 15, 0.40) * body * 0.5)
    buf.composite(Flesh.OUTLINE, S.outline(body, 5.0))
    # rough-cut inner edge
    inner = S.rect(h_, w_, 46, 42, w_ - 46, h_ - 42, r=10)
    inner = S.roughen(inner, S.value_noise(h_, w_, 18, 16, 3), 0.7, 1.6)
    buf.composite(Flesh.BONE_SHADE, inner * 0.0)
    buf.composite(Flesh.OUTLINE, S.outline(inner, 2.5) * 0.85)
    # hanging specimen hooks
    for x in (150, 256, 362):
        buf.composite(Flesh.IRON, S.capsule(h_, w_, x, 26, x, 74, 5.0))
        hook = S.arc_stroke(h_, w_, x + 14, 76, 14, 5.0, 200, 340)
        buf.composite(Flesh.IRON_LIGHT, hook)
    p = B.fname(HUD, "dep", "milestone", "frame_9s")
    B.register("DEP-15", p, w_, h_, "P1", "9slice", note="rough-cut bone frame with hooks")
    B.save(buf.to_image(), p)
    n += 1

    # ---------------------------------------------------------------- DEP-16 milestone seal
    w_ = 256
    buf = P.Buffer(w_, w_)
    seal = S.star(w_, w_, w_ / 2, w_ / 2, 104, 84, points=9)
    seal = S.roughen(seal, S.value_noise(w_, w_, 14, 16, 3), 0.5, 1.4)
    buf.composite(P.shade_fill(seal, Flesh.BLOOD, "#a32a2c", Flesh.BLOOD_DARK, 12.0), seal)
    buf.composite(Flesh.SEAM_SPLIT, P.grime(w_, w_, 16, 0.5) * seal * 0.5)
    # generic mark: a depth bar, no text
    mark = np.zeros((w_, w_), dtype=np.float32)
    for i in range(4):
        y = w_ * (0.36 + 0.10 * i)
        mark = np.maximum(mark, S.rect(w_, w_, w_ * 0.30, y, w_ * (0.70 - 0.06 * i),
                                       y + 14, r=6))
    mark = mark * seal
    buf.composite("#ffffff", mark * 0.0)
    buf.composite(Flesh.SEAM_SPLIT, mark)
    buf.composite(Flesh.OUTLINE, S.outline(seal, 4.0))
    p = B.fname(HUD, "dep", "milestone", "seal_256x256")
    B.register("DEP-16", p, w_, w_, "P1", note="wax-red stamp, generic depth-bar mark, no text")
    B.save(buf.to_image(), p)
    n += 1

    # ---------------------------------------------------------------- DEP-17 numerals (EMPTY)
    S_ = 128
    buf = P.Buffer(S_ * 12, S_ * 2)
    for i in range(24):
        cx, cy = (i % 12) * S_ + S_ / 2, (i // 12) * S_ + S_ / 2
        cell = S.rect(S_ * 2, S_ * 12, cx - S_ * 0.28, cy - S_ * 0.36,
                      cx + S_ * 0.28, cy + S_ * 0.36, r=S_ * 0.10)
        buf.composite(Flesh.UI_EDGE, cell * 0.26)
        buf.composite(Flesh.OUTLINE, S.outline(cell, 2.0) * 0.65)
    p = B.fname(HUD, "dep", "numerals", "atlas_1536x256")
    B.register("DEP-17", p, S_ * 12, S_ * 2, "MVP", "atlas", frames=24,
               note="EMPTY stencil cells: 0-9, m, minus rendered by the font, never baked")
    B.save(buf.to_image(), p)
    n += 1

    # ---------------------------------------------------------------- DEP-18 personal best
    p = B.fname(HUD, "dep", "personal_best", "flag_64x64")
    B.register("DEP-18", p, 64, 64, "P1", note="small gold flag on the meter rail")
    B.save(W.bone_flag(64), p)
    n += 1

    # ---------------------------------------------------------------- DEP-19 / DEP-21 arrows
    p = B.fname(HUD, "dep", "surface_arrow_128x128")
    B.register("DEP-19", p, 128, 128, "MVP", note="upward chevron, clean white, points to the restroom")
    B.save(W.chevron_icon(128, Restroom.CERAMIC, down=False, weight=19), p)
    n += 1
    p = B.fname(HUD, "dep", "danger_arrow_128x128")
    B.register("DEP-21", p, 128, 128, "P1", note="downward chevron, dull yellow")
    B.save(W.chevron_icon(128, Flesh.MOULD, down=True, weight=19), p)
    n += 1

    # ---------------------------------------------------------------- DEP-20 home bearing chip
    w_, h_ = 256, 128
    buf = P.Buffer(w_, h_)
    body = W.card(buf, w_, h_, 14, PANEL, corner=26, seed=20)
    dial = S.circle(h_, w_, 66, h_ / 2, 34)
    buf.composite(P.shade_fill(dial, Flesh.BRASS, Flesh.BRASS_LIGHT, Flesh.RUST_DARK, 8.0), dial)
    buf.composite(Flesh.OUTLINE, S.outline(dial, 2.5))
    buf.composite("#ffffff", S.capsule(h_, w_, 66, 26, 66, 48, 4.0))
    buf.composite(Flesh.BLOOD_DARK, S.capsule(h_, w_, 66, 50, 66, 96, 3.0))
    W.slot(buf, w_, h_, 118, 30, 118, 68, fill=Flesh.UI_EDGE, r=14)
    p = B.fname(HUD, "dep", "home_bearing", "chip_9s")
    B.register("DEP-20", p, w_, h_, "P1", "9slice", note="ties the compass to the actual goal")
    B.save(buf.to_image(), p)
    n += 1

    # ---------------------------------------------------------------- DEP-22 band ladder
    w_, h_ = 128, 512
    buf = P.Buffer(w_, h_)
    rail = S.rect(h_, w_, 22, 12, 34, h_ - 12, r=6)
    buf.composite(P.shade_fill(rail, Flesh.BONE, "#ffffff", Flesh.BONE_SHADE, 6.0), rail)
    for i in range(8):
        y = 30 + i * (h_ - 66) / 7.0
        rung = S.rect(h_, w_, 34, y - 6, w_ - 20, y + 6, r=6)
        # the current rung is the brightest; the others recede
        active = (i == 3)
        buf.composite(Flesh.BONE if not active else Flesh.nerve_base(), rung)
        buf.composite(Flesh.OUTLINE, S.outline(rung, 1.6) * 0.75)
    p = B.fname(HUD, "dep", "band", "progress_ladder_128x512")
    B.register("DEP-22", p, w_, h_, "P2", note="eight rungs, current highlighted, no text")
    B.save(buf.to_image(), p)
    n += 1

    print(f"DEP: {n} files")
    print(B.write_manifest("manifest_dep.json"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
