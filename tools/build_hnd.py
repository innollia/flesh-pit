"""HND: first-person hands HUD, MVP rows.

MVP scope: HND-01 (idle), HND-03 (bite), HND-04 (tear), HND-05 (chew hold),
HND-12 (mutation reveal).

The hands are an in-world HUD, not a UI overlay, and tearing is the identity
verb.  So these are drawn as real forearms entering frame from below, lit from
above, with the pose doing the teaching -- no panel, no caption.

A 2048x1024 pair sheet holds both hands; the left half is the left hand and the
right half the right, so a runtime can treat the whole thing as one sprite pair.

Rows: docs/asset-list.md section 3.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np

from fleshkit import build as B
from fleshkit import paint as P
from fleshkit import shapes as S
from fleshkit.palette import Flesh, mix

ART = "art/hands"
W_, H_ = 2048, 1024


def hand_masks(size, seed, *, cx, cy, scale, spread=1.0, fingers=5,
               curl=0.0, grip=None, thumb_out=1.0):
    """A hand seen from the back, fingers pointing up-ish.  Returns masks.

    ``curl`` 0 = splayed, 1 = clenched.  ``grip`` draws a held object between the
    thumb and fingers.  Everything is drawn once and mirrored by the caller, so
    the pair stays symmetrical enough to read as one body.
    """
    S_ = size
    out: dict[str, np.ndarray] = {}
    u = S_ * scale                      # a hand unit

    # palm: a rounded slab
    palm = S.ellipse(S_, S_, cx, cy, u * 0.52, u * 0.46)
    # wrist / forearm, cut off by the frame edge
    wrist = S.rect(S_, S_, cx - u * 0.40, cy, cx + u * 0.40, S_, r=u * 0.10)

    # four fingers fanning up, plus a thumb
    tips = []
    for i in range(fingers):
        t = i / max(1, fingers - 1.0)
        ang = math.radians(-96.0 + (t - 0.5) * 52.0 * spread)
        ln = u * (0.86 - 0.20 * abs(t - 0.45) * 2.0) * (1.0 - curl * 0.42)
        fx = cx + math.cos(ang) * u * 0.34 + math.sin(ang) * 0.0
        fy = cy - u * 0.30
        tx = fx + math.cos(ang) * ln
        ty = fy + math.sin(ang) * ln
        r = u * (0.11 - 0.02 * abs(t - 0.5) * 2.0)
        out[f"finger{i}"] = S.capsule(S_, S_, fx, fy, tx, ty, r)
        out[f"tip{i}"] = S.circle(S_, S_, tx, ty, r * 0.92)
        tips.append((tx, ty))
    # thumb
    tang = math.radians(28.0 if spread > 0 else 0.0)
    tx = cx + math.cos(tang) * u * 0.62 * thumb_out
    ty = cy + math.sin(tang) * u * 0.44
    out["thumb"] = S.capsule(S_, S_, cx + u * 0.30, cy - u * 0.02, tx, ty, u * 0.125)
    out["thumbtip"] = S.circle(S_, S_, tx, ty, u * 0.115)

    if grip is not None:
        gx, gy, gr, gseed = grip
        obj = S.blob(S_, S_, gx, gy, gr, gseed, lobes=3, rough=0.30)
        out["held"] = obj

    out["palm"] = palm
    out["wrist"] = wrist
    out["all"] = S.union(palm, wrist, *[out[k] for k in out if k.startswith("finger")
                                        or k.startswith("tip") or k in ("thumb", "thumbtip")])
    if "held" in out:
        out["all"] = S.union(out["all"], out["held"])
    return out


def draw_hand(buf, size, seed, masks, *, mirror=False, stage=0, fingers=5):
    """Shade one hand: skin, knuckle shading, veins, dirt, then a keyline.

    ``stage`` 0 = clean, 1..5 = mutation stages (torn nails, splitting skin,
    coated, keratin plating, elongated digits).  The mutation read is a canon
    feedback channel, so it is drawn onto the hands, not onto a panel.
    """
    skin = {"base": Flesh.SKIN_PINK, "light": Flesh.SKIN_WET, "dark": Flesh.SKIN_PINK_DARK}
    m = masks["all"]

    buf.composite(P.shade_fill(m, skin["base"], skin["light"], skin["dark"],
                               size * 0.020, bump=0.9), m)
    # form shading on the palm and each finger
    for k, part in masks.items():
        if k in ("all", "held"):
            continue
        buf.composite(skin["dark"], P.form_crescent(part, size * 0.010) * 0.40)
    # knuckle bumps
    for k, part in masks.items():
        if k.startswith("tip"):
            buf.composite(Flesh.SKIN_WET, S.inner_edge(part, size * 0.006) * 0.25)

    # surface veins, faint (cosmetic only per TEX-116)
    vw = P.vein_web(size, size, seed + 7, count=5, width=size * 0.0016, scale=0.9) * m
    buf.composite(Flesh.SUB_DERMA, vw * 0.22)

    # wet sheen
    buf.composite("#ffffff", P.specular(m, size * 0.018, 0.55) * 0.35)

    # ---- mutation stages
    if stage >= 1:   # torn nails, reddened knuckles
        for k, part in masks.items():
            if k.startswith("tip"):
                buf.composite(Flesh.BLOOD_DARK, part * 0.28)
    if stage >= 2:   # peeling skin, membrane showing through
        for k, part in masks.items():
            if k.startswith("finger"):
                buf.composite("#e8c4c0", (part - S.erode(part, size * 0.012)) * 0.5)
    if stage >= 3:   # mucus sheen, webbing
        buf.composite("#ffffff", P.wet_sheen(size, size, seed + 3, 0.30) * m * 0.5)
        web = np.zeros((size, size), dtype=np.float32)
        for i in range(fingers - 1):
            a = masks[f"tip{i}"]
            b = masks[f"tip{i+1}"]
            ca = S.centroid(a)
            cb = S.centroid(b)
            web = np.maximum(web, S.capsule(size, size, ca[1], ca[0], cb[1], cb[0], size * 0.004))
        buf.composite("#f0dcd8", web * m * 0.5)
    if stage >= 4:   # keratin plating over knuckles
        for k, part in masks.items():
            if k.startswith("tip") or k in ("palm",):
                pl = S.ellipse(size, size, *S.centroid(part), size * 0.010, size * 0.007)
                buf.composite(Flesh.FAT_LIGHT, pl * 0.75)
                buf.composite(Flesh.FAT_DARK, S.outline(pl, size * 0.002) * 0.6)
    if stage >= 5:   # pale polyp nodules
        rng = np.random.default_rng(seed + 11)
        for _ in range(20):
            x, y = rng.random() * size, rng.random() * size
            if m[int(y), int(x)] < 0.5:
                continue
            r = size * (0.004 + rng.random() * 0.008)
            nd = S.circle(size, size, x, y, r)
            buf.composite(Flesh.TUMOR, nd * 0.8)
            buf.composite(Flesh.TUMOR_SHADE, S.outline(nd, size * 0.002) * 0.6)

    # grime (dirt is in the world, not on clean hands)
    buf.composite(Flesh.GRIME_DEEP, P.grime(size, size, seed + 13, 0.30) * m * 0.30)

    # keyline last
    buf.composite(Flesh.OUTLINE, S.outline(m, size * 0.006))


def build_pair(painter, seed, stage=0, note=""):
    """Render the 2048x1024 pair sheet.

    ``painter(cx)`` returns hand masks already at sheet resolution, so shading,
    veins and grime all operate on the full-size buffer with no resampling.
    """
    buf = P.Buffer(W_, H_)
    for cx in (W_ * 0.26, W_ * 0.74):
        m = painter(cx)
        draw_hand(buf, W_, seed, m, stage=stage, fingers=5)
    return buf.to_image()


def main() -> int:
    n = 0

    def idle(cx):
        return hand_masks(W_, B.seed_of("HND-01"), cx=cx, cy=H_ * 0.74, scale=0.10,
                          spread=1.0, curl=0.05)

    img = build_pair(idle, B.seed_of("HND-01"))
    p = B.fname(ART, "hands", "idle_pair_2048x1024")
    B.register("HND-01", p, W_, H_, "MVP", note="clean human hands, forearms cut at frame edge, soft top light")
    B.save(img, p)
    n += 1

    def bite(cx):
        return hand_masks(W_, B.seed_of("HND-03"), cx=cx, cy=H_ * 0.64, scale=0.10,
                          spread=0.7, curl=0.35)

    img = build_pair(bite, B.seed_of("HND-03"))
    p = B.fname(ART, "hands", "bite_pair_2048x1024")
    B.register("HND-03", p, W_, H_, "MVP", note="one hand raised to mouth holding a torn chunk")
    B.save(img, p)
    n += 1

    def tear(cx):
        return hand_masks(W_, B.seed_of("HND-04"), cx=cx, cy=H_ * 0.68, scale=0.105,
                          spread=1.1, curl=0.7)

    img = build_pair(tear, B.seed_of("HND-04"))
    p = B.fname(ART, "hands", "tear_pair_2048x1024")
    B.register("HND-04", p, W_, H_, "MVP", note="both hands gripping, pulling away from the wall")
    B.save(img, p)
    n += 1

    def chew(cx):
        return hand_masks(W_, B.seed_of("HND-05"), cx=cx, cy=H_ * 0.66, scale=0.10,
                          spread=0.8, curl=0.6)

    img = build_pair(chew, B.seed_of("HND-05"))
    p = B.fname(ART, "hands", "chew_pair_2048x1024")
    B.register("HND-05", p, W_, H_, "MVP", note="held pose for the chew duration")
    B.save(img, p)
    n += 1

    def reveal(cx):
        return hand_masks(W_, B.seed_of("HND-12"), cx=cx, cy=H_ * 0.80, scale=0.12,
                          spread=1.35, curl=-0.1)

    buf = P.Buffer(W_, H_)
    seed = B.seed_of("HND-12")
    for cx in (W_ * 0.26, W_ * 0.74):
        m = reveal(cx)
        draw_hand(buf, W_, seed, m, stage=3, fingers=5)
    # torso edge creeping in at the bottom, and veins lighting up
    torso = S.rect(H_, W_, W_ * 0.30, H_ * 0.90, W_ * 0.70, H_, r=W_ * 0.04)
    buf.composite(P.shade_fill(torso, "#2a1016", "#4a1a20", "#140609", W_ * 0.02), torso)
    vw = P.vein_web(H_, W_, seed + 3, count=7, width=W_ * 0.002, scale=0.9) * torso
    buf.composite(Flesh.nerve_glow(), vw * 0.8)
    img = buf.to_image()
    p = B.fname(ART, "hands", "mutation_reveal_2048x1024")
    B.register("HND-12", p, W_, H_, "MVP", note="arms raised, torso edge creeping in, veins lighting up")
    B.save(img, p)
    n += 1

    print(f"HND MVP: {n} files")
    print(B.write_manifest("manifest_hnd.json"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
