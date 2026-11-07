#!/usr/bin/env python3
"""cycle: four rounds of tear / chew / swallow / purge, rendered by nkido.

All sound comes from cycle.akkado. This script only
  1. writes the score into that patch as per-step value patterns,
  2. calls nkido to render it,
  3. folds the tail past the loop end onto the head and sets the level,
  4. measures the result and draws a spectrogram PNG.

Form. Roots climb a chain of minor thirds, D F Ab B, so the fourth purge can
fall back onto the D the piece opens on. Every section grows each round and the
chew changes meter (16, 18, 14+18, then 22-based bars).

Clock. nkido runs one cycle per beat, so the patch runs at 576 BPM: each cycle
is one sixteenth of 144 BPM, exactly 5000 samples, and a top-level pattern token
is one step. The score is padded with PRE rest steps (the first trigger at time
zero needs a settled clock) and POST rest steps (room for the tails to ring out silently,
which is what gets folded).

Run: py -3 build.py
"""
import os
import re
import struct
import subprocess
import sys
import zlib

import numpy as np
from scipy import signal
from scipy.io import wavfile

HERE = os.path.dirname(os.path.abspath(__file__))
NKIDO = r'C:\projects\_tools\nkido\build-clang\bin\nkido.exe'
SR = 48000
BPM = 576
STEP = 5000
PRE, POST = 8, 40
TARGET_LUFS = -28.0
PEAK_LIMIT_DB = -1.0
D2 = 38

CYCLES = [
    dict(root=0, strange=0.0, tear=[16, 16], hits=[0, 3, 6, 8, 11, 14],
         chew=[16, 16, 16, 16], swallow=[16, 16], purge=32, fall=7,
         lead=[(7, 6), (8, 2), (4, 8), (12, 16)],
         chord=[0, 7, 12, 16], seq=[0, 0, 1, 0, 0, -2], ratio=2.0),
    dict(root=3, strange=0.25, tear=[16, 16, 8], hits=[0, 3, 6, 8, 11, 13, 14],
         chew=[18, 18, 18, 18], swallow=[16, 16, 16], purge=48, fall=12,
         lead=[(7, 6), (8, 2), (4, 8), (12, 10), (11, 2), (7, 4), (16, 16)],
         chord=[0, 7, 12, 16, 19], seq=[0, 1, 0, 3, 0, 1, -2], ratio=2.0),
    dict(root=6, strange=0.6, tear=[16, 16, 16], hits=[0, 3, 6, 9, 12, 14],
         chew=[14, 18, 14, 18, 14, 18], swallow=[16, 16, 16, 8], purge=64, fall=17,
         lead=[(7, 6), (8, 2), (4, 8), (12, 10), (14, 2), (13, 4), (8, 8), (16, 8), (19, 16)],
         chord=[0, 7, 12, 16, 19, 24], seq=[0, 1, 3, 1, 6, 0, 1, -2], ratio=1.41),
    dict(root=9, strange=1.0, tear=[16, 16, 16, 10], hits=[0, 2, 5, 8, 10, 13],
         chew=[22, 22, 18, 22, 22, 14], swallow=[16, 16, 16, 16, 8], purge=96, fall=33,
         lead=[(7, 6), (8, 2), (4, 8), (12, 10), (14, 2), (13, 4), (8, 8), (16, 8),
               (19, 6), (20, 2), (15, 8), (24, 32)],
         chord=[0, 7, 12, 16, 19, 24, 28], seq=[0, 1, 6, 3, 1, 8, 0, 1, -2], ratio=1.27),
]
BAR_FORMS = {  # bar length -> (kick spacing, riff grouping)
    16: ([4, 4, 4, 4], [3, 3, 2, 3, 3, 2]),
    18: ([4, 4, 4, 4, 2], [3, 3, 2, 3, 3, 2, 2]),
    14: ([4, 4, 3, 3], [3, 3, 2, 3, 3]),
    22: ([4, 4, 3, 4, 4, 3], [3, 3, 2, 3, 3, 3, 3, 2]),
}
TOTAL = sum(sum(c['tear']) + sum(c['chew']) + sum(c['swallow']) + c['purge'] for c in CYCLES)
LOOP = TOTAL * STEP
VOICES = 7
STEMS = dict(drums=2.0, perc=8.0, gnaw=7.0, bass=1.0, chord=8.0, lead=-9.0)   # trim dB

