# -*- coding: utf-8 -*-
"""Renders the seven .akkado patches with nkido, then only post-processes.

All sound comes from nkido. Python mixes the rendered buses (level, pan), folds
the 10 s tail past bar 40 back on to the head so the loop has no join, sets
loudness, and measures. It generates no audio of its own.
"""
import os
import struct
import subprocess
import sys
import wave
import zlib

import numpy as np
from scipy import signal
from scipy.io import wavfile

HERE = os.path.dirname(os.path.abspath(__file__))
STEM_DIR = os.path.join(HERE, 'stems')
NK = r'C:\projects\_tools\nkido\build-clang\bin\nkido.exe'
SR = 48000
BAR = 2.5
BARS = 40
N = int(SR * BAR * BARS)
TOTAL = 110.25          # 44 bars plus a block margin; bars 40-43 are silent
TARGET = -28.0

# patch, bus -> (gain dB, pan, or None for an already stereo return)
TRIM = dict(tap=6, porcelain=0, tile=5, pipe=6, teeth=8, meat=6, breath=-32)
WET = dict(tap=2, porcelain=2, tile=2, pipe=0, teeth=0, meat=0, breath=0)
WIDTH = 2.4         # side gain on the room returns, which come out of nkido nearly mono
MIX = {
    ('tap', 1): .30, ('tap', 2): None,
    ('porcelain', 1): -.22, ('porcelain', 2): None,
    ('tile', 1): .55, ('tile', 2): -.6, ('tile', 3): None,
    ('pipe', 1): -.08, ('pipe', 2): None,
    ('teeth', 1): 0, ('teeth', 2): None,
    ('meat', 1): .05, ('meat', 2): None,
    ('breath', 1): 0, ('breath', 2): None,
}
VOICES = ['tap', 'porcelain', 'tile', 'pipe', 'teeth', 'meat', 'breath']


def render(p):
    out = os.path.join(STEM_DIR, p + '.wav')
    r = subprocess.run([NK, 'render', os.path.join(HERE, p + '.akkado'), '-o', out, '--seconds', str(TOTAL),
                        '--rate', str(SR), '--bpm', '24', '--no-default-bank', '--stems', '--float32'],
                       capture_output=True, text=True, encoding='utf-8', errors='replace')
    errs = [l for l in (r.stdout + r.stderr).splitlines() if 'error' in l]
    if r.returncode or errs:
        sys.exit(f'nkido failed on {p}: rc={r.returncode}\n' + (r.stdout + r.stderr)[-1500:])


def read(path):
    return wavfile.read(path)[1].astype(np.float64)


def fold(x):
    """Lay everything past bar 40 back over the head, so tails wrap."""
    y = np.zeros((N, 2))
    m = min(len(x), N)
    y[:m] = x[:m]
    t = x[N:int(110 * SR)]     # the pattern restarts at bar 44, 110 s: stop just before
    y[:min(len(t), N)] += t[:N]
    return y


def place(x, pan):
    if pan is None:
        mid, side = x.mean(axis=1), (x[:, 0] - x[:, 1]) / 2
        return np.c_[mid + WIDTH * side, mid - WIDTH * side]
    th = (pan + 1) * np.pi / 4
    g = np.array([np.cos(th), np.sin(th)])
    m = x[:, 0]
    d = int(abs(pan) * 14)          # small time difference between the ears
    late = np.r_[np.zeros(d), m[:len(m) - d]] if d else m
    return np.c_[g[0] * (late if pan > 0 else m), g[1] * (late if pan < 0 else m)]


def kweight(x):
    b1, a1 = [1.53512485958697, -2.69169618940638, 1.19839281085285], [1, -1.69065929318241, 0.73248077421585]
    b2, a2 = [1, -2, 1], [1, -1.99004745483398, 0.99007225036621]
    return signal.lfilter(b2, a2, signal.lfilter(b1, a1, x, axis=0), axis=0)


