# -*- coding: utf-8 -*-
"""Render emotion.akkado with nkido, turn it into a seamless loop, measure it.

All sound comes from nkido. Python only does: take the second pass of the 100 s form
(so bar 0 already holds the tails of bar 39), crossfade its first moments from the
third pass's start (so sample N-1 runs into sample 0 as the render really continued),
remove DC, set level, dither, and then measure.
"""
import hashlib
import os
import shutil
import struct
import subprocess
import sys
import zlib

import numpy as np
from scipy import signal
from scipy.io import wavfile

HERE = os.path.dirname(os.path.abspath(__file__))
NKIDO = r'C:\projects\_tools\nkido\build-clang\bin\nkido.exe'
SR, LOOP_S, BPM = 48000, 100.0, 24
N = int(LOOP_S * SR)
FADE = int(.6 * SR)
TARGET = -28.0
TMP = os.path.join(HERE, '_render')


def load(p):
    return wavfile.read(p)[1].astype(np.float64)


def render():
    shutil.rmtree(TMP, ignore_errors=True)
    os.makedirs(TMP)
    subprocess.run([NKIDO, 'render', os.path.join(HERE, 'emotion.akkado'), '-o', os.path.join(TMP, 't.wav'),
                    '--seconds', '205', '--rate', str(SR), '--bpm', str(BPM), '--no-default-bank',
                    '--float32', '--stems'], check=True)


def fold(x):
    """Pass two, with its start blended over from the start of pass three."""
    y = x[N:2 * N].copy()
    c = (.5 - .5 * np.cos(np.pi * np.arange(FADE) / FADE))[:, None]
    y[:FADE] = np.sqrt(1 - c) * x[2 * N:2 * N + FADE] + np.sqrt(c) * y[:FADE]
    return y


def lufs(x):
    y = np.concatenate([x, x])
    sos = np.array([[1.53512485958697, -2.69169618940638, 1.19839281085285, 1, -1.69065929318241, .73248077421585],
                    [1, -2, 1, 1, -1.99004745483398, .99007225036621]])
    k = signal.sosfilt(sos, y, axis=0)[len(x):]
    w, h = int(.4 * SR), int(.1 * SR)
    p = np.array([np.sum(np.mean(k[i:i + w] ** 2, axis=0)) for i in range(0, len(k) - w, h)])
    l = -.691 + 10 * np.log10(p + 1e-14)
    rel = -.691 + 10 * np.log10(np.mean(p[l > -70])) - 10
    return -.691 + 10 * np.log10(np.mean(p[l > rel])), l


def db(v):
    return 20 * np.log10(v + 1e-12)


def rms(s):
    return db(np.sqrt(np.mean(s ** 2)))


def png(path, img):
    """img: h x w x 3 uint8. No plotting library here, so write it directly."""
    h, w, _ = img.shape
    raw = b''.join(b'\0' + img[r].tobytes() for r in range(h))
    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d))
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))


def spectrogram(x, short, path):
    W, H, LV = 1400, 560, 140
    f, t, S = signal.spectrogram(x.mean(1), SR, nperseg=4096, noverlap=4096 - 2400, window='hann')
    d = 10 * np.log10(S + 1e-14)
    ys = np.geomspace(40, 22000, H)[::-1]
    fi = np.clip(np.searchsorted(f, ys), 1, len(f) - 1)
    ti = np.linspace(0, d.shape[1] - 1, W).astype(int)
    v = np.clip((d[np.ix_(fi, ti)] + 115) / 70, 0, 1)
    img = np.stack([np.clip(v * 2.2, 0, 1), np.clip(v * 2 - .6, 0, 1), np.clip(v * 3 - 2, 0, 1) + .25 * np.sin(v * np.pi)], -1)
    img = (np.clip(img, 0, 1) * 255).astype(np.uint8)
    for hz in (100, 200, 800, 3000, 8000):          # frequency ticks
        img[np.searchsorted(-ys, -hz), :8] = 255
    for bar in (8, 16, 26, 34):                     # section lines
        img[:, int(bar * 2.5 / LOOP_S * W)] = (255, 255, 255)
    lv = np.zeros((LV, W, 3), np.uint8)
    ix = np.linspace(0, len(short) - 1, W).astype(int)
    yy = np.clip(((-15 - short[ix]) / 35 * LV).astype(int), 0, LV - 1)
    lv[yy, np.arange(W)] = (120, 220, 255)
    png(path, np.vstack([img, lv]))


