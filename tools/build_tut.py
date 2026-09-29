"""TUT: tutorial and onboarding prompts, MVP rows.

MVP scope: TUT-01 to TUT-08.

Canon: if the first interaction needs a tutorial panel, the design is too
complex.  So these are icon-only, outline-first, and every one teaches a verb
with a shape.  No text, no card chrome, no modal -- a ring, a chevron, an arrow.

TUT-08 is the exception the canon explicitly carves out: the nerve prompt is
"deliberately the loudest prompt in the set", because nerves must be recognised
before the player touches one.

Rows: docs/asset-list.md section 12.
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
from fleshkit.palette import Flesh, mix

PR = "ui/prompts"
PANEL = {"base": Flesh.UI_PANEL, "light": Flesh.UI_PANEL_LIGHT, "dark": Flesh.UI_EDGE}


def ring_prompt(size, color, *, width=None, inner=None, dash=0, gap=0):
    """An open ring, the core of the tutorial language: 'this, now'."""
    buf = P.Buffer(size, size)
    w = width if width is not None else size * 0.055
    c = size / 2
    m = S.ring(size, size, c, c, size * 0.40 + w / 2, size * 0.40 - w / 2)
    if inner is not None:
        buf.composite(inner, S.circle(size, size, c, c, size * 0.34))
    if dash > 0 and gap > 0:
        seg = np.zeros((size, size), dtype=np.float32)
        step = 360.0 / max(1, dash)
        for i in range(dash):
            seg = np.maximum(seg, S.arc_stroke(size, size, c, c, size * 0.40, w,
                                               i * step, i * step + step * 0.55))
        m = seg
    buf.composite(color, m)
    return buf.to_image()


def main() -> int:
    n = 0

    # ------------------------------------------------ TUT-01 first contact prompt
    # a hand-outline ring over the target tissue: shape, not a panel
    size = 256
    buf = P.Buffer(size, size)
    tissue = S.blob(size, size, size * 0.5, size * 0.5, size * 0.30,
                    B.seed_of("TUT-01"), lobes=4, rough=0.26)
    buf.composite(P.shade_fill(tissue, Flesh.MUSCLE, Flesh.MUSCLE_LIGHT,
                               Flesh.MUSCLE_DARK, size * 0.03), tissue)
    buf.composite(Flesh.BLOOD_DARK, P.form_crescent(tissue, size * 0.020) * 0.6)
    ring = S.ring(size, size, size / 2, size / 2, size * 0.44, size * 0.40)
    buf.composite(Flesh.BONE, ring)
    # the hand outline: a simple grip glyph inside the ring
    hand = S.capsule(size, size, size * 0.44, size * 0.44, size * 0.44, size * 0.62, size * 0.028)
    for i in range(3):
        hand = np.maximum(hand, S.capsule(size, size, size * (0.44 + i * 0.055),
                                          size * 0.50, size * (0.44 + i * 0.055),
                                          size * 0.40, size * 0.022))
    hand = np.maximum(hand, S.capsule(size, size, size * 0.36, size * 0.52,
                                      size * 0.60, size * 0.52, size * 0.026))
    buf.composite(Flesh.BONE, hand)
    p = B.fname(PR, "first_contact_prompt_256x256")
    B.register("TUT-01", p, size, size, "MVP", note="hand-outline ring over target tissue, icon only")
    B.save(buf.to_image(), p)
    n += 1

    # ------------------------------------------------ TUT-02 chew hold ring
    img = ring_prompt(256, Flesh.BONE, width=256 * 0.05, dash=10, gap=4)
    p = B.fname(PR, "chew_hold_ring_256x256")
    B.register("TUT-02", p, 256, 256, "MVP", note="circular progress ring around the held bite")
    B.save(img, p)
    n += 1

    # ------------------------------------------------ TUT-03 swallow prompt
    p = B.fname(PR, "swallow_prompt_128x128")
    B.register("TUT-03", p, 128, 128, "MVP", note="simple throat-down chevron")
    B.save(W.chevron_icon(128, Flesh.BONE, down=True, weight=18), p)
    n += 1

    # ------------------------------------------------ TUT-04 first full stomach prompt
    w_, h_ = 512, 256
    buf = P.Buffer(w_, h_)
    g = S.ellipse(h_, w_, w_ * 0.30, h_ * 0.5, w_ * 0.20, h_ * 0.32)
    ring = np.clip(S.outline(g, 7.0), 0, 1)
    buf.composite(Flesh.BONE, ring)
    # a hand pointing at the fill
    pt = S.capsule(h_, w_, w_ * 0.60, h_ * 0.5, w_ * 0.80, h_ * 0.5, 6.0)
    pt = np.maximum(pt, S.capsule(h_, w_, w_ * 0.78, h_ * 0.5, w_ * 0.86, h_ * 0.40, 6.0))
    buf.composite(Flesh.BONE, pt)
    p = B.fname(PR, "first_full_stomach_prompt_512x256")
    B.register("TUT-04", p, w_, h_, "MVP", note="gauge outline with a hand pointing at the fill")
    B.save(buf.to_image(), p)
    n += 1

    # ------------------------------------------------ TUT-05 return home hand-off
    w_, h_ = 512, 256
    buf = P.Buffer(w_, h_)
    c = S.arc_stroke(h_, w_, w_ * 0.42, h_ * 0.5, h_ * 0.32, 7.0, 0, 360)
    buf.composite(Flesh.BONE, c)
    buf.composite(Flesh.BONE, S.capsule(h_, w_, w_ * 0.42, h_ * 0.5, w_ * 0.42,
                                        h_ * 0.24, 5.0))
    arr = S.capsule(h_, w_, w_ * 0.42, h_ * 0.46, w_ * 0.42, h_ * 0.14, 6.0)
    arr = np.maximum(arr, S.chevron(h_, w_, w_ * 0.42, h_ * 0.16, 26, 6.0))
    # the arrow leaves the compass toward the surface
    leave = S.capsule(h_, w_, w_ * 0.56, h_ * 0.5, w_ * 0.80, h_ * 0.22, 6.0)
    leave = np.maximum(leave, S.chevron(h_, w_, w_ * 0.80, h_ * 0.24, 24, 6.0, angle=-38))
    buf.composite(Flesh.BONE, np.maximum(arr * 0.0, leave))
    p = B.fname(PR, "return_home_handoff_512x256")
    B.register("TUT-05", p, w_, h_, "MVP", note="compass outline with an arrow leaving it toward the surface")
    B.save(buf.to_image(), p)
    n += 1

    # ------------------------------------------------ TUT-06 first vomit prompt
    size = 256
    buf = P.Buffer(size, size)
    tank = S.rect(size, size, size * 0.30, size * 0.18, size * 0.60, size * 0.36, r=6)
    bowl = S.polygon(size, size, [(size * 0.26, size * 0.36), (size * 0.64, size * 0.36),
                                  (size * 0.56, size * 0.58), (size * 0.34, size * 0.58)])
    ped = S.rect(size, size, size * 0.42, size * 0.58, size * 0.48, size * 0.80, r=4)
    base = S.rect(size, size, size * 0.32, size * 0.80, size * 0.58, size * 0.86, r=4)
    body = S.union(tank, bowl, ped, base)
    buf.composite(Flesh.BONE, S.outline(body, 5.0))
    # arrow into the bowl
    ar = S.capsule(size, size, size * 0.45, size * 0.02, size * 0.45, size * 0.16, 5.0)
    ar = np.maximum(ar, S.chevron(size, size, size * 0.45, size * 0.18, 24, 5.0, down=True))
    buf.composite(Flesh.BONE, ar)
    p = B.fname(PR, "first_vomit_prompt_256x256")
    B.register("TUT-06", p, size, size, "MVP", note="toilet outline with an arrow into the bowl")
    B.save(buf.to_image(), p)
    n += 1

    # ------------------------------------------------ TUT-07 first mutation reveal card
    w_, h_ = 1024, 512
    buf = P.Buffer(w_, h_)
    body = W.card(buf, w_, h_, 46, PANEL, corner=60, seed=7)
    # a hand silhouette in the centre
    hx, hy = w_ * 0.5, h_ * 0.56
    hand = S.ellipse(h_, w_, hx, hy, 78, 66)
    for i in range(4):
        hand = np.maximum(hand, S.capsule(h_, w_, hx - 60 + i * 40, hy - 40,
                                          hx - 74 + i * 40, hy - 150 + i * 12, 15))
    hand = np.maximum(hand, S.capsule(h_, w_, hx - 92, hy - 10, hx - 150, hy + 26, 18))
    hand = np.maximum(hand, S.rect(h_, w_, hx - 58, hy + 40, hx + 58, h_, r=20))
    hand = S.roughen(hand, S.value_noise(h_, w_, 26, 7, 3), 0.5, 1.6)
    buf.composite(Flesh.OUTLINE, np.clip(S.dilate(hand, 10) - hand, 0, 1) * 0.9)
    buf.composite(mix(Flesh.SKIN_PINK_DARK, Flesh.OUTLINE, 0.55), hand * 0.9)
    vw = P.vein_web(h_, w_, 7, count=5, width=3.0, scale=0.8) * hand
    buf.composite(Flesh.nerve_glow(), vw * 0.5)
    p = B.fname(PR, "first_mutation_card_9s")
    B.register("TUT-07", p, w_, h_, "MVP", "9slice", note="wide card with a hand silhouette, 9-sliced")
    B.save(buf.to_image(), p)
    n += 1

    # ------------------------------------------------ TUT-08 first nerve contact prompt
    # the loudest prompt in the set, by canon
    size = 256
    buf = P.Buffer(size, size)
    from fleshkit import tissue_icons as TI
    nerve = TI.tissue_icon("T06", size, B.seed_of("TUT-08"))
    buf.composite(np.asarray(nerve, dtype=np.float32) / 255.0,
                  x0=size * 0.20, y0=size * 0.20)
    rng = np.random.default_rng(8)
    for i in range(7):
        a = rng.random() * 2 * math.pi
        d = size * (0.30 + rng.random() * 0.10)
        x, y = size / 2 + math.cos(a) * d, size / 2 + math.sin(a) * d
        ln = size * 0.10
        m = S.capsule(size, size, x, y, x + math.cos(a) * ln, y + math.sin(a) * ln, 4.0)
        buf.composite(Flesh.nerve_glow(), m)
    ring = S.ring(size, size, size / 2, size / 2, size * 0.455, size * 0.415)
    buf.composite(Flesh.nerve_glow(), ring)
    p = B.fname(PR, "first_nerve_contact_prompt_256x256")
    B.register("TUT-08", p, size, size, "MVP",
               note="nerve icon plus a shock line: deliberately the loudest prompt in the set")
    B.save(buf.to_image(), p)
    n += 1

    print(f"TUT MVP: {n} files")
    print(B.write_manifest("manifest_tut.json"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
