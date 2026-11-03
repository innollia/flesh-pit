# -*- coding: utf-8 -*-
"""Synthesizes the restroom's two extra ambience layers and adds them to the
restroom bed (game/audio/loops/<id>.wav, manifest "beds"."restroom").

    python -X utf8 tools/build_restroom_amb.py [amb_restroom_fan|amb_restroom_pipes]

  amb_restroom_fan    the old exhaust fan behind the vent grate: a steady
                      airy whoosh through a short duct (its modes ring
                      faintly), the five blades chopping at 112.5 Hz, and a
                      loose louvre that rattles once a turn now and then,
                      never for long. 16 s loop.
  amb_restroom_pipes  water in the pipes inside the wall, heard through the
                      tiles: mostly quiet, then a trickle runs for a while,
                      the pipe swallows air and glugs, a tick as the metal
                      settles. 40 s loop, so it never sounds like a pattern.

The owner's amb_restroom (fluorescent hum and buzz, pinned in
game/tools/audio/build_audio.py PS1_PINNED) stays untouched and keeps
playing; these two are added beside it, so the bed fades in and out of the
flesh exactly as before (the director fades every layer of a bed together).
User decision 2026-11-04: the restroom has no music for now, only the fan and
the water in the pipes (audio/fp_music.gd RESTROOM_ON_HOLD).

Seamless: every noise is shaped by an FFT filter over the whole loop
(circular convolution, so the wrap is just another sample), every tone has a
whole number of cycles per loop, every event is placed with wrap-around.
The PS1 texture is build_audio.py's "light" level (the same as amb_restroom),
run over three laps so it wraps too.

Levels: under the room's own hum (amb_restroom -34 LUFS) so breathing stays
on top (docs/spec/08-presentation.md 3), and far under the door, flush and
vent cues (-19..-20 LUFS); the script prints their masking margin against
the whole bed. Note: game/tools/audio/build_audio.py rewrites manifest.json
from its own list; run this builder again after it.
"""
import json
import math
import os
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIO_TOOLS = os.path.join(HERE, "..", "game", "tools", "audio")
sys.path.insert(0, AUDIO_TOOLS)
import analyze_audio as A  # noqa: E402
from build_audio import ps1_treat  # noqa: E402

RATE = 48000
OUT = os.path.join(HERE, "..", "game", "audio", "loops")
SFX = os.path.join(HERE, "..", "game", "audio", "sfx")
MANIFEST = os.path.join(HERE, "..", "game", "audio", "manifest.json")

# Integrated loudness (gated, so the pipes' quiet stretches do not count).
# amb_restroom is -34; the fan sits a few dB under it, the water lower still.
TARGET_LUFS = {"amb_restroom_fan": -38.0, "amb_restroom_pipes": -39.0}
LOOP_SEC = {"amb_restroom_fan": 16.0, "amb_restroom_pipes": 40.0}
BED = ["amb_restroom", "amb_restroom_fan", "amb_restroom_pipes"]


# --- circular building blocks ---------------------------------------------------

def shape(x, gain_fn):
    """Filters x circularly: FFT over the whole loop, so the wrap is seamless."""
    f = np.fft.rfftfreq(len(x), 1.0 / RATE)
    return np.fft.irfft(np.fft.rfft(x) * gain_fn(f), len(x))


def bp(lo, hi, order=2):
    def g(f):
        fs = np.maximum(f, 1.0)
        lo_g = 1.0 if lo is None else 1.0 / np.sqrt(1.0 + (lo / fs) ** (2 * order))
        hi_g = 1.0 if hi is None else 1.0 / np.sqrt(1.0 + (fs / hi) ** (2 * order))
        return lo_g * hi_g
    return g


def peaks(centres, q, gain):
    """Resonant bumps (a duct's modes, a pipe's ring) on top of a flat 1."""
    def g(f):
        out = np.ones_like(f)
        for c in centres:
            out += gain / (1.0 + ((f - c) / (c / q)) ** 2)
        return out
    return g


def smooth_env(n, rng, cutoff_hz):
    """A slow random 0..1 envelope that wraps (circular low-passed noise)."""
    e = shape(rng.standard_normal(n), bp(None, cutoff_hz, order=2))
    e = (e - e.min()) / (e.max() - e.min() + 1e-12)
    return e


