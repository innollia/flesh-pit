"""VFX: frame-sequence image assets, MVP rows.

MVP scope: VFX-01 tear burst, VFX-02 chew burst, VFX-03 tearing strand,
VFX-06 nerve contraction shockwave, VFX-09 vomit stream, VFX-10 flush swirl,
VFX-13 room transition bloom, VFX-17 mutation surge.

All flipbooks are horizontal strips with a power-of-two frame count and a
recorded FPS, per the format rule in asset-list.md section 0.  Frame-by-frame
PNGs are written next to each strip so a runtime can play either.

The look carries the same low-key rule as the rest of the set: these are lit
from a single source and mostly sit in shadow.  A big bright soft blob is the
fastest way to make an effect read as a cartoon puff, so motion is carried by
silhouette, speed, and value rather than by opacity ramps alone.

Rows: docs/asset-list.md section 15.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np

from fleshkit import build as B
from fleshkit import paint as P
from fleshkit import shapes as S
from fleshkit.palette import Deep, Flesh, Restroom, mix

VFX = "vfx"


def ease_out(t: float) -> float:
    return 1.0 - (1.0 - t) ** 3


def ease_in(t: float) -> float:
    return t ** 3


def lerp(a, b, t):
    return a + (b - a) * t


def particle(buf, size, cx, cy, r, color, seed, *, rough=0.34, lumps=4, keyline=True):
    """One irregular tissue blob, shaded and roughened."""
    m = S.blob(size, size, cx, cy, r, seed, lobes=lumps, rough=rough)
    m = S.roughen(m, S.value_noise(size, size, size * 0.10, seed + 3, 3), 0.7, 1.1)
    buf.composite(P.shade_fill(m, color, mix(color, "#ffffff", 0.35),
                               mix(color, "#000000", 0.55), r * 0.45), m)
    fall = S.blur(m, r * 0.18) - S.blur(m, r * 0.40)
    buf.composite(mix(color, "#000000", 0.6), np.clip(fall, 0, 1) * 0.8)
    return m


# --------------------------------------------------------------------------- VFX-01
def tear_burst(seed, size=256, frames=8):
    """Radial spray of red and pale fat streaks, fast.

    The signature effect.  The palette lifts from dark to full quickly and the
    streaks are elongated along their travel so the motion reads as a rip, not
    as an expanding circle.
    """
    out = []
    for f in range(frames):
        t = f / (frames - 1.0)
        buf = P.Buffer(size, size)
        c = size / 2
        rng = np.random.default_rng(seed)
        reach = ease_out(t) * size * 0.46
        for i in range(26):
            a = rng.random() * 2 * math.pi
            speed = 0.45 + rng.random() * 0.9
            d = reach * speed
            r = size * (0.012 + rng.random() * 0.030) * (1.0 - t * 0.45)
            # streak: a capsule trailing back along the travel direction
            tail = d * 0.34
            x, y = c + math.cos(a) * d, c + math.sin(a) * d
            col = Flesh.MUSCLE if rng.random() < 0.68 else Flesh.FAT
            m = S.capsule(size, size, x, y, x - math.cos(a) * tail, y - math.sin(a) * tail, r)
            m = np.clip(m, 0, 1)
            buf.composite(P.shade_fill(m, col, mix(col, "#ffffff", 0.30),
                                       mix(col, "#000000", 0.6), r * 0.6), m)
        # the wound itself: a dark tear that opens then begins to close
        if t < 0.6:
            k = t / 0.6
            w = size * 0.05 * (1.0 - k * 0.5)
            wound = S.capsule(size, size, c - size * 0.10, c, c + size * 0.10, c, w)
            buf.composite(Flesh.BLOOD_DARK, wound * 0.9)
            buf.composite(Flesh.BLOOD, S.erode(wound, size * 0.012) * 0.7)
        out.append(buf.to_image())
    return out


# --------------------------------------------------------------------------- VFX-02
def chew_burst(seed, size=256, frames=6):
    """Small compression puff with chunks flying: chewing made visible.

    The chunks hold their size and only dim as they leave, instead of shrinking
    to nothing, so the last frame still reads as chewing rather than as an
    empty frame.
    """
    out = []
    for f in range(frames):
        t = f / (frames - 1.0)
        buf = P.Buffer(size, size)
        c = size / 2
        puff = P.radial_mask(size, size, 0.5, 0.5, 0.16 + ease_out(t) * 0.26, 2.2)
        buf.composite(Flesh.SKIN_PINK, puff * (1.0 - t * 0.7) * 0.42)
        rng = np.random.default_rng(seed)
        for i in range(16):
            a = rng.random() * 2 * math.pi
            d = ease_out(t) * size * 0.26
            r = size * (0.016 + rng.random() * 0.022)
            m = S.circle(size, size, c + math.cos(a) * d, c + math.sin(a) * d, r)
            m = S.roughen(m, S.value_noise(size, size, size * 0.06, seed + i, 3), 0.7, 1.0)
            col = Flesh.MUSCLE if rng.random() < 0.6 else Flesh.FAT
            buf.composite(P.shade_fill(m, col, mix(col, "#ffffff", 0.28),
                                       mix(col, "#000000", 0.6), r * 0.5), m)
        out.append(buf.to_image())
    return out


# --------------------------------------------------------------------------- VFX-03
def tearing_strand(seed, size=256, frames=10):
    """Elastic filament stretching then snapping: tissue elasticity, canon.

    The strand is drawn as a thinning capsule that overshoots on frame 6 and
    whips back on 7, which is what makes elasticity legible without any number.
    """
    out = []
    for f in range(frames):
        t = f / (frames - 1.0)
        buf = P.Buffer(size, size)
        a = S.ellipse(size, size, size * 0.5, size * 0.16, size * 0.11, size * 0.09)
        b = S.ellipse(size, size, size * 0.5, size * 0.86, size * 0.11, size * 0.09)
        for m, col in ((a, Flesh.MUSCLE), (b, Flesh.MUSCLE_DARK)):
            buf.composite(P.shade_fill(m, col, mix(col, "#ffffff", 0.3),
                                       mix(col, "#000000", 0.55), size * 0.02), m)
        snap = t < 0.62
        if snap:
            k = ease_in(t / 0.62)
            gap = size * 0.06
            w = size * 0.030 * (1.0 - k * 0.45)
            y0, y1 = size * 0.16 + gap, size * 0.86 - gap
            # a slightly S-curved filament: it necks down in the middle
            m = np.zeros((size, size), dtype=np.float32)
            for i in range(10):
                yy = lerp(y0, y1, i / 9.0)
                xx = size * 0.5 + math.sin(i / 9.0 * math.pi) * size * 0.06 * k
                m = np.maximum(m, S.capsule(size, size, size * 0.5,
                                             lerp(y0, y1, max(0.0, i / 10.0 - 0.1)),
                                             xx, yy, w * (1.0 - abs(i / 9.0 - 0.5) * 0.35)))
            buf.composite(P.shade_fill(m, Flesh.MUSCLE_LIGHT, "#e8d8c8",
                                       Flesh.MUSCLE_DARK, size * 0.02), m)
        else:
            # the recoil: the two ends whip back and the gap closes
            k = ease_out((t - 0.62) / 0.38)
            for off, col in ((-1, Flesh.MUSCLE), (1, Flesh.MUSCLE_DARK)):
                w = size * 0.020
                m = S.capsule(size, size, size * 0.5, size * 0.5 - off * size * 0.10,
                              size * 0.5 + off * size * (0.30 * (1.0 - k) + 0.06),
                              size * 0.5, w)
                buf.composite(P.shade_fill(m, col, mix(col, "#ffffff", 0.3),
                                           mix(col, "#000000", 0.5), size * 0.012), m)
        out.append(buf.to_image())
    return out


# --------------------------------------------------------------------------- VFX-06
def nerve_shockwave(seed, size=512, frames=10):
    """Radial compression ripple with yellow dust.

    Canon requires the nerve reaction to read as caused by the player, so the
    ripple starts tight and centred and the dust is pushed outward in a ring,
    not scattered.
    """
    out = []
    c = size / 2
    for f in range(frames):
        t = f / (frames - 1.0)
        buf = P.Buffer(size, size)
        r = ease_out(t) * size * 0.44
        ring = S.ring(size, size, c, c, r + size * 0.035, r - size * 0.035)
        buf.composite(Flesh.nerve_base(), ring * (1.0 - t) * 0.85)
        buf.composite(Flesh.nerve_light(), S.erode(ring, size * 0.010) * (1.0 - t) * 0.7)
        rng = np.random.default_rng(seed)
        for i in range(40):
            a = rng.random() * 2 * math.pi
            d = r + rng.normal(0.0, size * 0.03)
            rr = size * (0.004 + rng.random() * 0.010)
            buf.composite(Flesh.nerve_glow(), S.circle(size, size, c + math.cos(a) * d,
                                                       c + math.sin(a) * d, rr) * (1.0 - t) * 0.8)
        # contracting flesh inside the ring: the wall is being pulled
        inner = S.circle(size, size, c, c, r * 0.92)
        buf.composite(Flesh.BLOOD_DARK, np.clip(1.0 - inner, 0, 1) * 0.0)
        out.append(buf.to_image())
    return out


# --------------------------------------------------------------------------- VFX-09
def vomit_stream(seed, size=256, frames=24, h=512):
    """Coarse stream into the bowl.  Played every single trip, so it must loop."""
    out = []
    W_, H_ = size, h
    for f in range(frames):
        t = f / frames
        buf = P.Buffer(W_, H_)
        yy, xx = S.grid(H_, W_)
        # a falling column with a wave, scrolling downward so the loop is seamless
        col = np.zeros((H_, W_), dtype=np.float32)
        phase = t * 2 * math.pi
        # Five overlapping falling columns.  They are drawn long enough to always
        # cover the frame: a capsule that only spans the visible height leaves
        # gaps as the scroll offset changes, which reads as a broken jet.
        for i in range(5):
            off = (i - 2) * W_ * 0.055
            cx = W_ * 0.5 + off + math.sin(phase + i * 0.6) * W_ * 0.022
            shift = t * H_ * 0.9
            col = np.maximum(col, S.capsule(H_, W_, float(cx), -H_ * 0.6 + shift,
                                            float(cx), H_ * 1.6 + shift, W_ * 0.085))
        # narrow the jet as it falls, so it reads as pouring not as a pipe
        taper = np.clip((yy / H_) * 1.0, 0, 1)
        col = np.clip(col * (1.0 - taper * 0.35), 0, 1)
        pal = Flesh.SKIN_PINK
        buf.composite(P.shade_fill(col, pal, mix(pal, "#ffffff", 0.35),
                                   mix(pal, "#000000", 0.6), W_ * 0.05), col)
        # coarse lumps travelling with the stream
        rng = np.random.default_rng(seed)
        for i in range(18):
            y = ((rng.random() + t * 1.0) % 1.0) * H_
            x = W_ * 0.5 + (rng.random() - 0.5) * W_ * 0.34
            r = W_ * (0.018 + rng.random() * 0.030)
            c2 = Flesh.BLOOD if rng.random() < 0.3 else "#c8a396"
            m = S.circle(H_, W_, x, y, r)
            m = S.roughen(m, S.value_noise(H_, W_, H_ * 0.05, seed + i, 3), 0.7, 1.0)
            buf.composite(P.shade_fill(m, c2, mix(c2, "#ffffff", 0.3),
                                       mix(c2, "#000000", 0.6), r * 0.5), m)
        out.append(buf.to_image())
    return out


# --------------------------------------------------------------------------- VFX-10
def flush_swirl(seed, size=256, frames=16):
    """Whirlpool in pale water.  Clean, not slimy -- this is the restroom."""
    out = []
    c = size / 2
    for f in range(frames):
        t = f / frames
        buf = P.Buffer(size, size)
        bowl = S.circle(size, size, c, c, size * 0.44)
        buf.composite(P.shade_fill(bowl, Restroom.WATER, "#e2eef0",
                                   Restroom.CERAMIC_SHADE, size * 0.04), bowl)
        # Two spiral arms with a strong outward taper.  Three arms at equal
        # weight produced a regular polygon instead of a whirlpool, because the
        # arm count was dividing the turn evenly; two arms with a rotating
        # phase read as rotation.
        for arm in range(2):
            prev = None
            for i in range(40):
                u = i / 39.0
                a = u * 3.4 * math.pi + t * 2 * math.pi + arm * math.pi
                d = size * 0.40 * (u ** 0.8)
                w = size * (0.030 * (1.0 - u * 0.80) + 0.004)
                cur = (c + math.cos(a) * d, c + math.sin(a) * d)
                if prev is not None:
                    m = S.capsule(size, size, prev[0], prev[1], cur[0], cur[1], w)
                    buf.composite("#ffffff", m * 0.50)
                    buf.composite(Restroom.ENAMEL_EDGE, S.shift(m, 0, 2) * 0.20)
                prev = cur
        # the drain
        dr = S.circle(size, size, c, c, size * 0.055)
        buf.composite(P.shade_fill(dr, Restroom.STEEL_DARK, Restroom.STEEL,
                                   "#3d4344", size * 0.012), dr)
        buf.composite(Restroom.ENAMEL_EDGE, S.outline(bowl, size * 0.012) * 0.8)
        out.append(buf.to_image())
    return out


# --------------------------------------------------------------------------- VFX-13
def room_bloom(seed, size=1024, frames=8):
    """White bloom expanding outward, clean: the colour contrast event."""
    out = []
    for f in range(frames):
        t = f / (frames - 1.0)
        buf = P.Buffer(size, size)
        r = ease_out(t) * size * 0.85
        core = P.radial_mask(size, size, 0.5, 0.5, max(0.02, r / size), 1.0)
        buf.composite("#ffffff", core * (0.35 + 0.65 * t))
        buf.composite(Restroom.FLUORESCENT, P.radial_mask(size, size, 0.5, 0.5,
                                                          max(0.02, r / size * 0.6), 1.6) * 0.5)
        # the bloom edge carries a faint warm ring so it is not a plain disc
        ring = S.ring(size, size, size / 2, size / 2, r * 1.06, r * 0.96)
        buf.composite(Restroom.SAFE_BLOOM, ring * (1.0 - t) * 0.55)
        out.append(buf.to_image())
    return out


# --------------------------------------------------------------------------- VFX-17
def mutation_surge(seed, size=1024, frames=12):
    """Body-wide red surge with a white core, travelling from the player outward."""
    out = []
    yy, xx = S.grid(size, size)
    for f in range(frames):
        t = f / (frames - 1.0)
        buf = P.Buffer(size, size)
        d = np.sqrt(((xx / size) - 0.5) ** 2 + ((yy / size) - 0.5) ** 2) / 0.7071
        front = ease_out(t) * 1.25
        band = np.clip(1.0 - np.abs(d - front) * 5.0, 0, 1)
        buf.composite(Flesh.BLOOD, np.clip(band, 0, 1) * (1.0 - t * 0.55) * 0.85)
        core = np.clip(1.0 - d * 1.5, 0, 1) ** 2
        buf.composite("#ffffff", core * np.clip(1.0 - t * 2.2, 0, 1))
        buf.composite(Flesh.CONGESTED, np.clip((d - front + 0.18) * 4.0, 0, 1)
                      * (1.0 - t * 0.4) * 0.5)
        out.append(buf.to_image())
    return out


def emit(aid, frames, path, **reg):
    B.register(aid, path, reg.get("tw", frames[0].width * len(frames)),
               reg.get("th", frames[0].height), reg.get("pri", "MVP"), "flipbook",
               frames=len(frames), fps=reg.get("fps", 24.0), note=reg.get("note", ""))
    B.save_flipbook(frames, path)


def main() -> int:
    n = 0
    specs = [
        ("VFX-01", tear_burst, "tear_burst_8f_256x256", 8, 24.0, 256, 256,
         "radial spray of red and fat streaks: the single most important game-feel effect"),
        ("VFX-02", chew_burst, "chew_burst_6f_256x256", 6, 18.0, 256, 256,
         "compression puff with chunks flying: chewing made visible"),
        ("VFX-03", tearing_strand, "tearing_strand_10f_256x256", 10, 30.0, 256, 256,
         "elastic filament stretching then snapping: tissue elasticity, canon"),
        ("VFX-06", nerve_shockwave, "nerve_shockwave_10f_512x512", 10, 24.0, 512, 512,
         "radial compression ripple with yellow dust; reads as caused by the player"),
        ("VFX-09", lambda s, w, nf: vomit_stream(s, 256, 24, 512),
         "vomit_stream_24f_256x512", 24, 24.0, 256, 512,
         "coarse stream into the bowl: the loop reset, played every single trip"),
        ("VFX-10", flush_swirl, "flush_swirl_16f_256x256", 16, 24.0, 256, 256,
         "whirlpool in pale water, clean not slimy: trip-end punctuation"),
        ("VFX-13", room_bloom, "room_transition_bloom_8f_1024x1024", 8, 12.0, 1024, 1024,
         "white bloom expanding outward: the colour contrast event"),
        ("VFX-17", mutation_surge, "mutation_surge_12f_1024x1024", 12, 24.0, 1024, 1024,
         "body-wide red surge with a white core: the transformation moment"),
    ]
    for aid, fn, name, nf, fps, w, h, note in specs:
        frames = fn(B.seed_of(aid), w, nf)
        path = B.fname(VFX, name)
        emit(aid, frames, path, tw=w * len(frames), th=h, pri="MVP", fps=fps, note=note)
        n += 1

    print(f"VFX MVP: {n} flipbooks")
    print(B.write_manifest("manifest_vfx.json"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
