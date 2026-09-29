"""Canonical colour tokens for flesh-pit.

Every value here is traceable to a line in docs/asset-list.md or
docs/world-direction.md. The world is red / wet / dirty / organic.
The restroom is the clean white exception and must never be pushed
toward the flesh palette.
"""

from __future__ import annotations

# --- flesh world ------------------------------------------------------------
FLESH_DARK = (0x2A, 0x0A, 0x0E)
FLESH_DEEP = (0x5E, 0x14, 0x18)
FLESH_MID = (0x9E, 0x30, 0x30)
FLESH_BRIGHT = (0xC7, 0x4A, 0x42)
FLESH_PALE = (0xE8, 0xA9, 0xA9)
FLESH_GREY = (0x8A, 0x6B, 0x6B)

# --- tissue families --------------------------------------------------------
FAT = (0xE0, 0xC0, 0x60)
FAT_DEEP = (0xB2, 0x92, 0x36)
NERVE = (0xF5, 0xD2, 0x1F)  # loudest colour in the game, canon requirement
NERVE_HOT = (0xFF, 0xF5, 0x9A)
NERVE_DEEP = (0xA8, 0x86, 0x0C)
CARTILAGE = (0xD8, 0xD6, 0xCE)
CARTILAGE_DEEP = (0x9E, 0x9C, 0x93)
BONE = (0xE8, 0xE0, 0xCC)
BONE_DEEP = (0xB4, 0xA8, 0x8C)
MUCOSA = (0xE9, 0xCF, 0xC9)
TUMOR = (0xDA, 0xC8, 0xB4)
TUMOR_DEEP = (0x9E, 0x8A, 0x7A)
SCAR = (0xE0, 0x94, 0x8E)
VEIN = (0x6E, 0x86, 0x9E)  # cosmetic only, see TEX-116

# --- restroom: the clean white exception ------------------------------------
CLEAN_WHITE = (0xFA, 0xFA, 0xF7)
TILE_WHITE = (0xF2, 0xF3, 0xEF)
GROUT = (0xC9, 0xCC, 0xC6)
FLOOR_GREY = (0xB6, 0xB8, 0xB4)
STEEL = (0x9A, 0xA0, 0xA6)
STEEL_DARK = (0x5E, 0x64, 0x6A)

# --- metal / ink / signal ---------------------------------------------------
BRASS = (0xC9, 0xA2, 0x27)
BRASS_DARK = (0x7A, 0x5E, 0x14)
INK = (0x24, 0x13, 0x16)
INK_SOFT = (0x4A, 0x30, 0x33)
BONE_WHITE = (0xEE, 0xE9, 0xDA)
PAPER = (0xE4, 0xDA, 0xC4)
PAPER_DAMP = (0xC4, 0xB4, 0x94)
BILE = (0xB8, 0xC2, 0x4A)
WATER = (0xC4, 0xD8, 0xDC)

# named bundles used by recipes
FLESH = [FLESH_DARK, FLESH_DEEP, FLESH_MID, FLESH_BRIGHT, FLESH_PALE]
CLEAN = [INK, INK_SOFT, STEEL_DARK, STEEL, TILE_WHITE, CLEAN_WHITE]


def mix(a, b, t: float) -> tuple[float, float, float]:
    """Linear blend between two rgb tuples, t in [0, 1]."""
    t = min(1.0, max(0.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))  # type: ignore[return-value]


def scale(c, k: float) -> tuple[float, float, float]:
    return tuple(max(0.0, min(255.0, v * k)) for v in c)  # type: ignore[return-value]


def ramp(stops: list[tuple[float, tuple[int, int, int]]], t):
    """Sample a multi-stop colour ramp. ``stops`` is [(pos, rgb), ...] sorted."""
    t = min(1.0, max(0.0, t))
    for i in range(len(stops) - 1):
        p0, c0 = stops[i]
        p1, c1 = stops[i + 1]
        if p0 <= t <= p1:
            span = (p1 - p0) or 1.0
            return mix(c0, c1, (t - p0) / span)
    return stops[-1][1] if t >= stops[-1][0] else stops[0][1]
