"""Seamless-loop post-process for nkido renders.

nkido has no loop mode: `render --seconds N` writes exactly N seconds and
stops. Playing that back on repeat clicks unless the last sample continues
naturally into the first one. White-noise ambience is the worst case,
because the splice lands on two uncorrelated random values.

Fix: render `loop_seconds + fade_seconds`, then fold the overhang back over
the head. For i in [0, F):

    out[i] = body[i] * w(i) + body[D + i] * (1 - w(i))

with a raised-cosine w that starts at 0. So out[0] is the natural successor
of body[D-1], and the transition to the untouched body is C1-continuous.
The result is exactly `loop_seconds` long and loops without a click.

Standard library only. Reads and writes 16-bit PCM WAV.
"""

import argparse
import array
import math
import sys
import wave


def fail(message):
    sys.stderr.write("loopify: " + message + "\n")
    sys.exit(2)


def read_wav(path):
    try:
        with wave.open(path, "rb") as handle:
            channels = handle.getnchannels()
            width = handle.getsampwidth()
            rate = handle.getframerate()
            frames = handle.readframes(handle.getnframes())
    except wave.Error as error:
        fail("cannot read %s: %s" % (path, error))

    if width != 2:
        fail("%s is %d-bit. Render 16-bit PCM (drop --float32)." % (path, width * 8))
    if channels < 1:
        fail("%s has %d channels" % (path, channels))

    samples = array.array("h")
    samples.frombytes(frames)
    return samples, channels, rate


def write_wav(path, samples, channels, rate):
    with wave.open(path, "wb") as handle:
        handle.setnchannels(channels)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(samples.tobytes())


def measure(samples):
    """Peak and RMS in 16-bit units, plus the clipped sample count."""
    peak = 0
    total = 0
    clipped = 0
    for value in samples:
        magnitude = -value if value < 0 else value
        if magnitude > peak:
            peak = magnitude
        if magnitude >= 32700:
            clipped += 1
        total += value * value
    count = len(samples)
    rms = math.sqrt(total / count) if count else 0.0
    return peak, rms, clipped


def fold(samples, channels, loop_frames, fade_frames):
    """Blend the overhang after loop_frames back over the head."""
    if fade_frames <= 0:
        return samples[: loop_frames * channels]

    blended = array.array("h", samples[: loop_frames * channels])
    for i in range(fade_frames):
        w = 0.5 - 0.5 * math.cos(math.pi * i / fade_frames)
        head = i * channels
        tail = (loop_frames + i) * channels
        for channel in range(channels):
            a = blended[head + channel]
            b = samples[tail + channel]
            blended[head + channel] = int(a * w + b * (1.0 - w))
    return blended


def fold_file(source, target, loop_frames, fade_frames, quiet=False):
    """Fold `source` into `target`, keeping exactly `loop_frames` frames.

    mix_profiles.py needs the same fold the ambience build uses, so the mix
    preview loops for the same reason the stems do and a click in the preview
    means a click in the game.
    """
    samples, channels, rate = read_wav(source)
    result = fold(samples, channels, loop_frames, fade_frames)
    write_wav(target, result, channels, rate)
    if not quiet:
        peak, rms, clipped = measure(result)
        print("  %s %dch %.3fs peak %.1f dBFS rms %.1f dBFS clipped %d" % (
            os.path.basename(target), channels, len(result) / channels / rate,
            20.0 * math.log10(peak / 32768.0) if peak else -99.0,
            20.0 * math.log10(rms / 32768.0) if rms else -99.0, clipped))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source")
    parser.add_argument("target")
    parser.add_argument("--loop-seconds", type=float, required=True)
    parser.add_argument("--fade-seconds", type=float, default=0.25)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    samples, channels, rate = read_wav(args.source)
    total_frames = len(samples) // channels
    loop_frames = int(round(args.loop_seconds * rate))
    fade_frames = int(round(args.fade_seconds * rate))

    if loop_frames <= 0:
        fail("--loop-seconds must be > 0")
    if loop_frames + fade_frames > total_frames:
        fail(
            "source is %.3f s but loop+fade needs %.3f s. Render longer."
            % (total_frames / rate, args.loop_seconds + args.fade_seconds)
        )
    if fade_frames >= loop_frames:
        fail("--fade-seconds must be shorter than --loop-seconds")

    # A loop only closes cleanly when the whole length fits the pattern
    # period. Report the remainder instead of hiding it.
    result = fold(samples, channels, loop_frames, fade_frames)
    peak, rms, clipped = measure(result)

    if not args.quiet:
        print(
            "  %dch %dHz  %d->%d frames  peak %5.1f dBFS  rms %5.1f dBFS  clipped %d"
            % (
                channels,
                rate,
                total_frames,
                len(result) // channels,
                (20.0 * math.log10(peak / 32768.0)) if peak else -99.0,
                (20.0 * math.log10(rms / 32768.0)) if rms else -99.0,
                clipped,
            )
        )

    write_wav(args.target, result, channels, rate)
    return 1 if clipped else 0


if __name__ == "__main__":
    sys.exit(main())
