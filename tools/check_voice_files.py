"""Checks the clips in game/audio/voice against the vent lines.

Run:  python -X utf8 tools/check_voice_files.py [--strict] [--stamp] [--fix]

Problems (exit 1): a file with no matching line id, a file the game cannot
read, a WAV with an "extensible" header (plays from the folder, but Godot's
importer refuses it, so an exported game would be silent; --fix rewrites the
two header bytes), the same id as both ogg and wav. Notes (exit 0): format, length,
loudness and lines whose wording changed after recording. Ids with no file are
counted and listed; --strict turns them into a problem. --stamp remembers the
current wording of every clip in recorded_lines.json.
"""
from __future__ import annotations

import argparse
import re
import struct
import subprocess
import sys
from pathlib import Path

from voice_lines import EXTENSIONS, REPO, clips, load_lines, read_stamp, reading_seconds, write_stamp

RATE = 48000
WAV_EXTENSIBLE = 0xFFFE
SHORTEST = 0.15
LONGEST = 15.0
# The vent can speak again this soon after a line (vent_rules.json LINE_GAP).
LINE_GAP = 2.5
LOUDNESS = -18.0
LOUDNESS_RANGE = 3.0
PEAK_MAX = -1.0
# Under this ffmpeg has no integrated loudness to give.
LOUDNESS_SHORTEST = 0.5


def wav_info(path: Path) -> dict:
    data = path.read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError("WAV가 아니다")
    pos = 12
    fmt = None
    size = None
    while pos + 8 <= len(data):
        chunk, length = data[pos:pos + 4], struct.unpack("<I", data[pos + 4:pos + 8])[0]
        if chunk == b"fmt ":
            fmt = struct.unpack("<HHIIHH", data[pos + 8:pos + 24])
        elif chunk == b"data":
            size = min(length, len(data) - pos - 8)
        pos += 8 + length + (length & 1)
    if fmt is None or size is None:
        raise ValueError("WAV에 fmt 또는 data가 없다")
    tag, channels, rate, byte_rate, _, bits = fmt
    return {
        "rate": rate, "channels": channels, "bits": bits, "extensible": tag == WAV_EXTENSIBLE,
        "seconds": size / byte_rate if byte_rate else 0.0,
    }


def fix_header(path: Path) -> None:
    """Puts the real sample format where Godot looks for it."""
    data = bytearray(path.read_bytes())
    pos = 12
    while data[pos:pos + 4] != b"fmt ":
        length = struct.unpack("<I", data[pos + 4:pos + 8])[0]
        pos += 8 + length + (length & 1)
    data[pos + 8:pos + 10] = data[pos + 32:pos + 34]
    path.write_bytes(data)


def ogg_info(path: Path) -> dict:
    data = path.read_bytes()
    if data[:4] != b"OggS":
        raise ValueError("Ogg가 아니다")
    start = data.find(b"\x01vorbis")
    if start < 0 or start + 16 > len(data):
        raise ValueError("Vorbis가 아니다")
    channels = data[start + 11]
    rate = struct.unpack("<I", data[start + 12:start + 16])[0]
    last = data.rfind(b"OggS")
    samples = struct.unpack("<q", data[last + 6:last + 14])[0]
    return {"rate": rate, "channels": channels, "bits": 0, "seconds": samples / rate if rate else 0.0}


def loudness(path: Path) -> tuple[float, float] | None:
    """(integrated LUFS, true peak dBTP), None when ffmpeg gives no number."""
    run = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af", "ebur128=peak=true:framelog=quiet", "-f", "null", "-"],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    level = re.findall(r"I:\s+(-?[\d.]+) LUFS", run.stderr)
    peak = re.findall(r"Peak:\s+(-?[\d.]+) dBFS", run.stderr)
    if not level or not peak:
        return None
    return float(level[-1]), float(peak[-1])


def notes_for(info: dict, ko: str) -> list[str]:
    notes = []
    if info["rate"] != RATE:
        notes.append(f"샘플레이트 {info['rate']} Hz (권장 {RATE})")
    if info["channels"] != 1:
        notes.append(f"{info['channels']}채널 (권장 모노)")
    if info["bits"] and info["bits"] < 16:
        notes.append(f"{info['bits']}비트 (권장 24)")
    seconds = info["seconds"]
    if seconds < SHORTEST:
        notes.append(f"너무 짧다 {seconds:.2f}초")
    if seconds > LONGEST:
        notes.append(f"너무 길다 {seconds:.1f}초")
    elif seconds > reading_seconds(ko) * 2.5:
        notes.append(f"글자 수보다 많이 길다 {seconds:.1f}초")
    return notes


