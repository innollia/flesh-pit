"""Low-poly console look translated to sound. Run: py -3 build.py

All sound comes from nkido. This script only (1) writes the score into .akkado
patches, (2) calls `nkido render` per stem, (3) folds each render's tail onto its
head, sets stem gains, normalises, (4) measures.

Look -> sound
  affine texture swim -> oscillators read a 32-step table; timbre and pitch offsets
                         are held per 30 fps frame, so they snap instead of glide
  vertex snap, jitter -> pitch walks in whole semitones, onsets jitter off the grid
  dithered gradient   -> two harmonic worlds cross by a 4x4 Bayer matrix, not a fade
  few colours         -> five timbres: tile, grout, pink, red, ivory
  near-sighted fog    -> one distance curve drives lowpass and dark reverb send
"""
import hashlib, os, struct, subprocess, sys, wave, zlib
from concurrent.futures import ThreadPoolExecutor
import numpy as np
import scipy.signal as sg

HERE = os.path.dirname(os.path.abspath(__file__))
NKIDO = r"C:\projects\_tools\nkido\build-clang\bin\nkido.exe"
SR, STEP = 48000, 6900
BPM = 60 * SR / (STEP * 4)            # nkido: one cycle = one beat = four steps
SECTIONS = [("A", 8, 16), ("B", 6, 16), ("C", 10, 16), ("D", 8, 14), ("E", 6, 16)]
TAIL_STEPS = 64

BARS, s0 = [], 0
for name, nb, sb in SECTIONS:
    for i in range(nb):
        BARS.append(dict(sec=name, i=i, start=s0, sb=sb))
        s0 += sb
N_STEPS = s0
TOTAL = N_STEPS + TAIL_STEPS
CYCLES = TOTAL // 4
L = N_STEPS * STEP
SEC_START = {}
for b in BARS:
    SEC_START.setdefault(b["sec"], b["start"])
SEC_END = {n: SEC_START[n] + nb * sb for n, nb, sb in SECTIONS}
A, B_, C, D, E = (SEC_START[k] for k in "ABCDE")
FRAME = (SR / 30) / STEP
BAYER = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16


def grad(step):
    return float(np.interp(step, [0, B_, C, E + 32, N_STEPS], [0, 0, 1, 1, 0]))


def fog(step):
    p = [0, B_, C, D, E, E + 48, E + 64, N_STEPS]
    v = [0.04, 0.05, 0.42, 0.14, 0.22, 0.95, 0.9, 0.04]
    return float(np.interp(step, p, v))