TRIGGERS = ('kick', 'kickbig', 'snare', 'snarebig', 'hat', 'ohat', 'tom', 'tooth', 'rip',
            'crash', 'bass', 'mid', 'lead', 'tear')
HELD = dict(toothp=70.0, toothr=2.0, toothpan=0.0, ripp=74.0, tomp=60.0,
            bassp=float(D2), basscut=240.0, basstop=1500.0, bassdec=0.09, basshold=0.0,
            basslvl=0.0, midcut=700.0, midtop=1500.0, middec=0.1, midhold=0.0, midlvl=0.0,
            ring=0.0, fall=0.0, bassfall=0.0, leadp=74.0, leadlvl=0.0, leadsub=0.0,
            risef=800.0, riselvl=0.0, heft=0.6)
S = {k: ['~'] * TOTAL for k in TRIGGERS}
C = {k: [None] * TOTAL for k in HELD}
VP = [[None] * TOTAL for _ in range(VOICES)]
VM = [[None] * TOTAL for _ in range(VOICES)]


def trig(name, step, value=1.0):
    S[name][step] = value if isinstance(value, str) else f'{value:.3g}'


def held(name, a, b, value):
    for i in range(a, min(b, TOTAL)):
        C[name][i] = value


def voices(a, b, pitches, masks):
    """Set chord voices from step a to b; voices not named fall silent."""
    for j in range(VOICES):
        p = pitches[j] if j < len(pitches) else None
        m = masks[j] if j < len(masks) else 0.0
        for i in range(a, min(b, TOTAL)):
            if p is not None:
                VP[j][i] = p
            VM[j][i] = m


def tear(c, at, rng):
    r = c['root']
    pos = at
    held('basslvl', at, at + sum(c['tear']), 0.9)
    held('midlvl', at, at + sum(c['tear']), 1.0)
    held('basscut', at, at + sum(c['tear']), 420.0)
    held('basstop', at, at + sum(c['tear']), 3000.0)
    held('bassdec', at, at + sum(c['tear']), 0.13)
    held('midcut', at, at + sum(c['tear']), 700.0)
    held('midtop', at, at + sum(c['tear']), 4300.0)
    held('middec', at, at + sum(c['tear']), 0.12)
    for b, blen in enumerate(c['tear']):
        hits = [h for h in c['hits'] if h < blen]
        for i, h in enumerate(hits):
            s = pos + h
            gap = (hits[i + 1] if i + 1 < len(hits) else blen) - h
            semi = D2 + r + [0, 0, 1, 0, 7, 0, 1][i % 7] * (i % 3 != 0 or b % 2 == 1)
            vel = 1.0 if i == 0 else 0.82
            trig('kick', s, 0.95 * vel)
            trig('tear', s)
            trig('bass', s, vel)
            trig('mid', s, vel)
            trig('rip', s, 0.75 * vel)
            held('bassp', s, s + gap, semi)
            held('ripp', s, s + gap, semi + 24)
            voices(s, s + gap, [semi + 12, semi + 19, semi + 25 + c['strange']], [0.85, 0.6, 0.45])
        pos += blen
    for off, v in ((-2, 0.45), (-1, 0.75)):
        trig('snare', pos + off, v)
    return pos


