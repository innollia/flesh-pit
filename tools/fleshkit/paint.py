"""Paint: shading, material, grime and RGBA compositing.

The style contract for this project, in one place:

  * light comes from the upper left, consistently, at every asset size
  * every silhouette carries a thick dark keyline (Flesh.OUTLINE) -- this is what
    makes UI icons readable when the game world behind them is also red
  * form is read by an inner crescent on the shadow side, never by a gradient
  * grime is layered at three different blotch sizes, because a single size
    reads as a repeating pattern rather than as dirt
  * the restroom never receives grime; `grime()` is a flesh-only verb

Colour buffers are premultiplied sRGB float32, matching the iconkit convention
this was ported from, so alpha edges composite without halos.
"""

from __future__ import annotations

import math

import numpy as np
from PIL import Image

from . import shapes as S
from .palette import Flesh, Restroom, hex_rgb, mix, ramp

# The one light direction, in screen space, pointing FROM the surface TOWARD the light.
LIGHT2 = (-0.45, -0.89)
LIGHT3 = (-0.45, -0.89, 0.42)


# --------------------------------------------------------------------------- buffers
class Buffer:
    """Premultiplied RGBA layer."""

    def __init__(self, w: int, h: int, fill=None):
        self.w, self.h = w, h
        self.rgb = np.zeros((h, w, 3), dtype=np.float32)
        self.a = np.zeros((h, w), dtype=np.float32)
        if fill is not None:
            self.rgb[:] = hex_rgb(fill)
            self.a[:] = 1.0

    def composite(self, rgb, alpha=None, x0: int = 0, y0: int = 0) -> None:
        """Composite over this buffer.

        Accepted forms:

          composite(colour, mask)             a flat colour through a mask
          composite(colour, mask, x0, y0)     the same, at a top-left position
          composite(rgba_array)               a finished sub-asset
          composite(rgba_array, x0=.., y0=..) a finished sub-asset, positioned

        Passing a positional number in the ``alpha`` slot is an error by design:
        positions must be passed by keyword so a stray int never becomes a mask.
        """
        if alpha is not None and not isinstance(alpha, np.ndarray):
            raise TypeError(
                "composite(rgb, mask, x0, y0) expects a mask array in slot 2; "
                "pass a position with x0=/y0= keywords")
        if alpha is None:
            rgb = np.asarray(rgb, dtype=np.float32)
            if rgb.ndim != 3 or rgb.shape[2] != 4:
                raise ValueError("composite needs a mask, or an (h, w, 4) rgb array")
            alpha = rgb[..., 3]
            rgb = rgb[..., :3]
        else:
            alpha = np.asarray(alpha, dtype=np.float32)
        if isinstance(rgb, str) or (isinstance(rgb, (list, tuple))
                                    and len(rgb) in (3, 4)
                                    and not isinstance(rgb[0], (list, tuple, np.ndarray))):
            rgb = np.broadcast_to(hex_rgb(rgb)[:3], (*alpha.shape, 3))
        else:
            rgb = np.asarray(rgb, dtype=np.float32)
            if rgb.ndim == 1 and rgb.shape[0] == 3:
                rgb = np.broadcast_to(rgb, (*alpha.shape, 3))
            elif rgb.ndim == 3 and rgb.shape[2] == 4:
                rgb = rgb[..., :3]
        h, w = alpha.shape
        # positions are pixel coordinates and may be fractional; slices need ints
        x0, y0 = int(round(float(x0))), int(round(float(y0)))
        bx0, by0 = max(0, x0), max(0, y0)
        bx1, by1 = min(self.w, x0 + w), min(self.h, y0 + h)
        if bx1 <= bx0 or by1 <= by0:
            return
        sx0, sy0 = bx0 - x0, by0 - y0
        a = alpha[sy0:sy0 + by1 - by0, sx0:sx0 + bx1 - bx0]
        c = rgb[sy0:sy0 + by1 - by0, sx0:sx0 + bx1 - bx0]
        da = self.a[by0:by1, bx0:bx1]
        dr = self.rgb[by0:by1, bx0:bx1]
        dr *= (1.0 - a)[..., None]
        dr += c * a[..., None]
        da *= 1.0 - a
        da += a

    def to_image(self) -> Image.Image:
        a = np.clip(self.a, 0.0, 1.0)
        safe = np.where(a > 1e-5, a, 1.0)[..., None]
        rgb = np.clip(self.rgb / safe, 0.0, 1.0)
        out = np.dstack([rgb, a[..., None]])
        return Image.fromarray(np.ascontiguousarray((out * 255.0 + 0.5).astype(np.uint8)))


