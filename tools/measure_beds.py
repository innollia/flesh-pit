# -*- coding: utf-8 -*-
"""Measures the flesh beds as the game mixes them, so a bed change can be
compared before and after in numbers (no ear in the loop).

    python -X utf8 tools/measure_beds.py --audio game/audio --out <dir> [--seconds 120]

--audio is any folder with manifest.json, loops/ and sfx/, so an old revision
checked out to a side folder measures the same way. For each bed in BEDS the
layers are summed as the Music bus plays them, plus the manifest's "bed_events"
one-shots at the gaps audio/fp_body_events.gd draws (one voice at a time, level
drawn from its range). Writes <out>/<bed>.wav and <out>/beds.json:

  spectrum    level-normalised third-octave profile, 150 Hz - 8 kHz, through
              SPEAKER (what a laptop passes), and each pair's mean distance dB
  separable   nearest-centroid on 3 s windows, half trains, half tests: how
              often a stretch of a bed is told from the others by spectrum
  range_db    400 ms level through SPEAKER, p95 - p10 over the whole take
  band_swing  mean over the bands of each band's p95 - p10 on 400 ms windows:
              a steady hiss scores low even when its level wobbles
  over_200    share of the bed's energy above 200 Hz, before SPEAKER
  masking     own-band margin (analyze_audio.masking_margin_db) of the game's
              constant sounds, median and worst of 24 places in the take
"""
import argparse
import json
import math
import os
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "game", "tools", "audio"))
import analyze_audio as A  # noqa: E402

RATE = 48000
BEDS = ["body_a", "body_b", "fat_caves", "rib_vault", "gut_folds", "cloth_wads", "hair_thicket"]
# settings defaults (main/scripts/fp_settings.gd): music 0.8, sfx 1.0
MUSIC_DB = 20.0 * math.log10(0.8)
# what the player does all the time in the flesh; first variation of each
MASK_EVENTS = ["tear_flesh", "tear_fat", "chew_loop_a", "step_flesh_s1", "swallow", "regen_creak", "stomach_gurgle"]
BANDS = [150.0 * 2 ** (i / 3.0) for i in range(17)]  # 150 Hz .. 7.6 kHz
# a laptop speaker, roughly: nothing under 200 Hz, rolling off above 12 kHz
SPEAKER = (200.0, 12000.0)


def read(path):
    with wave.open(path, "rb") as w:
        n = w.getnframes()
        ch = w.getnchannels()
        x = np.frombuffer(w.readframes(n), "<i2").astype(np.float64) / 32768.0
    x = x.reshape(-1, ch)
    return np.repeat(x, 2, axis=1) if ch == 1 else x


def res_path(audio, res):
    return os.path.join(audio, res.replace("res://audio/", "").replace("/", os.sep))


def speaker(x):
    f = np.fft.rfftfreq(len(x), 1.0 / RATE)
    g = 1.0 / np.sqrt(1.0 + (SPEAKER[0] / np.maximum(f, 1.0)) ** 8) / np.sqrt(1.0 + (f / SPEAKER[1]) ** 4)
    return np.fft.irfft(np.fft.rfft(x) * g, len(x))


