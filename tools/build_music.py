# -*- coding: utf-8 -*-
"""Synthesizes the background music (game/audio/loops/mus_*.wav) and
registers it in game/audio/manifest.json.

    python -X utf8 tools/build_music.py

Every track comes from the ending song's own tune (MELODY / HARMONY in
tools/build_song_layers.py). The title is that tune on worn timbres,
synthesized here in numpy. The tracks that must not feel like it are nkido patches (game/tools/audio/patches/mus_*.akkado): they keep the
tune's shape (the contour 3-5-6-5-3-2-1, or just its rising third) in another
key, metre, instrument and room. Python only folds their loop, adds tape or
crank wow, the lo-fi and the mastering (NKIDO_TRACKS).

docs/spec/08-presentation.md 3: while digging there is no music, only the
low drone (the song's faint melody is the one exception, already in
song_melody). So none of these plays in the flesh. Where each one plays
(game/audio/fp_music.gd):

  mus_title     start screen       music box lullaby over a worn organ, a
                                   hum joins, then the chords turn minor.
                                   D major, 44 bpm, 4/4
  mus_keybind   key settings stage a wheezing fairground organ cranked round
                                   for the turning stage of dolls: reedy
                                   pipes, drum and snare, oom-pah-pah.
                                   G minor, 130 bpm, 3/4
  mus_pause     Esc in the flesh   a slow warm string pad with no attacks at
                                   all, breathing: a refuge from the noise.
                                   Ab lydian, no beat (the lids show the heart)
  mus_pause_alt Esc in the room    a felted piano in a warm room, a few notes
                                   far apart, close, the size of the room.
                                   Db major, 66 bpm
  mus_vent      vent trade open    teeth tapped on a lip, a walking plucked
                                   string, someone whistling the song through
                                   their teeth, down a duct. B minor, 120 bpm
  mus_mirror    Tab, in the room   a soft analogue synth sequence in 7/8 with
                                   side-to-side echoes and a wristwatch's tick
                                   (the arm is up as if reading one). F lydian
  mus_room_*    restroom and bowl  one piece of music in parallel stems, all
                                   Bb phrygian, 54 bpm, 72 beats (80 s). They
                                   play together in one synchronized stream and
                                   only their levels move, by what the game
                                   says (audio/room_music.json): base (wet
                                   finger on the rim, always, very low: 03 1,
                                   so quiet you hear your own breath), reckon
                                   (the bowl's bowed basses, tally, drips),
                                   dread, linger, gut, cold, wrong, gold

Each is a seamless loop of whole bars. The numpy tracks wrap notes and
reverb tails round the loop end (circular placement and circular
convolution), every slow modulation runs a whole number of cycles per loop,
noise is filtered in the frequency domain over the whole loop. nkido has no
loop mode, so its tracks render twice round and keep the second pass, whose
start already carries the tails of the end, then fold a short overhang over
the head (KNOWHOW B4). Deterministic (fixed seeds). Lo-fi:
sample-and-hold down to an older rate and a coarser word length (PS1-era
streamed music), then mastered to TARGET_LUFS with a true peak of at most
-1 dBFS like the song layers.
"""
import math
import os
import shutil
import subprocess
import sys
import tempfile
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "game", "tools", "audio"))
import analyze_audio as A  # noqa: E402
from build_song_layers import HARMONY, MELODY, midi_hz, nasal_hum  # noqa: E402

RATE = 48000
OUT = os.path.join(HERE, "..", "game", "audio", "loops")
MANIFEST = os.path.join(HERE, "..", "game", "audio", "manifest.json")
PATCHES = os.path.join(HERE, "..", "game", "tools", "audio", "patches")
NKIDO = r"C:\projects\_tools\nkido\build-clang\bin\nkido.exe"

