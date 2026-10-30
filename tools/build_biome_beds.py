# -*- coding: utf-8 -*-
"""Synthesizes the biome bed layers (game/audio/loops/amb_<biome>.wav).

    python -X utf8 tools/build_biome_beds.py

Each is an 8 s seamless stereo loop at 48 kHz, layered over the shell's own
body bed (game/audio/manifest.json "beds"): fat caves bubble, the rib vault
breathes cold air through gristle, the gut folds thump on a slow beat, the
clothing wads rustle muffled, the hair thicket hisses dry.
Seamless: everything is built from whole-cycle waves over the loop or from
noise crossfaded across the loop point.
"""
import math
import os
import wave

import numpy as np

RATE = 48000
SEC = 8.0
N = int(RATE * SEC)
OUT = os.path.join(os.path.dirname(__file__), "..", "game", "audio", "loops")
t = np.arange(N) / RATE


def rng(seed):
    return np.random.default_rng(seed)


def loop_noise(seed, cutoff_hz):
    """Low-passed noise made seamless by crossfading the tail into the head."""
    r = rng(seed)
    pad = RATE
    x = r.standard_normal(N + pad)
    # one-pole low pass, run twice for a softer slope
    a = math.exp(-2 * math.pi * cutoff_hz / RATE)
    for _ in range(2):
        y = np.empty_like(x)
        acc = 0.0
        for i in range(len(x)):
            acc = a * acc + (1 - a) * x[i]
            y[i] = acc
        x = y
    head = x[:N].copy()
    fade = np.linspace(0, 1, pad)
    head[:pad] = head[:pad] * fade + x[N:N + pad] * (1 - fade)
    return head / (np.abs(head).max() + 1e-9)


def wobble(cycles, phase=0.0):
    """Slow periodic 0..1 envelope with a whole number of cycles per loop."""
    return 0.5 + 0.5 * np.sin(2 * math.pi * cycles * t / SEC + phase)


def blips(seed, count, f_lo, f_hi, dur):
    r = rng(seed)
    out = np.zeros(N)
    for _ in range(count):
        start = int(r.uniform(0, N))
        f0 = r.uniform(f_lo, f_hi)
        n = int(dur * RATE)
        tt = np.arange(n) / RATE
        # a bubble: rising chirp with a fast decay
        s = np.sin(2 * math.pi * (f0 * tt + f0 * 1.8 * tt * tt / dur)) * np.exp(-tt / (dur * 0.25))
        idx = (start + np.arange(n)) % N
        out[idx] += s * r.uniform(0.3, 1.0)
    return out


def fat_caves():
    base = loop_noise(1, 180) * (0.35 + 0.25 * wobble(2))
    return base * 0.5 + blips(2, 26, 140, 420, 0.12) * 0.35


def rib_vault():
    air = loop_noise(3, 900) * (0.25 + 0.6 * wobble(1, 1.0))
    tone = np.sin(2 * math.pi * 55 * t) * 0.08 * wobble(2)
    creak = blips(4, 5, 60, 110, 0.6) * 0.25
    return air * 0.45 + tone + creak


def gut_folds():
    # a squeeze every 4 s (twice per loop): a swelling low thump and a wet slide
    beat = np.zeros(N)
    for k in range(2):
        c = k * SEC / 2
        d = ((t - c) % SEC)
        env = np.where(d < 1.5, d / 1.5, np.where(d < 2.5, 1.0, np.maximum(0, 1 - (d - 2.5) / 1.5)))
        beat += env * np.sin(2 * math.pi * 38 * t) * 0.5
    slide = loop_noise(5, 300) * (0.2 + 0.5 * wobble(2, -1.2))
    return beat * 0.7 + slide * 0.35


def cloth_wads():
    rustle = loop_noise(6, 2500) * (0.15 + 0.3 * wobble(3, 0.4))
    r = rng(7)
    crackle = np.zeros(N)
    for i in r.integers(0, N, 400):
        crackle[i] = r.uniform(-1, 1)
    damp = loop_noise(8, 120) * 0.3
    return rustle * 0.35 + crackle * 0.25 + damp


def hair_thicket():
    hiss = loop_noise(9, 5000) * (0.2 + 0.25 * wobble(2, 2.0))
    hum = (np.sin(2 * math.pi * 220 * t) + 0.5 * np.sin(2 * math.pi * 330 * t)) * 0.03 * wobble(1)
    return hiss * 0.3 + hum


def save(name, mono):
    mono = mono / (np.abs(mono).max() + 1e-9) * 0.5
    # a little stereo width: right is the left delayed by 7 ms (wraps, so seamless)
    right = np.roll(mono, int(0.007 * RATE))
    data = (np.stack([mono, right], -1) * 32767).astype("<i2")
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())
    print("wrote", path)


if __name__ == "__main__":
    for fn in (fat_caves, rib_vault, gut_folds, cloth_wads, hair_thicket):
        save("amb_%s.wav" % fn.__name__, fn())
