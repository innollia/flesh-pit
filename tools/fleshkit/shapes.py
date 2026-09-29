"""Raster primitives: masks, shapes and the drawing verbs every asset is built from.

Everything returns a float32 coverage mask in 0..1, shape (h, w).  Shapes are
drawn supersampled by ``SS`` and reduced with a box filter, so an edge is smooth
at any size without needing a real antialiasing implementation.

Masks are the currency here.  An asset is: build masks -> shade them ->
composite.  That keeps lighting consistent across 333 unrelated files, which is
the only way a set this large stays one style.
"""

from __future__ import annotations

import math

import numpy as np

SS = 4  # supersample factor for shape rasterisation


# --------------------------------------------------------------------------- grid helpers
def grid(h: int, w: int) -> tuple[np.ndarray, np.ndarray]:
    """Return (yy, xx) float32 pixel-centre coordinate grids."""
    yy, xx = np.mgrid[0:h, 0:w]
    return yy.astype(np.float32) + 0.5, xx.astype(np.float32) + 0.5


def canvas(h: int, w: int) -> np.ndarray:
    """An empty coverage canvas."""
    return np.zeros((h, w), dtype=np.float32)


def place(mask: np.ndarray, h: int, w: int, x: float, y: float) -> np.ndarray:
    """Composite ``mask`` (top-left anchored) into an (h, w) canvas at (x, y)."""
    out = np.zeros((h, w), dtype=np.float32)
    mh, mw = mask.shape
    sx0, sy0 = int(round(x)), int(round(y))
    sx1, sy1 = sx0 + mw, sy0 + mh
    dx0, dy0 = max(0, sx0), max(0, sy0)
    dx1, dy1 = min(w, sx1), min(h, sy1)
    if dx1 <= dx0 or dy1 <= dy0:
        return out
    sub = mask[dy0 - sy0:dy1 - sy0, dx0 - sx0:dx1 - sx0]
    out[dy0:dy1, dx0:dx1] = np.maximum(out[dy0:dy1, dx0:dx1], sub)
    return out


def reduce_ss(mask_ss: np.ndarray) -> np.ndarray:
    """Box-reduce a supersampled mask back to 1x, antialiased."""
    h, w = mask_ss.shape
    hh, ww = h // SS, w // SS
    if hh < 1 or ww < 1:
        return mask_ss.astype(np.float32)
    m = mask_ss[:hh * SS, :ww * SS]
    return m.reshape(hh, SS, ww, SS).mean(axis=(1, 3)).astype(np.float32)


def shift(a: np.ndarray, dx: int, dy: int) -> np.ndarray:
    """Translate a mask, filling with zero.  Rim highlights and offset shadows."""
    out = np.zeros_like(a)
    h, w = a.shape[:2]
    if abs(dx) >= w or abs(dy) >= h:
        return out
    sy0, sx0 = max(0, -dy), max(0, -dx)
    dy0, dx0 = max(0, dy), max(0, dx)
    hh, ww = h - abs(dy), w - abs(dx)
    out[dy0:dy0 + hh, dx0:dx0 + ww] = a[sy0:sy0 + hh, sx0:sx0 + ww]
    return out


# --------------------------------------------------------------------------- basic shapes
def _bb(cx: float, cy: float, rx: float, ry: float) -> tuple[int, int, int, int]:
    """Integer supersampled bounding box for an axis-aligned region."""
    return (int(np.floor((cx - rx) * SS)), int(np.floor((cy - ry) * SS)),
            int(np.ceil((cx + rx) * SS)) + 1, int(np.ceil((cy + ry) * SS)) + 1)


def _paste_ss(out: np.ndarray, sub: np.ndarray, bx0: int, by0: int, bx1: int, by1: int) -> None:
    """Reduce a supersampled sub-block into ``out`` at supersampled position."""
    hh, ww = (by1 - by0) // SS, (bx1 - bx0) // SS
    if hh < 1 or ww < 1:
        return
    m = sub[:hh * SS, :ww * SS].reshape(hh, SS, ww, SS).mean(axis=(1, 3))
    ox, oy = bx0 // SS, by0 // SS
    oh, ow = out.shape
    dx0, dy0 = max(0, ox), max(0, oy)
    dx1, dy1 = min(ow, ox + ww), min(oh, oy + hh)
    if dx1 <= dx0 or dy1 <= dy0:
        return
    out[dy0:dy1, dx0:dx1] = np.maximum(out[dy0:dy1, dx0:dx1],
                                        m[dy0 - oy:dy1 - oy, dx0 - ox:dx1 - ox])


