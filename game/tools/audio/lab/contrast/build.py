"""lab_contrast: a bright little hold-music tune with three structural faults.

1. Every phrase is one beat too long. The extra beat holds a small pitched gulp.
2. The bass never plays the tonic of the current key and the tune never rests on
   it: phrases stop on the second degree or the leading tone.
3. The bright lead sits on a wet body: a mouth-like resonance opens on each note
   and small droplets follow, more of them as the loop goes on.

In A2 and C2 the accompaniment does not reset after the extra beat, so bass and
backbeat swap sides for a phrase.

All sound comes from nkido. This script only (a) writes the score into
lab_contrast.akkado, (b) renders it, (c) folds the rendered tail onto the head so
the loop is seamless, sets the level, writes the WAV, and (d) measures.
Deterministic. Run: py -3 build.py
"""
import os
import subprocess
import sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import lfilter

HERE = os.path.dirname(os.path.abspath(__file__))
NKIDO = r'C:\projects\_tools\nkido\build-clang\bin\nkido.exe'
SR = 48000
BS = 22800                 # samples per beat, integer so the loop length is exact
BPM = SR * 60 / BS         # 126.32
U = 40                     # score units per beat
SWING = 3                  # off-beat eighths land this many units late
TARGET_LUFS = -28.0
rng = np.random.default_rng(20261104)

M = dict(C=0, Cs=1, D=2, Ds=3, E=4, F=5, Fs=6, G=7, Gs=8, A=9, As=10, B=11)
def n(s):
    return 12 * (int(s[-1]) + 1) + M[s[:-1]]

# ---------------------------------------------------------------- the tune
BAR1 = [('A5', .5), ('B5', .5), ('A5', .5), ('Fs5', 1), ('E5', .5), ('Fs5', 1)]
BAR2 = [('G5', .5), ('A5', .5), ('G5', .5), ('E5', 1), ('D5', .5), ('E5', 1)]
A_MEL = BAR1 + BAR2 + [('Fs5', .5), ('G5', .5), ('A5', .5), ('B5', 1), ('A5', .5), ('Cs6', 1),
                       ('B5', .5), ('A5', .5), ('G5', .5), ('E5', 3.5)]
BAR3B = [('Fs5', .5), ('G5', .5), ('A5', .5), ('D6', 1), ('Cs6', .5), ('B5', 1)]
AP_MEL = BAR1 + BAR2 + BAR3B + [('A5', .5), ('Gs5', .5), ('A5', .5), ('Cs6', 3.5)]
A_CH = [('D/F#', 4), ('G', 2), ('Em', 2), ('Bm', 2), ('A', 2), ('Em', 2), ('A7sus', 2), ('A7', 1)]
AP_CH = [('D/F#', 4), ('G', 2), ('Em', 2), ('Bm', 2), ('G', 2), ('A', 2), ('A7', 3)]

BR1 = ([('B5', .5), ('D6', .5), ('B5', .5), ('G5', 1), ('A5', .5), ('B5', 1),
        ('Cs6', .5), ('B5', .5), ('A5', .5), ('E5', 3.5)], [('G', 4), ('A', 5)])
BR2 = ([('Cs6', .5), ('E6', .5), ('Cs6', .5), ('A5', 1), ('B5', .5), ('Cs6', 1),
        ('D6', .5), ('Cs6', .5), ('B5', .5), ('Fs5', 3.5)], [('A', 4), ('Bm', 5)])
BR3 = ([('D6', .5), ('Fs6', .5), ('D6', .5), ('B5', 1), ('Cs6', .5), ('D6', 1),
        ('E6', .5), ('D6', .5), ('B5', .5), ('Gs5', 3.5)], [('Bm', 2), ('G', 2), ('E7', 5)])
BR4 = ([('E6', .5), ('G6', .5), ('E6', .5), ('C6', 1), ('D6', .5), ('E6', 1),
        ('Fs6', .5), ('E6', .5), ('Ds6', .5), ('B5', 3.5)], [('C', 4), ('B7', 5)])

# Last phrase turns back: in E, it stops on A7, the way home to D.
OUT_TAIL = [('B5', .5), ('Gs5', .5), ('A5', .5), ('Cs6', 3.5)]
OUT_CH = [('D/F#', 4), ('G', 2), ('Em', 2), ('Bm', 2), ('G', 2), ('A7h', 5, 0)]

