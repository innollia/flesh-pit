"""fleshkit: procedural generation of every image asset for flesh-pit.

Design rules taken from docs/design-core.md and docs/asset-list.md:

  * No baked text anywhere.  Numerals too.  If a row needs digits, the row says
    "atlas" and ships an empty stencil frame, never a string.
  * The restroom is clean white.  It must never inherit flesh grime.  Callers
    get that for free: `flesh.grime` and `flesh.restroom` are separate calls and
    the restroom path simply never adds a stain.
  * Nerves are the loudest language in the game: saturated yellow, thick
    keyline, always drawn with `nerve_keyline` so no caller can quietly make
    them quiet.
  * Everything is a function of (id, seed).  Rebuilds are reproducible, so a
    caller can re-run one asset without touching the other 332.

Coordinates are final-output pixels, matching asset-list.md.  The renderer
supersamples internally and downsamples with a premultiplied Lanczos so
transparent edges do not darken.
"""

from __future__ import annotations

TOOL_VERSION = "1.0.0"

__all__ = ["TOOL_VERSION"]
