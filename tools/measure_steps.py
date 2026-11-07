# -*- coding: utf-8 -*-
"""Measures footsteps in an engine take of game/tests/capture_steps.gd (old vs
new, round7-sfx). Numbers, not an ear.

    python -X utf8 tools/measure_steps.py <take.wav> [<take.wav> ...]

Per segment (SEGS, the frames the capture prints, 30 fps), each step at
seg + 0.5 s + k * 0.55 s is cut 0..0.45 s and compared with the bed in the
quietest 80 ms before it:

  over_bed     step peak (10 ms RMS) over the bed's level, dB, median
  level_sd     standard deviation of the steps' peak levels, dB
  same         mean correlation of each step's 10 ms envelope with the next
               one's (1 = every step the same shape)
  tail         energy 120..450 ms after the onset vs 0..120 ms, dB (room)
  centroid     spectral centroid of the step cut minus the bed, Hz, median
"""
import sys
import wave

import numpy as np

RATE = 48000
SEGS = {"body_a": (5, 366), "rib_vault": (366, 727), "restroom": (727, 1028)}
GAP = 0.55


def read(path):
    with wave.open(path, "rb") as w:
        x = np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(np.float64) / 32768.0
        x = x.reshape(-1, w.getnchannels()).mean(axis=1)
        sr = w.getframerate()
    if sr != RATE:
        raise SystemExit("expected 48 kHz")
    return x


def rms_db(x):
    return 10 * np.log10((x ** 2).mean() + 1e-14)


def env(x, win=480):
    n = len(x) // win
    return np.sqrt((x[:n * win].reshape(n, win) ** 2).mean(axis=1))


def measure(x):
    out = {}
    for seg, (a, b) in SEGS.items():
        t0, t1 = a / 30.0, b / 30.0
        at = t0 + 0.5 + GAP  # skip the first step (bed still fading in)
        over, peaks, envs, tails, cents = [], [], [], [], []
        while at + 0.5 < t1:
            i = int(at * RATE)
            cut = x[i - int(0.02 * RATE):i + int(0.45 * RATE)]
            bed = x[i - int(0.12 * RATE):i - int(0.02 * RATE)]
            e = env(cut)
            bed_db = 20 * np.log10(np.percentile(env(bed), 30) + 1e-9)
            pk = 20 * np.log10(e.max() + 1e-9)
            over.append(pk - bed_db)
            peaks.append(pk)
            envs.append(e / (e.max() + 1e-12))
            k = int(np.argmax(e)) * 480
            head = cut[max(0, k - 480):k + int(0.12 * RATE)]
            tail = cut[k + int(0.12 * RATE):k + int(0.45 * RATE)]
            tails.append(rms_db(tail) + 10 * np.log10(len(tail) / max(len(head), 1)) - rms_db(head) if len(tail) else -99)
            f = np.fft.rfftfreq(len(cut), 1 / RATE)
            p = np.abs(np.fft.rfft(cut)) ** 2
            pb = np.abs(np.fft.rfft(np.resize(bed, len(cut)))) ** 2
            q = np.maximum(p - pb, 0)
            cents.append((f * q).sum() / max(q.sum(), 1e-20))
            at += GAP
        L = min(len(e) for e in envs)
        same = np.mean([np.corrcoef(envs[j][:L], envs[j + 1][:L])[0, 1] for j in range(len(envs) - 1)])
        out[seg] = {"steps": len(over), "over_bed": round(float(np.median(over)), 1),
                    "level_sd": round(float(np.std(peaks)), 2), "same": round(float(same), 3),
                    "tail": round(float(np.median(tails)), 1), "centroid": int(np.median(cents))}
    return out


def main():
    for p in sys.argv[1:]:
        print(p.replace("\\", "/").split("/")[-1])
        for seg, r in measure(read(p)).items():
            print("  %-10s %s" % (seg, r))


if __name__ == "__main__":
    main()
