#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""보상 척도 계산기 (docs/spec/09-reward-scale.md 11장 감사 표).

params.json의 코드 상수를 읽어 척도 지표를 계산하고, 대역 판정 표를 마크다운으로
표준 출력에 낸다. 실행할 때마다 params.json의 각 값을 같은 이름의 코드 상수와
대조한다(읽기만 한다). 구조 문제는 근거 줄의 글이 그대로인지로 판정한다.

이 표가 재는 것은 게임 안 보상 사건과 가설 반응이다. 신경전달물질은 재지 않는다.

안전 조건
- 표준 라이브러리만 쓴다. Godot를 실행하지 않는다.
- user:// 경로, %APPDATA%/Godot, *.save 같은 저장·설정 파일을 열지 않는다.
- 쓰기는 표준 출력, --write 대상, --json 대상에만 한다.

사용 (저장소 루트에서)
    python -X utf8 tools/economy/reward_scale.py            감사 표
    python -X utf8 tools/economy/reward_scale.py --check    대역 밖 항목이 있으면 종료 코드 1
    python -X utf8 tools/economy/reward_scale.py --json     지표를 JSON으로 표준 출력
    python -X utf8 tools/economy/reward_scale.py --json out.json   행 목록을 파일로
    python -X utf8 tools/economy/reward_scale.py --selftest 고정 입력으로 공식 검사(0/1)
    python -X utf8 tools/economy/reward_scale.py --write docs/spec/09-reward-scale.md
    python -X utf8 tools/economy/reward_scale.py --no-verify --params <사본>   후보 값 시험(--write 거부)

종료 코드: 0 정상, 1 대역 밖(--check), selftest 불일치 또는 가상 값으로 --write 시도,
2 상수·식·변이 목록·표지를 찾거나 읽지 못함. 예외: M06_CRUSH_BONUS, M17_DAMAGE_FACTOR,
GURGLE_BANDS는 못 찾으면 경고 뒤 params 값으로 계속하고 그 행에 재확인을 적는다.
변이 29개 검사는 코드에서 파싱한 목록에만 오류로 걸고, params 값에는 경고만 낸다.

Python 3.10 이상에서 돈다(f-string 식 안에 역슬래시나 같은 따옴표를 쓰지 않는다).

