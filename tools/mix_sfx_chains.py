# -*- coding: utf-8 -*-
"""Mixes the one-shots the game fires together into one file per variation,
so a chain can be measured and judged the way it is heard (round8-sfx).

    python -X utf8 tools/mix_sfx_chains.py <sfx dir> <out dir>

  knife_tear_v<n>  tear_flesh + scissors_snip in the same frame (fp_art_hookup
                   _on_torn with the knife), swallow 0.3 s later (the kit
                   director's swallow_delay). Both tear sounds at 0 dB.
  saw_tear_v<n>    tear_flesh + saw_stroke, swallow 0.3 s later.
  flush_chain_v<n> toilet_flush with the tank rattle (teeth_rattle; before
                   round8 coin_drop) every 0.22..0.45 s for 2.0 s (the hookup's
                   RATTLE_GAP, a fixed seeded draw), as the lever plays them.

The old build had no teeth_rattle: when <sfx dir> has none, coin_drop is used.
Writes 16-bit mono 48 kHz. Levels are the files' own (the game plays them at
0 dB); a simple sum, no bus effects.
"""
import os
import sys
import wave

import numpy as np

RATE = 48000


def read(path):
    with wave.open(path, "rb") as w:
        x = np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(np.float64) / 32768.0
        return x.reshape(-1, w.getnchannels()).mean(axis=1)


def write(path, x):
    peak = np.abs(x).max()
    if peak > 0.97:
        x = x * (0.97 / peak)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


def place(buf, x, at):
    i = int(round(at * RATE))
    need = i + len(x)
    if need > len(buf):
        buf = np.concatenate([buf, np.zeros(need - len(buf))])
    buf[i:i + len(x)] += x
    return buf


def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    f = lambda sid, n: os.path.join(src, "%s_v%d.wav" % (sid, n))
    rattle = "teeth_rattle" if os.path.exists(f("teeth_rattle", 1)) else "coin_drop"
    rng = np.random.default_rng(8)
    gaps = rng.uniform(0.22, 0.45, 32)
    for n in range(1, 5):
        for name, tool in (("knife_tear", "scissors_snip"), ("saw_tear", "saw_stroke")):
            b = np.zeros(RATE)
            b = place(b, read(f("tear_flesh", n)), 0.0)
            b = place(b, read(f(tool, n)), 0.0)
            b = place(b, read(f("swallow", n)), 0.3)
            write(os.path.join(out, "%s_v%d.wav" % (name, n)), b)
        b = np.zeros(RATE)
        b = place(b, read(f("toilet_flush", n)), 0.0)
        t, k = 0.0, 0
        while t < 2.0:
            b = place(b, read(f(rattle, (k % 4) + 1)), t)
            t += gaps[k]
            k += 1
        write(os.path.join(out, "flush_chain_v%d.wav" % n), b)
    print("chains ->", out, "(rattle:", rattle + ")")


if __name__ == "__main__":
    main()