def _fill(out: np.ndarray, bbox, fn) -> None:
    """Run ``fn(yy, xx)`` over a supersampled bbox and reduce it into ``out``."""
    bx0, by0, bx1, by1 = bbox
    if bx1 <= bx0 or by1 <= by0:
        return
    yy = (np.arange(by0, by1, dtype=np.float32) + 0.5)[:, None]
    xx = (np.arange(bx0, bx1, dtype=np.float32) + 0.5)[None, :]
    _paste_ss(out, fn(yy, xx), bx0, by0, bx1, by1)


def circle(h: int, w: int, cx: float, cy: float, r: float) -> np.ndarray:
    out = np.zeros((h, w), dtype=np.float32)
    r = max(0.0, r)
    _fill(out, _bb(cx, cy, r, r),
          lambda yy, xx: (np.sqrt((xx - cx * SS) ** 2 + (yy - cy * SS) ** 2) <= r * SS)
          .astype(np.float32))
    return out


def ellipse(h: int, w: int, cx: float, cy: float, rx: float, ry: float,
            rot: float = 0.0) -> np.ndarray:
    out = np.zeros((h, w), dtype=np.float32)
    rx, ry = max(0.5, rx), max(0.5, ry)
    reach = math.hypot(rx, ry)
    c, s = math.cos(-math.radians(rot)), math.sin(-math.radians(rot))

    def f(yy, xx):
        dx, dy = xx - cx * SS, yy - cy * SS
        ux, uy = dx * c - dy * s, dx * s + dy * c
        d = np.sqrt((ux / (rx * SS)) ** 2 + (uy / (ry * SS)) ** 2)
        return (d <= 1.0).astype(np.float32)

    _fill(out, _bb(cx, cy, reach, reach), f)
    return out


def rect(h: int, w: int, x0: float, y0: float, x1: float, y1: float, r: float = 0.0,
         rot: float = 0.0) -> np.ndarray:
    out = np.zeros((h, w), dtype=np.float32)
    hx, hy = abs(x1 - x0) * 0.5, abs(y1 - y0) * 0.5
    cx, cy = (x0 + x1) * 0.5, (y0 + y1) * 0.5
    r = min(r, hx, hy)
    reach = math.hypot(hx, hy) + 1
    c, s = math.cos(-math.radians(rot)), math.sin(-math.radians(rot))
    rx = max(0.5, hx - r)
    ry = max(0.5, hy - r)

    def f(yy, xx):
        dx, dy = xx - cx * SS, yy - cy * SS
        ux, uy = dx * c - dy * s, dx * s + dy * c
        if r <= 0.0:
            return ((np.abs(ux) <= hx * SS) & (np.abs(uy) <= hy * SS)).astype(np.float32)
        qx = np.abs(ux) - rx * SS
        qy = np.abs(uy) - ry * SS
        d = (np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2)
             + np.minimum(np.maximum(qx, qy), 0) - r * SS)
        return (d <= 0).astype(np.float32)

    _fill(out, _bb(cx, cy, reach, reach), f)
    return out


def capsule(h: int, w: int, x0: float, y0: float, x1: float, y1: float, r: float) -> np.ndarray:
    """Thick line segment with round caps: limbs, straps, veins, stems."""
    out = np.zeros((h, w), dtype=np.float32)
    r = max(0.0, r)
    lo_x, hi_x = (x0, x1) if x0 <= x1 else (x1, x0)
    lo_y, hi_y = (y0, y1) if y0 <= y1 else (y1, y0)
    ax, ay = x0 * SS, y0 * SS
    bx, by = x1 * SS, y1 * SS
    bx2, by2 = bx - ax, by - ay
    denom = bx2 * bx2 + by2 * by2

    def f(yy, xx):
        px, py = xx - ax, yy - ay
        t = 0.0 if denom < 1e-6 else np.clip((px * bx2 + py * by2) / denom, 0.0, 1.0)
        dx, dy = px - bx2 * t, py - by2 * t
        return (np.sqrt(dx * dx + dy * dy) <= r * SS).astype(np.float32)

    _fill(out, _bb((lo_x + hi_x) / 2, (lo_y + hi_y) / 2, (hi_x - lo_x) / 2 + r,
                   (hi_y - lo_y) / 2 + r), f)
    return out


