# -*- coding: utf-8 -*-
"""Synthesizes the one-shots for game signals that had no sound
(game/audio/sfx/<id>_v1..v4.wav) and registers them in
game/audio/manifest.json.

    python -X utf8 tools/build_wire_sounds.py

  hair_rustle  M23 sensory hairs (docs/spec/05-mutations.md): the stiff arm
               hairs shiver before a squeeze. A dry, fine rustle: thousands of
               tiny bristle ticks with a fast shiver flutter, no wetness.
  gulp_whole   M15 unhinged jaw: the whole carried pile goes down in one
               mouthful. A wet mouth slosh, then a real recorded gulp (CC0,
               a different recording from the stomach swallow) slowed to 0.88
               so it is deeper and longer, and a breath out through the nose.
  vent_spill   An absurd overpay (spec 03 7): early items tumble out of the
               vent. Hard objects (metal tools, plastic cans) hit the tile
               floor, bounce and settle, front-loaded like a spilled armful.
  ui_deny      The mirror refuses a part the hairs cannot pay for: two dull
               falling notes, quieter than a click is sharp.

Each sound gets 4 variations (seed and a small pitch change), so the bank
never repeats one back to back. Levels are mastered to TARGET_LUFS next to
comparable sounds (swallow, coin_drop, ui_click measured with the same
analyzer). Note: game/tools/audio/build_audio.py rewrites manifest.json from
its own list; run this builder (and build_song_layers.py) again after it.
"""
import json
import math
import os
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "game", "tools", "audio"))
import analyze_audio as A  # noqa: E402

RATE = 48000
OUT = os.path.join(HERE, "..", "game", "audio", "sfx")
MANIFEST = os.path.join(HERE, "..", "game", "audio", "manifest.json")

# swallow -20.7, coin_drop -21.0, ui_click -29.9 (integrated, v1)
TARGET_LUFS = {"hair_rustle": -22.0, "gulp_whole": -19.0, "vent_spill": -20.0, "ui_deny": -24.0}
SPATIAL = {"hair_rustle": False, "gulp_whole": False, "vent_spill": True, "ui_deny": False}
VARIATIONS = [(101, 1.0), (907, 0.97), (233, 1.03), (619, 0.985)]