def downsample(img: Image.Image, factor: int) -> Image.Image:
    """Premultiplied Lanczos reduction so transparent edges do not darken."""
    if factor <= 1:
        return img
    size = (max(1, img.width // factor), max(1, img.height // factor))
    arr = np.asarray(img.convert("RGBA"), dtype=np.float32) / 255.0
    premul = arr.copy()
    premul[..., :3] *= premul[..., 3:4]
    chans = [Image.fromarray(np.ascontiguousarray(premul[..., i])).resize(
        size, Image.Resampling.LANCZOS) for i in range(4)]
    out = np.dstack([np.asarray(c) for c in chans])
    a = np.clip(out[..., 3], 0.0, 1.0)
    safe = np.where(a > 1e-5, a, 1.0)[..., None]
    return Image.fromarray(np.ascontiguousarray(
        (np.dstack([np.clip(out[..., :3] / safe, 0.0, 1.0), a[..., None]]) * 255.0 + 0.5
    ).astype(np.uint8)))


# --------------------------------------------------------------------------- shading
def crescent(mask: np.ndarray, dx: float, dy: float) -> np.ndarray:
    """Part of ``mask`` uncovered when it moves by (dx, dy).

    Offset toward the light and this is the far (shadow-side) rim, which is the
    only interior shading cue the style uses.
    """
    return np.clip(mask - shift(mask, int(round(dx)), int(round(dy))), 0.0, 1.0)


def shift(a: np.ndarray, dx: int, dy: int) -> np.ndarray:
    out = np.zeros_like(a)
    h, w = a.shape[:2]
    if abs(dx) >= w or abs(dy) >= h:
        return out
    sy0, sx0 = max(0, -dy), max(0, -dx)
    dy0, dx0 = max(0, dy), max(0, dx)
    hh, ww = h - abs(dy), w - abs(dx)
    out[dy0:dy0 + hh, dx0:dx0 + ww] = a[sy0:sy0 + hh, sx0:sx0 + ww]
    return out


def lambert(mask: np.ndarray, radius: float = 9.0, bump: float = 1.0) -> np.ndarray:
    """Pseudo-3D light term in -1..1, treating the mask as a soft dome."""
    hgt = S.blur(mask, radius)
    gy, gx = np.gradient(hgt)
    k = bump * radius * 2.2
    nx, ny = -gx * k, -gy * k
    norm = np.sqrt(nx * nx + ny * ny + 1.0)
    lx, ly, lz = LIGHT3
    return (nx * lx + ny * ly + lz) / norm


def shade_fill(mask: np.ndarray, base, light, dark, radius: float = 9.0,
               bump: float = 1.0) -> np.ndarray:
    """Ramp a mask from ``light`` to ``dark`` along the light term.

    This is the workhorse.  The remap is deliberately bottom-heavy: the mean
    lands near the ``dark`` end and only the lit edge approaches ``light``.
    A symmetric remap puts half the surface in the light colour, which is what
    made the first pass read as a flat cartoon -- gothic form is carried by a
    small lit area against a large dark one.
    """
    term = lambert(mask, radius, bump)
    t = np.clip((term + 0.62) / 1.30, 0.0, 1.0)[..., None]
    t = t ** 1.45
    return mix(dark, light, t)


def form_crescent(mask: np.ndarray, width: float = 5.0) -> np.ndarray:
    """Interior shadow-side rim: the crescent every 3D form carries."""
    lx, ly = LIGHT2
    return crescent(mask, -lx * width, -ly * width)


def specular(mask: np.ndarray, radius: float = 6.0, thresh: float = 0.55,
             amount: float = 1.0) -> np.ndarray:
    """Wet highlights on the lit side.

    Tight and dim on purpose.  A broad bright blob is the single loudest
    "cartoon" signal in this set; wetness has to come from a thin bright edge
    plus a dark body, not from a glossy dome.
    """
    term = lambert(mask, radius, 1.2)
    return np.clip((term - thresh) / max(1e-3, 1.0 - thresh), 0.0, 1.0) ** 2.6 * amount


def keyline(mask: np.ndarray, width: float, color=None) -> tuple[np.ndarray, np.ndarray]:
    """Return (keyline_mask, silhouette).  The style's mandatory dark rim."""
    rim = S.outline(mask, width)
    return rim, mask


# --------------------------------------------------------------------------- flesh detail
def vein_web(h: int, w: int, seed: int, count: int = 9, width: float = 2.0,
             spread: float = 0.5, scale: float = 1.0, soft: float = 1.0) -> np.ndarray:
    """Branching surface veins.  STO-05 congestion, tumors, red band art.

    Short segments plus a blur, because long straight capsules read as scratches
    rather than as vessels.  Cos-cancelled so the result tiles on a rectangle,
    which the 2K band textures need.
    """
    rng = np.random.default_rng(seed)
    k = 2.0 * math.pi / max(1.0, scale)
    acc = np.zeros((h, w), dtype=np.float32)

    def fold(u):
        return (np.cos(k * u) + 1) * 0.5

    for _ in range(count):
        cx, cy = rng.random(), rng.random()
        a0 = rng.random() * 2 * math.pi
        x, y = cx, cy
        for _ in range(7):
            # walk in short hops with a wandering heading: a vessel, not a line
            a = a0 + float(rng.normal(0, 0.75))
            ln = 0.030 + rng.random() * 0.030
            x2, y2 = x + math.cos(a) * ln, y + math.sin(a) * ln
            m = S.capsule(h, w, fold(x) * w, fold(y) * h, fold(x2) * w, fold(y2) * h,
                          width * (0.6 + 0.4 * spread))
            # taper: distal segments are thinner, so the web thins outward
            m = m * float(rng.uniform(0.7, 1.0))
            acc = np.maximum(acc, m)
            x, y = x2, y2
    if soft > 0:
        acc = S.blur(acc, soft)
    return np.clip(acc, 0.0, 1.0)


def grime(h: int, w: int, seed: int, strength: float = 0.55,
          color=None, three_layer: bool = True, scale: float = 1.0) -> np.ndarray:
    """Dirt coverage in 0..1.

    Three blotch sizes at decreasing strength, because a single size reads as a
    repeating pattern.  asset-list.md's lessons-learned section is explicit
    about this, so the layering is not optional.
    """
    if three_layer:
        big = S.value_noise(h, w, 170.0 * scale, seed, 3)
        mid = S.value_noise(h, w, 78.0 * scale, seed + 101, 3)
        small = S.value_noise(h, w, 34.0 * scale, seed + 202, 3)
        cov = (S.smoothstep(0.56, 0.92, big) * 0.55
               + S.smoothstep(0.54, 0.90, mid) * 0.30
               + S.smoothstep(0.50, 0.88, small) * 0.15)
    else:
        cov = S.smoothstep(0.5, 0.9, S.value_noise(h, w, 90.0 * scale, seed, 4))
    return np.clip(cov * strength, 0.0, 1.0)


def mottling(h: int, w: int, seed: int, amount: float = 0.25, cell: float = 60.0) -> np.ndarray:
    """Uneven pigment: keeps a flat fill from looking like vector art."""
    n = S.fbm(h, w, seed, cell, 4)
    return np.clip((n - 0.5) * 2.0 * amount + 0.5, 0.0, 1.0)


def pores(h: int, w: int, seed: int, count: int = 260, r: float = 1.6,
          spread: float = 1.0) -> np.ndarray:
    """Follicle pits and small pockmarks: B01 surface, skin, tumors."""
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w), dtype=np.float32)
    for _ in range(count):
        cx, cy = rng.random() * w, rng.random() * h
        rr = r * (0.4 + rng.random() * 1.2)
        out = np.minimum(out + S.circle(h, w, cx, cy, rr), 1.0)
    return out


