# -*- coding: utf-8 -*-
"""Bakes the tissue textures of the biome tissues (docs/spec/02-world-tissue.md 1-1).

    python -X utf8 tools/build_biome_textures.py

Writes 128 px tileable PNGs next to the other tissue textures:
cartilage (rib vault), cloth wad (clothing wads), hair mat (hair thicket).
Fat (fat caves) reuses the existing tex_fat_128.png.
Everything is periodic over the tile so the terrain's planar UVs never seam.
"""
import math
import os

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "game", "addons", "flesh_dig_kit", "textures")
N = 128
rng = np.random.default_rng(20261030)
yy, xx = np.mgrid[0:N, 0:N].astype(np.float64) / N


def periodic_noise(octaves=4, base=3, seed=0):
    """Sum of random integer-frequency waves: tiles exactly over 0..1."""
    r = np.random.default_rng(seed)
    out = np.zeros((N, N))
    amp = 1.0
    for o in range(octaves):
        f = base * (2 ** o)
        for _ in range(6):
            fx, fy = r.integers(-f, f + 1, size=2)
            ph = r.uniform(0, math.tau)
            out += amp * np.sin(math.tau * (fx * xx + fy * yy) + ph)
        amp *= 0.5
    out -= out.min()
    return out / max(out.max(), 1e-9)


def save(name, rgb):
    img = Image.fromarray(np.clip(rgb * 255.0, 0, 255).astype(np.uint8), "RGB")
    img.save(os.path.join(OUT, name))
    print("wrote", name)


def cartilage():
    # pale blue-white gristle, ring striations bent by noise, faint pink vessels
    n = periodic_noise(4, 2, 11)
    rings = 0.5 + 0.5 * np.sin(math.tau * (yy * 6 + n * 1.6))
    vessels = periodic_noise(3, 3, 12)
    vein = np.clip(1.0 - np.abs(vessels - 0.5) * 22.0, 0, 1) * 0.55
    base = np.stack([0.80 + 0.06 * rings, 0.82 + 0.05 * rings, 0.86 + 0.07 * rings], -1)
    base *= (0.82 + 0.18 * n)[..., None]
    pink = np.array([0.78, 0.42, 0.48])
    rgb = base * (1 - vein[..., None]) + pink * vein[..., None]
    return rgb


def cloth():
    # compressed clothing strips: bands of faded fabric colours folded by
    # noise, a weave stipple, blood-brown matting in the creases
    fold = periodic_noise(3, 2, 21)
    band = (np.floor((yy + fold * 0.45) * 9) % 9).astype(int)
    palette = np.array([
        [0.36, 0.40, 0.52], [0.62, 0.58, 0.48], [0.50, 0.16, 0.18], [0.22, 0.24, 0.26],
        [0.70, 0.66, 0.60], [0.30, 0.42, 0.34], [0.56, 0.44, 0.30], [0.42, 0.30, 0.44], [0.66, 0.62, 0.30],
    ])
    rgb = palette[band]
    weave = 0.88 + 0.12 * (np.sin(math.tau * xx * 64) * np.sin(math.tau * yy * 64) > 0)
    rgb = rgb * weave[..., None]
    edge = np.abs(((yy + fold * 0.45) * 9) % 1.0 - 0.5) * 2.0
    crease = np.clip((edge - 0.75) * 4.0, 0, 1)
    grime = periodic_noise(4, 3, 22)
    mat = np.clip(crease + (grime - 0.6) * 1.5, 0, 1)[..., None]
    blood = np.array([0.30, 0.07, 0.07])
    return rgb * (1 - mat) + blood * mat


def hair():
    # dense dark strands combed by a flow field, pink scalp gaps between clumps
    flow = periodic_noise(3, 2, 31)
    strands = 0.5 + 0.5 * np.sin(math.tau * (xx * 22 + flow * 3.0) + 4.0 * np.sin(math.tau * yy * 2))
    fine = 0.5 + 0.5 * np.sin(math.tau * (xx * 61 + flow * 5.0))
    clump = periodic_noise(4, 2, 32)
    scalp = np.clip((0.32 - clump) * 6.0, 0, 1)[..., None]
    dark = np.array([0.07, 0.05, 0.05])
    lit = np.array([0.24, 0.17, 0.13])
    s = (strands * 0.6 + fine * 0.4)[..., None]
    rgb = dark * (1 - s) + lit * s
    skin = np.array([0.66, 0.36, 0.36]) * (0.8 + 0.2 * clump[..., None])
    return rgb * (1 - scalp) + skin * scalp


if __name__ == "__main__":
    save("tissue_cartilage_128.png", cartilage())
    save("tissue_cloth_128.png", cloth())
    save("tissue_hair_128.png", hair())
