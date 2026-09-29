"""CMP: compass and canary navigation, MVP rows.

MVP scope: CMP-01..04, CMP-09..11, CMP-14.

The canary is the second navigation channel and its exact function is undecided,
so its art has to carry state without implying a mechanic: three portraits that
read as calm / alert / distressed, and a world sprite seen from behind and above.
Nothing here suggests a reward, a meter, or a number.

Rows: docs/asset-list.md section 5.
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
from fleshkit.palette import Flesh, Restroom, mix

HUD = "ui/hud"
PANEL = {"base": Flesh.UI_PANEL, "light": Flesh.UI_PANEL_LIGHT, "dark": Flesh.UI_EDGE}
Y = Flesh.nerve_base()      # canary yellow: the same loud family as the nerve icon
Y_LIGHT = Flesh.nerve_light()
Y_DEEP = "#b8890a"


# --------------------------------------------------------------------------- canary
def canary_body(size, seed, *, state="idle", cx=0.5, cy=0.56, scale=1.0):
    """A small yellow bird.  Returns a dict of masks so callers can shade parts.

    ``state`` changes posture, not hue: idle is a smooth perched bird, alert has
    half-raised wings and a turned head, distress is puffed and dishevelled.
    """
    S_ = size
    sx, sy = cx * S_, cy * S_
    u = S_ * 0.30 * scale          # a body unit
    rng = np.random.default_rng(seed)
    out: dict[str, np.ndarray] = {}

    if state == "distress":
        u *= 1.16                  # puffed up
    body_rot = {"idle": -12, "alert": -18, "distress": 4}[state]
    out["body"] = S.ellipse(S_, S_, sx, sy, u * 0.78, u * 0.94, rot=body_rot)
    out["head"] = S.circle(S_, S_, sx - u * 0.52, sy - u * 0.86, u * 0.46)
    out["neck"] = S.capsule(S_, S_, sx - u * 0.30, sy - u * 0.40,
                            sx - u * 0.54, sy - u * 0.76, u * 0.30)
    out["beak"] = S.polygon(S_, S_, [(sx - u * 0.92, sy - u * 0.90),
                                     (sx - u * 1.34, sy - u * 0.80),
                                     (sx - u * 0.90, sy - u * 0.70)])
    out["tail"] = S.polygon(S_, S_, [(sx + u * 0.62, sy + u * 0.10),
                                     (sx + u * 1.46, sy + u * 0.46),
                                     (sx + u * 1.30, sy + u * 0.72),
                                     (sx + u * 0.58, sy + u * 0.56)])
    if state == "distress":
        # ragged, uneven tail
        out["tail"] = S.roughen(out["tail"], S.value_noise(S_, S_, S_ * 0.05, seed + 2, 3), 0.8, 1.4)

    # wings: smooth folded, half-raised, or splayed and ragged
    if state == "idle":
        out["wing"] = S.ellipse(S_, S_, sx + u * 0.02, sy + u * 0.04,
                                u * 0.46, u * 0.70, rot=body_rot + 12)
    elif state == "alert":
        out["wing"] = S.union(
            S.ellipse(S_, S_, sx - u * 0.10, sy - u * 0.30, u * 0.44, u * 0.58, rot=-34),
            S.ellipse(S_, S_, sx + u * 0.34, sy - u * 0.06, u * 0.40, u * 0.54, rot=20))
    else:
        out["wing"] = S.union(
            S.ellipse(S_, S_, sx - u * 0.16, sy - u * 0.34, u * 0.50, u * 0.62, rot=-52),
            S.ellipse(S_, S_, sx + u * 0.40, sy - u * 0.10, u * 0.46, u * 0.58, rot=26))
        out["wing"] = S.roughen(out["wing"], S.value_noise(S_, S_, S_ * 0.04, seed + 3, 3), 1.0, 1.3)

    out["legs"] = S.union(
        S.capsule(S_, S_, sx - u * 0.10, sy + u * 0.80, sx - u * 0.14, sy + u * 1.12, u * 0.055),
        S.capsule(S_, S_, sx + u * 0.20, sy + u * 0.80, sx + u * 0.24, sy + u * 1.12, u * 0.055))
    out["all"] = S.union(out["body"], out["head"], out["neck"], out["beak"],
                         out["tail"], out["wing"], out["legs"])
    return out


def canary_portrait(size, seed, state):
    """One canary portrait: yellow body, dark beak and eye, a brass perch."""
    buf = P.Buffer(size, size)
    m = canary_body(size, seed, state=state)
    rng = np.random.default_rng(seed)

    if state == "distress":
        # motion blur: a soft ghost offset behind the body
        buf.composite(Y, S.shift(m["all"], int(size * 0.018), 0) * 0.35)
        buf.composite(Y_DEEP, S.shift(m["all"], -int(size * 0.020), 0) * 0.30)

    buf.composite(P.shade_fill(m["body"], Y, Y_LIGHT, Y_DEEP, size * 0.045), m["body"])
    buf.composite(P.shade_fill(m["head"], Y, Y_LIGHT, Y_DEEP, size * 0.038), m["head"])
    buf.composite(P.shade_fill(m["neck"], Y, Y_LIGHT, Y_DEEP, size * 0.030), m["neck"])
    buf.composite(P.shade_fill(m["tail"], mix(Y, Y_DEEP, 0.4), Y, Y_DEEP, size * 0.030), m["tail"])
    buf.composite(P.shade_fill(m["wing"], mix(Y, Y_DEEP, 0.25), Y_LIGHT, Y_DEEP, size * 0.030),
                  m["wing"])
    # feather grain, ragged only in distress
    fm = P.fibres(size, size, seed, -20.0, 90, size * 0.008, size * 0.10)
    buf.composite(Y_DEEP, fm * m["all"] * (0.9 if state == "distress" else 0.35))
    # wet highlight: a thin edge only.  A broad bright term on a round body
    # wraps the silhouette in a light halo, which is the cartoon tell.
    buf.composite("#fff4c0", P.specular(m["all"], size * 0.022, 0.74) * 0.30)
    # beak, feet
    beak = S.subtract(m["beak"], m["head"])
    buf.composite(P.shade_fill(beak, Flesh.BRASS, Flesh.BRASS_LIGHT, Flesh.RUST_DARK,
                               size * 0.014), beak)
    buf.composite(P.shade_fill(m["legs"], Flesh.BRASS, Flesh.BRASS_LIGHT, Flesh.RUST_DARK,
                               size * 0.010), m["legs"])
    # eye: wide when alert or distressed
    u = size * 0.30
    ex = size * 0.5 - u * 0.52 - u * 0.10
    ey = size * 0.56 - u * 0.86 - u * 0.04
    er = size * (0.052 if state == "idle" else 0.066)
    eye = S.circle(size, size, ex, ey, er)
    buf.composite("#1a0b0d", eye)
    buf.composite("#ffffff", S.circle(size, size, ex - er * 0.30, ey - er * 0.32, er * 0.34))
    # alert and distress get a small shock ring, the loudest cue in the set
    if state in ("alert", "distress"):
        ring = S.ring(size, size, ex, ey, er * 2.1, er * 1.7)
        buf.composite(Flesh.nerve_glow(), ring * (0.9 if state == "alert" else 0.6))

    # No hard outer contour: a drawn keyline makes the bird read as a cartoon
    # sticker.  Form comes from the feather shading and a soft dark edge instead.
    fall = S.blur(m["all"], size * 0.010) - S.blur(m["all"], size * 0.024)
    buf.composite(mix(Y_DEEP, "#000000", 0.4), np.clip(fall, 0, 1) * 0.80)
    halo = np.clip(S.dilate(m["all"], size * 0.006) - m["all"], 0, 1)
    halo = S.roughen(halo, S.value_noise(size, size, size * 0.05, seed + 21, 3), 0.9, 1.0)
    buf.composite(mix(Y_DEEP, "#000000", 0.55), halo * 0.45)
    # feather separation strokes, clipped to the wing: short lines fanning out
    # from the shoulder.  (Arcs about the wing centroid produced large rings
    # across the head, which read as a halo rather than as feathering.)
    wx, wy = S.centroid(m["wing"])
    for i in range(4):
        a0 = math.radians(150.0 + i * 26.0)
        for j in range(3):
            r0 = size * (0.10 + j * 0.06)
            r1 = r0 + size * 0.05
            st = S.capsule(size, size, wx + math.cos(a0) * r0, wy + math.sin(a0) * r0,
                           wx + math.cos(a0 + 0.35) * r1, wy + math.sin(a0 + 0.35) * r1,
                           size * 0.005)
            buf.composite(Y_DEEP, st * m["wing"] * 0.55)

    # brass perch
    perch = S.rect(size, size, size * 0.20, size * 0.855, size * 0.80, size * 0.895, r=size * 0.02)
    buf.composite(P.shade_fill(perch, Flesh.BRASS, Flesh.BRASS_LIGHT, Flesh.RUST_DARK,
                               size * 0.020), perch)
    buf.composite(Flesh.OUTLINE, S.outline(perch, size * 0.010))
    return buf.to_image()


def canary_sprite(size, seed, frame, frames=6):
    """CMP-14: the canary in the 3D world, seen from behind and above, wing cycle."""
    buf = P.Buffer(size, size)
    t = frame / frames
    sx, sy = size * 0.50, size * 0.56
    u = size * 0.26
    # back view: no beak, tail toward the viewer, wings mid-beat
    body = S.ellipse(size, size, sx, sy, u * 0.70, u * 0.86, rot=-6)
    head = S.circle(size, size, sx - u * 0.10, sy - u * 0.80, u * 0.44)
    tail = S.polygon(size, size, [(sx - u * 0.30, sy + u * 0.50),
                                 (sx + u * 0.30, sy + u * 0.50),
                                 (sx + u * 0.20, sy + u * 1.30),
                                 (sx - u * 0.20, sy + u * 1.30)])
    a = math.sin(t * 2 * math.pi)
    lift = abs(a) * u * 0.55
    wl = S.ellipse(size, size, sx - u * 0.72, sy - lift * 0.5, u * 0.30, u * 0.62, rot=-40 - a * 26)
    wr = S.ellipse(size, size, sx + u * 0.72, sy - lift * 0.5, u * 0.30, u * 0.62, rot=40 + a * 26)
    m = S.union(body, head, tail, wl, wr)
    buf.composite(P.shade_fill(m, mix(Y, Y_DEEP, 0.15), Y_LIGHT, Y_DEEP, size * 0.045), m)
    # the upper surfaces catch more light: this is a top-down bird
    buf.composite(Y_LIGHT, S.dilate(m, size * 0.020) - m * 0.0)
    buf.composite(Y_DEEP, P.fibres(size, size, seed, 96.0, 60, size * 0.007, size * 0.08) * m * 0.35)
    # darker flight feathers on the wings
    buf.composite(Y_DEEP, (wl + wr) * 0.45)
    buf.composite(Flesh.nerve_keyline(), S.outline(m, max(1.5, size * 0.022)))
    # small eye hints, top-down
    for ex in (sx - u * 0.20, sx + u * 0.02):
        buf.composite("#1a0b0d", S.circle(size, size, ex, sy - u * 0.86, size * 0.016))
    return buf.to_image()


# --------------------------------------------------------------------------- compass
def compass_rose(size, seed):
    """CMP-02: 12 major degree marks, worn, no letters."""
    buf = P.Buffer(size, size)
    c = size / 2
    disc = S.circle(size, size, c, c, size * 0.44)
    buf.composite(P.shade_fill(disc, "#d8cbb0", "#f0e6cf", "#9c8f76", size * 0.03), disc)
    buf.composite(Flesh.GRIME, P.grime(size, size, seed, 0.42) * disc * 0.5)
    marks = np.zeros((size, size), dtype=np.float32)
    for i in range(12):
        a = math.radians(i * 30.0 - 90.0)
        ca, sa = math.cos(a), math.sin(a)
        long_ = (i % 3 == 0)
        r0 = size * (0.30 if long_ else 0.35)
        r1 = size * 0.425
        marks = np.maximum(marks, S.capsule(size, size, c + ca * r0, c + sa * r0,
                                            c + ca * r1, c + sa * r1,
                                            size * (0.014 if long_ else 0.008)))
    # minor ticks between the majors
    for i in range(60):
        a = math.radians(i * 6.0 - 90.0)
        ca, sa = math.cos(a), math.sin(a)
        marks = np.maximum(marks, S.capsule(size, size, c + ca * size * 0.40,
                                            c + sa * size * 0.40,
                                            c + ca * size * 0.425, c + sa * size * 0.425,
                                            size * 0.004))
    buf.composite(P.shade_fill(marks, "#4a4034", "#6b5c4a", "#241d16", size * 0.010), marks)
    buf.composite(Flesh.OUTLINE, S.outline(disc, size * 0.012) * 0.9)
    return buf.to_image(), disc


def main() -> int:
    n = 0
    S_ = 512

    # ------------------------------------------------------------- CMP-01 frame
    buf = P.Buffer(S_, S_)
    c = S_ / 2
    rim_o = S.circle(S_, S_, c, c, S_ * 0.47)
    rim_i = S.circle(S_, S_, c, c, S_ * 0.40)
    rim = np.clip(rim_o - rim_i, 0, 1)
    buf.composite(P.shade_fill(rim, Flesh.BRASS, Flesh.BRASS_LIGHT, Flesh.RUST_DARK,
                               S_ * 0.020), rim)
    # bone inlay segments around the bezel
    inlay = np.zeros((S_, S_), dtype=np.float32)
    for i in range(8):
        a0, a1 = i * 45.0 + 6.0, i * 45.0 + 39.0
        inlay = np.maximum(inlay, S.ring(S_, S_, c, c, S_ * 0.465, S_ * 0.405, a0, a1))
    buf.composite(P.shade_fill(inlay, Flesh.BONE, "#ffffff", Flesh.BONE_SHADE, S_ * 0.012), inlay)
    buf.composite(Flesh.RUST, P.grime(S_, S_, 1, 0.40) * rim * 0.6)
    buf.composite(Flesh.OUTLINE, S.outline(rim_o, S_ * 0.010))
    # cracked glass: a hairline web across the upper-left quadrant
    crack = np.zeros((S_, S_), dtype=np.float32)
    rng = np.random.default_rng(2)
    for _ in range(5):
        x, y = c - S_ * 0.30, c - S_ * 0.28
        for _ in range(4):
            a = rng.random() * 2 * math.pi
            x2, y2 = x + math.cos(a) * S_ * 0.07, y + math.sin(a) * S_ * 0.07
            crack = np.maximum(crack, S.capsule(S_, S_, x, y, x2, y2, S_ * 0.0035))
            x, y = x2, y2
    buf.composite("#ffffff", crack * 0.35)
    p = B.fname(HUD, "cmp", "compass", "frame_9s")
    B.register("CMP-01", p, S_, S_, "MVP", "9slice", note="brass rim, bone inlay, cracked glass, 9-slice 48/416/48")
    B.save(buf.to_image(), p)
    n += 1

    # ------------------------------------------------------------- CMP-02 rose face
    seed = B.seed_of("CMP-02")
    img, _disc = compass_rose(S_, seed)
    p = B.fname(HUD, "cmp", "compass", "rose_face_512x512")
    B.register("CMP-02", p, S_, S_, "MVP", note="12 major degree marks, no baked letters")
    B.save(img, p)
    n += 1

    # ------------------------------------------------------------- CMP-03/04 needles
    for aid, col, light, dark, name in (
        ("CMP-03", Flesh.IRON, Flesh.IRON_LIGHT, "#1e1c1c", "north_needle_128x256"),
        ("CMP-04", "#f4f7f6", "#ffffff", Restroom.CERAMIC_SHADE, "restroom_needle_128x256"),
    ):
        buf = P.Buffer(128, 256)
        m = S.polygon(256, 128, [(64, 14), (78, 120), (64, 132), (50, 120)])
        buf.composite(P.shade_fill(m, col, light, dark, 14.0), m)
        buf.composite(Flesh.OUTLINE if aid == "CMP-03" else Restroom.ENAMEL_EDGE, S.outline(m, 3.0))
        # the pale tip that makes north readable at a glance
        tip = S.polygon(256, 128, [(64, 14), (70, 60), (58, 60)])
        buf.composite("#ffffff" if aid == "CMP-04" else Flesh.BONE, tip)
        hub = S.circle(256, 128, 64, 124, 12)
        buf.composite(P.shade_fill(hub, Flesh.BRASS, Flesh.BRASS_LIGHT, Flesh.RUST_DARK, 5.0), hub)
        p = B.fname(HUD, "cmp", "compass", name)
        B.register(aid, p, 128, 256, "MVP",
                   note="standard heading" if aid == "CMP-03"
                   else "clean white, visually distinct from north: the goal is the toilet")
        B.save(buf.to_image(), p)
        n += 1

    # ------------------------------------------------------------- CMP-09 cage frame
    buf = P.Buffer(256, 256)
    outer = S.circle(256, 256, 128, 128, 116)
    inner = S.circle(256, 256, 128, 128, 100)
    dome = np.clip(outer - inner, 0, 1)
    buf.composite(P.shade_fill(dome, Flesh.BRASS, Flesh.BRASS_LIGHT, Flesh.RUST_DARK,
                               12.0), dome)
    bars = np.zeros((256, 256), dtype=np.float32)
    for i in range(-3, 4):
        x = 128 + i * 34
        bars = np.maximum(bars, S.capsule(256, 256, x, 128 - 100, x, 128 + 100, 5.0))
    for y in (60, 92, 164, 196):
        bars = np.maximum(bars, S.capsule(256, 256, 128 - 100, y, 128 + 100, y, 5.0))
    bars = np.maximum(bars, S.arc_stroke(256, 256, 128, 128, 74, 5.0, 180, 360))
    buf.composite(P.shade_fill(bars, Flesh.BRASS_LIGHT, "#ffe08a", Flesh.RUST, 6.0), bars)
    buf.composite(Flesh.OUTLINE, S.outline(outer, 4.0))
    p = B.fname(HUD, "cmp", "canary", "cage_frame_9s")
    B.register("CMP-09", p, 256, 256, "MVP", "9slice", note="domed brass cage, 9-slice 32/192/32")
    B.save(buf.to_image(), p)
    n += 1

    # ------------------------------------------------------------- CMP-10/11/12 portraits
    for aid, state, pri, label in (
        ("CMP-10", "idle", "MVP", "calm yellow bird on a perch"),
        ("CMP-11", "alert", "MVP", "wings half-raised, head turned, eye wide"),
        ("CMP-12", "distress", "P1", "motion-blurred, dishevelled, feathers puffed"),
    ):
        img = canary_portrait(256, B.seed_of(aid), state)
        p = B.fname(HUD, "cmp", "canary", f"{state}_portrait_256x256")
        B.register(aid, p, 256, 256, pri, note=label)
        B.save(img, p)
        n += 1

    # ------------------------------------------------------------- CMP-14 world sprite
    frames = [canary_sprite(256, B.seed_of("CMP-14"), i, 6) for i in range(6)]
    p = B.fname(HUD, "cmp", "canary", "world_sprite_6f_256x256")
    B.register("CMP-14", p, 1536, 256, "MVP", "flipbook", frames=6, fps=12.0,
               note="seen from behind and above, 6-frame wing cycle")
    B.save_flipbook(frames, p)
    n += 1

    print(f"CMP MVP: {n} files")
    print(B.write_manifest("manifest_cmp.json"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
