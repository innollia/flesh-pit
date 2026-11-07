# -*- coding: utf-8 -*-
"""Renders the flesh beds and the events that happen over them, all from nkido
patches (game/tools/audio/patches), and registers them in the manifest.

    python -X utf8 tools/build_biome_beds.py [id ...]

Owner, listening 2026-11-07: the beds were "a set of different white noises":
8 s of nearly level noise, 3 dB of movement, the gut folds under 60 Hz where no
speaker plays. So:

  * every bed is a long loop (LOOP_SEC, 23-37 s, none shares a length) with
    swells and silences in it, its identity in the band a laptop plays;
  * a biome's bed no longer sits on amb_body_a/b: that layer made them all one
    colour. A bed is its own layer plus the shell's heart (the heart is what
    every part of the body has in common, and it is left as it was);
  * BED_EVENTS: one-shots at long uneven gaps (audio/fp_body_events.gd), from
    a spot on a real wall near the player where the take has a place.

Levels: the beds went from -19 LUFS to LOOP_LUFS so the player's own sounds
stay on top; tools/measure_beds.py prints the margins. Events are takes heard
from the walls, under tear_flesh (-16) and level with regen_creak (-26). They
must not read as that creak or the contraction warning, which both mean
something: none of them reuses it, and rib_creak is bone (900-2200 Hz, slow
stick-slip) where the warning is wet at 520 Hz.

The manifest keeps every other sound as it is. Note: build_audio.py rewrites
manifest.json from sounds.json and drops "bed_events"; run this after it.
"""
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "game", "tools", "audio"))
import analyze_audio as A  # noqa: E402
import build_audio as B  # noqa: E402
import render_loop_patches as R  # noqa: E402

MANIFEST = os.path.join(B.AUDIO, "manifest.json")
SOUNDS = os.path.join(B.HERE, "sounds.json")
SFX = os.path.join(B.AUDIO, "sfx")
WORK = os.path.join(HERE, "..", "build", "beds")

LOOP_SEC = {"amb_body_a": 29.0, "amb_body_b": 41.0, "amb_fat_caves": 23.0, "amb_rib_vault": 37.0,
            "amb_gut_folds": 31.0, "amb_cloth_wads": 26.0, "amb_hair_thicket": 34.0}
LOOP_LUFS = {"amb_body_a": -25.0, "amb_body_b": -25.0, "amb_fat_caves": -24.0, "amb_rib_vault": -26.0,
             "amb_gut_folds": -25.0, "amb_cloth_wads": -27.0, "amb_hair_thicket": -27.0}
BEDS = {"body_a": ["amb_body_a", "amb_heart_a"], "body_b": ["amb_body_b", "amb_heart_b"],
        "fat_caves": ["amb_fat_caves", "amb_heart_a"], "rib_vault": ["amb_rib_vault", "amb_heart_a"],
        "gut_folds": ["amb_gut_folds", "amb_heart_a"], "cloth_wads": ["amb_cloth_wads", "amb_heart_b"],
        "hair_thicket": ["amb_hair_thicket", "amb_heart_b"]}
# seconds, mastered level, whether it comes from a place in the walls
EVENTS = {"body_glug": (1.6, -27.0, True), "flesh_press": (1.8, -27.0, True), "body_groan": (3.2, -26.0, False),
          "fat_blub": (1.3, -27.0, True), "fat_slump": (2.2, -27.0, True),
          "rib_creak": (1.7, -29.0, False), "rib_knock": (2.4, -28.0, False),
          "gut_squeeze": (2.8, -26.0, True), "gut_trill": (1.4, -28.0, True),
          "cloth_shift": (1.9, -28.0, True), "cloth_snag": (0.5, -30.0, True),
          "hair_sway": (2.4, -31.0, False), "hair_twang": (1.0, -32.0, True)}


def take(id_, lo=-5.0, hi=0.0):
    return {"id": id_, "db": [lo, hi]}


