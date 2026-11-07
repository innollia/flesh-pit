# -*- coding: utf-8 -*-
"""CLAP ear: old lab_artstyle vs lab_artstyle_organic on style prompts, plus loudness.
Runs in the CLAP venv:

    C:/fpear/Scripts/python.exe -B -X utf8 clap_compare.py <music-lab dir> <loved pause_alt wav> [<out json>]

Each song is cut into 10 s pieces; each piece is scored against all prompts (softmax over
the prompt set, as tools/clap_beds.py does) and the scores are averaged. Raw cosine
similarity per prompt is kept too, and the audio embedding's cosine to the two songs the
user loves (lab_emotion, mus_pause_alt).
"""
import json
import os
import sys

os.environ.setdefault("HF_HUB_OFFLINE", "1")
import librosa  # noqa: E402
import numpy as np  # noqa: E402
import scipy.signal as sg  # noqa: E402
import torch  # noqa: E402
from transformers import ClapModel, ClapProcessor  # noqa: E402

PROMPTS = {
    "upbeat": "upbeat energetic music with a driving beat",
    "electronic": "electronic synthesizer music",
    "organic": "organic acoustic music played by hand on real instruments",
    "warm": "warm soft intimate music",
}
MODEL = "laion/clap-htsat-unfused"
SR = 48000


def lufs_tp(path):
    x, sr = librosa.load(path, sr=None, mono=False)
    x = np.atleast_2d(x).T
    pre = np.array([[1.53512485958697, -2.69169618940638, 1.19839281085285, 1, -1.69065929318241, 0.73248077421585],
                    [1, -2, 1, 1, -1.99004745483398, 0.99007225036621]])
    y = sg.sosfilt(pre, x, axis=0)
    bl, hop = int(0.4 * sr), int(0.1 * sr)
    pw = np.array([np.sum(np.mean(y[i:i + bl] ** 2, 0)) for i in range(0, len(y) - bl, hop)])
    l_ = -0.691 + 10 * np.log10(pw + 1e-14)
    rel = -0.691 + 10 * np.log10(pw[l_ > -70].mean()) - 10
    I = -0.691 + 10 * np.log10(pw[l_ > rel].mean())
    tp = np.abs(sg.resample_poly(x, 4, 1, axis=0)).max()
    return round(float(I), 2), round(float(20 * np.log10(tp)), 2), round(len(x) / sr, 2)


def main():
    lab, pause_alt = sys.argv[1], sys.argv[2]
    songs = {"old": os.path.join(lab, "lab_artstyle.wav"), "new": os.path.join(lab, "lab_artstyle_organic.wav")}
    refs = {"lab_emotion": os.path.join(lab, "lab_emotion.wav"), "mus_pause_alt": pause_alt}
    proc = ClapProcessor.from_pretrained(MODEL)
    model = ClapModel.from_pretrained(MODEL).eval()
    torch.set_grad_enabled(False)
    keys = list(PROMPTS)
    with torch.no_grad():
        te = model.get_text_features(**proc(text=[PROMPTS[k] for k in keys], return_tensors="pt", padding=True))
        te = te / te.norm(dim=-1, keepdim=True)

    def embed(path):
        y, _ = librosa.load(path, sr=SR, mono=True)
        n = 10 * SR
        out = []
        for i in range(0, len(y) - n + 1, n):
            with torch.no_grad():
                ae = model.get_audio_features(**proc(audios=[y[i:i + n]], sampling_rate=SR, return_tensors="pt"))
            out.append((ae / ae.norm(dim=-1, keepdim=True))[0])
        return torch.stack(out)

    ref_mean = {}
    for k, p in refs.items():
        e = embed(p).mean(0)
        ref_mean[k] = e / e.norm()
    res = {}
    extra = {os.path.splitext(os.path.basename(p))[0]: p for p in sys.argv[4:]}
    for name, path in {**songs, **refs, **extra}.items():
        ae = embed(path)
        cos = ae @ te.T
        soft = torch.softmax(cos * model.logit_scale_a.exp(), dim=1).mean(0).detach().numpy()
        m = ae.mean(0)
        m = m / m.norm()
        I, tp, ln = lufs_tp(path)
        res[name] = {"softmax": {k: round(float(soft[i]), 3) for i, k in enumerate(keys)},
                     "cosine": {k: round(float(cos[:, i].mean()), 3) for i, k in enumerate(keys)},
                     "pieces": int(ae.shape[0]),
                     "sim_to": {k: round(float(m @ v), 3) for k, v in ref_mean.items()},
                     "lufs": I, "true_peak_dbtp": tp, "seconds": ln}
        print(name, json.dumps(res[name], ensure_ascii=False))
    if len(sys.argv) > 3:
        with open(sys.argv[3], "w", encoding="utf-8") as f:
            json.dump({"prompts": PROMPTS, "results": res}, f, indent=1, ensure_ascii=False)


if __name__ == "__main__":
    main()
