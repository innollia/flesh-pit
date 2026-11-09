# -*- coding: utf-8 -*-
"""Character numbers for one-shots (round8-sfx). Numbers, not an ear.

    python -X utf8 tools/measure_sfx_char.py <wav> [<wav> ...]
    python -X utf8 tools/measure_sfx_char.py --png <dir> <wav> ...   # spectrograms too

Per file (left+right mean, 48 kHz):

  tone_db    strongest pitched line: the loud frames' mean power spectrum
             (4096 Hann), each bin over the median of the bins within a third
             of an octave around it, 150 Hz..8 kHz. A pure tone stands 25+ dB
             over its neighbours, broadband noise about 5..8 dB.
  tone_hz    where that line is.
  hi_tone_db the same restricted to 2..5 kHz (a whistle or a bird).
  hi_sweep   how far the 2..5 kHz line moves over the loud frames, in
             semitones, while it stays 12 dB over its neighbours (a rising
             whistle; 0 if there is no such line).
  hi_share   the most of any 100 ms (within 20 dB of the loudest) that lies
             over 2.5 kHz, dB of that window's energy (0 = all of it).
  click_db   sharpest spike over 2 kHz: a 1 ms RMS of the high-passed sound
             over the RMS of the 31 ms around it, dB, among the 1 ms windows
             within 20 dB of the loudest. A lone metal click scores 10+ dB, a
             wet crackle or a 10 ms swell a few dB (31 ms of one spike: 14.9).
  boom_db    sub-150 Hz punch: the peak 10 ms RMS under 150 Hz over the whole
             sound's peak 10 ms RMS, dB (0 = the loudest part is a low boom).
  boom_rise  how fast that sub-150 Hz peak comes up: ms from 10 % to its peak.
  clarity    pitch clarity (normalised autocorrelation 70 Hz..1 kHz, 50 ms
             after the peak), as run_audio_tests checks footsteps.
"""
import os
import sys
import wave
import zlib
import struct

import numpy as np

RATE = 48000


def read(path):
    with wave.open(path, "rb") as w:
        n = w.getnframes()
        sw = w.getsampwidth()
        raw = w.readframes(n)
        ch = w.getnchannels()
        sr = w.getframerate()
    if sw == 2:
        x = np.frombuffer(raw, "<i2").astype(np.float64) / 32768.0
    elif sw == 4:
        x = np.frombuffer(raw, "<f4").astype(np.float64)
    else:
        raise SystemExit("16-bit or float wav only")
    x = x.reshape(-1, ch).mean(axis=1)
    if sr != RATE:
        raise SystemExit("expected 48 kHz: %s" % path)
    return x


def biquad(x, kind, hz, q=0.7071):
    w = 2 * np.pi * hz / RATE
    a = np.sin(w) / (2 * q)
    c = np.cos(w)
    if kind == "lp":
        b = [(1 - c) / 2, 1 - c, (1 - c) / 2]
    else:
        b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
    a0 = 1 + a
    b = [v / a0 for v in b]
    a1, a2 = -2 * c / a0, (1 - a) / a0
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(x):
        o = b[0] * v + b[1] * x1 + b[2] * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, o
        y[i] = o
    return y


def win_rms(x, win):
    n = len(x) // win
    if n == 0:
        return np.zeros(1)
    return np.sqrt((x[:n * win].reshape(n, win) ** 2).mean(axis=1) + 1e-20)


def stft(x, n=4096, hop=1024):
    w = np.hanning(n)
    if len(x) < n:
        x = np.pad(x, (0, n - len(x)))
    frames = [x[i:i + n] * w for i in range(0, len(x) - n + 1, hop)]
    return np.abs(np.fft.rfft(np.array(frames), axis=1)) ** 2


def prominence(spec_db, freqs, lo, hi):
    best, best_f = -99.0, 0.0
    idx = np.where((freqs >= lo) & (freqs <= hi))[0]
    for i in idx:
        f = freqs[i]
        nb = np.where((freqs >= f / 1.26) & (freqs <= f * 1.26))[0]
        p = spec_db[i] - np.median(spec_db[nb])
        if p > best:
            best, best_f = p, f
    return best, best_f


