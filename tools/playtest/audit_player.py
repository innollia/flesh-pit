"""Check that a playtest player agent stayed in its room (clean room).

  python -X utf8 tools/playtest/audit_player.py <transcript.jsonl> <room> [--out audit.md]

Reads a Claude Code transcript (a subagent's agent-*.jsonl or the stream-json
of `claude -p`), lists every tool call and flags anything that is not
`cd <room>` / `python play.py ...` in Bash or a Read under <room>. Exit code 1
when something left the room.
"""
import argparse
import json
import os
import re
import sys


def norm(p):
    return os.path.normcase(os.path.abspath(p.replace("/c/", "C:/", 1) if p.startswith("/c/") else p))


def injected_files(path):
    """Instruction files the harness put into the agent's context (CLAUDE.md, memory)."""
    out = []
    for line in open(path, encoding="utf-8", errors="replace"):
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        a = d.get("attachment")
        if isinstance(a, dict) and a.get("type") in ("instructions", "nested_memory", "memory"):
            for f in a.get("files") or []:
                out.append("%s (%d자)" % (f.get("path", "?"), len(f.get("content") or "")))
    return out


def tool_calls(path):
    for line in open(path, encoding="utf-8", errors="replace"):
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        msg = d.get("message") or {}
        content = msg.get("content")
        if not isinstance(content, list):
            continue
        for c in content:
            if isinstance(c, dict) and c.get("type") == "tool_use":
                yield c.get("name", ""), c.get("input") or {}


def bash_ok(cmd, room):
    parts = [p.strip() for p in re.split(r"&&|;|\n", cmd) if p.strip()]
    for p in parts:
        m = re.fullmatch(r'cd\s+"?([^"]+)"?', p)
        if m:
            d = norm(m.group(1))
            if d != norm(room) and not d.startswith(norm(room) + os.sep):
                return False
            continue
        if re.fullmatch(r'python(3)?\s+("?[^"\s]*[\\/])?play\.py"?(\s.*)?', p, flags=re.S):
            continue
        return False
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("transcript")
    ap.add_argument("room")
    ap.add_argument("--out")
    a = ap.parse_args()
    room = norm(a.room)
    counts = {}
    bad = []
    for name, inp in tool_calls(a.transcript):
        counts[name] = counts.get(name, 0) + 1
        if name == "Bash":
            if not bash_ok(str(inp.get("command", "")), a.room):
                bad.append("Bash: " + str(inp.get("command", ""))[:200])
        elif name == "Read":
            p = norm(str(inp.get("file_path", "")))
            if not (p == room or p.startswith(room + os.sep)):
                bad.append("Read: " + str(inp.get("file_path", "")))
        elif name not in ("SubagentHandback", "StructuredOutput"):
            # the harness's own final-report tools read nothing
            bad.append("%s: %s" % (name, json.dumps(inp, ensure_ascii=False)[:200]))
    lines = ["# 클린룸 검사", "", "도구 호출: " + ", ".join("%s %d" % kv for kv in sorted(counts.items())), ""]
    if bad:
        lines += ["방 밖을 본 호출 %d개:" % len(bad), ""] + ["- " + b for b in bad]
    else:
        lines.append("방 밖을 본 호출 없음. Bash는 방으로 cd와 play.py뿐, Read는 방 안 파일뿐이다.")
    inj = injected_files(a.transcript)
    lines += ["", "하네스가 넣은 문맥 파일: " + (", ".join(inj) if inj else "없음")]
    if inj:
        lines.append("도구로 방 밖을 보지는 않았지만 이 파일들의 내용은 플레이어가 알고 시작했다. "
                     "완전한 클린룸은 `claude -p` 방식(run_session.py)으로 돌린다.")
    text = "\n".join(lines) + "\n"
    if a.out:
        open(a.out, "w", encoding="utf-8").write(text)
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    print(text)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