def onepole_lp(x, hz):
    a = math.exp(-2 * math.pi * hz / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = a * acc + (1 - a) * x[i]
        y[i] = acc
    return y


def bandpass(x, lo, hi):
    """FFT brick-ish band with soft edges (offline, so no phase worries)."""
    n = len(x)
    f = np.fft.rfftfreq(n, 1.0 / RATE)
    g = 1.0 / (1.0 + (lo / np.maximum(f, 1.0)) ** 4) / (1.0 + (f / hi) ** 4)
    return np.fft.irfft(np.fft.rfft(x) * g, n)


def env_adsr(n, a, r, curve=2.0):
    t = np.arange(n) / RATE
    dur = n / RATE
    e = np.minimum(1.0, t / max(a, 1e-4))
    tail = np.clip((dur - t) / max(r, 1e-4), 0, 1) ** curve
    return e * tail


def hair_rustle(rng, pitch):
    sec = 0.75
    n = int(sec * RATE)
    t = np.arange(n) / RATE
    out = np.zeros(n)
    # bristle ticks: very short high bursts, dense in the middle
    dens = np.sin(np.pi * np.clip(t / sec, 0, 1)) ** 0.7
    count = 2600
    times = rng.choice(n, size=count, p=dens / dens.sum())
    for at in times:
        m = int(rng.uniform(0.00015, 0.0007) * RATE)
        if at + m >= n:
            continue
        burst = rng.standard_normal(m) * np.exp(-np.arange(m) / (m * 0.3))
        out[at:at + m] += burst * rng.uniform(0.2, 1.0)
    out = bandpass(out, 2600 * pitch, 11000 * pitch)
    # a faint brushed hiss under the ticks
    hiss = bandpass(rng.standard_normal(n), 3500, 9000) * 0.18
    out = out + hiss
    # the shiver: a fast uneven flutter (the hairs shake, ~22-30 Hz)
    rate = rng.uniform(22, 30) * pitch
    flutter = 0.55 + 0.45 * np.abs(np.sin(np.pi * rate * t + 0.6 * np.sin(2 * np.pi * 3.1 * t)))
    return out * flutter * env_adsr(n, 0.06, 0.32, 1.6)


# "Mouth Noises #1" by Joseph SARDIN, bigsoundbank.com, CC0 (already in the
# repo: game/tools/audio/PROVENANCE.md 4th pass, chew2/fs0352). Its gulp at
# 3.47..4.35 s is the only window of the three mouth/chew recordings that
# CLAP ranks first as "a person gulping and swallowing a big mouthful" (0.93).
# The stomach swallow uses a different recording (swallow/fs158479).
GULP_SAMPLE = {"path": os.path.join(HERE, "..", "game", "tools", "audio", "samples", "src", "chew2", "fs0352.wav"),
               "start": 3.47, "end": 4.35, "pitch": 0.88}


def real_gulp(pitch):
    x, r = A.read_wav(GULP_SAMPLE["path"])
    x = x[:, 0] if x.ndim > 1 else x
    seg = x[int(GULP_SAMPLE["start"] * r):int(GULP_SAMPLE["end"] * r)]
    n_out = int(len(seg) / pitch * RATE / r)
    seg = np.interp(np.arange(n_out) * pitch * r / RATE, np.arange(len(seg)), seg)
    seg = bandpass(seg, 60, 6500)
    fade = int(0.01 * RATE)
    seg[:fade] *= np.linspace(0, 1, fade)
    seg[-fade:] *= np.linspace(1, 0, fade)
    return seg


def gulp_whole(rng, pitch):
    sec = 1.3
    n = int(sec * RATE)
    t = np.arange(n) / RATE
    out = np.zeros(n)

    def put(seg, start):
        a = int(start * RATE)
        e = min(n, a + len(seg))
        out[a:e] += seg[:e - a]

    # 1) the mouthful sloshing at the back of the mouth (0..0.28 s): wet
    #    noise ticks
    slosh = bandpass(rng.standard_normal(n), 400, 3000)
    bub = np.zeros(n)
    for c in rng.uniform(0.02, 0.26, 10):
        bub += np.exp(-((t - c) / 0.008) ** 2) * rng.uniform(0.4, 1.0)
    out += slosh * bub * 0.12

    # 2) the real gulp (CC0 recording, see GULP_SAMPLE) slowed down a little:
    # a bigger, deeper mouthful than the stomach swallow
    real = real_gulp(pitch * GULP_SAMPLE["pitch"])
    put(real / (np.abs(real).max() + 1e-9) * 1.1, 0.24)
    # (a synthesized throat push under it read as "a drum hit" to CLAP, so
    # the recording carries the gulp alone)
    # 3) a short breath out through the nose after it is down
    breath = bandpass(rng.standard_normal(n), 600, 4500) * np.exp(-((t - 1.18) / 0.06) ** 2) * 0.06
    out += breath
    return out * env_adsr(n, 0.004, 0.12)


METAL = [1.0, 2.76, 5.40, 8.93]
PLASTIC = [1.0, 1.59, 2.14, 2.30]


def impact(rng, f0, ratios, decay, amp, m):
    tt = np.arange(m) / RATE
    tone = np.zeros(m)
    for k, r in enumerate(ratios):
        tone += np.sin(2 * np.pi * f0 * r * tt + rng.uniform(0, 6.28)) * np.exp(-tt / (decay / (1 + 0.6 * k))) / (1 + k * 0.7)
    # the hit itself: a hard noisy knock, and the hollow body of the object
    tick = bandpass(rng.standard_normal(m), 600, 9000) * np.exp(-tt / 0.004)
    thud = bandpass(rng.standard_normal(m), 120, 900) * np.exp(-tt / 0.02)
    return (0.35 * tone + 1.2 * tick + 0.8 * thud) * amp


def vent_spill(rng, pitch):
    sec = 1.8
    n = int(sec * RATE)
    out = np.zeros(n)
    items = 11
    for i in range(items):
        metal = rng.uniform() < 0.6
        ratios = METAL if metal else PLASTIC
        f0 = (rng.uniform(700, 2400) if metal else rng.uniform(220, 600)) * pitch
        decay = rng.uniform(0.03, 0.09) if metal else rng.uniform(0.015, 0.04)
        # they come out in a burst: most land in the first half second
        at = rng.uniform(0.0, 0.18) + i * rng.uniform(0.03, 0.07)
        amp = rng.uniform(0.6, 1.0)
        gap = rng.uniform(0.09, 0.18)
        for _b in range(rng.integers(2, 5)):
            a = int(at * RATE)
            m = int(min(0.6, decay * 6) * RATE)
            if a >= n:
                break
            seg = impact(rng, f0 * rng.uniform(0.98, 1.02), ratios, decay, amp, m)
            e = min(n, a + m)
            out[a:e] += seg[:e - a]
            at += gap
            gap *= rng.uniform(0.55, 0.75)
            amp *= rng.uniform(0.35, 0.55)
    # one can rolls a moment on the tile before it stops
    tr = np.arange(int(0.5 * RATE)) / RATE
    roll = bandpass(rng.standard_normal(len(tr)), 900, 4000) * (0.5 + 0.5 * np.sin(2 * np.pi * 14 * tr) ** 2) * np.exp(-tr / 0.18) * 0.12
    a = int(rng.uniform(0.7, 0.9) * RATE)
    out[a:a + len(tr)] += roll[:max(0, min(len(tr), n - a))]
    return out * env_adsr(n, 0.001, 0.2)


def ui_deny(rng, pitch):
    notes = [(0.0, 0.10, 196.0), (0.12, 0.16, 147.0)]
    sec = 0.5  # padded like ui_click (0.5 s), so the 400 ms loudness blocks fit
    n = int(sec * RATE)
    out = np.zeros(n)
    for start, length, f in notes:
        m = int(length * RATE)
        tt = np.arange(m) / RATE
        ph = 2 * np.pi * f * pitch * tt
        # a soft square through a felt lowpass: dull, not a beep
        tone = np.tanh(2.2 * np.sin(ph)) * env_adsr(m, 0.006, length * 0.6, 1.4)
        a = int(start * RATE)
        out[a:a + m] += tone
    out = onepole_lp(out, 1100) + 0.02 * rng.standard_normal(n) * env_adsr(n, 0.002, 0.3)
    return out


BUILDERS = {"hair_rustle": hair_rustle, "gulp_whole": gulp_whole, "vent_spill": vent_spill, "ui_deny": ui_deny}


def master(name, mono):
    mono = mono - mono.mean()
    data = mono[:, None]
    data = data / (np.abs(data).max() + 1e-9) * 0.5
    lufs = A.integrated_lufs(data, RATE)
    data = data * 10 ** ((TARGET_LUFS[name] - lufs) / 20.0)
    tp = A.true_peak_dbfs(data, RATE)
    if tp > -1.5:
        data = data * 10 ** ((-1.5 - tp) / 20.0)
    return data


def save(path, data):
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    print("wrote %s  %.2f s  LUFS %.1f  TP %.1f" % (
        os.path.basename(path), len(data) / RATE, A.integrated_lufs(data, RATE), A.true_peak_dbfs(data, RATE)))


def register(names):
    with open(MANIFEST, encoding="utf-8") as f:
        m = json.load(f)
    for name in names:
        m["sounds"][name] = {"kind": "sfx", "files": ["res://audio/sfx/%s_v%d.wav" % (name, i + 1) for i in range(len(VARIATIONS))],
                             "spatial": SPATIAL[name]}
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as f:
        json.dump(m, f, indent=1, ensure_ascii=False)
        f.write("\n")


if __name__ == "__main__":
    for name, fn in BUILDERS.items():
        for i, (seed, pitch) in enumerate(VARIATIONS):
            rng = np.random.default_rng(seed * 7 + len(name))
            save(os.path.join(OUT, "%s_v%d.wav" % (name, i + 1)), master(name, fn(rng, pitch)))
    register(list(BUILDERS))