# Integrated loudness per track. The menus are about where the song's tine
# (-24) is; the vent trade stays under where the being's voice will be; Esc and
# the forearm stay under reading and under the room's own sounds. Each room
# stem is mastered alike and audio/room_music.json sets what is heard: the
# base's gain there puts it under the room's own hum bed (amb_restroom -34).
TARGET_LUFS = {
    "mus_title": -23.0, "mus_vent": -27.0,
    "mus_pause": -28.0, "mus_pause_alt": -28.0, "mus_keybind": -25.0,
    "mus_mirror": -28.0,
}
PHRASE_UNITS = 32  # MELODY / HARMONY span 32 units (16 s at the song's 0.5 s)


# --- circular building blocks ---------------------------------------------------

def place(out, sig, start):
    """Adds sig into out at start, wrapping past the end (seamless tails)."""
    n = len(out)
    start %= n
    m = min(len(sig), n)
    first = min(m, n - start)
    out[start:start + first] += sig[:first]
    if m > first:
        out[:m - first] += sig[first:m]


def spectrum_gain(n, lo=None, hi=None, order=2):
    f = np.fft.rfftfreq(n, 1.0 / RATE)
    g = np.ones_like(f)
    if lo:
        g *= 1.0 / np.sqrt(1.0 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    if hi:
        g *= 1.0 / np.sqrt(1.0 + (f / hi) ** (2 * order))
    return g


def band(x, lo=None, hi=None, order=2):
    """Zero-phase filter over the whole loop (circular, so seamless)."""
    return np.fft.irfft(np.fft.rfft(x) * spectrum_gain(len(x), lo, hi, order), len(x))


def loop_noise(n, seed, lo=None, hi=None):
    x = band(np.random.default_rng(seed).standard_normal(n), lo, hi)
    return x / (np.abs(x).max() + 1e-9)


def cycles(n, k, phase=0.0):
    """0..1 swell with k whole cycles over the loop."""
    t = np.arange(n) / n
    return 0.5 + 0.5 * np.sin(2 * math.pi * k * t + phase)


def reverb(x, seconds, damp_hz, seed, predelay=0.012):
    """Stereo circular convolution with a decaying noise tail (RT60 = seconds)."""
    n = len(x)
    m = min(int(seconds * 1.2 * RATE), n)
    t = np.arange(m) / RATE
    outs = []
    for s in (seed, seed + 1):
        ir = np.random.default_rng(s).standard_normal(m) * np.exp(-6.9 * t / seconds)
        ir[: int(predelay * RATE)] = 0.0
        # the tail darkens as it dies
        ir = band(ir, 80, damp_hz) * 0.7 + band(ir, 80, damp_hz * 0.35) * 0.3
        ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
        full = np.zeros(n)
        full[:m] = ir
        outs.append(np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(full), n))
    return outs[0], outs[1]


def wow(x, depth_s, ks, phases=None):
    """Tape wow/flutter: a time-varying read delay of whole cycles per loop."""
    n = len(x)
    t = np.arange(n) / n
    phases = phases or [0.0] * len(ks)
    d = np.zeros(n)
    for k, ph in zip(ks, phases):
        d += np.sin(2 * math.pi * k * t + ph) / len(ks)
    pos = np.arange(n) - depth_s * RATE * (1.0 + d)
    i0 = np.floor(pos).astype(np.int64)
    fr = pos - i0
    return x[i0 % n] * (1 - fr) + x[(i0 + 1) % n] * fr


def lofi(x, rate, bits, seed):
    """Sample-and-hold to an older rate, a soft image filter, a coarser word."""
    n = len(x)
    step = RATE / rate
    idx = (np.floor(np.arange(n) / step) * step).astype(np.int64) % n
    y = band(x[idx], None, rate * 0.46, order=3)
    peak = np.abs(y).max() + 1e-9
    q = 2.0 ** (bits - 1)
    dither = (np.random.default_rng(seed).random(n) - np.random.default_rng(seed + 7).random(n)) / q
    return np.round((y / peak + dither) * q) / q * peak


# --- instruments ---------------------------------------------------------------