CHORDS = {  # bass root, bass other, voicing
    'D/F#':  (42, 45, [62, 66, 69]),
    'G':     (43, 47, [62, 67, 71]),
    'Em':    (40, 47, [64, 67, 71]),
    'Bm':    (47, 42, [62, 66, 71]),
    'A':     (45, 40, [61, 64, 69]),
    'A7':    (45, 40, [61, 67, 69]),
    'A7h':   (45, 49, [61, 67, 69]),
    'A7sus': (45, 40, [62, 67, 69]),
    'E7':    (40, 44, [62, 64, 68]),
    'C':     (48, 43, [60, 64, 67]),
    'B7':    (47, 42, [63, 66, 69]),
}

def P(mel, ch, tail=None):
    return dict(mel=mel, ch=ch, tail=tail or [])

SECTIONS = [
    dict(name='intro', T=0, wet=.2, cont=0, lead=0, third=0, gl=.8, pad=0, comp=.8, bass=.8,
         hat=.5, kick=0, pop=.5, shake=0, drops=0, ph=[P([], [('D/F#', 4), ('G', 2), ('A7', 3)])]),
    dict(name='A1', T=0, wet=.3, cont=0, lead=.8, third=0, gl=0, pad=0, comp=.45, bass=.8,
         hat=.6, kick=.3, pop=.6, shake=0, drops=.15, ph=[P(A_MEL, A_CH), P(AP_MEL, AP_CH)]),
    dict(name='A2', T=0, wet=.5, cont=1, lead=.9, third=0, gl=.9, pad=.5, comp=.85, bass=.9,
         hat=.8, kick=.7, pop=.8, shake=.5, drops=.3, ph=[P(A_MEL, A_CH), P(AP_MEL, AP_CH)]),
    dict(name='B', T=0, wet=.65, cont=0, lead=.85, third=0, gl=.5, pad=1., comp=.5, bass=.7,
         hat=.3, kick=.4, pop=.5, shake=.9, drops=.6, ph=[P(*BR1), P(*BR2), P(*BR3), P(*BR4)]),
    dict(name='A3', T=2, wet=.85, cont=0, lead=1., third=.6, gl=.8, pad=.9, comp=1., bass=1.,
         hat=1., kick=1., pop=1., shake=.7, drops=.8, ph=[P(A_MEL, A_CH), P(AP_MEL, AP_CH)]),
    dict(name='C1', T=2, wet=1., cont=0, lead=.9, third=0, gl=.6, pad=0, comp=.3, bass=0,
         hat=.3, kick=0, pop=.3, shake=0, drops=1., ph=[P(A_MEL, A_CH)]),
    dict(name='C2', T=2, wet=.7, cont=1, lead=.95, third=.4, gl=.7, pad=.6, comp=.9, bass=.9,
         hat=.8, kick=.7, pop=.8, shake=.5, drops=.5, ph=[P(AP_MEL[:18], OUT_CH, OUT_TAIL)]),
]

TOTAL = 0
for s in SECTIONS:
    s['start'] = TOTAL
    for p in s['ph']:
        p['len'] = int(sum(c[1] for c in p['ch']))
        TOTAL += p['len']
    s['end'] = TOTAL
TAIL = 7                    # beats of silence in the score for tails to ring into
SPAN = TOTAL + TAIL
N = TOTAL * BS

# ---------------------------------------------------------------- score to events
LINES = {k: [] for k in ['lead', 'lead2', 'bass', 'c1', 'c2', 'c3', 'gl', 'p1', 'p2', 'p3', 'kick', 'pop',
                         'hat', 'shake', 'dropL', 'dropR', 'gulp']}

def pos(b):
    u = int(round(b * U))
    return u + SWING if u % U == U // 2 else u

def ev(line, b, dur, midi, vel):
    LINES[line].append((pos(b), pos(b + dur), int(midi), round(float(vel), 3)))

def third_below(m):
    pcs = [2, 4, 6, 7, 9, 11, 1]
    if m % 12 in pcs:
        return m - ((m - pcs[(pcs.index(m % 12) - 2) % 7]) % 12)
    return m - 4