def lufs(x):
    y = kweight(np.vstack([x, x[:SR]]))
    block, hop = int(.4 * SR), int(.1 * SR)
    c = np.r_[0, np.cumsum(np.sum(y ** 2, axis=1))]
    pw = (c[block:] - c[:-block])[::hop] / block
    pw = pw[-0.691 + 10 * np.log10(pw + 1e-15) > -70]
    rel = -0.691 + 10 * np.log10(pw.mean()) - 10
    pw = pw[-0.691 + 10 * np.log10(pw) > rel]
    return -0.691 + 10 * np.log10(pw.mean())


def db(v):
    return 20 * np.log10(v + 1e-12)


BANDS = [(20, 60), (60, 120), (120, 250), (250, 500), (500, 1000), (1000, 2000), (2000, 4000), (4000, 8000), (8000, 12000), (12000, 16000), (16000, 24000)]
SECTS = [('tap', 0, 8), ('tile', 8, 16), ('flesh', 16, 24), ('climax', 24, 28), ('held', 28, 32), ('return', 32, 36), ('drain', 36, 40)]


def bandtab(x):
    S = np.abs(np.fft.rfft(x.mean(axis=1))) ** 2
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return [10 * np.log10(S[(f >= a) & (f < b)].sum() / (S.sum() + 1e-20) + 1e-12) for a, b in BANDS]


def report(mix, stems):
    print('bands dB rel total   ' + ' '.join(f'{a:>6}' for a, _ in BANDS))
    print(f'{"whole":<20}' + ' '.join(f'{v:6.1f}' for v in bandtab(mix)))
    for n, a, b in SECTS:
        seg = mix[int(a * BAR * SR):int(b * BAR * SR)]
        print(f'{n:<8}{db(np.sqrt(np.mean(seg ** 2))):6.1f}rms   ' + ' '.join(f'{v:6.1f}' for v in bandtab(seg)))
    print('level per bar (dB rms):', ' '.join(f'{db(np.sqrt(np.mean(mix[int(i * BAR * SR):int((i + 1) * BAR * SR)] ** 2))):.0f}' for i in range(BARS)))
    print('voice rms rel mix per section; last column spectral centroid Hz')
    print(f'{"":<10}' + ' '.join(f'{n:>7}' for n, _, _ in SECTS))
    f = np.fft.rfftfreq(N, 1 / SR)
    for v in VOICES:
        row = []
        for n, a, b in SECTS:
            i, j = int(a * BAR * SR), int(b * BAR * SR)
            row.append(db(np.sqrt(np.mean(stems[v][i:j] ** 2))) - db(np.sqrt(np.mean(mix[i:j] ** 2))))
        S = np.abs(np.fft.rfft(stems[v].mean(axis=1))) ** 2
        print(f'{v:<10}' + ' '.join(f'{r:7.1f}' for r in row) + f' {(S * f).sum() / (S.sum() + 1e-20):8.0f}')
    wrap = np.vstack([mix[-2400:], mix[:2400]])
    d = np.abs(np.diff(wrap, axis=0)).max(axis=1)
    print(f'seam step {d[2399]:.5f}; neighbours max {d.max():.5f}, median {np.median(d):.5f}')
    hp = signal.butter(4, 6000 / (SR / 2), 'high', output='sos')
    y = signal.sosfiltfilt(hp, np.vstack([mix[-24000:], mix[:24000]]), axis=0)
    w = lambda c, h: np.sqrt(np.mean(y[c - h:c + h] ** 2))
    print(f'hf at seam +-2ms {db(w(24000, 96)):.1f} dB; +-500ms {db(w(24000, 23999)):.1f} dB')
    y2 = signal.sosfiltfilt(hp, mix[int(BAR * SR) - 24000:int(BAR * SR) + 24000], axis=0)
    print(f'same drip one bar later +-2ms {db(np.sqrt(np.mean(y2[23904:24096] ** 2))):.1f} dB')
    print(f'L/R correlation {np.corrcoef(mix[:, 0], mix[:, 1])[0, 1]:.3f}; dc {mix.mean():.6f}')