def polygon(h: int, w: int, pts) -> np.ndarray:
    """Even-odd fill of a point list, via crossing count, bounded to its bbox."""
    pts = list(pts)
    if len(pts) < 3:
        return np.zeros((h, w), dtype=np.float32)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    rx, ry = (max(xs) - min(xs)) / 2 + 1, (max(ys) - min(ys)) / 2 + 1
    out = np.zeros((h, w), dtype=np.float32)

    def f(yy, xx):
        inside = np.zeros(np.broadcast_shapes(yy.shape, xx.shape), dtype=bool)
        n = len(pts)
        for i in range(n):
            x1, y1 = pts[i][0] * SS, pts[i][1] * SS
            x2, y2 = pts[(i + 1) % n][0] * SS, pts[(i + 1) % n][1] * SS
            cond = (y1 > yy) != (y2 > yy)
            denom = y2 - y1
            xint = (x2 - x1) * (yy - y1) / np.where(denom == 0, 1e-9, denom) + x1
            inside ^= cond & (xx < xint)
        return inside.astype(np.float32)

    _fill(out, _bb(cx, cy, rx, ry), f)
    return out


def ring(h: int, w: int, cx: float, cy: float, r_out: float, r_in: float,
         a0: float = 0.0, a1: float = 360.0) -> np.ndarray:
    """Annulus / arc.  Angles in degrees, 0 = +x, clockwise positive (screen y down).

    ``a0 == a1`` is a full circle; otherwise the arc sweeps from ``a0`` to ``a1``
    the short way round, so a negative span (e.g. -90 to 90) works as expected.
    """
    yy, xx = grid(h, w)
    dx, dy = xx - cx, yy - cy
    d = np.sqrt(dx * dx + dy * dy)
    ang = np.degrees(np.arctan2(dy, dx))
    span = (a1 - a0) % 360.0
    if span == 0.0:
        inside_ang = np.ones_like(ang, dtype=bool)
    else:
        inside_ang = ((ang - a0) % 360.0) <= span
    m = (d <= r_out) & (d >= r_in) & inside_ang
    return m.astype(np.float32)


def arc_stroke(h: int, w: int, cx: float, cy: float, r: float, width: float,
               a0: float, a1: float) -> np.ndarray:
    """A stroked arc, for gauges, rings and chevrons."""
    return ring(h, w, cx, cy, r + width / 2.0, max(0.0, r - width / 2.0), a0, a1)


def chevron(h: int, w: int, cx: float, cy: float, size: float, width: float,
            angle: float = 0.0, down: bool = False) -> np.ndarray:
    """Up or down chevron.  angle rotates it; used for DEP-19/21 and prompts."""
    a = math.radians(angle)
    dx, dy = math.cos(a), math.sin(a)
    px, py = -dy, dx  # perpendicular
    s = size
    if not down:
        tip = (cx, cy - s / 2)
        l = (cx - s / 2, cy + s / 2)
        r = (cx + s / 2, cy + s / 2)
    else:
        tip = (cx, cy + s / 2)
        l = (cx - s / 2, cy - s / 2)
        r = (cx + s / 2, cy - s / 2)
    rot = [(x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a))
           for x, y in (tip, l, r)]
    cx2, cy2 = cx + px * 0, cy + py * 0
    rot = [(x - cx2 + cx, y - cy2 + cy) for x, y in rot]
    return np.maximum(capsule(h, w, rot[0][0], rot[0][1], rot[1][0], rot[1][1], width / 2),
                      capsule(h, w, rot[0][0], rot[0][1], rot[2][0], rot[2][1], width / 2))


def triangle(h: int, w: int, pts) -> np.ndarray:
    return polygon(h, w, pts)


def star(h: int, w: int, cx: float, cy: float, r_out: float, r_in: float,
         points: int = 5, rot: float = -90.0) -> np.ndarray:
    """Spiked seal / wax stamp / accent.  ICO and CDX stamps use this."""
    pts = []
    for i in range(points * 2):
        ang = math.radians(rot + i * 180.0 / points)
        r = r_out if i % 2 == 0 else r_in
        pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    return polygon(h, w, pts)