flat = [(s, p) for s in SECTIONS for p in s['ph']]

def play(s, p, b0, next_bass):
    T, L = s['T'], p['len']
    b = b0
    for name, d, tr in [(x, d, T) for x, d in p['mel']] + [(x, d, 0) for x, d in p['tail']]:
        m = n(name) + tr
        hold = d > 2
        vel = s['lead'] * (1.0 if b % 2 < .01 else .86)
        g = d if hold else d * .78
        if s['lead']:
            ev('lead', b, g, m, vel)
            if s['third']:
                ev('lead2', b, g, third_below(n(name)) + tr, vel * s['third'])
            if s['drops'] and rng.random() < s['drops'] * .55:
                ev('dropL' if rng.random() < .5 else 'dropR', b + d * .8, .12, rng.integers(86, 94), rng.uniform(.5, 1.))
        if s['gl'] and s['third'] and not hold:
            ev('gl', b, d, m + 12, .5)
        b += d
    i, phase = 0, s.setdefault('_ph', 0)
    for c in p['ch']:
        name, dur = c[0], c[1]
        tc = c[2] if len(c) > 2 else T
        root, alt, voi = CHORDS[name]
        if s['pad']:
            for k, v in enumerate(voi):
                ev(f'p{k + 1}', b0 + i, dur - .02, v + tc, s['pad'])
        seen = 0
        for j in range(dur):
            at = i + j
            if at == L - 1 and not s['cont']:
                continue
            bb = b0 + at
            if (at + phase) % 2 == 0:
                if s['bass']:
                    ev('bass', bb, .8, (root if seen == 0 else alt) + tc, s['bass'])
                    seen += 1
                if s['kick']:
                    ev('kick', bb, .25, 40, s['kick'])
            else:
                if s['comp']:
                    for k, v in enumerate(voi):
                        ev(f'c{k + 1}', bb, .4, v + tc, s['comp'])
                if s['pop']:
                    ev('pop', bb, .25, 60, s['pop'])
        i += dur
    if s['gl'] and p['mel']:
        c = p['ch'][-1]
        tc = c[2] if len(c) > 2 else T
        arp = sorted(v + tc + 12 for v in CHORDS[c[0]][2])
        for k, m in enumerate([arp[0], arp[1], arp[2], arp[0] + 12, arp[2], arp[1]]):
            ev('gl', b0 + L - 3 + k * .5, .5, m + 12, s['gl'])
    elif s['gl']:
        for k, m in enumerate([69, 74, 78, 81, 78, 74, 76, 81]):
            ev('gl', b0 + 1 + k * .5, .5, m + 12, s['gl'])
    for e in range(L * 2):
        bb = b0 + e / 2
        if s['hat']:
            ev('hat', bb, .2, 60, s['hat'] * (1. if e % 2 else .6))
        if s['shake'] and e % 2:
            ev('shake', bb, .25, 60, s['shake'])
        if s['drops'] and rng.random() < s['drops'] * .22:
            ev('dropL' if rng.random() < .5 else 'dropR', bb + .25, .12, rng.integers(84, 92), rng.uniform(.3, .8))
    t = next_bass
    while t < 67:
        t += 12
    b1 = b0 + L - 1
    vg = .55 + .45 * s['wet']
    ev('gulp', b1, .3, t - 7, vg * .8)
    ev('gulp', b1 + .36, .5, t, vg)
    if s['cont']:
        s['_ph'] = (phase + L) % 2

b = 0
for i, (s, p) in enumerate(flat):
    ns, np_ = flat[(i + 1) % len(flat)]
    c0 = np_['ch'][0]
    nt = c0[2] if len(c0) > 2 else ns['T']
    play(s, p, b, CHORDS[c0[0]][0] + nt)
    b += p['len']

def pattern(line):
    """Weighted sequence stretched over the whole form. Each line is one voice."""
    evs = sorted(LINES[line])
    out, cur = [], 0
    for k, (a, e, m, v) in enumerate(evs):
        nxt = evs[k + 1][0] if k + 1 < len(evs) else SPAN * U
        if a == nxt or a < cur:
            continue
        if a > cur:
            out.append(f'~@{a - cur}')
        e = min(e, nxt)
        out.append(f'{m}{{vel:{v}}}@{e - a}')
        cur = e
    if cur < SPAN * U:
        out.append(f'~@{SPAN * U - cur}')
    return 'n"[' + ' '.join(out) + f']/{SPAN}"'

