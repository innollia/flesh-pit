"""Seamless numpy noise + small pixel helpers.

Everything here is periodic so that world textures tile. A field is tileable
when its lattice has an integer number of cells across the image and the
indices wrap, which is what ``value_noise`` and ``worley`` do.
"""

from __future__ import annotations

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# ---------------------------------------------------------------- noise ----


def _lattice(rng: np.random.Generator, n: int) -> np.ndarray:
    return rng.random((n, n), dtype=np.float32)


def _smooth(t: np.ndarray) -> np.ndarray:
    return t * t * (3.0 - 2.0 * t)


def value_noise(h: int, w: int, freq: int, rng, aniso=(1.0, 1.0)) -> np.ndarray:
    """Tileable bilinear value noise. ``freq`` is cells across the tile.

    ``aniso`` scales the cell count per axis, which is how the fibrous
    tissues get their grain direction. One lattice covers both axes, so the
    two cell counts are independent but the lookup stays a single array.
    """
    fy = max(1, int(round(freq * aniso[0])))
    fx = max(1, int(round(freq * aniso[1])))
    lat = rng.random((fy, fx), dtype=np.float32)

    xs = np.linspace(0, fx, w, endpoint=False, dtype=np.float32)
    ys = np.linspace(0, fy, h, endpoint=False, dtype=np.float32)
    x0 = np.floor(xs).astype(np.int32) % fx
    y0 = np.floor(ys).astype(np.int32) % fy
    x1 = (x0 + 1) % fx
    y1 = (y0 + 1) % fy
    tx = _smooth(xs - np.floor(xs))[None, :]
    ty = _smooth(ys - np.floor(ys))[:, None]

    a = lat[np.ix_(y0, x0)]
    b = lat[np.ix_(y0, x1)]
    c = lat[np.ix_(y1, x0)]
    d = lat[np.ix_(y1, x1)]
    top = a + (b - a) * tx
    bot = c + (d - c) * tx
    return top + (bot - top) * ty


def fbm(h: int, w: int, base: int, octaves: int, rng,
        gain: float = 0.5, lac: int = 2, aniso=(1.0, 1.0)) -> np.ndarray:
    """Fractal sum of tileable value noise, normalised to 0..1."""
    total = np.zeros((h, w), dtype=np.float32)
    amp = 1.0
    norm = 0.0
    freq = max(1, base)
    for _ in range(max(1, octaves)):
        total += amp * value_noise(h, w, freq, rng, aniso)
        norm += amp
        amp *= gain
        freq *= lac
    return total / (norm or 1.0)


def worley(h: int, w: int, cells: int, rng, jitter: float = 0.85) -> np.ndarray:
    """Tileable cellular noise. Returns distance to nearest feature, 0..1."""
    px = (rng.random((cells, cells), dtype=np.float32) - 0.5) * jitter
    py = (rng.random((cells, cells), dtype=np.float32) - 0.5) * jitter

    xs = np.arange(w, dtype=np.float32) * cells / max(1, w)
    ys = np.arange(h, dtype=np.float32) * cells / max(1, h)
    x0 = np.floor(xs).astype(np.int32)
    y0 = np.floor(ys).astype(np.int32)

    best = np.full((h, w), 8.0, dtype=np.float32)
    for dy in (0, 1):
        for dx in (0, 1):
            cy = ((y0 + dy) % cells)[:, None]      # (h, 1)
            cx = ((x0 + dx) % cells)[None, :]      # (1, w)
            fxp = cx + 0.5 + px[cy, cx]
            fyp = (y0 + dy)[:, None] + 0.5 + py[cy, cx]
            d = np.hypot(xs[None, :] - fxp, ys[:, None] - fyp)
            best = np.minimum(best, d.astype(np.float32))
    return np.clip(best / 1.6, 0.0, 1.0).astype(np.float32)


def ridged(h: int, w: int, base: int, octaves: int, rng) -> np.ndarray:
    n = fbm(h, w, base, octaves, rng)
    return (1.0 - np.abs(n * 2.0 - 1.0)).astype(np.float32)


def upscale(a: np.ndarray, h: int, w: int) -> np.ndarray:
    """Bilinear resize of a float32 field to (h, w)."""
    if a.shape[0] == h and a.shape[1] == w:
        return a.astype(np.float32)
    if a.ndim == 2:
        return np.array(Image.fromarray(a.astype(np.float32), "F")
                        .resize((w, h), Image.BILINEAR), np.float32)
    chans = [np.array(Image.fromarray(a[..., i].astype(np.float32), "F")
                      .resize((w, h), Image.BILINEAR), np.float32)
             for i in range(a.shape[2])]
    return np.stack(chans, -1)


THRESH = 300_000


def adaptive(h: int, w: int, fn) -> np.ndarray:
    """Run ``fn(h, w)`` at a cheaper resolution, then scale up.

    fbm and worley are the cost drivers and they are all low frequency, so
    evaluating them below ~300k samples and resampling is visually free.
    """
    if h * w <= THRESH:
        return fn(h, w).astype(np.float32)
    s = (THRESH / float(h * w)) ** 0.5
    small = fn(max(8, int(h * s)), max(8, int(w * s)))
    return upscale(small, h, w)


# ------------------------------------------------------------ gradients ----


