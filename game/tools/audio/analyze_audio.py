"""Objective gate for rendered audio. The ear's measurable half.

Everything here is a number with a threshold, not a taste call. What it cannot
measure -- tension, fatigue, whether the room fits the scene -- stays with a
human play pass, and this file says so instead of guessing.

Reads 16-bit PCM WAV, stdlib + numpy. Per stem it checks what is true of the
stem: does not clip, peak fits, the loop wrap is inaudible, the spectrum is not
soup. For a mix it sums the active layers of one profile first and measures
integrated LUFS on the result, because LUFS is a programme measure and a single
stem's LUFS only says how loud the render was.

Exit code 0 when every target passes, 1 otherwise.
"""

import argparse
import array as array_module
import glob
import json
import math
import os
import struct
import sys
import wave

try:
    import numpy as np
except ImportError:
    sys.stderr.write("analyze_audio: numpy is required and is not installed\n")
    sys.exit(2)


# ITU-R BS.1770-4 K-weighting, the 48 kHz coefficient set. Stage 1 is the
# high-frequency shelf, stage 2 the high-pass. Both run as two poles, and we
# evaluate them by measuring their own impulse response rather than iterating a
# recursion, so a 3 M sample file costs a convolution instead of a Python loop.
_SHELF_B = (1.53512485958697, -2.69169618940638, 1.19839281085285)
_SHELF_A = (1.0, -1.69065929318241, 0.73248077421585)
_HPF_B = (1.0, -2.0, 1.0)
_HPF_A = (1.0, -1.99004745483398, 0.99007225036621)

_IMPULSE_TAPS = 8192
_GATE_BLOCK_SECONDS = 0.400
_GATE_OVERLAP = 0.75
_ABSOLUTE_GATE_LUFS = -70.0
_RELATIVE_GATE_LUFS = -10.0

_TRUE_PEAK_OVERSAMPLE = 4


# --------------------------------------------------------------------------
# io


def read_wav(path):
    with wave.open(path, "rb") as handle:
        channels = handle.getnchannels()
        width = handle.getsampwidth()
        rate = handle.getframerate()
        frames = handle.getnframes()
        raw = handle.readframes(frames)
    if width != 2:
        raise SystemExit("analyze_audio: %s is %d-bit, expected 16-bit" % (path, width * 8))
    data = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    if channels > 1:
        data = data.reshape(-1, channels)
    else:
        data = data.reshape(-1, 1)
    return data, rate


# --------------------------------------------------------------------------
# filters


def _biquad_ir(b, a, taps, rate):
    """Impulse response of a two-pole section, by running the recursion once."""
    impulse = np.zeros(taps)
    impulse[0] = 1.0
    out = np.zeros(taps)
    x1 = x2 = y1 = y2 = 0.0
    for n in range(taps):
        y = b[0] * impulse[n] + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
        out[n] = y
        x2, x1 = x1, impulse[n]
        y2, y1 = y1, y
    del rate
    return out


def _k_weighting_ir(rate):
    shelf = _biquad_ir(_SHELF_B, _SHELF_A, _IMPULSE_TAPS, rate)
    hpf = _biquad_ir(_HPF_B, _HPF_A, _IMPULSE_TAPS, rate)
    kernel = np.convolve(shelf, hpf)
    # The two poles settle in a few milliseconds. Convolving a 16 second file
    # against 8192 taps is billions of multiply-adds for nothing, so cut the
    # tail once it is 80 dB down and keep a margin for ringing.
    loud = np.max(np.abs(kernel))
    live = np.nonzero(np.abs(kernel) > loud * 1e-4)[0]
    end = int(live[-1]) + 32 if live.size else _IMPULSE_TAPS
    return kernel[: min(end, _IMPULSE_TAPS)]


def _k_weighted(data, rate):
    kernel = _k_weighting_ir(rate)
    weighted = np.empty_like(data)
    for channel in range(data.shape[1]):
        weighted[:, channel] = np.convolve(data[:, channel], kernel)[: data.shape[0]]
    return weighted


def integrated_lufs(data, rate):
    """BS.1770-4 gated integrated loudness. L and R each carry weight 1.0.

    The per-block figure is the *sum* of the weighted channel mean squares, not
    their average. Averaging instead of summing puts every stereo file 3 dB low
    and would make the gate agree with the wrong answer.
    """
    weighted = _k_weighted(data, rate)
    block = int(round(_GATE_BLOCK_SECONDS * rate))
    step = int(round(block * (1.0 - _GATE_OVERLAP)))
    if weighted.shape[0] < block:
        return float("-inf")
    block_energy = []
    for start in range(0, weighted.shape[0] - block + 1, step):
        window = weighted[start:start + block]
        block_energy.append(float(np.sum(np.mean(window * window, axis=0))))
    energies = np.array(block_energy)
    with np.errstate(divide="ignore"):
        loudness = -0.691 + 10.0 * np.log10(energies)
    keep = loudness > _ABSOLUTE_GATE_LUFS
    if not keep.any():
        return float("-inf")
    relative = -0.691 + 10.0 * math.log10(float(np.mean(energies[keep])))
    keep &= loudness > (relative + _RELATIVE_GATE_LUFS)
    if not keep.any():
        return float("-inf")
    return -0.691 + 10.0 * math.log10(float(np.mean(energies[keep])))


def linear_to_db(value):
    """0 maps to -inf, which is the silent end of a gain ramp."""
    if value <= 0.0:
        return float("-inf")
    return 20.0 * math.log10(value)