def bed_mix(audio, manifest, bed, seconds):
    n = int(seconds * RATE)
    out = np.zeros((n, 2))
    for layer in manifest["beds"][bed]:
        x = read(res_path(audio, manifest["sounds"][layer]["files"][0]))
        out += np.tile(x, (n // len(x) + 1, 1))[:n]
    ev = manifest.get("bed_events", {}).get(bed)
    rng = np.random.default_rng(sum(map(ord, bed)))
    if ev:
        at = rng.uniform(*ev["first_gap"])
        takes = ev["takes"]
        last = ""
        while at < seconds:
            pool = [t for t in takes if t["id"] != last]
            take = pool[rng.integers(len(pool))]
            last = take["id"]
            files = manifest["sounds"][last]["files"]
            x = read(res_path(audio, files[rng.integers(len(files))]))
            db = rng.uniform(*take["db"])
            i = int(at * RATE)
            m = min(len(x), n - i)
            if m > 0:
                out[i:i + m] += x[:m] * 10.0 ** (db / 20.0)
            at += len(x) / RATE + rng.uniform(*ev["gap"])
    return out * 10.0 ** (MUSIC_DB / 20.0)


def bands_db(frames):
    """frames: (windows, samples). Third-octave levels in dB per window."""
    w = np.hanning(frames.shape[1])
    p = np.abs(np.fft.rfft(frames * w, axis=1)) ** 2
    f = np.fft.rfftfreq(frames.shape[1], 1.0 / RATE)
    out = []
    for lo in BANDS:
        m = (f >= lo) & (f < lo * 2 ** (1 / 3.0))
        out.append(p[:, m].sum(axis=1))
    return 10.0 * np.log10(np.stack(out, axis=1) + 1e-14)


def windows(x, size, hop):
    n = (len(x) - size) // hop + 1
    return np.stack([x[i * hop:i * hop + size] for i in range(n)])


def profile(mono):
    b = bands_db(windows(mono, 16384, 8192))
    lin = (10 ** (b / 10.0)).mean(axis=0)
    db = 10.0 * np.log10(lin + 1e-14)
    return db - db.mean()


def time_stats(mono):
    w = windows(mono, int(0.4 * RATE), int(0.1 * RATE))
    lv = 10.0 * np.log10((w ** 2).mean(axis=1) + 1e-14)
    full = np.percentile(lv, 95) - np.percentile(lv, 10)
    b = bands_db(windows(mono, 16384, 4800))
    swing = (np.percentile(b, 95, axis=0) - np.percentile(b, 10, axis=0)).mean()
    return float(full), float(swing)


def separable(shaped):
    """Train on the even 3 s windows of each bed, test on the odd ones."""
    size = 3 * RATE
    feats = {}
    for k, x in shaped.items():
        w = windows(x, size, size)
        b = bands_db(w[:, :2 ** 17])
        feats[k] = b - b.mean(axis=1, keepdims=True)
    cent = {k: v[::2].mean(axis=0) for k, v in feats.items()}
    keys = list(cent)
    C = np.stack([cent[k] for k in keys])
    hit = tot = 0
    per = {}
    for i, k in enumerate(keys):
        t = feats[k][1::2]
        d = np.abs(t[:, None, :] - C[None, :, :]).mean(axis=2)
        ok = int((d.argmin(axis=1) == i).sum())
        per[k] = ok / max(len(t), 1)
        hit += ok
        tot += len(t)
    return hit / max(tot, 1), per


def masking(audio, manifest, mix):
    """Own-band margin of each sound, median and worst of 24 places in the bed:
    one place would judge the event against whichever heartbeat it hit."""
    out = {}
    for ev in MASK_EVENTS:
        if ev not in manifest["sounds"]:
            continue
        e = read(res_path(audio, manifest["sounds"][ev]["files"][0]))
        got = []
        for k in range(24):
            i = k * (len(mix) - len(e) - 1) // 24
            got.append(float(A.masking_margin_db(e, RATE, mix[i:i + len(e)], RATE)["own_energy_weighted_margin_db"]))
        out[ev] = {"median": round(float(np.median(got)), 1), "worst": round(min(got), 1)}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--audio", default=os.path.join(HERE, "..", "game", "audio"))
    ap.add_argument("--out", required=True)
    ap.add_argument("--seconds", type=float, default=120.0)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.audio, "manifest.json"), encoding="utf-8") as f:
        manifest = json.load(f)
    res = {"beds": {}}
    prof = {}
    shaped = {}
    for bed in BEDS:
        mix = bed_mix(a.audio, manifest, bed, a.seconds)
        pcm = (np.clip(mix, -1, 1) * 32767).astype("<i2")
        with wave.open(os.path.join(a.out, bed + ".wav"), "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(pcm.tobytes())
        mono = mix.mean(axis=1)
        s = speaker(mono)
        shaped[bed] = s
        prof[bed] = profile(s)
        rng_db, swing = time_stats(s)
        spec = np.abs(np.fft.rfft(mono)) ** 2
        f = np.fft.rfftfreq(len(mono), 1.0 / RATE)
        res["beds"][bed] = {
            "lufs": round(float(A.integrated_lufs(mix, RATE)), 1),
            "lufs_speaker": round(float(A.integrated_lufs(np.stack([s, s], 1), RATE)), 1),
            "range_db": round(rng_db, 1), "band_swing_db": round(swing, 1),
            "over_200": round(float(spec[f >= 200].sum() / spec.sum()), 3),
            "masking": masking(a.audio, manifest, mix),
        }
    pairs = {}
    for i, p in enumerate(BEDS):
        for q in BEDS[i + 1:]:
            pairs[p + "/" + q] = round(float(np.abs(prof[p] - prof[q]).mean()), 2)
    res["pairs"] = pairs
    res["min_pair"] = min(pairs.items(), key=lambda kv: kv[1])
    res["mean_pair"] = round(float(np.mean(list(pairs.values()))), 2)
    acc, per = separable(shaped)
    res["separable"] = round(acc, 3)
    res["separable_per_bed"] = {k: round(v, 2) for k, v in per.items()}
    with open(os.path.join(a.out, "beds.json"), "w", encoding="utf-8") as f:
        json.dump(res, f, indent=1, ensure_ascii=False)
    print("bed            LUFS  spk   range swing >200   lowest margin (median / worst)")
    for k, v in res["beds"].items():
        worst = min(v["masking"].items(), key=lambda kv: kv[1]["median"])
        print("%-14s %5.1f %5.1f %5.1f %5.1f %5.3f  %s %.1f / %.1f" % (k, v["lufs"], v["lufs_speaker"], v["range_db"], v["band_swing_db"], v["over_200"], worst[0], worst[1]["median"], worst[1]["worst"]))
    print("pairs mean %.2f  min %s %.2f  separable %.3f" % (res["mean_pair"], res["min_pair"][0], res["min_pair"][1], acc))


if __name__ == "__main__":
    main()