def spectrogram(mix, path):
    """Log-frequency spectrogram over a level strip, written as a plain PNG."""
    W, H, S = 1500, 640, 120
    f, t, P = signal.spectrogram(mix.mean(axis=1), SR, nperseg=4096, noverlap=4096 - N // W)
    edges = np.geomspace(40, 20000, H + 1)
    idx = np.searchsorted(f, edges)
    img = np.zeros((H, P.shape[1]))
    for r in range(H):
        a, b = idx[r], max(idx[r] + 1, idx[r + 1])
        img[H - 1 - r] = P[a:b].mean(axis=0)
    v = np.clip((10 * np.log10(img + 1e-14) + 120) / 70, 0, 1)
    v = v[:, np.linspace(0, v.shape[1] - 1, W).astype(int)]
    rgb = np.stack([np.clip(v * 1.6, 0, 1), np.clip(v * 1.6 - .5, 0, 1), np.clip(v * 3 - 2, 0, 1) * .9 + .15 * v], -1)
    strip = np.full((S, W, 3), .08)
    e = np.array([np.sqrt(np.mean(c ** 2)) for c in np.array_split(mix, W)])
    y = np.clip((db(e) + 60) / 50, 0, 1) * (S - 2)
    for x in range(W):
        strip[S - 1 - int(y[x]):, x] = (.4, .8, .9)
    im = np.vstack([rgb, strip])
    for _, a, _b in SECTS:
        im[:, int(a / BARS * (W - 1))] = (.1, 1, .3)
    for hz in (100, 1000, 10000):
        im[int(H * (1 - np.log(hz / 40) / np.log(500))), :] *= .55
    data = (im * 255).astype(np.uint8)
    raw = bytes(0).join(bytes(1) + r.tobytes() for r in data)

    def chunk(k, d):
        return struct.pack('>I', len(d)) + k + d + struct.pack('>I', zlib.crc32(k + d))
    with open(path, 'wb') as fh:
        sig = bytes([137, 80, 78, 71, 13, 10, 26, 10])
        fh.write(sig + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H + S, 8, 2, 0, 0, 0))
                 + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))


def main():
    os.makedirs(STEM_DIR, exist_ok=True)
    if '--mix' not in sys.argv:
        for p in VOICES:
            render(p)
    stems = {v: np.zeros((N, 2)) for v in VOICES}
    for (p, b), pan in MIX.items():
        g = TRIM[p] + (WET[p] if pan is None else 0)
        path = os.path.join(STEM_DIR, f'{p}.bus{b}.wav')
        x = read(path)
        print(f'{p}.bus{b}: {len(x) / SR:.2f}s peak {db(np.abs(x).max()):.1f} dc {x.mean():.5f}')
        stems[p] += fold(place(x, pan)) * 10 ** (g / 20)
    mix = sum(stems.values())
    # circular high-pass: nothing useful below 34 Hz, and it removes any dc
    X = np.fft.rfft(mix, axis=0)
    f = np.fft.rfftfreq(N, 1 / SR)
    X *= (1 / np.sqrt(1 + (34.0 / np.maximum(f, .01)) ** 8))[:, None]
    X[0] = 0
    mix = np.fft.irfft(X, N, axis=0)
    g = 10 ** ((TARGET - lufs(mix)) / 20)
    mix *= g
    for v in VOICES:
        stems[v] *= g
    pk = np.abs(mix).max()
    if pk > 10 ** (-1.1 / 20):
        print('peak limited the level', db(pk))
        mix *= 10 ** (-1.1 / 20) / pk
    tp = max(np.abs(signal.resample_poly(mix[:, c], 4, 1)).max() for c in range(2))
    print(f'LUFS {lufs(mix):.2f} peak {db(np.abs(mix).max()):.2f} dBFS 4x-peak {db(tp):.2f} len {N / SR:.1f}s')
    report(mix, stems)
    pcm = np.clip(np.round(mix * 32767), -32768, 32767).astype('<i2')
    with wave.open(os.path.join(HERE, 'lab_materials.wav'), 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    spectrogram(mix, os.path.join(HERE, 'spectrogram.png'))


if __name__ == '__main__':
    main()