def teardrop(h: int, w: int, cx: float, cy: float, r: float, angle: float = 90.0) -> np.ndarray:
    """Saliva, mucus, droplet."""
    return ellipse(h, w, cx, cy, r, r * 1.25, rot=angle)


def blob(h: int, w: int, cx: float, cy: float, r: float, seed: int, lobes: int = 5,
         rough: float = 0.18, squash: float = 1.0, rot: float = 0.0) -> np.ndarray:
    """Irregular organic mass from a smoothly modulated polar radius.

    ``lobes`` is the number of *harmonics*, not bumps.  The radius is built as a
    truncated Fourier series, so the silhouette stays rounded: a plain cosine sum
    with one term per bump produces stars and flowers, which is what tumors and
    sacs must not look like.  Harmonics 1..3 carry most of the shape; 4..lobes add
    only fine irregularity.
    """
    rng = np.random.default_rng(seed)
    n = max(1, int(lobes))
    amp = np.zeros(n + 1, dtype=np.float32)
    amp[0] = 1.0
    for k in range(1, n + 1):
        amp[k] = rng.uniform(-rough, rough) * (0.35 ** (k - 1)) * (1.0 if k <= 3 else 0.5)
    phase = rng.random(n + 1).astype(np.float32) * (2 * math.pi)
    reach = r * (1.0 + float(np.abs(amp).sum()) + 0.05) + 3.0
    cxs, cys = cx * SS, cy * SS
    cr, sr = math.cos(-math.radians(rot)), math.sin(-math.radians(rot))
    out = np.zeros((h, w), dtype=np.float32)

    def f(yy, xx):
        dx, dy = xx - cxs, yy - cys
        ux, uy = dx * cr - dy * sr, (dx * sr + dy * cr) / max(0.2, squash)
        d = np.sqrt(ux * ux + uy * uy) / SS
        ang = np.arctan2(uy, ux)
        prof = np.full_like(ang, amp[0])
        for k in range(1, n + 1):
            prof = prof + amp[k] * np.cos(k * ang + phase[k])
        return np.clip((r * prof - d) / 1.4 + 0.5, 0.0, 1.0).astype(np.float32)

    _fill(out, _bb(cx, cy, reach, reach * max(0.2, squash) + reach * 0.5), f)
    return out


# --------------------------------------------------------------------------- noise
def value_noise(h: int, w: int, cell: float, seed: int, octaves: int = 3) -> np.ndarray:
    """Tileable-ish smooth noise 0..1.  The base of every organic breakup."""
    rng = np.random.default_rng(seed)
    total = np.zeros((h, w), dtype=np.float32)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        c = max(2.0, cell / (2 ** o))
        gh, gw = max(2, int(h / c) + 3), max(2, int(w / c) + 3)
        g = rng.random((gh, gw)).astype(np.float32)
        # bilinear upsample
        yi = np.linspace(0, gh - 1, h)
        xi = np.linspace(0, gw - 1, w)
        y0 = np.floor(yi).astype(int); x0 = np.floor(xi).astype(int)
        y1 = np.minimum(y0 + 1, gh - 1); x1 = np.minimum(x0 + 1, gw - 1)
        ty = (yi - y0)[:, None]; tx = (xi - x0)[None, :]
        ty = ty * ty * (3 - 2 * ty); tx = tx * tx * (3 - 2 * tx)
        g00 = g[np.ix_(y0, x0)]; g01 = g[np.ix_(y0, x1)]
        g10 = g[np.ix_(y1, x0)]; g11 = g[np.ix_(y1, x1)]
        v = (g00 * (1 - tx) + g01 * tx) * (1 - ty) + (g10 * (1 - tx) + g11 * tx) * ty
        total += amp * v
        norm += amp
        amp *= 0.5
    t = total / norm
    lo, hi = np.percentile(t, 2), np.percentile(t, 98)
    return np.clip((t - lo) / max(hi - lo, 1e-6), 0.0, 1.0)


def fbm(h: int, w: int, seed: int, cell: float = 48.0, octaves: int = 5) -> np.ndarray:
    return value_noise(h, w, cell, seed, octaves)


