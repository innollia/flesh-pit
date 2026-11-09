# -*- coding: utf-8 -*-
"""Renders named loop patches through the same chain as
game/tools/audio/build_audio.py (nkido, loopify fold, CC0 real_layer, rotate, PS1, DC,
master)
and writes only those loops, leaving manifest.json and every other sound alone.

    python -X utf8 tools/render_loop_patches.py amb_heart_a amb_heart_b amb_restroom
    python -X utf8 tools/render_loop_patches.py --out <dir> amb_heart_a

Use it instead of build_audio.py when a small change to a patch or to its
sounds.json entry must not rewrite the manifest (the builders that add to it
would all have to run again). A full build_audio.py run gives the same files.
"""
import argparse
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "game", "tools", "audio"))
import analyze_audio as A  # noqa: E402
import build_audio as B  # noqa: E402
import loopify  # noqa: E402


def render_loop(entry, spec, out_dir, work):
    sid = entry["id"]
    rate = int(spec["rate"])
    loop = float(entry["loop_seconds"])
    fade = float(entry["fade_seconds"])
    with open(os.path.join(B.HERE, "patches", sid + ".akkado"), encoding="utf-8") as f:
        patch = f.read()
    raw = os.path.join(work, sid + "_raw.wav")
    folded = os.path.join(work, sid + "_fold.wav")
    B.render(patch, raw, loop + fade + 0.25, rate)
    loopify.fold_file(raw, folded, int(round(loop * rate)), int(round(fade * rate)), quiet=True)
    data, _ = A.read_wav(folded)
    # the CC0 recording layer, summed as build_audio.py does (round9-hand-tear)
    real = B.load_real_layer(entry.get("real_layer"), rate, loop)
    if real is not None:
        take = min(real.size, data.shape[0])
        data = data.copy()
        data[:take, :] += real[:take, None]
    rot = int(round(float(entry.get("rotate_seconds", 0.0)) * rate))
    if rot:
        data = np.roll(data, -rot, axis=0)
    data = B.ps1_treat(data, rate, B.ps1_level(entry, spec.get("ps1_default", "off"), ""), True)
    data = B.remove_dc(data, rate, True)
    out, _, _ = B.master(data, rate, float(entry["target_lufs"]))
    path = os.path.join(out_dir, sid + ".wav")
    B.write_wav(path, out, rate)
    seam = A.loop_discontinuity(out)
    print("wrote %s  LUFS %.1f  TP %.1f  seam %.3f  wrap_hf %.1f dB" % (
        path, A.integrated_lufs(out, rate), A.true_peak_dbfs(out, rate), seam["jump_ratio"], seam["wrap_hf_dbfs"]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="+")
    ap.add_argument("--out", default=os.path.join(B.AUDIO, "loops"))
    args = ap.parse_args()
    with open(os.path.join(B.HERE, "sounds.json"), encoding="utf-8") as f:
        spec = json.load(f)
    by_id = {s["id"]: s for s in spec["sounds"] if s["kind"] == "loop"}
    os.makedirs(B.BUILD, exist_ok=True)
    os.makedirs(args.out, exist_ok=True)
    for sid in args.ids:
        render_loop(by_id[sid], spec, args.out, B.BUILD)


if __name__ == "__main__":
    main()