def chew(c, at, rng, ci):
    r = c['root']
    pos = at
    total = sum(c['chew'])
    seq, seq_i = c['seq'], 0
    held('basslvl', at, at + total, 0.82)
    held('bassdec', at, at + total, 0.085)
    held('midlvl', at, at + total, 0.8)
    held('middec', at, at + total, 0.07)
    held('toothr', at, at + total + sum(c['swallow']), c['ratio'])
    held('midtop', at, at + total, 900.0)
    for b, blen in enumerate(c['chew']):
        kicks, groups = BAR_FORMS[blen]
        prog = (pos - at) / total
        k = 0
        for i, d in enumerate(kicks):
            trig('kick', pos + k, 0.9)
            if i % 2 == 1:
                trig('snare', pos + k, 0.7)
            k += d
        k = 0
        for g in groups:
            a = seq[seq_i % len(seq)]
            seq_i += 1
            cell = [a, 0, 12] if g == 3 else [a, 12]
            for i, off in enumerate(cell):
                s = pos + k + i
                top = (1500 if i == 0 else 750) + 1400 * prog + 700 * ci
                trig('bass', s, (1.0 if i == 0 else 0.68) * (0.95 + 0.1 * rng.random()))
                held('bassp', s, s + 1, D2 + r + off)
                held('basstop', s, s + 1, top)
                held('basscut', s, s + 1, 240.0)
            deg = [12, 15, 19, 20, 24, 27, 31][(seq_i + int(prog * 5)) % 7]
            trig('tooth', pos + k, 0.5)
            held('toothp', pos + k, pos + k + g,
                 D2 + r + deg + 12 + 0.5 * (c['strange'] > 0.5) * (seq_i % 3 == 0))
            held('toothpan', pos + k, pos + k + g, -0.45 if seq_i % 2 else 0.45)
            k += g
        for i in range(blen):
            if ci >= 1 or prog >= 0.5:
                trig('hat', pos + i, 0.5 if i % 4 == 2 else 0.24)
            if ci >= 2 and (i * 3) % 7 == 0:
                trig('ohat', pos + i, 0.42)
            if ci == 3 and i % 5 == 0:
                trig('tom', pos + i, 0.5)
                held('tomp', pos + i, pos + i + 5, D2 + r + 19 + 1.5 * (i % 2) + 12)
        n = 2 + int(prog * (len(c['chord']) - 1))
        vs = [D2 + r + 12 + (3 if v == 16 else v) + 0.05 * j for j, v in enumerate(c['chord'][:n])]
        voices(pos, pos + blen, vs, [0.4] * n)
        held('midcut', pos, pos + blen, 500 + 2200 * prog)
        if ci >= 1 or prog >= 0.25:
            for i in range(2, blen, 4):
                trig('mid', pos + i, 0.9)
        pos += blen
    return pos


def swallow(c, at, rng, ci):
    r = c['root']
    pos = at
    total = sum(c['swallow'])
    down = [0, -1, -3, -5, -7]
    wedge = [12, 15, 19, 20, 24, 27, 31]
    held('basslvl', at, at + total, 0.82)
    held('bassdec', at, at + total, 0.13)
    held('midlvl', at, at + total, 1.0)
    held('middec', at, at + total, 0.1)
    held('midtop', at, at + total, 2500.0)
    for b, blen in enumerate(c['swallow']):
        last = b == len(c['swallow']) - 1
        semi = D2 + r + down[b]
        for i in range(0, blen, 2):
            s = pos + i
            prog = (s - at) / total
            if last and i >= blen - 2:
                continue                     # the held breath before the purge
            gulp = -4.0 if i >= blen - 2 else 0.0
            trig('bass', s, 0.8 + 0.2 * prog)
            held('bassp', s, s + 2, semi + gulp)
            held('basscut', s, s + 2, 300 + 900 * prog)
            held('basstop', s, s + 2, 1200 + 2400 * prog)
            rungs = min(VOICES, 2 + int(prog * (VOICES - 2) * (0.6 + 0.13 * ci) + 0.5))
            ps = []
            for j, v in enumerate(wedge[:rungs]):
                up = int(prog * 6) if j == rungs - 1 else 0
                ps.append(D2 + r + 12 + v + up + 0.06 * (j % 3 - 1) + 0.25 * c['strange'] * (j % 2))
            voices(s, s + 2, ps, [0.34] * rungs)
            trig('mid', s, 0.9)
            held('midcut', s, s + 2, 700 + 9000 * prog ** 1.6)
            trig('tooth', s, 0.36)
            held('toothp', s, s + 2, D2 + r + 24 + wedge[min(rungs, 6)])
            held('toothpan', s, s + 2, 0.3)
        spacing = 4 if not last else 2
        hold = 2 if last else 0
        for i in range(0, blen - hold, spacing):
            trig('kick', pos + i, 0.9)
        for i in range(blen - hold):
            prog = (pos + i - at) / total
            if last and i >= blen - hold - 4:
                trig('snare', pos + i, '[0.5 0.6]')
            elif prog > 0.5 or i % 4 == 2:
                trig('snare', pos + i, 0.2 + 0.55 * prog ** 2)
            held('risef', pos + i, pos + i + 1, 600 + 8000 * prog ** 2)
            held('riselvl', pos + i, pos + i + 1, 0.04 + 0.4 * prog ** 2)
        if last:
            for k in ('basslvl', 'midlvl'):
                held(k, pos + blen - 2, pos + blen, 0.0)
            held('riselvl', pos + blen - 2, pos + blen, 0.0)
        pos += blen
    return pos