# --------------------------------------------------------------------------- morphology
def blur(a: np.ndarray, radius: float) -> np.ndarray:
    """Three box passes ~= gaussian.  Cheap, and all we need for soft masks."""
    r = int(round(radius / 1.7))
    if r <= 0:
        return a.astype(np.float32)
    out = a.astype(np.float32)
    for _ in range(3):
        for axis in (0, 1):
            pad = [(0, 0)] * out.ndim
            pad[axis] = (r + 1, r)
            c = np.cumsum(np.pad(out, pad, mode="edge"), axis=axis, dtype=np.float64)
            n = c.shape[axis]
            hi = np.take(c, np.arange(2 * r + 1, n), axis=axis)
            lo = np.take(c, np.arange(0, n - 2 * r - 1), axis=axis)
            out = ((hi - lo) / (2 * r + 1)).astype(np.float32)
    return out


def dilate(a: np.ndarray, r: float) -> np.ndarray:
    r = int(round(r))
    if r <= 0:
        return a
    m = a.copy()
    for d in range(1, r + 1):
        m = np.maximum(m, np.roll(a, d, axis=0))
        m = np.maximum(m, np.roll(a, -d, axis=0))
        m = np.maximum(m, np.roll(a, d, axis=1))
        m = np.maximum(m, np.roll(a, -d, axis=1))
    return m


def erode(a: np.ndarray, r: float) -> np.ndarray:
    r = int(round(r))
    if r <= 0:
        return a
    p = np.pad(a, r, mode="edge")
    m = p.copy()
    for d in range(1, r + 1):
        m = np.minimum(m, np.roll(p, d, axis=0))
        m = np.minimum(m, np.roll(p, -d, axis=0))
        m = np.minimum(m, np.roll(p, d, axis=1))
        m = np.minimum(m, np.roll(p, -d, axis=1))
    return m[r:-r, r:-r]


def outline(a: np.ndarray, width: float) -> np.ndarray:
    """A keyline band just outside the silhouette: the style's thick dark rim."""
    return np.clip(dilate(a, width) - a, 0.0, 1.0)


def inner_edge(a: np.ndarray, width: float) -> np.ndarray:
    """A band just inside the silhouette, for interior contour lines."""
    return np.clip(a - erode(a, width), 0.0, 1.0)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / np.maximum(np.asarray(e1 - e0, dtype=np.float32), 1e-6), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def roughen(a: np.ndarray, noise: np.ndarray, amp: float, soft: float = 1.2) -> np.ndarray:
    """Break a clean silhouette with noise so shapes read as organic, not vector.

    The result is re-thresholded against the original mask so noise can only eat
    into the shape, never spray new disconnected pixels outside it.  Without that
    clamp a large ``amp`` produces speckled debris around the silhouette, which
    reads as dirt on the alpha channel rather than as a ragged edge.
    """
    if amp <= 0.0:
        return a
    s = blur(a, soft)
    thr = 0.5 + (noise - 0.5) * amp
    out = smoothstep(thr - 0.08, thr + 0.08, s)
    # confine to the dilated original: erode the outer boundary, never add
    reach = max(1, int(round(amp * 2.0)))
    confined = dilate(a, reach)
    return np.clip(out * confined, 0.0, 1.0).astype(np.float32)


# --------------------------------------------------------------------------- composition
def union(*masks: np.ndarray) -> np.ndarray:
    out = np.zeros_like(masks[0], dtype=np.float32)
    for m in masks:
        out = np.maximum(out, m)
    return out


def intersect(*masks: np.ndarray) -> np.ndarray:
    out = np.ones_like(masks[0], dtype=np.float32)
    for m in masks:
        out = np.minimum(out, m)
    return out


def subtract(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    return np.clip(a - b, 0.0, 1.0).astype(np.float32)


def centroid(m: np.ndarray) -> tuple[float, float]:
    """Coverage-weighted centre of a mask, as (x, y).  Returns (0, 0) if empty."""
    total = float(m.sum())
    if total < 1e-6:
        return 0.0, 0.0
    yy, xx = np.mgrid[0:m.shape[0], 0:m.shape[1]]
    return float((m * xx).sum() / total), float((m * yy).sum() / total)


def mask_of(a: np.ndarray, thresh: float = 0.5) -> np.ndarray:
    return (a >= thresh).astype(np.float32)


def soften(a: np.ndarray, radius: float = 0.8) -> np.ndarray:
    """A crisp mask turned back into a soft coverage ramp, for glows and fades."""
    if radius <= 0:
        return a
    m = np.clip((a - 0.5) / max(radius, 1e-3) + 0.5, 0.0, 1.0)
    return blur(m, 1.0)
