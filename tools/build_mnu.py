"""MNU: menu, settings and flow UI, MVP rows.

MVP scope: MNU-01 (main menu background), MNU-02 (logo plate), MNU-03 (menu
panel frame), MNU-04 (button states), MNU-07 (checkbox states), MNU-09 (slider
track), MNU-18 (UI font bitmap set).

MNU-01 is the pitch: red flesh on the right, clean restroom light spilling from
the left, centre left empty for a menu list.  That contrast IS the game, so the
composition is built around the two light sources meeting in a dirty middle.

MNU-18 ships EMPTY stencil cells.  Canon forbids baked text including numerals,
and this row is explicitly "no third-party IP"; the runtime font renders into
these cells.  A shipped glyph atlas would violate both rules at once.

Rows: docs/asset-list.md section 10.
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

MNU = "ui/menu"
BRAND = "brand"
PANEL = {"base": Flesh.UI_PANEL, "light": Flesh.UI_PANEL_LIGHT, "dark": Flesh.UI_EDGE}


def main() -> int:
    n = 0

    # ------------------------------------------------------ MNU-01 menu background
    w_, h_ = 1920, 1080
    yy, xx = S.grid(h_, w_)
    buf = P.Buffer(w_, h_)
    u = np.ones((h_, w_), dtype=np.float32)

    # right side: the flesh world, falling away into darkness
    flesh = mix(Flesh.MUSCLE_DARK, Flesh.MUSCLE, 0.5 + 0.5 * S.fbm(h_, w_, 1, w_ * 0.20, 4))
    flesh = mix(flesh, Flesh.BLOOD_DARK, S.fbm(h_, w_, 2, w_ * 0.08, 3) * 0.5)
    flesh = mix(flesh, Flesh.GRIME_DEEP, P.grime(h_, w_, 3, 0.7) * 0.7)
    # tissue structures so the right side is not a flat wall
    fib = P.fibres(h_, w_, 4, angle=64.0, count=int(h_ * 0.9), width=w_ * 0.0016, length=h_ * 0.18)
    flesh = mix(flesh, Flesh.MUSCLE_LIGHT, fib * 0.35)
    flesh = mix(flesh, Flesh.FAT, np.clip(P.fibres(h_, w_, 5, angle=-24.0, count=140,
                                                    width=w_ * 0.0022, length=h_ * 0.10), 0, 1) * 0.25)
    flesh = mix(flesh, Flesh.BLOOD_DARK, P.vein_web(h_, w_, 6, count=14, width=w_ * 0.0016) * 0.55)
    # depth: darken toward the right and the top, but never to a flat black.
    # A fully black half reads as an empty frame rather than as receding flesh.
    depth = np.clip((xx / w_ - 0.30) * 1.25, 0, 1)
    flesh = mix(flesh, Flesh.SHADOW, depth ** 2.0 * 0.55)
    flesh = mix(flesh, Flesh.SHADOW, np.clip((yy / h_ - 0.60) * 1.6, 0, 1) * 0.30)

    # left side: the clean restroom, the only bright thing in the world
    clean = mix(Restroom.WALL_TILE, Restroom.WALL_TILE_DEEP, S.fbm(h_, w_, 7, w_ * 0.22, 3) * 0.6)
    clean = mix(clean, Restroom.WALL_TILE_DEEP, S.fbm(h_, w_, 8, w_ * 0.05, 3) * 0.4)
    # tile grid
    pitch = 128
    gy = np.maximum(((yy % pitch) < 4).astype(np.float32),
                    ((xx % pitch) < 4).astype(np.float32))
    clean = mix(clean, Restroom.GROUT, gy * 0.7)
    light = P.radial_mask(h_, w_, 0.10, 0.46, 0.72, 1.3)
    clean = mix(clean, Restroom.FLUORESCENT, light * 0.55)

    # The two worlds meet across the middle: clean on the left, flesh on the
    # right, with a dirty seam where they cross.  This is a ramp, not a spike --
    # a spike left everything outside the transition band on one side, which put
    # restroom tile across the whole right half.
    ramp_x = np.clip((xx / w_ - 0.30) * 3.2, 0, 1) ** 1.15
    meat = mix(clean, flesh, ramp_x)
    # the seam itself is the dirtiest place in the image
    seam = np.clip(1.0 - np.abs(xx / w_ - 0.44) * 9.0, 0, 1)
    meat = mix(meat, Flesh.GRIME, P.grime(h_, w_, 9, 0.55) * seam * 0.65)
    buf.composite(meat, u)
    # the tunnel mouth: an irregular wound, not a black disc.  A clean circle
    # here reads as a hole punched in the artwork.
    mouth = S.blob(h_, w_, w_ * 0.66, h_ * 0.54, w_ * 0.14, 21, lobes=4, rough=0.24,
                   squash=1.9, rot=12)
    mouth = S.roughen(mouth, S.value_noise(h_, w_, 60, 22, 3), 0.55, 5.0)
    buf.composite(Flesh.SHADOW, S.blur(mouth, 16.0) * 0.90)
    lip = S.outline(mouth, 26.0)
    buf.composite(mix(Flesh.BLOOD_DARK, Flesh.GRIME, 0.4), S.blur(lip, 7.0) * 0.55)
    buf.composite(Flesh.MUSCLE_DARK, S.erode(mouth, 20.0) * 0.30)
    p = B.fname(MNU, "main_menu_background_1920x1080")
    B.register("MNU-01", p, w_, h_, "MVP", "png",
               note="red flesh right, clean restroom light left, centre empty for the menu list")
    B.save(buf.to_image(), p)
    n += 1

    # ------------------------------------------------------ MNU-02 logo plate
    w_, h_ = 2048, 512
    buf = P.Buffer(w_, h_)
    # The wordmark is font-rendered, so this plate is the lockup furniture: a
    # dark backing shape and the bite motif, no lettering.
    plate = S.ellipse(h_, w_, w_ * 0.5, h_ * 0.5, w_ * 0.40, h_ * 0.30, rot=-4)
    plate = S.roughen(plate, S.value_noise(h_, w_, 40, 11, 3), 0.35, 3.0)
    buf.composite(Flesh.SHADOW, np.clip(S.dilate(plate, 26) - plate, 0, 1) * 0.8)
    buf.composite(P.shade_fill(plate, Flesh.UI_PANEL, Flesh.UI_PANEL_LIGHT,
                               Flesh.UI_EDGE, w_ * 0.006), plate)
    # the bite: a torn crescent cut from the right edge
    bite = S.circle(h_, w_, w_ * 0.735, h_ * 0.44, h_ * 0.26)
    bite2 = S.circle(h_, w_, w_ * 0.815, h_ * 0.60, h_ * 0.20)
    cut = S.union(bite, bite2)
    cut = S.roughen(cut, S.value_noise(h_, w_, 26, 12, 3), 0.55, 2.2)
    plate = S.subtract(plate, cut)
    buf.composite(Flesh.BLOOD_DARK, np.clip(S.dilate(plate, 8) - plate, 0, 1) * 0.5)
    # bone-white edge, not a comic outline
    fall = S.blur(plate, 10) - S.blur(plate, 24)
    buf.composite(Flesh.OUTLINE, np.clip(fall, 0, 1) * 0.8)
    p = B.fname(BRAND, "menu_logo_plate_2048x512")
    B.register("MNU-02", p, w_, h_, "MVP", "png32",
               note="logo lockup backing plate with the bite motif; no baked lettering")
    B.save(buf.to_image(), p)
    n += 1

    # ------------------------------------------------------ MNU-03 menu panel frame
    w_, h_ = 1024, 1024
    buf = P.Buffer(w_, h_)
    body = W.clean_card(buf, w_, h_, 60, corner=44)
    buf.composite(Restroom.ENAMEL_EDGE, S.outline(body, 5.0) * 0.9)
    buf.composite(Restroom.WALL_TILE_DEEP, S.inner_edge(body, 10.0) * 0.5)
    p = B.fname(MNU, "panel_frame_9s")
    B.register("MNU-03", p, w_, h_, "MVP", "9slice", note="frosted clean panel, thin dark border")
    B.save(buf.to_image(), p)
    n += 1

    # ------------------------------------------------------ MNU-04 button states
    bw, bh = 512, 128
    states = [("normal", 0.0, 0.0, False), ("hover", -3.0, 0.30, False),
              ("pressed", 2.0, -0.12, True), ("disabled", 0.0, -0.30, False)]
    tiles = []
    for name, lift, bright, inset in states:
        buf = P.Buffer(bw, bh)
        body = S.rect(bh, bw, 26, 22 + lift, bw - 26, bh - 22 + lift, r=18)
        base = mix(Flesh.UI_PANEL, Flesh.UI_PANEL_LIGHT, max(0.0, bright))
        light = mix(Flesh.UI_PANEL_LIGHT, "#ffffff", max(0.0, bright) * 0.5)
        dark = mix(Flesh.UI_EDGE, Flesh.UI_WASH, max(0.0, -bright))
        if inset:
            body = S.erode(body, 3)
        buf.composite(P.shade_fill(body, base, light, dark, bw * 0.02), body)
        buf.composite(dark, P.form_crescent(body, bw * 0.012) * 0.5)
        # soft edge, not a hard contour
        fall = S.blur(body, 7) - S.blur(body, 16)
        buf.composite(Flesh.OUTLINE, np.clip(fall, 0, 1) * 0.85)
        if bright > 0.2:
            buf.composite(Flesh.BONE, np.clip(S.dilate(body, 5) - body, 0, 1) * bright)
        if name == "disabled":
            buf.composite(Flesh.UI_EDGE, body * 0.45)
        tiles.append(buf.to_image())
    atlas = Image.new("RGBA", (bw, bh * len(tiles)), (0, 0, 0, 0))
    for i, t in enumerate(tiles):
        atlas.paste(t, (0, i * bh), t)
    p = B.fname(MNU, "button_states_512x128x4")
    B.register("MNU-04", p, bw, bh * 4, "MVP", "atlas", frames=4,
               note="normal, hover, pressed, disabled; no baked label")
    B.save(atlas, p)
    n += 1

    # ------------------------------------------------------ MNU-07 checkbox states
    cs = 64
    names = ["normal", "hover", "checked"]
    tiles = []
    for i, name in enumerate(names):
        buf = P.Buffer(cs, cs)
        box = S.rect(cs, cs, 10, 10, cs - 10, cs - 10, r=8)
        if i == 2:
            # the tick is a drawn stroke, not a font glyph
            box = S.subtract(box, S.ellipse(cs, cs, 34, 34, 17, 17))
        base = Flesh.UI_WASH if i == 1 else Flesh.UI_PANEL
        buf.composite(P.shade_fill(box, base, Flesh.UI_PANEL_LIGHT, Flesh.UI_EDGE, 6.0), box)
        buf.composite(Flesh.OUTLINE, S.outline(box, 2.5) * 0.9)
        if i == 1:
            buf.composite(Flesh.BONE, S.outline(box, 2.5) * 0.8)
        if i == 2:
            tick = S.capsule(cs, cs, 20, 34, 29, 44, 3.2)
            tick = np.maximum(tick, S.capsule(cs, cs, 29, 44, 45, 21, 3.2))
            buf.composite(Flesh.BONE, tick)
        tiles.append(buf.to_image())
    atlas = Image.new("RGBA", (cs * 3, cs), (0, 0, 0, 0))
    for i, t in enumerate(tiles):
        atlas.paste(t, (i * cs, 0), t)
    p = B.fname(MNU, "checkbox_states_64x64x3")
    B.register("MNU-07", p, cs * 3, cs, "MVP", "atlas", frames=3,
               note="empty, hovered, ticked with a hand-drawn tick stroke")
    B.save(atlas, p)
    n += 1

    # ------------------------------------------------------ MNU-09 slider track
    w_, h_ = 64, 16
    buf = P.Buffer(w_, h_)
    track = S.rect(h_, w_, 2, 4, w_ - 2, h_ - 4, r=6)
    buf.composite(P.shade_fill(track, Flesh.UI_EDGE, Flesh.UI_WASH, Flesh.SHADOW, 3.0), track)
    fill = S.rect(h_, w_, 3, 5, w_ * 0.62, h_ - 5, r=5)
    buf.composite(P.shade_fill(fill, Flesh.BONE, "#ffffff", Flesh.BONE_SHADE, 3.0), fill)
    p = B.fname(MNU, "slider_track_9s")
    B.register("MNU-09", p, w_, h_, "MVP", "9slice", note="thin track plus a bright fill, no thumb")
    B.save(buf.to_image(), p)
    n += 1

    # ------------------------------------------------------ MNU-18 font bitmap set
    # EMPTY stencil cells.  Canon: no baked text anywhere, including numerals,
    # and this row is explicitly licence-clean.  The runtime font draws here.
    cols, rows_ = 8, 8
    cs2 = 64
    buf = P.Buffer(cols * cs2, rows_ * cs2)
    for i in range(cols * rows_):
        cx, cy = (i % cols) * cs2 + cs2 / 2, (i // cols) * cs2 + cs2 / 2
        cell = S.rect(rows_ * cs2, cols * cs2, cx - cs2 * 0.32, cy - cs2 * 0.36,
                      cx + cs2 * 0.32, cy + cs2 * 0.36, r=cs2 * 0.10)
        buf.composite(Flesh.UI_EDGE, cell * 0.22)
        buf.composite(Flesh.OUTLINE, S.outline(cell, 1.6) * 0.55)
    p = B.fname(MNU, "font_bitmap_atlas_512x512")
    B.register("MNU-18", p, cols * cs2, rows_ * cs2, "MVP", "atlas", frames=cols * rows_,
               note="EMPTY stencil cells, deliberately: no baked glyphs, font-rendered at runtime")
    B.save(buf.to_image(), p, grade=False)
    n += 1

    print(f"MNU MVP: {n} files")
    print(B.write_manifest("manifest_mnu.json"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