def curve(key, default=0):
    parts = [f"{s[key]}@{(s['end'] - s['start']) * U}" for s in SECTIONS]
    return 'v"[' + ' '.join(parts) + f' {default}@{TAIL * U}]/{SPAN}"'

for s in SECTIONS:
    s['phone'] = 1 if s['name'] == 'C1' else 0

GAIN = dict(lead=.34, bass=.62, comp=.17, gl=.14, pad=.017, kick=.40, pop=.17, hat=.075, shake=.05, drop=.15, gulp=.36)

VOICES = f'''// lab_contrast. Written by build.py from its score; the DSP below is the piece.
bpm = {BPM:.8f}

wetc = slew({curve('wet', 0.2)}, 0.6)
phone = slew({curve('phone', 0)}, 5)

fn lead_voice(f, trig, gate, vel) -> {{
    ld_drop = ar(trig, 0.001, 0.05)
    ld_open = 1 - ar(trig, 0.001, 0.16)
    ld_vib = sine(5.3) * 0.13 * adsr(gate, 0.3, 0.1, 1.0, 0.05)
    ld_fp = f * pow(2, (ld_vib - (0.25 + 2.6 * wetc) * ld_drop) / 12)
    ld_s = lp(sqr(ld_fp) * 0.5 + saw(ld_fp) * 0.55, 10500)
    ld_b1 = bp(ld_s, (620 + 980 * ld_open) * (1 + 0.1 * wetc * sine(3.4)), 3.0)
    ld_b2 = bp(ld_s, 2500 + 900 * ld_open, 4.5)
    ld_fl = 1 - 0.86 * wetc
    (ld_s * ld_fl * 0.55 + (ld_b1 * 1.5 + ld_b2 * 0.8) * (1 - ld_fl)) * adsr(gate, 0.004, 0.18, 0.62, 0.09) * vel
}}

fn bass_voice(f, trig, vel) -> {{
    bs_sag = ar(trig, 0.001, 0.035)
    bs_fp = f * pow(2, 1.6 * (0.4 + wetc) * bs_sag / 12)
    bs_s = saw(bs_fp) * 0.7 + sine(bs_fp) * 0.6
    lp(bs_s, 260 + 1000 * ar(trig, 0.001, 0.13), 3.2) * ar(trig, 0.003, 0.32) * vel
}}

fn comp_voice(f, trig, vel) -> {{
    cs_s = tri(f) + sqr(f) * 0.28
    lp(cs_s, 1300 + 4200 * ar(trig, 0.001, 0.06)) * ar(trig, 0.002, 0.15) * vel
}}

glock = ({{freq, trig, vel}}) ->
    (sine(freq) * ar(trig, 0.001, 0.42)
     + sine(freq * 2.756) * ar(trig, 0.001, 0.13) * 0.4
     + sine(freq * 5.404) * ar(trig, 0.001, 0.05) * 0.16) * vel

fn pad_voice(f, gate, vel) -> {{
    pv_e = adsr(gate, 0.14, 0.2, 0.9, 0.25) * vel
    stereo(lp(saw(f * 0.9977), 1100) * pv_e, lp(saw(f * 1.0023), 1100) * pv_e)
}}

fn drop_voice(f, trig, vel) -> {{
    dv_r = 1 - ar(trig, 0.001, 0.035)
    sine(f * (0.5 + 1.3 * dv_r)) * ar(trig, 0.001, 0.05) * vel
}}

fn gulp_voice(f, trig, vel) -> {{
    gv_r = 1 - ar(trig, 0.001, 0.09)
    gv_fp = f * (0.45 + 0.55 * gv_r)
    gv_s = sine(gv_fp) + tri(gv_fp * 2) * 0.35
    bp(gv_s, gv_fp * 2.2, 1.4) * 1.2 + gv_s * 0.6
}}
'''

BODY = []
def line(name, expr):
    BODY.append(f'{name} = {expr}')

