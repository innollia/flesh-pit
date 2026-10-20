"""Run one clean-room playtest session (docs/operations.md "클린룸 플레이테스트").

  python -X utf8 tools/playtest/run_session.py --session s1 [--steps 150] [--model sonnet]
      [--minutes 75] [--base DIR] [--no-agent] [--fresh]

1. Copies game/ into <base>/<session>/iso with its own project name (its own
   user:// folder, so the player's real save is never read or written) and
   the bridge autoload (game/tests/playtest_bridge.gd).
2. Makes the player's room <base>/<session>/room: play.py, manual.md and the
   session/ folder the game writes screenshots into. Nothing else.
3. Starts the game windowed at 960x540 with --fixed-fps 30.
4. Starts the player agent with `claude -p` in the room: it may only run
   `python play.py ...` and read files under the room. It never sees the code,
   the docs or the telemetry (<base>/<session>/evidence).
5. When it is done, stops the game and writes evidence/trajectory.md (each
   step: command, player notes, on-screen text, sounds, telemetry) and
   evidence/player_report.md (the player's final feedback) for the evaluator.
--no-agent stops after step 3 so a person or another tool can drive play.py;
--stop then ends that game and writes the evidence files.
"""
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = shutil.which("godot_console") or "godot_console"

PLAYER_PROMPT = """너는 이 게임을 처음 하는 플레이어다. 게임에 대해 아는 것은 이 폴더의 manual.md뿐이다. 먼저 manual.md를 읽어라.

- 게임은 `python play.py ...`로만 조작한다. 행동마다 나오는 화면 이미지(session/obs_NNNN.png)를 Read로 열어 보고 다음 행동을 정한다.
- 보통 플레이어처럼 해라. 화면에 보이는 것, 들린 소리 이름, 화면의 글자만으로 판단한다. 이 폴더 밖의 파일은 볼 수 없다.
- 생각을 자주 짧게 남겨라: `python play.py note "..."`. 특히 무엇을 해야 할지 모를 때, 헷갈릴 때, 막혔을 때, 재미있을 때, 이상하거나 고장 난 것 같을 때. 본 것과 짐작을 구분해서 적어라.
- 약 {steps}번 행동하거나, 바깥으로 나가거나, 더 진행할 수 없으면 멈춘다. 같은 실패를 10번 넘게 되풀이하면 다른 방법을 찾거나 멈춘다.
- 끝나면 마지막 답으로 한국어 피드백 보고서를 쓴다. 각 항목에 해당 step 번호와 화면 파일을 붙인다:
  1. 첫인상
  2. 무엇을 해야 하는지 언제, 어떻게 알게 됐나 (또는 끝까지 몰랐나)
  3. 헷갈리거나 막힌 곳
  4. 재미있던 것
  5. 답답하거나 지루했던 것
  6. 버그로 보이는 것 (본 것만. 짐작이면 짐작이라고 쓴다)
  7. 바꾸면 좋겠다고 느낀 것
"""


def log(msg):
    print("[playtest] " + msg, flush=True)


def user_dir(project_name):
    return os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", project_name)


