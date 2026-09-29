"""Bakes low-res PS1-style flat textures for flesh-pit from the higher-res
source textures in assets/3d/textures/** (read-only, never modified), with a
procedural fallback when a source is missing. Deterministic (fixed seeds).

Usage (from game/):
    python -X utf8 tools/bake_ps1_textures.py

Writes 64-256 px PNGs into addons/flesh_dig_kit/textures/ (kit-owned,
license-clear: either derived from this project's own generated source pool
under assets/3d/textures/, or procedurally generated here with numpy/PIL).
"""
from __future__ import annotations

import pathlib
import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT.parent / "assets" / "3d" / "textures"
OUT = ROOT / "addons" / "flesh_dig_kit" / "textures"
OUT.mkdir(parents=True, exist_ok=True)


def rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


def save(name: str, arr: np.ndarray) -> None:
    Image.fromarray(arr, "RGB" if arr.shape[-1] == 3 else "RGBA").save(OUT / name)
    print("wrote", name, arr.shape[:2])


def from_source(path: pathlib.Path, size: int) -> np.ndarray | None:
    """Downsample a source texture with box filtering (never nearest going
    down -- nearest is only for the runtime *upscale*), crop to square."""
    if not path.exists():
        return None
    im = Image.open(path).convert("RGB")
    w, h = im.size
    s = min(w, h)
    im = im.crop(((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s))
    im = im.resize((size, size), Image.BOX)
    return np.array(im)


def ordered_dither(arr: np.ndarray, levels: int = 32) -> np.ndarray:
    """4x4 Bayer ordered dither + colour-depth reduction, the PS1 signature."""
    bayer = np.array([
        [0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5],
    ], dtype=np.float32) / 16.0 - 0.5
    h, w = arr.shape[:2]
    tile = np.tile(bayer, (h // 4 + 1, w // 4 + 1))[:h, :w]
    step = 256.0 / levels
    out = arr.astype(np.float32) + tile[..., None] * step
    out = np.clip(np.round(out / step) * step, 0, 255)
    return out.astype(np.uint8)


def clamp01(a: np.ndarray) -> np.ndarray:
    return np.clip(a, 0.0, 1.0)


def value_noise(size: int, cell: int, seed: int) -> np.ndarray:
    g = rng(seed)
    n = size // cell + 2
    grid = g.random((n, n)).astype(np.float32)
    im = Image.fromarray((grid * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC)
    return np.array(im).astype(np.float32) / 255.0


def fbm(size: int, seed: int, octaves=4, base_cell=64) -> np.ndarray:
    out = np.zeros((size, size), dtype=np.float32)
    amp = 1.0
    total = 0.0
    for o in range(octaves):
        cell = max(2, base_cell // (2 ** o))
        out += value_noise(size, cell, seed + o * 101) * amp
        total += amp
        amp *= 0.55
    return out / total


def procedural_flesh(size: int, seed: int, base: tuple, vein: tuple, dark: tuple) -> np.ndarray:
    n1 = fbm(size, seed, octaves=5, base_cell=size // 3)
    n2 = fbm(size, seed + 999, octaves=3, base_cell=size // 6)
    base_c = np.array(base, dtype=np.float32)
    vein_c = np.array(vein, dtype=np.float32)
    dark_c = np.array(dark, dtype=np.float32)
    col = base_c[None, None, :] * (0.75 + 0.35 * n1[..., None])
    vein_mask = clamp01((n2 - 0.62) * 4.0)
    col = col * (1 - vein_mask[..., None]) + vein_c[None, None, :] * vein_mask[..., None]
    dark_mask = clamp01((0.32 - n1) * 3.0)
    col = col * (1 - dark_mask[..., None] * 0.6) + dark_c[None, None, :] * dark_mask[..., None] * 0.6
    return clamp01(col / 255.0) * 255.0


def procedural_tile(size: int, grout=18) -> np.ndarray:
    col = np.full((size, size, 3), 232, dtype=np.float32)
    n = fbm(size, 5, octaves=3, base_cell=size // 4)
    col += (n[..., None] - 0.5) * 14.0
    tiles = size // 2
    for i in range(0, size, tiles):
        col[i:i + grout // 2, :, :] -= 55
        col[:, i:i + grout // 2, :] -= 55
    return clamp01(col / 255.0) * 255.0


def procedural_skin(size: int, seed: int, base: tuple) -> np.ndarray:
    n1 = fbm(size, seed, octaves=4, base_cell=size // 3)
    n2 = fbm(size, seed + 7, octaves=5, base_cell=size // 8)
    base_c = np.array(base, dtype=np.float32)
    col = base_c[None, None, :] * (0.85 + 0.25 * n1[..., None]) * (0.94 + 0.1 * n2[..., None])
    return clamp01(col / 255.0) * 255.0



def ceramic(size: int) -> np.ndarray:
    """Clean white glazed ceramic: flat white base with a very soft vertical
    shade only (no noise, no stains, no grime). PS1 dither comes from the
    runtime post-process, not from the texture."""
    y = np.linspace(0.0, 1.0, size, dtype=np.float32)[:, None]
    v = 250.0 - 6.0 * y  # 250 at top -> 244 at bottom
    col = np.repeat(np.repeat(v, size, axis=1)[..., None], 3, axis=2)
    col[..., 2] += 2.0  # faint cool tint of glaze
    return np.clip(col, 0, 255).astype(np.uint8)


def build(size: int, suffix: str) -> None:
    dith_levels = 40

    # flesh: prefer a real generated source, downsampled; else procedural
    flesh_src = from_source(SRC / "shells" / "tex_B01_b01_surface_epithelium_pink_wet.png", size)
    flesh = flesh_src if flesh_src is not None else procedural_flesh(size, 1, (168, 40, 40), (150, 20, 20), (60, 6, 10))
    save(f"tex_flesh_{suffix}.png", ordered_dither(flesh, dith_levels))

    fat_src = from_source(SRC / "shells" / "tex_B02_b02_dermal_stratum_yellow_fat.png", size)
    fat = fat_src if fat_src is not None else procedural_flesh(size, 2, (214, 176, 96), (196, 150, 70), (110, 70, 30))
    save(f"tex_fat_{suffix}.png", ordered_dither(fat, dith_levels))

    nerve_src = from_source(SRC / "shells" / "tex_B06_b06_nerve_braid_yellow_strand.png", size)
    nerve = nerve_src if nerve_src is not None else procedural_flesh(size, 3, (222, 200, 60), (180, 150, 20), (90, 70, 10))
    save(f"tex_nerve_{suffix}.png", ordered_dither(nerve, dith_levels))

    memb_src = from_source(SRC / "shells" / "tex_B03_b03_fascia_sheet_white_fibrous.png", size)
    memb = memb_src if memb_src is not None else procedural_flesh(size, 4, (140, 60, 70), (110, 40, 55), (60, 20, 30))
    save(f"tex_membrane_{suffix}.png", ordered_dither(memb, dith_levels))

    tile_src = from_source(SRC / "restroom" / "rst_04_white_wall_tile_albedo.png", size)
    tile = tile_src if tile_src is not None else procedural_tile(size)
    save(f"tex_tile_wall_{suffix}.png", ordered_dither(tile, 56))

    floor_src = from_source(SRC / "restroom" / "rst_07_floor_tile_albedo.png", size)
    floor = floor_src if floor_src is not None else procedural_tile(size, grout=10)
    save(f"tex_tile_floor_{suffix}.png", ordered_dither(floor, 56))

    fixture_src = from_source(SRC / "restroom" / "rst_08_stainless_fixture_albedo.png", size)
    fixture = fixture_src if fixture_src is not None else np.full((size, size, 3), 214, dtype=np.uint8)
    save(f"tex_fixture_{suffix}.png", ordered_dither(fixture, 48))

    save(f"tex_ceramic_{suffix}.png", ceramic(size))

    skin = procedural_skin(size, 42, (224, 183, 156))
    save(f"tex_skin_{suffix}.png", ordered_dither(skin, 40))

    tank = procedural_flesh(size, 8, (150, 30, 30), (120, 15, 20), (55, 5, 8))
    save(f"tex_torn_chunk_{suffix}.png", ordered_dither(tank, dith_levels))


if __name__ == "__main__":
    for size, suffix in [(128, "128"), (64, "64")]:
        build(size, suffix)
    print("done. sources under", SRC, "read-only; nothing there was modified.")