def fibres(h: int, w: int, seed: int, angle: float = 0.0, count: int = 220,
           width: float = 1.4, length: float = 90.0) -> np.ndarray:
    """Directional fibre grain: muscle striation, nerve strands, fascia weave."""
    rng = np.random.default_rng(seed)
    a = math.radians(angle)
    dx, dy = math.cos(a), math.sin(a)
    out = np.zeros((h, w), dtype=np.float32)
    for _ in range(count):
        x, y = rng.random() * w, rng.random() * h
        ln = length * (0.3 + rng.random())
        out = np.maximum(out, S.capsule(h, w, x, y, x + dx * ln, y + dy * ln,
                                        width * (0.5 + rng.random())))
    return np.clip(out, 0.0, 1.0)


def striation(h: int, w: int, seed: int, bands: int = 40, angle: float = 0.0,
              thickness: float = 3.0) -> np.ndarray:
    """Regular parallel bands for muscle: the read that says 'striated'."""
    yy, xx = S.grid(h, w)
    a = math.radians(angle)
    t = xx * math.cos(a) + yy * math.sin(a)
    v = np.sin(t / max(1e-3, thickness) * math.pi)
    v = 0.5 + 0.5 * v
    n = S.value_noise(h, w, 40.0, seed, 3)
    return np.clip(v * 0.7 + n * 0.3, 0.0, 1.0)


