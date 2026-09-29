"""Shared widget builders for the UI groups.

These are the pieces every panel group needs: 9-slice cards, gauges, rings,
banners, plates.  They live here rather than in each group script so the STO
gauge, the MNU panel and the TUT prompt all get the same corner treatment and
the same keyline weight.
"""

from __future__ import annotations

import math

import numpy as np
from PIL import Image

from . import paint as P
from . import shapes as S
from .palette import Flesh, Restroom, hex_rgb, mix


# --------------------------------------------------------------------------- panels
def card(buf, w, h, border, pal, *, corner=None, keyline=None, kl=None,
         accent=None, accent_side="left", grime_amt=0.28, seed=0):
    """A wet dark-red UI card, 9-slice safe.  Returns the body mask."""
    pal = pal or {"base": Flesh.UI_PANEL, "light": Flesh.UI_PANEL_LIGHT,
                  "dark": Flesh.UI_EDGE}
    corner = corner if corner is not None else border * 0.8
    kl = kl if kl is not None else max(2.0, w * 0.006)
    body = S.rect(h, w, border, border, w - border, h - border, r=corner)
    buf.composite(P.shade_fill(body, pal["base"], pal["light"], pal["dark"],
                               max(3.0, w * 0.030)), body)
    # uneven pigment so the panel is not a flat vector fill
    mot = P.mottling(h, w, seed, 0.18, max(40.0, w * 0.12))
    buf.composite(pal["dark"], (1.0 - mot) * body * 0.22)
    if grime_amt > 0.0:
        buf.composite(Flesh.GRIME_DEEP, P.grime(h, w, seed + 31, grime_amt) * body * 0.55)
    buf.composite(pal["dark"], P.form_crescent(body, max(2.0, w * 0.016)) * 0.45)
    buf.composite(keyline or Flesh.OUTLINE, S.outline(body, kl))
    if accent:
        if accent_side == "left":
            bar = S.rect(h, w, border, border, border + max(3.0, w * 0.010), h - border, r=2)
        else:
            bar = S.rect(h, w, border, h - border - max(3.0, w * 0.012),
                         w - border, h - border, r=2)
        buf.composite(accent, bar)
    return body


def clean_card(buf, w, h, border, *, corner=None, keyline=None, kl=None, seed=0):
    """The restroom white panel.  No grime, ever."""
    corner = corner if corner is not None else border * 0.8
    kl = kl if kl is not None else max(1.5, w * 0.004)
    body = S.rect(h, w, border, border, w - border, h - border, r=corner)
    buf.composite(P.shade_fill(body, Restroom.ENAMEL, "#ffffff", Restroom.CERAMIC_SHADE,
                               max(3.0, w * 0.030)), body)
    buf.composite(Restroom.CERAMIC_SHADE,
                  (1.0 - P.mottling(h, w, seed, 0.10, max(40.0, w * 0.14))) * body * 0.25)
    buf.composite(keyline or Restroom.ENAMEL_EDGE, S.outline(body, kl) * 0.85)
    return body


def ruled_lines(buf, w, h, y0, y1, *, x0=None, x1=None, count=3, color=None,
                thickness=None, seed=0, jitter=0.10):
    """Blank ruled lines for font text.  Empty space, never a baked string."""
    x0 = w * 0.10 if x0 is None else x0
    x1 = w * 0.90 if x1 is None else x1
    th = thickness if thickness is not None else max(2.0, h * 0.018)
    rng = np.random.default_rng(seed)
    col = color or Flesh.UI_EDGE
    for i in range(count):
        t = 0.0 if count == 1 else i / (count - 1.0)
        y = y0 + (y1 - y0) * t
        end = x1 - (x1 - x0) * (jitter * (i % 2))
        buf.composite(col, S.rect(h, w, x0, y, end, y + th, r=th / 2) * 0.55)


