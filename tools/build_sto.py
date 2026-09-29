"""STO: stomach and fullness UI, STO-01 to STO-18.

Canon: the stomach gauge is the most-read element in the game.  It is a
decision boundary, not a punishment, so the three fill layers must be readable
as escalating pressure at a glance, and the overflow state must be unmistakably
a consequence rather than a damage state.

Rows: docs/asset-list.md section 2.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

from fleshkit import build as B
from fleshkit import paint as P
from fleshkit import shapes as S
from fleshkit import widgets as W
from fleshkit.palette import Flesh, Restroom, mix, ramp

HUD = "ui/hud"
PANEL = {"base": Flesh.UI_PANEL, "light": Flesh.UI_PANEL_LIGHT, "dark": Flesh.UI_EDGE}
# the stomach silhouette: a soft irregular sac, 512x256
SAC = [(0.16, 0.30), (0.30, 0.16), (0.52, 0.12), (0.74, 0.18), (0.86, 0.34),
       (0.88, 0.56), (0.78, 0.78), (0.58, 0.88), (0.36, 0.84), (0.20, 0.66)]


def _sac_mask(w: int, h: int, shrink: float = 1.0) -> np.ndarray:
    """A soft irregular stomach silhouette.

    Built from overlapping lobes and blurred rather than from a point list: a
    straight-edged polygon reads as a stone, and this shape is the frame the
    player looks at more than any other in the game.
    """
    lobes = [(0.30, 0.34, 0.20), (0.48, 0.24, 0.22), (0.66, 0.32, 0.20),
             (0.76, 0.52, 0.19), (0.66, 0.74, 0.20), (0.46, 0.80, 0.22),
             (0.28, 0.70, 0.19), (0.22, 0.50, 0.18)]
    m = np.zeros((h, w), dtype=np.float32)
    for x, y, r in lobes:
        m = np.maximum(m, S.ellipse(h, w, w * x, h * y,
                                    w * r * 1.15 * shrink, h * r * 1.30 * shrink))
    m = S.blur(m, max(2.0, w * 0.018))
    m = np.clip((m - 0.42) * 2.4, 0.0, 1.0)
    return m


def main() -> int:
    n = 0
    W_, H_ = 512, 256

    # ---------------------------------------------------------------- STO-01 frame
    buf = P.Buffer(W_, H_)
    body = _sac_mask(W_, H_, 1.0)
    outer = S.dilate(body, W_ * 0.030)
    # organic ribbed bezel
    rib = P.fibres(H_, W_, 11, 0.0, 90, W_ * 0.012, W_ * 0.10) * outer
    buf.composite(P.shade_fill(outer, Flesh.BLOOD, Flesh.MUSCLE_LIGHT, Flesh.SHADOW,
                               W_ * 0.020), outer)
    buf.composite(Flesh.BLOOD_DARK, rib * 0.55)
    buf.composite(Flesh.BLOOD_DARK, P.form_crescent(outer, W_ * 0.020) * 0.6)
    # wet highlight along the top edge
    top = np.clip(outer - S.shift(outer, 0, int(W_ * 0.018)), 0, 1)
    buf.composite(Flesh.SKIN_WET, top * 0.75)
    buf.composite(Flesh.OUTLINE, S.outline(outer, W_ * 0.010))
    B.register("STO-01", B.fname(HUD, "sto", "gauge", "frame_9s"), W_, H_, "MVP",
               "9slice", note="9-slice 32/224/32, transparent centre hole")
    B.save(buf.to_image(), B.fname(HUD, "sto", "gauge", "frame_9s"))
    n += 1

    # ---------------------------------------------------------------- STO-02 inner mask
    buf = P.Buffer(W_, H_)
    inner = _sac_mask(W_, H_, 0.90)
    buf.composite("#ffffff", inner)
    B.register("STO-02", B.fname(HUD, "sto", "gauge", "inner_mask"), W_, H_, "MVP",
               "png32", note="soft blob mask, clips the fill layers")
    B.save(buf.to_image(), B.fname(HUD, "sto", "gauge", "inner_mask"), grade=False)
    n += 1

    # ---------------------------------------------------------------- STO-03..05 fills
    # three escalating pressure states, Y-tileable, 256x256
    fills = [
        ("03", "fill_1_0to33", Flesh.SKIN_PINK, Flesh.SKIN_WET, Flesh.SKIN_PINK_DARK, 0.20, "MVP"),
        ("04", "fill_2_34to66", "#b04a45", "#c4674f", "#6d2827", 0.42, "MVP"),
        ("05", "fill_3_67to99", Flesh.CONGESTED, "#7e1620", "#2e050b", 0.62, "MVP"),
    ]
    for num, name, base, light, dark, lumps, pri in fills:
        S_ = 256
        buf = P.Buffer(S_, S_)
        m = np.ones((S_, S_), dtype=np.float32)
        # vertical fibre grain, tileable in Y
        fib = P.fibres(S_, S_, int(num) * 7 + 3, 90.0, 130, S_ * 0.010, S_ * 0.16)
        buf.composite(P.shade_fill(m, base, light, dark, S_ * 0.05), m)
        buf.composite(dark, fib * 0.30)
        buf.composite(mix(base, "#000000", 0.35),
                      P.striation(S_, S_, int(num) + 2, angle=90, thickness=S_ * 0.05) * 0.25)
        # visible lumps as fullness rises
        if lumps > 0.2:
            rng = np.random.default_rng(int(num) * 31)
            for _ in range(int(8 * lumps * 4)):
                cx, cy = rng.random() * S_, rng.random() * S_
                r = S_ * (0.04 + rng.random() * 0.07) * (0.6 + lumps)
                lm = S.circle(S_, S_, cx, cy, r)
                buf.composite(P.shade_fill(lm, light, mix(light, "#ffffff", 0.3), dark, r * 0.5), lm)
                buf.composite(dark, S.outline(lm, S_ * 0.006) * 0.5)
        # oil sheen / sweat, stronger as it fills
        buf.composite("#ffffff", P.wet_sheen(S_, S_, int(num) * 13, 0.16 + lumps * 0.2) * 0.6)
        if lumps > 0.5:
            vw = P.vein_web(S_, S_, int(num) * 5, count=8, width=S_ * 0.006, scale=0.7)
            buf.composite(Flesh.BLOOD_DARK, vw * 0.5)
        B.register(f"STO-{num}", B.fname(HUD, "sto", name, "256x256"), S_, S_, pri,
                   "png32", note="tileable Y")
        B.save(buf.to_image(), B.fname(HUD, "sto", name, "256x256"))
        n += 1

    # ---------------------------------------------------------------- STO-06 overflow
    buf = P.Buffer(W_, H_)
    body = _sac_mask(W_, H_, 1.0)
    bulge = S.dilate(body, W_ * 0.055)
    buf.composite(P.shade_fill(bulge, Flesh.CONGESTED, "#a02026", "#2c0509", W_ * 0.024), bulge)
    # split seams: short ragged tears, not full-height bars
    for i in range(5):
        x = W_ * (0.24 + 0.13 * i)
        y0 = H_ * (0.24 + 0.09 * (i % 3))
        y1 = y0 + H_ * (0.15 + 0.05 * (i % 2))
        seam = S.capsule(H_, W_, x, y0, x + W_ * 0.028, y1, W_ * 0.007)
        seam = S.subtract(seam, S.ellipse(H_, W_, x + W_ * 0.016, (y0 + y1) * 0.5,
                                           W_ * 0.010, H_ * 0.028))
        buf.composite(Flesh.SEAM_SPLIT, seam)
        buf.composite(Flesh.SKIN_WET, S.shift(seam, 0, 3) * 0.30)
    # cold blue vein overlay
    vw = P.vein_web(H_, W_, 91, count=12, width=W_ * 0.007, scale=0.9) * body
    buf.composite(Flesh.COLD_VEIN, vw * 0.75)
    buf.composite(Flesh.COLD_VEIN_LIGHT, P.vein_web(H_, W_, 92, count=12, width=W_ * 0.003) * body * 0.4)
    # rim glow
    rim = S.outline(bulge, W_ * 0.014)
    buf.composite(Flesh.COLD_VEIN_LIGHT, rim * 0.7)
    buf.composite(Flesh.OUTLINE, S.outline(bulge, W_ * 0.008))
    B.register("STO-06", B.fname(HUD, "sto", "overflow_state_9s"), W_, H_, "P1", "9slice",
               note="force-fed bulge, split seams, cold veins, rim glow")
    B.save(buf.to_image(), B.fname(HUD, "sto", "overflow_state_9s"))
    n += 1

    # ---------------------------------------------------------------- STO-07 capacity ticks
    buf = P.Buffer(128, 64)
    ticks = np.zeros((64, 128), dtype=np.float32)
    for i in range(8):
        x = 8 + i * 16
        ln = 34 if i % 2 == 0 else 20
        ticks = np.maximum(ticks, S.capsule(64, 128, x, 16, x, 16 + ln, 3.0))
    buf.composite(P.shade_fill(ticks, Flesh.BONE, "#ffffff", Flesh.BONE_SHADE, 6.0), ticks)
    buf.composite(Flesh.OUTLINE, S.outline(ticks, 1.6) * 0.8)
    B.register("STO-07", B.fname(HUD, "sto", "capacity_ticks_128x64"), 128, 64, "P1",
               note="8 notches, one per mutation stage")
    B.save(buf.to_image(), B.fname(HUD, "sto", "capacity_ticks_128x64"))
    n += 1

    # ---------------------------------------------------------------- STO-08 greedy rim
    buf = P.Buffer(W_, H_)
    body = _sac_mask(W_, H_, 1.0)
    outer = S.dilate(body, W_ * 0.030)
    rim = S.dilate(outer, W_ * 0.022) - outer
    buf.composite(P.shade_fill(rim, Flesh.GOLD_RIM, Flesh.GOLD_RIM_LIGHT,
                               Flesh.MOULD, W_ * 0.010), rim)
    buf.composite("#fff8d0", S.dilate(rim, W_ * 0.004) - rim * 0.0)
    B.register("STO-08", B.fname(HUD, "sto", "greedy_pulse_rim_9s"), W_, H_, "P1", "9slice",
               note="pulsing gold rim, 1.4 Hz")
    B.save(buf.to_image(), B.fname(HUD, "sto", "greedy_pulse_rim_9s"))
    n += 1

    # ---------------------------------------------------------------- STO-09 nausea vignette
    S_ = 1024
    v, col = W.vignette_overlay(S_, bile=True, strength=0.85, falloff=1.1)
    a = np.zeros((S_, S_), dtype=np.float32)
    yy, xx = S.grid(S_, S_)
    d = np.sqrt(((xx / S_) - .5) ** 2 + ((yy / S_) - .5) ** 2) / .7071
    a = np.clip((d - 0.30) / 0.70, 0, 1) ** 1.6 * 0.9
    img = P.Buffer(S_, S_)
    img.composite(Flesh.NAUSEA, a)
    img.composite(Flesh.BILE_LIGHT, np.clip((d - 0.55) / 0.45, 0, 1) ** 2.2 * 0.35)
    B.register("STO-09", B.fname(HUD, "sto", "nausea_vignette_1024x1024"), S_, S_, "MVP",
               note="bile-green corner bleed, transparent centre")
    B.save(img.to_image(), B.fname(HUD, "sto", "nausea_vignette_1024x1024"))
    n += 1

    # ---------------------------------------------------------------- STO-10 slosh mask
    frames = []
    for k in range(2):
        buf = P.Buffer(256, 256)
        yy, xx = S.grid(256, 256)
        phase = k * math.pi
        m = np.zeros((256, 256), dtype=np.float32)
        for i in range(7):
            t = i / 6.0
            x = 20 + t * 216
            y = 40 + math.sin(t * 3.4 + phase) * 26 + 90
            m = np.maximum(m, S.capsule(256, 256, x, y - 30, x, y + 30, 7.0))
        m = S.blur(m, 3.0)
        buf.composite("#ffffff", m)
        frames.append(buf.to_image())
    B.register("STO-10", B.fname(HUD, "sto", "slosh_distortion_mask_256x256x2"), 512, 256,
               "P1", "flipbook", frames=2, fps=2.0, note="two-frame vertical wobble")
    B.save_flipbook(frames, B.fname(HUD, "sto", "slosh_distortion_mask_256x256x2"))
    n += 1

    # ---------------------------------------------------------------- STO-11 digest ring
    buf = P.Buffer(256, 256)
    W.gauge_ring(buf, 256, 128, 128, 92, 18, 0.0, base=Flesh.UI_EDGE, fill=Flesh.SKIN_WET,
                 ticks=Flesh.BONE, tick_count=10, tick_len=10)
    W.gauge_ring(buf, 256, 128, 128, 92, 18, 0.62, base=None, fill=None)
    rim = S.ring(256, 256, 128, 128, 104, 98)
    buf.composite(Flesh.OUTLINE, rim * 0.8)
    B.register("STO-11", B.fname(HUD, "sto", "digest_ring_9s"), 256, 256, "P1", "9slice",
               note="clockwise wipe, ticks every 10%")
    B.save(buf.to_image(), B.fname(HUD, "sto", "digest_ring_9s"))
    n += 1

    # ---------------------------------------------------------------- STO-12 empty silhouette
    buf = P.Buffer(256, 256)
    body = S.blob(256, 256, 128, 132, 86, 17, lobes=4, rough=0.16, squash=0.78)
    wr = np.zeros((256, 256), dtype=np.float32)
    rng = np.random.default_rng(4)
    for _ in range(9):
        a = rng.random() * 2 * math.pi
        r0 = 40 + rng.random() * 30
        x, y = 128 + math.cos(a) * r0, 132 + math.sin(a) * r0 * 0.8
        wr = np.maximum(wr, S.capsule(256, 256, x, y,
                                       128 + math.cos(a + 0.5) * 40, 132 + math.sin(a + 0.5) * 32, 3.0))
    buf.composite(Flesh.BLOOD_DARK, body * 0.55)
    buf.composite(Flesh.SHADOW, wr * 0.7)
    buf.composite(Flesh.OUTLINE, S.outline(body, 3.0) * 0.5)
    B.register("STO-12", B.fname(HUD, "sto", "empty_silhouette_256x256"), 256, 256, "P1",
               note="contracted wrinkled hollow, dim")
    B.save(buf.to_image(), B.fname(HUD, "sto", "empty_silhouette_256x256"))
    n += 1

    # ---------------------------------------------------------------- STO-13 full block icon
    buf = P.Buffer(128, 128)
    belly = S.blob(128, 128, 64, 76, 34, 23, lobes=3, rough=0.10, squash=0.86)
    buf.composite(P.shade_fill(belly, Flesh.SKIN_PINK, Flesh.SKIN_WET,
                               Flesh.SKIN_PINK_DARK, 12.0), belly)
    buf.composite(Flesh.OUTLINE, S.outline(belly, 3.0))
    # crossed-out jaw
    jaw = S.union(S.capsule(128, 128, 34, 34, 58, 44, 6.0),
                  S.capsule(128, 128, 58, 44, 92, 34, 6.0))
    teeth = np.zeros((128, 128), dtype=np.float32)
    for i in range(6):
        x = 40 + i * 11
        teeth = np.maximum(teeth, S.polygon(128, 128, [(x, 30), (x + 8, 30), (x + 4, 42)]))
    jawm = S.union(jaw, teeth)
    buf.composite(Flesh.BONE, jawm)
    buf.composite(Flesh.OUTLINE, S.outline(jawm, 2.5))
    bar1 = S.capsule(128, 128, 20, 96, 108, 22, 7.0)
    buf.composite(Flesh.BLOOD_DARK, bar1)
    buf.composite(Flesh.SKIN_PINK, S.shift(bar1, 0, 3) * 0.35)
    B.register("STO-13", B.fname(HUD, "sto", "full_block_icon_128x128"), 128, 128, "P1",
               note="crossed-out jaw over a swelling belly")
    B.save(buf.to_image(), B.fname(HUD, "sto", "full_block_icon_128x128"))
    n += 1

    # ---------------------------------------------------------------- STO-14 toilet bowl gauge
    buf = P.Buffer(W_, H_)
    rim = S.ellipse(H_, W_, W_ / 2, H_ * 0.42, W_ * 0.42, H_ * 0.34)
    buf.composite(P.shade_fill(rim, Restroom.CERAMIC, "#ffffff", Restroom.CERAMIC_SHADE,
                               W_ * 0.02), rim)
    bowl = S.ellipse(H_, W_, W_ / 2, H_ * 0.44, W_ * 0.33, H_ * 0.25)
    buf.composite(P.shade_fill(bowl, Restroom.CERAMIC_SHADE, Restroom.WATER,
                               Restroom.GROUT, W_ * 0.015), bowl)
    chew = S.ellipse(H_, W_, W_ / 2, H_ * 0.50, W_ * 0.28, H_ * 0.17)
    buf.composite(P.shade_fill(chew, Flesh.SKIN_PINK, Flesh.SKIN_WET,
                               Flesh.SKIN_PINK_DARK, W_ * 0.012), chew)
    buf.composite(Flesh.OUTLINE, S.outline(rim, W_ * 0.006))
    buf.composite(Restroom.ENAMEL_EDGE, S.outline(rim, W_ * 0.006) * 0.4)
    ped = S.polygon(H_, W_, [(W_ * 0.38, H_ * 0.70), (W_ * 0.62, H_ * 0.70),
                             (W_ * 0.58, H_ * 0.96), (W_ * 0.42, H_ * 0.96)])
    buf.composite(P.shade_fill(ped, Restroom.CERAMIC, "#ffffff", Restroom.CERAMIC_SHADE,
                               W_ * 0.015), ped)
    buf.composite(Restroom.ENAMEL_EDGE, S.outline(ped, W_ * 0.005) * 0.7)
    B.register("STO-14", B.fname(HUD, "sto", "toilet_bowl_gauge_9s"), W_, H_, "MVP", "9slice",
               note="white ceramic bowl cross-section, restrom-only")
    B.save(buf.to_image(), B.fname(HUD, "sto", "toilet_bowl_gauge_9s"))
    n += 1

    # ---------------------------------------------------------------- STO-15 vomit stream fill
    S_ = 256
    buf = P.Buffer(S_, S_)
    m = np.ones((S_, S_), dtype=np.float32)
    buf.composite(P.shade_fill(m, "#d8b3a8", "#f0d8cc", "#8e6a60", S_ * 0.04), m)
    rng = np.random.default_rng(15)
    for _ in range(70):
        x, y = rng.random() * S_, rng.random() * S_
        r = S_ * (0.012 + rng.random() * 0.030)
        c = S.circle(S_, S_, x, y, r)
        col = Flesh.BLOOD if rng.random() < 0.28 else ("#e6cdc2" if rng.random() < 0.6 else "#a07a70")
        buf.composite(col, c * 0.85)
        buf.composite(mix(col, "#000000", 0.3), S.outline(c, S_ * 0.004) * 0.5)
    buf.composite("#ffffff", P.wet_sheen(S_, S_, 15, 0.22) * 0.5)
    B.register("STO-15", B.fname(HUD, "sto", "vomit_stream_fill_256x256"), S_, S_, "MVP",
               note="coarse chewed flesh, pale with red streaks, tileable Y")
    B.save(buf.to_image(), B.fname(HUD, "sto", "vomit_stream_fill_256x256"))
    n += 1

    # ---------------------------------------------------------------- STO-16 stage distortion x6
    for k in range(6):
        S_ = 256
        buf = P.Buffer(S_, S_)
        base = _sac_mask(S_, S_, 0.86)
        sil = base
        rng = np.random.default_rng(160 + k)
        # each stage alters the silhouette: sacs, cysts, scale patches
        for i in range(2 + k):
            a = rng.random() * 2 * math.pi
            d = rng.random() * 0.22 * S_
            r = S_ * (0.035 + rng.random() * 0.045) * (0.7 + k * 0.12)
            b = S.blob(S_, S_, S_ * 0.5 + math.cos(a) * d, S_ * 0.5 + math.sin(a) * d,
                       r, 300 + k * 7 + i, lobes=3, rough=0.12)
            sil = np.maximum(sil, b)
        pal = ramp([Flesh.SKIN_PINK, Flesh.BLOOD, Flesh.CONGESTED, Flesh.BLOOD_DARK],
                   np.full((1, 1), k / 5.0))[0, 0]
        buf.composite(pal, sil * 0.9)
        buf.composite(mix(pal, "#ffffff", 0.4), P.specular(sil, S_ * 0.05, 0.45) * 0.6)
        if k >= 3:  # scale patches
            for _ in range(14 * (k - 2)):
                x, y = rng.random() * S_, rng.random() * S_
                if sil[int(y), int(x)] < 0.4:
                    continue
                sc = S.circle(S_, S_, x, y, S_ * 0.022)
                buf.composite(Flesh.BONE, sc * 0.7)
                buf.composite(Flesh.BONE_SHADE, S.outline(sc, 1.4) * 0.6)
        buf.composite(Flesh.OUTLINE, S.outline(sil, S_ * 0.014) * 0.9)
        B.register(f"STO-16-{k + 1}", B.fname(HUD, "sto", "stage_distortion", f"stage{k + 1}_256x256"),
                   S_, S_, "P1", note=f"mutation stage {k + 1} organ silhouette")
        B.save(buf.to_image(), B.fname(HUD, "sto", "stage_distortion", f"stage{k + 1}_256x256"))
        n += 1

    # ---------------------------------------------------------------- STO-17 numerals atlas (EMPTY)
    # Canon: no baked text.  These are empty stencil cells for the font to sit in.
    cols, rows_ = 12, 2
    S_ = 128
    buf = P.Buffer(S_ * cols, S_ * rows_)
    for i in range(cols * rows_):
        cx = (i % cols) * S_ + S_ / 2
        cy = (i // cols) * S_ + S_ / 2
        cell = S.rect(S_ * rows_, S_ * cols, cx - S_ * 0.30, cy - S_ * 0.38,
                      cx + S_ * 0.30, cy + S_ * 0.38, r=S_ * 0.10)
        buf.composite(Flesh.UI_EDGE, cell * 0.30)
        buf.composite(Flesh.OUTLINE, S.outline(cell, 2.0) * 0.7)
    B.register("STO-17", B.fname(HUD, "sto", "fullness_numerals_atlas_256x128"), S_ * cols,
               S_ * rows_, "P1", "atlas", frames=cols * rows_,
               note="EMPTY stencil cells: no baked glyphs, font renders 0-9 and %")
    B.save(buf.to_image(), B.fname(HUD, "sto", "fullness_numerals_atlas_256x128"))
    n += 1

    # ---------------------------------------------------------------- STO-18 overfull tint
    S_ = 1024
    buf = P.Buffer(S_, S_)
    yy, xx = S.grid(S_, S_)
    d = np.clip(np.sqrt(((xx / S_) - .5) ** 2 + ((yy / S_) - .5) ** 2) / .7071, 0, 1)
    a = d ** 1.3 * 0.85
    buf.composite(Flesh.BLOOD, a)
    buf.composite(Flesh.CONGESTED, d ** 2.0 * 0.6)
    B.register("STO-18", B.fname(HUD, "sto", "overfull_tint_1024x1024"), S_, S_, "P2",
               note="deep red pulse, edges only")
    B.save(buf.to_image(), B.fname(HUD, "sto", "overfull_tint_1024x1024"))
    n += 1

    print(f"STO: {n} files")
    print(B.write_manifest("manifest_sto.json"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
