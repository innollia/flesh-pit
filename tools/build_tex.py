"""TEX: MVP world textures.

MVP scope: TEX-B01-A/N/R (albedo, normal, roughness for the surface band),
TEX-106 (nerve cluster detail), TEX-301 (organic noise base), TEX-303 (grunge
mask), TEX-304 (flesh chunk particle).

The B01 set is the first thing the player touches, so it carries the surface
identity: wet pink skin with follicle pits and subsurface reddening.

One normal-map convention, enforced in ``B.normal_from_height``: OpenGL +Y up.
Never mix conventions within the set.

Rows: docs/asset-list.md section 14.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

from fleshkit import build as B
from fleshkit import paint as P
from fleshkit import shapes as S
from fleshkit import widgets as W
from fleshkit.palette import BAND_PALETTE, Deep, Flesh, hex_rgb, mix, ramp

FLESH = "textures/flesh"
TISSUE = "textures/tissue"
UTIL = "textures/utility"
VFX = "vfx"


def hex3(c) -> np.ndarray:
    return hex_rgb(c)[:3]


def save_rgb(arr: np.ndarray, rel: str, *, linear: bool = False) -> None:
    a = np.clip(arr, 0.0, 1.0)
    if a.ndim == 2:
        a = np.dstack([a, a, a])
    if a.shape[2] == 3:
        a = np.dstack([a, np.ones_like(a[..., :1])])
    img = Image.fromarray(np.ascontiguousarray((a * 255.0 + 0.5).astype(np.uint8)), "RGBA")
    B.save(img, rel, grade=not linear)
    if linear:
        (B.ASSETS / rel).with_suffix(".linear.txt").write_text("linear\n", encoding="utf-8")


def band_surface(size, band, seed):
    """Albedo + height for one depth band, 60-degree top-down walls.

    Returns (albedo, height, roughness).
    """
    pal = BAND_PALETTE[band]
    yy, xx = S.grid(size, size)

    # base pigment with large-scale mottling
    n_big = S.fbm(size, size, seed, cell=size * 0.35, octaves=4)
    base = mix(pal["dark"], pal["key"], 0.5 + 0.5 * n_big)

    height = np.full((size, size), 0.5, dtype=np.float32)
    rough = np.full((size, size), 0.55, dtype=np.float32)

    if band == "B01":
        # wet pink skin, follicle pits, subsurface reddening
        depth_red = S.fbm(size, size, seed + 5, cell=size * 0.12, octaves=4)
        base = mix(base, Flesh.SUB_DERMA, np.clip(depth_red - 0.45, 0, 1) * 0.5)
        base = mix(base, Flesh.SKIN_WET, np.clip(0.6 - depth_red, 0, 1) * 0.5)
        # follicle pits: small dark craters, recessed in height.
        # Drawn as one vectorised scatter rather than per-pit supersampled draws,
        # which at 2K would otherwise dominate the whole build.
        rng = np.random.default_rng(seed)
        pitm = P.pores(size, size, seed + 9, int(size * 0.55), size * 0.0028)
        base = mix(base, Flesh.GRIME, pitm * 0.7)
        height = height - pitm * 0.35
        rough = rough - 0.18 * (1.0 - pitm) + 0.2 * pitm
        # wet sheen
        base = mix(base, Flesh.SKIN_WET, P.wet_sheen(size, size, seed + 3, 0.18) * 0.4)
    elif band == "B06":
        # nerve braid: yellow mass, fibre, glow in the crevices
        # Nerve braid: yellow mass, fibre, glow in the crevices.
        # Strands follow wandering polylines rather than a straight lattice.  A
        # regular grid of fibres reads as a grid, not as nerves, and the nerve
        # band is canonically the most visually distinct band in the game.
        rng = np.random.default_rng(seed + 1)
        strands = np.zeros((size, size), dtype=np.float32)
        # two densities: thick trunks plus a fine web, so the braid has depth
        for count, wscale, lscale in ((int(size * 0.075), 1.0, 1.0),
                                      (int(size * 0.10), 0.45, 0.6)):
            for _ in range(count):
                x, y = rng.random() * size, rng.random() * size
                a = rng.random() * 2 * math.pi
                wdt = size * (0.0012 + rng.random() * 0.0022) * wscale
                for _ in range(7):
                    a += float(rng.normal(0, 0.55))
                    ln = size * (0.03 + rng.random() * 0.05) * lscale
                    x2, y2 = x + math.cos(a) * ln, y + math.sin(a) * ln
                    strands = np.maximum(strands, S.capsule(size, size, x, y, x2, y2, wdt))
                    x, y = x2, y2
        strands = S.blur(strands, max(1.0, size * 0.0015))
        base = mix(base, Deep.NERVE_MASS_LIGHT, strands * 0.7)
        base = mix(base, Flesh.nerve_base(), strands * 0.35)
        crev = S.blur(1.0 - strands, size * 0.005)
        base = mix(base, Flesh.BLOOD_DARK, crev * 0.55)
        # glow pools in the crevices: the band's identity from a distance
        base = mix(base, Flesh.nerve_glow(), np.clip(crev - 0.55, 0, 1) * 0.55)
        height = height + strands * 0.35 - crev * 0.12
        rough = rough - strands * 0.15
    else:
        base = mix(base, pal["accent"], S.fbm(size, size, seed + 2, size * 0.10, 3) * 0.2)

    # fine grain everywhere so nothing reads as vector
    grain = S.fbm(size, size, seed + 40, size * 0.02, 3)
    base = base * (0.94 + 0.12 * grain)[..., None]
    height = height + (grain - 0.5) * 0.06
    rough = np.clip(rough + (grain - 0.5) * 0.10, 0.0, 1.0)

    return np.clip(base, 0.0, 1.0), np.clip(height, 0.0, 1.0), np.clip(rough, 0.0, 1.0)


def main() -> int:
    n = 0

    # --------------------------------------------------------- TEX-B01-A/N/R
    size = 2048
    albedo, height, rough = band_surface(size, "B01", B.seed_of("TEX-B01-A"))
    p = B.fname(FLESH, "b01_surface_albedo_2k")
    B.register("TEX-B01-A", p, size, size, "MVP", "png", note="wet pink skin, follicle pits, subsurface reddening")
    save_rgb(albedo, p)
    n += 1

    nrm = B.normal_from_height(height, strength=1.8)
    p = B.fname(FLESH, "b01_surface_normal_2k")
    B.register("TEX-B01-N", p, size, size, "MVP", "png", note="OpenGL +Y up, follicle pit depth")
    save_rgb(nrm, p, linear=True)
    n += 1

    p = B.fname(FLESH, "b01_surface_roughness_2k")
    B.register("TEX-B01-R", p, size, size, "MVP", "png", note="wet skin is glossy in the raised areas, dull in the pits; LINEAR")
    save_rgb(rough, p, linear=True)
    n += 1

    # --------------------------------------------------------- TEX-106 nerve detail
    size2 = 2048
    albedo, height, _ = band_surface(size2, "B06", B.seed_of("TEX-106"))
    p = B.fname(TISSUE, "nerve_cluster_detail_2k")
    B.register("TEX-106", p, size2, size2, "MVP", "png",
               note="yellow strands, the canon nerve language, must survive close inspection")
    save_rgb(albedo, p)
    n += 1

    # --------------------------------------------------------- TEX-301 organic noise
    size3 = 1024
    noise = S.fbm(size3, size3, B.seed_of("TEX-301"), cell=size3 * 0.12, octaves=6)
    noise = np.clip((noise - 0.5) * 1.4 + 0.5, 0, 1)
    p = B.fname(UTIL, "noise_organic_1k")
    B.register("TEX-301", p, size3, size3, "MVP", "png", note="tileable organic noise, greyscale base for breakup")
    save_rgb(noise, p, linear=True)
    n += 1

    # --------------------------------------------------------- TEX-303 grunge mask
    size4 = 1024
    g1 = S.fbm(size4, size4, B.seed_of("TEX-303"), cell=size4 * 0.30, octaves=5)
    g2 = S.fbm(size4, size4, B.seed_of("TEX-303") + 9, cell=size4 * 0.08, octaves=4)
    cov = S.smoothstep(0.5, 0.85, g1) * 0.6 + S.smoothstep(0.55, 0.9, g2) * 0.4
    a = np.clip(cov, 0, 1)
    p = B.fname(UTIL, "grunge_mask_1k")
    B.register("TEX-303", p, size4, size4, "MVP", "png32", note="dirt and stain overlay, alpha only; LINEAR")
    arr = np.dstack([np.zeros_like(a), np.zeros_like(a), np.zeros_like(a), a])
    B.save_atlas(arr, p)
    n += 1

    # --------------------------------------------------------- TEX-304 flesh chunk particle
    # the thing that actually gets eaten: irregular torn chunk, red with a pale fat core
    S_ = 128
    for k in range(4):
        buf = P.Buffer(S_, S_)
        seed = B.seed_of("TEX-304") + k * 31
        chunk = S.blob(S_, S_, S_ * 0.5, S_ * 0.5, S_ * 0.40, seed, lobes=4, rough=0.30)
        # tear it: cut a couple of bites out of the edge
        for _ in range(3):
            x, y = 20 + (seed % 90), 20 + ((seed * 7) % 90)
            chunk = S.subtract(chunk, S.circle(S_, S_, x, y, S_ * 0.10))
        chunk = S.roughen(chunk, S.value_noise(S_, S_, S_ * 0.06, seed + 1, 3), 0.6, 1.2)
        buf.composite(P.shade_fill(chunk, Flesh.MUSCLE, Flesh.MUSCLE_LIGHT,
                                   Flesh.MUSCLE_DARK, S_ * 0.05), chunk)
        # pale fat core
        core = S.blob(S_, S_, S_ * 0.46, S_ * 0.48, S_ * 0.18, seed + 4, lobes=3, rough=0.2)
        core = core * chunk
        buf.composite(P.shade_fill(core, Flesh.FAT, Flesh.FAT_LIGHT, Flesh.FAT_DARK,
                                   S_ * 0.03), core)
        buf.composite(Flesh.BLOOD_DARK, P.vein_web(S_, S_, seed + 5, count=4, width=S_ * 0.004) * chunk * 0.4)
        # soft dark edge rather than a drawn outline: a hard contour on a round
        # chunk reads as a sticker, and this is a piece of the world
        fall = S.blur(chunk, S_ * 0.020) - S.blur(chunk, S_ * 0.045)
        buf.composite(Flesh.BLOOD_DARK, np.clip(fall, 0, 1) * 0.85)
        halo = np.clip(S.dilate(chunk, S_ * 0.014) - chunk, 0, 1)
        halo = S.roughen(halo, S.value_noise(S_, S_, S_ * 0.05, seed + 6, 3), 0.9, 1.0)
        buf.composite(Flesh.OUTLINE, halo * 0.5)
        p = B.fname(VFX, "flesh_chunk_particle", f"rot{k}_128x128")
        aid = "TEX-304" if k == 0 else f"TEX-304-{k + 1}"
        B.register(aid, p, S_, S_, "MVP", note=f"torn chunk, rotation {k}")
        B.save(buf.to_image(), p)
        n += 1

    print(f"TEX MVP: {n} files")
    print(B.write_manifest("manifest_tex.json"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
