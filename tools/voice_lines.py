"""Shared by build_voice_sheet.py and check_voice_files.py: the vent lines, when
each one comes up, and which clips are already in game/audio/voice.

The game finds a clip by line id only (audio/fp_vent_voice.gd), so changing a
line's wording does not lose its clip. recorded_lines.json remembers the
wording each clip was recorded from, so a changed line can be found again.
"""
from __future__ import annotations

import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
LINE_FILES = ("vent_lines.json", "vent_biome_lines.json", "vent_guide_lines.json")
EXTENSIONS = ("ogg", "wav")  # the order the game looks in
STAMP = "recorded_lines.json"
NOT_CLIPS = {STAMP, ".gitkeep"}

SECTIONS = {
    "1": "첫 만남", "1d": "열어놓고 딴짓", "1t": "물탱크 거리", "1l": "뚜껑 연 뒤",
    "1p": "이빨을 올리면", "2a": "물 내림 직후", "2b": "물 내림 직후", "3": "봉 가지고 열었을 때",
    "4": "이빨 품평", "5": "올린 양", "6": "고를 때", "7": "안 고르고 끝낼 때",
    "8u": "봉 없이 열었을 때 (못 알아챔)", "8a": "봉 없이 열었을 때 (알아챔)", "9": "여닫기 반복",
    "10": "이상한 걸 올렸을 때", "11": "플레이어를 보고", "12m": "맨틀", "12s": "지표면",
    "12f": "마지막 거래", "guide": "물 내리라고 재촉",
}
PREFIX_SECTIONS = {"biome": "처음 다녀온 바이옴", "struct": "처음 서 본 구조물", "drawing": "종양 그림"}

# Rough grouping for recording in one mood. Taken from the "쓰는 법" part of
# docs/content/vent-lines.md by line family; the line data has no mood field.
MOODS = {
    "다급·조름": ("first", "flush", "distract", "guide"),
    "들뜸": ("tank", "lid", "place", "open"),
    "삐침·짜증": ("leave", "empty", "toggle", "weird"),
    "느긋·품평": ("appraise", "amount", "pick", "final"),
    "혼잣말": ("player", "mantle", "surface", "biome", "struct", "drawing"),
}


def mood_of(line_id: str) -> str:
    family = line_id.split(".")[0]
    for mood, families in MOODS.items():
        if family in families:
            return mood
    return "기타"


def section_of(line: dict) -> str:
    parts = line["id"].split(".")
    if parts[0] in PREFIX_SECTIONS:
        if parts[0] == "drawing":
            return PREFIX_SECTIONS[parts[0]]
        return f"{PREFIX_SECTIONS[parts[0]]}: {parts[1]}"
    section = str(line.get("section", ""))
    return SECTIONS.get(section, section or "기타")


def _rule_conditions(game: Path) -> dict[str, list[str]]:
    path = game / "main/data/vent_rules.json"
    if not path.exists():
        return {}
    rules = json.loads(path.read_text(encoding="utf-8"))
    found: dict[str, list[str]] = {}
    for group in ("사건", "대사묶음"):
        for entry in rules.get(group, {}).values():
            for line_id in entry.get("대사", []):
                note = entry.get("설명", "")
                if note and note not in found.setdefault(line_id, []):
                    found[line_id].append(note)
    return found


def _doc_conditions(game: Path) -> dict[str, str]:
    """ko text -> the "(when)" in front of it in docs/content/vent-lines.md."""
    path = game.parent / "docs/content/vent-lines.md"
    if not path.exists():
        return {}
    found = {}
    for row in path.read_text(encoding="utf-8").splitlines():
        if row.startswith("- (") and ")" in row:
            when, _, rest = row[3:].partition(")")
            found[rest.strip().strip('"')] = when
    return found


def load_lines(game: Path) -> list[dict]:
    """Every line the vent can say: id, ko, section, mood, when."""
    rules = _rule_conditions(game)
    docs = _doc_conditions(game)
    lines = []
    for name in LINE_FILES:
        path = game / "main/data" / name
        if not path.exists():
            continue
        for line in json.loads(path.read_text(encoding="utf-8")).get("lines", []):
            section = section_of(line)
            notes = rules.get(line["id"]) or ([docs[line["ko"]]] if line["ko"] in docs else [])
            lines.append({
                "id": line["id"],
                "ko": line["ko"],
                "section": section,
                "mood": mood_of(line["id"]),
                "when": " / ".join(notes) or section,
            })
    return lines


def voice_dir(game: Path) -> Path:
    return game / "audio/voice"


def clips(game: Path) -> list[Path]:
    """Files in the voice folder that are meant to be clips."""
    folder = voice_dir(game)
    if not folder.exists():
        return []
    return sorted(
        p for p in folder.iterdir()
        if p.is_file() and p.name not in NOT_CLIPS and p.suffix not in (".import", ".uid")
    )


def clip_ids(game: Path) -> dict[str, str]:
    """id -> extension the game would play."""
    found: dict[str, str] = {}
    for ext in reversed(EXTENSIONS):
        for clip in clips(game):
            if clip.suffix == "." + ext:
                found[clip.stem] = ext
    return found


def read_stamp(game: Path) -> dict[str, str]:
    path = voice_dir(game) / STAMP
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def write_stamp(game: Path, stamp: dict[str, str]) -> None:
    text = json.dumps(stamp, ensure_ascii=False, indent=1, sort_keys=True)
    (voice_dir(game) / STAMP).write_text(text + "\n", encoding="utf-8")


def reading_seconds(ko: str) -> float:
    """How long the subtitle stays without a clip (FPSubtitles)."""
    return max(1.8, len(ko) * 0.075)