def prepare(sess, name):
    iso = os.path.join(sess, "iso")
    room = os.path.join(sess, "room")
    ev = os.path.join(sess, "evidence")
    log("copying game/ -> " + iso)
    shutil.copytree(os.path.join(REPO, "game"), os.path.join(iso, "game"),
                    ignore=shutil.ignore_patterns(".godot", ".dryforge"))
    proj = os.path.join(iso, "game", "project.godot")
    text = open(proj, encoding="utf-8").read()
    text = re.sub(r'^config/name=.*$', 'config/name="%s"' % name, text, count=1, flags=re.M)
    text += '\n[autoload]\n\nPlaytestBridge="*res://tests/playtest_bridge.gd"\n'
    open(proj, "w", encoding="utf-8", newline="\n").write(text)
    ud = user_dir(name)
    if os.path.basename(ud).startswith("flesh-pit-playtest-") and os.path.isdir(ud):
        log("clearing the copy's own user folder " + ud)
        shutil.rmtree(ud)
    log("importing resources (first run of the copy)")
    subprocess.run([GODOT, "--headless", "--editor", "--path", os.path.join(iso, "game"), "--import"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=900)
    os.makedirs(os.path.join(room, "session"))
    os.makedirs(ev)
    shutil.copy(os.path.join(HERE, "play.py"), room)
    shutil.copy(os.path.join(HERE, "manual.md"), room)
    git = subprocess.run(["git", "-C", REPO, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
    dirty = subprocess.run(["git", "-C", REPO, "status", "--porcelain", "--", "game"], capture_output=True, text=True).stdout.strip()
    json.dump({"session": os.path.basename(sess), "project_name": name, "git": git, "game_dirty": bool(dirty),
               "started": time.strftime("%Y-%m-%d %H:%M:%S")}, open(os.path.join(ev, "manifest.json"), "w"), indent=1)
    return iso, room, ev


def start_game(iso, room, ev):
    env = dict(os.environ)
    env["PLAYTEST_DIR"] = os.path.join(room, "session").replace("\\", "/")
    env["PLAYTEST_EVIDENCE"] = ev.replace("\\", "/")
    out = open(os.path.join(ev, "godot.log"), "w", encoding="utf-8", errors="replace")
    proc = subprocess.Popen([GODOT, "--path", os.path.join(iso, "game"), "--resolution", "960x540",
                             "--fixed-fps", "30", "--position", "40,40"], env=env, stdout=out, stderr=subprocess.STDOUT)
    open(os.path.join(ev, "godot.pid"), "w").write(str(proc.pid))
    first = os.path.join(room, "session", "obs_0000.json")
    t0 = time.time()
    while not os.path.exists(first):
        if proc.poll() is not None or time.time() - t0 > 300:
            sys.exit("the game did not start; see " + os.path.join(ev, "godot.log"))
        time.sleep(0.5)
    log("game is up (step 0 written)")
    return proc


def run_player(room, ev, steps, model, minutes):
    cmd = ["claude", "-p", PLAYER_PROMPT.format(steps=steps), "--model", model,
           "--output-format", "stream-json", "--verbose", "--max-turns", str(steps * 3 + 40),
           "--setting-sources", "project", "--strict-mcp-config", "--disable-slash-commands",
           "--no-session-persistence", "--permission-mode", "dontAsk",
           "--allowedTools", "Bash(python play.py:*)", "Read(./**)",
           "--disallowedTools", "Edit", "Write", "NotebookEdit", "WebFetch", "WebSearch", "Task", "Agent", "Glob", "Grep"]
    log("player agent started (%s, about %d steps)" % (model, steps))
    with open(os.path.join(ev, "transcript.jsonl"), "w", encoding="utf-8") as out, \
            open(os.path.join(ev, "claude.err"), "w", encoding="utf-8") as err:
        try:
            subprocess.run(cmd, cwd=room, stdout=out, stderr=err, timeout=minutes * 60, encoding="utf-8")
        except subprocess.TimeoutExpired:
            log("player agent stopped at the time limit")


def quit_game(room):
    n = max([int(os.path.basename(p)[4:8]) for p in glob.glob(os.path.join(room, "session", "obs_[0-9]*.json"))] or [0])
    path = os.path.join(room, "session", "cmd_%04d.json" % (n + 1))
    with open(path + ".tmp", "w") as f:
        json.dump({"quit": True}, f)
    os.replace(path + ".tmp", path)


def stop_game(proc, room):
    quit_game(room)
    try:
        proc.wait(timeout=20)
    except subprocess.TimeoutExpired:
        proc.kill()


def collect(room, ev, transcript=None):
    notes = {}
    npath = os.path.join(room, "session", "notes.jsonl")
    if os.path.exists(npath):
        shutil.copy(npath, ev)
        for line in open(npath, encoding="utf-8"):
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            notes.setdefault(int(d.get("step", 0)), []).append(d.get("note", ""))
    report = ""
    tpath = transcript or os.path.join(ev, "transcript.jsonl")
    if os.path.exists(tpath):
        for line in open(tpath, encoding="utf-8", errors="replace"):
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            if d.get("type") == "result":
                report = d.get("result") or report
            # a subagent player hands its report back through a tool call
            for c in (d.get("message") or {}).get("content") or []:
                if isinstance(c, dict) and c.get("type") == "tool_use" and c.get("name") == "SubagentHandback":
                    report = (c.get("input") or {}).get("message") or report
    open(os.path.join(ev, "player_report.md"), "w", encoding="utf-8").write(report or "(no final report)\n")
    out = ["# 플레이 기록", "", "step마다: 명령 · 플레이어 메모 · 화면 글자 · 소리 · 텔레메트리(플레이어는 못 본 것)", ""]
    steps = sorted(int(os.path.basename(p)[4:8]) for p in glob.glob(os.path.join(room, "session", "obs_[0-9]*.json")))
    for n in steps:
        try:
            obs = json.load(open(os.path.join(room, "session", "obs_%04d.json" % n), encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        cmd = {}
        cpath = os.path.join(ev, "cmd_%04d.json" % n)
        if os.path.exists(cpath):
            cmd = json.load(open(cpath, encoding="utf-8"))
        tel = {}
        tp = os.path.join(ev, "tel_%04d.json" % n)
        if os.path.exists(tp):
            tel = json.load(open(tp, encoding="utf-8"))
        out.append("## step %d (t %.1f s)" % (n, obs.get("time", 0.0)))
        if cmd:
            out.append("- 명령: `%s`" % json.dumps(cmd, ensure_ascii=False))
        out.append("- 화면: room/session/%s" % obs.get("screenshot"))
        for t in notes.get(n, []):
            out.append("- 메모(이 화면을 본 뒤): %s" % t)
        texts = obs.get("text") or []
        if texts:
            out.append("- 화면 글자: " + "; ".join(t["text"].replace("\n", " ") for t in texts))
        if obs.get("sounds"):
            out.append("- 소리: " + ", ".join(obs["sounds"]))
        keep = {k: tel[k] for k in ("pos", "depth", "shell", "in_restroom", "stomach_fill", "teeth", "teeth_in_hand",
                                    "spray_cans", "barriers", "deaths", "opening", "title_open", "pause_open",
                                    "interact_target", "vent_open", "vent_offers", "crush_t", "wall_ms_per_frame") if k in tel}
        out.append("- 텔레메트리: `%s`" % json.dumps(keep, ensure_ascii=False))
        if tel.get("events"):
            out.append("- 사건: `%s`" % json.dumps(tel["events"], ensure_ascii=False))
        out.append("")
    open(os.path.join(ev, "trajectory.md"), "w", encoding="utf-8").write("\n".join(out))
    log("evidence: " + ev)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--session", required=True)
    ap.add_argument("--steps", type=int, default=150)
    ap.add_argument("--model", default="sonnet")
    ap.add_argument("--minutes", type=int, default=75)
    ap.add_argument("--base", default=os.path.join(os.environ.get("TEMP", "/tmp"), "flesh-pit-playtest"))
    ap.add_argument("--no-agent", action="store_true")
    ap.add_argument("--fresh", action="store_true")
    ap.add_argument("--stop", action="store_true")
    ap.add_argument("--transcript", help="with --stop: the player's transcript when it ran as a subagent")
    a = ap.parse_args()
    if not re.fullmatch(r"[a-z0-9-]+", a.session):
        sys.exit("session: lowercase letters, digits and - only")
    sess = os.path.join(a.base, a.session)
    if a.stop:
        room, ev = os.path.join(sess, "room"), os.path.join(sess, "evidence")
        if not os.path.exists(os.path.join(ev, "trajectory.md")):
            quit_game(room)
            time.sleep(3)
        collect(room, ev, a.transcript)
        return
    if os.path.exists(sess):
        if not a.fresh:
            sys.exit(sess + " exists (use --fresh to replace it)")
        shutil.rmtree(sess)
    name = "flesh-pit-playtest-" + a.session
    iso, room, ev = prepare(sess, name)
    proc = start_game(iso, room, ev)
    if a.no_agent:
        log("game left running for manual driving: cd %s && python play.py look" % room)
        return
    try:
        run_player(room, ev, a.steps, a.model, a.minutes)
    finally:
        stop_game(proc, room)
        collect(room, ev)


if __name__ == "__main__":
    main()