def purge(c, at, ci):
    r = c['root']
    n = c['purge']
    start_fall = {0: 0.70, 1: 0.70, 2: 0.66, 3: 0.56}[ci]
    held('basscut', at, at + n, 300.0)
    held('bassdec', at, at + n, 0.14)
    held('middec', at, at + n, 0.12)
    held('midtop', at, at + n, 1200.0)
    held('bassp', at, at + n, D2 + r)
    held('leadsub', at, at + n, 0.5 if ci >= 2 else 0.0)
    held('ring', at, at + n, [0.0, 0.0, 0.2, 0.5][ci])
    for i in range(n):
        x = i / n
        f = max(0.0, (x - start_fall) / (1 - start_fall)) ** 2.1
        fade = 1.0 - (0.45 if ci == 3 else 0.75) * max(0.0, (x - 0.82) / 0.18) ** 2
        s = at + i
        held('fall', s, s + 1, f * c['fall'])
        held('bassfall', s, s + 1, f * (9 if ci == 3 else c['fall']))
        held('basstop', s, s + 1, 300 + 1500 * np.exp(-x * 3))
        held('basslvl', s, s + 1, 0.8 * fade)
        held('basshold', s, s + 1, 0.62)
        held('midhold', s, s + 1, 0.62)
        held('midlvl', s, s + 1, fade)
        held('midcut', s, s + 1, 1100 + 8000 * np.exp(-x * 3.0) + 500 * ci)
        held('leadlvl', s, s + 1, fade)
        if i % 2 == 0:
            trig('bass', s, 1.0)
            trig('mid', s, 1.0)
        ps = [D2 + r + 12 + v + c['strange'] * 0.34 * (j % 3 - 1) * min(x * 2, 1)
              for j, v in enumerate(c['chord'])]
        voices(s, s + 1, ps, [0.34] * len(c['chord']))
    pos = at
    for semi, d in c['lead']:
        held('leadp', pos, min(pos + d, at + n), D2 + r + 24 + semi)
        trig('lead', pos)
        pos += d
    held('leadp', pos, at + n, D2 + r + 24 + c['lead'][-1][0])
    trig('kickbig', at, 1.0)
    trig('crash', at, 0.55)
    trig('snarebig', at, 1.0)
    for i in range(8, int(n * start_fall) + 8, 8):
        if i < n:
            trig('kick', at + i, 0.9)
            if i % 16 == 8:
                trig('snare', at + i, 0.7)
    for i in range(2, n, 4):
        trig('ohat', at + i, 0.42)
    return at + n


def compose():
    rng = np.random.default_rng(20261104)
    pos, marks = 0, []
    for ci, c in enumerate(CYCLES):
        marks.append((f'{ci + 1} tear', pos))
        pos = tear(c, pos, rng)
        marks.append((f'{ci + 1} chew', pos))
        pos = chew(c, pos, rng, ci)
        marks.append((f'{ci + 1} swallow', pos))
        pos = swallow(c, pos, rng, ci)
        marks.append((f'{ci + 1} purge', pos))
        pos = purge(c, pos, ci)
    assert pos == TOTAL
    shape_arc(marks)
    return marks