def tine(f, rng, detune_cents, length=2.8, bright=1.0):
    """One music-box tine: a soft knock, then partials ringing out."""
    m = int(length * RATE)
    tt = np.arange(m) / RATE
    f = f * 2 ** (detune_cents / 1200.0)
    tone = np.zeros(m)
    for ratio, amp, decay in [(1.0, 1.0, 1.5), (2.0, 0.3, 0.8), (3.0, 0.14, 0.5),
                              (4.16, 0.08 * bright, 0.25), (5.43, 0.04 * bright, 0.15)]:
        if f * ratio < RATE * 0.45:
            tone += amp * np.sin(2 * math.pi * f * ratio * tt + rng.uniform(0, 6.28)) * np.exp(-tt / decay)
    tone *= np.minimum(1.0, tt / 0.004)
    k = int(0.012 * RATE)
    tone[:k] += rng.standard_normal(k) * np.exp(-np.arange(k) / (0.003 * RATE)) * 0.08
    return tone


def voice_line(n, events, shape, harmonics=24, attack=0.09, release=0.22, glide=0.09, octave=0.5):
    """A sung line: events are (start s, length s, midi). Pitch glides between
    touching notes; each note has a raised-cosine rise and fall."""
    f0 = np.zeros(n)
    env = np.zeros(n)
    ev = sorted(events)
    for i, (t0, dur, note) in enumerate(ev):
        a = int(t0 * RATE) % n
        e = a + int(dur * RATE)
        f = midi_hz(note)
        seg = np.full(e - a, f)
        if i > 0:
            pt, pd, pn = ev[i - 1]
            if abs(pt + pd - t0) < 1e-6:
                g = min(int(glide * RATE), e - a)
                pf = midi_hz(pn)
                seg[:g] = pf + (f - pf) * (0.5 - 0.5 * np.cos(np.linspace(0, math.pi, g)))
        idx = np.arange(a, e) % n
        f0[idx] = seg
        ra = int(attack * RATE)
        rr = int(release * RATE)
        shape_env = np.ones(e - a + rr)
        shape_env[:ra] = 0.5 - 0.5 * np.cos(np.linspace(0, math.pi, ra))
        shape_env[e - a:] = 0.5 + 0.5 * np.cos(np.linspace(0, math.pi, rr))
        place(env, shape_env, a)
    # release tails and gaps keep the last note's pitch (wrapping round the
    # loop), so no tail ever jumps pitch while it is still sounding
    has = f0 > 0.0
    idx = np.maximum.accumulate(np.where(has, np.arange(n), -1))
    idx[idx < 0] = np.nonzero(has)[0][-1]
    f0 = f0[idx]
    env = np.minimum(env, 1.0)
    t = np.arange(n) / RATE
    vib = 1.0 + 0.004 * np.sin(2 * math.pi * 5.1 * t) * np.clip(env * 1.4 - 0.4, 0, 1)
    f0 = f0 * vib * octave
    phase = 2 * math.pi * np.cumsum(f0) / RATE
    out = np.zeros(n)
    for k in range(1, harmonics + 1):
        fk = f0 * k
        out += np.sin(phase * k) * shape(fk, k) * (fk < RATE * 0.45)
    return out * env


def reed(f, k):
    # a leaky harmonium reed: bright odd partials, a nasal box resonance
    odd = 1.0 if k % 2 else 0.55
    return odd / k ** 0.9 * (0.3 + 1.0 / (1.0 + ((f - 700) / 500) ** 2))


def organ_line(n, events, detune=8.0, seed=0, harmonics=14):
    """Two reeds a few cents apart (the beating of a worn organ) with a slow
    bellows tremolo."""
    up = [(t0, d, note + detune / 100.0) for t0, d, note in events]
    dn = [(t0, d, note - detune / 100.0) for t0, d, note in events]
    a = voice_line(n, up, reed, harmonics, attack=0.18, release=0.35, glide=0.0, octave=1.0)
    b = voice_line(n, dn, reed, harmonics, attack=0.22, release=0.4, glide=0.0, octave=1.0)
    trem = 0.88 + 0.12 * cycles(n, int(round(n / RATE * 4.3)), seed)
    return (a + b) * 0.5 * trem


# --- the tune, re-timed ----------------------------------------------------------

