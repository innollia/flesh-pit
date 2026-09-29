"""The look: low-key, grim, gothic.

A first pass at this set came out cartoony, and the cause was mechanical rather
than artistic -- four habits of the default shading, each of which is now fixed
here and in ``paint.shade_fill``:

  1. bright saturated mid-tones   -> values crushed down, saturation pulled back
  2. large soft specular blobs    -> specular tightened and dimmed
  3. clean even outlines          -> keylines thickened and made uneven
  4. flat frontal light           -> most of every form sits in shadow, and only
                                     the lit edge carries the read

`grade` is applied once at save time so the whole set shares one response curve
instead of each group re-deciding it.  Two rules it has to respect:

  * normal maps and roughness maps are LINEAR data, not pictures.  They are never
    graded; ``build.save(..., grade=False)`` is the only correct call for them.
  * white masks (STO-02) are data too, and pass through untouched.

Split toning is the other half of the look: warm flesh in the highlights, a cold
green-blue in the shadows.  That contrast is what stops a red world from
reading as a red cartoon, and it is the same trick gothic painting uses.
"""

from __future__ import annotations

import numpy as np

from .palette import hex_rgb, mix

# shadow / highlight split-tone targets
SHADOW_TINT = "#141c1e"      # cold blue-green, pushes toward dirty and wet
HIGHLIGHT_TINT = "#f0d8b0"   # warm bone, keeps flesh from going magenta

# the grade.  These are the knobs the whole set is tuned against.
LIFT = 0.012        # blacks are lifted slightly: not crushed to pure black
GAMMA = 1.28        # >1 darkens mid-tones, the main low-key move
SATURATION = 0.72   # pull saturation back; full saturation reads as cartoon
SPLIT = 0.30        # how far shadows and highlights are tinted
CONTRAST = 1.12     # gentle S-curve on top of the gamma
VIGNETTE = 0.34     # edge falloff, keeps focus centre-frame
GRAIN = 0.020       # fine film grain so flats never read as vector


def grade(rgba: np.ndarray, *, seed: int = 0, strength: float = 1.0,
          vignette: float | None = None) -> np.ndarray:
    """Apply the house look to a float RGBA image in 0..1.  Alpha is preserved."""
    arr = np.asarray(rgba, dtype=np.float32)
    if arr.ndim != 3 or arr.shape[2] != 4:
        raise ValueError("grade expects an (h, w, 4) RGBA array")
    rgb, alpha = arr[..., :3], arr[..., 3:4]
    h, w = alpha.shape[:2]
    k = float(np.clip(strength, 0.0, 1.0))

    # ---- value: gamma, then a gentle S-curve for contrast
    v = np.clip(rgb, 0.0, 1.0) ** (1.0 + (GAMMA - 1.0) * k)
    v = np.clip((v - 0.5) * (1.0 + (CONTRAST - 1.0) * k) + 0.5, 0.0, 1.0)
    v = LIFT * k + v * (1.0 - LIFT * k)

    # ---- saturation
    luma = (v * np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)).sum(axis=-1, keepdims=True)
    sat = 1.0 + (SATURATION - 1.0) * k
    v = luma + (v - luma) * sat

    # ---- split toning: cold shadows, warm highlights
    lum2 = np.clip((v.max(axis=-1, keepdims=True) + v.min(axis=-1, keepdims=True)) * 0.5, 0, 1)
    shadow_w = np.clip(1.0 - lum2 * 2.0, 0.0, 1.0) * SPLIT * k
    high_w = np.clip((lum2 - 0.5) * 2.0, 0.0, 1.0) * SPLIT * k * 0.7
    v = v * (1.0 - shadow_w - high_w) + hex_rgb(SHADOW_TINT) * shadow_w \
        + hex_rgb(HIGHLIGHT_TINT) * high_w

    # ---- vignette
    vig = vignette if vignette is not None else VIGNETTE
    if vig > 0.0:
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        dx = (xx / max(1, w - 1) - 0.5) * 2.0
        dy = (yy / max(1, h - 1) - 0.5) * 2.0
        d = np.clip(np.sqrt(dx * dx + dy * dy) / 1.4142, 0.0, 1.0) ** 1.7
        v = v * (1.0 - d * vig * k)[..., None]

    # ---- grain, scaled by inverse luminance so it sits in the mid-tones
    if GRAIN > 0.0:
        rng = np.random.default_rng(seed or 1)
        g = rng.normal(0.0, GRAIN * k, (h, w, 1)).astype(np.float32)
        v = v + g * (0.35 + 0.65 * (1.0 - np.abs(luma * 2.0 - 1.0)))

    return np.clip(np.dstack([np.clip(v, 0.0, 1.0), alpha]), 0.0, 1.0).astype(np.float32)


def to_image(rgba: np.ndarray, seed: int = 0, strength: float = 1.0, **kw):
    """Grade and convert to a PIL RGBA image."""
    from PIL import Image
    a = np.clip(grade(rgba, seed=seed, strength=strength, **kw), 0.0, 1.0)
    return Image.fromarray(
        np.ascontiguousarray((a * 255.0 + 0.5).astype(np.uint8)), "RGBA")