def place(out, sig, start):
    n = len(out)
    start %= n
    idx = (start + np.arange(len(sig))) % n
    np.add.at(out, idx, sig)


# --- the fan --------------------------------------------------------------------

def amb_restroom_fan():
    sec = LOOP_SEC["amb_restroom_fan"]
    n = int(sec * RATE)
    t = np.arange(n) / RATE
    rng = np.random.default_rng(4120)
    rot = 22.5            # turns per second (1350 rpm); 360 whole turns per loop
    blades = 5
    bpf = rot * blades    # 112.5 Hz
    # the motor drifts a little: phase modulation by whole-loop sines
    drift = 0.35 * np.sin(2 * math.pi * t / sec) + 0.2 * np.sin(2 * math.pi * 3 * t / sec + 1.1)
    turn_phase = 2 * math.pi * rot * t + drift

    # 1) air through the grate and a short duct: broadband whoosh with the
    #    duct's modes (about 0.8 m: 212, 425, 637 Hz) ringing a little
    air = rng.standard_normal(n)
    air = shape(air, lambda f: bp(140, 2600, 2)(f) * peaks([212.0, 425.0, 637.0, 1180.0], 9.0, 1.6)(f))
    # the blades chop the stream once per pass, softly
    chop = 1.0 + 0.16 * np.sin(blades * turn_phase) + 0.05 * np.sin(turn_phase + 0.7)
    air = air * chop
    air /= np.abs(air).max() + 1e-9

    # 2) the blade tone and its first harmonics, thin and a bit uneven
    tone = (np.sin(blades * turn_phase) * 1.0 + np.sin(2 * blades * turn_phase + 0.4) * 0.45
            + np.sin(3 * blades * turn_phase + 1.3) * 0.18 + np.sin(turn_phase) * 0.25)
    # imbalance: the whole thing breathes once a turn
    tone *= 1.0 + 0.12 * np.sin(turn_phase + 2.0)

    # 3) the loose louvre: a tick once a turn while it is loose; it comes and
    #    goes with a slow random envelope and is quiet most of the time
    loose = smooth_env(n, rng, 0.35)
    loose = np.clip((loose - 0.55) / 0.45, 0, 1) ** 1.5
    rattle = np.zeros(n)
    m = int(0.012 * RATE)
    tt = np.arange(m) / RATE
    turns = int(round(rot * sec))
    for k in range(turns):
        at = (k / rot) + rng.normal(0.0, 0.0009)
        a = int(at * RATE) % n
        lvl = loose[a]
        if lvl < 0.02:
            continue
        ring = (np.sin(2 * math.pi * 2150 * tt + rng.uniform(0, 6.28)) * 0.6
                + np.sin(2 * math.pi * 3420 * tt + rng.uniform(0, 6.28)) * 0.35) * np.exp(-tt / 0.0035)
        click = rng.standard_normal(m) * np.exp(-tt / 0.0012)
        place(rattle, (ring + click) * lvl * rng.uniform(0.6, 1.0), a)
    rattle = shape(rattle, bp(900, 6000, 2))

    # 4) the motor's own whine, very faint
    whine = np.sin(2 * math.pi * 1350.0 * t + 3 * drift) * 0.5

    mono = air * 1.0 + tone * 0.22 + rattle * 0.9 + whine * 0.012
    # behind the grate: the top end dulled
    mono = shape(mono, bp(45, 4200, 2))
    return stereo(mono, 0.006)


# --- the pipes ------------------------------------------------------------------

def bubble(rng, f0, dur, rise, attack=0.003):
    """One bubble in water (Minnaert ring): a sine gliding up as the bubble
    shrinks, soft-started (a hard start reads as a click or a drum)."""
    m = int(dur * RATE)
    tt = np.arange(m) / RATE
    f = f0 * (1.0 + rise * tt / dur)
    ph = 2 * math.pi * np.cumsum(f) / RATE
    a = np.minimum(1.0, tt / attack)
    a = 0.5 - 0.5 * np.cos(math.pi * a)
    return np.sin(ph + rng.uniform(0, 6.28)) * np.exp(-tt / (dur * 0.35)) * a


