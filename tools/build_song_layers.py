# -*- coding: utf-8 -*-
"""Synthesizes the ending song layers and the M03 magnet hum
(game/audio/loops/*.wav) and registers them in game/audio/manifest.json.

    python -X utf8 tools/build_song_layers.py

docs/spec/00-overview.md: breaking out of the last shell lands the player in
the street with a peaceful hum without words; the song's melody is already
heard faintly inside the flesh, louder toward the outer shells; a complete
tumor codex adds one more voice. docs/spec/05-mutations.md M03: facing the
restroom, a low hum in the ears.

  song_melody  the tune alone on a soft plucked tine (heard in the flesh)
  song_hum     the same tune hummed with closed lips ("mm"): the ending hum,
               which takes the tune over from the tine
  song_voice2  a lower second voice humming the harmony (complete codex)
  magnet_hum   a low two-tone drone with a slow beat (M03)

All song layers share one 16 s bar grid, so they play in step. Each ends in
a breath of silence, so the loop point needs no crossfade. The magnet hum
uses only whole cycles per loop. Levels are mastered to TARGET_LUFS.
"""
import math
import os
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "game", "tools", "audio"))
import analyze_audio as A  # noqa: E402

RATE = 48000
OUT = os.path.join(HERE, "..", "game", "audio", "loops")
MANIFEST = os.path.join(HERE, "..", "game", "audio", "manifest.json")

SONG_SEC = 16.0
BEAT = 0.5  # 120 bpm eighths... 32 slots in the bar grid
TARGET_LUFS = {"song_melody": -24.0, "song_hum": -20.0, "song_voice2": -21.0, "magnet_hum": -21.0}

# (start beat, length in beats, midi note); D major pentatonic lullaby.
# The last two beats stay empty: a breath before the tune comes round.
MELODY = [
    (0, 2, 66), (2, 2, 69), (4, 3, 71), (7, 1, 69),
    (8, 2, 66), (10, 2, 64), (12, 4, 62),
    (16, 2, 64), (18, 2, 66), (20, 3, 69), (23, 1, 71),
    (24, 2, 69), (26, 2, 66), (28, 2, 64),
]
# the second voice under it: thirds and sixths below, longer notes
HARMONY = [
    (0, 4, 62), (4, 4, 66), (8, 4, 62), (12, 4, 57),
    (16, 4, 59), (20, 4, 62), (24, 4, 61), (28, 2, 57),
]