def timed(notes, unit, offset=0.0, transpose=0, stretch=1.0):
    """MELODY/HARMONY units -> (start s, length s, midi)."""
    return [(offset + b * unit, length * unit * stretch, note + transpose) for b, length, note in notes]


def box_line(out, events, rng, detune_spread=10.0, gain=1.0, bright=1.0):
    tuning = {}
    for t0, _d, note in events:
        if note not in tuning:  # each comb tooth stays out of tune the same way
            tuning[note] = rng.uniform(-detune_spread, detune_spread)
        place(out, tine(midi_hz(note), rng, tuning[note], bright=bright) * gain, int(t0 * RATE))


# --- tracks ----------------------------------------------------------------------

def mus_title():
    """Start screen: the lullaby on an out-of-tune music box, slowed, over a
    worn organ; a closed-lip hum joins the second time; the third time the
    same tune sits on minor chords; the fourth only fragments are left."""
    unit = 0.68
    phrase = PHRASE_UNITS * unit
    n = int(round(4 * phrase * RATE))
    rng = np.random.default_rng(101)
    box = np.zeros(n)
    for p in range(3):
        box_line(box, timed(MELODY, unit, p * phrase, 12), rng, gain=1.0 if p != 2 else 0.85)
    frag = [MELODY[i] for i in (0, 1, 2, 11, 12, 13)]
    box_line(box, timed(frag, unit, 3 * phrase, 12), rng, detune_spread=22.0, gain=0.8)
    minor = [(0, 8, 47), (8, 8, 43), (16, 8, 50), (24, 6, 45)]  # Bm  G  D  A
    pads = []
    for p in (0, 1, 3):
        pads += timed(HARMONY, unit, p * phrase, -12)
    pads += timed(minor, unit, 2 * phrase)
    organ = organ_line(n, pads, detune=9.0, seed=1.0)
    fifths = timed(minor, unit, 2 * phrase, 7)
    organ += organ_line(n, fifths, detune=11.0, seed=2.0) * 0.5
    hum = voice_line(n, timed(MELODY, unit, phrase) + timed(MELODY, unit, 2 * phrase), nasal_hum)
    hiss = loop_noise(n, 5, 1500, 9000) * 0.01
    dry = box * 0.55 + band(organ, 60, 1800) * 0.16 + hum * 0.22
    dry = wow(dry, 0.004, [2, 7], [0.0, 1.3])
    l, r = reverb(dry, 2.6, 3200, 11)
    return np.stack([dry * 0.75 + l * 0.45 + hiss, dry * 0.75 + r * 0.45 + hiss], -1)


TRACKS = (mus_title,)

# nkido tracks: bpm, loop seconds (whole cycles of the patch), overhang folded
# over the head, then tape or crank wow as wow()'s arguments.
NKIDO_TRACKS = {
    "mus_pause": (6.0, 80.0, 1.5, None),
    "mus_pause_alt": (66.0, 96 / 1.1, 0.5, (0.0022, [1, 4], [0.0, 0.0])),
    "mus_keybind": (60.0 / 0.46, 120 * 0.46, 0.08, (0.018, [1, 3, 5], [0.0, 0.7, 2.0])),
    "mus_mirror": (300.0 / 7.0, 67.2, 0.12, None),
    "mus_vent": (120.0, 64.0, 0.1, (0.006, [3, 11], [0.0, 2.1])),
}
LOFI = {"mus_title": (22050, 12), "mus_vent": (16000, 10),
        "mus_pause": (22050, 14), "mus_pause_alt": (22050, 14), "mus_keybind": (18900, 10),
        "mus_mirror": (32000, 12)}

# The room's stems: one piece, so one length, one wow curve (a different one per
# stem would slide them against each other) and one lo-fi. Their loudness is
# alike; the game sets the mix. Written at half rate: the lo-fi leaves nothing
# above 8 kHz, and eight long stems are the largest thing in the sound folder.
ROOM_STEMS = ("base", "reckon", "dread", "linger", "gut", "cold", "wrong", "gold")
ROOM_LOOP = 72 * 60.0 / 54.0
ROOM_RATE = 24000
for stem in ROOM_STEMS:
    NKIDO_TRACKS["mus_room_" + stem] = (54.0, ROOM_LOOP, 0.3, (0.002, [2, 5], [0.0, 0.0]))
    LOFI["mus_room_" + stem] = (16000, 12)
    TARGET_LUFS["mus_room_" + stem] = -28.0
