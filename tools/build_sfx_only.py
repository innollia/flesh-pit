# -*- coding: utf-8 -*-
"""Rebuilds only the named one-shots of game/tools/audio/sounds.json with the
build_audio.py steps (nkido render of the seeded variations, CC0 real layer,
PS1 level from sounds.json, DC removal, mastering), without touching the
loops or manifest.json. build_audio.py run whole rewrites the manifest and
every loop, which the bed and music builders then have to redo; this does
not.

    python -X utf8 tools/build_sfx_only.py step_flesh_s1 step_tile_s1 ...
    python -X utf8 tools/build_sfx_only.py --out <dir> step_flesh_s1   # side folder, game untouched
    python -X utf8 tools/build_sfx_only.py --out <dir> --ps1 off step_flesh_s1   # try a PS1 level

The variation choice is build_audio.py's: render all seeds, keep the four with
distinct spectra and the smallest level spread. File names stay <id>_v<n>.wav,
so the manifest entries are unchanged.
"""
import argparse
import itertools
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIO_TOOLS = os.path.join(HERE, "..", "game", "tools", "audio")
sys.path.insert(0, AUDIO_TOOLS)
import build_audio as B  # noqa: E402


def build_one(s, spec, rate, out_dir, ps1_override=""):
    sid = s["id"]
    patch = open(os.path.join(AUDIO_TOOLS, "patches", sid + ".akkado"), encoding="utf-8").read()
    os.makedirs(B.BUILD, exist_ok=True)
    cands = []
    for c, (seed, seed2, pitch) in enumerate(spec["variations"], start=1):
        raw = os.path.join(B.BUILD, "%s_c%d_raw.wav" % (sid, c))
        B.render(B.variant_patch(patch, seed, seed2, pitch), raw, float(s["seconds"]), rate)
        data, _ = B.A.read_wav(raw)
        mono = data.mean(axis=1, keepdims=True)
        cands.append((B.A.integrated_lufs(mono, rate), mono))
    targets = json.load(open(os.path.join(AUDIO_TOOLS, "targets.json"), encoding="utf-8"))
    var_t = targets["variation"]
    keep = int(spec.get("variations_keep", 4))
    best = None
    for combo in itertools.combinations(range(len(cands)), keep):
        lv = [cands[i][0] for i in combo]
        if not all(math.isfinite(v) for v in lv):
            continue
        dmin = min(B.log_spectral_distance(cands[i][1][:, 0], cands[j][1][:, 0]) for i, j in itertools.combinations(combo, 2))
        key = (0 if dmin >= var_t["spectral_distance_min_db"] else 1, max(lv) - min(lv))
        if best is None or key < best[0]:
            best = (key, combo)
    chosen = best[1] if best else tuple(range(keep))
    real = B.load_real_layer(s.get("real_layer"), rate, float(s["seconds"]))
    level = B.ps1_level(s, spec.get("ps1_default", "off"), ps1_override)
    written = []
    for n, i in enumerate(chosen, start=1):
        mono = cands[i][1]
        if real is not None:
            take = min(real.size, mono.shape[0])
            mono = mono.copy()
            mono[:take, 0] += real[:take]
        mono = B.ps1_treat(mono, rate, level, False)
        out, _, _ = B.master(B.remove_dc(mono, rate, False), rate, float(s["target_lufs"]))
        path = os.path.join(out_dir, "%s_v%d.wav" % (sid, n))
        B.write_wav(path, out, rate)
        written.append(path)
    return level, written


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="+")
    ap.add_argument("--out", default=os.path.join(B.AUDIO, "sfx"))
    ap.add_argument("--ps1", default="", help="try another PS1 level (off/subtle/light/mid/strong) without editing sounds.json")
    args = ap.parse_args()
    spec = json.load(open(os.path.join(AUDIO_TOOLS, "sounds.json"), encoding="utf-8"))
    rate = int(spec["rate"])
    by_id = {s["id"]: s for s in spec["sounds"]}
    for sid in args.ids:
        s = by_id.get(sid)
        if s is None or s["kind"] != "sfx":
            raise SystemExit("not a one-shot in sounds.json: " + sid)
        level, written = build_one(s, spec, rate, args.out, args.ps1)
        print("%s ps1=%s -> %d files" % (sid, level, len(written)))


if __name__ == "__main__":
    main()
