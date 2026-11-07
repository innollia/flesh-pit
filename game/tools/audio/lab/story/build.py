# -*- coding: utf-8 -*-
"""
lab_story build: the sound comes only from nkido (story.akkado).
Python here does three things: run the renderer, fold the loop, measure.

The loop: render two passes plus a little. The second pass already carries the
first pass's reverb and release tails, so it is the piece in steady state. Its
tail past the end is folded back over its own head (no cutting).
"""
import os
import struct
import subprocess
import wave
import zlib
import numpy as np
import scipy.fft as sf
import scipy.io.wavfile as wf
import scipy.signal as ss

OUT = os.path.dirname(os.path.abspath(__file__))
NKIDO = r'C:\projects\_tools\nkido\build-clang\bin\nkido.exe'
SR = 48000
BARS = 40
BAR = 2.5
EI = BAR / 7.0
N = int(round(BARS * BAR * SR))
FOLD = int(0.14 * SR)
TARGET = -28.0


def tb(bar):
    return bar * BAR


def render():
    raw = os.path.join(OUT, '_raw.wav')
    secs = 2 * N / SR + FOLD / SR + 0.5
    subprocess.run([NKIDO, 'render', os.path.join(OUT, 'story.akkado'), '-o', raw, '--float32', '--seconds', str(secs),
                    '--rate', str(SR), '--bpm', '24', '--no-default-bank'], check=True)
    sr, x = wf.read(raw)
    assert sr == SR
    os.remove(raw)
    return x.astype(np.float64)


def fold(x):
    seg = x[N:2 * N + FOLD]
    print('raw peak %.3f, rail hits %d, dc %s' % (np.abs(x).max(), int(np.sum(np.abs(x) >= 0.9999)), seg.mean(0)))
    hot = np.argsort(np.abs(seg[:N]).max(1))[-200:] / SR
    print('hottest moments (s):', np.unique(np.round(hot, 1))[:30])
    y = seg[:N].copy()
    t = (np.arange(FOLD) + 0.5) / FOLD
    a = np.sin(t * np.pi / 2)[:, None]
    b = np.cos(t * np.pi / 2)[:, None]
    y[:FOLD] = y[:FOLD] * a + seg[N:N + FOLD] * b
    return y - y.mean(0)


def k_filter(x):
    b1 = [1.53512485958697, -2.69169618940638, 1.19839281085285]
    a1 = [1.0, -1.69065929318241, 0.73248077421585]
    b2 = [1.0, -2.0, 1.0]
    a2 = [1.0, -1.99004745483398, 0.99007225036621]
    return ss.lfilter(b2, a2, ss.lfilter(b1, a1, x, axis=0), axis=0)


def lufs(x):
    y = k_filter(np.concatenate([x, x], 0))[len(x):]
    h, b = int(0.1 * SR), int(0.4 * SR)
    e = np.sum(y ** 2, axis=1)
    c = np.concatenate([[0], np.cumsum(e)])
    p = (c[b::h] - c[:-b:h][:len(c[b::h])]) / b
    L = -0.691 + 10 * np.log10(p + 1e-14)
    a = p[L > -70]
    g = -0.691 + 10 * np.log10(a.mean()) - 10
    return -0.691 + 10 * np.log10(p[L > g].mean())