# folded into the stems: no longer built, gone from the manifest
RETIRED = ("mus_restroom", "mus_settle")


def render_nkido(name):
    """The patch twice round plus the overhang; the second pass is the loop."""
    bpm, loop, fold, flutter = NKIDO_TRACKS[name]
    tmp = tempfile.mkdtemp(prefix="fp_music_")
    try:
        raw = os.path.join(tmp, name + ".wav")
        args = [NKIDO, "render", os.path.join(PATCHES, name + ".akkado"), "-o", raw,
                "--seconds", "%.3f" % (2 * loop + fold + 0.25), "--rate", str(RATE),
                "--bpm", "%.9f" % bpm, "--no-default-bank"]
        r = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace")
        if r.returncode != 0 or not os.path.exists(raw):
            raise RuntimeError("nkido render failed: " + (r.stdout + r.stderr)[-600:])
        data, rate = A.read_wav(raw)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if rate != RATE:
        raise RuntimeError("%s rendered at %d Hz" % (name, rate))
    n, f = int(round(loop * RATE)), int(round(fold * RATE))
    body = data[n:2 * n + f].copy()
    w = (0.5 - 0.5 * np.cos(math.pi * np.arange(f) / f))[:, None]
    body[:f] = body[:f] * w + body[n:n + f] * (1.0 - w)  # out[0] continues out[n-1]
    body = body[:n]
    if flutter:
        body = np.stack([wow(body[:, c], *flutter) for c in range(2)], -1)
    return body


def master(name, data):
    rate, bits = LOFI[name]
    data = np.stack([lofi(data[:, c], rate, bits, 60 + c) for c in range(2)], -1)
    data = data - data.mean(axis=0)
    data = data / (np.abs(data).max() + 1e-9) * 0.5
    lufs = A.integrated_lufs(data, RATE)
    data = data * 10 ** ((TARGET_LUFS[name] - lufs) / 20.0)
    tp = A.true_peak_dbfs(data, RATE)
    if tp > -1.0:
        data = data * 10 ** ((-1.0 - tp) / 20.0)
    return data


def save(name, data):
    path = os.path.join(OUT, name + ".wav")
    rate = RATE
    if name.startswith("mus_room_"):
        step = RATE // ROOM_RATE
        data = np.stack([band(data[:, c], None, ROOM_RATE * 0.46, order=4) for c in range(2)], -1)[::step]
        rate = ROOM_RATE
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())
    seam = A.loop_discontinuity(data)
    print("wrote %s  %.2f s  LUFS %.1f  TP %.1f  seam %.3f  wrap_hf %.1f dB" % (
        path, len(data) / rate, A.integrated_lufs(data, rate), A.true_peak_dbfs(data, rate),
        seam["jump_ratio"], seam["wrap_hf_dbfs"]))
    return len(data) / rate


def register(lengths):
    import json
    with open(MANIFEST, encoding="utf-8") as f:
        m = json.load(f)
    for name, sec in lengths.items():
        m["sounds"][name] = {"kind": "loop", "files": ["res://audio/loops/%s.wav" % name],
                             "loop_seconds": round(sec, 3)}
    for name in RETIRED:
        m["sounds"].pop(name, None)
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as f:
        json.dump(m, f, indent=1, ensure_ascii=False)
        f.write("\n")


if __name__ == "__main__":
    only = sys.argv[1:]
    lengths = {}
    for fn in TRACKS:
        if only and fn.__name__ not in only:
            continue
        lengths[fn.__name__] = save(fn.__name__, master(fn.__name__, fn()))
    for name in NKIDO_TRACKS:
        if only and name not in only:
            continue
        lengths[name] = save(name, master(name, render_nkido(name)))
    register(lengths)
