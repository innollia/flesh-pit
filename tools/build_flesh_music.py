# -*- coding: utf-8 -*-
"""Builds the flesh's three songs (game/audio/loops/mus_flesh_*.wav) from the
candidate patches the user liked, and registers them in game/audio/manifest.json
and the phrase marks in game/audio/flesh_music.json.

    python -X utf8 tools/build_flesh_music.py            # render with nkido
    python -X utf8 tools/build_flesh_music.py --from build/music-lab
                                                         # reuse rendered lab wavs

Every sound comes from nkido through each candidate's own build script
(game/tools/audio/lab/<name>/build.py, which renders its .akkado patches, folds
the loop and sets -28 LUFS). The lab folder is copied to build/flesh-music/<name>/
first, so a render never writes into the patches in the repository (the cycle
script writes its score into its patches). Python here only copies the folded
loop, checks its seam and length, and writes the registry.

Which song plays where is audio/fp_flesh_music.gd (one per shell):

  mus_flesh_core     lab_emotion    the core     3/4 lullaby, disgust slides into appetite
  mus_flesh_mantle   lab_materials  the mantle   7/8 groove of drips, tile, pipe, meat, teeth, breath
  mus_flesh_surface  lab_cycle      the surface  tear / chew / swallow / vomit, 144 BPM
"""
import argparse
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
GAME = os.path.join(ROOT, "game")
LAB = os.path.join(GAME, "tools", "audio", "lab")
WORK = os.path.join(ROOT, "build", "flesh-music")
LOOPS = os.path.join(GAME, "audio", "loops")
MANIFEST = os.path.join(GAME, "audio", "manifest.json")
CONFIG = os.path.join(GAME, "audio", "flesh_music.json")
RATE = 48000

# shell order: core, mantle, surface
SONGS = [("mus_flesh_core", "emotion"), ("mus_flesh_mantle", "materials"), ("mus_flesh_surface", "cycle")]
# emotion and materials: 2.5 s bars (24 cycles a minute), four-bar phrases
BAR_PHRASE = 10.0


def render(name):
    src = os.path.join(LAB, name)
    dst = os.path.join(WORK, name)
    shutil.rmtree(dst, ignore_errors=True)
    shutil.copytree(src, dst)
    print("render", name, "->", dst, flush=True)
    subprocess.run([sys.executable, "-X", "utf8", "build.py"], cwd=dst, check=True)
    return os.path.join(dst, "lab_%s.wav" % name)


def read(path):
    with wave.open(path, "rb") as w:
        assert w.getframerate() == RATE and w.getnchannels() == 2 and w.getsampwidth() == 2, path
        raw = w.readframes(w.getnframes())
    return raw, np.frombuffer(raw, "<i2").reshape(-1, 2).astype(np.float64) / 32768.0


def cycle_phrases(seconds):
    """Section starts (tear, chew, swallow, purge of each round) of lab_cycle."""
    spec = importlib.util.spec_from_file_location("lab_cycle_build", os.path.join(LAB, "cycle", "build.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    at, out = 0, []
    for c in mod.CYCLES:
        for part in (sum(c["tear"]), sum(c["chew"]), sum(c["swallow"]), c["purge"]):
            out.append(round(at * mod.STEP / mod.SR, 4))
            at += part
    assert abs(at * mod.STEP / mod.SR - seconds) < 0.01, (at, seconds)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="src", help="folder with already rendered lab_<name>.wav")
    a = ap.parse_args()
    with open(MANIFEST, encoding="utf-8") as f:
        manifest = json.load(f)
    with open(CONFIG, encoding="utf-8") as f:
        config = json.load(f)
    for i, (sid, name) in enumerate(SONGS):
        path = os.path.join(a.src, "lab_%s.wav" % name) if a.src else render(name)
        raw, x = read(path)
        seconds = round(len(x) / RATE, 4)
        steps = np.abs(np.diff(x, axis=0)).max(axis=1)
        jump = float(np.abs(x[0] - x[-1]).max())
        p999 = float(np.percentile(steps, 99.9))
        print("%-18s %s  %.3f s  seam jump %.4f (p99.9 step %.4f)" % (sid, name, seconds, jump, p999))
        assert jump <= 2.0 * p999, "%s: the loop seam jumps" % sid
        out = os.path.join(LOOPS, sid + ".wav")
        with wave.open(out, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(raw)
        manifest["sounds"][sid] = {"kind": "loop", "files": ["res://audio/loops/%s.wav" % sid], "loop_seconds": seconds}
        shell = config["shells"][i]
        assert shell["song"] == sid, (shell, sid)
        shell["source"] = "lab_" + name
        shell["loop_seconds"] = seconds
        if name == "cycle":
            shell["phrases"] = cycle_phrases(seconds)
        else:
            shell["phrases"] = [round(t * BAR_PHRASE, 4) for t in range(int(round(seconds / BAR_PHRASE)))]
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1, ensure_ascii=False)
        f.write("\n")
    with open(CONFIG, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print("wrote", MANIFEST, "and", CONFIG)


if __name__ == "__main__":
    main()