def midi_hz(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


def pitch_and_gate(notes, glide=0.09):
    """Per-sample f0 (gliding between joined notes) and a soft 0..1 gate."""
    n = int(SONG_SEC * RATE)
    t = np.arange(n) / RATE
    f0 = np.full(n, midi_hz(notes[0][2]))
    gate = np.zeros(n)
    for i, (b, length, note) in enumerate(notes):
        a = int(b * BEAT * RATE)
        e = int((b + length) * BEAT * RATE)
        f0[a:e] = midi_hz(note)
        gate[a:e] = 1.0
        # glide in from the previous note when they touch
        if i > 0:
            pb, pl, pn = notes[i - 1]
            if pb + pl == b:
                g = min(int(glide * RATE), e - a)
                f0[a:a + g] = midi_hz(pn) + (midi_hz(note) - midi_hz(pn)) * (0.5 - 0.5 * np.cos(np.linspace(0, math.pi, g)))
    # fill the gaps with the following note's pitch so phase never jumps
    last = f0[-1]
    for i in range(n - 1, -1, -1):
        if gate[i] == 0.0:
            f0[i] = last
        else:
            last = f0[i]
    # soften the gate: 0.12 s rise, 0.25 s fall
    rise = np.exp(-1.0 / (0.04 * RATE))
    fall = np.exp(-1.0 / (0.09 * RATE))
    env = np.empty(n)
    acc = 0.0
    for i in range(n):
        k = rise if gate[i] > acc else fall
        acc = k * acc + (1 - k) * gate[i]
        env[i] = acc
    # a slow, late vibrato inside each held note
    vib = 1.0 + 0.004 * np.sin(2 * math.pi * 5.1 * t) * np.clip(env * 1.4 - 0.4, 0, 1)
    return f0 * vib, env, t


def voiced(f0, harmonics, shape):
    """Sum of harmonics of a gliding f0, each weighted by shape(freq, k)."""
    phase = 2 * math.pi * np.cumsum(f0) / RATE
    out = np.zeros_like(f0)
    for k in range(1, harmonics + 1):
        fk = f0 * k
        out += np.sin(phase * k) * shape(fk, k) * (fk < RATE * 0.45)
    return out


def resonance(f, centre, width):
    return 1.0 / (1.0 + ((f - centre) / width) ** 2)


def nasal_hum(f, k):
    # glottal roll-off, the nasal murmur near 250 Hz, an anti-resonance
    # near 900 Hz and the weak upper nasal formant: closed-lip "mm"
    glottal = 1.0 / k ** 1.2
    shape = 0.25 + 1.6 * resonance(f, 260, 110) + 0.35 * resonance(f, 2100, 300)
    notch = 1.0 - 0.85 * resonance(f, 950, 160)
    return glottal * shape * notch


def low_hum(f, k):
    # a darker, rounder voice for the second part
    glottal = 1.0 / k ** 1.4
    shape = 0.2 + 1.8 * resonance(f, 220, 90) + 0.2 * resonance(f, 1800, 260)
    notch = 1.0 - 0.9 * resonance(f, 800, 150)
    return glottal * shape * notch


def breath(env, seed, amount):
    r = np.random.default_rng(seed)
    x = r.standard_normal(len(env))
    a = math.exp(-2 * math.pi * 1800 / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = a * acc + (1 - a) * x[i]
        y[i] = acc
    return y / (np.abs(y).max() + 1e-9) * env * amount


def song_melody():
    # the tune alone on a soft plucked tine (a muffled music box): every
    # note rings out and decays; tails wrap round the loop, so it is seamless
    n = int(SONG_SEC * RATE)
    out = np.zeros(n)
    r = np.random.default_rng(21)
    partials = [(1.0, 1.0, 1.4), (2.0, 0.3, 0.8), (3.0, 0.14, 0.5), (4.16, 0.08, 0.25), (5.43, 0.04, 0.15)]
    for b, _length, note in MELODY:
        f = midi_hz(note)
        start = int(b * BEAT * RATE)
        m = int(2.5 * RATE)
        tt = np.arange(m) / RATE
        tone = np.zeros(m)
        for ratio, amp, decay in partials:
            tone += amp * np.sin(2 * math.pi * f * ratio * tt + r.uniform(0, 1)) * np.exp(-tt / decay)
        tone *= np.minimum(1.0, tt / 0.004)
        # the felt hitting the tine: a short soft knock
        knock = r.standard_normal(int(0.012 * RATE)) * np.exp(-np.arange(int(0.012 * RATE)) / (0.003 * RATE)) * 0.08
        tone[:len(knock)] += knock
        out[(start + np.arange(m)) % n] += tone
    return out


def song_hum():
    f0, env, _ = pitch_and_gate(MELODY)
    return voiced(f0 * 0.5, 24, nasal_hum) * env + breath(env, 11, 0.02)


def song_voice2():
    f0, env, _ = pitch_and_gate(HARMONY, glide=0.12)
    return voiced(f0 * 0.5, 24, low_hum) * env + breath(env, 12, 0.015)


def magnet_hum():
    sec = 8.0
    t = np.arange(int(sec * RATE)) / RATE
    # whole cycles per 8 s: a 55 Hz mains-like hum with its odd harmonics,
    # 110 and 110.5 Hz beating twice a second, and a slow swell (1 cycle
    # per loop)
    tone = (np.sin(2 * math.pi * 55.0 * t) * 0.6
            + np.sin(2 * math.pi * 110.0 * t) * 0.5
            + np.sin(2 * math.pi * 110.5 * t) * 0.45
            + np.sin(2 * math.pi * 165.0 * t) * 0.3
            + np.sin(2 * math.pi * 275.0 * t) * 0.16
            + np.sin(2 * math.pi * 385.0 * t) * 0.08)
    return tone * (0.85 + 0.15 * np.sin(2 * math.pi * t / sec))


def master(name, mono):
    mono = mono - mono.mean()
    right = np.roll(mono, int(0.004 * RATE))
    data = np.stack([mono, right], -1)
    data = data / (np.abs(data).max() + 1e-9) * 0.5
    lufs = A.integrated_lufs(data, RATE)
    data = data * 10 ** ((TARGET_LUFS[name] - lufs) / 20.0)
    tp = A.true_peak_dbfs(data, RATE)
    if tp > -1.0:
        data = data * 10 ** ((-1.0 - tp) / 20.0)
    return data


def save(name, data):
    path = os.path.join(OUT, name + ".wav")
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    print("wrote %s  LUFS %.1f  TP %.1f  seam %.3f" % (
        path, A.integrated_lufs(data, RATE), A.true_peak_dbfs(data, RATE),
        A.loop_discontinuity(data)["jump_ratio"]))


def register(names):
    import json
    with open(MANIFEST, encoding="utf-8") as f:
        m = json.load(f)
    for name in names:
        m["sounds"][name] = {"kind": "loop", "files": ["res://audio/loops/%s.wav" % name],
                             "loop_seconds": 8.0 if name == "magnet_hum" else SONG_SEC}
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as f:
        json.dump(m, f, indent=1, ensure_ascii=False)
        f.write("\n")


if __name__ == "__main__":
    built = []
    for fn in (song_melody, song_hum, song_voice2, magnet_hum):
        save(fn.__name__, master(fn.__name__, fn()))
        built.append(fn.__name__)
    register(built)