여러 경우가 있는 행의 합계 판정: 경우가 모두 같으면 그 판정, 아니면
위반 > 낮음 > 높음 > 미정 순서에서 처음 나오는 판정으로 센다.
"""

from __future__ import annotations

import argparse
import ast
import csv
import decimal
import io
import json
import math
import re
import statistics
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

SCRIPT_PATH = Path(__file__).resolve()
TOOL_LABEL = "tools/economy/reward_scale.py"
DEFAULT_REPO = SCRIPT_PATH.parents[2]
DEFAULT_PARAMS = SCRIPT_PATH.with_name("params.json")

EXIT_OK, EXIT_FAIL, EXIT_PARSE = 0, 1, 2

IN, LOW, HIGH, VIOL, UNDET = "대역 안", "낮음", "높음", "위반", "미정"
VERDICT_ORDER = [IN, LOW, HIGH, VIOL, UNDET]
OUT_OF_BAND = (LOW, HIGH, VIOL)
PRIORITY = (VIOL, LOW, HIGH, UNDET)

GROUPS = ["정합성", "L1 한 입", "위기와 위협", "L2 원정", "L3 성장", "L4 회차", "실측"]
BIOMES = ["core", "mantle", "surface"]
SHELL_KO = ["핵", "맨틀", "지표면"]
TOOL_KO = {"bare": "맨손", "knife": "칼", "saw": "큰 톱"}

EPS = 1e-9


class ParseError(Exception):
    """필수 상수·식·변이 목록·표지를 찾거나 읽지 못했다(종료 코드 2)."""


# ---------------------------------------------------------------------------
# 파일 접근 (읽기 전용, 금지 경로 차단)
# ---------------------------------------------------------------------------

_FORBIDDEN_SUFFIX = {".save", ".sav", ".cfg"}


def guard_path(path: Path) -> Path:
    s = str(path).replace("\\", "/").lower()
    if "user://" in s or "appdata/roaming/godot" in s or path.suffix.lower() in _FORBIDDEN_SUFFIX:
        raise ParseError(f"열지 않는 경로다(저장·설정 파일): {path}")
    return path


class Repo:
    def __init__(self, root: Path):
        self.root = root
        self._cache: dict[str, str | None] = {}

    def text(self, rel: str) -> str | None:
        if rel not in self._cache:
            p = guard_path(self.root / rel)
            try:
                self._cache[rel] = p.read_text(encoding="utf-8")
            except (FileNotFoundError, IsADirectoryError, UnicodeDecodeError):
                self._cache[rel] = None
        return self._cache[rel]

    def lines(self, rel: str) -> list[str] | None:
        t = self.text(rel)
        return None if t is None else t.splitlines()

    def find_line(self, rel: str, needle: str) -> int | None:
        ls = self.lines(rel)
        if ls is None:
            return None
        want = collapse(needle)
        for i, line in enumerate(ls):
            if want in collapse(line):
                return i + 1
        return None

    def at(self, rel: str, needle: str) -> str:
        n = self.find_line(rel, needle)
        base = rel.rsplit("/", 1)[-1]
        return f"{base}:{n}" if n else base

    def gd_files(self, sub: str, exclude_tests: bool = True) -> list[str]:
        base = self.root / sub
        if not base.is_dir():
            return []
        out = []
        for p in sorted(base.rglob("*.gd")):
            rel = p.relative_to(self.root).as_posix()
            if exclude_tests and rel.startswith("game/tests/"):
                continue
            if "/.godot/" in rel:
                continue
            out.append(rel)
        return out


def collapse(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


# ---------------------------------------------------------------------------
# GDScript 상수 읽기
# ---------------------------------------------------------------------------

SYMBOLS = {
    "BIOME_CORE": "core", "BIOME_MANTLE": "mantle", "BIOME_SURFACE": "surface", "COMMON": "common",
    "COMPRESSIVE": 0, "NERVE": 1, "LEGACY_FAT": 2, "MEMBRANE": 3, "CONTRACTILE": 4, "MELTED": 5,
}


def gd_decl_re(name: str) -> re.Pattern:
    return re.compile(
        r"^\s*(?:@export\s+)?(?:static\s+)?(?:const|var)\s+" + re.escape(name)
        + r"\s*(?::\s*[\w\[\]]+)?\s*:?=\s*(.+?)\s*(#.*)?$"
    )


def strip_comment(line: str) -> str:
    q = None
    for i, ch in enumerate(line):
        if q:
            if ch == q:
                q = None
        elif ch in "\"'":
            q = ch
        elif ch == "#":
            return line[:i].rstrip()
    return line.rstrip()


def bracket_depth(s: str) -> int:
    d, q = 0, None
    for ch in s:
        if q:
            if ch == q:
                q = None
        elif ch in "\"'":
            q = ch
        elif ch in "{[(":
            d += 1
        elif ch in "}])":
            d -= 1
    return d


def split_top(s: str) -> list[str]:
    parts, d, q, cur = [], 0, None, []
    for ch in s:
        if q:
            cur.append(ch)
            if ch == q:
                q = None
            continue
        if ch in "\"'":
            q = ch
        elif ch in "{[(":
            d += 1
        elif ch in "}])":
            d -= 1
        if ch == "," and d == 0:
            parts.append("".join(cur).strip())
            cur = []
            continue
        cur.append(ch)
    tail = "".join(cur).strip()
    if tail:
        parts.append(tail)
    return [p for p in parts if p]


def eval_expr(text: str, resolve) -> float | int:
    """숫자와 이미 읽은 이름 위의 + - * / 와 단항 -만 허용한다."""
    try:
        tree = ast.parse(text.strip(), mode="eval")
    except SyntaxError as e:
        raise ParseError(f"식을 읽지 못했다: {text!r}") from e

    def ev(n):
        if isinstance(n, ast.Expression):
            return ev(n.body)
        if isinstance(n, ast.Constant) and isinstance(n.value, (int, float)) and not isinstance(n.value, bool):
            return n.value
        if isinstance(n, ast.Name):
            v = resolve(n.id)
            if not isinstance(v, (int, float)) or isinstance(v, bool):
                raise ParseError(f"숫자가 아닌 이름: {n.id}")
            return v
        if isinstance(n, ast.BinOp) and isinstance(n.op, (ast.Add, ast.Sub, ast.Mult, ast.Div)):
            a, b = ev(n.left), ev(n.right)
            if isinstance(n.op, ast.Add):
                return a + b
            if isinstance(n.op, ast.Sub):
                return a - b
            if isinstance(n.op, ast.Mult):
                return a * b
            if b == 0:
                raise ParseError(f"0으로 나눔: {text!r}")
            if isinstance(a, int) and isinstance(b, int):
                return int(a / b)  # GDScript 정수 나눗셈
            return a / b
        if isinstance(n, ast.UnaryOp) and isinstance(n.op, ast.USub):
            return -ev(n.operand)
        raise ParseError(f"허용하지 않는 식: {text!r}")

    return ev(tree)


_PAIR_RE = re.compile(r'(\w+|"[^"]+")\s*:\s*("[^"]*"|-?[0-9.]+|[A-Za-z_]\w*)')


def _atom(tok: str, resolve):
    tok = tok.strip()
    if tok.startswith('"') and tok.endswith('"'):
        return tok[1:-1]
    if re.fullmatch(r"-?\d+", tok):
        return int(tok)
    if re.fullmatch(r"-?[0-9]*\.[0-9]+|-?[0-9]+\.", tok):
        return float(tok)
    if re.fullmatch(r"[A-Za-z_]\w*", tok):
        return resolve(tok)
    return eval_expr(tok, resolve)


def parse_gd_value(text: str, resolve):
    t = text.strip().rstrip(",").strip()
    if t.startswith("{"):
        out = {}
        for k, v in _PAIR_RE.findall(t[1:-1] if t.endswith("}") else t[1:]):
            out[_atom(k, resolve)] = _atom(v, resolve)
        return out
    t = re.sub(r"\s+as\s+Array\[\w+\]$", "", t)
    if t.startswith("["):
        inner = t[1:t.rindex("]")]
        return [_atom(p, resolve) for p in split_top(inner)]
    m = re.fullmatch(r"Vector[234]i?\s*\((.*)\)", t)
    if m:
        return tuple(float(eval_expr(p, resolve)) for p in split_top(m.group(1)))
    if re.fullmatch(r'"[^"]*"', t):
        return t[1:-1]
    if t in ("true", "false"):
        return t == "true"
    return eval_expr(t, resolve)


class GDFile:
    def __init__(self, lines: list[str], label: str):
        self.lines = lines
        self.label = label
        self._cache: dict[str, tuple] = {}
        self._busy: set[str] = set()

    def resolve(self, name: str):
        if name in SYMBOLS:
            return SYMBOLS[name]
        return self.find(name)[0]

    def find(self, name: str):
        if name in self._cache:
            return self._cache[name]
        if name in self._busy:
            raise ParseError(f"{self.label}: {name} 순환 참조")
        self._busy.add(name)
        try:
            rx = gd_decl_re(name)
            for i, raw in enumerate(self.lines):
                line = strip_comment(raw)
                m = rx.match(line)
                if not m:
                    continue
                text = m.group(1).strip()
                j = i
                while bracket_depth(text) > 0:
                    j += 1
                    if j >= len(self.lines):
                        raise ParseError(f"{self.label}: {name}의 괄호가 닫히지 않았다")
                    text += " " + strip_comment(self.lines[j]).strip()
                value = parse_gd_value(text, self.resolve)
                self._cache[name] = (value, i + 1)
                return self._cache[name]
            raise ParseError(f"{self.label}: {name}을 찾지 못했다")
        finally:
            self._busy.discard(name)


MUT_RE = re.compile(r'_def\("(M\d\d)",\s*"[^"]*",\s*"(\w+)"')
COMBO_RE = re.compile(r"\[(BIOME_\w+),\s*(BIOME_\w+)\]")
EXPECTED_BRANCH_COUNTS = {"common": 6, "compressive": 6, "contractile": 7, "nerve": 7, "combination": 3}


def parse_mutations(lines: list[str]) -> tuple[list[dict], int]:
    out, first = [], None
    for i, line in enumerate(lines):
        m = MUT_RE.search(line)
        if not m:
            continue
        first = first or i + 1
        d = {"id": m.group(1), "branch": m.group(2)}
        c = COMBO_RE.search(line)
        if c:
            d["pools"] = [SYMBOLS[c.group(1)], SYMBOLS[c.group(2)]]
        out.append(d)
    validate_mutations(out)
    return out, first or 0


def validate_mutations(muts: list[dict], strict_counts: bool = True) -> None:
    """조합 변이의 풀 두 개는 늘 검사한다. 29개 고정 개수는 코드에서 파싱한 목록에만 오류로 건다.

    params.json 값(가상의 변이를 넣은 사본 포함)에는 strict_counts=False로 불러 경고만 낸다.
    """
    counts: dict[str, int] = {}
    for m in muts:
        counts[m["branch"]] = counts.get(m["branch"], 0) + 1
        if m["branch"] == "combination" and len(m.get("pools", [])) != 2:
            raise ParseError(f"조합 변이 {m['id']}의 풀 두 개를 찾지 못했다")
    if len(muts) != 29 or counts != EXPECTED_BRANCH_COUNTS:
        msg = f"변이 목록이 29개(공통 6, 압축 6, 수축 7, 신경 7, 조합 3)가 아니다: {len(muts)}개 {counts}"
        if strict_counts:
            raise ParseError(msg)
        print(f"경고: {msg}", file=sys.stderr)


# 이름이 아닌 방법으로 찾는 상수: (정규식, 없어도 되는가)
REGEX_LOOKUPS = {
    "progression.M06_CRUSH_BONUS": (r'BASE_CRUSH_TIME\s*\+\s*\(?\s*([0-9.]+)\s+if\s+_m\("M06"\)', True),
    "progression.M17_DAMAGE_FACTOR": (r'return\s+([0-9.]+)\s+if\s+_m\("M17"\)', True),
    "audio_director.GURGLE_BANDS": (r"fill\s*/\s*maxf\(capacity,\s*[0-9.]+\)\s*\*\s*([0-9.]+)", True),
    "main.climb_up_speed": (r"climb_up_speed\s*=\s*([0-9.]+)", False),
    "main.nerve_cooldown": (r"_nerve_cool\[id\]\s*=\s*([0-9.]+)", False),
    "spray_can.CHEAP_DEPTH": (r"Tier\.CHEAP:\s*([0-9.]+)", False),
    "spray_can.DEEP_DEPTH": (r"Tier\.DEEP:\s*([0-9.]+)", False),
}
JSON_SECTIONS = ("시간", "기준")


def split_source(src: str) -> tuple[str, int | None]:
    if ":" in src:
        path, _, line = src.rpartition(":")
        if line.isdigit():
            return path, int(line)
    return src, None


def lookup_live(repo: Repo, key: str, src: str):
    """코드에서 key의 현재 값과 줄을 찾는다. 반환 (값, 줄)."""
    path, _ = split_source(src)
    if key in REGEX_LOOKUPS:
        pat, _opt = REGEX_LOOKUPS[key]
        ls = repo.lines(path)
        if ls is None:
            raise ParseError(f"{path}를 열지 못했다")
        rx = re.compile(pat)
        for i, line in enumerate(ls):
            m = rx.search(line)
            if m:
                return float(m.group(1)), i + 1
        raise ParseError(f"{path}: {key} 근거 줄을 찾지 못했다")
    if key == "progression.MUTATIONS":
        ls = repo.lines(path)
        if ls is None:
            raise ParseError(f"{path}를 열지 못했다")
        return parse_mutations(ls)
    if path.endswith(".json"):
        text = repo.text(path)
        if text is None:
            raise ParseError(f"{path}를 열지 못했다")
        data = json.loads(text)
        name = key.split(".", 1)[1]
        for sec in JSON_SECTIONS:
            node = data.get(sec, {})
            if isinstance(node, dict) and name in node and "값" in node[name]:
                ls = text.splitlines()
                sec_line = next((i for i, l in enumerate(ls) if re.search(r'"' + sec + r'"\s*:', l)), 0)
                ln = next((i + 1 for i in range(sec_line, len(ls)) if re.search(r'"' + re.escape(name) + r'"\s*:', ls[i])), None)
                return node[name]["값"], ln
        raise ParseError(f"{path}: {name}.값을 찾지 못했다")
    ls = repo.lines(path)
    if ls is None:
        raise ParseError(f"{path}를 열지 못했다")
    return GDFile(ls, path).find(key.split(".", 1)[1])


def same_value(a, b) -> bool:
    if isinstance(a, bool) or isinstance(b, bool):
        return a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return math.isclose(float(a), float(b), rel_tol=1e-9, abs_tol=1e-9)
    if isinstance(a, dict) and isinstance(b, dict):
        na = {str(k): v for k, v in a.items()}
        nb = {str(k): v for k, v in b.items()}
        return na.keys() == nb.keys() and all(same_value(na[k], nb[k]) for k in na)
    if isinstance(a, (list, tuple)) and isinstance(b, (list, tuple)):
        return len(a) == len(b) and all(same_value(x, y) for x, y in zip(a, b))
    return a == b


@dataclass
class VerifyResult:
    mismatches: list[str] = field(default_factory=list)
    drift: list[str] = field(default_factory=list)
    recheck: set[str] = field(default_factory=set)  # 없어도 되는 상수 중 못 찾은 것
    mismatch_keys: list[str] = field(default_factory=list)


def verify_params(repo: Repo, params: dict, quiet: bool = False) -> VerifyResult:
    res = VerifyResult()

    def warn(msg: str) -> None:
        if not quiet:
            print(msg, file=sys.stderr)

    for key, entry in params.items():
        src = entry.get("source", "")
        path, line = split_source(src)
        try:
            live, live_line = lookup_live(repo, key, src)
        except ParseError as e:
            if key in REGEX_LOOKUPS and REGEX_LOOKUPS[key][1]:
                res.recheck.add(key)
                warn(f"경고: {e} (재확인)")
                continue
            raise
        if line is not None and live_line and live_line != line:
            msg = f"{key}: {path}:{line} → 지금은 {live_line}줄"
            res.drift.append(msg)
            warn(f"경고: 줄이 바뀌었다 {msg}")
        if not same_value(live, entry.get("value")):
            msg = f"{key}: params.json {entry.get('value')!r} ≠ 코드 {live!r} ({path}:{live_line})"
            res.mismatches.append(msg)
            res.mismatch_keys.append(key)
            warn(f"경고: 값이 다르다 {msg}")
    return res


# ---------------------------------------------------------------------------
# 근거 플래그와 연결 수
# ---------------------------------------------------------------------------

P_PROG = "game/main/scripts/fp_progression.gd"
P_MAIN = "game/main/scripts/main.gd"
P_APPLY = "game/main/scripts/fp_mutation_apply.gd"
P_SUBS = "game/main/scripts/fp_subtitles.gd"
P_TOILET = "game/main/scripts/toilet_settlement.gd"
P_HOOK = "game/audio/fp_audio_hookup.gd"
P_MANIFEST = "game/audio/manifest.json"
P_MIRROR_BODY = "game/main/art/fp_mirror_body.gd"
P_VENT = "game/main/scripts/fp_vent.gd"
P_ECON = "docs/spec/04-economy.md"
P_FIRST10 = "docs/spec/10-first-ten-minutes.md"
KIT = "game/addons/flesh_dig_kit/"
P_CHEWER = KIT + "eat/fdk_chewer.gd"
P_STOMACH = KIT + "eat/fdk_stomach.gd"
P_FIELD = KIT + "terrain/fdk_terrain_field.gd"
P_CHUNK = KIT + "terrain/fdk_chunk.gd"
P_DROP = KIT + "death/fdk_death_drop.gd"
P_RULES = KIT + "terrain/fdk_tissue_rules.gd"
P_DIRECTOR = KIT + "audio/fdk_audio_director.gd"
P_HAIR = "game/main/art/fp_arm_hair.gd"


@dataclass
class Flag:
    name: str
    ok: bool
    files: list[str]
    detail: str = ""

    @property
    def status(self) -> str:
        return "TRUE" if self.ok else "RECHECK"

    def recheck_memo(self) -> str:
        return "재확인 필요: " + ", ".join(f.rsplit("/", 1)[-1] for f in self.files)


def _has(repo: Repo, rel: str, needle: str) -> bool:
    t = repo.text(rel)
    return t is not None and collapse(needle) in collapse(t)


def _count(repo: Repo, rel: str, needle: str) -> int:
    t = repo.text(rel)
    return 0 if t is None else collapse(t).count(collapse(needle))


def _after(repo: Repo, rel: str, start: str, n: int) -> str | None:
    ls = repo.lines(rel)
    if ls is None:
        return None
    for i, line in enumerate(ls):
        if start in line:
            return "\n".join(ls[i + 1:i + 1 + n])
    return None


def evidence_flags(repo: Repo) -> dict[str, Flag]:
    F: dict[str, Flag] = {}

    # teeth move one at a time and the vent sums one trade (2026-10-13)
    ok = (_has(repo, P_MAIN, "func place_tooth_at_vent() -> bool:")
          and _has(repo, P_VENT, "return place_teeth(trade_paid, prog)"))
    F["F_TRADE_SUM"] = Flag("F_TRADE_SUM", ok, [P_MAIN, P_VENT])

    ok = (_has(repo, P_CHEWER, "terrain.density_at(world_pos) < terrain.config.iso_level")
          and _has(repo, P_CHEWER, "stomach.add_flesh(config.flesh_per_cell)")
          and _has(repo, P_FIELD, "m = maxf(m, corner_density_global("))
    F["F_REGEN_PAY"] = Flag("F_REGEN_PAY", ok, [P_CHEWER, P_FIELD])

    body = _after(repo, P_STOMACH, "func add_flesh", 3)
    ok = (body is not None and "fill += amount" in body and not re.search(r"\bmin[fi]?\(|clamp", body)
          and _has(repo, P_MAIN, "chewer.stomach = null if carry_mode else stomach")
          and _has(repo, P_MAIN, "carried_flesh += stomach_config.flesh_per_cell"))
    F["F_NO_STOMACH_END"] = Flag("F_NO_STOMACH_END", ok, [P_STOMACH, P_MAIN])

    ok = False
    ls = repo.lines(P_CHUNK)
    if ls:
        for i, line in enumerate(ls):
            if "m *= crowd_growth_factor(" in line and i > 0:
                ok = "] == 0:" in ls[i - 1]
                break
    F["F_CROWD_COMPRESSIVE_ONLY"] = Flag("F_CROWD_COMPRESSIVE_ONLY", ok, [P_CHUNK])

    body = _after(repo, P_DROP, "func drop(", 6)
    ok = body is not None and "items = dropped_items.duplicate(true)" in body and "if active" not in body
    F["F_DROP_OVERWRITE"] = Flag("F_DROP_OVERWRITE", ok, [P_DROP])

    ok = _has(repo, P_RULES, 'return tool == "knife" or tool == "big_saw" # muscle needs a blade')
    F["F_KNIFE_GATE"] = Flag("F_KNIFE_GATE", ok, [P_RULES])

    # T6가 막의 기준 경도 d를 바꾸는 분기가 없어야 한다. M09 분기의 'not has_mutation("T6")'는 부정이라 빼고 본다.
    ok = (_has(repo, P_APPLY, "base *= p.hardness(t, bare) / d")
          and _has(repo, P_APPLY, 'p.has_mutation("M09") and not p.has_mutation("T6")'))
    ls = repo.lines(P_APPLY) or []
    for i, line in enumerate(ls):
        if "TISSUE_MEMBRANE" not in line:
            continue
        pos = re.sub(r'not\s+(?:\w+\.)?has_mutation\("T6"\)', "", line)
        if 'has_mutation("T6")' in pos and i + 1 < len(ls) and re.match(r"\s*d ", ls[i + 1]):
            ok = False
    F["F_T6_DOUBLE"] = Flag("F_T6_DOUBLE", ok and bool(ls), [P_APPLY])

    ok = (_has(repo, P_DIRECTOR, "_life_timer = bank.rng.randf_range(life_interval.x, life_interval.y)")
          and _has(repo, P_DIRECTOR, 'play("regen_creak", pos)'))
    F["F_CREAK_RANDOM"] = Flag("F_CREAK_RANDOM", ok, [P_DIRECTOR])

    t = repo.text(P_SUBS)
    ok = t is not None and "label.text = text" in t and not re.search(r"queue(?!_free)", t)
    F["F_SUB_OVERWRITE"] = Flag("F_SUB_OVERWRITE", ok, [P_SUBS])

    # fixes made on 2026-10-14 (each row reads its fix first)
    F["F_T6_FIXED"] = Flag("F_T6_FIXED", _has(repo, P_APPLY, 'if t == FPProgression.TISSUE_MEMBRANE and p.has_mutation("T6"):')
                           and _has(repo, P_APPLY, "d = 1.0 # fp_tissue_tools already chews membrane"), [P_APPLY])
    F["F_STOMACH_END"] = Flag("F_STOMACH_END", _has(repo, P_STOMACH, "func is_full() -> bool:")
                              and _has(repo, P_CHEWER, "stomach.is_full()")
                              and _has(repo, P_MAIN, "carried_flesh >= progression.carry_capacity()"), [P_STOMACH, P_CHEWER, P_MAIN])
    F["F_DROPS_KEPT"] = Flag("F_DROPS_KEPT", _has(repo, P_MAIN, "death_drops.append(death_drop)"), [P_MAIN])
    F["F_PAY_REMOVED"] = Flag("F_PAY_REMOVED", _has(repo, P_CHEWER, "last_units = config.units_for_removed(before - after)")
                              and _has(repo, P_MAIN, "return stomach_config.units_for_removed("), [P_CHEWER, P_MAIN])
    F["F_CREAK_REAL"] = Flag("F_CREAK_REAL", _has(repo, P_DIRECTOR, "pos = creak_source.call()")
                             and _has(repo, P_HOOK, "director.creak_source = _regrowing_spot"), [P_DIRECTOR, P_HOOK])
    F["F_SUB_QUEUE"] = Flag("F_SUB_QUEUE", _has(repo, P_SUBS, "_queue.append([text, seconds])"), [P_SUBS])
    F["F_CUD_CREDIT"] = Flag("F_CUD_CREDIT", _has(repo, P_APPLY, "cud_credit += m.stomach.fill * FPProgression.CUD_SHRINK")
                             and _has(repo, P_MAIN, "stomach.vomit() + mutation_apply.take_cud_credit()"), [P_APPLY, P_MAIN])

    # 이 계산기가 더한 근거 플래그
    ok = (_has(repo, P_HOOK, 'director.play("toilet_flush"') and _has(repo, P_HOOK, '_hook("settle_ticked"')
          and _has(repo, P_TOILET, "RATTLE_BASE + RATTLE_PER_TOOTH * teeth_gain"))
    F["F_SETTLE_SENSES"] = Flag("F_SETTLE_SENSES", ok, [P_HOOK, P_TOILET])

    body = _after(repo, P_MAIN, "func settle_at_rest_point", 4)
    ok = body is not None and "flushed.emit(" in body and "rattle" not in body and "tank" not in body
    F["F_REST_NO_CARRIER"] = Flag("F_REST_NO_CARRIER", ok, [P_MAIN])

    callers = []
    for rel in repo.gd_files("game/main"):
        base = rel.rsplit("/", 1)[-1]
        if base.startswith(("fp_mirror", "fp_progression", "fp_tab")):
            continue
        txt = repo.text(rel) or ""
        if re.search(r"\bbelly_bumps\(\)", txt):
            callers.append(base)
    ok = _has(repo, P_MIRROR_BODY, "_bump(i, false)") and not callers
    F["F_BUMP_MIRROR_ONLY"] = Flag("F_BUMP_MIRROR_ONLY", ok, [P_MIRROR_BODY], ", ".join(callers))

    wall = 0
    for rel in repo.gd_files("game/main/scripts"):
        wall += len(re.findall(r"Time\.get_unix|OS\.get_unix|get_datetime", repo.text(rel) or ""))
    ok = _has(repo, P_PROG, '"rng": _rng_state') and wall == 0
    F["F_RNG_SAVED"] = Flag("F_RNG_SAVED", ok, [P_PROG], f"wall={wall}")
    return F


CUE_SIGNALS = ["contraction_warning", "canary_chirp", "canary_cry", "tank_rattle_started", "opening_flush"]
# 명세에 있는 신호만 B14에서 센다. "hair sound"(털 자람 소리)는 명세에 없는 제안이라 A10에서 관찰만 한다.
SPEC_CUES = CUE_SIGNALS + ["melody", "ending voice", "mutation sound stage"]
CUE_KO = {
    "contraction_warning": "수축 예고", "canary_chirp": "카나리아 지저귐", "canary_cry": "카나리아 울음",
    "tank_rattle_started": "물탱크 달그락", "opening_flush": "시작 물소리", "hair sound": "털 자람 소리",
    "melody": "바깥 선율", "ending voice": "엔딩 목소리", "mutation sound stage": "변이 소리 단계",
}
CUE_REF = {
    "contraction_warning": "02:56", "canary_chirp": "07:43", "canary_cry": "07:43", "tank_rattle_started": "03:49",
    "opening_flush": "03:25", "melody": "00:35", "ending voice": "00:36", "mutation sound stage": "08:45",
}


def signal_connect_re(sig: str) -> re.Pattern:
    """구독 세 형태: sig.connect(…), obj.connect("sig", …), _hook("sig", …)."""
    s = re.escape(sig)
    return re.compile(r"\b" + s + r"\.connect\(|\bconnect\(\s*[\"']" + s + r"[\"']|\b_hook\(\s*[\"']" + s + r"[\"']")


def consumer_counts(repo: Repo) -> dict[str, int]:
    files = repo.gd_files("game")
    texts = {rel: repo.text(rel) or "" for rel in files}
    out: dict[str, int] = {}
    for sig in CUE_SIGNALS:
        rx = signal_connect_re(sig)
        out[sig] = sum(len(rx.findall(t)) for t in texts.values())
    n = 0
    for t in texts.values():
        for line in t.splitlines():
            if "melody_level()" in line and "func melody_level" not in line:
                n += 1
    out["melody"] = n
    n = 0
    audio = repo.root / "game/audio"
    if audio.is_dir():
        for p in sorted(audio.rglob("*")):
            if p.is_file() and p.suffix in (".gd", ".json", ".tres", ".tscn", ".md"):
                try:
                    n += guard_path(p).read_text(encoding="utf-8").count("voice_layers")
                except (UnicodeDecodeError, ParseError):
                    pass
    out["ending voice"] = n
    n = 0
    mt = repo.text(P_MANIFEST)
    if mt:
        try:
            sounds = json.loads(mt).get("sounds", {})
            ids = list(sounds.keys()) if isinstance(sounds, dict) else [s.get("id", "") for s in sounds]
            n = sum(1 for i in ids if "hair" in str(i))
        except (json.JSONDecodeError, AttributeError):
            n = 0
    out["hair sound"] = n
    unconnected = _has(repo, P_HOOK, 'main.get("mutation_points")') and not re.search(
        r"^\s*var\s+mutation_points\b", repo.text(P_MAIN) or "", re.M)
    out["mutation sound stage"] = 0 if unconnected else 1
    return out


UNWIRED = {
    "body_radius": "M05, T4(반경)",
    "carry_capacity": "M13",
    "squeeze_speed_factor": "M19, M20",
    "two_hand_tools_while_carrying": "M28, T2",
}


def unwired_counts(repo: Repo) -> dict[str, int]:
    # calls inside fp_progression count too (one_hand_busy uses
    # two_hand_tools_while_carrying); only the definition lines are skipped
    files = list(repo.gd_files("game/main/scripts"))
    files += repo.gd_files("game/audio")
    out = {}
    for fn in UNWIRED:
        rx = re.compile(r"(?:\.|\b)" + fn + r"\(")
        n = 0
        for rel in files:
            for line in (repo.text(rel) or "").splitlines():
                if line.lstrip().startswith(("func ", "static func ")):
                    continue
                n += len(rx.findall(line))
        out[fn] = n
    return out


# ---------------------------------------------------------------------------
# 모델 (5장 파생량)
# ---------------------------------------------------------------------------

SCENARIOS = {  # 이름: (조직, 도구, 껍질)
    "core_bare": (0, "bare", 0), "core_knife": (0, "knife", 0), "mantle_knife": (4, "knife", 1),
    "surf_bare": (1, "bare", 2), "surf_knife": (1, "knife", 2),
    "saw_core": (0, "saw", 0), "saw_mantle": (4, "saw", 1), "saw_surf": (1, "saw", 2),
}
MAIN_SCENARIOS = ["core_bare", "core_knife", "mantle_knife", "surf_bare", "surf_knife"]
SCN_KO = {"core_bare": "핵 맨손", "core_knife": "핵 칼", "mantle_knife": "맨틀 칼", "surf_bare": "지표면 맨손",
          "surf_knife": "지표면 칼", "saw_core": "핵 톱", "saw_mantle": "맨틀 톱", "saw_surf": "지표면 톱"}
CONTEXTS = {  # 이름: (조직, 껍질, 고체 이웃 면 수, 스프레이)
    # 셀 하나를 뜯으면 dig_at이 2×2×2 모서리를 함께 비우므로 막 뜯긴 모서리의 고체 이웃은 최대 3개다.
    # 고체 4개(core_max)는 주변이 먼저 다시 찬 뒤에야 생기는 도달 상한(동적)이다.
    "core_open": (0, 0, 1, False), "core_1cell": (0, 0, 2, False), "core_dead": (0, 0, 3, False),
    "core_max": (0, 0, 4, False), "core_1cell_spray": (0, 0, 2, True), "core_max_spray": (0, 0, 4, True),
    "core_nerve": (1, 0, None, False), "mantle_contr": (4, 1, None, False), "surf_nerve": (1, 2, None, False),
}
DYNAMIC_CONTEXTS = {"core_max", "core_max_spray"}
CTX_KO = {"core_open": "핵 열린 곳", "core_1cell": "핵 1셀", "core_dead": "핵 막다른 곳",
          "core_max": "핵 최대(동적 상한)", "core_1cell_spray": "핵 1셀 스프레이",
          "core_max_spray": "핵 최대 스프레이(동적 상한)", "core_nerve": "핵 신경",
          "mantle_contr": "맨틀 수축", "surf_nerve": "지표면 신경"}
SHELL_CONTEXT = ["core_1cell", "mantle_contr", "surf_nerve"]
RHO_PAIRS = [("core_1cell", "core_1cell", "core_bare"), ("core_open", "core_open", "core_bare"),
             ("core_max", "core_max", "core_bare"), ("mantle", "mantle_contr", "mantle_knife"),
             ("surf_bare", "surf_nerve", "surf_bare"), ("surf_knife", "surf_nerve", "surf_knife")]
RHO_KO = {"core_1cell": "핵 1셀", "core_open": "핵 열린 곳", "core_max": "핵 최대(동적)", "mantle": "맨틀",
          "surf_bare": "지표면 맨손", "surf_knife": "지표면 칼"}
ONEOFF_TOOLS = ["knife", "tumor_bag", "blender", "big_saw"]  # params.json assumptions.oneoff_tools가 없을 때의 기본값
ITEM_KO ={"barrier": "방벽", "spray_cheap": "싼 스프레이", "knife": "칼", "spray_deep": "비싼 스프레이",
           "blender": "믹서기", "big_saw": "큰 톱", "canary_feed": "카나리아 먹이", "tumor_bag": "가방"}


def round_half_away(x: float) -> int:
    """GDScript round(): 0.5는 0에서 먼 쪽으로."""
    return int(math.floor(abs(x) + 0.5)) * (1 if x >= 0 else -1)


def clamp(x, lo, hi):
    return max(lo, min(hi, x))


def _intmap(d: dict) -> dict[int, float]:
    return {int(k): float(v) for k, v in d.items()}


def ceil_safe(x: float) -> int:
    return math.ceil(round(x, 9))


class Model:
    def __init__(self, V: dict, A: dict):
        self.V, self.A = V, A
        f = lambda k: float(V[k])
        self.tau = f("progression.BASE_CHEW_TIME")
        self.C = f("progression.BASE_CAPACITY")
        self.Ov = f("progression.BASE_OVERFILL")
        self.Om = f("progression.BASE_OVERFILL_CHEW")
        self.fpc = f("stomach_config.flesh_per_cell")
        self.H = _intmap(V["progression.TISSUE_HARDNESS"])
        self.R = _intmap(V["tissue_rules.REGEN"])
        self.knife = f("tissue_rules.KNIFE_SPEED")
        self.saw_factor = f("tissue_rules.SAW_TIME_FACTOR")
        self.saw_cells = int(V["tissue_rules.SAW_TEAR_CELLS"])
        sm = V["progression.SHELL_MULTIPLIER"]
        self.m = [float(sm[b]) for b in BIOMES]
        step = f("depth_danger.DANGER_STEP")
        self.D = [1.0 + step * k for k in range(3)]
        self.iso = f("terrain_config.iso_level")
        self.regen = f("terrain_config.regen_rate")
        self.cell = f("terrain_config.cell_size")
        self.crowd = f("chunk.CROWD_GAIN")
        self.boost = f("spray_can.BOOST_MULT")
        self.crouch = f("player_config.crouch_speed")
        self.teeth_rate = f("progression.TEETH_PER_FLESH")
        self.exp_teeth = f("progression.EXPEDITION_TEETH")
        self.PB = f("progression.FLESH_PER_BIOME_HAIR")
        self.PC = f("progression.FLESH_PER_COMMON_HAIR")
        self.u_E = self.exp_teeth / self.teeth_rate  # 1 E = 100 u
        self.a = float(A["aim"])
        self.T_E = float(A["T_E"])
        self.ritual = (float(A["ritual"][0]), float(A["ritual"][1]))
        self.escape = (int(A["escape_cells"][0]), int(A["escape_cells"][1]))
        self.u_list = [float(x) for x in A["u"]]
        cells = A["tunnel_cells_per_m"]
        self.u_per_m = (float(cells[0]) * self.fpc, float(cells[1]) * self.fpc)
        door = A.get("door_depth")
        self.door = float(door) if door is not None else float(V["restroom.HALF"][2])
        self.tool_by_shell = list(A["expected_tool"])
        self.measured_TE: dict[int, tuple[float, float]] = {}
        self.measured_overall: tuple[float, float] | None = None

    # D1 ---------------------------------------------------------------
    def O(self, f: float) -> float:
        return 1.0 + (self.Om - 1.0) * clamp((f - self.C) / self.Ov, 0.0, 1.0)

    def tool_mult(self, tool: str) -> float:
        return {"bare": 1.0, "knife": 1.0 / self.knife, "saw": self.saw_factor}[tool]

    def t_r(self, tissue: int, tool: str, f: float = 0.0) -> float:
        return self.tau * self.H[tissue] * self.tool_mult(tool) * self.O(f)

    def t_r_scn(self, scn: str, f: float = 0.0) -> float:
        tissue, tool, _ = SCENARIOS[scn]
        return self.t_r(tissue, tool, f)

    # D2 ---------------------------------------------------------------
    def per_resp(self, scn: str) -> float:
        return self.fpc * (self.saw_cells if SCENARIOS[scn][1] == "saw" else 1)

    def n_resp(self, scn: str, u: float) -> float:
        return u / self.per_resp(scn)

    def T_fill(self, scn: str, u: float) -> float:
        per = self.per_resp(scn)
        n = u / per
        steps = ceil_safe(n)
        frac = n - math.floor(n + EPS)
        total = 0.0
        for i in range(steps):
            w = frac if (i == steps - 1 and frac > EPS) else 1.0
            total += w * self.t_r_scn(scn, i * per)
        return total

    def T_dig(self, scn: str, u: float) -> float:
        return self.T_fill(scn, u) + self.n_resp(scn, u) * self.a

    def avg_overfill_mult(self) -> float:
        n = int(round(self.Ov / self.fpc))
        return sum(self.O(self.C + i * self.fpc) for i in range(n)) / n

    # D3, D4 -------------------------------------------------------------
    def teeth_E(self, u: float) -> int:
        return round_half_away(self.teeth_rate * u)

    def biome_E(self, k: int, u: float | None = None) -> float:
        return (self.u_E if u is None else u) * self.m[k] / self.PB

    def common_E(self, k: int, u: float | None = None) -> float:
        return (self.u_E if u is None else u) * self.m[k] / self.PC

    def cells_per_strand(self, k: int, common: bool = False) -> float:
        return (self.PC if common else self.PB) / (self.fpc * self.m[k])

    def strands_per_resp(self, k: int, cells: int) -> float:
        return self.fpc * cells * self.m[k] / self.PB

    # D5 ---------------------------------------------------------------
    def t_close(self, ctx: str) -> float:
        tissue, k, n_solid, spray = CONTEXTS[ctx]
        cr = 1.0
        if tissue == 0 and n_solid is not None:
            cr = 1.0 + self.crowd * clamp((n_solid - 1) / 3.0, 0.0, 1.0)
        b = self.boost if spray else 1.0
        rate = self.regen * self.R[tissue] * self.D[k] * cr * b
        return math.inf if rate <= 0 else self.iso / rate

    # D6 ---------------------------------------------------------------
    def d_E(self, u: float, standing: bool = False) -> float:
        return u / self.u_per_m[1 if standing else 0]

    def t_back(self, u: float) -> float:
        return self.d_E(u) / self.crouch

    def T_E_calc(self, scn: str, u: float) -> tuple[float, float]:
        base = self.T_dig(scn, u) + 2.0 * self.d_E(u) / self.crouch
        return base + self.ritual[0], base + self.ritual[1]

    def T_E_basis(self, scn: str, u: float) -> tuple[float, float]:
        """추정 기준의 T_E 범위. 실측이 있으면 실측 사분위로 바꾼다."""
        k = SCENARIOS[scn][2]
        if k in self.measured_TE:
            return self.measured_TE[k]
        if self.measured_overall:
            return self.measured_overall
        return self.T_E_calc(scn, u)

    def shell_scn(self, k: int) -> str:
        tool = self.tool_by_shell[k]
        return {0: {"bare": "core_bare", "knife": "core_knife"}, 1: {"bare": "mantle_knife", "knife": "mantle_knife"},
                2: {"bare": "surf_bare", "knife": "surf_knife"}}[k].get(tool, SHELL_SCN_DEFAULT[k])

    # D7 ---------------------------------------------------------------
    def rho(self, ctx: str, scn: str, u: float) -> float:
        return self.t_close(ctx) / (self.T_dig(scn, u) + self.t_back(u))

    # D8 ---------------------------------------------------------------
    def anchors(self) -> list[float]:
        T = float(self.V["world_features.SHELL_THICKNESS"])
        n = int(self.V["world_features.SHELL_COUNT"])
        band = float(self.V["world_features.BOUNDARY_BAND"])
        a = [self.door] + [float(x) for x in self.V["world_features.REST_DEPTH"]]
        for b in range(1, n):
            a += [b * T - band, b * T]
        a.append(float(self.V["world_features.OUTER_RADIUS"]) - 0.3)
        return sorted(a)

    def max_gap(self) -> float:
        T = float(self.V["world_features.SHELL_THICKNESS"])
        n = int(self.V["world_features.SHELL_COUNT"])
        band = float(self.V["world_features.BOUNDARY_BAND"])
        bands = [(b * T - band, b * T) for b in range(1, n)]
        a = self.anchors()
        gaps = []
        for x, y in zip(a, a[1:]):
            if any(abs(x - lo) < EPS and abs(y - hi) < EPS for lo, hi in bands):
                continue
            gaps.append(y - x)
        return max(gaps)

    def transit(self) -> tuple[float, float]:
        T = float(self.V["world_features.SHELL_THICKNESS"])
        band = float(self.V["world_features.BOUNDARY_BAND"])
        up = self.u_per_m[0]
        mantle = up * ((T - band) - self.door)
        surface = mantle + up * ((2 * T - band) - T)
        return mantle, surface

    # D08 소모품 -------------------------------------------------------
    def spray_demand(self) -> dict:
        """스프레이 통로망의 이빨 수요. 뿌린 셀은 다시 자라지 않으므로(06-tools.md 5) 스프레이는
        "같은 땅을 여러 번 파는" 길을 영구 통로로 바꾸는 투자다. 통로망 = 화장실 문에서 가장 바깥
        껍질까지의 줄기(경계 띠는 원래 자라지 않아 뺀다) + 되돌아가는 쉼터마다 줄기에서 갈라지는 가지.
        가지 길이는 반지름 r 구면 위 두 무작위 점의 평균 직선 거리 4r/3으로 본다.
        한 번 뿌리면 반경 0.75 m 원통을 깊이만큼 녹이니 1 m 통로 = 1 ÷ 깊이 번이다."""
        n = int(self.V["world_features.SHELL_COUNT"])
        band = float(self.V["world_features.BOUNDARY_BAND"])
        trunk = float(self.V["world_features.OUTER_RADIUS"]) - self.door - band * (n - 1)
        share = float(self.A.get("spray_rest_share", 1.0) if self.A.get("spray_rest_share") is not None else 1.0)
        rests = [int(x) for x in self.V["world_features.REST_PER_SHELL"]]
        depths = [float(x) for x in self.V["world_features.REST_DEPTH"]]
        branch = share * sum(c * 4.0 / 3.0 * r for c, r in zip(rests, depths))
        per_can = float(self.V["spray_can.SPRAYS_PER_CAN"])
        tiers = {"spray_cheap": float(self.V["spray_can.CHEAP_DEPTH"]),
                 "spray_deep": float(self.V["spray_can.DEEP_DEPTH"])}
        per_m = {t: self.price(t) / (per_can * d) for t, d in tiers.items()}
        best = min(per_m, key=lambda t: per_m[t])
        route = trunk + branch
        return {"trunk_m": trunk, "branch_m": branch, "route_m": route, "per_m": per_m, "best": best,
                "teeth": route * per_m[best], "trunk_teeth": trunk * per_m[best],
                "sprays": {t: route / d for t, d in tiers.items()}}

    def consumable_demand(self) -> tuple[float, str]:
        """(이빨 수, 출처). assumptions.consumable_teeth_demand가 숫자면 그 값, null이면 스프레이 통로망."""
        v = self.A.get("consumable_teeth_demand")
        if v is not None:
            return float(v), "가정"
        return self.spray_demand()["teeth"], "스프레이 통로망"

    # D9 ---------------------------------------------------------------
    def oneoff_tools(self) -> list[str]:
        tools = self.A.get("oneoff_tools")
        return list(tools) if tools else list(ONEOFF_TOOLS)

    def tumors_by_shell(self) -> list[int]:
        """껍질별 종양 수. assumptions.tumors_by_shell이 null이면 TUMORS_PER_SHELL을 껍질마다 쓴다."""
        t = self.A.get("tumors_by_shell")
        n = int(self.V["world_features.SHELL_COUNT"])
        if t:
            return [int(x) for x in t]
        return [int(self.V["world_features.TUMORS_PER_SHELL"])] * n

    def with_capacity(self, cap: float) -> "Model":
        """위장 용량만 바꾼 사본(E03 용량 효과)."""
        m = Model.__new__(Model)
        m.__dict__.update(self.__dict__)
        m.C = float(cap)
        return m

    def price(self, item: str) -> int:
        return max(1, round_half_away(float(self.V["progression.PRICE_UNITS"][item]) * self.exp_teeth))

    def run(self) -> dict:
        pool_cost = {k: float(v) for k, v in self.V["progression.POOL_COST"].items()}
        combo = float(self.V["progression.COMBO_FACTOR"])
        branch_pool = self.V["progression.BRANCH_POOL"]
        bE = {b: self.biome_E(k) for k, b in enumerate(BIOMES)}
        demand = {"common": 0.0, "core": 0.0, "mantle": 0.0, "surface": 0.0}
        combos = []
        for mut in self.V["progression.MUTATIONS"]:
            if mut["branch"] == "combination":
                p1, p2 = mut["pools"]
                c1, c2 = ceil_safe(pool_cost[p1] * combo), ceil_safe(pool_cost[p2] * combo)
                e1, e2 = c1 / bE[p1], c2 / bE[p2]
                pick = (p1, c1, e1) if e1 <= e2 + EPS else (p2, c2, e2)
                demand[pick[0]] += pick[1]
                combos.append({"id": mut["id"], "pool": pick[0], "cost": pick[1], "E": pick[2],
                               "costs": {p1: c1, p2: c2}})
            else:
                pool = branch_pool[mut["branch"]]
                demand[pool] += pool_cost[pool]
        E_k = [demand[b] / bE[b] for b in BIOMES]
        E_hair = sum(E_k)
        common_supply = sum(E_k[k] * self.common_E(k) for k in range(3))
        common_demand = demand["common"]
        E_run = E_hair
        common_extra = 0.0
        if common_supply < common_demand - EPS:
            common_extra = (common_demand - common_supply) / self.common_E(2)
            E_run += common_extra
        teeth100 = self.teeth_E(self.u_E)
        teeth_supply = E_run * teeth100
        tools_oneoff = sum(self.price(i) for i in self.oneoff_tools())
        teeth_extra = 0.0
        if teeth_supply < tools_oneoff - EPS:
            teeth_extra = (tools_oneoff - teeth_supply) / teeth100
            E_run += teeth_extra
        return {"demand": demand, "combos": combos, "E_k": E_k, "E_hair": E_hair, "common_supply": common_supply,
                "common_demand": common_demand, "common_extra": common_extra, "teeth_supply": teeth_supply,
                "tools_oneoff": tools_oneoff, "teeth_extra": teeth_extra, "E_run": E_run}

    def trips(self, E_run: float, u: float) -> float:
        return E_run * self.u_E / u

    # D10 --------------------------------------------------------------
    def barrier_life(self, k: int, deficit: float = 1.0) -> float:
        thr = float(self.V["barrier.break_threshold"])
        decay = float(self.V["barrier.stress_decay"])
        bp = float(self.V["main.BARRIER_PRESSURE"])
        den = self.regen * bp * self.D[k] * deficit - decay
        return math.inf if den <= 0 else thr / den

    def core_no_break_deficit(self) -> float:
        return float(self.V["barrier.stress_decay"]) / (self.regen * float(self.V["main.BARRIER_PRESSURE"]))

    # D11 --------------------------------------------------------------
    def nerve_survival(self, damage_factor: float = 1.0, dt: float = 0.001) -> float:
        hmax = float(self.V["hazard_check.health"])
        dps = float(self.V["hazard_check.hazard_dps"]) * damage_factor
        regen = float(self.V["main.HEALTH_REGEN"])
        hz = float(self.V["main.HAZARD_TIME"])
        cool = float(self.V["main.nerve_cooldown"])
        n_d = int(round(hz / dt))
        n_r = int(round(max(0.0, cool - hz) / dt))
        h, steps = hmax, 0
        for _cycle in range(100000):
            start = h
            for _ in range(n_d):
                h -= dps * dt
                steps += 1
                if h <= EPS:
                    return steps * dt
            for _ in range(n_r):
                h = min(hmax, h + regen * dt)
                steps += 1
            if h >= start - EPS:
                return math.inf
        return math.inf

    def t_escape(self) -> float:
        return float(self.V["hazard_check.hazard_radius"]) / self.crouch

    # D12 --------------------------------------------------------------
    def crush(self) -> dict:
        base = float(self.V["progression.BASE_CRUSH_TIME"])
        bonus = float(self.V.get("progression.M06_CRUSH_BONUS", 3.0))
        tn = self.t_r(0, "bare", 0.0)
        to = self.t_r(0, "bare", self.C + self.Ov)
        return {"normal": base / (self.escape[0] * tn), "over": base / (self.escape[1] * to),
                "m06": (base + bonus) / (self.escape[1] * to), "base": base, "m06_time": base + bonus}

    # D13 --------------------------------------------------------------
    def death(self) -> dict:
        pu = self.V["progression.PRICE_UNITS"]
        stomach = (self.C + self.Ov) / self.u_E
        typical = float(self.A["death_typical_fill"]) / self.u_E + float(self.A["death_typical_barriers"]) * float(pu["barrier"])
        worst = (stomach + float(self.V["progression.MAX_BARRIERS"]) * float(pu["barrier"])
                 + float(self.V["progression.MAX_CANARY_FEED"]) * float(pu["canary_feed"])
                 + float(self.V["spray_can.MAX_CARRIED"]) * float(pu["spray_deep"])
                 + float(self.A.get("death_teeth_in_hand", 4)) / self.exp_teeth
                 + 2.0 * float(self.V["progression.TUMOR_TOOTH_PAYOUT"]) / self.exp_teeth)
        return {"stomach": stomach, "typical": typical, "worst": worst}

    # D14 --------------------------------------------------------------
    def idle(self, k: int) -> dict:
        reach = float(self.V["progression.BASE_REACH"])
        period = float(self.V["progression.ALIEN_HAND_PERIOD"])
        protect = float(self.V["main.BODY_PROTECT_RADIUS"])
        window = float(self.A["idle_window"])
        tr = self.t_r_scn(self.shell_scn(k))
        active = 1.0 / (tr + self.a)
        burst = math.floor(reach / self.cell + EPS)
        regrow = math.floor((reach - protect) / self.cell + EPS)
        cycle = self.t_close(SHELL_CONTEXT[k])
        cells = burst + (window - burst * period) * regrow / cycle
        return {"ratio": (cells / window) / active, "burst_ratio": (tr + self.a) / period, "burst": burst,
                "regrow": regrow, "cycle": cycle, "cells": cells}

    # D15 --------------------------------------------------------------
    def draws(self, E_run: float) -> dict:
        n = len(self.V["progression.TUMOR_MUTATIONS"])
        tumors = sum(self.tumors_by_shell())
        new_stock = len({int(v) for v in self.V["progression.UNLOCK_SHELL"].values() if int(v) > 0})
        disc = (tumors + (int(self.V["world_features.SHELL_COUNT"]) - 1) + new_stock
                + int(self.A["new_tissue_sightings"]))
        body = len(self.V["progression.MUTATIONS"]) + n
        return {"G": 2.0 * n / (n + 1), "discovery_count": disc, "discovery_interval": E_run / disc,
                "body_changes": body, "body_interval": E_run / body, "tumors": tumors, "new_stock": new_stock}

    # D16 --------------------------------------------------------------
    def door_shortcut(self) -> dict:
        td = self.T_dig("core_bare", self.u_E)
        tmin = (td + self.ritual[0], td + self.ritual[1])
        est = self.T_E_basis("core_bare", self.u_E)
        # F10 추정 T_E는 T_min(T_dig + 의식)에 이동만 더한 값이라 r_est는 이동 비율만 잰다(독립 기준이 아니다).
        independent = bool(self.measured_TE or self.measured_overall)
        return {"T_min": tmin, "r_assumed": (tmin[0] / self.T_E, tmin[1] / self.T_E),
                "r_est": (tmin[0] / est[0], tmin[1] / est[1]), "est_independent": independent}

    # D17 --------------------------------------------------------------
    def payback(self) -> dict:
        pu = self.V["progression.PRICE_UNITS"]
        cells_E = self.u_E / self.fpc
        dk = cells_E * (self.t_r(0, "bare") - self.t_r(0, "knife"))
        ds = cells_E * self.t_r(0, "bare") - (self.u_E / (self.fpc * self.saw_cells)) * self.t_r(0, "saw")
        return {"knife": float(pu["knife"]) * self.T_E / dk if dk > 0 else math.inf,
                "saw": float(pu["big_saw"]) * self.T_E / ds if ds > 0 else math.inf, "dk": dk, "ds": ds}

    # D18 --------------------------------------------------------------
    def cud(self) -> dict:
        s = float(self.V["progression.CUD_SHRINK"])
        keep = [(1 - s) ** n for n in (1, 2, 3)]
        teeth = [round_half_away(self.teeth_rate * self.C * k) for k in keep]
        return {"keep": keep, "teeth": teeth, "topup_teeth": self.teeth_E(self.C)}


SHELL_SCN_DEFAULT = ["core_bare", "mantle_knife", "surf_knife"]


# ---------------------------------------------------------------------------
# 서식과 판정
# ---------------------------------------------------------------------------

def _q(x: float, nd: int) -> str:
    """사람이 읽는 반올림: 10자리에서 부동소수 잡음을 지우고 0.5는 올린다."""
    if x == math.inf:
        return "∞"
    d = decimal.Decimal(repr(round(x, 10)))
    out = d.quantize(decimal.Decimal(1).scaleb(-nd), rounding=decimal.ROUND_HALF_UP)
    s = format(out, "f")
    return "0" + s[2:] if s.startswith("-0") and float(out) == 0 else s


def fs(x: float) -> str:
    if x == math.inf:
        return "∞"
    ax = abs(x)
    if ax < 0.995:
        return _q(x, 2)
    if ax < 99.95:
        return _q(x, 1)
    return _q(x, 0)


def S(x: float) -> str:
    return fs(x) + " s"


def f2(x: float) -> str:
    return _q(x, 2)


def fu(x: float) -> str:
    return _q(x, 1)


def fn(x: float) -> str:
    s = _q(x, 2).rstrip("0").rstrip(".")
    return s if s not in ("-0", "") else "0"


def rng(lo: float, hi: float, fmt=f2) -> str:
    return f"{fmt(lo)}~{fmt(hi)}"


def judge(x: float, lo: float | None = None, hi: float | None = None) -> str:
    if lo is not None and x < lo - EPS:
        return LOW
    if hi is not None and x > hi + EPS:
        return HIGH
    return IN


def judge_mid(lo_v: float, hi_v: float, lo: float | None = None, hi: float | None = None) -> str:
    return judge((lo_v + hi_v) / 2.0, lo, hi)


def combine(cases) -> tuple[str, str]:
    """(표시, 합계 판정)."""
    if isinstance(cases, str):
        return cases, cases
    vs = [v for _, v in cases]
    if all(v == vs[0] for v in vs):
        return vs[0], vs[0]
    disp = " / ".join(f"{label} {v}" for label, v in cases)
    for p in PRIORITY:
        if p in vs:
            return disp, p
    return disp, vs[0]


@dataclass
class Row:
    id: str
    group: str
    label: str
    current: str
    scale: str
    band: str
    cell: str
    va: str
    ve: str
    memo: str
    inputs: list[str] = field(default_factory=list)
    flags: list[str] = field(default_factory=list)


def make_row(id_, group, label, current, scale, band, cases_a, memo, inputs=(), flags=(), cases_e=None,
             est_label="추정") -> Row:
    da, ca = combine(cases_a)
    if cases_e is None:
        return Row(id_, group, label, current, scale, band, da, ca, ca, memo, list(inputs), list(flags))
    de, ce = combine(cases_e)
    return Row(id_, group, label, current, scale, band, f"가정 {da} · {est_label} {de}", ca, ce, memo,
               list(inputs), list(flags))


def grade(x: float) -> str:
    return "I1" if x < 0.2 else ("I2" if x < 2 else "I3")


# ---------------------------------------------------------------------------
# 행 만들기 (7장)
# ---------------------------------------------------------------------------

@dataclass
class Context:
    model: Model
    params: dict           # 키 → 항목(값, 단위, 출처, 메모)
    repo: Repo | None
    flags: dict[str, Flag]
    cons: dict[str, int]
    unwired: dict[str, int]
    recheck: set[str]
    measured: dict | None = None

    def src(self, key: str) -> str:
        s = self.params.get(key, {}).get("source", "")
        path, line = split_source(s)
        base = path.rsplit("/", 1)[-1]
        return f"{base}:{line}" if line else base

    def at(self, rel: str, needle: str) -> str:
        if self.repo is None:
            return rel.rsplit("/", 1)[-1]
        return self.repo.at(rel, needle)

    def flag_ok(self, name: str) -> bool:
        f = self.flags.get(name)
        return bool(f and f.ok)


def build_rows(cx: Context) -> list[Row]:
    M, V, A = cx.model, cx.model.V, cx.model.A
    rows: list[Row] = []
    est_label = "실측" if (M.measured_TE or M.measured_overall) else "추정"
    u_lo = M.u_list[0]
    us = M.u_list
    ulab = lambda u: f"{fn(u)} u"
    run = M.run()
    E_run = run["E_run"]
    pu = V["progression.PRICE_UNITS"]

    def add(*a, **k):
        rows.append(make_row(*a, **k))

    # 7.1 정합성 ------------------------------------------------------------
    g = "정합성"
    vals = [float(V["progression.BASE_CHEW_TIME"]), float(V["stomach_config.base_chew_time"]),
            float(V["tissue_rules.BASE_CHEW_TIME"])]
    eq = all(abs(v - vals[0]) < EPS for v in vals)
    add("K01", g, "base_chew_time 중복 정의", " / ".join(S(v) for v in vals), f"τ = {S(vals[0])}", "세 값이 같음",
        IN if eq else UNDET,
        f"실제 조정값은 {cx.src('progression.BASE_CHEW_TIME')}이다. {cx.at(P_APPLY, 'm.stomach_config.base_chew_time = base')}이 "
        f"매 프레임 {cx.src('stomach_config.base_chew_time')}을 덮는다. 키트 사본은 {cx.src('tissue_rules.BASE_CHEW_TIME')}.",
        ["progression.BASE_CHEW_TIME", "stomach_config.base_chew_time", "tissue_rules.BASE_CHEW_TIME"])

    th, kh = _intmap(V["progression.TISSUE_HARDNESS"]), _intmap(V["tissue_rules.HARDNESS"])
    eq = all(abs(th.get(i, -1) - kh.get(i, -2)) < EPS for i in range(5))
    add("K02", g, "경도표 중복", " / ".join(fn(th[i]) for i in range(5)), "id 0~4 대조", "TISSUE_HARDNESS = HARDNESS",
        IN if eq else UNDET,
        f"{cx.src('progression.TISSUE_HARDNESS')}와 {cx.src('tissue_rules.HARDNESS')}. 0 압축, 1 신경, 2 옛 지방, 3 막, 4 수축.",
        ["progression.TISSUE_HARDNESS", "tissue_rules.HARDNESS"])

    game3 = [M.C, M.Ov, M.Om]
    kit3 = [float(V["stomach_config.capacity"]), float(V["stomach_config.overfill_capacity"]),
            float(V["stomach_config.overfill_chew_multiplier"])]
    eq = all(abs(a - b) < EPS for a, b in zip(game3, kit3))
    add("K03", g, "위장 설정 중복", f"게임 {fn(game3[0])} u / {fn(game3[1])} u / ×{fn(game3[2])}",
        f"키트 {fn(kit3[0])} u / {fn(kit3[1])} u / ×{fn(kit3[2])}", "게임 = 키트", IN if eq else UNDET,
        f"게임 값({cx.src('progression.BASE_CAPACITY')}~79)이 키트 값({cx.src('stomach_config.capacity')}~20)을 덮는다.",
        ["progression.BASE_CAPACITY", "progression.BASE_OVERFILL", "progression.BASE_OVERFILL_CHEW",
         "stomach_config.capacity", "stomach_config.overfill_capacity", "stomach_config.overfill_chew_multiplier"])

    # 7.2 L1 한 입 -----------------------------------------------------------
    g = "L1 한 입"
    tr_cb = M.t_r(0, "bare")
    add("A01", g, "핵 압축 맨손 t_r", S(tr_cb), f"{f2(tr_cb / M.tau)} τ", "0.35~1.0 s", judge(tr_cb, 0.35, 1.0),
        f"τ × 경도 1.0 × 과식 없음({cx.src('progression.BASE_CHEW_TIME')}).",
        ["progression.BASE_CHEW_TIME", "progression.TISSUE_HARDNESS"])

    kn = [M.t_r(0, "knife"), M.t_r(4, "knife"), M.t_r(1, "knife")]
    pb = M.payback()
    add("A02", g, "칼 t_r (핵 / 맨틀 수축 / 지표면 신경)", " / ".join(S(x) for x in kn),
        " / ".join(f"{f2(x / M.tau)} τ" for x in kn), "0.35~1.0 s",
        combine([(SHELL_KO[i], judge(x, 0.35, 1.0)) for i, x in enumerate(kn)])[1],
        f"칼 ÷{fn(M.knife)}은 명세에 없다({cx.src('tissue_rules.KNIFE_SPEED')}). 06-tools.md:17은 막 1.2 s, 코드는 "
        f"{S(M.t_r(3, 'knife'))}다. 칼 회수 약 {fu(pb['knife'])} E(D17).",
        ["tissue_rules.KNIFE_SPEED", "progression.TISSUE_HARDNESS", "progression.BASE_CHEW_TIME"])

    tr_sb = M.t_r(1, "bare")
    add("A03", g, "지표면 신경 맨손 t_r", S(tr_sb), f"{f2(tr_sb / M.tau)} τ", "0.35~1.0 s", judge(tr_sb, 0.35, 1.0),
        "신경 경도 1.2. 칼이 없어도 뜯는다.", ["progression.TISSUE_HARDNESS"])

    sw = [M.t_r(0, "saw"), M.t_r(4, "saw"), M.t_r(1, "saw")]
    add("A04", g, "큰 톱 스트로크 (압축 / 수축 / 신경)", " / ".join(S(x) for x in sw),
        f"{M.saw_cells}셀/스트로크", "≤ 2.0 s",
        combine([(SHELL_KO[i], judge(x, None, 2.0)) for i, x in enumerate(sw)])[1],
        f"셀당 {' / '.join(S(x / M.saw_cells) for x in sw)}. 회수 약 {fu(pb['saw'])} E(D17). "
        f"{cx.src('tissue_rules.SAW_TIME_FACTOR')}~28.",
        ["tissue_rules.SAW_TIME_FACTOR", "tissue_rules.SAW_TEAR_CELLS"])

    fmax = M.C + M.Ov
    ov = [M.t_r_scn(M.shell_scn(k), fmax) for k in range(3)]
    ov_lab = [f"{SHELL_KO[k]} {TOOL_KO[SCENARIOS[M.shell_scn(k)][1]]}" for k in range(3)]
    add("A05", g, "과식 최대 t_r (기대 도구)", " / ".join(f"{ov_lab[k]} {S(ov[k])}" for k in range(3)),
        f"×{fn(M.Om)} (fill {fn(fmax)} u)", "≤ 2.0 s",
        combine([(ov_lab[k], judge(ov[k], None, 2.0)) for k in range(3)])[1],
        f"지표면 맨손이면 {S(M.t_r(1, 'bare', fmax))}다.",
        ["progression.BASE_OVERFILL_CHEW", "progression.BASE_OVERFILL"])

    band = float(V["world_features.BOUNDARY_BAND"])
    cross = ceil_safe(band / M.cell)
    mk, m9 = M.t_r(3, "knife"), M.tau * M.H[3] * 3.0
    ok = max(mk, m9) <= 4 + EPS and cross * m9 <= 30 + EPS
    # M09 ×3 줄: 'if tissue == TISSUE_MEMBRANE and bare_hand and _m("M09")' 다음 줄의 h *= 3.0
    m09_if = cx.repo.find_line(P_PROG, 'if tissue == TISSUE_MEMBRANE and bare_hand and _m(') if cx.repo else None
    m09_at = f"fp_progression.gd:{m09_if + 1}" if m09_if else "fp_progression.gd"
    add("A06", g, "막 관문", f"칼 {S(mk)}/셀 · M09 맨손 {S(m9)}/셀",
        f"띠 {cross}셀 통과: 칼 {S(cross * mk)} · M09 {S(cross * m9)}", "셀당 ≤ 4 s, 통과 ≤ 30 s",
        IN if ok else HIGH,
        f"띠 {fn(band)} m({cx.src('world_features.BOUNDARY_BAND')}) ÷ 셀 {fn(M.cell)} m. M09는 막 경도 ×3({m09_at}).",
        ["world_features.BOUNDARY_BAND", "terrain_config.cell_size", "tissue_rules.KNIFE_SPEED"])

    t6_spec = M.tau * 1.0
    if cx.flag_ok("F_T6_FIXED"):
        add("A07", g, "T6 막", f"코드 {S(t6_spec)}", f"명세 {S(t6_spec)}", "코드 = 명세 (05-mutations.md:83)", IN,
            f"T6이면 기준 경도 d도 1.0이라 이중 적용이 없다({cx.at(P_APPLY, 'd = 1.0 # fp_tissue_tools already chews membrane')}).",
            ["progression.BASE_CHEW_TIME", "progression.TISSUE_HARDNESS"], ["F_T6_FIXED"])
    else:
        if cx.flag_ok("F_T6_DOUBLE"):
            t6_code = M.tau * 1.0 * (1.0 / M.H[3])
            v = IN if abs(t6_code - t6_spec) < EPS else UNDET
            a_from = cx.at(P_APPLY, "var b: float = float(FPProgression.TISSUE_HARDNESS")
            a_to = cx.at(P_APPLY, "m.stomach_config.base_chew_time = base").split(":")[-1]
            memo = (f"이중 적용: {fn(M.tau)} × {fn(1.0)} ÷ {fn(M.H[3])} = {S(t6_code)}({a_from}~{a_to}). "
                    f"T6에서 progression.hardness(막)은 1.0인데 기준 경도 d는 {fn(M.H[3])}로 남고, 키트 쪽 split_jaw 경도도 1.0이다.")
            cur = f"코드 {S(t6_code)}"
        else:
            v, memo, cur = UNDET, cx.flags["F_T6_DOUBLE"].recheck_memo(), "재확인"
        add("A07", g, "T6 막", cur, f"명세 {S(t6_spec)}", "코드 = 명세 (05-mutations.md:83)", v, memo,
            ["progression.BASE_CHEW_TIME", "progression.TISSUE_HARDNESS"], ["F_T6_DOUBLE"])

    cps = [M.cells_per_strand(k) for k in range(3)]
    add("A08", g, "바이옴 털 셀/가닥", " / ".join(f"{fn(x)} c" for x in cps), "P_W ÷ (4 × m_k)", "3~15 c",
        combine([(SHELL_KO[k], judge(cps[k], 3, 15)) for k in range(3)])[1],
        f"{cx.src('progression.FLESH_PER_BIOME_HAIR')}, {cx.src('stomach_config.flesh_per_cell')}.",
        ["progression.FLESH_PER_BIOME_HAIR", "stomach_config.flesh_per_cell", "progression.SHELL_MULTIPLIER"])

    single = [M.strands_per_resp(k, 1) for k in range(3)]
    saw = [M.strands_per_resp(k, M.saw_cells) for k in range(3)]
    worst = max(single + saw)
    which = ("지표면 큰 톱" if worst == saw[2] else "최대")
    add("A09", g, "반응당 털 (표현)", f"셀 1개 {' / '.join(fn(x) for x in single)} · 톱 {' / '.join(fn(x) for x in saw)}가닥",
        f"최대 {fn(worst)}가닥({which})", "표현: 한 반응의 여러 가닥은 보이고 들리는 신호를 묶거나 엇갈려 냄 (4.3 규칙 5)",
        UNDET if worst > 1.0 + EPS else IN,
        "털의 양과 시점은 실제 먹은 살에 묶여 있고 바꾸지 않는다(04-economy.md 털 환산, business-rules.md 섭취 시점). "
        "한 번에 여러 가닥이 자랄 때 신호를 묶는지는 실측 M06(겹침)으로 본다.",
        ["tissue_rules.SAW_TEAR_CELLS", "progression.FLESH_PER_BIOME_HAIR"])

    bx = [1.0 / M.biome_E(k) for k in range(3)]
    cxv = [1.0 / M.common_E(k) for k in range(3)]
    hs = cx.cons.get("hair sound", 0)
    add("A10", g, "털 순간 지각",
        f"바이옴 {' / '.join(f2(x) for x in bx)} E ({' / '.join(grade(x) for x in bx)}) · "
        f"공통 {' / '.join(f2(x) for x in cxv)} E ({' / '.join(sorted(set(grade(x) for x in cxv)))})",
        f"털 소리 {hs}개(명세에 없음)", "I1 감각 1개, I2 감각 2개 또는 1개 + 흔적", IN if hs >= 1 else UNDET,
        ("털 자람 소리는 명세에 없는 제안이다. 지금 순간 운반체는 왼 팔뚝의 시각뿐이라 I2 조건은 실측 M10(관찰 지표)으로 본다. "
         "팔·Tab 자세를 바꾸는 해법은 승인 기준과 대조해야 한다(CLAUDE.md).") if hs == 0 else
        "털 자람 소리가 연결되어 있다(game/audio/manifest.json).",
        ["progression.FLESH_PER_BIOME_HAIR", "progression.FLESH_PER_COMMON_HAIR"], ["hair sound"])

    costs = [int(v) for v in V["progression.POOL_COST"].values()] + [c["cost"] for c in run["combos"]]
    for c in run["combos"]:
        costs += list(c["costs"].values())
    top = max(costs)
    slots, shaggy = int(V["arm_hair.MAX_SLOTS"]), int(V["arm_hair.SHAGGY_AT"])
    add("A11", g, "팔 털 표시 상한", f"MAX_SLOTS {slots}가닥", f"최대 털 가격 {top} · SHAGGY_AT {shaggy}",
        f"{slots} ≥ max({top}, {shaggy})", IN if slots >= max(top, shaggy) else LOW,
        (f"{slots}가닥을 넘으면 종류마다 개수 비율로 자리를 나누고 털이 굵고 길어진다({cx.at(P_HAIR, 'func _slot_shares() -> Dictionary:')}). 모은 털은 계속 몸에 보인다."
         if _has(cx.repo, P_HAIR, "func _slot_shares() -> Dictionary:") else
         f"변이를 다 산 뒤 모은 털은 {slots}가닥을 넘으면 보이지 않는다({cx.src('arm_hair.MAX_SLOTS')})."),
        ["arm_hair.MAX_SLOTS", "arm_hair.SHAGGY_AT", "progression.POOL_COST"])

    sd = float(V["audio_director.swallow_delay"])
    add("A12", g, "삼킴 지연", S(sd), "뜯김 → 삼킴 소리", "0.2~0.5 s", judge(sd, 0.2, 0.5),
        f"{cx.src('audio_director.swallow_delay')}.", ["audio_director.swallow_delay"])

    ms = cx.measured
    if ms and ms.get("M01") is not None:
        add("A13", g, "첫 뜯기", S(ms["M01"]), "실측 M01", "≤ 30 s", judge(ms["M01"], None, 30), "실측 기록의 첫 R-TEAR.")
    else:
        add("A13", g, "첫 뜯기", "—", "—", "≤ 30 s", UNDET, "실측 M01이 필요하다.")

    # 7.3 위기와 위협 --------------------------------------------------------
    g = "위기와 위협"
    cr = M.crush()
    m06_memo = "" if "progression.M06_CRUSH_BONUS" not in cx.recheck else " M06 근거 줄 재확인."
    add("B01", g, "압사 시간", f"{S(cr['base'])} (M06 {S(cr['m06_time'])})",
        f"정상 {f2(cr['normal'])} · 과식 {f2(cr['over'])} · M06 {f2(cr['m06'])}", "≥ 1.5 × 최악 탈출",
        [("정상", judge(cr["normal"], 1.5)), ("과식", judge(cr["over"], 1.5))],
        f"탈출 {M.escape[0]}/{M.escape[1]}셀 × 그 순간 t_r. 과식 끝에서는 {S(M.t_r(0, 'bare', fmax))}/셀이다. "
        f"{cx.src('progression.BASE_CRUSH_TIME')}, M06 {cx.src('progression.M06_CRUSH_BONUS')}.{m06_memo}",
        ["progression.BASE_CRUSH_TIME", "progression.M06_CRUSH_BONUS"])

    warn = float(V["tissue_rules.CONTRACT_WARN"])
    te = M.t_escape()
    nc = cx.cons.get("contraction_warning", 0)
    need = 0.5 + te
    add("B02", g, "수축 예고", f"{S(warn)} · 소비자 {nc}", f"필요 ≥ {S(need)}", "L ≥ 0.5 s + t_escape",
        UNDET if nc == 0 else judge(warn, need),
        (f"미연결이다({cx.at(P_FIELD, 'signal contraction_warning')} 신호에 connect 0개). 명세 02-world-tissue.md:56. "
         f"M23만 {S(float(V['progression.HAIR_WARN_TIME']))} 털 떨림을 준다({cx.src('progression.HAIR_WARN_TIME')}).")
        if nc == 0 else f"수축 예고 신호 소비자 {nc}개.",
        ["tissue_rules.CONTRACT_WARN", "hazard_check.hazard_radius", "player_config.crouch_speed"],
        ["contraction_warning"])

    ns = M.nerve_survival()
    m17 = float(V.get("progression.M17_DAMAGE_FACTOR", 0.5))
    ns17 = M.nerve_survival(m17)
    add("B03", g, "신경 접촉 생존", f"{S(ns)} (M17 {S(ns17)})", f"t_escape {S(te)} → {f2(ns / te)}배",
        f"≥ 1.5 × t_escape = {S(1.5 * te)}", judge(ns, 1.5 * te),
        f"{fn(float(V['main.HAZARD_TIME']))} s 피해 {fn(float(V['hazard_check.hazard_dps']))}/s, 쿨다운 "
        f"{fn(float(V['main.nerve_cooldown']))} s({cx.src('main.nerve_cooldown')}), 회복 {fn(float(V['main.HEALTH_REGEN']))}/s. "
        f"M17은 피해 ×{fn(m17)}({cx.src('progression.M17_DAMAGE_FACTOR')}).",
        ["hazard_check.hazard_dps", "hazard_check.hazard_radius", "main.HAZARD_TIME", "main.HEALTH_REGEN",
         "main.nerve_cooldown", "progression.M17_DAMAGE_FACTOR"])

    if cx.flag_ok("F_STOMACH_END"):
        add("B04", g, "위장 시계의 끝", f"{fn(fmax)} u에서 멈춤", f"{fn(fmax)} u까지 한계 비용 ×1→×{fn(M.Om)}, 그다음 먹기 멈춤",
            "한계 비용 단조 증가 + 정해진 끝", IN,
            f"용량 + 과식에 닿으면 씹기가 시작되지 않는다({cx.at(P_CHEWER, 'stomach.is_full()')}). "
            f"들기 모드는 들기 용량에서 멈춘다({cx.at(P_MAIN, 'carried_flesh >= progression.carry_capacity()')}).",
            ["progression.BASE_OVERFILL", "progression.BASE_OVERFILL_CHEW"], ["F_STOMACH_END"])
    elif cx.flag_ok("F_NO_STOMACH_END"):
        add("B04", g, "위장 시계의 끝", "끝 없음", f"{fn(fmax)} u 뒤 한계 비용 ×{fn(M.Om)} 고정",
            "한계 비용 단조 증가 + 정해진 끝", UNDET,
            f"{fn(fmax)} u가 넘으면 한계 비용이 ×{fn(M.Om)}에서 평평하고 먹기에 상한이 없다"
            f"({cx.at(P_STOMACH, 'func add_flesh')}~17). 들기 모드에는 감속도 상한도 없다"
            f"({cx.at(P_MAIN, 'chewer.stomach = null if carry_mode else stomach')}, "
            f"{cx.at(P_MAIN, 'carried_flesh += stomach_config.flesh_per_cell').split(':')[-1]}). 믹서기는 시계를 우회한다. "
            "01:49, 키트 주석, text_game이 서로 다르다. 끝의 형태는 팀이 정한다.",
            ["progression.BASE_OVERFILL", "progression.BASE_OVERFILL_CHEW"], ["F_NO_STOMACH_END"])
    else:
        add("B04", g, "위장 시계의 끝", "재확인", "—", "한계 비용 단조 증가 + 정해진 끝", UNDET,
            cx.flags["F_NO_STOMACH_END"].recheck_memo(), [], ["F_NO_STOMACH_END"])

    tc = {c: M.t_close(c) for c in CONTEXTS}
    ratio = tc["surf_nerve"] / tc["core_1cell"]
    ratio_open = tc["surf_nerve"] / tc["core_open"]
    # 막 뜯긴 자리의 닫힘: 동적 상한(core_max)은 빼고 본다
    inner_min = min(tc[c] for c in CONTEXTS
                    if CONTEXTS[c][1] == 0 and not CONTEXTS[c][3] and c not in DYNAMIC_CONTEXTS)
    if cx.flag_ok("F_CROWD_COMPRESSIVE_ONLY"):
        v, memo = UNDET, (
            f"설계 질문이다. 핵이 지표면보다 빨리 닫히는 것은 승인된 조직 표에서 온다(02-world-tissue.md:37 압축 R "
            f"{fn(M.R[0])}, :39 신경 R {fn(M.R[1])}). 이웃 배율이 없어도 지표면 ÷ 핵 열린 곳 = {f2(ratio_open)}이고, "
            f"압축 조직에만 붙는 이웃 배율({cx.at(P_CHUNK, 'm *= crowd_growth_factor(')})이 그 차이를 키운다. "
            f"02:13의 '안쪽부터 위험이 커진다'와 맞는지는 사용자가 정한다. 핵 막다른 곳 {S(tc['core_dead'])}, "
            f"주변이 먼저 찬 뒤의 동적 상한 {S(tc['core_max'])}.")
    else:
        v, memo = UNDET, cx.flags["F_CROWD_COMPRESSIVE_ONLY"].recheck_memo()
    add("B05", g, "재생 깊이 기울기", f"지표면 {S(tc['surf_nerve'])} / 핵 1셀 {S(tc['core_1cell'])}", f2(ratio),
        "설계 질문 (대역 없음)", v,
        memo, ["chunk.CROWD_GAIN", "depth_danger.DANGER_STEP", "tissue_rules.REGEN"], ["F_CROWD_COMPRESSIVE_ONLY"])

    b06 = [("핵 열린 곳", "core_open", 0), ("핵 1셀", "core_1cell", 0), ("맨틀", "mantle_contr", 1),
           ("지표면", "surf_nerve", 2)]
    ca, ce, sa, se = [], [], [], []
    for lab, ctx, k in b06:
        lo, hi = M.T_E_basis(M.shell_scn(k), M.u_E)
        la = tc[ctx] / M.T_E
        le = (tc[ctx] / hi, tc[ctx] / lo)
        ca.append((lab, judge(la, 0.25, 1.0)))
        ce.append((lab, judge_mid(le[0], le[1], 0.25, 1.0)))
        sa.append(f2(la))
        se.append(rng(*le))
    add("B06", g, "닫힘비 λ (주 조직)", " / ".join(S(tc[c]) for _, c, _ in b06),
        f"가정 {' / '.join(sa)} · {est_label} {' / '.join(se)}", "0.25~1", ca,
        f"순서는 {', '.join(l for l, _, _ in b06)}. {est_label} T_E는 그 껍질 기대 장면의 {fn(M.u_E)} u 원정이다.",
        ["terrain_config.regen_rate", "tissue_rules.REGEN", "chunk.CROWD_GAIN", "depth_danger.DANGER_STEP"],
        cases_e=ce, est_label=est_label)

    b07 = ["core_dead", "core_max", "core_1cell_spray", "core_max_spray"]
    lo, hi = M.T_E_basis("core_bare", M.u_E)
    ca = [(CTX_KO[c], judge(tc[c] / M.T_E, 0.25, 1.0)) for c in b07]
    ce = [(CTX_KO[c], judge_mid(tc[c] / hi, tc[c] / lo, 0.25, 1.0)) for c in b07]
    add("B07", g, "닫힘비 λ (좁은 곳·스프레이)", " / ".join(S(tc[c]) for c in b07),
        f"가정 {' / '.join(f2(tc[c] / M.T_E) for c in b07)} · {est_label} "
        f"{' / '.join(rng(tc[c] / hi, tc[c] / lo) for c in b07)}", "0.25~1", ca,
        f"순서는 {', '.join(CTX_KO[c] for c in b07)}. 막 뜯긴 모서리의 고체 이웃은 최대 3개라(dig_at이 모서리 8개를 함께 비움) "
        f"'최대'는 주변이 먼저 다시 찬 뒤에야 닿는 동적 상한이다. 핵 신경 {S(tc['core_nerve'])}(가정 {f2(tc['core_nerve'] / M.T_E)})은 참고다.",
        ["terrain_config.regen_rate", "chunk.CROWD_GAIN", "spray_can.BOOST_MULT"], cases_e=ce, est_label=est_label)

    cur, cases, disp = [], [], []
    for u in us:
        cur.append(f"u {fn(u)}: " + " / ".join(f2(M.rho(ctx, scn, u)) for _, ctx, scn in RHO_PAIRS))
    for name, ctx, scn in RHO_PAIRS:
        vs = [judge(M.rho(ctx, scn, u), 1.5, 4.0) for u in us]
        cases += [(f"{RHO_KO[name]} {fn(u)} u", v) for u, v in zip(us, vs)]
        disp.append(f"{RHO_KO[name]} " + ", ".join(vs))
    _, cnt = combine(cases)
    rows.append(Row("B08", g, "귀환 여유 ρ", " · ".join(cur), f"쌍 순서: {', '.join(RHO_KO[n] for n, _, _ in RHO_PAIRS)}",
                    "1.5~4", (" / ".join(disp) + f" (u {', '.join(fn(u) for u in us)})") if cnt != IN or len(set(v for _, v in cases)) > 1 else IN,
                    cnt, cnt, "ρ = t_close ÷ (T_dig + t_back). t_back = d_E ÷ 웅크림 속도.",
                    ["terrain_config.regen_rate", "player_config.crouch_speed"]))

    life = [M.barrier_life(k) for k in range(3)]
    ca, ce, sa, se = [], [], [], []
    for k in range(3):
        lo, hi = M.T_E_basis(M.shell_scn(k), M.u_E)
        ca.append((SHELL_KO[k], judge(life[k] / M.T_E, 0.25)))
        ce.append((SHELL_KO[k], judge_mid(life[k] / hi, life[k] / lo, 0.25)))
        sa.append(f2(life[k] / M.T_E))
        se.append(rng(life[k] / hi, life[k] / lo))
    add("B09", g, "방벽 수명 (결손 1)", " / ".join(S(x) for x in life),
        f"가정 {' / '.join(sa)} T_E · {est_label} {' / '.join(se)} T_E", "≥ 0.25 T_E", ca,
        f"핵에서는 결손이 {f2(M.core_no_break_deficit())} 미만이면 방벽이 깨지지 않는다. "
        f"{cx.src('barrier.break_threshold')}, {cx.src('main.BARRIER_PRESSURE')}.",
        ["barrier.break_threshold", "barrier.stress_decay", "main.BARRIER_PRESSURE", "terrain_config.regen_rate"],
        cases_e=ce, est_label=est_label)

    dc = M.death()
    add("B10", g, "죽음 비용", f"전형 {f2(dc['typical'])} E · 위장만 {f2(dc['stomach'])} E · 최악 {f2(dc['worst'])} E",
        "회수 가능", "전형 ≤ 2 E", judge(dc["typical"], None, 2.0),
        "최악은 과식 끝 위장, 방벽 3, 먹이 3, 비싼 스프레이 3통, 한 줌, 종양 2개를 모두 떨어뜨린 경우다.",
        ["progression.PRICE_UNITS", "progression.MAX_BARRIERS", "progression.MAX_CANARY_FEED",
         "spray_can.MAX_CARRIED", "progression.TUMOR_TOOTH_PAYOUT"])

    def rule_row(id_, label, flag, cur, band_txt, verdict, memo, inputs=(), fixed=None):
        if fixed is not None and cx.flag_ok(fixed[0]):
            add(id_, g, label, fixed[1], "규칙 검사", band_txt, IN, fixed[2], inputs, [fixed[0]])
        elif cx.flag_ok(flag):
            add(id_, g, label, cur, "규칙 검사", band_txt, verdict, memo, inputs, [flag])
        else:
            add(id_, g, label, "재확인", "규칙 검사", band_txt, UNDET, cx.flags[flag].recheck_memo(), inputs, [flag])

    rule_row("B11", "두 번째 죽음", "F_DROP_OVERWRITE", "되찾기 전 죽으면 첫 드롭을 덮어씀", "영구 손실 0 (N8)", VIOL,
             f"종양은 다시 생기지 않는다({cx.at(P_DROP, 'items = dropped_items.duplicate(true)')}). 07-danger-navigation.md:34.",
             fixed=("F_DROPS_KEPT", "죽을 때마다 시체가 따로 남음",
                    f"시체 목록에 쌓이고 덮어쓰지 않는다({cx.at(P_MAIN, 'death_drops.append(death_drop)')})."))
    rule_row("B12", "먹은 양과 제거 (재생 셀 지급)", "F_REGEN_PAY", f"재생 중인 셀이 {fn(M.fpc)} u를 다 줌",
             "먹은 u = 제거한 밀도 (N9)", UNDET,
             f"모서리 하나가 0.5 이상이면 셀이 {fn(M.fpc)} u를 다 준다({cx.at(P_CHEWER, 'stomach.add_flesh(config.flesh_per_cell)')}, "
             f"{cx.at(P_FIELD, 'm = maxf(m, corner_density_global(')}). 문 앞 통로가 {fn(round(inner_min))}~{fn(round(tc['core_open']))} s마다 "
             "다시 찬다. N9에 걸리는지 사용자 판정을 기다리며, CLAUDE.md에 따라 사용자에게 바로 알릴 항목이다. "
             "V_T ≤ 0(F22)은 가정 대역이라 이 판정에 쓰지 않는다.", ["stomach_config.flesh_per_cell"],
             fixed=("F_PAY_REMOVED", f"제거한 밀도만큼(최대 {fn(M.fpc)} u)",
                    f"뜯을 때 줄어든 꼭짓점 밀도가 꼭짓점 4개 분량보다 적으면 그 비율만 준다({cx.at(P_CHEWER, 'last_units = config.units_for_removed(before - after)')}). "
                    "먹은 u는 제거한 밀도를 넘지 않는다."))
    lo_i, hi_i = V["audio_director.life_interval"]
    creak_at = cx.at(P_DIRECTOR, 'play("regen_creak", pos)')
    rule_row("B13", "위협 신호 정직성", "F_CREAK_RANDOM", f"regen_creak {fn(lo_i)}~{fn(hi_i)} s 무작위", "신호 = 실제 상태 (N7)", VIOL,
             f"regen_creak은 재생 상태와 무관한 무작위 타이머로 난다({creak_at}).",
             ["audio_director.life_interval"],
             fixed=("F_CREAK_REAL", "실제로 차오르는 자리에서만",
                    f"삐걱 소리는 근처에서 다시 차오르는 뜯긴 자리에서만 난다({cx.at(P_HOOK, 'director.creak_source = _regrowing_spot')}). "
                    "수축 직전 벽도 그 자리에서 삐걱인다."))

    cues = list(SPEC_CUES)
    unc = [c for c in cues if cx.cons.get(c, 0) == 0]
    add("B14", g, "신호 미연결 (명세상)", f"{len(unc)} / {len(cues)}", ", ".join(CUE_KO[c] for c in unc) or "없음", "0",
        LOW if unc else IN,
        ("빠진 신호: " + ", ".join(f"{CUE_KO[c]}({CUE_REF[c]})" for c in unc) + ". 앞섬과 운반체 규칙을 판정할 수 없다. "
         "털 자람 소리는 명세에 없어 세지 않는다(A10).")
        if unc else "명세에 있는 모든 신호에 소비자가 있다.", [], cues)

    cd = M.cud()
    add("B15", g, "M16 되새김 위", f"유지 {' / '.join(f2(x) for x in cd['keep'])} (1/2/3틱)",
        f"가득 찬 위 이빨 {' / '.join(str(x) for x in cd['teeth'])} · 채워 넣으면 {cd['topup_teeth']} + 털",
        "정산 보상 그대로 (05-mutations.md:46)",
        IN if cx.flag_ok("F_CUD_CREDIT") else (UNDET if cd["teeth"][0] != cd["topup_teeth"] else IN),
        f"{fn(float(V['progression.CUD_PERIOD']))} s마다 −{fn(100 * float(V['progression.CUD_SHRINK']))}%"
        f"({cx.src('progression.CUD_SHRINK')}). "
        + (f"줄어든 양은 크레딧으로 쌓여 정산 때 더해진다({cx.at(P_APPLY, 'cud_credit += m.stomach.fill * FPProgression.CUD_SHRINK')}). 채워 넣으면 공간을 털로 바꾼다."
           if cx.flag_ok("F_CUD_CREDIT") else "채워 넣으면 시간을 털로 바꾼다. 명세와 코드가 다르다."),
        ["progression.CUD_PERIOD", "progression.CUD_SHRINK"])

    # 7.4 L2 원정 ------------------------------------------------------------
    g = "L2 원정"
    parts, allv = [], []
    for scn in MAIN_SCENARIOS:
        seg = []
        for u in us:
            lo, hi = M.T_E_basis(scn, u)
            allv += [lo, hi]
            seg.append(rng(lo, hi, fs))
        parts.append(f"{SCN_KO[scn]} {'·'.join(seg)}")
    tot = (min(allv), max(allv))
    add("C01", g, f"원정 시간 {est_label} (F10)", " / ".join(parts) + " s", f"전체 {rng(*tot, fs)} s", "180~300 s",
        judge_mid(tot[0], tot[1], 180, 300),
        f"u {', '.join(fn(u) for u in us)} 순서다. 재굴착, 탐색, 죽음 시간은 빠져 있다. 이동은 왕복으로 센 상한이다"
        f"(문 앞 루프에서는 나가는 길이 T_dig 안에 있으므로 귀환만 넣으면 {fn(M.u_E)} u 핵 맨손이 "
        f"{rng(*[x - M.d_E(M.u_E) / M.crouch for x in M.T_E_calc('core_bare', M.u_E)], fs)} s)." if est_label == "추정"
        else "실측 T_E 사분위다.", ["player_config.crouch_speed"])

    tf = [M.T_fill("core_bare", u) for u in us]
    ka = [x / M.T_E for x in tf]
    ke = []
    for x, u in zip(tf, us):
        lo, hi = M.T_E_basis("core_bare", u)
        ke.append((x / hi, x / lo))
    all_a = [M.T_fill(s, u) / M.T_E for s in MAIN_SCENARIOS for u in us]
    all_e = []
    for s in MAIN_SCENARIOS:
        for u in us:
            lo, hi = M.T_E_basis(s, u)
            all_e += [M.T_fill(s, u) / hi, M.T_fill(s, u) / lo]
    need_fill = 0.2 * 180
    add("C02", g, "씹기 비율 κ (핵 맨손)", "T_fill " + " / ".join(S(x) for x in tf),
        f"가정 {' / '.join(f2(x) for x in ka)} · {est_label} {' / '.join(rng(*x) for x in ke)}", "0.2~0.5",
        [(ulab(u), judge(x, 0.2, 0.5)) for u, x in zip(us, ka)],
        f"모든 장면에서 가정 {rng(min(all_a), max(all_a))}, {est_label} {rng(min(all_e), max(all_e))}. "
        f"T_E 180 s에서 κ ≥ 0.2이려면 T_fill ≥ {S(need_fill)}가 필요하고 지금은 {' / '.join(S(x) for x in tf)}다. "
        "T_E와 κ를 동시에 대역에 넣을 수 없다. 씹는 시간·살 단위·위장 용량을 바꿔 맞추지 않는다(business-rules.md, N3).",
        ["progression.BASE_CHEW_TIME", "progression.BASE_CAPACITY"],
        cases_e=[(ulab(u), judge_mid(x[0], x[1], 0.2, 0.5)) for u, x in zip(us, ke)], est_label=est_label)

    gap = M.max_gap()
    dc_ = [M.d_E(u) for u in us]
    ds_ = [M.d_E(u, True) for u in us]
    add("C03", g, "전진 거리", f"웅크림 {' / '.join(fu(x) for x in dc_)} m · 서기 {' / '.join(fu(x) for x in ds_)} m",
        f"÷ 최대 간격 {fn(gap)} m = {' / '.join(f2(x / gap) for x in dc_)}", "≥ 1",
        combine([(ulab(u), judge(x / gap, 1.0)) for u, x in zip(us, dc_)])[1],
        "직선 근사다. 쉼터 방향은 모델링하지 않았다. 거점은 문, 쉼터, 경계 막, 바깥 껍질이다.",
        ["world_features.REST_DEPTH", "world_features.SHELL_THICKNESS", "world_features.BOUNDARY_BAND", "restroom.HALF"])

    tm, tsur = M.transit()
    add("C04", g, "통과 비용", f"맨틀 {fu(tm)} u · 지표면 {fu(tsur)} u", f"{f2(tm / M.C)} C / {f2(tsur / M.C)} C", "≤ 0.5 C",
        [("맨틀", judge(tm / M.C, None, 0.5)), ("지표면", judge(tsur / M.C, None, 0.5))],
        "쉼터에서 출발하면 0이다. 스프레이 통로와 방벽이 줄인다. 지표면까지 가려면 칼이 필요하다.",
        ["world_features.SHELL_THICKNESS", "world_features.BOUNDARY_BAND", "stomach_config.flesh_per_cell"])

    hair = [M.biome_E(k) + M.common_E(k) for k in range(3)]
    add("C05", g, "원정당 털", " / ".join(f2(x) for x in hair) + "가닥", f"바이옴 + 공통, {fn(M.u_E)} u", "≥ 2가닥",
        combine([(SHELL_KO[k], judge(hair[k], 2.0)) for k in range(3)])[1],
        f"{cx.src('progression.FLESH_PER_BIOME_HAIR')}~29, 껍질 배율 {cx.src('progression.SHELL_MULTIPLIER')}.",
        ["progression.FLESH_PER_BIOME_HAIR", "progression.FLESH_PER_COMMON_HAIR", "progression.SHELL_MULTIPLIER"])

    bands_n = float(V.get("audio_director.GURGLE_BANDS", 4.0))
    gur = [math.floor(u / (M.C / bands_n) + EPS) for u in us]
    add("C06", g, "원정당 꾸르륵", " / ".join(str(x) for x in gur) + "번", f"용량 ÷ {fn(bands_n)} = {fn(M.C / bands_n)} u마다",
        "4~6번", combine([(ulab(u), judge(x, 4, 6)) for u, x in zip(us, gur)])[1],
        f"fill ÷ 용량 × {fn(bands_n)} 구간이 오를 때마다 난다({cx.src('audio_director.GURGLE_BANDS')}).",
        ["audio_director.GURGLE_BANDS", "progression.BASE_CAPACITY"])

    zero_u = 0.5 / M.teeth_rate
    add("C07", g, "이빨 반올림", "기대 손실 약 0 · 최악 0.5개/정산", f"{fn(zero_u)} u 미만이면 0개", "기대 손실 ≈ 0", IN,
        f"round는 0.5를 0에서 먼 쪽으로 올린다({cx.at(P_PROG, 'var gain_teeth := int(round(flesh_amount * TEETH_PER_FLESH))')}).",
        ["progression.TEETH_PER_FLESH"])

    rb, rp = float(V["toilet_settlement.RATTLE_BASE"]), float(V["toilet_settlement.RATTLE_PER_TOOTH"])
    shake = min(rb + rp * M.exp_teeth, float(V["toilet_settlement.RATTLE_MAX"]))
    xs = M.exp_teeth / M.exp_teeth
    rattle_sound = cx.cons.get("tank_rattle_started", 0)
    if cx.flag_ok("F_SETTLE_SENSES"):
        v = IN
        memo = ("03-restroom.md:49, 53의 달그락 소리가 없다. settle_tick은 양과 무관하게 한 번 난다."
                if rattle_sound == 0 else "달그락 소리가 흔들림에 연결되어 있다.")
    else:
        v, memo = UNDET, cx.flags["F_SETTLE_SENSES"].recheck_memo()
    add("C08", g, "레버 정산 표현", f"X {f2(xs)} E → {grade(xs)}",
        f"감각 2(청각 toilet_flush·settle_tick, 시각 흔들림 {S(shake)}) · 양 운반체 흔들림 길이·탱크 더미",
        "I2: 감각 ≥ 2 + 양 운반체", v, memo,
        ["toilet_settlement.RATTLE_BASE", "toilet_settlement.RATTLE_PER_TOOTH", "toilet_settlement.RATTLE_MAX"],
        ["F_SETTLE_SENSES", "tank_rattle_started"])

    if cx.flag_ok("F_REST_NO_CARRIER"):
        v, memo = LOW, f"이빨은 탱크에 쌓이지만 쉼터에서는 보이지 않는다({cx.at(P_MAIN, 'func settle_at_rest_point')}). 운반체 규칙 2에 어긋난다."
    else:
        v, memo = UNDET, cx.flags["F_REST_NO_CARRIER"].recheck_memo()
    add("C09", g, "쉼터 정산 표현", f"X {f2(xs)} E → {grade(xs)}", "감각 2(settle_tick, 토하기 동작) · 양 운반체 없음",
        "I2: 감각 ≥ 2 + 양 운반체", v, memo, [], ["F_REST_NO_CARRIER"])

    rest_band = "강제 의식 ≤ 45 s, 자발적 쉼은 제한 없음"
    if ms and ms.get("rest_median") is not None:
        add("C10", g, "화장실 강제 의식", S(ms["rest_median"]), "실측 A 구간 중앙값(자발적 쉼 포함)", rest_band, UNDET,
            "A 구간에는 자발적 쉼이 섞여 강제 의식만 따로 잴 수 없다. 관찰값이다.")
    else:
        add("C10", g, "화장실 강제 의식", f"추정 {rng(M.ritual[0], M.ritual[1], fs)} s", "의식 시간 가정", rest_band, UNDET,
            "실측이 필요하다. 지금은 의식 시간 가정뿐이다. 화장실은 쉬는 곳이라 머무는 시간에 하한을 두지 않는다.")

    tkeys = ["FRANTIC_TIME", "CALM_TIME", "NAG_INTERVAL", "IDLE_TIME", "STARE_TIME", "PICK_LONG_TIME", "TOGGLE_HIDE"]
    tv = [(k.replace("_TIME", "").replace("_INTERVAL", ""), float(V["vent_rules." + k])) for k in tkeys]
    tv.append(("DARK_DWELL", float(V["glare.DARK_DWELL_THRESHOLD"])))
    sulk = float(V["vent_rules.SPRAY_SULK"])
    cases = [(n, judge(x, 5, 30)) for n, x in tv] + [("SPRAY_SULK", judge(sulk, 30, 60))]
    add("C11", g, "즉시 반응 타이머", " / ".join(f"{n} {fs(x)}" for n, x in tv) + f" s · SPRAY_SULK {S(sulk)}",
        "게임 초", "5~30 s (SPRAY_SULK 30~60 s)", combine(cases)[1],
        "SPRAY_SULK는 쉼 길이의 토라짐이라 30~60 s로 본다. game/main/data/vent_rules.json 시간.*.값, "
        f"{cx.src('glare.DARK_DWELL_THRESHOLD')}.",
        ["vent_rules." + k for k in tkeys] + ["vent_rules.SPRAY_SULK", "glare.DARK_DWELL_THRESHOLD"])

    rc = float(V["vent_rules.REMARK_COOLDOWN"])
    add("C12", g, "REMARK_COOLDOWN", S(rc), "혼잣말 간격(전역 시계)", "60~180 s", judge(rc, 60, 180),
        f"아무 혼잣말 사이에 두는 전역 간격이다({cx.at(P_VENT, '_clock - _remark_t < REMARK_COOLDOWN')}). "
        f"{cx.src('vent_rules.REMARK_COOLDOWN')}.", ["vent_rules.REMARK_COOLDOWN"])

    la = float(V["vent_rules.LONG_AWAY"])
    lab_ = la * float(V["vent_rules.LONG_ABSENT_MULT"])
    add("C13", g, "LONG_AWAY / LONG_ABSENT", f"{S(la)} / {S(lab_)}", f"× {fn(float(V['vent_rules.LONG_ABSENT_MULT']))}",
        "'오래' 타이머 > 300 s (LONG_ABSENT만)", judge(lab_, 300),
        f"LONG_AWAY는 '오래 안 옴'이 아니다. 물건을 두고 나간 뒤 {S(la)}가 지나면 존재가 말없이 물건을 내밀고, "
        f"그 전이면 '잠깐 갔다옴'을 말한다({cx.at(P_VENT, 'away >= LONG_AWAY:')}). 그래서 대역을 걸지 않는다. "
        f"'오래 안 옴' 혼잣말은 LONG_AWAY × {fn(float(V['vent_rules.LONG_ABSENT_MULT']))} = {S(lab_)}다"
        f"({cx.at(P_VENT, 'LONG_AWAY * LONG_ABSENT_MULT')}).",
        ["vent_rules.LONG_AWAY", "vent_rules.LONG_ABSENT_MULT"])

    if cx.flag_ok("F_SUB_QUEUE"):
        add("C14", g, "자막 겹침", "대기열(최대 3줄)", "규칙 검사", "0.3 s 창에 주 신호 1개 (N13)", IN,
            f"앞 줄이 떠 있는 동안 온 줄은 기다렸다가 이어서 나온다({cx.at(P_SUBS, '_queue.append([text, seconds])')}).",
            [], ["F_SUB_QUEUE"])
    elif cx.flag_ok("F_SUB_OVERWRITE"):
        add("C14", g, "자막 겹침", "새 줄이 앞 줄을 덮어씀", "규칙 검사", "0.3 s 창에 주 신호 1개 (N13)", VIOL,
            f"place_teeth는 2~3줄, 종양 레버는 물 내림과 그림 대사를 한 프레임에 낸다. 대기열이 없다({cx.at(P_SUBS, 'label.text = text')}).",
            [], ["F_SUB_OVERWRITE"])
    else:
        add("C14", g, "자막 겹침", "재확인", "규칙 검사", "0.3 s 창에 주 신호 1개 (N13)", UNDET,
            cx.flags["F_SUB_OVERWRITE"].recheck_memo(), [], ["F_SUB_OVERWRITE"])

    # 7.5 L3 성장 ------------------------------------------------------------
    g = "L3 성장"
    pc = {k: float(v) for k, v in V["progression.POOL_COST"].items()}
    bx = [pc[b] / M.biome_E(k) for k, b in enumerate(BIOMES)]
    same04 = all(abs(pc[b] - 5 * M.m[k]) < EPS for k, b in enumerate(BIOMES))
    cases = [(SHELL_KO[k], judge(bx[k], 2, 3)) for k in range(3)]
    v = combine(cases)[1] if same04 else UNDET
    eco_calc = cx.at(P_ECON, "원정 약 60번")
    add("D01", g, "바이옴 변이 X", " / ".join(fn(pc[b]) for b in BIOMES) + "가닥", " / ".join(f2(x) for x in bx) + " E",
        "2~3 E, 현재 설계값 = 5 × m_k (2.5 E)", v,
        f"{cx.src('progression.POOL_COST')}. 2.5 E는 {eco_calc}의 계산에서 도출했다. 04는 이 값을 첫 시험용이라고 적는다"
        f"({cx.at(P_ECON, '값은 첫 시험용이다')})." + ("" if same04 else " 코드가 04의 값(5 × m_k)과 다르다."),
        ["progression.POOL_COST", "progression.SHELL_MULTIPLIER"])

    combos = run["combos"]
    add("D02", g, "조합 변이 X (E 최소 풀)",
        " / ".join(f"{c['id']} {SHELL_KO[BIOMES.index(c['pool'])]} {c['cost']}" for c in combos) + "가닥",
        " / ".join(f2(c["E"]) for c in combos) + " E", "≤ 4 E",
        combine([(c["id"], judge(c["E"], None, 4.0)) for c in combos])[1],
        f"조합 = ceil(바이옴 값 × {fn(float(V['progression.COMBO_FACTOR']))})({cx.src('progression.COMBO_FACTOR')}).",
        ["progression.COMBO_FACTOR", "progression.POOL_COST"])

    cxv = [pc["common"] / M.common_E(k) for k in range(3)]
    other_min = min(bx)
    add("D03", g, "공통 변이 X", f"{fn(pc['common'])}가닥", " / ".join(f2(x) for x in cxv) + " E",
        "≤ 10 E. 넘으면 다른 목표 X ≤ 3 E",
        IN if (max(cxv) <= 10 + EPS or other_min <= 3 + EPS) else HIGH,
        f"평행 채널이다. 핵에서 첫 공통 변이는 약 {fn(round(cxv[0]))} E에 온다. 그동안 바이옴 변이가 {f2(other_min)} E마다 있다.",
        ["progression.POOL_COST", "progression.FLESH_PER_COMMON_HAIR"])

    m10 = next((m for m in V["progression.MUTATIONS"] if m["id"] == "M10"), None)
    m10_pool = V["progression.BRANCH_POOL"][m10["branch"]] if m10 else "core"
    m10_cost = pc[m10_pool]
    kk = BIOMES.index(m10_pool)
    xs = [m10_cost / M.biome_E(kk, u) for u in us]
    add("D04", g, "첫 변이 (M10, 핵 털 5)", f"{SHELL_KO[kk]} 털 {fn(m10_cost)}가닥",
        f"{f2(m10_cost / M.biome_E(kk))} E = 원정 " + " / ".join(f"{f2(x)}번({fn(u)} u)" for x, u in zip(xs, us)),
        "1 < X ≤ 3 E (가정)",
        combine([(ulab(u), (LOW if x <= 1 + EPS else judge(x, None, 3))) for u, x in zip(us, xs)])[1],
        f"하한은 첫 방문에서는 아직 못 산다는 문장({cx.at(P_FIRST10, '첫 방문에서는 아직 못 산다')})에서, 상한 3 E는 가정이다. "
        f"첫 변이는 오른손 마디가 늘어나는 M10이다({cx.at(P_FIRST10, '## 첫 변이')}).",
        ["progression.POOL_COST", "progression.FLESH_PER_BIOME_HAIR"])

    cons4 = ["barrier", "canary_feed"]
    add("D05", g, "4이빨 소모품", " · ".join(f"{ITEM_KO[i]} {M.price(i)}개" for i in cons4),
        " / ".join(f2(M.price(i) / M.exp_teeth) for i in cons4) + " E", "0.5~1 E",
        combine([(ITEM_KO[i], judge(M.price(i) / M.exp_teeth, 0.5, 1.0)) for i in cons4])[1],
        f"가격 = max(1, round(값 × 8))({cx.at(P_PROG, 'func price_for')}).", ["progression.PRICE_UNITS"])

    big = sorted([i for i in pu if M.price(i) >= 8], key=lambda i: M.price(i))
    if cx.flag_ok("F_TRADE_SUM"):
        v = IN
        memo = (f"이빨을 하나씩 집고 올리며 환풍구가 한 거래의 합계로 감정한다({cx.at(P_MAIN, 'func place_tooth_at_vent() -> bool:')}, "
                f"{cx.at(P_VENT, 'return place_teeth(trade_paid, prog)')}). 모든 물건에 정상 입력으로 닿는다.")
    else:
        v, memo = UNDET, cx.flags["F_TRADE_SUM"].recheck_memo()
    add("D06", g, "8이빨 이상 물건", " / ".join(f"{ITEM_KO.get(i, i)} {M.price(i)}" for i in big) + "개",
        " / ".join(f2(M.price(i) / M.exp_teeth) for i in big) + " E", "한 거래 합계로 닿음", v, memo,
        ["progression.PRICE_UNITS"], ["F_TRADE_SUM"])

    saw_x = M.price("big_saw") / M.exp_teeth
    add("D07", g, "큰 톱 저축", f"{M.price('big_saw')}개", f"{f2(saw_x)} E", "≤ 10 E", judge(saw_x, None, 10),
        "지표면이 열릴 때 이미 살 수 있을 수 있다.", ["progression.PRICE_UNITS"])

    tum_shell = M.tumors_by_shell()
    tumors_total = sum(tum_shell)
    tum_teeth = tumors_total * float(V["progression.TUMOR_TOOTH_PAYOUT"])
    cons_demand, cons_src = M.consumable_demand()
    sp = M.spray_demand()
    t_supply = run["teeth_supply"] + tum_teeth
    t_demand = run["tools_oneoff"] + cons_demand
    sd_t = t_supply / t_demand
    cons_note = " (소모품 미정)" if cons_demand <= 0 else ""
    sd_trunk = t_supply / (run["tools_oneoff"] + sp["trunk_teeth"])
    afford = (t_supply - run["tools_oneoff"]) / sp["teeth"] if sp["teeth"] > 0 else math.inf
    if cons_src == "스프레이 통로망":
        cons_memo = (f"소모품은 스프레이 통로망이다: 줄기 {f2(sp['trunk_m'])} m + 쉼터 가지 {f2(sp['branch_m'])} m "
                     f"= {f2(sp['route_m'])} m, 1 m에 {f2(sp['per_m'][sp['best']])}개"
                     f"(싼 통 {f2(sp['per_m']['spray_cheap'])} · 비싼 통 {f2(sp['per_m']['spray_deep'])}, "
                     f"{cx.src('spray_can.SPRAYS_PER_CAN')}). 뿌린 셀은 다시 자라지 않는다({cx.at(P_FIELD, 'sealed, never')}). "
                     f"이빨로 통로망의 {f2(min(afford, 9.99) * 100)}%를 영구로 만든다. "
                     f"줄기만 뿌리면 SD {f2(sd_trunk)}라 남는다: 이빨의 쓰임은 쉼터까지 이어지는 영구 통로다.")
    else:
        cons_memo = "소모품 기준 수요는 정하기 전까지 0이다."
    add("D08", g, "이빨 공급/수요", f"공급 {fu(t_supply)}(원정 {fu(run['teeth_supply'])} + 종양 {fn(tum_teeth)}) / "
        f"수요 {fn(round(t_demand, 1))}개(일회성 도구 {fn(run['tools_oneoff'])} + {cons_src} {fn(round(cons_demand, 1))})",
        f"{f2(sd_t)}{cons_note}", "≤ 1.5", judge(sd_t, None, 1.5),
        f"일회성 도구: {', '.join(ITEM_KO.get(i, i) for i in M.oneoff_tools())}. 종양은 모두 정산한 상한으로 셌다. "
        + cons_memo + " 이빨 SD는 가격으로 맞추지 않고 이빨의 쓰임으로 푼다(N12).",
        ["progression.TEETH_PER_FLESH", "progression.PRICE_UNITS", "progression.TUMOR_TOOTH_PAYOUT",
         "spray_can.SPRAYS_PER_CAN", "spray_can.CHEAP_DEPTH", "spray_can.DEEP_DEPTH", "world_features.REST_PER_SHELL"])

    tp = float(V["progression.TUMOR_TOOTH_PAYOUT"])
    delta = tp / M.exp_teeth
    beta = float(A["tumor_point_value_E"]) / (tp / M.exp_teeth)
    add("D09", g, "종양 정산", f"{fn(tp)}개 = {f2(tp / M.exp_teeth)} E", f"Δ {f2(delta)}(힌트: 보이는 종양) · β {f2(beta)}",
        "Δ ≥ 3이면 힌트, β 0.5~2", judge(beta, 0.5, 2.0),
        f"먹기는 혹 1개 = {fn(float(A['tumor_point_value_E']))} E로 본다. core_knot 덤 이빨(03-restroom.md:114)은 구현되지 않았다.",
        ["progression.TUMOR_TOOTH_PAYOUT"])

    kinds = len(V["progression.TUMOR_KINDS"])
    nt = len(V["progression.TUMOR_MUTATIONS"])
    enough = tumors_total >= kinds + nt
    add("D10", g, "종양 공급", f"{tumors_total}개 ({' / '.join(str(x) for x in tum_shell)})",
        f"필요 {kinds + nt}개 (도감 {kinds} + 종양 변이 {nt})", "공급 ≥ 필요",
        IN if enough else LOW,
        "공급이 필요 이상이다." if enough else
        "도감과 종양 변이를 다 채울 수 없다. 의도라면 decisions/에 기록한다.",
        ["world_features.TUMORS_PER_SHELL", "progression.TUMOR_KINDS", "progression.TUMOR_MUTATIONS"])

    dr = M.draws(E_run)
    add("D11", g, "혹 추첨 G", f"비복원 {nt}장", f2(dr["G"]), "≤ 2", judge(dr["G"], None, 2.0),
        "특정 결과를 노릴 수 없어서 상한값이다.", ["progression.TUMOR_MUTATIONS"])

    max_offer = int(V["progression.VENT_MAX_OFFER"])
    core_prices = sorted(M.price(i) for i in pu if int(V["progression.UNLOCK_SHELL"][i]) == 0)
    # the first slot is the dearest affordable item; the rest are drawn from
    # what is left, so the mix varies once max_offer or more items remain
    rand_from = core_prices[max_offer] if len(core_prices) > max_offer else None
    if cx.flag_ok("F_TRADE_SUM"):
        v = IN if rand_from is not None else UNDET
        memo = ("제안 구성의 무작위는 남은 후보가 " + str(max_offer) + "개 이상일 때"
                + (f"(핵에서 한 거래 {rand_from}개)" if rand_from else "") + "부터다. 1번 칸은 결정적으로 낸 값으로 살 최고 해금 물건이다. "
                "적게 내면 잡동사니, 거스름돈 없음, 안 집으면 돌려주지 않음은 승인된 흥정이다(03-restroom.md). "
                f"한 거래 합계로 감정하므로 무작위 구간에 닿는다({cx.at(P_PROG, 'func vent_offer')}).")
    else:
        v, memo = UNDET, cx.flags["F_TRADE_SUM"].recheck_memo()
    add("D12", g, "환풍구 제안 변동", f"무작위 시작 {rand_from}개" if rand_from else "무작위 없음",
        "1번 칸 결정 + 나머지 추첨", "1번 칸 = 낸 값으로 살 최고 해금 물건(V5)",
        v, memo, ["progression.VENT_MAX_OFFER", "progression.PRICE_UNITS"], ["F_TRADE_SUM"])

    td = V["world_features.TUMOR_DEPTH"]
    add("D13", g, "발견 간격", f"{dr['discovery_count']}번", f"{f2(dr['discovery_interval'])} E", "2~6 E",
        judge(dr["discovery_interval"], 2, 6),
        f"종양 {dr['tumors']} + 껍질 진입 {int(V['world_features.SHELL_COUNT']) - 1} + 새 재고 {dr['new_stock']} + "
        f"새 조직 {int(A['new_tissue_sightings'])}. 회차 평균이라 한 원정에 몰리는 경우는 D18에서 본다.",
        ["world_features.TUMORS_PER_SHELL", "world_features.TUMOR_DEPTH", "progression.UNLOCK_SHELL"])

    add("D14", g, "몸 변화 간격", f"{dr['body_changes']}번", f"{f2(dr['body_interval'])} E", "1.5~4 E",
        judge(dr["body_interval"], 1.5, 4), f"털 변이 {len(V['progression.MUTATIONS'])} + 종양 변이 {nt}.",
        ["progression.MUTATIONS", "progression.TUMOR_MUTATIONS"])

    dead = [fn_ for fn_, c in cx.unwired.items() if c == 0]
    add("D15", g, "미작동 변이", f"미연결 함수 {len(dead)} / {len(UNWIRED)}",
        ", ".join(UNWIRED[f] for f in dead) or "없음", "0 (N16)", VIOL if dead else IN,
        ("호출되지 않는 함수: " + ", ".join(dead) + ". 털을 내도 효과가 없다.") if dead else "모든 효과 함수가 호출된다.",
        ["progression.MUTATIONS"], ["F_UNWIRED"])

    if cx.flag_ok("F_BUMP_MIRROR_ONLY"):
        v, memo = LOW, f"혹은 거울과 Tab에서만 보인다({cx.at(P_MIRROR_BODY, '_extras.append(_bump(i, false))')})."
    else:
        v, memo = UNDET, cx.flags["F_BUMP_MIRROR_ONLY"].recheck_memo()
    tx = float(A["tumor_point_value_E"])
    add("D16", g, "배 혹 운반체", f"혹 1개 X 약 {f2(tx)} E → {grade(tx)}", "거울과 Tab에서만 보임",
        "I3: 평소 시야의 영구 운반체", v, memo, [], ["F_BUMP_MIRROR_ONLY"])

    ek = run["E_k"]
    core_branch7 = 7 * pc["core"] / M.biome_E(0)
    add("D17", g, "껍질당 원정", " / ".join(f2(x) for x in ek) + " E", f"수요 {' / '.join(fn(run['demand'][b]) for b in BIOMES)}가닥",
        "20~30 E (가정)", [(SHELL_KO[k], judge(ek[k], 20, 30)) for k in range(3)],
        f"조합 변이는 E가 작은 풀로 셌다. 대역은 '껍질마다 원정 약 20번'({eco_calc}) + 가정이고, 04는 상한을 적지 않았다. "
        f"04처럼 핵 가지 7개({fn(7 * pc['core'])}가닥)로 세면 핵은 {f2(core_branch7)} E다. 핵 기준을 어느 쪽으로 둘지는 정해야 한다.",
        ["progression.POOL_COST", "progression.MUTATIONS"])

    td = V["world_features.TUMOR_DEPTH"]
    tcases, tvals = [], []
    for k in range(min(3, len(tum_shell))):
        iv = ek[k] / tum_shell[k] if tum_shell[k] > 0 else math.inf
        tvals.append(iv)
        tcases.append((SHELL_KO[k], judge(iv, 2, 6)))
    add("D18", g, "종양 만남 간격 (껍질별)", " / ".join(f"{SHELL_KO[k]} {tum_shell[k]}개" for k in range(len(tvals))),
        " / ".join(f"{f2(x) if x != math.inf else '∞'} E" for x in tvals), "그 껍질 E_k ÷ 종양 수 2~6 E, 최대 간격 ≤ 2 × 평균 (가정)",
        combine(tcases)[1],
        f"E_k는 D17이다. 종양은 껍질마다 한 깊이의 고리에 놓인다(TUMOR_DEPTH {' / '.join(fn(x) for x in td)} m). "
        "그래서 한 원정에 몰아 만날 수 있고, 최대 간격(가뭄 G)은 배치 실측이 있어야 판정한다.",
        ["world_features.TUMORS_PER_SHELL", "world_features.TUMOR_DEPTH"])

    # 7.6 L4 회차 ------------------------------------------------------------
    g = "L4 회차"
    trips = [M.trips(E_run, u) for u in us]
    ok = abs(sum(ek) + run["common_extra"] + run["teeth_extra"] - E_run) < 1e-6
    add("E01", g, "회차 원정 단위", f"E_run {f2(E_run)} E ({' + '.join(f2(x) for x in ek)})",
        "원정 " + " / ".join(f"{f2(t)}번" for t in trips) + f" ({' / '.join(ulab(u) for u in us)})", "E_k 합 = E_run",
        IN if ok else UNDET,
        f"공통 털 보충 {f2(run['common_extra'])} E, 이빨 보충 {f2(run['teeth_extra'])} E.",
        ["progression.POOL_COST", "progression.MUTATIONS", "progression.PRICE_UNITS"])

    ha = [t * M.T_E / 3600 for t in trips]
    he = []
    for t, u in zip(trips, us):
        lo, hi = M.T_E_basis("core_bare", u)
        he.append((t * lo / 3600, t * hi / 3600))
    req = [14400 / t for t in trips]
    add("E02", g, "회차 시간", "원정 " + " / ".join(f"{f2(t)}번" for t in trips),
        f"가정 {' / '.join(f2(x) for x in ha)} h · {est_label} {' / '.join(rng(*x) for x in he)} h", "4~6 h",
        [(ulab(u), judge(x, 4, 6)) for u, x in zip(us, ha)],
        "4시간 회차에는 T_E " + " 또는 ".join(f"{S(r)}({ulab(u)})" for r, u in zip(req, us)) + "가 필요하다. "
        f"가정 쪽은 u와 상관없이 T_E를 {S(M.T_E)}로 두므로 {ulab(us[-1])} 판정은 '그 원정도 {S(M.T_E)}라면'이라는 뜻이다. "
        f"{est_label} T_E는 핵 맨손 장면이고 u와 함께 늘어난다.",
        ["progression.POOL_COST", "progression.TEETH_PER_FLESH"],
        cases_e=[(ulab(u), judge_mid(x[0], x[1], 4, 6)) for u, x in zip(us, he)], est_label=est_label)

    caps = [M.C, M.C + 20, M.C + 60, 2 * M.C, 2 * (M.C + 20)]
    sweep = [(c, M.trips(E_run, c)) for c in caps if c != M.C]
    # 추정: 그 용량까지 채우는 원정(과식 없음)의 F10 T_E. 실측이 있으면 T_E_basis가 실측을 준다.
    est_h = []
    for c, t in sweep:
        mc = M.with_capacity(c)
        lo, hi = mc.T_E_basis("core_bare", c)
        est_h.append((t * lo / 3600, t * hi / 3600))
    add("E03", g, "용량 효과", "C_eff " + " / ".join(fn(c) for c, _ in sweep) + " u",
        "원정 " + " / ".join(f2(t) for _, t in sweep) + "번 → 가정 " + " / ".join(f2(t * M.T_E / 3600) for _, t in sweep)
        + f" h (T_E {fn(M.T_E)} s 고정) · {est_label} " + " / ".join(rng(*x) for x in est_h) + " h", "4~6 h",
        [(fn(c), judge(t * M.T_E / 3600, 4, 6)) for c, t in sweep],
        f"{fn(M.C + 20)}은 M01, {fn(2 * M.C)}은 T4, {fn(2 * (M.C + 20))}은 T4 + M01이다. 가정 쪽은 T_E를 고정해서 용량이 클수록 "
        "회차가 짧아지는 것이 식의 결과일 뿐이다. 추정 쪽은 원정 시간이 용량과 함께 늘어 회차 길이가 거의 같다. 털 수요가 고정이면 "
        "씹는 시간 총합도 거의 같고, 줄어드는 것은 원정마다 드는 이동과 의식 시간뿐이다.",
        ["progression.BASE_CAPACITY"],
        cases_e=[(fn(c), judge_mid(x[0], x[1], 4, 6)) for (c, _), x in zip(sweep, est_h)], est_label=est_label)

    sdc = run["common_supply"] / run["common_demand"]
    add("E04", g, "공통 털 공급/수요", f"공급 {fu(run['common_supply'])} / 수요 {fn(run['common_demand'])}가닥", f2(sdc),
        "0.8~1.2", judge(sdc, 0.8, 1.2), "털 변이를 다 사는 동안 자라는 공통 털이다.",
        ["progression.FLESH_PER_COMMON_HAIR", "progression.POOL_COST"])

    if ms and ms.get("TE_by_shell") and 0 in ms["TE_by_shell"] and len(ms["TE_by_shell"]) > 1:
        base = ms["TE_by_shell"][0]
        cases = [(SHELL_KO[k], IN if M.m[k] / M.m[0] >= v_ / base - EPS else LOW) for k, v_ in sorted(ms["TE_by_shell"].items()) if k > 0]
        add("E05", g, "껍질 시간 중립 (F12)", " / ".join(f"{SHELL_KO[k]} {S(v_)}" for k, v_ in sorted(ms["TE_by_shell"].items())),
            "m_k ÷ m_0 = " + " / ".join(fn(x / M.m[0]) for x in M.m), "m_k ÷ m_0 ≥ T_E(k) ÷ T_E(0)", cases, "실측 T_E 중앙값.")
    else:
        add("E05", g, "껍질 시간 중립 (F12)", "—", "m_k ÷ m_0 = " + " / ".join(fn(x / M.m[0]) for x in M.m),
            "m_k ÷ m_0 ≥ T_E(k) ÷ T_E(0)", UNDET, "껍질별 실측 T_E(M04)가 필요하다.", ["progression.SHELL_MULTIPLIER"])

    if ms and ms.get("M09"):
        r9 = ms["M09"]
        add("E06", g, "전진 우위 (F14)", " / ".join(f"{k} {f2(v_)}" for k, v_ in r9.items()), "실측 M09", "≥ 1",
            combine([(k, judge(v_, 1.0)) for k, v_ in r9.items()])[1], "바깥 ÷ 문 앞 분당 수익.")
    else:
        add("E06", g, "전진 우위 (F14)", "—", "—", "≥ 1", UNDET,
            "실측 M09가 필요하다. 이빨에는 깊이 배율이 없고, 다시 찬 셀도 값을 다 준다(B12).", ["progression.TEETH_PER_FLESH"])

    dsh = M.door_shortcut()
    if dsh["est_independent"]:
        e07_e, e07_note = judge_mid(*dsh["r_est"], 0.5), " 실측 T_E를 T_ref로 썼다."
    else:
        e07_e = UNDET
        e07_note = (" 추정 쪽은 미정이다. F10 추정 T_E는 T_min에 이동만 더한 값이라 r이 이동 비율만 잰다(독립 기준이 아니다). "
                    "실측 T_E나 바깥 껍질 루프가 있어야 판정한다.")
    add("E07", g, "최단 경로 r (문 앞)", f"T_min {rng(*dsh['T_min'], fs)} s",
        f"가정 {rng(*dsh['r_assumed'])} · {est_label} {rng(*dsh['r_est'])}", "≥ 0.5",
        judge_mid(*dsh["r_assumed"], 0.5),
        f"T_min = T_dig(핵 맨손, {fn(M.u_E)} u) + 의식 시간. 하한끼리, 상한끼리 짝지었다." + e07_note,
        ["progression.BASE_CHEW_TIME"], cases_e=e07_e, est_label=est_label)

    idl = [M.idle(k) for k in range(3)]
    add("E08", g, "M22 무입력", "지속 " + " / ".join(f2(x["ratio"]) for x in idl), f"폭발 {f2(idl[0]['burst_ratio'])}",
        "≤ 0.25", combine([(SHELL_KO[k], judge(idl[k]["ratio"], None, 0.25)) for k in range(3)])[1],
        f"처음 {idl[0]['burst']}셀 폭발은 능동의 {fn(round(100 * idl[0]['burst_ratio']))}%로 진행된다. 실측 M08이 필요하다(추정).",
        ["progression.ALIEN_HAND_PERIOD", "progression.BASE_REACH", "main.BODY_PROTECT_RADIUS"])

    add("E09", g, "소진 인계 (N12)", "—", "—", "남은 목표가 보임", UNDET,
        f"변이를 다 산 뒤에도 털이 자란다. 도구를 다 사면 이빨 쓸 곳은 소모품뿐이다. 종양 변이 {nt}개 뒤에는 혹이 생기지 않는다.",
        ["progression.TUMOR_MUTATIONS"])

    f_rng = cx.flags.get("F_RNG_SAVED")
    rng_at = cx.at(P_PROG, '"rng": _rng_state')
    if f_rng and f_rng.ok:
        add("E10", g, "벽시계 시간·돈·재추첨", "벽시계 시간 호출 0개 · 무작위 상태 저장", "규칙 검사",
            "벽시계 시간 보상 0, 무작위 상태 저장 (N4, N5)", IN,
            f"진행 LCG가 저장된다({rng_at}).", [], ["F_RNG_SAVED"])
    else:
        add("E10", g, "벽시계 시간·돈·재추첨", "재확인", "규칙 검사", "벽시계 시간 보상 0, 무작위 상태 저장 (N4, N5)", UNDET,
            f_rng.recheck_memo() if f_rng else "재확인 필요", [], ["F_RNG_SAVED"])

    if ms:
        rows += ms["rows"]
    return rows


# ---------------------------------------------------------------------------
# 실측 기록 (--log)
# ---------------------------------------------------------------------------

LOG_COLS = ["t", "phase", "shell", "channel", "code", "du", "dteeth", "dhair_biome", "dhair_common", "dtumor",
            "fill", "x", "y", "z", "sound", "arm_visible", "input_active"]
POSITIVE = set("SADRB")
T_FILL_GAP_MAX = 2.0


def read_log_text(text: str) -> list[dict]:
    rdr = list(csv.reader(io.StringIO(text)))
    rdr = [r for r in rdr if r and any(c.strip() for c in r)]
    if not rdr:
        return []
    if rdr[0][0].strip().lower() == "t":
        hdr = [c.strip() for c in rdr[0]]
        body = rdr[1:]
    else:
        hdr, body = LOG_COLS, rdr
    out = []
    for r in body:
        d = dict(zip(hdr, [c.strip() for c in r]))

        def num(k, cast=float):
            try:
                return cast(float(d.get(k, "") or 0))
            except ValueError:
                return cast(0)
        out.append({"t": num("t"), "phase": d.get("phase", "").upper(), "shell": num("shell", int),
                    "channel": d.get("channel", "").upper(), "code": d.get("code", ""), "du": num("du"),
                    "dteeth": num("dteeth"), "dhair": num("dhair_biome") + num("dhair_common"), "dtumor": num("dtumor"),
                    "fill": num("fill"), "x": num("x"), "y": num("y"), "z": num("z"), "sound": num("sound", int),
                    "arm": num("arm_visible", int), "input": num("input_active", int)})
    out.sort(key=lambda e: e["t"])
    return out


def _quart(xs: list[float]) -> tuple[float, float, float]:
    xs = sorted(xs)
    if len(xs) == 1:
        return xs[0], xs[0], xs[0]
    q = statistics.quantiles(xs, n=4, method="inclusive")
    return q[0], statistics.median(xs), q[2]


def analyse_log(ev: list[dict], model: Model) -> dict:
    res: dict = {"rows": []}
    if not ev:
        return res
    t0 = ev[0]["t"]
    tears = [e for e in ev if e["code"] == "R-TEAR"]
    res["M01"] = (tears[0]["t"] - t0) if tears else None

    starts = [i for i, e in enumerate(ev) if e["phase"] == "B" and (i == 0 or ev[i - 1]["phase"] != "B")]
    exps = []
    for n, s in enumerate(starts):
        end = starts[n + 1] if n + 1 < len(starts) else len(ev)
        seg = ev[s:end]
        complete = n + 1 < len(starts) or seg[-1]["phase"] == "A"
        if not complete:
            continue
        t_end = ev[end]["t"] if end < len(ev) else seg[-1]["t"]
        T_E = t_end - ev[s]["t"]
        b_tears = [e["t"] for e in seg if e["phase"] == "B" and e["code"] == "R-TEAR"]
        T_fill = sum(b - a for a, b in zip(b_tears, b_tears[1:]) if b - a <= T_FILL_GAP_MAX)
        shell = max((e["shell"] for e in seg if e["phase"] == "B"), default=0)
        pos = [e for e in seg if e["channel"] in POSITIVE]
        holes = 0
        for a, b in zip(pos, pos[1:]):
            gap = b["t"] - a["t"]
            # 굴착(B)만 잰다. 귀환(C)의 긴 정적은 의도라서 빈 구간으로 세지 않는다.
            if a["phase"] == "B" and gap > 10:
                holes += 1
        a_rows = [e["t"] for e in seg if e["phase"] == "A"]
        rest = (t_end - a_rows[0]) if a_rows else None
        exps.append({"T_E": T_E, "T_fill": T_fill, "kappa": T_fill / T_E if T_E > 0 else 0, "shell": shell,
                     "pos": len(pos), "holes": holes, "rest": rest})
    res["exps"] = exps
    by_shell: dict[int, list] = {}
    for x in exps:
        by_shell.setdefault(x["shell"], []).append(x)
    res["TE_by_shell"] = {k: statistics.median([x["T_E"] for x in v]) for k, v in by_shell.items()}
    res["TE_q"] = {k: _quart([x["T_E"] for x in v]) for k, v in by_shell.items()}
    res["TE_all"] = _quart([x["T_E"] for x in exps]) if exps else None
    rests = [x["rest"] for x in exps if x["rest"] is not None]
    res["rest_median"] = statistics.median(rests) if rests else None

    chans: dict[str, list[float]] = {}
    for e in ev:
        chans.setdefault(e["channel"], []).append(e["t"])
    res["M02"] = {}
    for c, ts in sorted(chans.items()):
        gaps = [b - a for a, b in zip(ts, ts[1:])]
        if gaps:
            res["M02"][c] = (statistics.mean(gaps), statistics.pvariance(gaps))
    res["M03"] = sum(x["holes"] for x in exps) if exps else None

    if len(exps) >= 2:
        xs = list(range(len(exps)))
        ys = [x["pos"] for x in exps]
        mx, my = statistics.mean(xs), statistics.mean(ys)
        den = sum((a - mx) ** 2 for a in xs)
        res["M05"] = sum((a - mx) * (b - my) for a, b in zip(xs, ys)) / den if den else 0.0
    else:
        res["M05"] = None

    st = [e["t"] for e in ev if e["sound"] == 1]
    over, i = 0, 0
    while i < len(st):
        j = i
        while j + 1 < len(st) and st[j + 1] - st[i] < 0.3:
            j += 1
        if j > i:
            over += 1
        i = j + 1
    res["M06"] = over

    leads, last_warn = [], None
    for e in ev:
        if e["channel"] != "T":
            continue
        if "WARN" in e["code"].upper() or e["code"] == "K-CANARY":
            last_warn = e["t"]
        elif e["code"] in ("K-CONTR", "K-NERVE", "K-CRUSH"):
            leads.append(e["t"] - last_warn if (last_warn is not None and e["t"] - last_warn <= 10) else 0.0)
    res["M07"] = min(leads) if leads else None

    idle_t = act_t = idle_u = act_u = 0.0
    for a, b in zip(ev, ev[1:]):
        dt = b["t"] - a["t"]
        if a["input"]:
            act_t += dt
        else:
            idle_t += dt
    for e in ev:
        if e["input"]:
            act_u += e["du"]
        else:
            idle_u += e["du"]
    res["M08"] = ((idle_u / idle_t) / (act_u / act_t)) if (idle_t > 0 and act_t > 0 and act_u > 0) else None

    max_shell = max((e["shell"] for e in ev if e["phase"] == "B"), default=0)
    door_r = model.door + 3.0
    zones = {"door": [0.0, 0.0, 0.0], "outer": [0.0, 0.0, 0.0]}  # 시간, u, 털
    for a, b in zip(ev, ev[1:] + [None]):
        if a["phase"] != "B":
            continue
        dt = (b["t"] - a["t"]) if b else 0.0
        r = math.sqrt(a["x"] ** 2 + a["y"] ** 2 + a["z"] ** 2)
        zone = None
        if a["shell"] == 0 and r <= door_r:
            zone = "door"
        elif max_shell > 0 and a["shell"] == max_shell:
            zone = "outer"
        if zone:
            zones[zone][0] += dt
            zones[zone][1] += a["du"]
            zones[zone][2] += a["dhair"]
    if zones["door"][0] > 0 and zones["outer"][0] > 0:
        out = {}
        for idx, name in ((1, "u"), (2, "털")):
            d_rate = zones["door"][idx] / zones["door"][0]
            o_rate = zones["outer"][idx] / zones["outer"][0]
            if d_rate > 0:
                out[name] = o_rate / d_rate
        res["M09"] = out or None
    else:
        res["M09"] = None

    hairs = [e for e in ev if e["code"].startswith("R-HAIR")]
    res["M10"] = (sum(1 for e in hairs if e["arm"]) / len(hairs)) if hairs else None
    return res


def measured_rows(res: dict, model: Model) -> list[Row]:
    g = "실측"
    rows = []
    te = model.t_escape()

    def add(id_, label, cur, scale, band, verdict, memo):
        rows.append(make_row(id_, g, label, cur, scale, band, verdict, memo))

    v = res.get("M01")
    add("M01", "첫 뜯기", "—" if v is None else S(v), "첫 R-TEAR", "≤ 30 s", UNDET if v is None else judge(v, None, 30),
        "기록 시작부터 첫 R-TEAR까지.")
    m2 = res.get("M02") or {}
    add("M02", "채널 간격", " / ".join(f"{c} {fs(m)}±{fs(math.sqrt(var))}" for c, (m, var) in m2.items()) or "—",
        "평균±표준편차 s", "참고", IN if m2 else UNDET, "Cook(2006)의 채널별 평균 간격에 이 문서가 분산을 더했다.")
    v = res.get("M03")
    add("M03", "빈 구간 (굴착)", "—" if v is None else f"{v}개", "B > 10 s", "원정당 0개",
        UNDET if v is None else (IN if v == 0 else HIGH),
        "굴착 구간의 양(+) 사건 사이 공백. 귀환 구간은 재지 않는다. 대역을 넘어도 보상 사건을 더해서 고치지 않는다.")
    exps = res.get("exps") or []
    if exps:
        cases, cur = [], []
        for k in sorted(res["TE_q"]):
            q1, md, q3 = res["TE_q"][k]
            kap = statistics.median([x["kappa"] for x in exps if x["shell"] == k])
            cur.append(f"{SHELL_KO[k]} T_E {fs(md)}({rng(q1, q3, fs)}) s κ {f2(kap)}")
            cases.append((f"{SHELL_KO[k]} T_E", judge(md, 180, 300)))
            cases.append((f"{SHELL_KO[k]} κ", judge(kap, 0.2, 0.5)))
        add("M04", "원정", " / ".join(cur), f"원정 {len(exps)}번", "T_E 180~300 s, κ 0.2~0.5", cases,
            f"T_fill은 B 구간 R-TEAR 사이 {fn(T_FILL_GAP_MAX)} s 이하 간격의 합이다.")
    else:
        add("M04", "원정", "—", "완료한 원정 없음", "T_E 180~300 s, κ 0.2~0.5", UNDET, "B 구간 시작으로 원정을 나눈다.")
    v = res.get("M05")
    add("M05", "회차 추세", "—" if v is None else f"기울기 {f2(v)}건/원정", "원정 번호별 양(+) 사건 수", "감시",
        UNDET if v is None else IN, "리텐션 지표가 아니다. 지켜보기만 한다.")
    v = res.get("M06")
    add("M06", "겹침", "—" if v is None else f"{v}개", "0.3 s 창 안 소리 2개 이상", "0", UNDET if v is None else (IN if v == 0 else HIGH),
        "소리가 난 줄을 주 신호로 본다.")
    v = res.get("M07")
    add("M07", "앞섬", "—" if v is None else S(v), f"t_escape {S(te)}", f"≥ {S(0.5 + te)}", UNDET if v is None else judge(v, 0.5 + te),
        "가장 짧은 예고 → 피해 간격. 예고가 없으면 0이다.")
    v = res.get("M08")
    add("M08", "무입력", "—" if v is None else f2(v), "무입력 u/분 ÷ 능동 u/분", "≤ 0.25", UNDET if v is None else judge(v, None, 0.25),
        "입력이 없던 구간의 섭취율.")
    v = res.get("M09")
    add("M09", "전진 우위", "—" if not v else " / ".join(f"{k} {f2(x)}" for k, x in v.items()), "바깥 ÷ 문 앞 분당", "≥ 1",
        UNDET if not v else combine([(k, judge(x, 1.0)) for k, x in v.items()])[1], "문 앞은 핵에서 문 깊이 + 3 m 안이다.")
    v = res.get("M10")
    add("M10", "털 지각", "—" if v is None else f2(v), "R-HAIR 중 팔뚝이 보인 비율", "관찰 (대역 없음)",
        UNDET if v is None else IN,
        "관찰 지표다. 팔·Tab 자세를 바꾸는 해법은 승인 기준과 대조해야 한다(CLAUDE.md).")
    return rows


# ---------------------------------------------------------------------------
# 출력
# ---------------------------------------------------------------------------

def git_label(repo_root: Path) -> str:
    try:
        h = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=repo_root, capture_output=True, text=True,
                           timeout=10)
        if h.returncode != 0:
            return "git 알 수 없음"
        s = subprocess.run(["git", "status", "--porcelain", "--untracked-files=no"], cwd=repo_root,
                           capture_output=True, text=True, timeout=20)
        dirty = " + 작업 트리 변경" if s.returncode == 0 and s.stdout.strip() else ""
        return f"git {h.stdout.strip()}{dirty}"
    except (OSError, subprocess.SubprocessError):
        return "git 알 수 없음"


def header_line(model: Model, git: str, as_of: str = "", virtual: str | None = None) -> str:
    """표 머리. 날짜는 실행일이 아니라 params.json의 as_of라서 같은 입력이면 표가 바뀌지 않는다."""
    A = model.A
    tools = "/".join(f"{SHELL_KO[k]} {TOOL_KO.get(t, t)}" for k, t in enumerate(model.tool_by_shell))
    virt = f"가상 값: {virtual} · " if virtual else ""
    return (f"{virt}생성: {TOOL_LABEL} · params {as_of or '날짜 없음'} · {git} · 가정: T_E {fn(model.T_E)} s, "
            f"겨눔 {fn(model.a)} s, 의식 {fn(model.ritual[0])}~{fn(model.ritual[1])} s, "
            f"탈출 {model.escape[0]}/{model.escape[1]}셀, 문 깊이 {fn(model.door)} m, "
            f"통로 {fn(model.u_per_m[0])}/{fn(model.u_per_m[1])} u/m, 기대 도구 {tools}, "
            f"혹 {fn(float(A['tumor_point_value_E']))} E, 새 조직 {int(A['new_tissue_sightings'])}번, "
            f"전형 죽음 {fn(float(A['death_typical_fill']))} u + 방벽 {int(A['death_typical_barriers'])}, "
            f"무입력 창 {fn(float(A['idle_window']))} s"
            + (f", 종양 껍질별 {'/'.join(str(x) for x in A['tumors_by_shell'])}" if A.get("tumors_by_shell") else "")
            + (f", 소모품 이빨 수요 {fn(float(A['consumable_teeth_demand']))}" if A.get("consumable_teeth_demand") is not None
               else f", 스프레이 쉼터 가지 {fn(float(A.get('spray_rest_share') if A.get('spray_rest_share') is not None else 1.0) * 100)}%")
            + (f", 일회성 도구 {'/'.join(A['oneoff_tools'])}" if A.get("oneoff_tools") and list(A["oneoff_tools"]) != ONEOFF_TOOLS else ""))


def cell(s: str) -> str:
    return s.replace("|", "\\|").replace("\n", " ")


def summary(rows: list[Row], attr: str) -> str:
    counts = {v: 0 for v in VERDICT_ORDER}
    for r in rows:
        counts[getattr(r, attr)] = counts.get(getattr(r, attr), 0) + 1
    return " · ".join(f"{v} {counts[v]}" for v in VERDICT_ORDER)


def render(rows: list[Row], header: str, layout: str, est_label: str, has_log: bool) -> str:
    out = ["<!-- AUDIT_TABLE:BEGIN -->", header, ""]
    for g in GROUPS:
        out.append(f"**{g}**")
        out.append("")
        grp = [r for r in rows if r.group == g]
        if g == "실측" and not has_log:
            out.append("실측 기록 없음: M01-M10 미정")
            out.append("")
            continue
        if layout == "spec":
            out.append("| ID | 수치 | 현재 | 척도 값 | 대역 | 판정 | 메모 |")
            out.append("|---|---|---|---|---|---|---|")
            for r in grp:
                out.append("| " + " | ".join(cell(x) for x in (r.id, r.label, r.current, r.scale, r.band, r.cell, r.memo)) + " |")
        else:
            out.append("| 항목 | 현재값 | 척도 위의 값 | 목표 범위 | 판정 | 근거 |")
            out.append("|---|---|---|---|---|---|")
            for r in grp:
                out.append("| " + " | ".join(cell(x) for x in (f"{r.id} {r.label}", r.current, r.scale, r.band, r.cell, r.memo)) + " |")
        out.append("")
    out.append(f"판정 합계(가정 기준): {summary(rows, 'va')}")
    out.append(f"판정 합계({est_label} 기준): {summary(rows, 've')}")
    out.append("<!-- AUDIT_TABLE:END -->")
    return "\n".join(out)


def write_doc(path: Path, block: str) -> None:
    guard_path(path)
    raw = path.read_bytes()
    text = raw.decode("utf-8")
    nl = "\r\n" if "\r\n" in text else "\n"
    blk = block.replace("\n", nl)
    b, e = "<!-- AUDIT_TABLE:BEGIN -->", "<!-- AUDIT_TABLE:END -->"
    i, j = text.find(b), text.find(e)
    if i >= 0 and j > i:
        new = text[:i] + blk + text[j + len(e):]
    else:
        m = re.search(r"^<!-- AUDIT_TABLE -->[ \t]*$", text, re.M)
        if not m:
            raise ParseError(f"{path}에 AUDIT_TABLE 표지가 없다")
        new = text[:m.start()] + blk + text[m.end():]
    path.write_bytes(new.encode("utf-8"))


def metrics_dict(M: Model) -> dict:
    run = M.run()
    out = {
        "t_r": {k: M.t_r_scn(k) for k in SCENARIOS},
        "T_fill": {k: {fn(u): M.T_fill(k, u) for u in M.u_list} for k in SCENARIOS},
        "T_dig": {k: {fn(u): M.T_dig(k, u) for u in M.u_list} for k in SCENARIOS},
        "T_E_est": {k: {fn(u): list(M.T_E_basis(k, u)) for u in M.u_list} for k in MAIN_SCENARIOS},
        "avg_overfill_mult": M.avg_overfill_mult(),
        "d_E": {fn(u): M.d_E(u) for u in M.u_list},
        "t_close": {c: M.t_close(c) for c in CONTEXTS},
        "rho": {p: {fn(u): M.rho(c, s, u) for u in M.u_list} for p, c, s in RHO_PAIRS},
        "run": run,
        "trips": {fn(u): M.trips(run["E_run"], u) for u in M.u_list},
        "T_run_h_assumed": {fn(u): M.trips(run["E_run"], u) * M.T_E / 3600 for u in M.u_list},
        "transit_u": list(M.transit()),
        "max_gap_m": M.max_gap(),
        "barrier_life": [M.barrier_life(k) for k in range(3)],
        "core_no_break_deficit": M.core_no_break_deficit(),
        "nerve_survival": M.nerve_survival(),
        "crush": M.crush(),
        "death_E": M.death(),
        "idle": [M.idle(k) for k in range(3)],
        "draws": M.draws(run["E_run"]),
        "door_shortcut": M.door_shortcut(),
        "payback_E": M.payback(),
        "cud": M.cud(),
    }

    def clean(x):
        if isinstance(x, float):
            return None if math.isinf(x) else x
        if isinstance(x, dict):
            return {str(k): clean(v) for k, v in x.items()}
        if isinstance(x, (list, tuple)):
            return [clean(v) for v in x]
        return x
    return clean(out)


# ---------------------------------------------------------------------------
# 자체 검사 (고정 입력)
# ---------------------------------------------------------------------------

FIXED_PARAMS = {
    "progression.SHELL_MULTIPLIER": {"core": 1, "mantle": 2, "surface": 3},
    "progression.TEETH_PER_FLESH": 0.08, "progression.EXPEDITION_TEETH": 8,
    "progression.FLESH_PER_BIOME_HAIR": 50.0, "progression.FLESH_PER_COMMON_HAIR": 150.0,
    "progression.PRICE_UNITS": {"barrier": 0.5, "spray_cheap": 1.0, "knife": 2.0, "spray_deep": 3.0, "blender": 5.0,
                                "big_saw": 10.0, "canary_feed": 0.5, "tumor_bag": 2.0},
    "progression.UNLOCK_SHELL": {"barrier": 0, "spray_cheap": 0, "knife": 0, "canary_feed": 0, "spray_deep": 1,
                                 "blender": 1, "tumor_bag": 1, "big_saw": 2},
    "progression.VENT_MAX_OFFER": 3, "progression.MAX_BARRIERS": 3, "progression.MAX_CANARY_FEED": 3,
    "progression.TUMOR_KINDS": ["core_knot", "core_bulb", "mantle_coil", "mantle_sac", "surface_star", "surface_ear"],
    "progression.TUMOR_TOOTH_PAYOUT": 24, "progression.TUMOR_MUTATIONS": ["T1", "T2", "T3", "T4", "T5", "T6", "T7"],
    "progression.BRANCH_POOL": {"common": "common", "compressive": "core", "contractile": "mantle", "nerve": "surface"},
    "progression.POOL_COST": {"common": 12, "core": 5, "mantle": 10, "surface": 15},
    "progression.COMBO_FACTOR": 1.5, "progression.BASE_REACH": 2.5, "progression.BASE_CHEW_TIME": 0.6,
    "progression.BASE_CAPACITY": 100.0, "progression.BASE_OVERFILL": 60.0, "progression.BASE_OVERFILL_CHEW": 3.0,
    "progression.BASE_CRUSH_TIME": 6.0, "progression.M06_CRUSH_BONUS": 3.0, "progression.M17_DAMAGE_FACTOR": 0.5,
    "progression.TISSUE_HARDNESS": {"0": 1.0, "1": 1.2, "2": 1.0, "3": 2.0, "4": 1.4},
    "progression.CUD_SHRINK": 0.1, "progression.ALIEN_HAND_PERIOD": 2.0,
    "progression.MUTATIONS": (
        [{"id": f"M0{i}", "branch": "common"} for i in range(1, 7)]
        + [{"id": i, "branch": "compressive"} for i in ("M07", "M08", "M09", "M10", "M12", "M13")]
        + [{"id": f"M{i}", "branch": "contractile"} for i in range(14, 21)]
        + [{"id": f"M{i}", "branch": "nerve"} for i in range(21, 28)]
        + [{"id": "M28", "branch": "combination", "pools": ["core", "mantle"]},
           {"id": "M29", "branch": "combination", "pools": ["mantle", "surface"]},
           {"id": "M30", "branch": "combination", "pools": ["surface", "core"]}]),
    "tissue_rules.REGEN": {"0": 1.5, "1": 0.8, "2": 1.0, "3": 0.0, "4": 1.0, "5": 0.0},
    "tissue_rules.KNIFE_SPEED": 1.6, "tissue_rules.SAW_TIME_FACTOR": 1.5, "tissue_rules.SAW_TEAR_CELLS": 6,
    "terrain_config.cell_size": 0.5, "terrain_config.iso_level": 0.5, "terrain_config.regen_rate": 0.003,
    "depth_danger.DANGER_STEP": 0.35, "chunk.CROWD_GAIN": 1.5, "stomach_config.flesh_per_cell": 4.0,
    "spray_can.BOOST_MULT": 2.0, "spray_can.MAX_CARRIED": 3,
    "spray_can.SPRAYS_PER_CAN": 6, "spray_can.CHEAP_DEPTH": 0.5, "spray_can.DEEP_DEPTH": 1.5,
    "world_features.REST_PER_SHELL": [2, 4, 6],
    "barrier.break_threshold": 12.0, "barrier.stress_decay": 0.15, "player_config.crouch_speed": 1.5,
    "hazard_check.hazard_dps": 40.0, "hazard_check.hazard_radius": 1.1, "hazard_check.health": 100.0,
    "main.BODY_PROTECT_RADIUS": 0.9, "main.HAZARD_TIME": 1.2, "main.HEALTH_REGEN": 12.0,
    "main.BARRIER_PRESSURE": 0.28 / 0.003, "main.nerve_cooldown": 2.0,
    "world_features.SHELL_THICKNESS": 9.0, "world_features.SHELL_COUNT": 3, "world_features.OUTER_RADIUS": 27.0,
    "world_features.REST_DEPTH": [4.5, 13.5, 22.5], "world_features.BOUNDARY_BAND": 0.9,
    "world_features.TUMORS_PER_SHELL": 4, "restroom.HALF": [2.25, 1.3, 1.5],
}
FIXED_ASSUMPTIONS = {
    "T_E": 240.0, "aim": 0.3, "ritual": [11.0, 40.0], "escape_cells": [2, 3], "door_depth": None,
    "u": [100.0, 160.0], "tunnel_cells_per_m": [2, 6], "expected_tool": ["bare", "knife", "knife"],
    "tumor_point_value_E": 2.5, "new_tissue_sightings": 3, "death_typical_fill": 100.0,
    "death_typical_barriers": 1, "idle_window": 300.0,
    "oneoff_tools": ["knife", "tumor_bag", "blender", "big_saw"], "tumors_by_shell": None,
    "consumable_teeth_demand": None, "spray_rest_share": 1.0,
}


def selftest() -> int:
    M = Model(FIXED_PARAMS, FIXED_ASSUMPTIONS)
    run = M.run()
    fails, total = [], 0

    def chk(name, got, exp):
        nonlocal total
        got_l = list(got) if isinstance(got, (list, tuple)) else [got]
        exp_l = list(exp) if isinstance(exp, (list, tuple)) else [exp]
        for g_, e_ in zip(got_l, exp_l):
            total += 1
            ok = abs(g_ - e_) <= 0.01 or (e_ != 0 and abs(g_ - e_) / abs(e_) <= 0.005)
            if not ok:
                fails.append(f"{name}: 기대 {e_}, 계산 {g_}")
        if len(got_l) != len(exp_l):
            fails.append(f"{name}: 개수가 다르다")
        print(("ok   " if not any(f.startswith(name + ":") for f in fails) else "FAIL ") + name + ": "
              + " / ".join(f"{x:.4g}" for x in got_l))

    chk("t_r 핵맨손/핵칼/맨틀칼/지표면맨손/지표면칼", [M.t_r_scn(s) for s in MAIN_SCENARIOS], [0.6, 0.375, 0.525, 0.72, 0.45])
    chk("큰 톱 스트로크", [M.t_r(0, "saw"), M.t_r(4, "saw"), M.t_r(1, "saw")], [0.9, 1.26, 1.08])
    chk("T_fill core_bare", [M.T_fill("core_bare", u) for u in (100, 160)], [15.0, 32.4])
    chk("T_fill core_knife", [M.T_fill("core_knife", u) for u in (100, 160)], [9.375, 20.25])
    chk("T_fill mantle_knife", [M.T_fill("mantle_knife", u) for u in (100, 160)], [13.125, 28.35])
    chk("T_fill surf_bare", [M.T_fill("surf_bare", u) for u in (100, 160)], [18.0, 38.88])
    chk("T_fill surf_knife", [M.T_fill("surf_knife", u) for u in (100, 160)], [11.25, 24.3])
    chk("과식 15셀 평균 배수", M.avg_overfill_mult(), 1.933)
    chk("d_E 웅크림", [M.d_E(100), M.d_E(160)], [12.5, 20.0])
    chk("T_E,est core_bare 100", M.T_E_calc("core_bare", 100), [50.17, 79.17])
    chk("T_E,est core_bare 160", M.T_E_calc("core_bare", 160), [82.07, 111.07])
    chk("t_close", [M.t_close(c) for c in ("core_open", "core_1cell", "core_dead", "core_max", "core_max_spray",
                                           "core_1cell_spray", "core_nerve", "mantle_contr", "surf_nerve")],
        [111.11, 74.07, 55.56, 44.44, 22.22, 37.04, 208.33, 123.46, 122.55])
    chk("ρ", [M.rho(c, s, u) for _, c, s in RHO_PAIRS for u in (100, 160)],
        [2.40, 1.28, 3.60, 1.92, 1.44, 0.77, 4.26, 2.30, 3.62, 1.91, 4.52, 2.47])
    chk("E_k", run["E_k"], [15.0, 25.0, 21.333])
    chk("E_run", run["E_run"], 61.333)
    chk("common_supply", run["common_supply"], 86.0)
    chk("teeth_supply", run["teeth_supply"], 490.67)
    chk("tools_oneoff", run["tools_oneoff"], 152)
    chk("T_run 240 s (h)", [M.trips(run["E_run"], u) * 240 / 3600 for u in (100, 160)], [4.089, 2.556])
    chk("4시간 필요 T_E", [14400 / M.trips(run["E_run"], u) for u in (100, 160)], [234.8, 375.7])
    chk("용량 원정 수", [M.trips(run["E_run"], c) for c in (120, 160, 200, 240)], [51.11, 38.33, 30.67, 25.56])
    m120 = M.with_capacity(120)
    chk("용량 120 u T_E,est", m120.T_E_calc("core_bare", 120), [58.0, 87.0])
    chk("용량 120 u 회차 추정 (h)", [M.trips(run["E_run"], 120) * x / 3600 for x in m120.T_E_calc("core_bare", 120)],
        [0.823, 1.235])
    chk("이빨 SD (원정 + 종양 ÷ 일회성 도구)", (run["teeth_supply"] + 12 * 24) / run["tools_oneoff"], 5.123)
    spd = M.spray_demand()
    chk("스프레이 통로망 줄기/가지/1 m 이빨", [spd["trunk_m"], spd["branch_m"], spd["per_m"]["spray_cheap"],
                                       spd["per_m"]["spray_deep"]], [23.7, 264.0, 2.6667, 2.6667])
    chk("스프레이 이빨 수요", spd["teeth"], 767.2)
    chk("이빨 SD (원정 + 종양 ÷ 도구 + 스프레이)", (run["teeth_supply"] + 12 * 24) / (run["tools_oneoff"] + spd["teeth"]), 0.8492)
    chk("종양 껍질별", M.tumors_by_shell(), [4, 4, 4])
    chk("새 재고 사건", M.draws(run["E_run"])["new_stock"], 2)
    chk("신호 구독 정규식", [len(signal_connect_re("canary_cry").findall(s)) for s in
                         ('x.canary_cry.connect(f)', 'main.connect("canary_cry", f)', '_hook("canary_cry", f)',
                          'canary_crying.connect(f)')], [1, 1, 1, 0])
    chk("통과", M.transit(), [52.8, 117.6])
    chk("max_gap", M.max_gap(), 4.5)
    chk("방벽 수명", [M.barrier_life(k) for k in range(3)], [92.31, 52.63, 36.81])
    chk("핵 무파손 결손", M.core_no_break_deficit(), 0.536)
    chk("신경 생존", M.nerve_survival(), 4.58)
    cr = M.crush()
    chk("압사 비", [cr["normal"], cr["over"], cr["m06"]], [5.0, 1.11, 1.67])
    dc = M.death()
    chk("죽음 비용", [dc["typical"], dc["stomach"], dc["worst"]], [1.5, 1.6, 20.1])
    chk("무입력 비", [M.idle(k)["ratio"] for k in range(3)], [0.050, 0.033, 0.030])
    chk("폭발 비", M.idle(0)["burst_ratio"], 0.45)
    dr = M.draws(run["E_run"])
    chk("G_tumor", dr["G"], 1.75)
    chk("발견 간격", dr["discovery_interval"], 3.228)
    chk("몸 변화 간격", dr["body_interval"], 1.704)
    chk("톱 털/스트로크", [M.strands_per_resp(k, 6) for k in range(3)], [0.48, 0.96, 1.44])
    ds = M.door_shortcut()
    chk("문 앞 r 가정", ds["r_assumed"], [0.140, 0.260])
    chk("문 앞 r 추정", ds["r_est"], [0.668, 0.789])
    pb = M.payback()
    chk("회수 칼/톱", [pb["knife"], pb["saw"]], [85.3, 213.3])
    chk("M16 이빨", M.cud()["teeth"], [7, 6, 6])

    # 파서 검사
    sample = [
        "const A := 0.28 / 0.003",
        "const B := {",
        '\t"x": 0.5,',
        '\t"y": 2.0, # 주석',
        "}",
        "@export var life_interval: Vector2 = Vector2(5.0, 12.0)",
        "const POOL := {COMMON: 12, BIOME_CORE: 5}",
        'const ARR: Array[String] = ["T1", "T2"] ## doc',
        "const T := 9.0",
        "const R := T * 3",
        "const H := {COMPRESSIVE: 1.0, MEMBRANE: 2.0}",
        "const MAX_CARRIED: int = 3",
    ]
    gd = GDFile(sample, "sample")
    parse_cases = [
        ("식", gd.find("A")[0], 93.333),
        ("여러 줄 사전", [gd.find("B")[0]["x"], gd.find("B")[0]["y"]], [0.5, 2.0]),
        ("Vector2", list(gd.find("life_interval")[0]), [5.0, 12.0]),
        ("이름 식", gd.find("R")[0], 27.0),
        ("기호 키", [gd.find("POOL")[0]["common"], gd.find("H")[0][3]], [12, 2.0]),
        ("형 선언", gd.find("MAX_CARRIED")[0], 3),
        ("줄 번호", gd.find("R")[1], 10),
        ("반올림", [round_half_away(0.5), round_half_away(2.5), round_half_away(7.2), round_half_away(-0.5)], [1, 3, 7, -1]),
    ]
    for name, got, exp in parse_cases:
        chk("파서 " + name, got, exp)
    total += 1
    if gd.find("ARR")[0] != ["T1", "T2"]:
        fails.append("파서 배열: 기대 ['T1', 'T2']")
    try:
        eval_expr("__import__('os')", lambda n: 0)
        fails.append("파서 안전: 함수 호출이 통과했다")
    except ParseError:
        pass
    total += 1
    try:
        validate_mutations(FIXED_PARAMS["progression.MUTATIONS"])
    except ParseError as e:
        fails.append(f"변이 목록: {e}")
    total += 1

    # 기록 분석 검사
    log = "\n".join([
        "t,phase,shell,channel,code,du,dteeth,dhair_biome,dhair_common,dtumor,fill,x,y,z,sound,arm_visible,input_active",
        "0,A,0,R,R-START,0,0,0,0,0,0,0,0,0,0,1,1",
        "5,B,0,S,R-TEAR,4,0,0,0,0,4,2,0,0,1,1,1",
        "5.6,B,0,S,R-TEAR,4,0,0,0,0,8,2,0,0,1,1,1",
        "6.0,B,0,A,R-HAIR-B,0,0,1,0,0,8,2,0,0,0,1,1",
        "6.2,B,0,S,R-TEAR,4,0,0,0,0,12,2,0,0,1,0,1",
        "7.0,B,0,A,R-HAIR-B,0,0,1,0,0,12,2,0,0,0,0,1",
        "20,C,0,R,R-SETL,0,1,0,0,0,0,0,0,0,1,1,1",
        "40,A,0,R,R-VENT,0,0,0,0,0,0,0,0,0,1,1,1",
        "60,B,0,S,R-TEAR,4,0,0,0,0,4,2,0,0,1,1,1",
    ])
    res = analyse_log(read_log_text(log), M)
    chk("기록 M01", res["M01"], 5.0)
    chk("기록 M10", res["M10"], 0.5)
    chk("기록 T_E", res["exps"][0]["T_E"], 55.0)
    chk("기록 T_fill", res["exps"][0]["T_fill"], 1.2)
    chk("기록 M06", res["M06"], 0)

    print(f"\n검사 {total}개 중 실패 {len(fails)}개")
    for f in fails:
        print("  " + f)
    return EXIT_OK if not fails else EXIT_FAIL


# ---------------------------------------------------------------------------
# 진입점
# ---------------------------------------------------------------------------

def parse_pair(s: str, cast=float) -> list:
    parts = [p.strip() for p in s.split(",") if p.strip()]
    return [cast(p) for p in parts]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="보상 척도 계산기 (docs/spec/09-reward-scale.md 11장)")
    ap.add_argument("--repo", type=Path, default=DEFAULT_REPO, help="저장소 루트 (기본: tools/의 부모)")
    ap.add_argument("--params", type=Path, default=DEFAULT_PARAMS, help="입력 params.json")
    ap.add_argument("--te", type=float, help="가정 T_E (s)")
    ap.add_argument("--aim", type=float, help="겨눔 시간 a (s)")
    ap.add_argument("--ritual", help="의식 시간 하한,상한 (s)")
    ap.add_argument("--escape", help="탈출 셀 수 보통,과식")
    ap.add_argument("--door-depth", type=float, help="문 깊이 (m)")
    ap.add_argument("--u", help="원정당 정산 위장 양 목록 (u)")
    ap.add_argument("--json", nargs="?", const="-", metavar="PATH",
                    help="경로 없이 쓰면 지표와 행을 JSON으로 표준 출력, 경로를 주면 행 목록을 그 파일에 쓴다")
    ap.add_argument("--write", type=Path, metavar="PATH", help="문서의 AUDIT_TABLE 표지 사이를 표로 바꾼다")
    ap.add_argument("--log", action="append", type=Path, default=[], metavar="PATH", help="실측 기록 CSV (여러 번)")
    ap.add_argument("--check", action="store_true", help="대역 밖 항목이 있으면 그 목록을 내고 1로 끝난다")
    ap.add_argument("--selftest", action="store_true", help="고정 입력으로 공식을 검사한다")
    ap.add_argument("--no-verify", action="store_true", help="params.json을 코드와 대조하지 않는다")
    ap.add_argument("--layout", choices=["audit", "spec"], default="audit",
                    help="audit: 항목·현재값·척도 위의 값·목표 범위·판정·근거 6열, spec: ID·수치·현재·척도 값·대역·판정·메모 7열")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest()

    try:
        data = json.loads(guard_path(args.params).read_text(encoding="utf-8"))
        params = data["params"]
        assumptions = {k: v["value"] for k, v in data["assumptions"].items()}
        as_of = str(data.get("as_of", ""))
    except (OSError, KeyError, json.JSONDecodeError, ParseError) as e:
        print(f"오류: params.json을 읽지 못했다: {e}", file=sys.stderr)
        return EXIT_PARSE

    try:
        if args.te is not None:
            assumptions["T_E"] = args.te
        if args.aim is not None:
            assumptions["aim"] = args.aim
        if args.ritual:
            assumptions["ritual"] = parse_pair(args.ritual)[:2]
        if args.escape:
            assumptions["escape_cells"] = parse_pair(args.escape, int)[:2]
        if args.door_depth is not None:
            assumptions["door_depth"] = args.door_depth
        if args.u:
            assumptions["u"] = parse_pair(args.u)
        if len(assumptions["ritual"]) != 2 or len(assumptions["escape_cells"]) != 2 or not assumptions["u"]:
            raise ValueError("--ritual과 --escape는 값 두 개, --u는 하나 이상이다")
    except ValueError as e:
        print(f"오류: 옵션을 읽지 못했다: {e}", file=sys.stderr)
        return EXIT_PARSE

    repo = Repo(args.repo.resolve())
    virtual = None
    try:
        if args.no_verify:
            vr = VerifyResult()
            # 대조하지 않는 실행: 다른 값을 조용히 찾아 표 머리에만 적는다. 찾지 못해도 계속한다.
            try:
                quiet = verify_params(repo, params, quiet=True)
                virtual = "--no-verify 실행, 코드와 다른 params: " + (", ".join(quiet.mismatch_keys) or "없음")
            except ParseError:
                virtual = "--no-verify 실행, 코드와 대조하지 못함"
        else:
            vr = verify_params(repo, params)
            if vr.mismatch_keys:
                virtual = ", ".join(vr.mismatch_keys)
        validate_mutations(params["progression.MUTATIONS"]["value"], strict_counts=False)
    except ParseError as e:
        print(f"오류: {e}", file=sys.stderr)
        return EXIT_PARSE

    V = {k: v["value"] for k, v in params.items()}
    model = Model(V, assumptions)

    measured = None
    if args.log:
        ev = []
        try:
            for p in args.log:
                ev += read_log_text(guard_path(p).read_text(encoding="utf-8"))
        except (OSError, ParseError) as e:
            print(f"오류: 기록을 읽지 못했다: {e}", file=sys.stderr)
            return EXIT_PARSE
        ev.sort(key=lambda e: e["t"])
        measured = analyse_log(ev, model)
        if measured.get("TE_q"):
            model.measured_TE = {k: (q[0], q[2]) for k, q in measured["TE_q"].items()}
            q = measured["TE_all"]
            model.measured_overall = (q[0], q[2])
        measured["rows"] = measured_rows(measured, model)

    flags = evidence_flags(repo)
    cons = consumer_counts(repo)
    unw = unwired_counts(repo)
    flags["F_UNWIRED"] = Flag("F_UNWIRED", True, ["game/main/scripts", "game/audio"],
                              ", ".join(f"{k}={v}" for k, v in unw.items()))
    cx = Context(model, params, repo, flags, cons, unw, vr.recheck, measured)
    rows = build_rows(cx)
    est_label = "실측" if (model.measured_TE or model.measured_overall) else "추정"
    header = header_line(model, git_label(repo.root), as_of, virtual)
    table = render(rows, header, args.layout, est_label, bool(args.log))

    if args.json:
        payload = [{"id": r.id, "group": r.group, "label": r.label, "current": r.current, "scale_value": r.scale,
                    "band": r.band, "verdict_assumed": r.va, "verdict_est": r.ve, "verdict_cell": r.cell,
                    "memo": r.memo, "inputs": r.inputs, "flags": r.flags} for r in rows]
        if args.json == "-":
            obj = {"header": header, "assumptions": assumptions, "metrics": metrics_dict(model),
                   "flags": {k: f.status for k, f in flags.items()}, "consumers": cons, "unwired": unw,
                   "params_mismatch": vr.mismatches, "rows": payload}
            print(json.dumps(obj, ensure_ascii=False, indent=2))
            return EXIT_OK
        Path(args.json).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if args.write:
        if args.no_verify or virtual:
            print("오류: 가상 값(--no-verify 또는 코드와 다른 params)으로 만든 표는 --write에 쓰지 않는다. "
                  "코드에 반영한 뒤 기본 실행으로 다시 만든다.", file=sys.stderr)
            return EXIT_FAIL
        try:
            write_doc(args.write, table)
        except (OSError, ParseError) as e:
            print(f"오류: {e}", file=sys.stderr)
            return EXIT_PARSE

    if args.check:
        bad = [r for r in rows if r.va in OUT_OF_BAND or r.ve in OUT_OF_BAND]
        if vr.mismatches:
            print(f"params.json이 코드와 다르다 {len(vr.mismatches)}건:")
            for m in vr.mismatches:
                print(f"- {m}")
        if bad:
            print(f"대역 밖 {len(bad)}건:")
            for r in bad:
                print(f"- {r.id} {r.label}: {r.cell}")
        if bad or vr.mismatches:
            return EXIT_FAIL
        print("대역 밖 항목이 없다.")
        return EXIT_OK

    print(table)
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