def shape_arc(marks):
    """The long shape: each round louder, each swallow a climb, each purge the top."""
    pts = [p for _, p in marks] + [TOTAL]
    for (name, a), b in zip(marks, pts[1:]):
        ci = int(name[0]) - 1
        base = [0.6, 0.72, 0.86, 1.0][ci]
        for i in range(a, b):
            x = (i - a) / (b - a)
            if name.endswith('tear'):
                v = 0.9 * base
            elif name.endswith('chew'):
                v = base * (0.78 + 0.22 * x)
            elif name.endswith('swallow'):
                v = base * (0.72 + 0.6 * x ** 1.5)
            else:
                v = 1.15 * base
            C['heft'][i] = v


# ---------------------------------------------------------------- the patch
def fmt(v):
    return ('%.3f' % v).rstrip('0').rstrip('.')


def line_trig(name):
    # e.trig drops every 16th cycle here, so a trigger is a pulse written into
    # the value itself: gateup() sees it on every step, and sah() keeps its height.
    def tok(v):
        if v == '~':
            return '0'
        return '[' + ' '.join(f'{p} 0' for p in v.strip('[]').split()) + ']'
    return f'{name}_p = v"' + ' '.join(['0'] * PRE + [tok(v) for v in S[name]] + ['0'] * POST) + '"'


def line_held(name, values, default, silent=None):
    """Carry each value forward; the padding holds the default so nothing moves."""
    out, cur = [], default
    for v in values:
        cur = cur if v is None else v
        out.append(fmt(cur))
    tail = fmt(default if silent is None else silent)
    return f'{name} = v"' + ' '.join([fmt(default)] * PRE + out + [tail] * POST) + '"'


def clear_sections():
    """Levels that only mean something inside one section must drop outside it."""
    for name in ('basshold', 'midhold', 'leadlvl', 'riselvl', 'ring', 'fall', 'bassfall',
                 'leadsub'):
        C[name] = [0.0 if v is None else v for v in C[name]]


def voice_sections():
    text = open(os.path.join(HERE, 'voices.akkado'), encoding='utf-8').read()
    parts = re.split(r'^//@ (\w+)\n', text, flags=re.M)
    return dict(zip(parts[1::2], parts[2::2]))


def score_lines():
    clear_sections()
    lines = {}
    for t in TRIGGERS:
        lines[t + '_p'] = line_trig(t)
    for k, d in HELD.items():
        silent = 0.0 if k in ('basslvl', 'midlvl', 'leadlvl', 'riselvl', 'basshold', 'midhold') else None
        lines[k] = line_held(k, C[k], d, silent)
    for j in range(VOICES):
        first = next(v for v in VP[j] if v is not None)
        lines[f'vp{j}'] = line_held(f'vp{j}', VP[j], first)
        lines[f'vm{j}'] = line_held(f'vm{j}', [0.0 if v is None else v for v in VM[j]], 0.0)
    return lines


def write_patches():
    """One patch per stem: a Cedar program holds only 256 buffers, and past that
    the overflow renders silent with no error."""
    sec = voice_sections()
    score = score_lines()
    paths = {}
    for name in STEMS:
        dsp = sec['common'] + sec[name]
        words = set(re.findall(r'[A-Za-z_]\w*', dsp))
        used = [line for key, line in score.items() if key in words]
        path = os.path.join(HERE, f'cycle_{name}.akkado')
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(f'// cycle / {name}: score (one token = one sixteenth), then the voice.\n')
            f.write('bpm = %d\n\n' % BPM + '\n'.join(used) + '\n\n' + dsp)
        paths[name] = path
    return paths


