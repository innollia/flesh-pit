"""Render N seeded variations of one event patch and gate them against each
other, not just against the objective per-file checks.

A patch opts in by containing the literal token SEED somewhere in a noise()
call (see patches/kit_a_sideview_ecosystem/footstep_stone.akkado for the
shape: a separate low-level 'grit' signal added to the unchanged tone, so
the pitch and envelope -- the actual identity of the sound -- never move).
This substitutes a different integer for SEED per variation and renders
each one with nkido, exactly like build_audio.ps1 does for the base event.

Gate: level spread across variations must stay within 1.5 LU, and no two
variations may be spectrally identical (same defect build_audio.ps1's
channel_correlation check catches for stereo width -- here it is checked
across variations of the SAME mono signal instead).

Exit code 0 when every requested event's variations pass, 1 otherwise."""

import argparse
import json
import math
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analyze_audio  # noqa: E402

# Distinct, widely-spaced integers so two variations never fold to the same
# pattern (README 8.1: a constant difference alone can be folded by the
# compiler, so these are not just N, N+1, N+2).
SEEDS = [101, 907, 233, 619, 359, 811, 157, 733]


def render_variation(nkido_exe, template_text, seed, out_path, seconds, rate, bpm):
    # Only the default-seed BINDING line changes; every other bare SEED
    # reference in the patch stays as the identifier (akkado's single-
    # binding rule refuses a second assignment, so the template has exactly
    # one "SEED = <n>" line and this is the only line that may change).
    patched = template_text.replace("SEED = 101", "SEED = " + str(seed))
    scratch = out_path + ".src.akkado"
    with open(scratch, "w", encoding="utf-8") as handle:
        handle.write(patched)
    args = [nkido_exe, "render", scratch, "-o", out_path,
            "--seconds", str(seconds), "--rate", str(rate),
            "--bpm", str(bpm), "--no-default-bank"]
    result = subprocess.run(args, capture_output=True, text=True)
    os.remove(scratch)
    if result.returncode != 0:
        raise SystemExit(
            "nkido render failed for seed " + str(seed) + ": " + result.stdout + result.stderr
        )


def log_spectral_distance(a, b):
    """RMS distance between two signals' log-magnitude spectra, in dB.

    Byte-identity (np.allclose) only catches a seed that had NO effect at
    all. It cannot catch a seed that changed one sample by 0.1 dB and
    called it a day -- two renders that are technically different but
    read as the same sound. This measures how far apart the two spectra
    actually are, in the units a human would judge them by (dB), so a
    near-duplicate pair fails the same way a true duplicate does.
    """
    length = min(a.size, b.size)
    size = 1
    while size * 2 <= length:
        size *= 2
    if size < 64:
        return 0.0
    window = np.hanning(size)
    spec_a = np.abs(np.fft.rfft(a[:size] * window))
    spec_b = np.abs(np.fft.rfft(b[:size] * window))
    floor = max(spec_a.max(), spec_b.max(), 1e-9) * 1e-4
    log_a = np.log10(np.maximum(spec_a, floor))
    log_b = np.log10(np.maximum(spec_b, floor))
    return float(np.sqrt(np.mean((log_a - log_b) ** 2)) * 20.0)


# Below this, two variations read as the same render with rounding noise,
# not two different takes of the same grit layer. Calibrated against the
# selftest pairs in _selftest_spectral_distance() below: a genuinely
# different seed clears this by a wide margin, a near-duplicate does not.
SPECTRAL_DISTANCE_MIN_DB = 0.5


def check_variation_set(paths):
    """Level spread and pairwise spectral distance across N renders of one event."""
    measurements = [analyze_audio.measure(p) for p in paths]
    lufs_values = [m["integrated_lufs"] for m in measurements]
    finite = [v for v in lufs_values if v > -100.0]
    problems = []
    if len(finite) >= 2:
        spread = max(finite) - min(finite)
        if spread > 1.5:
            problems.append(
                "level spread across variations is %.2f LU, above 1.5" % spread
            )
    signals = []
    for p in paths:
        data, _ = analyze_audio.read_wav(p)
        signals.append(data.mean(axis=1))
    length = min(s.size for s in signals)
    for i in range(len(signals)):
        for j in range(i + 1, len(signals)):
            a = signals[i][:length]
            b = signals[j][:length]
            if np.allclose(a, b, atol=1e-6):
                problems.append(
                    "variation %d and %d are byte-identical (seed had no effect)" % (i, j)
                )
                continue
            distance = log_spectral_distance(a, b)
            if distance < SPECTRAL_DISTANCE_MIN_DB:
                problems.append(
                    "variation %d and %d are %.3f dB apart in log-spectrum, below %.2f -- too similar to read as different takes"
                    % (i, j, distance, SPECTRAL_DISTANCE_MIN_DB)
                )
    return problems