def slot(buf, w, h, x, y, sw, sh, *, fill=None, rim=None, r=None, seed=0):
    """An empty inset well: where a sub-icon or a numeral will be composited."""
    r = r if r is not None else sw * 0.18
    m = S.rect(h, w, x, y, x + sw, y + sh, r=r)
    buf.composite(fill or Flesh.UI_EDGE, m)
    buf.composite(Flesh.OUTLINE, S.outline(m, max(1.5, sw * 0.03)) * 0.8)
    return m


# --------------------------------------------------------------------------- gauges
def gauge_ring(buf, size, cx, cy, r, width, frac, *, base=None, fill=None,
               ticks=None, tick_count=10, tick_len=0.0):
    """A clockwise wipe ring.  ``frac`` 0..1.  No numerals, ticks only."""
    base = base or Flesh.UI_EDGE
    fill = fill or Flesh.SKIN_WET
    buf.composite(base, S.ring(size, size, cx, cy, r + width / 2, r - width / 2))
    if frac > 0.0:
        buf.composite(fill, S.arc_stroke(size, size, cx, cy, r, width, -90.0,
                                         -90.0 + 360.0 * min(1.0, frac)))
    if ticks and tick_len > 0:
        for i in range(tick_count):
            a = math.radians(-90.0 + 360.0 * i / tick_count)
            c, s = math.cos(a), math.sin(a)
            buf.composite(ticks, S.capsule(size, size, cx + c * (r + width / 2 + 2),
                                           cy + s * (r + width / 2 + 2),
                                           cx + c * (r + width / 2 + 2 + tick_len),
                                           cy + s * (r + width / 2 + 2 + tick_len),
                                           max(1.0, width * 0.12)))


def bar_gauge(buf, w, h, x, y, bw, bh, frac, *, track=None, fill=None, r=None,
              vertical=False):
    """A linear fill track.  ``frac`` 0..1."""
    track = track or Flesh.UI_EDGE
    r = r if r is not None else bh * 0.4
    t = S.rect(h, w, x, y, x + bw, y + bh, r=r)
    buf.composite(track, t)
    if frac > 0.0:
        if vertical:
            fh = bh * min(1.0, frac)
            f = S.rect(h, w, x, y + bh - fh, x + bw, y + bh, r=r)
        else:
            fw = bw * min(1.0, frac)
            f = S.rect(h, w, x, y, x + fw, y + bh, r=r)
        buf.composite(fill or Flesh.SKIN_WET, f)
    return t


def notch_ticks(size, count, x, y0, y1, width, color, *, long_every=0, long_extra=0.0):
    """A vertical strip of short marks: STO-07, DEP-03, CMP-05."""
    out = np.zeros((size, size), dtype=np.float32)
    for i in range(count):
        t = i / max(1, count - 1.0)
        y = y0 + (y1 - y0) * t
        ln = width + (long_extra if (long_every and i % long_every == 0) else 0.0)
        out = np.maximum(out, S.capsule(size, size, x, y, x + ln, y,
                                        max(1.0, width * 0.10)))
    return out * 1.0 if color is None else out


# --------------------------------------------------------------------------- banners
def torn_edge(h, w, y, *, amp=None, freq=None, seed=0, down=False):
    """An organic torn horizontal edge.  Band cards and death cards use this."""
    rng = np.random.default_rng(seed)
    amp = amp if amp is not None else h * 0.045
    freq = freq if freq is not None else 3.0
    xx = np.arange(w, dtype=np.float32)
    n = S.value_noise(1, w, max(8.0, w / freq), seed, 3)[0]
    edge = y + (n - 0.5) * 2.0 * amp + np.sin(xx / max(1.0, w / (freq * 2.0)) * math.pi * 2.0) * amp * 0.35
    yy = np.arange(h, dtype=np.float32)[:, None]
    return (yy >= edge[None, :]).astype(np.float32) if not down else (yy <= edge[None, :]).astype(np.float32)


