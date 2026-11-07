"""lab_artstyle_organic: the artstyle song played by hands. Run: py -3 build.py [--out DIR] [--evidence DIR]

Same subject as ../artstyle (white tile and raw flesh; a clear bell theme in D minor collapses
a semitone down, a pink lead follows), without its drive: no kick, snare, hats, arpeggio
grid or stepped wavetables. All sound comes from nkido. This script only (1) writes the
score into .akkado patches, (2) calls `nkido render` per stem, (3) folds each render's tail
onto its head, sets stem gains, normalises, (4) measures.

Voices
  porcelain bowl  the bell theme: struck bowl modes with split doublets, felt mallet
  felt piano      rolled chords, slow soft hammer, two strings a breath apart (mus_pause_alt)
  rim             a wet finger on a porcelain rim: the white tile's held D
  bowed           the pink lead (alto, then high and in thirds) and a cello under it;
                  it scoops up into notes and slides between them
  breath          a nose exhaling a chord, a short inhale before
  wet             drips that rise in pitch, a bubbling film, a few slow squelches
The collapse is one shared pitch curve: everything that sounds sags a semitone at once at
the end of B and stays there; it climbs back in the last beats, under the tails, for the loop.
Timing is jittered off the grid continuously and chords are rolled, as a hand plays them.
"""
import hashlib, os, struct, subprocess, sys, tempfile, wave, zlib
from concurrent.futures import ThreadPoolExecutor
import numpy as np
import scipy.signal as sg

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", ".."))
NKIDO = r"C:\projects\_tools\nkido\build-clang\bin\nkido.exe"


def arg(name, default):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


OUT = arg("--out", os.path.join(ROOT, "build", "music-lab"))
EVID = arg("--evidence", OUT)
STEMS = os.path.join(tempfile.gettempdir(), "lab_artstyle_organic_stems")

SR, STEP = 48000, 11100
BPM = 60 * SR / (STEP * 4)            # nkido: one cycle = one beat = four steps; ~64.9 bpm
SECTIONS = [("A", 64), ("B", 64), ("C", 128), ("D", 64), ("E", 48)]
SEC_START, s0 = {}, 0
for n_, ln in SECTIONS:
    SEC_START[n_] = s0
    s0 += ln
N_STEPS = s0                           # 368 steps, 85.1 s
TAIL_STEPS = 64
TOTAL = N_STEPS + TAIL_STEPS
CYCLES = TOTAL // 4
L = N_STEPS * STEP
A, B_, C, D, E = (SEC_START[k] for k in "ABCDE")
rng = np.random.default_rng(7)

# D minor world; bar = 16 steps. The last chord of four is split Eb -> A7(b9).
W1 = [(38, [57, 62, 64, 65, 69]), (34, [58, 62, 65, 69]), (41, [57, 60, 64, 65]),
      ((39, [58, 62, 67, 69]), (33, [55, 61, 64, 70]))]


def chord(bar, half):
    c = W1[bar % 4]
    if isinstance(c[0], tuple):
        c = c[half]
    return c


NAMES = ["c", "c#", "d", "d#", "e", "f", "f#", "g", "g#", "a", "a#", "b"]


def nm(m):
    m = int(round(m))
    return f"{NAMES[m % 12]}{m // 12 - 1}"


def pattern(events):
    """events: (start, dur, midi, vel) in steps -> one long n-pattern over the render."""
    ev = sorted(events, key=lambda e: e[0])
    if not ev:
        ev = [(0, 1, 60, 0.0)]
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


def values(fn, cell=1.0):
    out, cur, run, t = [], None, 0.0, 0.0
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


def smooth(t, pts, vals):
    """Piecewise cosine between points."""
    if t <= pts[0]:
        return vals[0]
    for (p0, v0), (p1, v1) in zip(zip(pts, vals), zip(pts[1:], vals[1:])):
        if t <= p1:
            u = (t - p0) / (p1 - p0)
            return v0 + (v1 - v0) * (0.5 - 0.5 * np.cos(np.pi * u))
    return vals[-1]