line('leadA', f'{pattern("lead")} as e |> lead_voice(e.freq, e.trig, e.gate, e.vel)')
line('leadB', f'{pattern("lead2")} as e |> lead_voice(e.freq, e.trig, e.gate, e.vel)')
line('bassS', f'{pattern("bass")} as e |> bass_voice(e.freq, e.trig, e.vel)')
for k in (1, 2, 3):
    line(f'comp{k}', f'{pattern(f"c{k}")} as e |> comp_voice(e.freq, e.trig, e.vel)')
    line(f'pad{k}', f'{pattern(f"p{k}")} as e |> pad_voice(e.freq, e.gate, e.vel)')
line('glockS', f'{pattern("gl")} |> poly(@, glock, 6, release: 0.7) |> mono(@)')
line('kickS', f'{pattern("kick")} as e |> sine(55 + 140 * ar(e.trig, 0.001, 0.025)) * ar(e.trig, 0.001, 0.11) * e.vel')
line('popS', f'{pattern("pop")} as e |> sine(420 + 1200 * (1 - ar(e.trig, 0.001, 0.025))) * ar(e.trig, 0.001, 0.03) * e.vel'
             ' + bp(noise(), 2600, 0.9) * ar(e.trig, 0.001, 0.05) * e.vel * 0.55')
line('hatS', f'{pattern("hat")} as e |> lp(hp(noise(), 7500), 13000) * ar(e.trig, 0.001, 0.02) * e.vel')
line('shakeS', f'{pattern("shake")} as e |> bp(noise(), 6000, 1.0) * ar(e.trig, 0.018, 0.045) * e.vel')
line('dropL', f'{pattern("dropL")} as e |> drop_voice(e.freq, e.trig, e.vel)')
line('dropR', f'{pattern("dropR")} as e |> drop_voice(e.freq, e.trig, e.vel)')
line('gulpS', f'{pattern("gulp")} as e |> gulp_voice(e.freq, e.trig, e.vel) * ar(e.trig, 0.006, 0.13) * e.vel')

g = GAIN
ROUTE = f'''
leadM = leadA * {g['lead']} + leadB * {g['lead'] * .8}
compM = (comp1 + comp2 + comp3) * {g['comp']}
padM = (pad1 + pad2 + pad3) * {g['pad']}
glM = glockS * {g['gl']}
dropM = (dropL + dropR) * {g['drop']}
gulpM = gulpS * {g['gulp']}
perc = kickS * {g['kick']} + popS * {g['pop']} + hatS * {g['hat']} + shakeS * {g['shake']}

send = leadM * 0.20 + compM * 0.16 + glM * 0.40 + dropM * 0.5 + gulpM * 0.22 + popS * {g['pop']} * 0.10
rvb = send |> dattorro(@, 0.42, 14, 0.75, 0.6, dry: 0, wet: 1, damping: 0.45) |> hp(@, 180)
echoL = delay(glM, spb * 0.75, 0.3, 0, 0.5)

fn phoneline(x) -> left(x |> saturate(@, 2.2) |> lp(@, 3000, 1.0) |> hp(@, 430, 1.0))
master((l, r) -> stereo((l * (1 - phone) + phoneline(l) * phone * 0.3) * 0.72,
                        (r * (1 - phone) + phoneline(r) * phone * 0.3) * 0.72))

pan(leadM, -0.06) |> bus(1, @)
pan(bassS * {g['bass']}, 0) |> bus(2, @)
pan(compM, 0.42) |> bus(3, @)
pan(glM, -0.5) + pan(echoL, 0.7) |> bus(4, @)
padM |> bus(5, @)
pan(perc, 0.05) |> bus(6, @)
pan(dropL * {g['drop']}, -0.6) + pan(dropR * {g['drop']}, 0.6) + pan(gulpM, 0) |> bus(7, @)
rvb * 1.8 |> bus(8, @)
'''

patch = os.path.join(HERE, 'lab_contrast.akkado')
with open(patch, 'w', encoding='utf-8', newline='\n') as fh:
    fh.write(VOICES + '\n' + '\n'.join(BODY) + '\n' + ROUTE)

# ---------------------------------------------------------------- render
TMP = os.path.join(HERE, '_raw.wav')
stems = '--stems' in sys.argv
cmd = [NKIDO, 'render', patch, '-o', TMP, '--seconds', f'{SPAN * BS / SR + .1:.3f}', '--rate', str(SR),
       '--bpm', f'{BPM:.8f}', '--no-default-bank', '--float32'] + (['--stems'] if stems else [])