def render(name, path):
    wav = os.path.join(HERE, f'stem_{name}.wav')
    seconds = (PRE + TOTAL + POST) * STEP / SR + 0.25
    r = subprocess.run([NKIDO, 'render', path, '-o', wav, '--seconds', f'{seconds:.3f}',
                        '--rate', str(SR), '--bpm', str(BPM), '--no-default-bank', '--float32'],
                       capture_output=True, text=True, encoding='utf-8', errors='replace')
    text = r.stdout + r.stderr
    if r.returncode != 0:
        print(text[-1500:].encode('ascii', 'replace').decode())
        sys.exit('nkido render failed: ' + name)
    for l in text.splitlines():
        if 'arena' in l or 'rror' in l:
            print(name, l.encode('ascii', 'replace').decode()[:120])
    sr, x = wavfile.read(wav)
    os.remove(wav)
    assert sr == SR and len(x) >= (PRE + TOTAL + POST) * STEP
    x = x.astype(np.float64)
    print(f'  stem {name:6} peak {db(np.max(np.abs(x))):7.2f}  rms {db(np.std(x)):7.2f}'
          f'  corr {np.corrcoef(x[:, 0], x[:, 1])[0, 1]:.3f}')
    return x


def fold(x):
    """Tails past the loop end wrap onto the head (no cut, no crossfade)."""
    start = PRE * STEP
    y = x[start:start + LOOP].copy()
    tail = x[start + LOOP:]
    y[:len(tail)] += tail
    return y


# ---------------------------------------------------------------- measure
def k_weight(x):
    b1 = [1.53512485958697, -2.69169618940638, 1.19839281085285]
    a1 = [1.0, -1.69065929318241, 0.73248077421585]
    b2 = [1.0, -2.0, 1.0]
    a2 = [1.0, -1.99004745483398, 0.99007225036621]
    return signal.lfilter(b2, a2, signal.lfilter(b1, a1, x, axis=0), axis=0)


def lufs(x):
    y = k_weight(np.concatenate([x, x], axis=0))[len(x):]
    win, hop = int(0.4 * SR), int(0.1 * SR)
    pw = np.sum(y ** 2, axis=1)
    c = np.concatenate([[0], np.cumsum(pw)])
    e = (c[win:] - c[:-win])[::hop] / win
    l = -0.691 + 10 * np.log10(e + 1e-12)
    keep = l > -70
    thresh = -0.691 + 10 * np.log10(np.mean(e[keep])) - 10
    return -0.691 + 10 * np.log10(np.mean(e[l > thresh]))


def db(v):
    return 20 * np.log10(np.maximum(v, 1e-9))


def report(x, marks):
    print(f'duration {len(x) / SR:.3f}s  steps {TOTAL}  samples {len(x)}')
    print(f'LUFS {lufs(x):.2f}  sample peak {db(np.max(np.abs(x))):.2f}  DC {x.mean(axis=0)}')
    tp = np.max(np.abs(signal.resample_poly(x[:: 1], 4, 1, axis=0)))
    print(f'4x peak {db(tp):.2f}  L/R corr {np.corrcoef(x[:, 0], x[:, 1])[0, 1]:.3f}')
    m = x.mean(axis=1)
    f, p = signal.welch(m, SR, nperseg=16384)
    edges = [20, 60, 120, 250, 500, 1000, 2000, 4000, 8000, 12000, 16000, 20000, 24000]
    print('band share dB:')
    for lo, hi in zip(edges, edges[1:]):
        print(f'  {lo:>6}-{hi:<6}{10 * np.log10(p[(f >= lo) & (f < hi)].sum() / p.sum() + 1e-15):8.1f}')
    sos = signal.butter(4, 200, 'high', fs=SR, output='sos')
    lap = signal.sosfilt(sos, m)
    print(f'lost through 200 Hz highpass: {db(np.std(lap) / np.std(m)):.1f} dB')
    print('section     start   RMS  laptop  centroid')
    pts = [p_ for _, p_ in marks] + [TOTAL]
    for (name, a), e_ in zip(marks, pts[1:]):
        i, j = a * STEP, e_ * STEP
        seg = m[i:j]
        sp = np.abs(np.fft.rfft(seg * np.hanning(len(seg))))
        fr = np.fft.rfftfreq(len(seg), 1 / SR)
        print(f'  {name:10}{i / SR:6.1f}{db(np.std(seg)):7.1f}{db(np.std(lap[i:j])):7.1f}'
              f'{np.sum(sp * fr) / np.sum(sp):9.0f}')
    d = np.abs(np.diff(np.concatenate([x[-4800:], x[:4800]], axis=0), axis=0)).max(axis=1)
    print(f'seam step {d[4799]:.5f}; local max {d.max():.5f}; median {np.median(d):.5f}; '
          f'percentile {100 * np.mean(d < d[4799]):.0f}')
    # high-passed jump at the wrap compared with the same sample pairs nearby
    w = np.concatenate([x[-960:], x[:960]], axis=0).mean(axis=1)
    hf = np.abs(signal.sosfiltfilt(signal.butter(4, 8000, 'high', fs=SR, output='sos'), w))
    print(f'8k+ at seam {db(hf[955:965].max()):.1f} dB vs window median {db(np.median(hf)):.1f}')
    w_ = 2400
    print(f'RMS 50 ms before seam {db(np.std(x[-w_:])):.1f}, after {db(np.std(x[:w_])):.1f}')