def report(x):
    print('integrated LUFS %.2f' % lufs(x))
    ov = ss.resample_poly(np.concatenate([x[-200:], x, x[:200]]), 4, 1, axis=0)
    print('sample peak %.2f dBFS, true peak %.2f dBTP' % (20 * np.log10(np.abs(x).max()), 20 * np.log10(np.abs(ov).max())))
    print('L/R correlation %.3f, DC %s' % (np.corrcoef(x[:, 0], x[:, 1])[0, 1], x.mean(0)))
    mono = x.mean(1)
    X = np.abs(sf.rfft(mono)) ** 2
    f = np.fft.rfftfreq(len(mono), 1 / SR)
    edges = [0, 60, 150, 500, 2000, 6000, 12000, 18000, 24000]
    tot = X.sum()
    print('band share (dB rel total):')
    for a, b in zip(edges[:-1], edges[1:]):
        print('  %5d-%5d  %6.1f' % (a, b, 10 * np.log10(X[(f >= a) & (f < b)].sum() / tot + 1e-16)))
    print('section: K-rms, then dB share <60, 150-2k, 2k-6k, 6k+')
    y = k_filter(np.concatenate([x, x], 0))[len(x):]
    for name, a, b in (('room', 0, 8), ('drop', 8, 16), ('trek1', 16, 24), ('trek2', 24, 28), ('grate', 28, 34), ('climb', 34, 38), ('hang', 38, 40)):
        s0, s1 = int(tb(a) * SR), int(tb(b) * SR)
        L = -0.691 + 10 * np.log10(np.mean(np.sum(y[s0:s1] ** 2, axis=1)) + 1e-14)
        S = np.abs(sf.rfft(mono[s0:s1])) ** 2
        ff = np.fft.rfftfreq(s1 - s0, 1 / SR)
        t_ = S.sum()
        print('  %-6s %6.1f  %6.1f %6.1f %6.1f %6.1f' % (name, L,
              10 * np.log10(S[ff < 60].sum() / t_ + 1e-16), 10 * np.log10(S[(ff >= 150) & (ff < 2000)].sum() / t_ + 1e-16),
              10 * np.log10(S[(ff >= 2000) & (ff < 6000)].sum() / t_ + 1e-16), 10 * np.log10(S[ff >= 6000].sum() / t_ + 1e-16)))
    print('level per bar (K rms dB):')
    bs = int(BAR * SR)
    print(' '.join('%.0f' % (-0.691 + 10 * np.log10(np.mean(np.sum(y[i:i + bs] ** 2, axis=1)) + 1e-14)) for i in range(0, len(y), bs)))
    q_ = int(0.25 * SR)
    r_ = np.roll(mono, 2 * SR)
    print('rms per 250 ms across seam (-2..+2 s):', ' '.join('%.0f' % (20 * np.log10(np.sqrt(np.mean(r_[i:i + q_] ** 2)) + 1e-9)) for i in range(0, 4 * SR, q_)))
    d = np.abs(np.diff(x, axis=0))
    jump = np.abs(x[0] - x[-1])
    print('seam jump', jump, ' median diff', np.median(d, axis=0), ' p99.9 diff', np.percentile(d, 99.9, axis=0))
    print('loop_jump_ratio %.2f' % (jump.max() / (np.percentile(d, 99.9) + 1e-12)))
    w = int(0.02 * SR)
    a_ = np.concatenate([x[-w:], x[:w]], 0)
    print('rms before/after seam 20 ms: %.1f / %.1f dB' % (20 * np.log10(np.sqrt(np.mean(a_[:w] ** 2))), 20 * np.log10(np.sqrt(np.mean(a_[w:] ** 2)))))
    hp = ss.butter(4, 3000, 'highpass', fs=SR, output='sos')
    r = ss.sosfiltfilt(hp, np.roll(mono, len(mono) // 2))
    c = len(r) // 2
    print('HF (>3k) at seam 4 ms %.1f dB vs nearby 400 ms %.1f dB' % (20 * np.log10(np.sqrt(np.mean(r[c - 96:c + 96] ** 2)) + 1e-12),
                                                                    20 * np.log10(np.sqrt(np.mean(r[c - 9600:c + 9600] ** 2)) + 1e-12)))
    png_spectrogram(mono, os.path.join(OUT, 'lab_story_spectrogram.png'))


def png_spectrogram(mono, path):
    """Log-frequency spectrogram (30 Hz-22 kHz) over a level strip, written with zlib only.
    White ticks mark section starts."""
    W, H, LV = 1400, 620, 120
    fr, tt, S = ss.spectrogram(mono, SR, nperseg=8192, noverlap=8192 - int(len(mono) / W), window='hann')
    db = 10 * np.log10(S + 1e-14)
    ys = np.exp(np.linspace(np.log(22000), np.log(30), H))
    col = np.minimum(np.searchsorted(fr, ys), len(fr) - 1)
    im = db[col][:, :W]
    v = np.clip((im + 125) / 75, 0, 1)
    rgb = np.stack([np.clip(v * 1.7, 0, 1), np.clip(v * 1.9 - 0.7, 0, 1), np.clip(v * 3 - 2.2, 0, 1) + 0.25 * np.clip(0.5 - np.abs(v - 0.3), 0, 1)], 2)
    img = np.ones((H + LV, im.shape[1], 3))
    img[:H] = np.clip(rgb, 0, 1)
    w = im.shape[1]
    hop = len(mono) // w
    lv = np.array([10 * np.log10(np.mean(mono[i * hop:(i + 1) * hop] ** 2) + 1e-12) for i in range(w)])
    row = np.clip(((-10 - lv) / 55 * (LV - 1)).astype(int), 0, LV - 1)
    img[H + row, np.arange(w)] = [0, 0, 0]
    for b in (8, 16, 24, 28, 34, 38):
        x_ = int(tb(b) / (BARS * BAR) * w)
        img[:, x_] = [1, 1, 1]
    for f_ in (100, 1000, 10000):
        y_ = int(np.log(22000 / f_) / np.log(22000 / 30) * H)
        img[y_, ::6] = [0.7, 0.9, 1]
    raw = (img * 255).astype(np.uint8)
    h_, w_ = raw.shape[:2]
    body = b''.join(bytes([0]) + raw[i].tobytes() for i in range(h_))

    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d))
    with open(path, 'wb') as f:
        f.write(bytes([137, 80, 78, 71, 13, 10, 26, 10]) + chunk(b'IHDR', struct.pack('>IIBBBBB', w_, h_, 8, 2, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(body, 6)) + chunk(b'IEND', b''))


def main():
    y = fold(render())
    l = lufs(y)
    y *= 10 ** ((TARGET - l) / 20)
    ov = ss.resample_poly(np.concatenate([y[-200:], y, y[:200]]), 4, 1, axis=0)
    tp = np.abs(ov).max()
    limit = 10 ** (-1.2 / 20)
    if tp > limit:
        y *= limit / tp
        print('gain held down by peak; LUFS will read low')
    d = np.random.default_rng(99)
    q = 32767.0
    pcm = np.clip(np.round(y * q + d.random(y.shape) - d.random(y.shape)), -32768, 32767).astype('<i2')
    path = os.path.join(OUT, 'lab_story.wav')
    with wave.open(path, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print('wrote', path, len(pcm) / SR, 's; gain from raw %.1f dB' % (TARGET - l))
    report(pcm.astype(np.float64) / 32768.0)


if __name__ == '__main__':
    main()