r = subprocess.run(cmd, capture_output=True, text=True)
print((r.stdout + r.stderr)[-800:])
if r.returncode:
    raise SystemExit(f'nkido failed: {r.returncode}')
sr, raw = wavfile.read(TMP)
assert sr == SR
raw = raw.astype(np.float64)
print(f'raw peak {np.max(np.abs(raw)):.3f}  rms {20 * np.log10(np.sqrt(np.mean(raw ** 2))):.1f} dB  clipped {np.sum(np.abs(raw) >= .999)}')

# ---------------------------------------------------------------- loop, level
def fold(y):
    x = y[:N].copy()
    t = y[N:SPAN * BS]
    x[:len(t)] += t
    return x

def hpf(x, fc=32.0):
    X = np.fft.rfft(x, axis=0)
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    fr[0] = 1e-3
    return np.fft.irfft(X / np.sqrt(1 + (fc / fr) ** 4)[:, None], len(x), axis=0)

def lufs(x):
    y = np.concatenate([x, x], 0)
    b1, a1 = [1.53512485958697, -2.69169618940638, 1.19839281085285], [1, -1.69065929318241, .73248077421585]
    b2, a2 = [1, -2, 1], [1, -1.99004745483398, .99007225036621]
    y = lfilter(b2, a2, lfilter(b1, a1, y, axis=0), axis=0)[len(x):]
    blk, hop = int(.4 * SR), int(.1 * SR)
    p = np.array([np.mean(y[i:i + blk] ** 2, 0).sum() for i in range(0, len(y) - blk, hop)])
    p = p[p > 10 ** ((-70 + .691) / 10)]
    return -.691 + 10 * np.log10(p[p > p.mean() * .1].mean())

print(f'DC before removal L/R {raw[:, 0].mean():.5f} {raw[:, 1].mean():.5f}')
mix = hpf(fold(raw))
mix -= mix.mean(0)
mix *= 10 ** ((TARGET_LUFS - lufs(mix)) / 20)
if np.max(np.abs(mix)) > 10 ** (-1 / 20):
    raise SystemExit('peak above -1 dBFS')
dith = np.random.default_rng(7).uniform(-.5, .5, mix.shape) + np.random.default_rng(8).uniform(-.5, .5, mix.shape)
pcm = np.clip(np.round(mix * 32767 + dith), -32768, 32767).astype(np.int16)
out = os.path.join(HERE, 'lab_contrast.wav')
wavfile.write(out, SR, pcm)

# ---------------------------------------------------------------- measure
x = pcm / 32768.0
print(f'beats {TOTAL}  dur {N / SR:.2f}s  peak {20 * np.log10(np.max(np.abs(x))):.2f} dBFS  LUFS {lufs(x):.2f}')
mono = x.mean(1)
print(f'L/R correlation {np.corrcoef(x[:, 0], x[:, 1])[0, 1]:.3f}')
fr = np.fft.rfftfreq(N, 1 / SR)
PW = np.abs(np.fft.rfft(mono)) ** 2
edges = [20, 60, 120, 250, 500, 1000, 2000, 4000, 8000, 16000, 24000]
tot = PW.sum()
print('band share dB:', ' '.join(f'{lo}-{hi}:{10 * np.log10(PW[(fr >= lo) & (fr < hi)].sum() / tot + 1e-14):.1f}' for lo, hi in zip(edges, edges[1:])))
print(f'above 250 Hz {100 * PW[fr > 250].sum() / tot:.1f}%  above 18k {10 * np.log10(PW[fr > 18000].sum() / tot + 1e-14):.1f} dB')
step = np.abs(np.diff(x, axis=0))
seam = np.abs(x[0] - x[-1])
print(f'seam step {seam[0]:.5f} {seam[1]:.5f}; median step {np.median(step):.5f}, p99 {np.percentile(step, 99):.5f}')
for s in SECTIONS:
    a, e = s['start'] * BS, s['end'] * BS
    seg = mono[a:e]
    S = np.abs(np.fft.rfft(seg)) ** 2
    f = np.fft.rfftfreq(len(seg), 1 / SR)
    print(f"  {s['name']:<6} t={a / SR:5.1f}  rms {10 * np.log10(np.mean(seg ** 2)):6.1f}  centroid {(S * f).sum() / S.sum():6.0f}")

