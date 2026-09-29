"""flesh-pit audio build. Renders every sound in sounds.json with nkido,
folds loops seamless (loopify.py), masters each file to its target loudness,
then gates the result with analyze_audio.py (thresholds in targets.json) plus
variation distinctness and masking over the real background beds.

Writes:
  game/audio/sfx/<id>_v<n>.wav, game/audio/loops/<id>.wav
  game/audio/manifest.json      runtime data read by FDKSoundBank
  game/audio/REPORT.md          PASS/FAIL per file and per check

Exit code 0 when every check passes, 1 when anything FAILs (the files are
still written, failures are recorded, nothing is hidden).

usage: python -X utf8 build_audio.py [--only id,id]
"""
import argparse
import itertools
import json
import math
import os
import subprocess
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import analyze_audio as A  # noqa: E402
import loopify  # noqa: E402
from render_variations import log_spectral_distance  # noqa: E402

GAME = os.path.normpath(os.path.join(HERE, "..", ".."))
AUDIO = os.path.join(GAME, "audio")
BUILD = os.path.join(HERE, "build")
NKIDO = r"C:\projects\_tools\nkido\build-clang\bin\nkido.exe"
PEAK_CEILING = -1.5  # master a little under the -1.0 gate so resampling cannot push it over


def render(patch_text, out_path, seconds, rate):
    src = out_path + ".src.akkado"
    with open(src, "w", encoding="utf-8", newline="\n") as f:
        f.write(patch_text)
    args = [NKIDO, "render", src, "-o", out_path, "--seconds", "%.3f" % seconds,
            "--rate", str(rate), "--bpm", "60", "--no-default-bank"]
    r = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace")
    os.remove(src)
    if r.returncode != 0 or not os.path.exists(out_path):
        raise RuntimeError("nkido render failed: " + (r.stdout + r.stderr)[-400:])


def write_wav(path, data, rate):
    data = np.clip(data, -1.0, 32767.0 / 32768.0)
    pcm = np.round(data * 32768.0).astype("<i2")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(data.shape[1])
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())


SAMPLES_SRC = os.path.join(HERE, "samples", "src")


def _resample_linear(mono, src_rate, dst_rate):
    if src_rate == dst_rate:
        return mono
    n_out = int(round(mono.shape[0] * dst_rate / float(src_rate)))
    x_old = np.arange(mono.shape[0], dtype=np.float64)
    x_new = np.linspace(0.0, mono.shape[0] - 1, n_out)
    return np.interp(x_new, x_old, mono)


def _biquad_lp(mono, rate, cutoff):
    """One-pole low-pass, run twice for a steeper roll-off."""
    a = math.exp(-2.0 * math.pi * cutoff / rate)
    for _ in range(2):
        y = np.empty_like(mono)
        prev = 0.0
        for i in range(mono.size):
            prev = (1 - a) * mono[i] + a * prev
            y[i] = prev
        mono = y
    return mono


def _biquad_hp(mono, rate, cutoff):
    """Complement of the one-pole low-pass, run twice."""
    for _ in range(2):
        mono = mono - _biquad_lp(mono, rate, cutoff)
    return mono


