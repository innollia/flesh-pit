"""Bakes the tissue textures for the flesh terrain (docs/asset-list.md TIS-01..05,
docs/spec/02-world-tissue.md 3). Procedural, tileable, deterministic, PS1 tone
(128 px, few colours, light ordered dither). Writes into
addons/flesh_dig_kit/textures/tissue_*.png.

Usage (from game/):  python -X utf8 tools/bake_tissue_textures.py
"""
from __future__ import annotations

import pathlib
import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "addons" / "flesh_dig_kit" / "textures"


def pnoise(size: int, scale: float, seed: int) -> np.ndarray:
    """Tileable band-limited noise in 0..1 (random spectrum, FFT)."""
    r = np.random.default_rng(seed)
    f = np.fft.fftfreq(size)[:, None] ** 2 + np.fft.fftfreq(size)[None, :] ** 2
    f = np.sqrt(f) * size
    amp = np.exp(-((f - scale) ** 2) / (2 * (scale * 0.5 + 0.5) ** 2))
    amp[0, 0] = 0
    spec = amp * np.exp(2j * np.pi * r.random((size, size)))
    n = np.real(np.fft.ifft2(spec))
    n = (n - n.min()) / (n.max() - n.min() + 1e-9)
    return n


def blobs(size: int, count: int, rmin: float, rmax: float, seed: int) -> np.ndarray:
    """Tileable soft puffy bumps (max of gaussian domes on a torus)."""
    r = np.random.default_rng(seed)
    y, x = np.mgrid[0:size, 0:size].astype(float)
    out = np.zeros((size, size))
    for _ in range(count):
        cx, cy = r.random() * size, r.random() * size
        rad = rmin + r.random() * (rmax - rmin)
        dx = np.minimum(np.abs(x - cx), size - np.abs(x - cx))
        dy = np.minimum(np.abs(y - cy), size - np.abs(y - cy))
        d = np.sqrt(dx * dx + dy * dy) / rad
        out = np.maximum(out, np.clip(1 - d * d, 0, 1))
    return out


def ramp(t: np.ndarray, stops: list[tuple[float, tuple[int, int, int]]]) -> np.ndarray:
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,))
    xs = [s[0] for s in stops]
    for c in range(3):
        out[..., c] = np.interp(t, xs, [s[1][c] for s in stops])
    return out


def ps1(rgb: np.ndarray, levels: int = 20) -> np.ndarray:
    bayer = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0 - 0.5
    size = rgb.shape[0]
    d = np.tile(bayer, (size // 4, size // 4))[..., None]
    step = 255.0 / (levels - 1)
    q = np.round(rgb / step + d * 0.8) * step
    return np.clip(q, 0, 255).astype(np.uint8)


def save(name: str, rgb: np.ndarray) -> None:
    Image.fromarray(ps1(rgb), "RGB").save(OUT / name)
    print("wrote", name)


def shade_from_height(h: np.ndarray, strength: float) -> np.ndarray:
    gy, gx = np.gradient(np.pad(h, 1, mode="wrap"))
    gx, gy = gx[1:-1, 1:-1], gy[1:-1, 1:-1]
    return np.clip(0.5 + (-gx * 0.7 - gy * 0.7) * strength, 0, 1)


def compressive(size: int = 128) -> np.ndarray:
    # puffy, swollen, wet pink flesh: fat round bumps with dark creases
    h = blobs(size, 60, 9, 22, 11) * 0.8 + pnoise(size, 10, 12) * 0.25
    lit = shade_from_height(h, 9.0)
    crease = np.clip(1 - h * 2.2, 0, 1) ** 2
    base = ramp(h * 0.6 + lit * 0.4, [(0, (120, 38, 52)), (0.45, (196, 92, 104)), (0.8, (232, 146, 150)), (1, (250, 196, 196))])
    base *= (1 - crease * 0.55)[..., None]
    wet = np.clip((lit - 0.78) * 5, 0, 1) * (pnoise(size, 16, 13) > 0.55)
    base += wet[..., None] * np.array([55, 50, 50])
    return base


def contractile(size: int = 128) -> np.ndarray:
    # dark red-brown muscle: tight bundles of fibres, warped, knotted
    y, x = np.mgrid[0:size, 0:size].astype(float) / size
    warp = pnoise(size, 3, 21) * 0.9
    fib = 0.5 + 0.5 * np.sin((y + warp * 0.35) * np.pi * 2 * 22 + np.sin(x * np.pi * 2 * 2) * 1.3)
    bundles = 0.5 + 0.5 * np.sin((y + warp * 0.35) * np.pi * 2 * 5)
    h = fib * 0.45 + bundles * 0.35 + pnoise(size, 14, 22) * 0.2
    lit = shade_from_height(h, 6.0)
    base = ramp(h * 0.55 + lit * 0.45, [(0, (46, 12, 14)), (0.4, (98, 30, 28)), (0.75, (140, 58, 46)), (1, (178, 96, 78))])
    sheen = np.clip((lit - 0.7) * 4, 0, 1) * 0.5
    base += sheen[..., None] * np.array([60, 40, 40])
    return base


def nerve(size: int = 128) -> np.ndarray:
    # red flesh packed with yellow nerve roots (the most saturated colour)
    n1 = pnoise(size, 6, 31)
    n2 = pnoise(size, 11, 32)
    ridge = 1 - np.abs(n1 - 0.5) * 2
    ridge2 = 1 - np.abs(n2 - 0.5) * 2
    roots = np.clip((np.maximum(ridge ** 10, ridge2 ** 14 * 0.9) - 0.25) * 1.6, 0, 1)
    flesh = ramp(pnoise(size, 9, 33), [(0, (92, 16, 22)), (0.6, (150, 36, 38)), (1, (186, 64, 58))])
    yellow = ramp(roots, [(0, (200, 150, 30)), (1, (255, 226, 70))])
    lit = shade_from_height(roots, 5.0)
    out = flesh * (1 - roots[..., None]) + yellow * roots[..., None]
    out *= (0.75 + lit * 0.4)[..., None]
    return out


def membrane(size: int = 128) -> np.ndarray:
    # milky, pale, tough sheet: whitish with a faint web of stretched fibres
    n = pnoise(size, 4, 41)
    web = 1 - np.abs(pnoise(size, 9, 42) - 0.5) * 2
    web = np.clip((web ** 8 - 0.2) * 1.4, 0, 1)
    base = ramp(n, [(0, (178, 160, 160)), (0.5, (214, 200, 196)), (1, (236, 228, 222))])
    base -= web[..., None] * np.array([40, 52, 44])
    vein = np.clip((1 - np.abs(pnoise(size, 3, 43) - 0.5) * 2) ** 30 * 2, 0, 1)
    base -= vein[..., None] * np.array([10, 70, 60])
    return base


def melted(size: int = 64) -> np.ndarray:
    # sprayed flesh: smooth, set, greyish, a few frozen bubble pits
    n = pnoise(size, 3, 51)
    base = ramp(n, [(0, (104, 102, 98)), (1, (150, 146, 138))])
    pits = blobs(size, 14, 1.5, 3.5, 52)
    base -= (pits ** 2)[..., None] * np.array([46, 46, 42])
    gloss = np.clip((pnoise(size, 5, 53) - 0.72) * 5, 0, 1)
    base += gloss[..., None] * np.array([40, 40, 40])
    return base


if __name__ == "__main__":
    save("tissue_compressive_128.png", compressive())
    save("tissue_contractile_128.png", contractile())
    save("tissue_nerve_128.png", nerve())
    save("tissue_membrane_128.png", membrane())
    save("tissue_melted_64.png", melted())