def write_png(path, rgb):
    h, w, _ = rgb.shape
    raw = b''.join(b'\0' + rgb[y].tobytes() for y in range(h))

    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d))
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))


def spectrogram(x, marks):
    m = x.mean(axis=1)
    W, H, LV = 1600, 560, 150
    f, t, S_ = signal.spectrogram(m, SR, nperseg=4096, noverlap=3072, scaling='spectrum')
    ly = np.logspace(np.log10(30), np.log10(24000), H)
    fi = np.clip(np.searchsorted(f, ly), 0, len(f) - 1)
    ti = np.linspace(0, S_.shape[1] - 1, W).astype(int)
    A = 10 * np.log10(S_[fi][:, ti] + 1e-14)
    v = np.clip((A + 125) / 80, 0, 1)[::-1]
    img = np.zeros((H + LV, W, 3), dtype=np.uint8)
    img[:H, :, 0] = (255 * np.clip(v * 1.6, 0, 1)).astype(np.uint8)
    img[:H, :, 1] = (255 * np.clip(v * 1.7 - 0.7, 0, 1)).astype(np.uint8)
    img[:H, :, 2] = (255 * np.clip(v * 2.4 - 1.5, 0, 1) + 90 * np.clip(1 - np.abs(v - 0.25) * 4, 0, 1)).astype(np.uint8)
    img[H:] = 255
    hop = len(m) // W
    rms = np.array([np.std(m[i * hop:(i + 1) * hop]) for i in range(W)])
    y = np.clip((db(rms) + 60) / 60, 0, 1)
    for i in range(W):
        img[H + LV - int(y[i] * (LV - 2)) - 1:H + LV, i] = (40, 40, 40)
    for name, p in marks:
        col = int(p * STEP / len(m) * W)
        bright = 255 if name.endswith('tear') else 150
        img[:, min(col, W - 1)] = (bright, bright, 255)
    write_png(os.path.join(HERE, 'lab_cycle.png'), img)


def main():
    marks = compose()
    paths = write_patches()
    cache = os.path.join(HERE, 'stems.npz')
    if '--mix' in sys.argv and os.path.exists(cache):
        stems = dict(np.load(cache))
    else:
        stems = {n: fold(render(n, p)).astype(np.float32) for n, p in paths.items()}
        np.savez(cache, **stems)
    x = sum(stems[n].astype(np.float64) * 10 ** (t / 20) for n, t in STEMS.items())
    x = x - x.mean(axis=0)
    gain = 10 ** ((TARGET_LUFS - lufs(x)) / 20)
    x = x * gain
    print(f'raw peak before gain {db(np.max(np.abs(x)) / gain):.2f} dB, gain {db(gain):.1f} dB')
    assert np.max(np.abs(x)) <= 10 ** (PEAK_LIMIT_DB / 20), 'peak over limit at target loudness'
    out = os.path.join(HERE, 'lab_cycle.wav')
    wavfile.write(out, SR, np.round(x * 32767).astype(np.int16))
    y = wavfile.read(out)[1] / 32768.0
    report(y, marks)
    spectrogram(y, marks)


if __name__ == '__main__':
    main()
