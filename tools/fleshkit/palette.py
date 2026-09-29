"""Palette: the two colour languages, kept apart on purpose.

`FLESH` is dirty, warm, organic.  `RESTROOM` is clean, cool, bright.  They are
separate namespaces so a caller cannot blend a grime colour into a restroom
asset by accident -- which is the single most expensive art mistake this project
can make, because the restroom is the one deliberate visual exception in an
otherwise red world (design-core.md section 8).

`NERVE_*` exists so the nerve keyline colour is written down once.  Every nerve
asset pulls its outline from here and callers are expected to use
`flesh.nerve_keyline()` rather than a literal.
"""

from __future__ import annotations

import numpy as np


# --------------------------------------------------------------------------- helpers
def hex_rgb(value) -> np.ndarray:
    """'#rrggbb' | 'rgb' | '#rrggbbaa' | sequence -> float32[3 or 4] in 0..1."""
    if isinstance(value, (list, tuple, np.ndarray)):
        return np.asarray(value, dtype=np.float32)
    v = str(value).lstrip("#")
    if len(v) == 3:
        v = "".join(c * 2 for c in v)
    if len(v) not in (6, 8):
        raise ValueError(f"bad colour {value!r}")
    chans = [int(v[i:i + 2], 16) / 255.0 for i in range(0, len(v), 2)]
    return np.array(chans, dtype=np.float32)


def mix(a, b, t):
    """Linear blend; ``t`` may be a scalar or a (h, w) map."""
    ta = hex_rgb(a)
    tb = hex_rgb(b)
    t = np.asarray(t, dtype=np.float32)
    if t.ndim == 2:
        t = t[..., None]
    return ta + (tb - ta) * t


def ramp(colors, t):
    """Sample a multi-stop gradient at ``t`` in 0..1 -> float32[3].

    Stops are evenly spaced.  Used for depth gradients, vein travel, the
    nav banner wipe, and anywhere a row says "gradient".
    """
    stops = np.stack([hex_rgb(c)[:3] for c in colors]).astype(np.float32)
    t = np.clip(np.asarray(t, dtype=np.float32), 0.0, 1.0)
    if t.ndim == 2:
        return ramp(colors, t.reshape(-1)).reshape(*t.shape, 3)
    n = len(stops) - 1
    pos = t * n
    idx = np.clip(np.floor(pos).astype(np.int32), 0, n - 1)
    frac = (pos - idx)[..., None]
    return stops[idx] * (1.0 - frac) + stops[idx + 1] * frac


