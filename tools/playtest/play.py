"""Player-side client for a clean-room playtest (docs/operations.md).

Copied next to manual.md into the player's room; it only talks to the game
through files in ./session (the game writes what is on screen, this writes
commands). Game time is frozen while no command is running.

  python play.py look                show the current screen again
  python play.py act "W 1.5"         hold W for 1.5 s
  python play.py act "W+Shift 2"     hold several keys
  python play.py act "LMB 2"         hold the left mouse button 2 s (RMB, MMB)
  python play.py act "W+LMB 3"       keys and mouse buttons together
  python play.py act "turn 30 -10"   turn the view 30 deg right, 10 deg down
  python play.py act "W 2 turn 20 0" walk and turn at the same time
  python play.py act "tap F"         press keys once (tap Esc, tap V ...)
  python play.py act "click 480 300" left-click at x,y of the screenshot
  python play.py act "click 480 300 RMB"
  python play.py act "wait 3"        do nothing for 3 s
  python play.py note "..."          write down what you think right now
"""
import glob
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
# a player session opened on a copy of the room (its own project) finds the
# game's session folder through session_dir.txt
_POINTER = os.path.join(HERE, "session_dir.txt")
SESSION = open(_POINTER, encoding="utf-8").read().strip() if os.path.exists(_POINTER) else os.path.join(HERE, "session")
BUTTONS = {"LMB", "RMB", "MMB", "WHEELUP", "WHEELDOWN"}


def last_step():
    steps = [int(os.path.basename(p)[4:8]) for p in glob.glob(os.path.join(SESSION, "obs_[0-9][0-9][0-9][0-9].json"))]
    return max(steps) if steps else -1


def wait_obs(n, timeout=240.0):
    path = os.path.join(SESSION, "obs_%04d.json" % n)
    t0 = time.time()
    while not os.path.exists(path):
        if time.time() - t0 > timeout:
            sys.exit("the game did not answer (step %d). Try `python play.py look` again in a moment." % n)
        time.sleep(0.1)
    for _ in range(20):
        try:
            with open(path, encoding="utf-8") as f:
                return json.load(f)
        except (json.JSONDecodeError, PermissionError):
            time.sleep(0.05)
    sys.exit("could not read %s" % path)


def show(obs):
    print("step %d  (game time %.1f s)" % (obs["step"], obs.get("time", 0.0)))
    print("screen: %s" % os.path.join(SESSION, obs["screenshot"]))
    if obs.get("mid_screenshot"):
        print("halfway through the action: %s" % os.path.join(SESSION, obs["mid_screenshot"]))
    texts = obs.get("text") or []
    if texts:
        print("text on screen: " + "; ".join(
            '"%s" %s' % (t["text"].replace("\n", " "), "@(%d,%d)" % tuple(t["at"]) if t.get("at") else "(on a surface; see the screenshot)")
            for t in texts))
    else:
        print("text on screen: (none readable as text; look at the screenshot)")
    sounds = obs.get("sounds") or []
    print("heard: " + (", ".join(sounds) if sounds else "(nothing new)"))


def parse(text):
    text = text.strip()
    if text.startswith("{"):
        return json.loads(text)
    toks = text.split()
    if not toks:
        raise ValueError("empty command")
    head = toks[0].lower()
    if head == "tap":
        return {"tap": toks[1:], "secs": 0.2}
    if head == "wait":
        return {"wait": float(toks[1]) if len(toks) > 1 else 1.0}
    if head == "click":
        cmd = {"at": [int(float(toks[1])), int(float(toks[2]))], "click": toks[3].upper() if len(toks) > 3 else "LMB", "secs": 0.2}
        return cmd
    cmd = {}
    rest = toks
    if head in ("turn", "look"):
        cmd["look"] = [float(toks[1]), float(toks[2])]
        cmd["secs"] = float(toks[3]) if len(toks) > 3 else 0.3
        return cmd
    keys = [k for k in rest[0].split("+") if k]
    cmd["keys"] = [k for k in keys if k.upper() not in BUTTONS]
    cmd["mouse"] = [k.upper() for k in keys if k.upper() in BUTTONS]
    i = 1
    cmd["secs"] = 0.5
    if len(rest) > 1 and rest[1].lower() not in ("turn", "look"):
        cmd["secs"] = float(rest[1])
        i = 2
    if len(rest) > i + 2 and rest[i].lower() in ("turn", "look"):
        cmd["look"] = [float(rest[i + 1]), float(rest[i + 2])]
    return cmd


def act(text):
    cmd = parse(text)
    n = last_step()
    if n < 0:
        show(wait_obs(0))
        n = 0
    path = os.path.join(SESSION, "cmd_%04d.json" % (n + 1))
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(cmd, f)
    os.replace(tmp, path)
    show(wait_obs(n + 1))


def note(text):
    with open(os.path.join(SESSION, "notes.jsonl"), "a", encoding="utf-8") as f:
        f.write(json.dumps({"step": max(0, last_step()), "note": text, "t": time.time()}, ensure_ascii=False) + "\n")
    print("noted at step %d" % max(0, last_step()))


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help", "help"):
        print(__doc__)
        return
    what = sys.argv[1]
    arg = " ".join(sys.argv[2:])
    if what == "look":
        show(wait_obs(max(0, last_step())))
    elif what == "act":
        try:
            act(arg)
        except (ValueError, IndexError) as e:
            sys.exit("could not read the command (%s). See `python play.py help`." % e)
    elif what == "note":
        note(arg)
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
