# -*- coding: utf-8 -*-
"""CLAP judgement of one-shots: do they read as a real recorded sound or as an
arcade / retro game effect? Runs in the CLAP venv:

    C:/fpear/Scripts/python.exe -B -X utf8 tools/clap_arcade.py <sfx dir> [<out json>] [--ids a,b]

For each id, every variation <id>_v<n>.wav is scored against its own real
description (REAL) and the ARCADE labels; arcade_share is the softmax mass on
the arcade labels, averaged over the variations. A number from a model, not
an ear: it tells which of two builds leans further toward "game effect".
"""
import glob
import json
import os
import sys

os.environ.setdefault("HF_HUB_OFFLINE", "1")
import librosa  # noqa: E402
import numpy as np  # noqa: E402
import torch  # noqa: E402
from transformers import ClapModel, ClapProcessor  # noqa: E402

MODEL = "laion/clap-htsat-unfused"
ARCADE = ["arcade game sound effect", "retro 8-bit video game sound", "low-fi bitcrushed digital sound effect",
          "synthesized beep"]
REAL = {
    "step_flesh_s1": "a realistic wet squelchy footstep on soft flesh",
    "step_flesh_s2": "a realistic wet squelchy footstep on soft flesh",
    "step_flesh_s3": "a realistic heavy wet footstep in mud",
    "step_tile_s1": "a realistic footstep on a tiled bathroom floor",
    "step_tile_s2": "a realistic footstep on a tiled bathroom floor",
    "step_tile_s3": "a realistic heavy wet footstep on a tiled floor",
    "tear_flesh": "realistic sound of tearing raw meat",
    "tear_fat": "realistic sound of tearing soft fat",
    "tear_nerve": "realistic sound of snapping a tough sinew",
    "tear_membrane": "realistic sound of ripping a wet membrane",
    "swallow": "a realistic recording of a person swallowing",
    "stomach_gurgle": "a realistic recording of a stomach gurgling",
    "regen_creak": "realistic creak of wet flesh growing",
    "nerve_twitch": "realistic wet twitch of a muscle",
}


def main():
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith("--") else ""
    ids = list(REAL)
    if "--ids" in sys.argv:
        ids = sys.argv[sys.argv.index("--ids") + 1].split(",")
    proc = ClapProcessor.from_pretrained(MODEL)
    model = ClapModel.from_pretrained(MODEL).eval()
    res = {}
    for sid in ids:
        labels = [REAL[sid]] + ARCADE
        with torch.no_grad():
            te = model.get_text_features(**proc(text=labels, return_tensors="pt", padding=True))
            te = te / te.norm(dim=-1, keepdim=True)
        shares = []
        for p in sorted(glob.glob(os.path.join(src, sid + "_v*.wav"))):
            y, _ = librosa.load(p, sr=48000, mono=True)
            with torch.no_grad():
                ae = model.get_audio_features(**proc(audios=[y], sampling_rate=48000, return_tensors="pt"))
                ae = ae / ae.norm(dim=-1, keepdim=True)
                s = torch.softmax((ae @ te.T)[0] * model.logit_scale_a.exp(), dim=0).numpy()
            shares.append(float(s[1:].sum()))
        if shares:
            res[sid] = round(float(np.mean(shares)), 3)
            print("%-16s arcade_share %.3f" % (sid, res[sid]))
    if out:
        with open(out, "w", encoding="utf-8") as f:
            json.dump(res, f, indent=1)


if __name__ == "__main__":
    main()