if '--measure-only' not in sys.argv:
    render()
main = load(os.path.join(TMP, 't.wav'))
print('render length', len(main) / SR, 'raw peak', round(float(np.abs(main).max()), 3))
drift = rms(main[N + SR:N + 4 * SR] - main[2 * N + SR:2 * N + 4 * SR]) - rms(main[N + SR:N + 4 * SR])
print(f'pass 2 vs pass 3, 1-4 s: difference {drift:.1f} dB relative to the signal')

mix = fold(main)
mix -= mix.mean(0)
gain = 10 ** ((TARGET - lufs(mix)[0]) / 20)
mix *= gain
d = np.random.default_rng(5).random((N, 2)) - np.random.default_rng(6).random((N, 2))
pcm = np.clip(np.round(mix * 32767 + d * .7), -32768, 32767).astype(np.int16)
wav = os.path.join(HERE, 'lab_emotion.wav')
wavfile.write(wav, SR, pcm)
print('sha1', hashlib.sha1(pcm.tobytes()).hexdigest()[:12])

x = wavfile.read(wav)[1] / 32768.0
I, short = lufs(x)
tp = np.abs(signal.resample_poly(np.concatenate([x[-3000:], x, x[:3000]]), 4, 1, axis=0)).max()
print(f'\nlen {len(x)/SR:.3f}s  LUFS {I:.2f}  peak {db(np.abs(x).max()):.2f}  true-peak {db(tp):.2f}  '
      f'L/R corr {np.corrcoef(x[:,0],x[:,1])[0,1]:.2f}  dc {x.mean():.6f}')

BANDS = [(20, 80), (80, 200), (200, 800), (800, 3000), (3000, 8000), (8000, 16000), (16000, 24000)]
SECT = [('A', 0, 8), ('B', 8, 16), ('C', 16, 26), ('D', 26, 34), ('E', 34, 40), ('ALL', 0, 40)]
print('section ' + ''.join(f'{a}-{b}'.rjust(12) for a, b in BANDS) + '     level')
for nm, a, b in SECT:
    seg = x[int(a * 2.5 * SR):int(b * 2.5 * SR)]
    f, P = signal.welch(seg.mean(1), SR, nperseg=8192)
    row = [10 * np.log10(P[(f >= lo) & (f < hi)].sum() / P.sum() + 1e-12) for lo, hi in BANDS]
    print(f'{nm:7s} ' + ''.join(f'{v:12.1f}' for v in row) + f'  {rms(seg):8.1f}')
print('momentary by 5 s:', ' '.join(f'{np.mean(short[i:i+50]):.0f}' for i in range(0, len(short), 50)))

print('\nlayers in dB against the whole mix, per section:')
names = {1: 'lead', 2: 'keys', 3: 'low', 4: 'pad', 5: 'ticks', 6: 'air', 7: 'reverb'}
print('        ' + ''.join(n.rjust(9) for n, _, _ in SECT))
for i, nm in names.items():
    st = fold(load(os.path.join(TMP, f't.bus{i}.wav'))) * gain
    print(f'{nm:8s}' + ''.join(f'{rms(st[int(a*2.5*SR):int(b*2.5*SR)]) - rms(x[int(a*2.5*SR):int(b*2.5*SR)]):9.1f}' for _, a, b in SECT))

jump = np.abs(x[0] - x[-1]).max()
steps = np.abs(np.diff(x, axis=0)).max(1)
print(f'\nseam jump {jump:.5f}  median step {np.median(steps):.5f}  p99.9 {np.percentile(steps,99.9):.5f}'
      f'  ratio to p99.9 {jump/np.percentile(steps,99.9):.2f}')
join = np.concatenate([x[-SR:], x[:SR]]).mean(1)
hp = signal.sosfiltfilt(signal.butter(4, 6000 / (SR / 2), 'high', output='sos'), join)
wn = int(.01 * SR)
env = np.array([np.sqrt(np.mean(hp[i:i + wn] ** 2)) for i in range(0, len(hp) - wn, wn)])
m = len(env) // 2
print(f'HF at seam {db(env[m-1:m+1].max()):.1f} dB  median around {db(np.median(env)):.1f} dB')
print(f'level 250 ms before seam {rms(x[-12000:]):.1f}  after {rms(x[:12000]):.1f}')
spectrogram(x, short, os.path.join(HERE, 'lab_emotion_spectrogram.png'))
if "--keep" not in sys.argv: shutil.rmtree(TMP, ignore_errors=True)