# spectrogram PNG, written directly (log frequency, section ticks, level strip below)
import zlib, struct
from scipy.signal import spectrogram
f, tt, S = spectrogram(mono, SR, nperseg=4096, noverlap=3072, window='hann', mode='psd')
W, H, H2 = 1400, 560, 90
logf = np.geomspace(40, 20000, H)
cols = np.linspace(0, S.shape[1] - 1, W).astype(int)
img = np.zeros((H, W))
for j, c in enumerate(cols):
    img[:, j] = np.interp(logf, f, S[:, c])
db = 10 * np.log10(img + 1e-16)
v = np.clip((db + 125) / 75, 0, 1)[::-1]
rgb = np.stack([v ** .6, v ** 1.6, .35 * v + .65 * v ** 3.5], 2)
strip = np.zeros((H2, W, 3))
hop = N // W
lev = np.array([10 * np.log10(np.mean(mono[i * hop:(i + 1) * hop] ** 2) + 1e-12) for i in range(W)])
for j, l in enumerate(lev):
    strip[H2 - 1 - int(np.clip((l + 60) / 40, 0, 1) * (H2 - 1)):, j] = (.5, .8, .6)
page = np.concatenate([rgb, strip], 0)
for s in SECTIONS:
    page[:, int(s['start'] * BS / N * W)] = 1
for fq in (100, 1000, 10000):
    page[H - 1 - int(np.log(fq / 40) / np.log(500) * (H - 1)), :18] = 1
raw8 = (np.clip(page, 0, 1) * 255).astype(np.uint8)
def chunk(k, d):
    return struct.pack('>I', len(d)) + k + d + struct.pack('>I', zlib.crc32(k + d))
body = b''.join(bytes(1) + r_.tobytes() for r_ in raw8)
with open(os.path.join(HERE, 'lab_contrast_spectrogram.png'), 'wb') as fh:
    fh.write(bytes([137, 80, 78, 71, 13, 10, 26, 10]) + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H + H2, 8, 2, 0, 0, 0))
             + chunk(b'IDAT', zlib.compress(body, 9)) + chunk(b'IEND', b''))

# ---------------------------------------------------------------- did the notes arrive?
if stems:
    def check(bus, line, lo, hi):
        _, y = wavfile.read(TMP.replace('.wav', f'.bus{bus}.wav'))
        y = y.mean(1).astype(np.float64)
        bad, seen = 0, 0
        for a, e, m, v in sorted(LINES[line]):
            c = int(a / U * BS) + int(.05 * SR)
            L = 12000
            seg = y[c:c + L]
            if (e - a) / U * BS < .1 * SR or np.sqrt(np.mean(seg ** 2)) < 1e-4:
                bad += (e - a) / U * BS >= .1 * SR
                continue
            seg = seg * np.hanning(L)
            ac = np.fft.irfft(np.abs(np.fft.rfft(seg, 2 * L)) ** 2)[:L]
            want = SR / (440 * 2 ** ((m - 69) / 12))
            i0, i1 = int(want * .94), int(want * 1.06) + 2
            k = i0 + int(np.argmax(ac[i0:i1]))
            seen += 1
            if ac[k] < .45 * ac[0]:
                bad += 1
                print('  off:', a / U, m, round(float(ac[k] / ac[0]), 2))
        print(f'pitch check {line}: {seen} notes heard, {bad} wrong or missing')
    check(1, 'lead', 0, 0)
    check(2, 'bass', 0, 0)
    tonic = sum(1 for s in SECTIONS for a, e, m, v in LINES['bass'] if s['start'] * U <= a < s['end'] * U and m % 12 == (2 + s['T']) % 12)
    print('bass notes on the tonic of the current key:', tonic)
    print('bass line length', len(LINES['bass']), 'lead', len(LINES['lead']), 'gulps', len(LINES['gulp']) // 2)

for name in os.listdir(HERE):
    if name.startswith('_raw'):
        os.remove(os.path.join(HERE, name))