def crosshatch(h: int, w: int, seed: int, pitch: float = 26.0,
               width: float = 2.0) -> np.ndarray:
    """Fascia weave: two fibre passes at a right angle."""
    a = fibres(h, w, seed, 18.0, 160, width, pitch * 2.4)
    b = fibres(h, w, seed + 7, 108.0, 160, width, pitch * 2.4)
    return np.clip(a + b, 0.0, 1.0)


# --------------------------------------------------------------------------- wetness
def wet_sheen(h: int, w: int, seed: int, amount: float = 0.35,
              sharp: float = 0.75) -> np.ndarray:
    """Specular coating for TEX-117 and every 'wet' row."""
    n = S.fbm(h, w, seed, 90.0, 4)
    return np.clip((n - (1.0 - sharp)) / max(1e-3, sharp), 0.0, 1.0) * amount


# --------------------------------------------------------------------------- gradients
def linear_gradient(h: int, w: int, colors, angle: float = 90.0) -> np.ndarray:
    """Ramp across the image.  ``angle`` 90 = top-to-bottom."""
    yy, xx = S.grid(h, w)
    a = math.radians(angle)
    t = xx * math.cos(a) + yy * math.sin(a)
    t = (t - t.min()) / max(1e-6, t.max() - t.min())
    return ramp(colors, t)


def radial(h: int, w: int, cx: float = 0.5, cy: float = 0.5, r: float = 0.7,
           colors=("#ffffff", "#000000"), power: float = 1.0) -> np.ndarray:
    """Radial ramp in 0..1 with a colour at centre and one at radius."""
    yy, xx = S.grid(h, w)
    d = np.sqrt(((xx / w) - cx) ** 2 + ((yy / h) - cy) ** 2) / max(1e-6, r)
    return ramp(colors, np.clip(d, 0.0, 1.0) ** power)


def radial_mask(h: int, w: int, cx: float = 0.5, cy: float = 0.5, r: float = 0.7,
                falloff: float = 1.0) -> np.ndarray:
    """Soft round coverage: vignettes, glows, safe bloom, bokeh."""
    yy, xx = S.grid(h, w)
    d = np.sqrt(((xx / w) - cx) ** 2 + ((yy / h) - cy) ** 2) / max(1e-6, r)
    return np.clip(1.0 - d, 0.0, 1.0) ** max(0.05, falloff)


def vignette(h: int, w: int, strength: float = 0.6, falloff: float = 1.4,
             invert: bool = False) -> np.ndarray:
    """Dark edge bleed.  The dirty world's default; ``invert`` gives RST-13 clean corners."""
    yy, xx = S.grid(h, w)
    dx = (xx / w - 0.5) * 2.0
    dy = (yy / h - 0.5) * 2.0
    d = np.clip(np.sqrt(dx * dx + dy * dy) / 1.414, 0.0, 1.0)
    v = d ** falloff * strength
    return (1.0 - v) if invert else v


# --------------------------------------------------------------------------- icon helper
def icon_base(size: int, seed: int = 0) -> tuple[S.Buffer, np.ndarray, float]:
    """Standard icon setup: 128-style box, transparent centre, keyline width scaled.

    Returns (buffer, transparent-hole mask, keyline width).  Every ICO row starts
    here so the set has one border weight.
    """
    buf = Buffer(size, size)
    hole = np.zeros((size, size), dtype=np.float32)
    kl = max(2.0, size * 0.035)
    return buf, hole, kl


def render_icon(size: int, seed: int, painter) -> Image.Image:
    """Run ``painter(buf, S, size, seed)`` and return a finished square icon."""
    buf = Buffer(size, size)
    painter(buf, S, size, seed)
    return buf.to_image()