def bend(t):          # semitones; the collapse
    return smooth(t, [0, B_ + 46, B_ + 62, N_STEPS - 10, N_STEPS - 1], [0, 0, -1, -1, 0])


def flesh(t):         # 0 white tile room, 1 wet flesh room
    return smooth(t, [0, B_ + 40, C + 16, E + 16, N_STEPS], [0, 0, 1, 1, 0])


def wetness(t):       # density of drips and bubbling
    return smooth(t, [0, B_, B_ + 56, C + 40, D + 40, E + 24, N_STEPS], [0.05, 0.05, 0.25, 0.8, 1.0, 0.4, 0.05])


def hand(amt=0.12):   # a hand is never on the grid
    return float(rng.normal(0, amt))


V = {}


def add(k, *e):
    V.setdefault(k, []).append(e)


theme1 = [(0, 3, 74), (3, 3, 69), (6, 2, 76), (8, 4, 77), (12, 2, 76), (14, 2, 72),
          (16, 6, 74), (22, 2, 69), (24, 3, 70), (27, 3, 69), (30, 2, 67),
          (32, 3, 65), (35, 3, 69), (38, 2, 72), (40, 4, 76), (44, 2, 74), (46, 2, 69),
          (48, 6, 75), (54, 2, 74), (56, 8, 73)]
theme2 = [(0, 3, 74), (3, 3, 69), (6, 2, 76), (8, 4, 77), (12, 2, 79), (14, 2, 81),
          (16, 6, 82), (22, 2, 81), (24, 3, 79), (27, 3, 77), (30, 2, 76),
          (32, 3, 77), (35, 3, 76), (38, 2, 74), (40, 4, 72), (44, 2, 76), (46, 2, 79),
          (48, 6, 75), (54, 2, 74), (56, 4, 73), (60, 2, 76), (62, 2, 81)]

# ---- porcelain bell: the theme --------------------------------------------------
bk = 0


def bell(st, m, v):
    global bk
    add(["b0", "b1", "b2"][bk % 3], max(st, 0), 10, m, v * (0.85 + 0.3 * rng.random()))
    bk += 1


for s, d, m in theme1:                                  # A: the clear theme
    bell(A + s + hand(0.1), m, 0.8)
for s, d, m in theme2:                                  # B: again, higher; it sags at the end
    bell(B_ + s + hand(0.12), m, 0.7 - 0.15 * (s >= 44))
for s, d, m in theme1:                                  # C: the bell only answers, far up
    if s in (0, 8, 16, 32, 40, 48):
        bell(C + 64 + s + 6 + hand(0.2), m + 12, 0.3)
for s, d, m in theme2:                                  # D: a faint double of the lead
    bell(D + s + hand(0.12), m + 12, 0.22)
for bar, cnt, v in ((0, 6, 0.7), (1, 3, 0.5), (2, 2, 0.35)):   # E: fragments
    for s, d, m in theme1[:cnt]:
        bell(E + bar * 16 + s + hand(0.15), m, v)

# ---- felt piano: rolled chords ------------------------------------------------------
fk = 0


def felt(st, m, v):
    global fk
    add(f"f{fk % 8}", max(st, 0), 8, m, v)
    fk += 1


def roll(st, root, tones, v, spread=0.16):
    felt(st + hand(0.05), root + 12, v * 0.9)
    for k, m in enumerate(sorted(tones)):
        felt(st + 0.05 + k * spread * (0.7 + 0.6 * rng.random()), m - 12 if m > 66 else m, v * (0.45 + 0.2 * rng.random()))