def measure(x):
    out = {}
    S = stft(x)
    freqs = np.fft.rfftfreq(4096, 1 / RATE)
    fe = S.sum(axis=1)
    loud = fe > fe.max() * 10 ** (-20 / 10)
    mean_db = 10 * np.log10(S[loud].mean(axis=0) + 1e-20)
    out["tone_db"], out["tone_hz"] = prominence(mean_db, freqs, 150, 8000)
    out["hi_tone_db"], _ = prominence(mean_db, freqs, 2000, 5000)
    # a moving 2..5 kHz line, frame by frame
    track = []
    for k in np.where(loud)[0]:
        fdb = 10 * np.log10(S[k] + 1e-20)
        p, f = prominence(fdb, freqs, 2000, 5000)
        if p > 12:
            track.append(f)
    out["hi_sweep"] = 12 * np.log2(max(track) / min(track)) if len(track) >= 3 else 0.0
    # the most of any 100 ms that sits over 2.5 kHz (a hiss or a whistle on top)
    hop = 4800
    shares = []
    tops = []
    for i in range(0, max(len(x) - hop + 1, 1), hop):
        f = np.abs(np.fft.rfft(x[i:i + hop] * np.hanning(min(hop, len(x[i:i + hop]))))) ** 2
        fr = np.fft.rfftfreq(len(x[i:i + hop]), 1 / RATE)
        tops.append(f.sum())
        shares.append(f[fr >= 2500].sum() / (f.sum() + 1e-20))
    tops = np.array(tops)
    shares = np.array(shares)
    keep = tops > tops.max() * 10 ** (-20 / 10)
    out["hi_share"] = 10 * np.log10(shares[keep].max() + 1e-12)
    # click over 2 kHz
    h = biquad(x, "hp", 2000)
    e1 = win_rms(h, 48)
    best = 0.0
    loud_hi = e1 > e1.max() * 10 ** (-20 / 20)
    for i in np.where(loud_hi)[0]:
        ctx = e1[max(i - 15, 0):i + 16]
        best = max(best, 20 * np.log10(e1[i] / np.sqrt((ctx ** 2).mean())))
    out["click_db"] = best
    # sub-150 boom
    lo = biquad(biquad(x, "lp", 150), "lp", 150)
    el = win_rms(lo, 480)
    ea = win_rms(x, 480)
    out["boom_db"] = 20 * np.log10(el.max() / ea.max())
    e1l = win_rms(lo, 48)
    p = int(np.argmax(e1l))
    s = p
    while s > 0 and e1l[s] > e1l[p] * 0.1:
        s -= 1
    out["boom_rise"] = (p - s) * 1.0
    # pitch clarity (run_audio_tests._pitch_clarity)
    peak = int(np.argmax(np.abs(x)))
    seg = x[peak:peak + 2400]
    e0 = (seg ** 2).sum()
    best = 0.0
    if e0 > 0:
        for lag in range(48, 686, 2):
            best = max(best, (seg[:-lag] * seg[lag:]).sum() / e0)
    out["clarity"] = best
    out["dur"] = len(x) / RATE
    return out


def png(path, x):
    """Grey spectrogram, 0..12 kHz, 120 dB range to 60 dB, numpy + zlib."""
    S = stft(x, 1024, 256)
    freqs = np.fft.rfftfreq(1024, 1 / RATE)
    S = S[:, freqs <= 12000]
    db = 10 * np.log10(S + 1e-20)
    db = np.clip((db - (db.max() - 70)) / 70, 0, 1)
    img = (255 * (1 - db.T[::-1])).astype(np.uint8)
    h, w = img.shape
    rows = b"".join(b"\x00" + img[r].tobytes() for r in range(h))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(data)


def main():
    args = sys.argv[1:]
    png_dir = None
    if args and args[0] == "--png":
        png_dir = args[1]
        args = args[2:]
        os.makedirs(png_dir, exist_ok=True)
    keys = ["tone_db", "tone_hz", "hi_tone_db", "hi_sweep", "hi_share", "click_db", "boom_db", "boom_rise", "clarity"]
    print("%-28s " % "file" + " ".join("%10s" % k for k in keys))
    for p in args:
        x = read(p)
        m = measure(x)
        print("%-28s " % os.path.basename(p)[:28] + " ".join("%10.2f" % m[k] for k in keys))
        if png_dir:
            png(os.path.join(png_dir, os.path.splitext(os.path.basename(p))[0] + ".png"), x)


if __name__ == "__main__":
    main()