# --------------------------------------------------------------------------- flesh world
class Flesh:
    """Dirty organic world.  Dark, wet, blood-warm.

    Values sit LOW on purpose.  The first pass used believable mid-tone skin and
    rendered cartoon: bright pinks and a fat specular read as illustration, not
    as something you are standing inside.  Every colour here is roughly two
    stops under the intuitive choice, and the keyline is nearly black.
    """

    # surfaces
    SKIN_PINK = "#a86a68"
    SKIN_PINK_DARK = "#6b3a3c"
    SKIN_WET = "#c28b84"
    SUB_DERMA = "#8a3d43"
    BLOOD = "#63171c"
    BLOOD_DARK = "#3a0c10"
    CONGESTED = "#4a0a11"
    MUSCLE = "#5e1f20"
    MUSCLE_DARK = "#341113"
    MUSCLE_LIGHT = "#7d3630"
    FAT = "#b39338"
    FAT_LIGHT = "#d4b155"
    FAT_DARK = "#6e5620"
    FASCIA = "#b0a996"
    FASCIA_SHADE = "#6f6a5c"
    CARTILAGE = "#8f948f"
    CARTILAGE_DARK = "#5c615d"
    MUCOSA = "#96727a"
    MUCOSA_SHEEN = "#d8bcc0"
    SCAR = "#a4625f"
    SCAR_HEAL = "#7a4446"
    SHELL = "#b6b0a4"
    TUMOR = "#9a9284"
    TUMOR_SHADE = "#6b6459"
    BONE = "#b8ae98"
    BONE_SHADE = "#7d7565"

    # grime / dirt
    GRIME = "#2c1c1d"
    GRIME_DEEP = "#160c0e"
    DAMP = "#38241f"
    MOULD = "#45452f"
    RUST = "#5a3018"
    RUST_DARK = "#361a0d"

    # hardware embedded in flesh
    BRASS = "#6f5424"
    BRASS_LIGHT = "#9c7a36"
    IRON = "#333232"
    IRON_LIGHT = "#5f5c5a"
    STEEL = "#7e8284"

    # shadow / outline
    OUTLINE = "#0d0507"
    OUTLINE_SOFT = "#1c0b0d"
    SHADOW = "#080305"

    # dirty-world UI
    UI_PANEL = "#2b1114"
    UI_PANEL_LIGHT = "#42191d"
    UI_EDGE = "#150709"
    UI_WASH = "#401a1e"
    UI_WASH_SOFT = "#2a1013"

    # warnings
    BILE = "#5c6626"
    BILE_LIGHT = "#7d8a36"
    COLD_VEIN = "#2e4660"
    COLD_VEIN_LIGHT = "#4d6d8a"
    GOLD_RIM = "#96751f"
    GOLD_RIM_LIGHT = "#c0a044"
    NAUSEA = "#515c1e"

    # decay states
    SEAM_SPLIT = "#2c0609"
    SCAB = "#221312"

    @staticmethod
    def nerve_base() -> str:
        return "#c9a613"

    @staticmethod
    def nerve_light() -> str:
        return "#e8cd45"

    @staticmethod
    def nerve_deep() -> str:
        return "#6a5104"

    @staticmethod
    def nerve_keyline() -> str:
        return "#0a0700"

    @staticmethod
    def nerve_glow() -> str:
        return "#c9b02a"


# --------------------------------------------------------------------------- restroom world
class Restroom:
    """Clean white.  Deliberately, visibly separate from Flesh.

    Still clean and still the bright exception, but not bright-white: a pure
    white surface in a game graded this low reads as a blown-out hole rather
    than as safety.  The exception is carried by chroma and clarity, not by
    raw luminance.
    """

    WALL_TILE = "#c9cecb"
    WALL_TILE_ALT = "#b6bcb9"
    WALL_TILE_DEEP = "#9aa19e"
    GROUT = "#7c8482"
    FLOOR_TILE = "#a8aeac"
    FLOOR_TILE_ALT = "#959b99"
    CERAMIC = "#dfe3e1"
    CERAMIC_SHADE = "#aeb4b1"
    WATER = "#c3d3d5"
    PAPER = "#cfd0cc"
    ENAMEL = "#d5dad7"
    ENAMEL_EDGE = "#6d7674"
    STEEL = "#98a0a1"
    STEEL_DARK = "#6a7274"
    FLUORESCENT = "#e4eef2"
    FLUORESCENT_WARM = "#dde3d7"
    # the one warm thing in this world, so the exit reads as safe
    SAFE_BLOOM = "#f0e6d4"
    SAFE_BLOOM_EDGE = "#c4bda9"


# --------------------------------------------------------------------------- deep world
class Deep:
    """Bands B05 and below: darker, more saturated, less light."""

    GLAND_SAC = "#c98fa0"
    GLAND_FLUID = "#e6b6c2"
    GLAND_DEEP = "#7d4f5c"
    CAVITY = "#140b0d"
    CAVITY_SHEEN = "#2c1c20"
    CORRIDOR = "#3a1a1c"
    CORRIDOR_RIB = "#5a2a2c"
    CORRIDOR_DEEP = "#1c0d0f"
    PERISTALTIC = "#4a2224"
    NERVE_MASS = "#b8960f"
    NERVE_MASS_LIGHT = "#e8c62a"


# --------------------------------------------------------------------------- groups
GROUP = {
    "flesh": Flesh,
    "restroom": Restroom,
    "deep": Deep,
}


