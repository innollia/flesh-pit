# -*- coding: utf-8 -*-
"""CLAP judgement of the beds measure_beds.py wrote: does each one read as its
place and not as noise? Runs in the CLAP venv:

    C:/fpear/Scripts/python.exe -B -X utf8 tools/clap_beds.py <measure out dir> [<out json>]

Each bed's take is cut into 10 s pieces, each piece is scored against every
label and the scores are averaged. A piece is one bed heard for 10 s, so a bed
that lives in events is judged with the events in it.
"""
import json
import os
import sys

os.environ.setdefault("HF_HUB_OFFLINE", "1")
import librosa  # noqa: E402
import numpy as np  # noqa: E402
import torch  # noqa: E402
from transformers import ClapModel, ClapProcessor  # noqa: E402

PLACES = {
    "body_a": "wet flesh slowly pressing and breathing, inside a living body",
    "body_b": "a deep low groaning moan from inside a huge heavy body",
    "fat_caves": "thick grease bubbling slowly in a warm cave",
    "rib_vault": "cold hollow air blowing across bones in a huge empty vault",
    "gut_folds": "stomach gurgling, liquid squeezed through intestines",
    "cloth_wads": "fabric rustling and crumpling, clothes shifting",
    "hair_thicket": "dry hair brushing and rustling, thin strands",
}
NOISE = ["white noise", "static hiss", "wind blowing", "air conditioner hum", "ocean waves", "rain"]
MODEL = "laion/clap-htsat-unfused"


def main():
    src = sys.argv[1]
    labels = list(PLACES.values()) + NOISE
    proc = ClapProcessor.from_pretrained(MODEL)
    model = ClapModel.from_pretrained(MODEL).eval()
    with torch.no_grad():
        tin = proc(text=labels, return_tensors="pt", padding=True)
        te = model.get_text_features(**tin)
        te = te / te.norm(dim=-1, keepdim=True)
    res = {}
    for bed in PLACES:
        y, _ = librosa.load(os.path.join(src, bed + ".wav"), sr=48000, mono=True)
        n = 10 * 48000
        pieces = [y[i:i + n] for i in range(0, len(y) - n + 1, n)]
        scores = []
        for p in pieces:
            with torch.no_grad():
                ain = proc(audios=[p], sampling_rate=48000, return_tensors="pt")
                ae = model.get_audio_features(**ain)
                ae = ae / ae.norm(dim=-1, keepdim=True)
                scores.append(torch.softmax((ae @ te.T)[0] * model.logit_scale_a.exp(), dim=0).numpy())
        s = np.mean(scores, axis=0)
        order = np.argsort(-s)
        own = float(s[labels.index(PLACES[bed])])
        noise = float(sum(s[labels.index(k)] for k in NOISE))
        res[bed] = {"own": round(own, 3), "own_rank": int(np.where(order == labels.index(PLACES[bed]))[0][0]) + 1,
                    "noise_share": round(noise, 3), "top": labels[int(order[0])], "top_score": round(float(s[order[0]]), 3)}
        print("%-13s own %.3f rank %d  noise %.3f  top: %s (%.3f)" % (bed, own, res[bed]["own_rank"], noise, labels[int(order[0])], s[order[0]]))
    right = sum(1 for v in res.values() if v["own_rank"] == 1)
    print("own place first in %d of %d; mean noise share %.3f" % (right, len(res), np.mean([v["noise_share"] for v in res.values()])))
    if len(sys.argv) > 2:
        with open(sys.argv[2], "w", encoding="utf-8") as f:
            json.dump(res, f, indent=1, ensure_ascii=False)


if __name__ == "__main__":
    main()