def trickle(rng, n, start, length, strength):
    """Water running down a pipe, the babble of a small brook: many
    overlapping bubbles, each a soft gliding sine, over a faint wet hush,
    swelling in and thinning out."""
    out = np.zeros(n)
    m = int(length * RATE)
    tt = np.arange(m) / RATE
    swell = np.minimum(1.0, tt / 1.6) * np.clip((length - tt) / 2.2, 0, 1) ** 1.3
    # the flow itself wavers (more, less) a few times
    waver = 0.55 + 0.45 * np.interp(tt, np.linspace(0, length, 9), rng.uniform(0, 1, 9))
    w = swell * waver
    stream = np.zeros(m)
    for at in rng.uniform(0, length, int(length * 140)):
        lvl = float(np.interp(at, tt, w))
        if rng.uniform() > lvl:
            continue
        b = bubble(rng, rng.uniform(480, 1500), rng.uniform(0.015, 0.05), rng.uniform(0.6, 1.8),
                   attack=rng.uniform(0.002, 0.006))
        a = int(at * RATE)
        e = min(m, a + len(b))
        stream[a:e] += b[:e - a] * math.exp(rng.uniform(-2.3, 0.0))
    hush = shape(rng.standard_normal(m), bp(250, 1400, 2))
    hush /= np.abs(hush).max() + 1e-9
    stream += hush * w * 0.12
    place(out, stream * strength, int(start * RATE))
    return out


def gurgle(rng, n, start, length, strength):
    """The drain sucking air after the water: a sputtering wet rush through a
    hollow pipe (its resonance wandering as the air pocket moves), broken by
    a scatter of big and small bubbles with no beat to it (evenly spaced
    glugs read as a frog croaking)."""
    out = np.zeros(n)
    m = int(length * RATE)
    tt = np.arange(m) / RATE
    swell = np.minimum(1.0, tt / 0.15) * np.clip((length - tt) / (length * 0.6), 0, 1) ** 1.5
    # the sputter: a fast random envelope, only its peaks let air through
    sput = shape(rng.standard_normal(m), bp(None, rng.uniform(7, 11), 1))
    sput = np.clip(sput / (np.abs(sput).max() + 1e-9) * 2.0 + 0.15, 0, None) ** 1.3
    # the hollow pipe: a resonance moving between about 220 and 520 Hz
    x = rng.standard_normal(m)
    centre = 220.0 * (520.0 / 220.0) ** np.interp(tt, np.linspace(0, length, 7), rng.uniform(0, 1, 7))
    y = np.zeros(m)
    y1 = y2 = 0.0
    r = 0.992
    for i in range(m):
        w0 = 2 * math.pi * centre[i] / RATE
        y0 = x[i] * (1 - r) + 2 * r * math.cos(w0) * y1 - r * r * y2
        y[i] = y0
        y2, y1 = y1, y0
    y = y / (np.abs(y).max() + 1e-9)
    air = shape(rng.standard_normal(m), bp(300, 1500, 2))
    air = air / (np.abs(air).max() + 1e-9)
    g = (y * 0.8 + air * 0.25) * sput * swell
    # bubbles at random (Poisson) times, more where the sputter is open
    for at in np.sort(rng.uniform(0, length, int(length * 40))):
        lvl = float(np.interp(at, tt, sput * swell)) / (sput.max() + 1e-9)
        if rng.uniform() > lvl * 1.6:
            continue
        big = rng.uniform() < 0.3
        b = bubble(rng, rng.uniform(120, 260) if big else rng.uniform(320, 1000),
                   rng.uniform(0.05, 0.11) if big else rng.uniform(0.012, 0.04), rng.uniform(0.8, 2.0),
                   attack=rng.uniform(0.006, 0.012) if big else rng.uniform(0.002, 0.005))
        a = int(at * RATE)
        e = min(m, a + len(b))
        g[a:e] += b[:e - a] * (0.5 if big else rng.uniform(0.15, 0.45))
    place(out, g * strength, int(start * RATE))
    return out


def tick(rng, n, at, strength):
    """The metal pipe settling: a short dull ring."""
    m = int(0.09 * RATE)
    tt = np.arange(m) / RATE
    s = (np.sin(2 * math.pi * 940 * tt) * 0.7 + np.sin(2 * math.pi * 1610 * tt) * 0.4) * np.exp(-tt / 0.018)
    s += rng.standard_normal(m) * np.exp(-tt / 0.002) * 0.5
    out = np.zeros(n)
    place(out, s * strength, int(at * RATE))
    return out