def banner(buf, w, h, border, pal, *, seed=0, keyline=None):
    """A wide torn-flesh banner with a reserved top band for font text."""
    pal = pal or {"base": Flesh.UI_PANEL, "light": Flesh.UI_PANEL_LIGHT, "dark": Flesh.UI_EDGE}
    body = torn_edge(h, w, h * 0.16, seed=seed)
    buf.composite(P.shade_fill(body, pal["base"], pal["light"], pal["dark"], w * 0.02), body)
    buf.composite(Flesh.GRIME_DEEP, P.grime(h, w, seed + 5, 0.42) * body * 0.60)
    buf.composite(pal["dark"], P.form_crescent(body, w * 0.012) * 0.5)
    buf.composite(keyline or Flesh.OUTLINE, S.outline(body, max(2.0, w * 0.005)))
    return body


# --------------------------------------------------------------------------- plates
def plate(buf, w, h, border, base, light, dark, *, seed=0, worn=0.30, kl=None):
    """A stained enamel plate: DEP-05..12, DEP-16, LDG-07.  Always textless."""
    body = S.rect(h, w, border, border, w - border, h - border, r=border * 0.5)
    buf.composite(P.shade_fill(body, base, light, dark, max(2.0, w * 0.02)), body)
    buf.composite(Flesh.GRIME, P.grime(h, w, seed, worn) * body * 0.55)
    buf.composite(dark, P.form_crescent(body, max(1.5, w * 0.010)) * 0.4)
    buf.composite(Flesh.OUTLINE, S.outline(body, kl if kl is not None else max(1.5, w * 0.004)))
    return body


# --------------------------------------------------------------------------- vignettes
def vignette_overlay(size, *, bile=False, invert=False, strength=0.6, falloff=1.4):
    """STO-09 nausea, DTH-01 death, RST-13 clean, ACC-03 reduced motion."""
    yy, xx = S.grid(size, size)
    dx, dy = (xx / size - 0.5) * 2.0, (yy / size - 0.5) * 2.0
    d = np.clip(np.sqrt(dx * dx + dy * dy) / 1.414, 0.0, 1.0)
    v = (d ** falloff * strength)
    if invert:
        v = 1.0 - v
    col = Flesh.NAUSEA if bile else (Flesh.BLOOD_DARK if not invert else Restroom.SAFE_BLOOM_EDGE)
    return v.astype(np.float32), col


# --------------------------------------------------------------------------- misc
def chevron_icon(size, color, *, down=False, weight=None, angle=0.0):
    """A clean directional chevron: DEP-19 up, DEP-21 down, TUT-03 throat-down."""
    buf = P.Buffer(size, size)
    wgt = weight if weight is not None else size * 0.16
    m = S.chevron(size, size, size / 2, size / 2, size * 0.56, wgt, angle=angle, down=down)
    buf.composite(color, m)
    return buf.to_image()


def bone_flag(size, color=None):
    """DEP-18 personal-best marker: a small gold pennant on a bone pin."""
    buf = P.Buffer(size, size)
    col = color or Flesh.GOLD_RIM
    pole = S.capsule(size, size, size * 0.30, size * 0.16, size * 0.30, size * 0.86, size * 0.045)
    buf.composite(P.shade_fill(pole, Flesh.BONE, "#ffffff", Flesh.BONE_SHADE,
                               size * 0.06), pole)
    flag = S.polygon(size, size, [(size * 0.32, size * 0.20), (size * 0.76, size * 0.34),
                                  (size * 0.32, size * 0.50)])
    buf.composite(P.shade_fill(flag, col, Flesh.GOLD_RIM_LIGHT, Flesh.MOULD, size * 0.05), flag)
    buf.composite(Flesh.OUTLINE, S.outline(flag, size * 0.022))
    buf.composite(Flesh.OUTLINE, S.outline(pole, size * 0.020) * 0.8)
    return buf.to_image()