def bayer_thr(cell):
    return BAYER[(cell // 16) % 4, cell % 4]


def world_at(step):
    return 2 if grad(step) > bayer_thr(int(step)) else 1


W1 = [(38, [57, 62, 64, 65, 69]), (34, [58, 62, 65, 69]), (41, [57, 60, 64, 65]),
      ((39, [58, 62, 67, 69]), (33, [55, 61, 64, 70]))]
W2 = [(37, [56, 61, 63, 64, 68]), (33, [57, 61, 64, 68]), (42, [57, 61, 64, 66]),
      ((38, [57, 62, 66, 68]), (32, [54, 60, 63, 69]))]
WD = [(37, [56, 61, 64, 68]), (40, [59, 63, 64, 68]), (33, [57, 61, 64, 68]),
      ((42, [57, 61, 66, 69]), (32, [54, 60, 63, 69]))]


def chord_of(bar, s, world):
    tab = WD if bar["sec"] == "D" else (W2 if world == 2 else W1)
    c = tab[bar["i"] % 4]
    if isinstance(c[0], tuple):
        c = c[0] if s < bar["sb"] / 2 else c[1]
    return c


NAMES = ["c", "c#", "d", "d#", "e", "f", "f#", "g", "g#", "a", "a#", "b"]


def nm(m):
    m = int(round(m))
    return f"{NAMES[m % 12]}{m // 12 - 1}"


def pattern(events, default_vel=None):
    """events: (start, dur, midi, vel) in steps -> one long n-pattern over the render."""
    ev = sorted(events, key=lambda e: e[0])
    out, pos = [], 0.0
    for k, (s, d, m, v) in enumerate(ev):
        s = round(max(s, pos), 3)
        nxt = ev[k + 1][0] if k + 1 < len(ev) else TOTAL
        d = round(min(d, max(nxt - s, 0.05)), 3)
        if s > pos + 1e-4:
            out.append(f"~@{s - pos:.3f}")
        out.append(f"{nm(m)}:{min(v, 1):.3f}@{d:.3f}")
        pos = s + d
    if pos < TOTAL:
        out.append(f"~@{TOTAL - pos:.3f}")
    return 'n"[' + " ".join(out) + f']/{CYCLES}"'


def values(fn, cell=4.0):
    """Held value curve: run-length merged."""
    out, cur, run = [], None, 0.0
    t = 0.0
    while t < TOTAL - 1e-6:
        v = round(fn(t), 3)
        if v == cur:
            run += cell
        else:
            if cur is not None:
                out.append(f"{cur}@{run:g}")
            cur, run = v, cell
        t += cell
    out.append(f"{cur}@{run:g}")
    return 'v"[' + " ".join(out) + f']/{CYCLES}"'


# ---- score ----------------------------------------------------------------
V = {k: [] for k in ["bL", "bC", "bR", "glint", "echo", "ivL", "ivR", "arpL", "arpC", "arpR", "lead", "bass",
                     "kick", "snare", "tickL", "tickR", "tone", "squelch", "drop", "tomb"]}
rj = np.random.default_rng(11)


def jit(sec, amt=0.03):
    if sec in ("C", "D"):
        amt *= 1.6
    return float(rj.choice([0, 0, 1, 2])) * amt


def bell(step, m, vel, slot):
    V[["bL", "bC", "bR"][slot % 3]].append((step, 8, m, vel))


theme1 = [(0, 3, 74), (3, 3, 69), (6, 2, 76), (8, 4, 77), (12, 2, 76), (14, 2, 72),
          (16, 6, 74), (22, 2, 69), (24, 3, 70), (27, 3, 69), (30, 2, 67),
          (32, 3, 65), (35, 3, 69), (38, 2, 72), (40, 4, 76), (44, 2, 74), (46, 2, 69),
          (48, 6, 75), (54, 2, 74), (56, 8, 73)]
theme2 = [(0, 3, 74), (3, 3, 69), (6, 2, 76), (8, 4, 77), (12, 2, 79), (14, 2, 81),
          (16, 6, 82), (22, 2, 81), (24, 3, 79), (27, 3, 77), (30, 2, 76),
          (32, 3, 77), (35, 3, 76), (38, 2, 74), (40, 4, 72), (44, 2, 76), (46, 2, 79),
          (48, 6, 75), (54, 2, 74), (56, 4, 73), (60, 2, 76), (62, 2, 81)]


def warp14(th):
    return [(s // 16 * 14 + int(round(s % 16 * 14 / 16)), max(1, int(round(d * 14 / 16))), m) for s, d, m in th]


for k, (s, d, m) in enumerate(theme1):
    bell(A + s + jit("A"), m, 0.8, k)
    V["ivL"].append((A + s + jit("A"), 2, m - 12, 0.9))
for k, (s, d, m) in enumerate(theme2):
    bell(A + 32 + s + jit("A"), m + 12, 0.72, k)
    V["ivL"].append((A + 32 + s + jit("A"), 2, m - 12, 0.8))


def glint(step, notes, vel=0.6):
    for k, m in enumerate(notes):
        V["glint"].append((step + k * FRAME, FRAME, m, vel))


glint(A + 31, [62, 65, 69, 72, 76, 77, 81, 84, 88])
glint(D - 5, [61, 64, 68, 73, 76, 80, 85, 88])
glint(N_STEPS - 3, [64, 67, 70, 73, 76, 79, 82, 85, 88, 91], 0.5)

for s, d, m in [(0, 32, 62), (32, 16, 61), (48, 8, 62), (56, 40, 61)]:
    V["lead"].append((B_ + s, d, m, 0.55))
for bar in (0, 1, 3, 4):
    for k, (s, d, m) in enumerate(theme1[:6 if bar % 2 == 0 else 4]):
        st = B_ + bar * 16 + s
        bell(st + jit("B", 0.05), m + (-1 if world_at(st) == 2 else 0), 0.55 - 0.05 * bar, bar * 2 + k)

lead_c = [(0, 12, 73), (12, 4, 68), (16, 12, 75), (28, 4, 76), (32, 8, 76), (40, 8, 75), (48, 8, 74), (56, 8, 73)]
lead_c += [(64 + s, d, m - 1) for s, d, m in theme1]
lead_c += [(128, 6, 80), (134, 2, 78), (136, 8, 76), (144, 4, 76), (148, 4, 75), (152, 8, 73)]
for s, d, m in lead_c:
    V["lead"].append((C + s + jit("C"), d - 0.1, m, 0.85))

t14a = warp14([(s, d, m - 1) for s, d, m in theme1])
t14b = warp14([(s, d, m - 1) for s, d, m in theme2])
for s, d, m in t14a:
    V["lead"].append((D + s + jit("D"), d - 0.1, m, 0.8))
    bell(D + s + jit("D"), m + 12, 0.4, s)
for s, d, m in t14b:
    V["lead"].append((D + 56 + s + jit("D"), d - 0.1, m, 0.9))
    bell(D + 56 + s + jit("D"), m + 12, 0.6, s)
    V["ivL"].append((D + 56 + s + jit("D"), 2, m - 5, 0.75))

for bar, cnt in ((0, 6), (2, 3), (3, 2)):
    for k, (s, d, m) in enumerate(theme1[:cnt]):
        st = E + bar * 16 + s
        bell(st, m - 1, 0.8, k)
        V["echo"].append((st + 6, 3, m - 1, 0.5))
for st, d, m in [(E + 32, 16, 55), (E + 48, 16, 56), (E + 64, 16, 57)]:
    V["lead"].append((st, d - 0.2, m, 0.6))

BASS = {"C": [(0, 0, 3), (3, 0, 2), (6, 12, 2), (8, 0, 3), (11, -2, 3), (14, 7, 2)],
        "D": [(0, 0, 3), (3, 0, 2), (6, 12, 2), (8, 0, 2), (10, 7, 2), (12, -2, 2)],
        "A": [(0, 0, 8), (10, 0, 4), (14, 12, 2)]}
for b in BARS:
    if b["sec"] in BASS and not (b["sec"] == "A" and b["i"] < 2):
        for s, iv, d in BASS[b["sec"]]:
            root, _ = chord_of(b, s, 2 if b["sec"] != "A" else 1)
            V["bass"].append((b["start"] + s, d - 0.1, root + iv + 12, 0.6 if b["sec"] == "A" else 1.0))
    elif b["sec"] in ("B", "E"):
        root, _ = chord_of(b, 0, 1 if b["sec"] == "B" and b["i"] < 2 else 2)
        V["bass"].append((b["start"], b["sb"] - 0.1, root + 12, 0.5))

ARP = [0, 2, 1, 3, 2, 0, 3, 1]
for b in BARS:
    sec = b["sec"]
    for s in range(b["sb"]):
        st = b["start"] + s
        on = {"A": b["i"] >= 4 and s % 2 == 1, "B": True, "C": s % 4 == 2 or (s % 8 == 7 and b["i"] >= 4),
              "D": True, "E": b["i"] >= 4}[sec]
        if not on:
            continue
        _, tones = chord_of(b, s, world_at(st))
        m = sorted(tones)[ARP[s % 8] % len(tones)] + (12 if sec in ("D", "E") and s % 8 >= 4 else 0)
        if sec == "D" and b["i"] >= 4 and s % 3 == 0:
            m += 12
        vel = {"A": 0.4, "B": 0.55, "C": 0.5, "D": 0.6, "E": 0.15 + 0.5 * (st - (E + 64)) / 32}[sec]
        V[["arpL", "arpR", "arpC", "arpR", "arpL"][s % 5]].append((st + jit(sec), 1, m, vel))


def tick(st, v, tone=False):
    V["tickL" if int(st) % 2 == 0 else "tickR"].append((st, 0.8, 69, v))
    if tone:
        V["tone"].append((st, 0.8, 69, v))


kicks = []
for b in BARS:
    sec, i, sb, base = b["sec"], b["i"], b["sb"], b["start"]
    if sec == "A":
        if i >= 4:
            for s in (0, 10):
                V["kick"].append((base + s, 2, 40, 0.75))
            V["snare"].append((base + 12, 2, 40, 0.5))
        for s in range(0, 16, 2):
            tick(base + s, 0.45 if s % 4 else 0.65, s % 8 == 4)
    elif sec == "B":
        for s in range(16):
            if bayer_thr(base + s) > grad(base + s) + 0.15:
                tick(base + s, 0.4)
    elif sec == "C":
        for s in ((0, 6, 10) if i % 2 == 0 else (0, 6, 10, 13)):
            V["kick"].append((base + s, 2, 40, 0.95))
        for s in (4, 12):
            V["snare"].append((base + s + jit(sec), 2, 40, 0.85))
        for s in range(16):
            if s % 2 == 1 or i >= 4:
                tick(base + s, 0.35 + 0.25 * (s % 4 == 3))
        for s in (3, 7, 9, 15)[: 2 + i % 3]:
            V["squelch"].append((base + s + jit(sec), 1, chord_of(b, s, 2)[0] + 24, 0.7))
    elif sec == "D":
        for s in (0, 6, 10):
            V["kick"].append((base + s, 2, 40, 1.0))
        for s in (4, 11):
            V["snare"].append((base + s + jit(sec), 2, 40, 0.95))
        for s in range(14):
            tick(base + s, 0.4 + 0.25 * (s % 2 == 0), s % 7 == 0)
    elif sec == "E":
        if i == 0:
            V["kick"].append((base, 2, 40, 0.85))
        if i in (0, 1):
            V["snare"].append((base + 12, 2, 40, 0.6 / (i + 1)))
        if i >= 4:
            for s in range(0, 16, 1 if i == 5 else 2):
                tick(base + s, 0.25 + 0.35 * (i - 4) * s / 16, True)
        if i == 5:
            for s in range(8, 16):
                V["snare"].append((base + s, 0.9, 40, 0.15 + 0.6 * ((s - 8) / 8) ** 2))

rd = np.random.default_rng(23)
for st in range(N_STEPS):
    if rd.uniform() < 0.1 * grad(st):
        V["drop"].append((st, 1, int(rd.integers(62, 76)), 0.7))

# pads: tone-index voices per world
PV = {(w, i): [] for w in (1, 2) for i in range(5)}
for w in (1, 2):
    for b in BARS:
        if (b["sec"] == "A" and w == 2) or (b["sec"] in ("C", "D") and w == 1):
            continue
        tab = WD if b["sec"] == "D" else W1
        split = isinstance(tab[b["i"] % 4][0], tuple)
        parts = [(0, b["sb"] // 2), (b["sb"] // 2, b["sb"] - b["sb"] // 2)] if split else [(0, b["sb"])]
        for s, sp in parts:
            for i, m in enumerate(chord_of(b, s, w)[1]):
                PV[w, i].append((b["start"] + s, sp, m, 0.8))

FOG = values(lambda t: fog(min(t, N_STEPS)), 4.0)
DITHER = values(lambda t: 1.0 if t < N_STEPS and grad(t) > bayer_thr(int(t * 2)) else 0.0, 0.5)

# ---- patches --------------------------------------------------------------
HEAD = f"""// generated by build.py; loop {N_STEPS} steps + tail {TAIL_STEPS}
frame = phasor(30) < 0.02
fg = sah(slew({FOG}, 3), frame)
cut = 520 * 20 ^ (1 - fg)
"""
T = 6.2831853
KICKS = pattern(V["kick"])


def pads():
    tx = HEAD + f"""
g = slew({DITHER}, 300)
k = {KICKS} as kk
duck = 1 - 0.5 * ar(kk.trig, 0.002, 0.14)
wob = floor(sah(sine(0.8), frame) * 2 + 0.5) / 2
scanA = sah(sine(0.17), frame) * 0.5 + 0.5
scanB = sah(sine(0.31), frame) * 0.5 + 0.5
fn tileTab(f, w) -> {{
  q = floor(phasor(f) * 32) / 32
  sin(q * {T}) + 0.3 * w * sin(q * {T * 3}) + 0.2 * w * sin(q * {T * 5}) + 0.12 * w * sin(q * {T * 7})
}}
fn fleshTab(f, w) -> {{
  qq = floor(phasor(f) * 32) / 32
  sin(qq * {T}) + 0.45 * sin(qq * {T * 2}) + (0.2 + 0.5 * w) * sin(qq * {T * 3}) + 0.5 * w * sin(qq * {T * 4}) + 0.12 * sin(qq * {T * 6})
}}
"""
    names = {1: [], 2: []}
    for (w, i), ev in PV.items():
        if not ev:
            continue
        v = f"p{w}{i}"
        names[w].append((i, f"x{w}{i}"))
        fn_ = "tileTab" if w == 1 else "fleshTab"
        f = f"{v}.freq" if w == 1 else f"{v}.freq * (1 + 0.006 * wob)"
        scan = "scanA" if w == 1 else "scanB"
        tx += f"{pattern(ev)} as {v}\nx{w}{i} = {fn_}({f}, {scan}) * adsr({v}.gate, 0.03, 0.8, 0.7, 0.3)\n"
    for side, pick in (("L", 0), ("R", 1)):
        terms = []
        for w in (1, 2):
            sel = " + ".join(n for i, n in names[w] if i % 2 == pick)
            oth = " + ".join(n for i, n in names[w] if i % 2 != pick)
            ctl = "(1 - g)" if w == 1 else "g"
            terms.append(f"(({sel}) + 0.35 * ({oth})) * {ctl}")
        tx += f"s{side} = ({' + '.join(terms)}) * duck |> lp(@, cut * 0.6, 0.7)\n"
    tx += """dry = pan(sL, -0.5) + pan(sR, 0.5)
wet = dry * (0.2 + fg) |> freeverb(@, 0.85, 0.6)
dry * 0.5 + wet * 0.4 |> hp(@, 70) |> @ * 0.07 |> out(@)
"""
    return tx


def bells():
    tx = HEAD + """
fn belly(f, t, b) -> {
  idx = b * (1.3 * ar(t, 0.0005, 0.13) + 0.45 * ar(t, 0.0005, 0.7))
  m = sine(f * 3.01, 0, t)
  c = sine(f * (1 + idx * m), 0, t)
  h = sine(f * 7.03, 0, t) * ar(t, 0.0003, 0.05) * 0.2
  (c + h) * ar(t, 0.0006, 0.75)
}
"""
    for k in ("bL", "bC", "bR", "glint", "echo"):
        tx += f'{pattern(V[k])} as {k}E\n'
    tx += """
L = belly(bLE.freq, bLE.trig, 1) * bLE.vel |> lp(@, cut, 0.7)
C = belly(bCE.freq, bCE.trig, 1) * bCE.vel |> lp(@, cut, 0.7)
R = belly(bRE.freq, bRE.trig, 1) * bRE.vel |> lp(@, cut, 0.7)
G = belly(glintE.freq, glintE.trig, 0.6) * glintE.vel * 0.7 * ar(glintE.trig, 0.0005, 0.12) |> lp(@, cut, 0.7)
Q = belly(echoE.freq, echoE.trig, 0.6) * echoE.vel |> lp(@, cut * 0.45, 0.7)
dry = pan(L, -0.6) + C + pan(R, 0.6) + pan(G, 0.3) + pan(Q, -0.2)
rmx = dry * 0.3 |> freeverb(@, 0.55, 0.35)
far = dry * fg |> freeverb(@, 0.92, 0.75) |> lp(@, 2200, 0.7)
dry * (1 - 0.3 * fg) + rmx * 0.8 + far * 1.1 |> hp(@, 180) |> @ * 0.2 |> out(@)
"""
    return tx


def ivory():
    tx = HEAD + """
fn tooth(f, t) -> {
  y = sine(f, 0, t) * ar(t, 0.0004, 0.2) + 0.3 * sine(f * 2, 0, t) * ar(t, 0.0003, 0.11)
  y2 = 0.5 * sine(f * 3.93, 0, t) * ar(t, 0.0002, 0.05) + 0.16 * sine(f * 9.2, 0, t) * ar(t, 0.0002, 0.016)
  n = noise() * 0.22 * ar(t, 0.0001, 0.004)
  tanh((y + y2 + n) * 1.6)
}
"""
    for k in ("ivL", "ivR", "arpL", "arpC", "arpR"):
        tx += f"{pattern(V[k] or [(0, 1, 60, 0.0)])} as {k}E\n"
    tx += """
a = tooth(ivLE.freq, ivLE.trig) * ivLE.vel |> lp(@, cut, 0.7)
b = tooth(ivRE.freq, ivRE.trig) * ivRE.vel |> lp(@, cut, 0.7)
c = tooth(arpLE.freq, arpLE.trig) * arpLE.vel |> lp(@, cut, 0.7)
d = tooth(arpCE.freq, arpCE.trig) * arpCE.vel |> lp(@, cut, 0.7)
e2 = tooth(arpRE.freq, arpRE.trig) * arpRE.vel |> lp(@, cut, 0.7)
dry = pan(a, -0.15) + pan(b, 0.3) + pan(c, -0.6) + d + pan(e2, 0.6)
rmx = dry * (0.2 + 0.5 * fg) |> freeverb(@, 0.6, 0.5)
dry + rmx * 0.6 |> hp(@, 110) |> @ * 0.17 |> out(@)
"""
    return tx


def lead():
    return HEAD + f"""
{pattern(V["lead"])} as e
fn pinkTab(f, w) -> {{
  q = floor(phasor(f) * 32) / 32
  y = sin(q * {T}) + 0.5 * sin(q * {T * 2}) + (0.2 + 0.7 * w) * sin(q * {T * 3}) + 0.7 * w * sin(q * {T * 5}) + 0.35 * w * sin(q * {T * 7})
  floor(y * 12) / 12
}}
wv = sah(sine(1.13) * 0.5 + 0.5, frame)
vib = floor((sah(sine(5.1), frame) * 0.6 + sah(noise(), frame) * 0.25) * 2 + 0.5) / 2
walk = floor(slew(e.note, 75) + 0.5)
f = mtof(walk + vib)
env = adsr(e.gate, 0.012, 0.5, 0.65, 0.09) * e.vel
mouth = 420 + 2100 * wv
a = pinkTab(f, wv) * env
b = pinkTab(f * 1.0041, wv) * env
fa = bp(a, mouth, 2.5) * 1.1 + a * 0.45 |> lp(@, cut * 1.8, 0.7)
fb = bp(b, mouth * 1.07, 2.5) * 1.1 + b * 0.45 |> lp(@, cut * 1.8, 0.7)
dry = pan(fa, -0.55) + pan(fb, 0.55)
wet = dry * (0.3 + fg) |> freeverb(@, 0.8, 0.65)
dry + wet * 0.5 |> hp(@, 120) |> @ * 0.17 |> out(@)
"""


def bass():
    return HEAD + f"""
{pattern(V["bass"])} as e
{KICKS} as kk
duck = 1 - 0.45 * ar(kk.trig, 0.002, 0.12)
fn redTab(f) -> {{
  q = floor(phasor(f) * 32) / 32
  y = sin(q * {T}) + 0.7 * sin(q * {T * 2}) + 0.55 * sin(q * {T * 3}) + 0.4 * sin(q * {T * 4}) + 0.25 * sin(q * {T * 5}) + 0.18 * sin(q * {T * 7})
  floor(y * 10) / 10
}}
env = adsr(e.gate, 0.003, 0.14, 0.55, 0.05) * e.vel
tone = sah(sine(0.5) * 0.5 + 0.5, frame)
redTab(e.freq) * env * duck |> lp(@, 700 + 1100 * tone * (1 - fg), 1.0) |> hp(@, 38) |> mono(@) |> tanh(@ * 1.3) |> @ * 0.24 |> out(@)
"""


def drums():
    tx = HEAD
    for k, en in (("kick", "kE"), ("snare", "sE"), ("tickL", "tlE"), ("tickR", "trE"), ("tone", "toE")):
        tx += f"{pattern(V[k])} as {en}\n"
    tx += """
kp = 52 + 120 * ar(kE.trig, 0.0002, 0.05) + 300 * ar(kE.trig, 0.0002, 0.008)
kk = tanh(sine(kp, 0, kE.trig) * ar(kE.trig, 0.0005, 0.26) * 3) * kE.vel
kb = sine(165, 0, kE.trig) * ar(kE.trig, 0.0005, 0.09) * 0.3 * kE.vel
grit = bitcrush(noise(0, 0, 11), 7, 0.33)
grit2 = bitcrush(noise(0, 0, 977), 7, 0.5)
sn = sine(200 + 60 * ar(sE.trig, 0.0002, 0.02), 0, sE.trig) * ar(sE.trig, 0.0005, 0.1) * 0.55
sn2 = sine(410, 0, sE.trig) * ar(sE.trig, 0.0005, 0.06) * 0.3
snn = bp(grit, 2200, 0.6) * ar(sE.trig, 0.0005, 0.16) * 1.2
snare = tanh(mono(sn + sn2 + snn) * 1.6) * sE.vel
tl = hp(grit, 3500, 0.7) * ar(tlE.trig, 0.0002, 0.03) * tlE.vel
tr = hp(grit2, 3500, 0.7) * ar(trE.trig, 0.0002, 0.03) * trE.vel
tt = sine(2350, 0, toE.trig) * ar(toE.trig, 0.0002, 0.025) * 0.5 * toE.vel
body = kk + kb
hat = pan(tl |> lp(@, cut + 900, 0.7), -0.6) + pan(tr |> lp(@, cut + 900, 0.7), 0.6) + (tt |> lp(@, cut + 900, 0.7))
sna = snare |> lp(@, cut + 900, 0.7)
sends = sna * (0.3 + 0.6 * fg) + hat * 0.15 |> freeverb(@, 0.62, 0.45)
body * 0.5 + sna * 0.4 + hat * 0.32 + sends * 0.5 |> hp(@, 42) |> @ * 0.34 |> out(@)
"""
    return tx


def tex():
    return HEAD + f"""
{pattern(V["squelch"] or [(0, 1, 60, 0.0)])} as q
{pattern(V["drop"] or [(0, 1, 60, 0.0)])} as dr
fn sq(f, w) -> {{
  p = floor(phasor(f) * 32) / 32
  sin(p * {T}) + 0.7 * w * sin(p * {T * 3}) + 0.8 * w * sin(p * {T * 4})
}}
sv = sq(mtof(q.note + 7 * ar(q.trig, 0.0005, 0.07)), 1 - ar(q.trig, 0.0005, 0.09)) * ar(q.trig, 0.001, 0.13) * q.vel
drf = dr.freq * (2.9 - 1.9 * ar(dr.trig, 0.0002, 0.05))
ds = sine(drf, 0, dr.trig) * ar(dr.trig, 0.001, 0.06) * dr.vel
sqf = sv |> lp(@, cut * 1.6, 1.2)
dsf = ds |> lp(@, cut + 700, 0.7)
dry = pan(sqf, -0.4) + pan(dsf, 0.45)
wet = dry * 0.4 |> freeverb(@, 0.7, 0.5)
dry + wet |> hp(@, 200) |> @ * 0.16 |> out(@)
"""


PATCHES = dict(pad=pads, bell=bells, ivory=ivory, lead=lead, bass=bass, drums=drums, tex=tex)
GAIN = dict(pad=1.15, bell=1.9, ivory=2.6, lead=0.75, bass=1.1, drums=3.0, tex=3.5)


def render(name):
    src = PATCHES[name]()
    path = os.path.join(HERE, f"{name}.akkado")
    h = hashlib.sha1(src.encode()).hexdigest()[:12]
    wav = os.path.join(HERE, "stems", f"{name}.{h}.wav")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(src)
    if not os.path.exists(wav):
        secs = TOTAL * STEP / SR
        r = subprocess.run([NKIDO, "render", path, "-o", wav, "--seconds", f"{secs:.3f}", "--rate", str(SR),
                            "--bpm", f"{BPM:.6f}", "--no-default-bank", "--float32"], capture_output=True, text=True)
        if r.returncode or not os.path.exists(wav):
            raise SystemExit(f"nkido failed on {name}:\n{r.stdout[-1500:]}\n{r.stderr[-1500:]}")
    return name, wav


def read_float(path):
    with open(path, "rb") as f:
        d = f.read()
    i = 12
    while i < len(d):
        cid, sz = d[i:i + 4], struct.unpack("<I", d[i + 4:i + 8])[0]
        if cid == b"data":
            return np.frombuffer(d[i + 8:i + 8 + sz], "<f4").reshape(-1, 2).astype(np.float64)
        i += 8 + sz + (sz & 1)
    raise SystemExit("no data " + path)


def fold(x):
    y = x[:L].copy()
    t = x[L:]
    y[:t.shape[0]] += t
    return y


os.makedirs(os.path.join(HERE, "stems"), exist_ok=True)
with ThreadPoolExecutor(4) as ex:
    paths = dict(ex.map(render, PATCHES))
stems = {k: fold(read_float(p)) * GAIN[k] for k, p in paths.items()}
mix = sum(stems.values())


# ---- measure ----------------------------------------------------------------
def lufs(x):
    pre = np.array([[1.53512485958697, -2.69169618940638, 1.19839281085285, 1, -1.69065929318241, 0.73248077421585],
                    [1, -2, 1, 1, -1.99004745483398, 0.99007225036621]])
    y = sg.sosfilt(pre, np.concatenate([x, x], 0), axis=0)[L:]
    bl, hop = int(0.4 * SR), int(0.1 * SR)
    p = np.sum(y**2, 1)
    cs = np.concatenate([[0], np.cumsum(np.concatenate([p, p[:bl]]))])
    pw = (cs[bl:] - cs[:-bl])[::hop][: L // hop] / bl
    l_ = -0.691 + 10 * np.log10(pw + 1e-12)
    keep = pw[l_ > -70]
    rel = -0.691 + 10 * np.log10(keep.mean()) - 10
    return -0.691 + 10 * np.log10(pw[l_ > rel].mean())


mix = mix - mix.mean(0)
mix *= 10 ** ((-28.0 - lufs(mix)) / 20)
scale = 10 ** ((-28.0 - lufs(sum(stems.values()) - sum(stems.values()).mean(0))) / 20)
peak = np.max(np.abs(mix))
if peak > 10 ** (-1.05 / 20):
    raise SystemExit(f"peak too high {20 * np.log10(peak):.2f} dBFS")
d = np.random.default_rng(99)
pcm = np.clip(np.round(mix * 32767 + d.uniform(-0.5, 0.5, mix.shape) + d.uniform(-0.5, 0.5, mix.shape)), -32768, 32767).astype(np.int16)
with wave.open(os.path.join(HERE, "lab_artstyle.wav"), "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())

x = pcm / 32768.0
print(f"length {L / SR:.2f}s LUFS {lufs(x):.2f} peak {20 * np.log10(np.abs(x).max()):.2f} dBFS dc {x.mean(0).round(6)}")
up = sg.resample_poly(np.concatenate([x[-256:], x, x[:256]], 0), 4, 1, axis=0)
print(f"true peak ~ {20 * np.log10(np.abs(up).max()):.2f} dBTP  LR corr {np.corrcoef(x.T)[0, 1]:.2f}")
BANDS = [(20, 100), (100, 300), (300, 1000), (1000, 3000), (3000, 8000), (8000, 24000)]
for name, nb, sb in SECTIONS:
    a, b = SEC_START[name] * STEP, SEC_END[name] * STEP
    seg = x[a:b]
    spec = np.abs(np.fft.rfft(seg.mean(1)))**2
    fr = np.fft.rfftfreq(seg.shape[0], 1 / SR)
    rms = 20 * np.log10(np.sqrt(np.mean(seg**2)))
    print(f"{name} {a / SR:5.1f}-{b / SR:5.1f}s rms {rms:6.1f} |",
          " ".join(f"{10 * np.log10(spec[(fr >= l) & (fr < h)].sum() / spec.sum() + 1e-12):5.1f}" for l, h in BANDS))
print("stems rms dB in mix:", {k: round(float(20 * np.log10(np.sqrt(np.mean((v * scale)**2)) + 1e-9)), 1) for k, v in stems.items()},
      "peak:", {k: round(float(np.abs(v).max()), 2) for k, v in stems.items()})
dd = np.abs(np.diff(np.concatenate([x, x[:1]], 0), axis=0))
print(f"seam jump {dd[-1].max():.5f} median {np.median(dd):.5f} p99.9 {np.percentile(dd, 99.9):.5f}")
print(f"rms around seam: tail50ms {20 * np.log10(np.sqrt(np.mean(x[-2400:]**2))):.1f} head50ms {20 * np.log10(np.sqrt(np.mean(x[:2400]**2))):.1f}")
w5 = 5 * SR
print("lvl5s:", [round(float(20 * np.log10(np.sqrt(np.mean(x[i:i + w5]**2)) + 1e-9)), 1) for i in range(0, L - w5 + 1, w5)])

# ---- spectrogram PNG (no plotting library here) ------------------------------
f, t, S = sg.spectrogram(x.mean(1), SR, nperseg=4096, noverlap=4096 - 1200)
W, H = 1400, 620
freqs = np.geomspace(40, 20000, H)[::-1]
col = np.interp(np.linspace(0, S.shape[1] - 1, W), np.arange(S.shape[1]), np.arange(S.shape[1])).astype(int)
idx = np.searchsorted(f, freqs).clip(0, S.shape[0] - 1)
db = 10 * np.log10(S[np.ix_(idx, col)] + 1e-14)
v = np.clip((db + 115) / 70, 0, 1)
img = np.stack([np.clip(v * 2.2, 0, 1), np.clip(v * 2 - 0.7, 0, 1), np.clip(v * 3 - 2, 0, 1) + 0.25 * np.clip(1 - v * 2, 0, 1) * (v > 0.02)], 2)
for n_ in SEC_START:
    img[:, int(SEC_START[n_] * STEP / L * (W - 1))] = 1
env = 20 * np.log10(np.sqrt(np.mean(x.mean(1)[:(L // W) * W].reshape(W, -1)**2, 1)) + 1e-6)
strip = np.zeros((90, W, 3))
for c_, e_ in enumerate(env):
    strip[int(np.clip((-(e_ + 15)) * 1.6, 0, 89)):, c_] = (0.6, 0.7, 0.9)
img = np.concatenate([img, strip], 0)
raw = b"".join(b"\0" + (r * 255).astype(np.uint8).tobytes() for r in img)
def chunk(t_, b_):
    return struct.pack(">I", len(b_)) + t_ + b_ + struct.pack(">I", zlib.crc32(t_ + b_))
with open(os.path.join(HERE, "spectrogram.png"), "wb") as p_:
    p_.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H + 90, 8, 2, 0, 0, 0)) +
             chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))
