# -*- coding: utf-8 -*-
"""Synthesizes the background music (game/audio/loops/mus_*.wav) and
registers it in game/audio/manifest.json.

    python -X utf8 tools/build_music.py

Every track is made from the ending song's own tune (MELODY / HARMONY in
tools/build_song_layers.py): fragments, slower or re-metered versions and
other chords, on worn timbres (an out-of-tune music box, closed-lip hums, a
leaky reed organ, a wet finger round porcelain, teeth counted on a lip). The
tune is the game's one piece of music, so every place it is heard points at
the ending.

docs/spec/08-presentation.md 3: while digging there is no music, only the
low drone (the song's faint melody is the one exception, already in
song_melody). So none of these plays in the flesh. Where each one plays
(game/audio/fp_music.gd):

  mus_title    start screen        music box lullaby over a worn organ, a
                                   hum joins, then the chords turn minor
  mus_restroom white restroom      fragments sung by a wet finger round the
                                   porcelain, far apart in a tiled room;
                                   mostly silence (03 1: so
                                   quiet you hear your own breath)
  mus_vent     vent trade open     teeth clicked on a lip, a plucked low
                                   string, the tune late on a reed organ,
                                   then backwards on the box, down a duct
  mus_pause    Esc (eyes shut)     the hum heard through your own lids at the
                                   lids' heartbeat (66 bpm), blood rushing
  mus_keybind  key settings stage  the tune re-metered as a slow, sagging
                                   music-box waltz with missing teeth, for
                                   the turning stage of dolls

Each is a seamless loop of whole bars: notes and reverb tails wrap round
the loop end (circular placement and circular convolution), every slow
modulation runs a whole number of cycles per loop, noise is filtered in the
frequency domain over the whole loop. Deterministic (fixed seeds). Lo-fi:
sample-and-hold down to an older rate and a coarser word length (PS1-era
streamed music), then mastered to TARGET_LUFS with a true peak of at most
-1 dBFS like the song layers.
"""
import math
import os
import sys
import wave

import numpy as np
from scipy.signal import lfilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "game", "tools", "audio"))
import analyze_audio as A  # noqa: E402
from build_song_layers import HARMONY, MELODY, low_hum, midi_hz, nasal_hum  # noqa: E402

RATE = 48000
OUT = os.path.join(HERE, "..", "game", "audio", "loops")
MANIFEST = os.path.join(HERE, "..", "game", "audio", "manifest.json")