# first_gap and gap run in seconds from the end of one take to the next
BED_EVENTS = {
    "body_a": {"first_gap": [8.0, 20.0], "gap": [12.0, 34.0], "takes": [take("body_glug"), take("flesh_press")]},
    "body_b": {"first_gap": [8.0, 20.0], "gap": [14.0, 38.0], "takes": [take("body_groan"), take("flesh_press"), take("body_glug", -8.0, -3.0)]},
    "fat_caves": {"first_gap": [6.0, 16.0], "gap": [9.0, 28.0], "takes": [take("fat_blub"), take("fat_slump"), take("body_glug", -8.0, -3.0)]},
    "rib_vault": {"first_gap": [8.0, 20.0], "gap": [12.0, 36.0], "takes": [take("rib_creak"), take("rib_knock")]},
    "gut_folds": {"first_gap": [6.0, 16.0], "gap": [10.0, 30.0], "takes": [take("gut_squeeze"), take("gut_trill"), take("body_glug", -6.0, -1.0)]},
    "cloth_wads": {"first_gap": [8.0, 20.0], "gap": [12.0, 34.0], "takes": [take("cloth_shift"), take("cloth_snag")]},
    "hair_thicket": {"first_gap": [8.0, 20.0], "gap": [12.0, 34.0], "takes": [take("hair_sway"), take("hair_twang")]},
}
VARIATIONS = 4


def load_spec():
    with open(SOUNDS, encoding="utf-8") as f:
        return json.load(f)


def update_spec(spec):
    """sounds.json is the build input: the loops and takes live there too."""
    by_id = {s["id"]: s for s in spec["sounds"]}
    for sid, sec in LOOP_SEC.items():
        e = by_id.get(sid)
        if e is None:
            e = {"id": sid, "kind": "loop"}
            spec["sounds"].append(e)
        e.update({"loop_seconds": sec, "fade_seconds": 3.0, "target_lufs": LOOP_LUFS[sid], "ps1": "off"})
    for sid, (sec, lufs, spatial) in EVENTS.items():
        e = by_id.get(sid)
        if e is None:
            e = {"id": sid, "kind": "sfx"}
            spec["sounds"].append(e)
        e.update({"seconds": sec, "target_lufs": lufs, "spatial": spatial, "ps1": "off"})
    spec["beds"].update(BEDS)
    with open(SOUNDS, "w", encoding="utf-8", newline="\n") as f:
        json.dump(spec, f, indent=1, ensure_ascii=False)
        f.write("\n")


def render_event(sid, spec):
    sec, lufs, _ = EVENTS[sid]
    with open(os.path.join(B.HERE, "patches", sid + ".akkado"), encoding="utf-8") as f:
        patch = f.read()
    rate = int(spec["rate"])
    for i, (seed, seed2, pitch) in enumerate(spec["variations"][:VARIATIONS], start=1):
        raw = os.path.join(WORK, "%s_%d_raw.wav" % (sid, i))
        B.render(B.variant_patch(patch, seed, seed2, pitch), raw, sec, rate)
        data, _ = A.read_wav(raw)
        mono = data.mean(axis=1, keepdims=True)
        # a short fade keeps the render's cut from clicking under a reverb tail
        n = int(0.05 * rate)
        mono[-n:, 0] *= np.linspace(1.0, 0.0, n)
        out, _, _ = B.master(B.remove_dc(mono, rate, False), rate, lufs)
        path = os.path.join(SFX, "%s_v%d.wav" % (sid, i))
        B.write_wav(path, out, rate)
        print("wrote %s  LUFS %.1f  TP %.1f" % (os.path.basename(path), A.integrated_lufs(out, rate), A.true_peak_dbfs(out, rate)))


def register():
    with open(MANIFEST, encoding="utf-8") as f:
        m = json.load(f)
    for sid, sec in LOOP_SEC.items():
        m["sounds"][sid] = {"kind": "loop", "files": ["res://audio/loops/%s.wav" % sid], "loop_seconds": sec}
    for sid, (_, _, spatial) in EVENTS.items():
        m["sounds"][sid] = {"kind": "sfx", "files": ["res://audio/sfx/%s_v%d.wav" % (sid, i + 1) for i in range(VARIATIONS)],
                            "spatial": spatial}
    m["beds"].update(BEDS)
    m["bed_events"] = BED_EVENTS
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as f:
        json.dump(m, f, indent=1, ensure_ascii=False)
        f.write("\n")


def main():
    ids = sys.argv[1:] or list(LOOP_SEC) + list(EVENTS)
    spec = load_spec()
    update_spec(spec)
    os.makedirs(WORK, exist_ok=True)
    by_id = {s["id"]: s for s in spec["sounds"]}
    for sid in ids:
        if sid in LOOP_SEC:
            R.render_loop(by_id[sid], spec, os.path.join(B.AUDIO, "loops"), WORK)
        else:
            render_event(sid, spec)
    register()


if __name__ == "__main__":
    main()