def tissue_palette(tissue_id: str) -> dict:
    """Colour set for one of the ten tissue types (asset-list.md section 0, 14.2)."""
    F = Flesh
    table = {
        "T01": {"base": F.MUSCLE, "light": F.MUSCLE_LIGHT, "dark": F.MUSCLE_DARK,
                "accent": F.OUTLINE, "read": "red striated, springs back"},
        "T02": {"base": F.FAT, "light": F.FAT_LIGHT, "dark": F.FAT_DARK,
                "accent": F.OUTLINE, "read": "yellow, soft, high yield"},
        "T03": {"base": F.FASCIA, "light": "#ffffff", "dark": F.FASCIA_SHADE,
                "accent": F.OUTLINE, "read": "white, tough, tears in strips"},
        "T04": {"base": F.MUCOSA, "light": F.MUCOSA_SHEEN, "dark": F.SUB_DERMA,
                "accent": F.OUTLINE, "read": "translucent, fluid-filled, slow chew"},
        "T05": {"base": F.CARTILAGE, "light": "#eef0ec", "dark": F.CARTILAGE_DARK,
                "accent": F.OUTLINE, "read": "grey-white, hard, uncuttable by hands"},
        "T06": {"base": F.nerve_base(), "light": F.nerve_light(), "dark": F.nerve_deep(),
                "accent": F.nerve_keyline(), "read": "yellow, protruding, wriggling"},
        "T07": {"base": F.TUMOR, "light": "#efe9dc", "dark": F.TUMOR_SHADE,
                "accent": F.OUTLINE, "read": "pale nodular mass, codex target"},
        "T08": {"base": F.MUCOSA, "light": F.MUCOSA_SHEEN, "dark": F.MUCOSA,
                "accent": F.OUTLINE, "read": "slippery translucent sheet"},
        "T09": {"base": F.SHELL, "light": "#ffffff", "dark": F.BONE_SHADE,
                "accent": F.OUTLINE, "read": "dense bone-white barrier"},
        "T10": {"base": F.SCAR, "light": "#f0a8a4", "dark": F.SCAR_HEAL,
                "accent": F.OUTLINE, "read": "fresh pink seam lines, healing grain"},
    }
    if tissue_id not in table:
        raise KeyError(f"unknown tissue {tissue_id!r}")
    return table[tissue_id]


BAND_PALETTE = {
    "B01": {"key": Flesh.SKIN_PINK, "light": Flesh.SKIN_WET, "dark": Flesh.SKIN_PINK_DARK,
            "accent": Flesh.SUB_DERMA, "hole": Flesh.GRIME},
    "B02": {"key": Flesh.FAT, "light": Flesh.FAT_LIGHT, "dark": Flesh.FAT_DARK,
            "accent": Flesh.SKIN_PINK_DARK, "hole": Flesh.BLOOD_DARK},
    "B03": {"key": Flesh.FASCIA, "light": "#ffffff", "dark": Flesh.FASCIA_SHADE,
            "accent": Flesh.MUSCLE_DARK, "hole": Flesh.MUSCLE_DARK},
    "B04": {"key": Flesh.MUSCLE, "light": Flesh.MUSCLE_LIGHT, "dark": Flesh.MUSCLE_DARK,
            "accent": Flesh.OUTLINE, "hole": Flesh.BLOOD_DARK},
    "B05": {"key": Deep.GLAND_SAC, "light": Deep.GLAND_FLUID, "dark": Deep.GLAND_DEEP,
            "accent": Flesh.OUTLINE, "hole": Flesh.SHADOW},
    "B06": {"key": Deep.NERVE_MASS, "light": Deep.NERVE_MASS_LIGHT, "dark": Flesh.nerve_deep(),
            "accent": Flesh.nerve_keyline(), "hole": Flesh.BLOOD_DARK},
    "B07": {"key": Deep.CAVITY, "light": Deep.CAVITY_SHEEN, "dark": "#000000",
            "accent": Flesh.OUTLINE, "hole": "#000000"},
    "B08": {"key": Deep.PERISTALTIC, "light": Deep.CORRIDOR_RIB, "dark": Deep.CORRIDOR_DEEP,
            "accent": Flesh.OUTLINE, "hole": "#000000"},
}