def load_real_layer(spec_entry, rate, seconds):
    """Load a CC0 recording window, resample/pitch/filter/gain it to mono,
    trim or loop-tile it to `seconds`, and return a (seconds*rate,) array
    ready to be summed under the synth layer. Returns None when the entry
    has no real_layer (pure synth, unchanged behaviour)."""
    if not spec_entry:
        return None
    path = os.path.join(SAMPLES_SRC, spec_entry["sample"])
    with wave.open(path, "rb") as w:
        ch = w.getnchannels(); src_rate = w.getframerate(); n = w.getnframes()
        raw = w.readframes(n)
    data = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    data = data.reshape(-1, ch)
    mono = data.mean(axis=1)
    off = int(round(spec_entry.get("offset_s", 0.0) * src_rate))
    dur = int(round(spec_entry.get("dur_s", seconds) * src_rate))
    mono = mono[off:off + dur]
    if mono.size == 0:
        return np.zeros(int(round(seconds * rate)))
    pitch = float(spec_entry.get("pitch", 1.0))
    eff_rate = rate / pitch if pitch else rate
    mono = _resample_linear(mono, src_rate, eff_rate)
    if "hp" in spec_entry:
        mono = _biquad_hp(mono, rate, float(spec_entry["hp"]))
    if "lp" in spec_entry:
        mono = _biquad_lp(mono, rate, float(spec_entry["lp"]))
    target_n = int(round(seconds * rate))
    if mono.size >= target_n:
        # short fade at both ends so a trim never clicks
        out = mono[:target_n].copy()
    else:
        out = np.zeros(target_n)
        out[:mono.size] = mono
    fade_n = min(int(round(0.01 * rate)), out.size // 2) or 1
    fade = np.linspace(0.0, 1.0, fade_n)
    out[:fade_n] *= fade
    out[-fade_n:] *= fade[::-1]
    gain = 10.0 ** (float(spec_entry.get("gain_db", 0.0)) / 20.0)
    return out * gain


def remove_dc(data, rate, is_loop):
    """DC removal is mastering, not a gate change. A loop only gets its mean
    subtracted (a constant keeps the wrap seamless); a one-shot gets a
    one-pole 20 Hz high-pass so the start from silence stays click-free."""
    if is_loop:
        return data - data.mean(axis=0, keepdims=True)
    a = math.exp(-2.0 * math.pi * 20.0 / rate)
    out = np.empty_like(data)
    for c in range(data.shape[1]):
        x = data[:, c]
        y = np.empty_like(x)
        prev_x = 0.0
        prev_y = 0.0
        for i in range(x.size):
            prev_y = a * (prev_y + x[i] - prev_x)
            prev_x = x[i]
            y[i] = prev_y
        out[:, c] = y
    return out


def master(data, rate, target_lufs):
    lufs = A.integrated_lufs(data, rate)
    if not math.isfinite(lufs):
        return data, lufs, 0.0
    gain_db = target_lufs - lufs
    out = data * (10.0 ** (gain_db / 20.0))
    tp = A.true_peak_dbfs(out, rate)
    if tp > PEAK_CEILING:
        cut = PEAK_CEILING - tp
        out = out * (10.0 ** (cut / 20.0))
        gain_db += cut
    return out, lufs, gain_db


def variant_patch(text, seed, seed2, pitch):
    return (text.replace("SEED = 101", "SEED = %d" % seed)
                .replace("SEED2 = 211", "SEED2 = %d" % seed2)
                .replace("PITCH = 1.0", "PITCH = %s" % repr(pitch)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    args = ap.parse_args()
    spec = json.load(open(os.path.join(HERE, "sounds.json"), encoding="utf-8"))
    targets = json.load(open(os.path.join(HERE, "targets.json"), encoding="utf-8"))
    rate = int(spec["rate"])
    only = set(x for x in args.only.split(",") if x)
    os.makedirs(BUILD, exist_ok=True)

    selftest = subprocess.run([sys.executable, "-X", "utf8", os.path.join(HERE, "analyze_audio.py"), "--selftest"],
                              capture_output=True, text=True, cwd=BUILD)
    if selftest.returncode != 0:
        print(selftest.stdout[-800:], selftest.stderr[-800:])
        raise SystemExit("analyzer selftest failed; the gate is not trustworthy")

    stem_limits = dict(targets["stem"])
    na = [n.replace("_", " ") for n in targets["sfx_not_applicable"]]
    var_t = targets["variation"]
    mask_min = float(targets["masking"]["min_margin_db"])

    rows = []  # (file, status, detail)
    runtime = {"version": 1, "rate": rate, "sounds": {}}
    loop_paths = {}
    sfx_files = {}

    for s in spec["sounds"]:
        sid = s["id"]
        patch = open(os.path.join(HERE, "patches", sid + ".akkado"), encoding="utf-8").read()
        if s["kind"] == "loop":
            loop = float(s["loop_seconds"]); fade = float(s["fade_seconds"])
            raw = os.path.join(BUILD, sid + "_raw.wav")
            folded = os.path.join(BUILD, sid + "_fold.wav")
            if not only or sid in only:
                render(patch, raw, loop + fade + 0.25, rate)
                loopify.fold_file(raw, folded, int(round(loop * rate)), int(round(fade * rate)), quiet=True)
            data, r = A.read_wav(folded)
            real = load_real_layer(s.get("real_layer"), rate, loop)
            if real is not None:
                pad = np.zeros((data.shape[0], data.shape[1]))
                take = min(real.size, data.shape[0])
                pad[:take, :] += real[:take, None]
                data = data + pad
            rot = int(round(float(s.get("rotate_seconds", 0.0)) * rate))
            if rot:
                # move the wrap point into the quiet gap between two bites
                data = np.roll(data, -rot, axis=0)
            data = remove_dc(data, rate, True)
            out, raw_lufs, gain = master(data, rate, float(s["target_lufs"]))
            rel = "audio/loops/%s.wav" % sid
            write_wav(os.path.join(GAME, rel), out, rate)
            loop_paths[sid] = os.path.join(GAME, rel)
            runtime["sounds"][sid] = {"kind": "loop", "files": ["res://" + rel], "loop_seconds": loop}
        else:
            files = []
            cands = []
            for c, (seed, seed2, pitch) in enumerate(spec["variations"], start=1):
                raw = os.path.join(BUILD, "%s_c%d_raw.wav" % (sid, c))
                if not only or sid in only:
                    render(variant_patch(patch, seed, seed2, pitch), raw, float(s["seconds"]), rate)
                data, r = A.read_wav(raw)
                mono = data.mean(axis=1, keepdims=True)
                cands.append((A.integrated_lufs(mono, rate), mono))
            keep = int(spec.get("variations_keep", 4))
            best = None
            for combo in itertools.combinations(range(len(cands)), keep):
                lv = [cands[i][0] for i in combo]
                if not all(math.isfinite(v) for v in lv):
                    continue
                spread_c = max(lv) - min(lv)
                dmin = min(log_spectral_distance(cands[i][1][:, 0], cands[j][1][:, 0]) for i, j in itertools.combinations(combo, 2))
                ok = dmin >= var_t["spectral_distance_min_db"]
                key = (0 if ok else 1, spread_c)
                if best is None or key < best[0]:
                    best = (key, combo)
            chosen = best[1] if best else tuple(range(keep))
            raw_lufs_list = [cands[i][0] for i in chosen]
            mono_list = [cands[i][1][:, 0] for i in chosen]
            real = load_real_layer(s.get("real_layer"), rate, float(s["seconds"]))
            for n, i in enumerate(chosen, start=1):
                mono = cands[i][1]
                if real is not None:
                    take = min(real.size, mono.shape[0])
                    mono = mono.copy()
                    mono[:take, 0] += real[:take]
                out, _, gain = master(remove_dc(mono, rate, False), rate, float(s["target_lufs"]))
                rel = "audio/sfx/%s_v%d.wav" % (sid, n)
                write_wav(os.path.join(GAME, rel), out, rate)
                files.append(rel)
            sfx_files[sid] = files
            runtime["sounds"][sid] = {"kind": "sfx", "files": ["res://" + f for f in files],
                                      "spatial": bool(s.get("spatial", False))}
            # variation gate on raw renders
            finite = [x for x in raw_lufs_list if math.isfinite(x)]
            spread = (max(finite) - min(finite)) if finite else float("inf")
            dists = []
            for i in range(len(mono_list)):
                for j in range(i + 1, len(mono_list)):
                    dists.append(log_spectral_distance(mono_list[i], mono_list[j]))
            problems = []
            if spread > var_t["level_spread_max_lu"]:
                problems.append("level spread %.2f LU > %.1f" % (spread, var_t["level_spread_max_lu"]))
            if min(dists) < var_t["spectral_distance_min_db"]:
                problems.append("closest variations %.2f dB apart < %.1f" % (min(dists), var_t["spectral_distance_min_db"]))
            rows.append((sid + " (variations)", "FAIL" if problems else "PASS",
                         "; ".join(problems) or "spread %.2f LU, min distance %.2f dB" % (spread, min(dists))))

    # per-file objective gate
    for s in spec["sounds"]:
        sid = s["id"]
        paths = [loop_paths[sid]] if s["kind"] == "loop" else [os.path.join(GAME, f) for f in sfx_files[sid]]
        for p in paths:
            m = A.measure(p)
            probs = A.judge(m, stem_limits)
            skipped = []
            if s["kind"] == "sfx":
                keep = []
                for pr in probs:
                    if any(key in pr for key in na):
                        skipped.append(pr)
                    else:
                        keep.append(pr)
                probs = keep
            detail = "LUFS %.1f, TP %.1f, DC %.4f" % (m["integrated_lufs"], m["true_peak_dbfs"], m["dc_offset"])
            if s["kind"] == "loop":
                detail += ", wrap %.2f, corr %.2f, tick %.1f dB" % (m["loop"]["jump_ratio"], m["channel_correlation"], m.get("repetition_tick_db", float("nan")))
            rows.append((os.path.relpath(p, GAME).replace("\\", "/"), "FAIL" if probs else "PASS",
                         ("; ".join(probs) + " | " if probs else "") + detail))

    # masking over the real beds (both at mastered level)
    beds = {}
    for bed_id, layers in spec.get("beds", {}).items():
        mix = None
        for layer in layers:
            d = A.read_wav(loop_paths[layer])[0]
            if d.shape[1] == 1:
                d = np.repeat(d, 2, axis=1)
            mix = d if mix is None else mix[:min(len(mix), len(d))] + d[:min(len(mix), len(d))]
        beds[bed_id] = mix
    runtime["beds"] = spec.get("beds", {})
    for s in spec["sounds"]:
        for bed in s.get("bed", []):
            if bed not in beds:
                continue
            paths = [loop_paths[s["id"]]] if s["kind"] == "loop" else [os.path.join(GAME, f) for f in sfx_files[s["id"]]]
            worst = None
            for p in paths:
                ev, r = A.read_wav(p)
                mg = A.masking_margin_db(ev, r, beds[bed], rate).get("own_energy_weighted_margin_db")
                if mg is not None and (worst is None or mg < worst):
                    worst = mg
            status = "PASS" if worst is not None and worst >= mask_min else "FAIL"
            rows.append(("mask %s over %s" % (s["id"], bed), status, "worst margin %.1f dB (min %.0f)" % (worst if worst is not None else float("nan"), mask_min)))

    with open(os.path.join(AUDIO, "manifest.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(runtime, f, indent=1, ensure_ascii=False)
        f.write("\n")
    npass = sum(1 for r in rows if r[1] == "PASS"); nfail = len(rows) - npass
    lines = ["# flesh-pit audio build report", "", "Generated by game/tools/audio/build_audio.py. Thresholds: game/tools/audio/targets.json (copied from TINProject nkido_pipeline, not relaxed).", "",
             "PASS %d / FAIL %d" % (npass, nfail), "", "| item | result | detail |", "|---|---|---|"]
    for r in rows:
        lines.append("| %s | %s | %s |" % r)
    with open(os.path.join(AUDIO, "REPORT.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    for r in rows:
        if r[1] == "FAIL":
            print("FAIL", r[0], "--", r[2])
    print("PASS %d FAIL %d" % (npass, nfail))
    return 1 if nfail else 0


if __name__ == "__main__":
    sys.exit(main())