def _selftest_spectral_distance():
    """A near-duplicate pair (same seed, 0.1 dB gain nudge) must trip the
    floor; a genuinely different pair (different noise seed) must clear it
    by a wide margin. Exit 0/1 like analyze_audio.py --selftest."""
    rate = 48000
    frames = 4096

    def lcg_noise(seed, n):
        state = seed
        out = np.empty(n)
        for i in range(n):
            state = (1103515245 * state + 12345) & 0x7fffffff
            out[i] = (state / float(0x7fffffff)) * 2.0 - 1.0
        return out

    tone = np.array([math.sin(2.0 * math.pi * 440.0 * i / rate) for i in range(frames)])
    noise_a = lcg_noise(101, frames)
    noise_b = lcg_noise(907, frames)
    same_seed = tone * 0.8 + noise_a * 0.05
    same_seed_nudged = tone * 0.8 * (10 ** (0.1 / 20.0)) + noise_a * 0.05
    different_seed = tone * 0.8 + noise_b * 0.05

    failures = []
    near = log_spectral_distance(same_seed, same_seed_nudged)
    if near >= SPECTRAL_DISTANCE_MIN_DB:
        failures.append(
            "selftest: same-seed + 0.1dB nudge measured %.3f dB apart, expected below the %.2f floor (should read as a near-duplicate)"
            % (near, SPECTRAL_DISTANCE_MIN_DB)
        )
    far = log_spectral_distance(same_seed, different_seed)
    if far < SPECTRAL_DISTANCE_MIN_DB:
        failures.append(
            "selftest: different-seed pair measured %.3f dB apart, expected at/above the %.2f floor (should read as genuinely different)"
            % (far, SPECTRAL_DISTANCE_MIN_DB)
        )
    for f in failures:
        print("  FAIL " + f, file=sys.stderr)
    if not failures:
        print("  render_variations selftest: near-duplicate rejected, distinct pair accepted")
    return 1 if failures else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--events", help="path to audio_events.json")
    parser.add_argument("--pipeline-root", help="")
    parser.add_argument("--nkido", help="")
    parser.add_argument("--out-dir", help="")
    parser.add_argument("--rate", type=int, default=48000)
    parser.add_argument("--selftest", action="store_true", help="verify the spectral-distance floor and exit")
    args = parser.parse_args()

    if args.selftest:
        return _selftest_spectral_distance()

    if not (args.events and args.pipeline_root and args.nkido and args.out_dir):
        parser.error("--events, --pipeline-root, --nkido and --out-dir are required unless --selftest")

    with open(args.events, "r", encoding="utf-8") as handle:
        manifest = json.load(handle)

    os.makedirs(args.out_dir, exist_ok=True)
    failures = []
    checked_any = False
    for kit in manifest["kits"]:
        for event in kit["events"]:
            variations = int(event.get("variations", 1))
            if variations <= 1:
                continue
            checked_any = True
            patch_path = os.path.join(args.pipeline_root, event["akkado"])
            with open(patch_path, "r", encoding="utf-8") as handle:
                template = handle.read()
            if "SEED" not in template:
                failures.append(event["id"] + ": variations declared but patch has no SEED token")
                continue
            paths = []
            for k in range(variations):
                seed = SEEDS[k % len(SEEDS)]
                out_path = os.path.join(args.out_dir, event["id"] + "_v" + str(k) + ".wav")
                render_variation(
                    args.nkido, template, seed, out_path,
                    event["duration_seconds"], args.rate, event.get("bpm", 120.0),
                )
                paths.append(out_path)
            problems = check_variation_set(paths)
            if problems:
                failures.extend(event["id"] + ": " + p for p in problems)
                print("  FAIL " + event["id"])
                for p in problems:
                    print("    " + p)
            else:
                print("  PASS " + event["id"] + "  " + str(variations) + " variations")

    if not checked_any:
        print("  no events declare variations > 1")
    if failures:
        for f in failures:
            print("  FAIL  " + f, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