def loudness_notes(path: Path, seconds: float) -> list[str]:
    if seconds < LOUDNESS_SHORTEST:
        return []
    measured = loudness(path)
    if measured is None:
        return []
    level, peak = measured
    notes = []
    if abs(level - LOUDNESS) > LOUDNESS_RANGE:
        notes.append(f"음량 {level:.1f} LUFS (권장 {LOUDNESS:.0f}±{LOUDNESS_RANGE:.0f})")
    if peak > PEAK_MAX:
        notes.append(f"피크 {peak:.1f} dBTP (권장 {PEAK_MAX:.0f} 이하)")
    return notes


def check(game: Path, strict: bool = False, stamp_now: bool = False, fix: bool = False) -> int:
    lines = {line["id"]: line for line in load_lines(game)}
    stamp = read_stamp(game)
    problems: list[str] = []
    notes: list[str] = []
    long_lines = 0
    measure = True
    good: set[str] = set()
    seen: dict[str, list[str]] = {}
    for clip in clips(game):
        line = lines.get(clip.stem)
        if line is None or clip.suffix[1:] not in EXTENSIONS:
            problems.append(f"{clip.name}: 대응하는 대사가 없다")
            continue
        seen.setdefault(clip.stem, []).append(clip.name)
        try:
            info = wav_info(clip) if clip.suffix == ".wav" else ogg_info(clip)
        except (ValueError, struct.error, IndexError) as err:
            problems.append(f"{clip.name}: 읽을 수 없다 ({err})")
            continue
        if info.get("extensible") and fix:
            fix_header(clip)
            print(f"{clip.name}: 머리말을 고쳤다")
        elif info.get("extensible"):
            problems.append(f"{clip.name}: EXTENSIBLE WAV라 내보낸 게임에서 안 나온다 (--fix로 고친다)")
        if info["seconds"] <= 0.0:
            problems.append(f"{clip.name}: 소리가 없다")
            continue
        good.add(clip.stem)
        long_lines += info["seconds"] > LINE_GAP
        found = notes_for(info, line["ko"])
        if measure:
            try:
                found += loudness_notes(clip, info["seconds"])
            except FileNotFoundError:
                measure = False
                print("ffmpeg가 없어 음량은 재지 않았다.")
        if clip.stem in stamp and stamp[clip.stem] != line["ko"]:
            found.append("녹음한 뒤 문구가 바뀌었다")
        notes.extend(f"{clip.name}: {note}" for note in found)
    for line_id, names in seen.items():
        if len(names) > 1:
            problems.append(f"{line_id}: {', '.join(names)} 둘 다 있다 (ogg가 나온다)")
    missing = [line_id for line_id in lines if line_id not in seen]
    print(f"대사 {len(lines)}줄, 파일 있음 {len(seen)}줄, 없음 {len(missing)}줄")
    if long_lines:
        print(f"{LINE_GAP}초보다 긴 파일 {long_lines}개: 다음 대사가 곧바로 나오면 끊길 수 있다.")
    for title, items in (("문제", problems), ("살펴볼 것", notes)):
        if items:
            print(f"\n{title} {len(items)}건")
            for item in items:
                print("  " + item)
    if missing and (strict or len(missing) <= 20):
        print(f"\n없는 대사 {len(missing)}줄")
        for line_id in missing:
            print("  " + line_id)
    if stamp_now:
        write_stamp(game, {line_id: lines[line_id]["ko"] for line_id in sorted(good)})
        print(f"\n문구 기록 {len(good)}줄")
    return 1 if problems or (strict and missing) else 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--game", type=Path, default=REPO / "game")
    parser.add_argument("--strict", action="store_true", help="없는 대사도 문제로 친다")
    parser.add_argument("--stamp", action="store_true", help="지금 문구를 recorded_lines.json에 기록한다")
    parser.add_argument("--fix", action="store_true", help="EXTENSIBLE WAV 머리말을 고친다")
    args = parser.parse_args()
    sys.exit(check(args.game, args.strict, args.stamp, args.fix))


if __name__ == "__main__":
    main()