for bar in range(N_STEPS // 16):
    st = bar * 16
    sec = "ABCDE"[sum(st >= SEC_START[k] for k in "BCDE")]
    if sec == "E" and st >= E + 32:
        felt(st + hand(0.1), chord(bar, 0)[0] + 12, 0.45)
        continue
    split = isinstance(W1[bar % 4][0], tuple)
    v = {"A": 0.55, "B": 0.6, "C": 0.65, "D": 0.75, "E": 0.5}[sec]
    for half in ((0, 1) if split else (0,)):
        root, tones = chord(bar, half)
        roll(st + 8 * half + hand(0.08), root, tones, v)
    if sec == "D":                                      # broken chord upward, rubato
        root, tones = chord(bar, 1 if split else 0)
        for k, m in enumerate(sorted(tones)[:4]):
            felt(st + (10 if split else 8) + k * (1.3 + 0.3 * rng.random()), m, 0.3)

# ---- bowed: pink lead and cello -------------------------------------------------------
lead_c = [(0, 12, 74), (12, 4, 69), (16, 12, 76), (28, 4, 77), (32, 8, 77), (40, 8, 76), (48, 8, 75), (56, 8, 74)]
lead_c += [(64 + s, d, m) for s, d, m in theme1]
for s, d, m in lead_c:                                  # C: alto, an octave down, warm
    add("lead", C + s + hand(0.15), d - 0.15, m - 12, 0.75 + 0.1 * rng.random())
SCALE = [2, 4, 5, 7, 9, 10, 0, 1]                        # D minor, with C# for the A chord


def third_below(m):
    for k in (3, 4):
        if (m - k) % 12 in SCALE:
            return m - k
    return m - 3


for s, d, m in theme2:                                  # D: high and too sweet, in thirds
    st = D + s + hand(0.12)
    add("lead", st, d - 0.15, m, 0.85)
    add("third", st + 0.1 + hand(0.05), d - 0.15, third_below(m), 0.55)
cello = [(B_, 32, 50), (B_ + 32, 16, 49), (B_ + 48, 8, 50), (B_ + 56, 24, 49)]
for bar in range(C // 16 + 1, D // 16 + 4):
    root = chord(bar, 0)[0]
    cello.append((bar * 16, 15.6, root + 12))
cello += [(E + 16, 16, 45), (E + 32, 14, 50)]
for st, d, m in cello:
    add("cello", st + hand(0.1), d - 0.2, m, 0.6)
for bar in range(B_ // 16 + 2, E // 16 + 2):            # held chord under the lead
    _, tones = chord(bar, 0)
    for i, m in enumerate(sorted(tones)[:4]):
        add(f"q{i}", bar * 16 + hand(0.1), 15.8, m, 0.5)

for k in ("lead", "third", "cello", "q0", "q1", "q2", "q3"):    # slides start from the first note, not from 0
    first = min(V[k])
    V[k].insert(0, (0.0, 0.2, first[2], 0.0))

# ---- rim: white tile's held D ------------------------------------------------------
for st, d, v in ((A + 4, 28, 0.5), (A + 36, 26, 0.45), (B_ + 8, 52, 0.5), (E + 2, 40, 0.4)):
    add("rim", st, d, 62, v)

# ---- breath: a nose exhaling the chord, an inhale before --------------------------
for bar in range(C // 16, E // 16 + 1, 2):
    root, tones = chord(bar, 0)
    st = bar * 16 + 2 + hand(0.3)
    for i, m in enumerate(sorted(tones)[1:4]):
        add(f"x{i}", st, 10, m, 0.7)
        add(f"n{i}", st - 6, 5.5, m, 0.5)

# ---- wet: drips, squelches --------------------------------------------------------
t = 0.0
while t < N_STEPS - 4:
    t += rng.exponential(1.0 / (0.015 + 0.13 * wetness(t)))
    if t < N_STEPS - 4:
        add(["d0", "d1"][int(t * 7) % 2], t, 1, int(rng.integers(79, 94)), 0.4 + 0.5 * rng.random())
for st in (C + 22, C + 57, C + 90, C + 117, D + 13, D + 41, D + 59):
    add("sq", st + hand(1.0), 4, 40, 0.6 + 0.3 * rng.random())

BEND = values(bend, 0.5)
FLESH = values(flesh, 1.0)
WET = values(wetness, 2.0)
HEAD = f"""// generated by build.py; loop {N_STEPS} steps + tail {TAIL_STEPS}
sag = pow(2, slew({BEND}, 2.5) / 12)
fl = slew({FLESH}, 0.4)
"""
ROOM = """
tile = dry * 0.35 |> freeverb(@, 0.5, 0.15) |> hp(@, 300)
meat = dry * 0.5 |> freeverb(@, 0.82, 0.75) |> lp(@, 1600)
"""


def room(gain, hpf=60):
    return ROOM + f"dry + tile * (1 - fl) * 0.9 + meat * fl |> hp(@, {hpf}) |> @ * {gain} |> out(@)\n"


def bells():
    tx = HEAD + """
fn bowl(f, g, v) -> {
  a = (sine(f) + 0.55 * sine(f * 1.0021)) * ar(g, 0.002, 2.6) ^ 2
  b = (0.3 * sine(f * 2.76) + 0.17 * sine(f * 2.771)) * ar(g, 0.0015, 1.2) ^ 2
  c = (0.12 * sine(f * 5.4) + 0.05 * sine(f * 8.93)) * ar(g, 0.001, 0.4) ^ 2
  mal = (noise(0, 0, 31) |> bp(@, 900, 0.7)) * ar(g, 0.001, 0.012) ^ 2 * 0.2
  (a + b + c + mal) * v
}
"""
    for k in ("b0", "b1", "b2"):
        tx += f"{pattern(V[k])} as {k}\n"
    tx += """
x0 = bowl(b0.freq * sag, b0.trig, b0.vel)
x1 = bowl(b1.freq * sag, b1.trig, b1.vel)
x2 = bowl(b2.freq * sag, b2.trig, b2.vel)
dry = pan(x0, -0.35) + x1 + pan(x2, 0.35) |> lp(@, 5200)
""" + room(0.22, 150)
    return tx


def piano():
    tx = HEAD + """
fn felt(f, g, v) -> {
  body = (sine(f * 0.9993) + sine(f * 1.0007)) * 0.5 * ar(g, 0.024, 6.0)
  second = sine(f * 2.002) * 0.3 * ar(g, 0.024, 3.0)
  third = sine(f * 3.006) * 0.08 * ar(g, 0.03, 1.4)
  thump = (noise(0, 0, 41) |> lp(@, 300)) * ar(g, 0.002, 0.03) ^ 2 * 0.3
  (body + second + third + thump) * v
}
"""
    terms = []
    for i in range(8):
        tx += f"{pattern(V.get(f'f{i}', []))} as f{i}\n"
        terms.append(f"pan(felt(f{i}.freq * sag, f{i}.trig, f{i}.vel), {(-0.4 + 0.8 * i / 7):.2f})")
    tx += "dry = " + " + ".join(terms) + " |> lp(@, 2400)\n" + room(0.16, 70)
    return tx


BOW = """
fn bowbody(x) -> bp(x, 380, 1.1) * 1.2 + bp(x, 1050, 1.4) * 0.7 + bp(x, 2700, 2.2) * 0.25 + x * 0.25
"""


def bowed_voice(name, rate, vib, hi):
    return f"""
nt{name} = slew({name}.note, {rate})
vb{name} = sine({4.9 + 0.13 * len(name):.2f}) * {vib} * adsr({name}.gate, 0.7, 0.1, 1, 0.3)
sc{name} = (1 - adsr({name}.gate, 0.16, 0.01, 1, 0.2)) * 0.6
dr{name} = mono(noise(0, 0, {len(name) * 17 + 3}) |> lp(@, 2.5)) * 2.5
fr{name} = mtof(nt{name} + vb{name} - sc{name} + dr{name} * 0.12) * sag
pr{name} = mono(noise(0, 0, {len(name) * 19 + 1}) |> lp(@, 40)) * 4
grip{name} = 1 + pr{name} * 0.18
ha{name} = sine(fr{name}) + sine(fr{name} * 2) * 0.5 + sine(fr{name} * 3) * 0.33 + sine(fr{name} * 4) * 0.22 + sine(fr{name} * 5) * 0.14 + sine(fr{name} * 6) * 0.08 + sine(fr{name} * 7) * 0.05
sw{name} = ha{name} * grip{name} |> lp(@, fr{name} * {hi} + 300)
hair{name} = (noise(0, 0, {len(name) * 13 + 5}) |> bp(@, fr{name} * 2.5, 1.5)) * 0.22 * (0.6 + 0.4 * grip{name})
v{name} = bowbody(sw{name} + hair{name}) * adsr({name}.gate, 0.22, 0.4, 0.85, 0.45) * {name}.vel
"""


def lead():
    tx = HEAD + BOW
    for k in ("lead", "third"):
        tx += f"{pattern(V[k])} as {k}\n" + bowed_voice(k, 9, 0.16, 3.2)
    tx += """
br = (noise(0, 0, 77) |> bp(@, mtof(ntlead) * sag * 3, 3)) * adsr(lead.gate, 0.3, 0.3, 0.6, 0.4) * lead.vel * 0.18
dry = pan(vlead + br, -0.1) + pan(vthird, 0.35) * 0.8
""" + room(0.2, 110)
    return tx


def strings():
    tx = HEAD + BOW
    for k in ("cello", "q0", "q1", "q2", "q3"):
        tx += f"{pattern(V[k])} as {k}\n" + bowed_voice(k, 3, 0.1, 2.2)
    tx += """
quiet = (vq0 + vq2) * 0.5 |> pan(@, -0.5)
quiet2 = (vq1 + vq3) * 0.5 |> pan(@, 0.5)
dry = vcello * 1.2 + (quiet + quiet2) * 0.45 |> lp(@, 1800)
""" + room(0.16, 45)
    return tx


def rim():
    tx = HEAD + f"""
{pattern(V["rim"])} as r
fn rimv(f, g, v) -> {{
  e = adsr(g, 0.9, 0.1, 0.9, 1.2)
  sl = ar(g, 0.0002, 0.12)
  fr = f * (1 - 0.03 * sl * sl + 0.0028 * sine(4.3))
  tone = sine(fr) + 0.55 * sine(fr * 1.0034) + 0.15 * sine(fr * 2) + 0.05 * sine(fr * 3) + 0.03 * sine(fr * 2.76)
  rough = (noise(0, 0, 22) |> lp(@, 30)) * 3
  chat = 1 + rough * (0.08 + 0.5 * sl)
  fric = (noise(0, 0, 23) |> bp(@, 2500, 1.2)) * 0.05
  (tone * chat * e + fric * e) * v
}}
dry = rimv(r.freq * sag, r.gate, r.vel) |> pan(@, 0.2)
""" + room(0.14, 120)
    return tx


def breath():
    tx = HEAD + """
fn exhale(f, g, v) -> (noise(0, 0, 81) |> bp(@, f, 14)) * ar(g, 0.35, 3.8) ^ 2 * 4 * v
fn inhale(f, g, v) -> (noise(0, 0, 82) |> bp(@, f * 2, 8)) * ar(g, 1.1, 0.06) ^ 2 * 2 * v
fn air(g, v) -> (noise(0, 0, 83) |> bp(@, 1300, 0.7)) * ar(g, 0.35, 3.0) ^ 2 * 0.5 * v
"""
    terms = []
    for i in range(3):
        tx += f"{pattern(V[f'x{i}'])} as x{i}\n{pattern(V[f'n{i}'])} as n{i}\n"
        terms.append(f"exhale(x{i}.freq * sag, x{i}.trig, x{i}.vel) + inhale(n{i}.freq * sag, n{i}.trig, n{i}.vel)")
    tx += "mid = " + " + ".join(terms) + " + air(x0.trig, x0.vel)\n"
    tx += "dry = pan(mid, -0.2) |> hp(@, 200)\n" + room(0.14, 150)
    return tx


def wet():
    tx = HEAD + f"""
wd = slew({WET}, 0.3)
fn bub(lo, hi, th, seed) -> {{
  p = noise(0, 0, seed) > th
  r = sah(noise(0, 0, seed + 1) * 0.5 + 0.5, p)
  fc = lo * (hi / lo) ^ r
  (p |> bp(@, fc, 13)) * 11
}}
fn drip(f, g, v) -> sine(f * (1.6 - 0.9 * ar(g, 0.0003, 0.03)), 0, g) * ar(g, 0.0008, 0.06) ^ 2 * v
fn squelch(g, v) -> (noise(0, 0, 91) |> lp(@, 250 + 1400 * ar(g, 0.05, 0.25), 4)) * ar(g, 0.06, 0.4) ^ 2 * v * 0.8
"""
    for k in ("d0", "d1", "sq"):
        tx += f"{pattern(V[k])} as {k}\n"
    tx += """
film = (bub(300, 1400, 0.9993, 51) + bub(500, 2200, 0.9995, 53) * 0.7) * wd * 0.05
dry = pan(drip(d0.freq, d0.trig, d0.vel), -0.5) + pan(drip(d1.freq, d1.trig, d1.vel), 0.45) + pan(film, 0.1) + squelch(sq.trig, sq.vel)
""" + room(0.12, 120)
    return tx


PATCHES = dict(bell=bells, piano=piano, lead=lead, strings=strings, rim=rim, breath=breath, wet=wet)
GAIN = dict(bell=2.8, piano=2.8, lead=0.75, strings=0.55, rim=1.2, breath=0.35, wet=6.0)


def render(name):
    src = PATCHES[name]()
    path = os.path.join(HERE, f"{name}.akkado")
    h = hashlib.sha1(src.encode()).hexdigest()[:12]
    wav = os.path.join(STEMS, f"{name}.{h}.wav")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(src)
    if not os.path.exists(wav):
        secs = TOTAL * STEP / SR
        r = subprocess.run([NKIDO, "render", path, "-o", wav, "--seconds", f"{secs:.3f}", "--rate", str(SR),
                            "--bpm", f"{BPM:.6f}", "--no-default-bank", "--float32"], capture_output=True, text=True)
        if r.returncode or not os.path.exists(wav):
            raise SystemExit(f"nkido failed on {name}:\n{r.stdout[-2500:]}\n{r.stderr[-2500:]}")
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
    t_ = x[L:]
    y[:t_.shape[0]] += t_
    return y


def lufs(x):
    pre = np.array([[1.53512485958697, -2.69169618940638, 1.19839281085285, 1, -1.69065929318241, 0.73248077421585],
                    [1, -2, 1, 1, -1.99004745483398, 0.99007225036621]])
    n = x.shape[0]
    y = sg.sosfilt(pre, np.concatenate([x, x], 0), axis=0)[n:]
    bl, hop = int(0.4 * SR), int(0.1 * SR)
    p = np.sum(y**2, 1)
    cs = np.concatenate([[0], np.cumsum(np.concatenate([p, p[:bl]]))])
    pw = (cs[bl:] - cs[:-bl])[::hop][: n // hop] / bl
    l_ = -0.691 + 10 * np.log10(pw + 1e-12)
    rel = -0.691 + 10 * np.log10(pw[l_ > -70].mean()) - 10
    return -0.691 + 10 * np.log10(pw[l_ > rel].mean())


if __name__ == "__main__":
    os.makedirs(STEMS, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(EVID, exist_ok=True)
    with ThreadPoolExecutor(4) as ex:
        paths = dict(ex.map(render, PATCHES))
    stems = {k: fold(read_float(p)) * GAIN[k] for k, p in paths.items()}
    mix = sum(stems.values())
    mix = mix - mix.mean(0)
    scale = 10 ** ((-28.0 - lufs(mix)) / 20)
    mix *= scale
    peak = np.max(np.abs(mix))
    if peak > 10 ** (-1.05 / 20):
        raise SystemExit(f"peak too high {20 * np.log10(peak):.2f} dBFS")
    d = np.random.default_rng(99)
    pcm = np.clip(np.round(mix * 32767 + d.uniform(-0.5, 0.5, mix.shape) + d.uniform(-0.5, 0.5, mix.shape)),
                  -32768, 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, "lab_artstyle_organic.wav"), "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())

    x = pcm / 32768.0
    print(f"length {L / SR:.2f}s LUFS {lufs(x):.2f} peak {20 * np.log10(np.abs(x).max()):.2f} dBFS")
    up = sg.resample_poly(np.concatenate([x[-256:], x, x[:256]], 0), 4, 1, axis=0)
    print(f"true peak ~ {20 * np.log10(np.abs(up).max()):.2f} dBTP  LR corr {np.corrcoef(x.T)[0, 1]:.2f}")
    BANDS = [(20, 100), (100, 300), (300, 1000), (1000, 3000), (3000, 8000), (8000, 24000)]
    for name, ln in SECTIONS:
        a, b = SEC_START[name] * STEP, (SEC_START[name] + ln) * STEP
        seg = x[a:b]
        spec = np.abs(np.fft.rfft(seg.mean(1)))**2
        fr = np.fft.rfftfreq(seg.shape[0], 1 / SR)
        print(f"{name} {a / SR:5.1f}-{b / SR:5.1f}s rms {20 * np.log10(np.sqrt(np.mean(seg**2))):6.1f} |",
              " ".join(f"{10 * np.log10(spec[(fr >= l) & (fr < h)].sum() / spec.sum() + 1e-12):5.1f}" for l, h in BANDS))
    print("stems rms dB in mix:", {k: round(float(20 * np.log10(np.sqrt(np.mean((v * scale)**2)) + 1e-9)), 1)
                                   for k, v in stems.items()})
    print("stems below 100 Hz, dB, per section:")
    lo = sg.butter(4, 100 / (SR / 2), output="sos")
    for k, v_ in stems.items():
        y_ = sg.sosfilt(lo, (v_ * scale).mean(1))
        print(f"  {k:8s}", " ".join(f"{20 * np.log10(np.sqrt(np.mean(y_[SEC_START[n] * STEP:(SEC_START[n] + ln) * STEP]**2)) + 1e-9):6.1f}"
                                   for n, ln in SECTIONS))
    dd = np.abs(np.diff(np.concatenate([x, x[:1]], 0), axis=0))
    print(f"seam jump {dd[-1].max():.5f} median {np.median(dd):.5f} p99.9 {np.percentile(dd, 99.9):.5f}")
    w5 = 5 * SR
    print("lvl5s:", [round(float(20 * np.log10(np.sqrt(np.mean(x[i:i + w5]**2)) + 1e-9)), 1) for i in range(0, L - w5 + 1, w5)])

    f, t_, S = sg.spectrogram(x.mean(1), SR, nperseg=4096, noverlap=4096 - 1200)
    W, H = 1400, 620
    freqs = np.geomspace(40, 20000, H)[::-1]
    col = np.linspace(0, S.shape[1] - 1, W).astype(int)
    idx = np.searchsorted(f, freqs).clip(0, S.shape[0] - 1)
    db = 10 * np.log10(S[np.ix_(idx, col)] + 1e-14)
    v = np.clip((db + 115) / 70, 0, 1)
    img = np.stack([np.clip(v * 2.2, 0, 1), np.clip(v * 2 - 0.7, 0, 1),
                    np.clip(v * 3 - 2, 0, 1) + 0.25 * np.clip(1 - v * 2, 0, 1) * (v > 0.02)], 2)
    for n_ in SEC_START:
        img[:, int(SEC_START[n_] * STEP / L * (W - 1))] = 1
    env = 20 * np.log10(np.sqrt(np.mean(x.mean(1)[:(L // W) * W].reshape(W, -1)**2, 1)) + 1e-6)
    strip = np.zeros((90, W, 3))
    for c_, e_ in enumerate(env):
        strip[int(np.clip((-(e_ + 15)) * 1.6, 0, 89)):, c_] = (0.6, 0.7, 0.9)
    img = np.clip(np.concatenate([img, strip], 0), 0, 1)
    raw = b"".join(b"\0" + (r * 255).astype(np.uint8).tobytes() for r in img)

    def chunk(t_, b_):
        return struct.pack(">I", len(b_)) + t_ + b_ + struct.pack(">I", zlib.crc32(t_ + b_))
    with open(os.path.join(EVID, "lab_artstyle_organic_spectrogram.png"), "wb") as p_:
        p_.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H + 90, 8, 2, 0, 0, 0)) +
                 chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))