def _upsample(data, factor):
    """Windowed-sinc interpolation. Only used to look for inter-sample peaks.

    Zero-stuffing by `factor` divides the envelope by `factor`, so the gain has
    to be put back or every true peak reads `factor` too quiet.
    """
    taps = 16 * factor
    n = np.arange(taps) - (taps // 2)
    kernel = np.sinc(n / float(factor)) * np.blackman(taps * 2)[:taps]
    kernel *= factor / kernel.sum()
    stretched = np.zeros((data.shape[0] * factor, data.shape[1]))
    stretched[::factor] = data
    out = np.empty_like(stretched)
    for channel in range(data.shape[1]):
        out[:, channel] = np.convolve(stretched[:, channel], kernel, mode="same")
    return out


def true_peak_dbfs(data, rate):
    oversampled = _upsample(data, _TRUE_PEAK_OVERSAMPLE)
    peak = float(np.max(np.abs(oversampled))) if oversampled.size else 0.0
    del rate
    return 20.0 * math.log10(peak) if peak > 0.0 else float("-inf")


# --------------------------------------------------------------------------
# per-stem measurements


def loop_discontinuity(data):
    """How badly the wrap would click, relative to the signal's own slope.

    x[0] is supposed to continue x[n-1]. So the jump across the wrap should
    look like any other sample step. A ratio near 1 is invisible; a ratio of
    tens is an audible tick every time the loop turns over.

    A silent file has no slope to compare against and must not be allowed to
    divide by zero, so both ends of the ratio are guarded.
    """
    mono = data.mean(axis=1)
    if mono.size < 4:
        return {"jump_ratio": 0.0, "wrap_hf_dbfs": float("-inf")}
    steps = np.abs(np.diff(mono))
    typical = float(np.mean(steps))
    jump = abs(float(mono[0]) - float(mono[-1]))
    ratio = jump / typical if typical > 1e-9 else 0.0
    # Second difference isolates the top of the spectrum, which is where a
    # splice tick lives. Compare the wrap against the whole file.
    curvature = np.abs(np.diff(mono, n=2))
    window = max(2, int(round(0.002 * len(mono))))
    wrap = float(np.mean(curvature[:window])) if curvature.size >= window else float(np.mean(curvature))
    overall = float(np.mean(curvature)) if curvature.size else 0.0
    if wrap > 1e-12 and overall > 1e-12:
        wrap_hf = 20.0 * math.log10(wrap / overall)
    else:
        wrap_hf = 0.0
    return {"jump_ratio": ratio, "wrap_hf_dbfs": wrap_hf}


def octave_bands(data, rate):
    """Energy per octave band, as dB relative to the loudest band."""
    mono = data.mean(axis=1)
    if mono.size < 1024:
        return {}
    size = 1
    while size * 2 <= mono.size:
        size *= 2
    windowed = mono[:size] * np.hanning(size)
    spectrum = np.abs(np.fft.rfft(windowed)) ** 2
    freqs = np.fft.rfftfreq(size, 1.0 / rate)
    bands = {}
    for low in (20, 60, 150, 400, 1000, 2500, 6000):
        mask = (freqs >= low) & (freqs < low * 2)
        bands["%d-%d" % (low, low * 2)] = float(spectrum[mask].sum()) if mask.any() else 0.0
    peak = max(bands.values()) or 1.0
    return {name: 20.0 * math.log10(value / peak) if value > 0 else -120.0 for name, value in bands.items()}


def stereo_width_db(data):
    """Side energy over mid energy. 0 dB is normal full stereo, -120 is mono.

    Ambiguous on its own: half-signal content and independent content both land
    near 0 dB. `channel_correlation` is what actually tells the two apart, so
    both are reported.
    """
    if data.shape[1] < 2:
        return 0.0, 1.0
    left = data[:, 0]
    right = data[:, 1]
    mid = (left + right) * 0.5
    side = (left - right) * 0.5
    mid_energy = float(np.mean(mid * mid))
    side_energy = float(np.mean(side * side))
    width = 10.0 * math.log10(side_energy / mid_energy) if mid_energy > 1e-12 and side_energy > 0 else -120.0
    left_energy = float(np.mean(left * left))
    right_energy = float(np.mean(right * right))
    if left_energy <= 1e-12 or right_energy <= 1e-12:
        return width, 0.0
    return width, float(np.mean(left * right) / math.sqrt(left_energy * right_energy))


def repetition_tick_db(data, rate, period_seconds=(0.05, 0.5), frame_seconds=0.08,
                        hop_seconds=0.01, lowest_hz=20.0, smooth_seconds=1.0):
    """How strongly a short period repeats in the ENVELOPE, not the waveform.

    A loop that is meant to breathe over 8-16 seconds should not also tick
    every quarter-second -- that is a second, shorter loop hiding inside the
    render (an LFO that did not get snap_lfo'd, or an envelope retriggering
    on a fixed grid). The waveform itself repeats every pitch period by
    definition -- a 1 kHz tone is "self-similar" at every short lag, and that
    is timbre, not this defect -- so this measures the repetition of the
    ENERGY ENVELOPE instead.

    A single rectangular frame that is short relative to the signal's OWN
    pitch period does not measure envelope repetition at all: a 55 Hz tone
    has an ~18 ms cycle, so a bare 25 ms frame lands a different, arbitrary
    fraction of a cycle inside itself as it slides along, and that beat
    frequency shows up as fake RMS ripple that has nothing to do with any
    real defect. Guarding against this with an "was there really nothing to
    find" std-dev floor is a patch, not a fix, and it still trips on a plain
    held low tone with no LFO at all.

    The real fix is to make each analysis window long enough, relative to
    the lowest pitch period we care about, that it always averages over a
    whole number of cycles: at least `frame_seconds` (80 ms) AND at least 3x
    the period of `lowest_hz` (so a 20 Hz tone needs a >=150 ms window). This
    also needs to slide in small (`hop_seconds`, 10 ms) steps rather than
    tumble in frame-sized jumps, or the lag resolution of the envelope
    autocorrelation below would be too coarse for the requested
    `period_seconds` range. RMS is computed on each overlapping window; the
    envelope is what is left after subtracting a slow (~1 s) moving average
    so a genuine 8-16 s breath does not register as periodic, then that is
    autocorrelated. A steady tone or noise bed has a flat envelope there
    (nothing to autocorrelate); a click retriggering on a fixed grid does not.

    Returns dB below the envelope's own zero-lag energy. 0 dB (or thereabouts)
    means an obvious short repeat; very negative means none was found.
    """
    mono = data.mean(axis=1)
    n = mono.size
    window_seconds = max(frame_seconds, 3.0 * (1.0 / max(lowest_hz, 1e-6)))
    window_len = max(1, int(round(window_seconds * rate)))
    hop_len = max(1, int(round(hop_seconds * rate)))
    if n < window_len:
        return float("-inf")
    n_frames = 1 + (n - window_len) // hop_len
    if n_frames < 8:
        return float("-inf")
    starts = np.arange(n_frames) * hop_len
    idx = starts[:, None] + np.arange(window_len)[None, :]
    frames = mono[idx]
    # A rectangular window slides through the waveform at a rate not
    # commensurate with the signal's own pitch period, so each window
    # captures a different fraction of a leftover partial cycle at its
    # edges -- that alone produces RMS ripple with no real envelope defect
    # behind it (measured: a plain 55 Hz tone gave 0.10 dB of fake ripple
    # through a bare rectangular window here, comparable to a real but
    # subtle tick). Tapering each window with a Hann function before RMS
    # suppresses the edges instead, cutting that same ripple to ~0.0001 dB
    # -- as good as choosing a window length an exact multiple of the
    # period, but without needing to know the period in advance.
    taper = np.hanning(window_len)
    taper_rms = math.sqrt(float(np.mean(taper * taper))) if window_len > 1 else 1.0
    if taper_rms <= 1e-12:
        taper_rms = 1.0
    taper = taper / taper_rms
    tapered = frames * taper[None, :]
    rms = np.sqrt(np.mean(tapered * tapered, axis=1) + 1e-12)
    log_energy = 20.0 * np.log10(rms + 1e-9)
    frame_seconds_eff = hop_seconds
    lo_frame = max(1, int(round(period_seconds[0] / frame_seconds_eff)))
    hi_frame = min(n_frames - 1, int(round(period_seconds[1] / frame_seconds_eff)))
    if hi_frame <= lo_frame:
        return float("-inf")
    smooth_frames = max(1, int(round(smooth_seconds / frame_seconds_eff)))
    if smooth_frames > 1 and n_frames > smooth_frames:
        kernel = np.ones(smooth_frames) / smooth_frames
        # np.convolve(mode="same") implicitly zero-pads outside the signal.
        # log_energy sits around -10..-40 dB, never near 0, so mixing in
        # zeros at the edges drags the moving average sharply toward zero
        # there -- measured: a perfectly steady 55 Hz tone (envelope std
        # 0.0001 dB with proper edge handling) came out at 0.91 dB of fake
        # "envelope" with zero-padding, entirely from the first/last
        # smooth_frames/2 windows, comparable in size to a real tick. Pad
        # with edge-replication instead so the moving average has real
        # values to average at the boundary, not silence that was never in
        # the recording.
        pad = smooth_frames // 2
        padded = np.pad(log_energy, pad, mode="edge")
        slow = np.convolve(padded, kernel, mode="same")[pad:pad + n_frames]
    else:
        slow = np.full_like(log_energy, float(np.mean(log_energy)))
    envelope = log_energy - slow
    # A near-silent envelope (steady tone/noise, nothing left after removing
    # the slow trend) has nothing to find; guard division by a near-zero
    # zero-lag below, kept as a safety net now that the window fix is the
    # primary defense rather than this threshold.
    env_std = float(np.std(envelope))
    # The Hann taper (needed to kill the rectangular-window aliasing above)
    # trades away some effective sample length, which raises a white-noise
    # bed's own natural envelope std from ~0.03 to ~0.05 dB -- right at the
    # old 0.05 floor, so a clean noise bed started tripping this check as a
    # false positive. Measured against the three reference cases: a clean
    # noise bed sits at ~0.05 dB, a real periodic tick sits at ~1.7 dB, so
    # 0.15 clears the former with headroom while the latter is nowhere near
    # it.
    if env_std < 0.15:
        return float("-inf")
    windowed = envelope * np.hanning(n_frames)
    size = 1
    while size < 2 * n_frames:
        size *= 2
    spectrum = np.fft.rfft(windowed, n=size)
    autocorr = np.fft.irfft(spectrum * np.conj(spectrum), n=size)[:n_frames]
    zero_lag = float(autocorr[0])
    if zero_lag <= 1e-9:
        return float("-inf")
    corr_window = autocorr[lo_frame:hi_frame + 1] / zero_lag
    if corr_window.size == 0:
        return float("-inf")
    peak = float(np.max(np.abs(corr_window)))
    if peak <= 0.0:
        return float("-inf")
    return 20.0 * math.log10(peak)


def masking_margin_db(event_data, event_rate, bed_data, bed_rate):
    """Per-octave-band headroom of an event over a background bed, in dB.

    Sums the event's own spectrum and the bed's spectrum (both power, both
    normalized to the same duration by repeating the shorter one) and reports,
    band by band, how far the event's energy sits above the bed's in that
    band. A negative number means the bed already outweighs the event there
    -- the event would be buried at that frequency regardless of overall
    level, which octave_bands_db (single-file, no bed) cannot see at all.

    Also returns "own_energy_weighted_margin_db": the energy-weighted average
    margin restricted to the bands where the EVENT itself has energy (within
    12 dB of the event's own loudest band). A band the event never occupies
    (e.g. a 20-40 Hz rumble under a footstep with no low end) always loses to
    any bed there -- that is not masking, it is measuring silence. Judging the
    worst band across the whole spectrum conflates "buried" with "was never
    there"; this key answers the actual question, "is the event's own sound
    readable over the bed", and is what callers should gate on.
    """
    event_mono = event_data.mean(axis=1)
    bed_mono = bed_data.mean(axis=1)
    if event_rate != bed_rate:
        raise SystemExit("masking_margin_db: sample rates differ (%d vs %d)" % (event_rate, bed_rate))
    length = event_mono.size
    if length < 1024 or bed_mono.size < 1024:
        return {}
    if bed_mono.size < length:
        reps = int(math.ceil(length / float(bed_mono.size)))
        bed_mono = np.tile(bed_mono, reps)
    bed_mono = bed_mono[:length]
    size = 1
    while size * 2 <= length:
        size *= 2
    window = np.hanning(size)
    event_spec = np.abs(np.fft.rfft(event_mono[:size] * window)) ** 2
    bed_spec = np.abs(np.fft.rfft(bed_mono[:size] * window)) ** 2
    freqs = np.fft.rfftfreq(size, 1.0 / event_rate)
    margins = {}
    band_event_energy = {}
    for low in (20, 60, 150, 400, 1000, 2500, 6000):
        mask = (freqs >= low) & (freqs < low * 2)
        if not mask.any():
            continue
        event_energy = float(event_spec[mask].sum())
        bed_energy = float(bed_spec[mask].sum())
        band_event_energy["%d-%d" % (low, low * 2)] = event_energy
        if event_energy <= 0.0 and bed_energy <= 0.0:
            margins["%d-%d" % (low, low * 2)] = 0.0
        elif bed_energy <= 1e-12:
            margins["%d-%d" % (low, low * 2)] = 120.0
        else:
            margins["%d-%d" % (low, low * 2)] = 10.0 * math.log10(max(event_energy, 1e-15) / bed_energy)
    own_bands = [b for b, e in band_event_energy.items() if e > 0.0]
    if own_bands:
        loudest_energy = max(band_event_energy[b] for b in own_bands)
        loudest_db = 10.0 * math.log10(max(loudest_energy, 1e-15))
        occupied = [
            b for b in own_bands
            if 10.0 * math.log10(max(band_event_energy[b], 1e-15)) >= loudest_db - 12.0
        ]
        weights = [band_event_energy[b] for b in occupied]
        total_weight = sum(weights)
        if total_weight > 0.0:
            margins["own_energy_weighted_margin_db"] = sum(
                margins[b] * band_event_energy[b] for b in occupied
            ) / total_weight
    return margins


# --------------------------------------------------------------------------
# gate


def measure(path, rate=None):
    data, file_rate = read_wav(path)
    use_rate = rate or file_rate
    peak = float(np.max(np.abs(data))) if data.size else 0.0
    clipped = int(np.sum(np.abs(data) >= 0.999969))
    dc = float(np.mean(data)) if data.size else 0.0
    mono = data.mean(axis=1)
    rms = float(np.sqrt(np.mean(mono * mono))) if mono.size else 0.0
    width = stereo_width_db(data)
    return {
        "file": os.path.basename(path),
        "path": path,
        "channels": int(data.shape[1]),
        "sample_rate": int(file_rate),
        "frames": int(data.shape[0]),
        "seconds": data.shape[0] / float(file_rate),
        "peak_dbfs": 20.0 * math.log10(peak) if peak > 0 else float("-inf"),
        "rms_dbfs": 20.0 * math.log10(rms) if rms > 0 else float("-inf"),
        "integrated_lufs": integrated_lufs(data, file_rate),
        "clipped_samples": clipped,
        "dc_offset": dc,
        "true_peak_dbfs": true_peak_dbfs(data, file_rate),
        "stereo_width_db": width[0],
        "channel_correlation": width[1],
        "octave_bands_db": octave_bands(data, use_rate),
        "loop": loop_discontinuity(data),
        "repetition_tick_db": repetition_tick_db(data, use_rate),
    }


def stem_category(filename):
    """Classify a stem by its filename prefix into a loudness category.

    ambience: the amb_* beds. music_layer: the m_*_bass/harmony/melody
    layers that get crossfaded together (not the drums, which are
    percussive and read on peak, not integrated loudness). rhythmic: the
    drum layers and the bgm_* full songs. sfx: everything else (short,
    one-shot events like footsteps, impacts).
    """
    name = filename
    if name.startswith("amb_"):
        return "ambience"
    if name.startswith("m_") and (name.endswith("_drums.wav") or "_drums_" in name):
        return "rhythmic"
    if name.startswith("m_"):
        return "music_layer"
    if name.startswith("bgm_"):
        return "rhythmic"
    return "sfx"


def judge(measurement, targets):
    """Turn measurements into a list of failures. Empty list means it passed.

    Missing keys mean the limit is on, not off. A gate that silently relaxes
    when a field is missing is a gate that will pass anything.
    """
    problems = []
    limits = targets if targets is not None else {}
    category_windows = limits.get("category_lufs", {})
    category = stem_category(measurement["file"])
    window = category_windows.get(category)
    if window is not None:
        low, high = window
        if not (low <= measurement["integrated_lufs"] <= high):
            problems.append(
                "%s: category '%s' integrated loudness %.1f LUFS is outside %.1f..%.1f"
                % (measurement["file"], category, measurement["integrated_lufs"], low, high)
            )
    # A render that succeeds can still be silence. That is not a loudness
    # problem, it is a patch that asked for nothing.
    if limits.get("min_rms_dbfs", -60.0) > measurement["rms_dbfs"]:
        problems.append("%s: renders at %.1f dBFS RMS, effectively silent" % (measurement["file"], measurement["rms_dbfs"]))
    if limits.get("no_clipping", True) and measurement["clipped_samples"] > 0:
        problems.append("%s: %d clipped samples" % (measurement["file"], measurement["clipped_samples"]))
    peak_ceiling = limits.get("true_peak_max_db", -1.0)
    if measurement["true_peak_dbfs"] > peak_ceiling:
        problems.append(
            "%s: true peak %.2f dBFS is above %.2f" % (measurement["file"], measurement["true_peak_dbfs"], peak_ceiling)
        )
    dc_ceiling = limits.get("max_dc_offset", 0.002)
    if abs(measurement["dc_offset"]) > dc_ceiling:
        problems.append("%s: DC offset %.5f" % (measurement["file"], measurement["dc_offset"]))
    jump_ceiling = limits.get("loop_jump_ratio_max", 3.0)
    ratio = measurement["loop"]["jump_ratio"]
    if ratio > jump_ceiling:
        problems.append("%s: loop wrap jump ratio %.2f is above %.2f" % (measurement["file"], ratio, jump_ceiling))
    hf_ceiling = limits.get("loop_wrap_hf_max_db", 3.0)
    hf = measurement["loop"]["wrap_hf_dbfs"]
    if hf > hf_ceiling:
        problems.append("%s: loop wrap is %.1f dB brighter than the file" % (measurement["file"], hf))
    low_ceiling = limits.get("low_band_max_db", -3.0)
    bands = measurement["octave_bands_db"]
    if "20-40" in bands and bands["20-40"] > low_ceiling:
        problems.append(
            "%s: 20-40 Hz is %.1f dB above the loudest band, over-heavy low end" % (measurement["file"], bands["20-40"])
        )
    width_ceiling = limits.get("stereo_width_max_db", 12.0)
    if measurement["stereo_width_db"] > width_ceiling:
        problems.append("%s: stereo width %.1f dB is too wide" % (measurement["file"], measurement["stereo_width_db"]))
    # A near-1 correlation means the two channels are the same signal, which is
    # invisible to a ceiling and is the failure that actually happened: layers
    # written as `out(a |> lp(@, 800), b |> lp(@, 800))` came out bit-identical.
    width_floor = limits.get("channel_correlation_max")
    mono_ok = limits.get("mono_ok", [])
    if width_floor is not None and measurement["file"] not in mono_ok:
        if measurement["channel_correlation"] > width_floor:
            problems.append(
                "%s: channel correlation %.3f is above %.3f, the stem is effectively mono"
                % (measurement["file"], measurement["channel_correlation"], width_floor)
            )
    # Rhythmic stems (drums, songs) are SUPPOSED to retrigger on a short
    # fixed grid, that is the music, not a hidden second loop. Only an
    # ambience bed, meant to breathe over many seconds with no beat,
    # should ever trip this. rhythmic_ok names the exceptions the same
    # way mono_ok names the deliberately-mono stems.
    tick_ceiling = limits.get("repetition_tick_max_db")
    rhythmic_ok = limits.get("rhythmic_ok", [])
    if (tick_ceiling is not None and measurement["file"] not in rhythmic_ok
            and measurement.get("repetition_tick_db", float("-inf")) > tick_ceiling):
        problems.append(
            "%s: repetition tick %.1f dB is above %.1f, a short loop is hiding inside the render"
            % (measurement["file"], measurement["repetition_tick_db"], tick_ceiling)
        )
    return problems


def mix_down(paths, gains_db):
    """Sum stems the way the mixer does, so LUFS is measured on what is heard."""
    total = None
    for path, gain_db in zip(paths, gains_db):
        data, _ = read_wav(path)
        if data.shape[1] == 1 and total is not None and total.shape[1] == 2:
            data = np.repeat(data, 2, axis=1)
        if total is None:
            total = data * (10.0 ** (gain_db / 20.0))
        else:
            width = max(total.shape[1], data.shape[1])
            if total.shape[1] < width:
                total = np.repeat(total, width // total.shape[1], axis=1)
            if data.shape[1] < width:
                data = np.repeat(data, width // data.shape[1], axis=1)
            length = min(total.shape[0], data.shape[0])
            total = total[:length] + data[:length] * (10.0 ** (gain_db / 20.0))
    return total


def _open_check_for(problem):
    if "clipped samples" in problem:
        return "clipped"
    if "true peak" in problem:
        return "true_peak"
    if "DC offset" in problem:
        return "dc_offset"
    if "loop wrap jump" in problem:
        return "loop_jump_ratio"
    if "brighter than the file" in problem:
        return "loop_wrap_hf"
    if "20-40 Hz" in problem:
        return "low_band"
    if "stereo width" in problem:
        return "stereo_width"
    if "effectively mono" in problem:
        return "mono"
    if "repetition tick" in problem:
        return "repetition_tick"
    return "?"


def _matches_open(name, problem, known):
    return _open_check_for(problem) in known.get(name, set())


def _selftest(directory):
    """Check the meter against signals whose answer is known in advance.

    A gate nobody has checked is a gate nobody should trust. Each case here has
    one property and the analyzer has to find exactly that one.
    """
    import shutil

    if os.path.isdir(directory):
        shutil.rmtree(directory)
    os.makedirs(directory)
    rate = 48000
    frames = rate

    def write(name, mono):
        with wave.open(os.path.join(directory, name), "wb") as handle:
            handle.setnchannels(2)
            handle.setsampwidth(2)
            handle.setframerate(rate)
            interleaved = array_module.array("h")
            for value in mono:
                sample = int(max(-1.0, min(1.0, value)) * 32767)
                interleaved.append(sample)
                interleaved.append(sample)
            handle.writeframes(interleaved.tobytes())

    # Every fixture sits near -6 dBFS so the true-peak ceiling is not the thing
    # under test. Each one carries exactly one defect.
    quiet = [0.5 * math.sin(2.0 * math.pi * 1000.0 * i / rate) for i in range(frames)]
    write("selftest_clean.wav", quiet)

    stepped = list(quiet)
    for k in range(6):
        stepped[k] = 0.6
    write("selftest_wrap.wav", stepped)

    # A hard-clipped signal legitimately trips the true-peak ceiling too, so
    # that is the expected set rather than a second defect.
    write("selftest_clip.wav", [max(-1.0, min(1.0, 3.0 * v)) for v in quiet])
    write("selftest_rumble.wav", [0.5 * math.sin(2.0 * math.pi * 20.0 * i / rate) for i in range(frames)])

    # Wide: a small common component with a large opposed one, so mid stays
    # non-zero and the side/mid ratio lands above the ceiling.
    wide = []
    for i in range(frames):
        common = 0.02 * math.sin(2.0 * math.pi * 200.0 * i / rate)
        opposed = 0.4 * math.sin(2.0 * math.pi * 700.0 * i / rate)
        wide.append((common + opposed, common - opposed))
    with wave.open(os.path.join(directory, "selftest_wide.wav"), "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        interleaved = array_module.array("h")
        for left, right in wide:
            interleaved.append(int(max(-1.0, min(1.0, left)) * 32767))
            interleaved.append(int(max(-1.0, min(1.0, right)) * 32767))
        handle.writeframes(interleaved.tobytes())

    # A pure tone is strongly self-similar at every short lag by definition
    # (it repeats every waveform period, and that repetition is timbre, not
    # the defect this check is for), so both the clean control AND the tick
    # fixture here are white noise: broadband, no strong periodicity of its
    # own, so the only thing that can trip the check is the click actually
    # added on the fixed grid.
    rng_state = 424242
    def _lcg():
        nonlocal rng_state
        rng_state = (1103515245 * rng_state + 12345) & 0x7fffffff
        return (rng_state / float(0x7fffffff)) * 2.0 - 1.0
    noise_bed = [0.05 * _lcg() for _ in range(frames)]
    write("selftest_tick_clean.wav", noise_bed)

    # D1: a too-quiet "ambience" and a too-loud "ambience" so the category
    # LUFS window catches both a dead render and a stem that will clip once
    # the mix trim is applied. Named amb_* / m_*_bass so stem_category()
    # sorts them the same way it would sort a real render.
    write("amb_selftest_quiet.wav", [1e-4 * math.sin(2.0 * math.pi * 300.0 * i / rate) for i in range(frames)])
    write("m_selftest_bass_loud.wav", [0.85 * math.sin(2.0 * math.pi * 80.0 * i / rate) for i in range(frames)])

    tick_period = int(round(0.1 * rate))
    # Offset so a click sits mid-period rather than at sample 0: the file
    # then starts and ends on plain background, not mid-decay, so this
    # fixture does not ALSO trip loop_jump_ratio as a side effect.
    tick_offset = tick_period // 2
    ticking = list(noise_bed)
    for start in range(tick_offset, frames, tick_period):
        for k in range(min(200, frames - start)):
            ticking[start + k] += 0.6 * math.exp(-k / 40.0)
    write("selftest_tick.wav", ticking)

    # A held low tone with NO LFO and no second detuned partial: a plain
    # 55 Hz sine (period ~18.2 ms; sine rather than saw so the waveform
    # itself has no built-in discontinuity to confound loop_jump_ratio,
    # which is not what this fixture is testing). A short rectangular
    # analysis frame would alias this tone's own cycle into fake RMS ripple
    # and trip repetition_tick as a false positive -- this fixture is
    # exactly the case that regression guards against. Length is snapped to
    # an exact integer number of 55 Hz cycles so mono[0] and mono[-1] land
    # at the same phase and the fixture does not also trip loop_jump_ratio
    # as an unrelated side effect.
    low_tone_cycles = int(round(frames * 55.0 / rate))
    low_tone_frames = int(round(low_tone_cycles * rate / 55.0))
    write("selftest_low_tone.wav", [0.5 * math.sin(2.0 * math.pi * 55.0 * i / rate) for i in range(low_tone_frames)])

    targets = {
        "no_clipping": True,
        "true_peak_max_db": -1.0,
        "max_dc_offset": 0.002,
        "loop_jump_ratio_max": 3.0,
        "loop_wrap_hf_max_db": 3.0,
        "low_band_max_db": -3.0,
        "stereo_width_max_db": 12.0,
        "repetition_tick_max_db": -8.0,
        "category_lufs": {"ambience": [-46.0, -9.0], "music_layer": [-46.0, -9.0]},
    }
    cases = [
        ("selftest_clean.wav", set()),
        ("selftest_wrap.wav", {"loop_jump_ratio"}),
        ("selftest_clip.wav", {"clipped", "true_peak"}),
        ("selftest_rumble.wav", {"low_band"}),
        ("selftest_wide.wav", {"stereo_width"}),
        ("selftest_tick.wav", {"repetition_tick"}),
        ("selftest_tick_clean.wav", set()),
        ("selftest_low_tone.wav", set()),
        ("amb_selftest_quiet.wav", {"category_lufs"}),
        ("m_selftest_bass_loud.wav", {"category_lufs"}),
    ]

    failures = []
    # Independent check on the meter: derive the expected LUFS from the K-weighting
    # coefficients themselves rather than a remembered number, so a change to the
    # filter shows up as a failure instead of silently moving the goalposts.
    omega = 2.0 * math.pi * 1000.0 / 48000.0
    z = complex(math.cos(-omega), math.sin(-omega))

    def section(b, a):
        return abs((b[0] + b[1] * z + b[2] * z * z) / (a[0] + a[1] * z + a[2] * z * z))

    gain = section(_SHELF_B, _SHELF_A) * section(_HPF_B, _HPF_A)
    # 0.5 peak amplitude sine: per-channel mean square 0.125, two channels
    # summed to 0.25, scaled by the K-weighting power gain.
    expected = -0.691 + 10.0 * math.log10(0.25 * gain * gain)
    sine = measure(os.path.join(directory, "selftest_clean.wav"))
    if abs(sine["integrated_lufs"] - expected) > 0.5:
        failures.append(
            "selftest: stereo sine reads %.2f LUFS, expected about %.2f (K-weight %.2f dB at 1 kHz)"
            % (sine["integrated_lufs"], expected, 20.0 * math.log10(gain))
        )
    if abs(sine["true_peak_dbfs"] - sine["peak_dbfs"]) > 0.5:
        failures.append(
            "selftest: true peak %.2f should track sample peak %.2f for a low sine"
            % (sine["true_peak_dbfs"], sine["peak_dbfs"])
        )

    for name, expected in cases:
        problems = judge(measure(os.path.join(directory, name)), targets)
        found = set()
        for problem in problems:
            if "clipped" in problem:
                found.add("clipped")
            if "loop wrap jump" in problem:
                found.add("loop_jump_ratio")
            if "20-40 Hz" in problem:
                found.add("low_band")
            if "stereo width" in problem:
                found.add("stereo_width")
            if "true peak" in problem:
                found.add("true_peak")
            if "repetition tick" in problem:
                found.add("repetition_tick")
            if "integrated loudness" in problem:
                found.add("category_lufs")
        if found != expected:
            failures.append(
                "selftest: %s tripped %s, expected %s"
                % (name, sorted(found) or "nothing", sorted(expected) or "nothing")
            )

    for failure in failures:
        print("  FAIL " + failure, file=sys.stderr)
    if not failures:
        print("  selftest: %d reference signals, all detected as expected" % len(cases))
    # masking_margin_db: a 1 kHz event over a matching 1 kHz bed at equal
    # level must show a margin near 0 dB in that band, and the SAME event
    # over a bed 20 dB louder in that band must show a margin near -20 dB.
    # This is the one check that needs two files at once, so it is not a
    # (name, expected) case above; it is verified directly here instead.
    event_tone = np.array([[0.2 * math.sin(2.0 * math.pi * 1000.0 * i / rate)] * 2 for i in range(frames)])
    equal_bed = np.array([[0.2 * math.sin(2.0 * math.pi * 1000.0 * i / rate)] * 2 for i in range(frames)])
    loud_bed = np.array([[2.0 * math.sin(2.0 * math.pi * 1000.0 * i / rate)] * 2 for i in range(frames)])
    equal_margins = masking_margin_db(event_tone, rate, equal_bed, rate)
    loud_margins = masking_margin_db(event_tone, rate, loud_bed, rate)
    equal_band = equal_margins.get("1000-2000")
    loud_band = loud_margins.get("1000-2000")
    if equal_band is None or abs(equal_band) > 1.0:
        failures.append(
            "selftest: equal-level 1 kHz event/bed margin is %s, expected about 0 dB" % equal_band
        )
    if loud_band is None or abs(loud_band - (-20.0)) > 1.0:
        failures.append(
            "selftest: event under a 20 dB louder bed margin is %s, expected about -20 dB" % loud_band
        )

    # own_energy_weighted_margin_db: a 1 kHz event with NO low end must PASS
    # over a bed with a huge rumble the event never occupies (that band is
    # not masking, the event was just never there); the SAME event's own
    # 1 kHz band must FAIL when the bed also outweighs it exactly there.
    no_rumble_event = event_tone
    rumble_bed = np.array(
        [[0.2 * math.sin(2.0 * math.pi * 1000.0 * i / rate)
          + 5.0 * math.sin(2.0 * math.pi * 30.0 * i / rate)] * 2
         for i in range(frames)]
    )
    buried_bed = np.array([[5.0 * math.sin(2.0 * math.pi * 1000.0 * i / rate)] * 2 for i in range(frames)])
    rumble_margins = masking_margin_db(no_rumble_event, rate, rumble_bed, rate)
    buried_margins = masking_margin_db(no_rumble_event, rate, buried_bed, rate)
    rumble_own = rumble_margins.get("own_energy_weighted_margin_db")
    buried_own = buried_margins.get("own_energy_weighted_margin_db")
    if rumble_own is None or rumble_own < -10.0:
        failures.append(
            "selftest: event with no low end over a big-rumble bed own-band margin is %s, expected a PASS (>= -10 dB, the rumble band is not the event's own)" % rumble_own
        )
    if buried_own is None or buried_own >= -10.0:
        failures.append(
            "selftest: event buried in its own 1 kHz band own-band margin is %s, expected a FAIL (< -10 dB)" % buried_own
        )

    shutil.rmtree(directory, ignore_errors=True)
    return 1 if failures else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("targets", nargs="?", default="-", help="JSON file of thresholds, or '-' for none")
    parser.add_argument("wavs", nargs="*")
    parser.add_argument("--json-out", default="")
    parser.add_argument("--mix", default="", help="JSON list of [path, gain_db] pairs summed before measuring")
    parser.add_argument("--mix-out", default="")
    parser.add_argument("--selftest", action="store_true", help="verify the meter against known signals and exit")
    parser.add_argument("--mask", default="", help="JSON list of {event, bed, min_margin_db} to check an event is not buried under a bed")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    if args.selftest:
        return _selftest(os.path.join(os.path.dirname(os.path.abspath(__file__)), "selftest_tmp"))
    if not args.wavs and not args.mix and not args.mask:
        parser.error("nothing to measure: pass wavs, --mix, --mask, or --selftest")

    targets = {}
    if args.targets != "-":
        with open(args.targets, "r", encoding="utf-8") as handle:
            targets = json.load(handle)
    stem_targets = targets.get("stem", {})
    mix_targets = targets.get("mix", {})

    # `open_findings` is a ratchet, not a switch. A known-unfixed problem stays
    # listed and keeps printing, so it cannot quietly become acceptable; only
    # new failures stop the build.
    known = {}
    for entry in targets.get("open_findings", []):
        known.setdefault(entry["file"], set()).add(entry["check"])

    results = []
    failures = []
    accepted = []
    for pattern in args.wavs:
        for path in sorted(glob.glob(pattern)):
            measurement = measure(path)
            results.append(measurement)
            for problem in judge(measurement, stem_targets):
                if _matches_open(measurement["file"], problem, known):
                    accepted.append(problem)
                else:
                    failures.append(problem)

    mix_result = None
    if args.mix:
        with open(args.mix, "r", encoding="utf-8") as handle:
            plan = json.load(handle)
        stems = [(entry["path"], float(entry.get("gain_db", 0.0))) for entry in plan["stems"] if entry.get("audible")]
        if stems:
            summed = mix_down([p for p, _ in stems], [g for _, g in stems])
            rate = read_wav(stems[0][0])[1]
            peak = float(np.max(np.abs(summed)))
            mix_result = {
                "profile": plan.get("profile", "?"),
                "layers": len(stems),
                "seconds": summed.shape[0] / float(rate),
                "integrated_lufs": integrated_lufs(summed, rate),
                "true_peak_dbfs": 20.0 * math.log10(peak) if peak > 0 else float("-inf"),
                "stereo_width_db": stereo_width_db(summed)[0],
            }
            loudness_target = mix_targets.get("integrated_lufs")
            if loudness_target is not None:
                low = loudness_target[0]
                high = loudness_target[1]
                if not (low <= mix_result["integrated_lufs"] <= high):
                    failures.append(
                        "mix %s: integrated %.1f LUFS is outside %.1f..%.1f"
                        % (mix_result["profile"], mix_result["integrated_lufs"], low, high)
                    )
            mix_ceiling = mix_targets.get("true_peak_max_db")
            if mix_ceiling is not None and mix_result["true_peak_dbfs"] > mix_ceiling:
                failures.append(
                    "mix %s: true peak %.2f dBFS is above %.2f" % (mix_result["profile"], mix_result["true_peak_dbfs"], mix_ceiling)
                )

    mask_results = []
    if args.mask:
        with open(args.mask, "r", encoding="utf-8") as handle:
            mask_plan = json.load(handle)
        mask_pairs = mask_plan["pairs"] if isinstance(mask_plan, dict) else mask_plan
        for entry in mask_pairs:
            event_data, event_rate = read_wav(entry["event"])
            bed_data, bed_rate = read_wav(entry["bed"])
            margins = masking_margin_db(event_data, event_rate, bed_data, bed_rate)
            floor_db = entry.get("min_margin_db", 0.0)
            own_margin = margins.get("own_energy_weighted_margin_db")
            mask_results.append({
                "event": entry["event"],
                "bed": entry["bed"],
                "margins_db": margins,
            })
            if own_margin is not None and own_margin < floor_db:
                failures.append(
                    "%s under %s: own-band masking margin %.1f dB is below %.1f, the event's own sound is buried"
                    % (entry["event"], entry["bed"], own_margin, floor_db)
                )

    if not args.quiet:
        for measurement in results:
            loop = measurement["loop"]
            print(
                "  %-18s %5.2fs  peak %6.1f  truepeak %6.1f  width %5.1f  corr %5.2f  clip %d  loopjump %5.2f  wrapHF %6.1f"
                % (
                    measurement["file"],
                    measurement["seconds"],
                    measurement["peak_dbfs"],
                    measurement["true_peak_dbfs"],
                    measurement["stereo_width_db"],
                    measurement["channel_correlation"],
                    measurement["clipped_samples"],
                    loop["jump_ratio"],
                    loop["wrap_hf_dbfs"],
                )
            )
        if mix_result:
            print(
                "  MIX %-14s layers %2d  %.1f LUFS  truepeak %.1f dBFS"
                % (mix_result["profile"], mix_result["layers"], mix_result["integrated_lufs"], mix_result["true_peak_dbfs"])
            )
        if results:
            bands = results[0]["octave_bands_db"]
            print(
                "  bands 20-40/60-120/150-300/400-800/1k-2k/2.5k-5k/6k-12k (dB rel loudest): %s"
                % " ".join("%s=%.0f" % (name, value) for name, value in bands.items())
            )
    for problem in accepted:
        print("  KNOWN " + problem, file=sys.stderr)
    for problem in failures:
        print("  FAIL  " + problem, file=sys.stderr)

    report = {"stems": results, "mix": mix_result, "mask": mask_results, "failures": failures, "known": accepted}
    if args.json_out:
        os.makedirs(os.path.dirname(os.path.abspath(args.json_out)), exist_ok=True)
        with open(args.json_out, "w", encoding="utf-8") as handle:
            json.dump(report, handle, indent=2, sort_keys=True)
    if args.mix_out and mix_result:
        os.makedirs(os.path.dirname(os.path.abspath(args.mix_out)), exist_ok=True)
        with open(args.mix_out, "w", encoding="utf-8") as handle:
            json.dump(mix_result, handle, indent=2, sort_keys=True)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())