def linear_grad(h: int, w: int, c0, c1, angle: float = 90.0) -> np.ndarray:
    """Directional 2-stop gradient, h x w x 3 float."""
    rad = np.deg2rad(angle)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    xx /= max(1, w - 1)
    yy /= max(1, h - 1)
    t = xx * np.cos(rad) + yy * np.sin(rad)
    t = (t - t.min()) / ((t.max() - t.min()) or 1.0)
    c0 = np.array(c0, dtype=np.float32)
    c1 = np.array(c1, dtype=np.float32)
    return c0[None, None, :] + (c1 - c0)[None, None, :] * t[:, :, None]


def radial_mask(h: int, w: int, cx: float = 0.5, cy: float = 0.5,
                r: float = 0.5, falloff: float = 1.6, aspect: float = 1.0) -> np.ndarray:
    """Soft radial field, 1 at the centre going to 0 at ``r``."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx = (xx / max(1, w - 1) - cx) * 2.0
    ny = (yy / max(1, h - 1) - cy) * 2.0 * aspect
    d = np.sqrt(nx * nx + ny * ny) / max(1e-6, r * 2.0)
    return np.clip(1.0 - d, 0.0, 1.0) ** falloff


def edge_mask(h: int, w: int, power: float = 1.4) -> np.ndarray:
    """1 at the border, 0 in the middle. Used for creeping growth."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx = np.minimum(xx, w - 1 - xx) / (w * 0.5)
    ny = np.minimum(yy, h - 1 - yy) / (h * 0.5)
    d = np.minimum(nx, ny)
    return np.clip(1.0 - d, 0.0, 1.0) ** power


def ring(h: int, w: int, r: float, thickness: float, cx=0.5, cy=0.5) -> np.ndarray:
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx = (xx / max(1, w - 1) - cx) * 2.0
    ny = (yy / max(1, h - 1) - cy) * 2.0
    d = np.sqrt(nx * nx + ny * ny)
    return np.clip(1.0 - np.abs(d - r) / max(1e-6, thickness), 0.0, 1.0)


# ------------------------------------------------------------- surfaces ----


def sobel_normal(height: np.ndarray, strength: float = 2.4) -> np.ndarray:
    """Height field -> tangent space normal map, h x w x 3 uint8."""
    h = height.astype(np.float32)
    gy, gx = np.gradient(h)
    nx = -gx * strength
    ny = -gy * strength
    nz = np.ones_like(nx)
    n = np.stack([nx, ny, nz], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return ((n * 0.5 + 0.5) * 255.0 + 0.5).astype(np.uint8)


def blur(a: np.ndarray, r: float) -> np.ndarray:
    """Separable box blur, works on HxW or HxWxC float arrays."""
    if r <= 0:
        return a
    k = int(r) * 2 + 1
    arr = a.astype(np.float32)
    if arr.ndim == 2:
        arr = arr[:, :, None]
        squeeze = True
    else:
        squeeze = False
    pad = np.pad(arr, ((r, r), (r, r), (0, 0)), mode="edge")
    cs = np.cumsum(pad, axis=0)
    arr = (cs[k:, :, :] - cs[:-k, :, :]) / k
    cs = np.cumsum(arr, axis=1)
    arr = (cs[:, k:, :] - cs[:, :-k, :]) / k
    arr = arr[r:-r if r else None, r:-r if r else None, :]
    return arr[:, :, 0] if squeeze else arr


def to_img(a: np.ndarray) -> Image.Image:
    a = np.clip(a, 0, 255).astype(np.uint8)
    if a.ndim == 2:
        return Image.fromarray(a, "L")
    if a.shape[2] == 3:
        return Image.fromarray(a, "RGB")
    return Image.fromarray(a, "RGBA")


def rounded_rect(w: int, h: int, r: int, inset: int = 0) -> np.ndarray:
    """Boolean mask, rounded rectangle with a soft 1px feather."""
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([inset, inset, w - 1 - inset, h - 1 - inset],
                        radius=max(0, r), fill=255)
    return np.array(m, dtype=np.float32) / 255.0


def load_font(size: int, bold: bool = True, italic: bool = False):
    """Best-effort system font. Generation-time only, never shipped."""
    from PIL import ImageFont
    names = []
    if bold:
        names += ["seguibl.ttf", "segoeuib.ttf", "arialbd.ttf", "verdanab.ttf"]
    else:
        names += ["segoeui.ttf", "arial.ttf", "verdana.ttf"]
    if italic:
        names = [n.replace(".ttf", "i.ttf") for n in names] + names
    for n in names:
        try:
            return ImageFont.truetype("C:/Windows/Fonts/" + n, size)
        except Exception:
            continue
    try:
        return ImageFont.load_default(size)
    except Exception:
        return ImageFont.load_default()


def paste_mask(base: np.ndarray, colour, mask: np.ndarray) -> np.ndarray:
    """Alpha-composite a flat colour onto an RGB base using ``mask`` 0..1."""
    c = np.array(colour, dtype=np.float32)[None, None, :]
    m = np.clip(mask, 0.0, 1.0)[:, :, None]
    return base * (1.0 - m) + c * m


def mul_alpha(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    out = np.zeros(rgb.shape[:2] + (4,), dtype=np.uint8)
    out[:, :, :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    out[:, :, 3] = (np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    return out


def pil_round(img: Image.Image, radius: int) -> Image.Image:
    return img.filter(ImageFilter.GaussianBlur(max(0.1, radius / 3.0)))