# Integrated loudness per track. The restroom one sits just above the room's
# own hum bed (amb_restroom -34) so the light, the water and your breath stay
# on top; the menus are about where the song's tine (-24) is; the vent trade
# stays under where the being's voice will be.
TARGET_LUFS = {
    "mus_title": -23.0, "mus_restroom": -31.0, "mus_vent": -27.0,
    "mus_pause": -25.0, "mus_keybind": -24.0,
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


def duct(x, delay_ms, feedback):
    """A pipe's comb resonance, applied as its steady-state response (circular)."""
    n = len(x)
    w = 2 * math.pi * np.fft.rfftfreq(n, 1.0 / RATE)
    h = 1.0 / (1.0 - feedback * np.exp(-1j * w * delay_ms / 1000.0))
    return np.fft.irfft(np.fft.rfft(x) * h, n) * (1.0 - feedback)


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


def rim(f, dur, rng):
    """A wet fingertip drawn round the porcelain rim (a glass-harp tone):
    it swells in, sings with the stick-slip roughness of skin on glaze,
    and dies away. No struck attack, so nothing in the quiet room pings."""
    m = int((dur + 1.4) * RATE)
    tt = np.arange(m) / RATE
    env = np.minimum(1.0, 0.5 - 0.5 * np.cos(math.pi * np.minimum(1.0, tt / 0.35)))
    after = np.maximum(0.0, tt - dur)
    env *= np.exp(-after / 0.45)
    grit = band(rng.standard_normal(m), 4, 30)
    grit /= np.abs(grit).max() + 1e-9
    waver = 1.0 + 0.0015 * grit
    phase = 2 * math.pi * np.cumsum(f * waver) / RATE + rng.uniform(0, 6.28)
    tone = np.zeros(m)
    for ratio, amp in [(1.0, 1.0), (2.012, 0.22), (3.03, 0.07), (4.9, 0.025)]:
        if f * ratio < RATE * 0.45:
            tone += amp * np.sin(phase * ratio)
    return tone * env * (1.0 + 0.12 * grit)


def pluck(f, rng, length=2.4, damping=0.996):
    """A dull plucked low string (Karplus-Strong through lfilter)."""
    m = int(length * RATE)
    p = max(2, int(round(RATE / f)))
    exc = np.zeros(m)
    burst = band(rng.standard_normal(p * 4), None, f * 6) if p * 4 > 8 else rng.standard_normal(p * 4)
    exc[: p * 4] = burst * np.hanning(p * 4)
    a = np.zeros(p + 2)
    a[0] = 1.0
    a[p] = -0.5 * damping
    a[p + 1] = -0.5 * damping
    y = lfilter([1.0], a, exc)
    tt = np.arange(m) / RATE
    return y / (np.abs(y).max() + 1e-9) * np.exp(-tt / 0.9)


def click(rng, gain=1.0):
    """A tooth tapped on a tooth: a tiny bright knock."""
    m = int(0.03 * RATE)
    x = rng.standard_normal(m) * np.exp(-np.arange(m) / (0.0025 * RATE))
    f0 = rng.uniform(2300, 3600)
    tt = np.arange(m) / RATE
    ring = np.sin(2 * math.pi * f0 * tt) * np.exp(-tt / 0.006)
    return (band(x, 900, 6000) * 0.6 + ring * 0.5) * gain


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


def mus_restroom():
    """The restroom: a few notes of the tune sung by a wet finger round the
    porcelain, far apart, the tiles answering. The gaps are long; the room's
    own light and water and your breath fill them. Kept off the tube's
    60/120/180 Hz and its 2.4 kHz buzz (amb_restroom)."""
    n = int(96.0 * RATE)
    rng = np.random.default_rng(202)
    sung = np.zeros(n)
    slow = 0.85

    def phrase(idx, at, transpose=0, gain=1.0):
        base = MELODY[idx[0]][0]
        for i in idx:
            b, length, note = MELODY[i]
            place(sung, rim(midi_hz(note + transpose), length * slow, rng) * gain,
                  int((at + (b - base) * slow + rng.normal(0.0, 0.04)) * RATE))

    phrase([0, 1, 2, 3], 4.0)
    phrase([4, 5, 6], 28.0, gain=0.85)
    for at, dur, note in ((50.0, 2.6, 62), (52.4, 3.2, 57)):
        place(sung, rim(midi_hz(note), dur, rng) * 0.6, int(at * RATE))
    phrase([7, 8, 9, 10], 66.0, 12, gain=0.3)
    phrase([11, 12, 13], 82.0, gain=0.8)  # stops on E, the loop's first F# answers it
    # the cistern's water holding D and A, swelling once across the loop
    t = np.arange(n) / RATE
    tank = (np.sin(2 * math.pi * midi_hz(62) * t) + 0.6 * np.sin(2 * math.pi * midi_hz(69) * t))
    tank = tank * (cycles(n, 1, -math.pi / 2) ** 2) * 0.03
    tank += band(loop_noise(n, 9, 250, 900) * cycles(n, 3, 0.4), 250, 900) * 0.012
    dry = band(sung, 220, 5000) * 0.5 + tank
    dry = wow(dry, 0.0015, [1, 3])
    l, r = reverb(dry, 1.3, 6000, 21, predelay=0.006)
    return np.stack([dry * 0.6 + l * 0.6, dry * 0.6 + r * 0.6], -1)


def mus_vent():
    """The vent trade: teeth tapped on a lip like someone counting, a dull
    low string walking the chords, the tune coming late on a reed organ, then
    backwards on the box, all heard down a sheet-metal duct."""
    unit = 0.5
    phrase = PHRASE_UNITS * unit
    n = int(round(4 * phrase * RATE))
    rng = np.random.default_rng(303)
    clicks = np.zeros(n)
    accent = [1.0, 0.3, 0.6, 0.3, 0.9, 0.3, 0.5, 0.45]
    for u in range(4 * PHRASE_UNITS):
        if rng.random() < 0.12:  # a tooth missed
            continue
        at = u * unit + rng.normal(0.0, 0.012)
        place(clicks, click(rng, accent[u % 8]), int(at * RATE))
    bass = np.zeros(n)
    for p in range(4):
        for b, length, note in HARMONY:
            for off in range(0, length, 2):
                place(bass, pluck(midi_hz(note - 12), rng) * (1.0 if off == 0 else 0.6),
                      int((p * phrase + (b + off) * unit) * RATE))
    late = []
    for p in (1, 3):
        late += timed(MELODY, unit, p * phrase + unit * 0.5, -12)  # half a unit behind
    organ = organ_line(n, late, detune=14.0, seed=3.0)
    box = np.zeros(n)
    rev = []
    for b, length, note in MELODY:
        rev.append((PHRASE_UNITS - 2 - b - length, length, note))
    box_line(box, timed(rev, unit, 2 * phrase, 12), rng, detune_spread=25.0, gain=0.8)
    dry = clicks * 0.22 + band(bass, 50, 1500) * 0.5 + band(organ, 80, 2500) * 0.13 + box * 0.4
    dry = duct(dry, 5.3, 0.45)
    dry = wow(dry, 0.006, [3, 11], [0.0, 2.1])
    l, r = reverb(dry, 0.9, 2500, 31, predelay=0.02)
    return np.stack([dry * 0.8 + l * 0.35, dry * 0.8 + r * 0.35], -1)


def mus_pause():
    """Eyes shut (Esc): the hum heard from inside your own head, through the
    lids, at the lids' heartbeat (fp_pause_lids.gdshader beats 1.1 times a
    second, so one unit of the tune is one beat); a second voice under it the
    second time; blood rushing; then only pieces of it."""
    unit = 1.0 / 1.1
    phrase = PHRASE_UNITS * unit
    n = int(round(3 * phrase * RATE))
    lead = timed(MELODY, unit) + timed(MELODY, unit, phrase)
    lead += timed([MELODY[i] for i in (0, 1, 2, 3)], unit, 2 * phrase)
    lead += timed([MELODY[i] for i in (11, 12, 13)], unit, 2 * phrase)
    hum = voice_line(n, lead, nasal_hum, attack=0.16, release=0.4)
    second = voice_line(n, timed(HARMONY, unit, phrase) + timed(HARMONY[:4], unit, 2 * phrase),
                        low_hum, attack=0.2, release=0.5, glide=0.14)
    pad = organ_line(n, timed(HARMONY, unit, 0, -12) + timed(HARMONY, unit, 2 * phrase, -12), detune=6.0, seed=4.0)
    blood = loop_noise(n, 13, 30, 220) * (0.35 + 0.65 * cycles(n, 4, 0.7))
    dry = band(hum * 0.5 + second * 0.32 + pad * 0.06, 70, 1100, order=3) + blood * 0.09
    dry = wow(dry, 0.003, [1, 5])
    l, r = reverb(dry, 3.4, 1400, 41, predelay=0.03)
    return np.stack([dry * 0.7 + l * 0.5, dry * 0.7 + r * 0.5], -1)


# the tune re-metered into 3/4: long-short pairs, (beat, beats, midi), 24 beats
WALTZ = [(0, 2, 66), (2, 1, 69), (3, 2, 71), (5, 1, 69), (6, 2, 66), (8, 1, 64), (9, 3, 62),
         (12, 2, 64), (14, 1, 66), (15, 2, 69), (17, 1, 71), (18, 2, 69), (20, 1, 66), (21, 3, 64)]
# one chord per bar from HARMONY's eight roots: (bass, two upper notes)
WALTZ_CHORDS = {62: (50, 66, 69), 66: (54, 69, 73), 57: (45, 61, 64), 59: (47, 62, 66), 61: (49, 64, 69)}


def mus_keybind():
    """The key settings stage (dolls on a turning stage): the tune as a slow
    music-box waltz, slower than any jingle and never quite in tune. Plain;
    in minor; with the harmony ringing above; an octave up and thin; and last
    with teeth missing from the comb. The spring's pull drifts the pitch."""
    q = 0.72
    phrase = 24 * q
    n = int(round(5 * phrase * RATE))
    rng = np.random.default_rng(505)
    box = np.zeros(n)
    acc = np.zeros(n)
    roots = [note for _b, _l, note in HARMONY]
    for p in range(5):
        at = p * phrase
        mel = list(WALTZ)
        transpose = 12
        minor = p == 1
        if minor:
            mel = [(b, l, {66: 65, 71: 70}.get(note, note)) for b, l, note in mel]
        if p == 3:
            transpose = 24
        if p == 4:
            mel = [e for i, e in enumerate(mel) if i % 3 != 2]
        box_line(box, timed(mel, q, at, transpose), rng, detune_spread=20.0,
                 gain=0.7 if p == 3 else 1.0, bright=0.6 if p == 3 else 0.8)
        for bar in range(8):
            bass, u1, u2 = WALTZ_CHORDS[roots[bar]]
            if minor:
                u1, u2 = [{66: 65, 73: 72, 54: 53, 69: 69}.get(u, u) for u in (u1, u2)]
            t0 = at + bar * 3 * q
            place(acc, tine(midi_hz(bass), rng, 0.0, 2.0, 0.5) * 0.55, int(t0 * RATE))
            for beat in (1, 2):
                for u in (u1, u2):
                    place(acc, tine(midi_hz(u), rng, rng.uniform(-9, 9), 1.2, 0.3) * 0.11,
                          int((t0 + beat * q) * RATE))
        if p == 2:
            box_line(box, timed(HARMONY, q * 0.75, at, 24, 1.0), rng, gain=0.25, bright=0.5)
    clicks = np.zeros(n)
    for b in range(int(round(5 * 24))):
        place(clicks, click(rng, 0.25 if b % 3 == 0 else 0.12), int(b * q * RATE) - int(0.004 * RATE))
    dry = box * 0.5 + band(acc, 70, 4000) * 0.6 + band(clicks, 1500, 7000) * 0.12
    # the spring: pitch sags once round the loop, with a small flutter
    dry = wow(dry, 0.009, [1, 9], [0.0, 0.5])
    l, r = reverb(dry, 1.8, 4200, 51)
    return np.stack([dry * 0.75 + l * 0.42, dry * 0.75 + r * 0.42], -1)


TRACKS = (mus_title, mus_restroom, mus_vent, mus_pause, mus_keybind)
LOFI = {"mus_title": (22050, 12), "mus_restroom": (24000, 12), "mus_vent": (16000, 10),
        "mus_pause": (22050, 12), "mus_keybind": (22050, 12)}


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
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    seam = A.loop_discontinuity(data)
    print("wrote %s  %.2f s  LUFS %.1f  TP %.1f  seam %.3f  wrap_hf %.1f dB" % (
        path, len(data) / RATE, A.integrated_lufs(data, RATE), A.true_peak_dbfs(data, RATE),
        seam["jump_ratio"], seam["wrap_hf_dbfs"]))
    return len(data) / RATE


def register(lengths):
    import json
    with open(MANIFEST, encoding="utf-8") as f:
        m = json.load(f)
    for name, sec in lengths.items():
        m["sounds"][name] = {"kind": "loop", "files": ["res://audio/loops/%s.wav" % name],
                             "loop_seconds": round(sec, 3)}
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
    register(lengths)