def amb_restroom_pipes():
    sec = LOOP_SEC["amb_restroom_pipes"]
    n = int(sec * RATE)
    rng = np.random.default_rng(7731)
    w = np.zeros(n)
    # 0..3 s quiet; a tick, then someone's water runs down for a while
    w += tick(rng, n, 2.7, 0.35)
    w += trickle(rng, n, 3.2, 8.5, 1.0)
    # the last of it drags air down the pipe
    w += gurgle(rng, n, 11.4, 2.4, 2.2)
    # quiet; a faint second tick far along the wall
    w += tick(rng, n, 19.6, 0.18)
    # a shorter, thinner run, then a small glug
    w += trickle(rng, n, 24.0, 5.0, 0.85)
    w += gurgle(rng, n, 29.3, 1.4, 1.5)
    # a short lone gurgle late, as if from another floor
    w += gurgle(rng, n, 35.8, 0.7, 0.9)
    # inside the wall: the tiles take the top off, the pipe rings low
    w = shape(w, lambda f: bp(90, 2400, 2)(f) * peaks([310.0, 760.0], 6.0, 0.9)(f))
    return stereo(w, 0.0045)


# --- output ----------------------------------------------------------------------

def stereo(mono, delay):
    """A little width: right is left delayed (np.roll wraps, so seamless)."""
    return np.stack([mono, np.roll(mono, int(delay * RATE))], -1)


def master(name, data):
    data = data - data.mean(axis=0)
    data = data / (np.abs(data).max() + 1e-9) * 0.5
    data = ps1_treat(data, RATE, "light", True)
    lufs = A.integrated_lufs(data, RATE)
    data = data * 10 ** ((TARGET_LUFS[name] - lufs) / 20.0)
    tp = A.true_peak_dbfs(data, RATE)
    if tp > -1.5:
        data = data * 10 ** ((-1.5 - tp) / 20.0)
    return data


def save(name, data):
    path = os.path.join(OUT, name + ".wav")
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    seam = A.loop_discontinuity(data)
    print("wrote %s  %.2f s  LUFS %.1f  TP %.1f  seam %.3f  wrap_hf %.1f dB" % (
        os.path.basename(path), len(data) / RATE, A.integrated_lufs(data, RATE), A.true_peak_dbfs(data, RATE),
        seam["jump_ratio"], seam["wrap_hf_dbfs"]))


def register():
    with open(MANIFEST, encoding="utf-8") as f:
        m = json.load(f)
    for name, sec in LOOP_SEC.items():
        m["sounds"][name] = {"kind": "loop", "files": ["res://audio/loops/%s.wav" % name], "loop_seconds": sec}
    m["beds"]["restroom"] = list(BED)
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as f:
        json.dump(m, f, indent=1, ensure_ascii=False)
        f.write("\n")


def report_masking():
    """Door, flush and vent cues over the whole restroom bed (old and new)."""
    beds = {}
    for name in BED:
        d, r = A.read_wav(os.path.join(OUT, name + ".wav"))
        beds[name] = d
    n = max(len(d) for d in beds.values())
    old = np.resize(beds["amb_restroom"], (n, 2))
    new = sum(np.resize(d, (n, 2)) for d in beds.values())
    print("restroom bed LUFS: old %.1f  new %.1f" % (A.integrated_lufs(old, RATE), A.integrated_lufs(new, RATE)))
    for cue in ("door_open", "door_close", "toilet_flush", "vent_open", "coin_drop"):
        path = os.path.join(SFX, cue + "_v1.wav")
        if not os.path.exists(path):
            continue
        e, r = A.read_wav(path)
        mo = A.masking_margin_db(e, r, old, RATE).get("own_energy_weighted_margin_db", float("nan"))
        mn = A.masking_margin_db(e, r, new, RATE).get("own_energy_weighted_margin_db", float("nan"))
        print("  %-13s margin over bed: old %+.1f dB  new %+.1f dB (gate -10)" % (cue, mo, mn))


if __name__ == "__main__":
    only = sys.argv[1:]
    for fn in (amb_restroom_fan, amb_restroom_pipes):
        if only and fn.__name__ not in only:
            continue
        save(fn.__name__, master(fn.__name__, fn()))
    register()
    report_masking()
