"""ICO group: tissue icons, legend chrome, and the colour-blind variants.

Run:  py -3 -B tools/build_ico.py
Out:  assets/ui/icons/  and  assets/icons/
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

from fleshkit import build as B
from fleshkit import paint as P
from fleshkit import shapes as S
from fleshkit import tissue_icons as TI
from fleshkit.palette import Flesh, Restroom, hex_rgb, mix

ICO = "ui/icons/"
TISSUES = ["T01", "T02", "T03", "T04", "T05", "T06", "T07", "T08", "T09", "T10"]

# The Look column of docs/asset-list.md section 6, kept next to the ids so a
# reviewer can check a render against the spec without opening the document.
TISSUES_DESC = {
    "T01": "red striated wedge, layered bands",
    "T02": "soft yellow lobes, glossy",
    "T03": "white torn strip, fibrous ends",
    "T04": "translucent sac with fluid highlight",
    "T05": "grey-white smooth plate with a rim",
    "T06": "bright yellow, thick keyline, three strands, wriggle ticks: "
           "the highest-contrast element in the set",
    "T07": "pale nodular mass with clustered bulbs",
    "T08": "translucent rippled sheet with a wet highlight",
    "T09": "dense bone-white barrier plate, heavy shadow",
    "T10": "fresh pink seam lines, healing grain",
}


# --------------------------------------------------------------------------- panel helpers
def nine_slice(w: int, h: int, border: int, painter, centre: bool = True) -> Image.Image:
    """Draw a 9-slice-ready panel: the caller renders the full rect, the art is
    authored to survive having its border stretched.  Returns the flat image."""
    buf = P.Buffer(w, h)
    painter(buf, w, h, border)
    return buf.to_image()


def _ruled_card(buf, w, h, pal, kl, accent=None, lines=3, border=24):
    """A wet dark-red card with a thick keyline, used by every legend card row."""
    body = S.rect(h, w, border, border, w - border, h - border, r=border * 0.7)
    fill = P.shade_fill(body, pal["base"], pal["light"], pal["dark"], w * 0.05)
    buf.composite(fill, body)
    buf.composite(pal["dark"], P.form_crescent(body, w * 0.02) * 0.4)
    buf.composite(Flesh.OUTLINE, S.outline(body, kl))
    if accent:
        bar = S.rect(h, w, border, border, border + w * 0.035, h - border, r=2)
        buf.composite(accent, bar)
    # blank ruled lines for font text: empty space, never a baked string
    for i in range(lines):
        y = h * 0.42 + i * h * 0.13
        ln = S.rect(h, w, w * 0.30, y, w * (0.92 if i % 2 == 0 else 0.80), y + h * 0.022, r=2)
        buf.composite(pal["dark"], ln * 0.5)
    return body


# --------------------------------------------------------------------------- main
def main() -> int:
    made = 0
    size = 128

    # ---- ICO-05..ICO-15 : the ten tissue icons + unknown.
    # Spec numbering: ICO-05 is unknown, ICO-06..ICO-15 are T01..T10 in order.
    ICO_NUM = {t: f"{6 + i:02d}" for i, t in enumerate(TISSUES)}
    for tid in TISSUES:
        seed = B.seed_of(f"ICO-{ICO_NUM[tid]}")
        img = TI.tissue_icon(tid, size, seed)
        p = B.fname(ICO, "tissue", tid.lower(), "128")
        B.register(f"ICO-{ICO_NUM[tid]}", p, size, size, "MVP",
                   note=f"tissue {tid}: {TISSUES_DESC[tid]}")
        B.save(img, p)
        made += 1
        # the plain icons also go to assets/icons/ so the icon folder is the one
        # place a designer looks for tissue identification
        B.save(img, B.fname("icons", "tissue", tid.lower(), "128"))
        made += 1

    seed = B.seed_of("ICO-05")
    img = TI.unknown_icon(size, seed)
    p = B.fname(ICO, "tissue", "unknown", "128")
    B.register("ICO-05", p, size, size, "MVP", note="unknown, deliberately low contrast")
    B.save(img, p)
    B.save(img, B.fname("icons", "tissue", "unknown", "128"))
    made += 2

    # ---- ICO-27 / ACC-01 : colour-blind safe atlas, 10 x 128
    tiles = []
    for tid in TISSUES:
        tiles.append(TI.tissue_icon_colourblind(tid, size, B.seed_of(f"ACC-01-{tid}")))
    atlas = Image.new("RGBA", (size * len(tiles), size), (0, 0, 0, 0))
    for i, t in enumerate(tiles):
        atlas.paste(t, (i * size, 0))
    p = B.fname(ICO, "tissue", "colourblind_atlas", "1280x256")
    B.register("ICO-27", p, size * 10, size, "P1", kind="atlas", note="shape+pattern, not colour")
    B.save(atlas, p)
    B.save(atlas, B.fname("icons", "tissue", "colourblind_atlas", "1280x256"))
    made += 2

    # ---- ICO-28 / ACC-02 : high contrast nerve, 3 sizes
    for i, s in enumerate((128, 64, 32)):
        img = TI.nerve_icon_high_contrast(s, B.seed_of("ICO-28"))
        p = B.fname(ICO, "nerve", "highcontrast", str(s))
        aid = "ICO-28" if i == 0 else f"ACC-02-{s}"
        B.register(aid, p, s, s, "P1", note="white halo, hard keyline")
        B.save(img, p)
        made += 1
    strip_w = 128 + 64 + 32
    strip = Image.new("RGBA", (strip_w, 128), (0, 0, 0, 0))
    x = 0
    for s in (128, 64, 32):
        strip.paste(TI.nerve_icon_high_contrast(s, B.seed_of("ACC-02")), (x, 0))
        x += s
    B.save(strip, B.fname("icons", "nerve", "highcontrast", "atlas"))
    made += 1

    # ---- ICO-01 : legend panel frame, 1024x512 9-slice
    pal = {"base": Flesh.UI_PANEL, "light": Flesh.UI_PANEL_LIGHT, "dark": Flesh.UI_EDGE}

    def legend_frame(buf, w, h, b):
        _ruled_card(buf, w, h, pal, w * 0.010, lines=0, border=b)

    p = B.fname(ICO, "legend", "panel_9s")
    B.register("ICO-01", p, 1024, 512, "MVP", kind="9slice", note=f"9-slice border {64}")
    B.save(nine_slice(1024, 512, 64, legend_frame), p)
    made += 1

    # ---- ICO-02..04 : legend tabs
    for state, (lift, bright, underline) in {
        "normal": (0.0, 0.0, False),
        "hover": (-2.0, 0.22, False),
        "selected": (0.0, 0.30, True),
    }.items():
        buf = P.Buffer(256, 64)
        bar = S.rect(64, 256, 4, 8 + lift, 252, 60 + lift, r=8)
        buf.composite(P.shade_fill(bar, Flesh.UI_WASH, Flesh.UI_PANEL_LIGHT, Flesh.UI_EDGE,
                                   30.0), bar)
        if bright:
            buf.composite(Flesh.SKIN_WET, S.dilate(bar, 2.0) - bar * 0.0)
        buf.composite(Flesh.OUTLINE, S.outline(bar, 3.0) * (0.7 if not bright else 1.0))
        if underline:
            u = S.rect(64, 256, 24, 56, 232, 61, r=2)
            buf.composite("#ffffff", u)
        p = B.fname(ICO, "legend", "tab", state, "256x64")
        B.register(f"ICO-{'02' if state == 'normal' else '03' if state == 'hover' else '04'}",
                   p, 256, 64, "P1")
        B.save(buf.to_image(), p)
        made += 1

    # ---- ICO-16..25 : per-tissue legend cards, 512x256 9-slice
    card_ids = {"T01": "16", "T02": "17", "T03": "18", "T04": "19", "T05": "20",
                "T06": "21", "T07": "22", "T08": "23", "T09": "24", "T10": "25"}
    for tid, num in card_ids.items():
        tpal = {"base": Flesh.UI_PANEL, "light": Flesh.UI_PANEL_LIGHT, "dark": Flesh.UI_EDGE}
        accent = Flesh.nerve_base() if tid == "T06" else None
        buf = P.Buffer(512, 256)
        body = _ruled_card(buf, 512, 256, tpal, 5.0, accent=accent, lines=3, border=22)
        # the tissue swatch and its icon slot, left column
        swatch = S.rect(256, 512, 40, 46, 132, 210, r=10)
        ip = {"base": "#000000", "light": "#000000", "dark": "#000000"}
        from fleshkit.palette import tissue_palette
        tp = tissue_palette(tid)
        buf.composite(P.shade_fill(swatch, tp["base"], tp["light"], tp["dark"], 20.0), swatch)
        buf.composite(Flesh.OUTLINE, S.outline(swatch, 4.0))
        slot = S.rect(256, 512, 152, 46, 244, 152, r=10)
        buf.composite(Flesh.UI_EDGE, slot)
        buf.composite(tp["base"] if tid == "T06" else Flesh.UI_WASH,
                      S.outline(slot, 3.0) * 0.8)
        mini = TI.tissue_icon(tid, 96, B.seed_of(f"ICO-{num}"))
        buf.composite(np.asarray(mini, dtype=np.float32) / 255.0, x0=160, y0=51)
        p = B.fname(ICO, "legend", "card", tid.lower(), "9s")
        B.register(f"ICO-{num}", p, 512, 256, "MVP" if num in ("16", "17", "18", "21")
                   else "P1", kind="9slice", note="icon + swatch + blank ruled lines")
        B.save(buf.to_image(), p)
        made += 1

    # ---- ICO-26 / TUT-12 : tooltip bubble, 512x128 9-slice
    def bubble(buf, w, h, b):
        body = S.rect(h, w, b, b, w - b, h - b - b * 0.5, r=h * 0.35)
        tip = S.polygon(h, w, [(w * 0.30, h - b * 0.6), (w * 0.40, h - 2),
                               (w * 0.40, h - b * 0.6)])
        m = S.union(body, tip)
        buf.composite(P.shade_fill(m, Flesh.UI_PANEL, Flesh.UI_PANEL_LIGHT,
                                   Flesh.UI_EDGE, w * 0.03), m)
        buf.composite(Flesh.OUTLINE, S.outline(m, 4.0))
        for i in range(2):
            y = h * 0.40 + i * h * 0.20
            buf.composite(Flesh.UI_EDGE,
                          S.rect(h, w, w * 0.14, y, w * 0.86, y + h * 0.045, r=3) * 0.55)

    for aid in ("ICO-26", "TUT-12"):
        p = B.fname("ui/prompts", "tooltip", "bubble_9s")
        B.register(aid, p, 512, 128, "MVP" if aid == "ICO-26" else "P1", kind="9slice")
        B.save(nine_slice(512, 128, 40, bubble), p)
        made += 1

    # ---- ACC-01 mirrors ICO-27 into assets/icons for convenience
    B.register("ACC-01", B.fname(ICO, "tissue", "colourblind_atlas", "1280x256"),
               1280, 128, "P1", kind="atlas", note="accessibility duplicate of ICO-27")

    mf = B.write_manifest()
    print(f"ICO group: {made} files, registry {len(B.REGISTRY)}")
    print(f"manifest: {mf}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
