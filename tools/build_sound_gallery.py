"""Build one local HTML page that plays every sound in the game.

    py -3 -B tools/build_sound_gallery.py     -> writes build/sound_gallery.html

Reads game/audio/manifest.json (sounds + beds) and the "언제/느낌" tables of
game/audio/SOUND_LIST.md, and scans game/audio for wav files.  The metadata is
inlined into the page (fetch() of a local file is blocked under file://) and the
wavs are referenced by relative path (../game/audio/...), so the page plays
straight from the checkout without a server.  Re-running picks up whatever the
manifest has at that moment; nothing here is hand-listed except how known id
prefixes are grouped, and unknown ids still land in a catch-all group.

Output is deterministic: same inputs -> byte-identical page.  stdlib only.
"""

from __future__ import annotations

import json
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AUDIO = ROOT / "game" / "audio"
MANIFEST = AUDIO / "manifest.json"
SOUND_LIST = AUDIO / "SOUND_LIST.md"
OUT = ROOT / "build" / "sound_gallery.html"

# sfx purpose groups: (group title, id prefixes or exact ids).  First match wins.
SFX_GROUPS: list[tuple[str, tuple[str, ...]]] = [
    ("효과음 · 뜯기와 먹기", ("tear_", "nerve_twitch", "grab_refuse", "swallow", "stomach_gurgle",
                         "tumor_eat", "gulp_whole", "chew_")),
    ("효과음 · 토하기", ("gag_", "vomit_")),
    ("효과음 · 걸음", ("step_",)),
    ("효과음 · 몸과 깊이", ("regen_", "depth_", "shell_", "player_death", "ending_")),
    ("효과음 · 화장실과 변기", ("door_", "toilet_", "coin_", "tank_", "vent_", "settle_",
                            "blender_", "mirror_")),
    ("효과음 · 카나리아", ("canary_",)),
    ("효과음 · 도구와 장벽", ("barrier_", "spray_", "scissors_", "saw_")),
    ("효과음 · 변이", ("hair_", "echo_")),
    ("효과음 · 화면", ("ui_",)),
]
WIRE_SECTION_MARK = "신호 연결"  # SOUND_LIST heading of the signal-wiring sounds
ORDER = ["오류", "배경 묶음", "배경음악", "엔딩 노래 층", "반복음 · 배경 층", "반복음 · 씹기",
         "반복음 · 기타", WIRE_SECTION_MARK + " 소리"] + [g for g, _ in SFX_GROUPS] + \
        ["효과음 · 기타", "등록 안 됨"]


def res_to_rel(res: str) -> str:
    """res://audio/x.wav -> game/audio/x.wav (repo-relative, forward slashes)."""
    return "game/" + res[len("res://"):] if res.startswith("res://") else res


def wav_seconds(path: Path) -> float | None:
    """Duration from RIFF chunks (works for PCM and float wavs)."""
    try:
        with path.open("rb") as f:
            head = f.read(12)
            if head[:4] != b"RIFF" or head[8:12] != b"WAVE":
                return None
            byte_rate = None
            while True:
                ch = f.read(8)
                if len(ch) < 8:
                    return None
                cid, size = ch[:4], struct.unpack("<I", ch[4:])[0]
                if cid == b"fmt ":
                    fmt = f.read(size)
                    byte_rate = struct.unpack("<I", fmt[8:12])[0]
                elif cid == b"data":
                    return size / byte_rate if byte_rate else None
                else:
                    f.seek(size, 1)
                if size % 2:
                    f.seek(1, 1)
    except OSError:
        return None


def parse_sound_list(text: str) -> tuple[dict, dict]:
    """-> ({id: {kind, when, feel, section, hold}}, {id: [bullet notes]})."""
    rows: dict[str, dict] = {}
    notes: dict[str, list[str]] = {}
    section = "1차"
    for line in text.splitlines():
        if line.startswith("## "):
            section = line[3:].strip()
            continue
        s = line.strip()
        if s.startswith("- "):
            for tok in re.findall(r"[a-z][a-z0-9_]+", s):
                notes.setdefault(tok, [])
                if s[2:] not in notes[tok]:
                    notes[tok].append(s[2:])
            continue
        if not s.startswith("|") or s.startswith("|---") or s.startswith("| id"):
            continue
        cells = [c.strip() for c in s.strip("|").split("|")]
        if len(cells) < 4:
            continue
        ids_cell, kind, when, feel = cells[0], cells[1], cells[2], " | ".join(cells[3:])
        ids = expand_ids(ids_cell)
        hold = "보류" in s
        for i in ids:
            rows[i] = {"kind": kind, "when": when, "feel": feel, "section": section, "hold": hold,
                       "shared": len(ids) > 1}
    return rows, notes


def expand_ids(cell: str) -> list[str]:
    """'step_flesh_s1..s3' -> 3 ids, 'a / b' and 'a + b' -> 2 ids."""
    out: list[str] = []
    for part in re.split(r"\s*[/+]\s*", cell.replace("`", "")):
        m = re.fullmatch(r"([a-z0-9_]*?)(\d+)\.\.[a-z_]*?(\d+)", part)
        if m:
            out += [f"{m.group(1)}{n}" for n in range(int(m.group(2)), int(m.group(3)) + 1)]
        elif part:
            out.append(part)
    return out


def group_for(sid: str, snd: dict, info: dict | None) -> str:
    if info and WIRE_SECTION_MARK in info["section"]:
        return WIRE_SECTION_MARK + " 소리"
    if sid.startswith("mus_"):
        return "배경음악"
    if sid.startswith("song_"):
        return "엔딩 노래 층"
    if snd.get("kind") == "loop":
        if sid.startswith("amb_"):
            return "반복음 · 배경 층"
        if sid.startswith("chew_"):
            return "반복음 · 씹기"
        return "반복음 · 기타"
    for title, prefixes in SFX_GROUPS:
        if any(sid.startswith(p) for p in prefixes):
            return title
    return "효과음 · 기타"


def build() -> dict:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    rows, notes = parse_sound_list(SOUND_LIST.read_text(encoding="utf-8"))
    sounds = manifest.get("sounds", {})
    referenced: set[str] = set()
    errors: list[str] = []
    items: list[dict] = []

    for sid in sorted(sounds):
        snd = sounds[sid]
        info = rows.get(sid)
        files = []
        for i, res in enumerate(snd.get("files", [])):
            rel = res_to_rel(res)
            referenced.add(rel)
            p = ROOT / rel
            exists = p.is_file()
            if not exists:
                errors.append(f"{sid}: manifest 파일이 디스크에 없음 — {rel}")
            label = f"v{i + 1}" if len(snd.get("files", [])) > 1 else "재생"
            files.append({"label": label, "src": "../" + rel, "path": rel, "ok": exists,
                          "sec": round(wav_seconds(p), 2) if exists and wav_seconds(p) else None})
        items.append({
            "id": sid, "group": group_for(sid, snd, info), "kind": snd.get("kind", "?"),
            "loop": snd.get("kind") == "loop", "loop_seconds": snd.get("loop_seconds"),
            "spatial": bool(snd.get("spatial")), "files": files,
            "when": info["when"] if info else "", "feel": info["feel"] if info else "",
            "listKind": info["kind"] if info else "", "section": info["section"] if info else "",
            "hold": bool(info and info["hold"]), "notes": notes.get(sid, []),
            "described": info is not None,
        })

    beds = []
    for name in sorted(manifest.get("beds", {})):
        layers = manifest["beds"][name]
        srcs, missing = [], []
        for lid in layers:
            snd = sounds.get(lid)
            if not snd or not snd.get("files"):
                missing.append(lid)
                errors.append(f"배경 묶음 {name}: 층 {lid} 이(가) manifest sounds에 없음")
                continue
            srcs.append("../" + res_to_rel(snd["files"][0]))
        beds.append({"id": name, "layers": layers, "srcs": srcs, "missing": missing})

    unreferenced = []
    for p in sorted(AUDIO.rglob("*.wav")):
        rel = p.relative_to(ROOT).as_posix()
        if rel not in referenced:
            sec = wav_seconds(p)
            unreferenced.append({"path": rel, "src": "../" + rel, "sec": round(sec, 2) if sec else None})

    n_files = sum(len(it["files"]) for it in items)
    return {"items": items, "beds": beds, "unreferenced": unreferenced, "errors": errors,
            "order": ORDER, "counts": {"ids": len(items), "files": n_files, "beds": len(beds),
                                       "unreferenced": len(unreferenced), "errors": len(errors)}}


PAGE = r"""<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>flesh-pit 소리 모음</title>
<style>
:root{--bg:#f6f5f2;--card:#fff;--ink:#1d1c1a;--mute:#6b6862;--line:#e2dfd8;--acc:#8a2f2f;--acc-ink:#fff;--ok:#2d6a3e;--warn:#9a5b00;--err:#b3261e;--chip:#efece6}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#151413;--card:#1f1e1c;--ink:#ecebe7;--mute:#a19d95;--line:#33312d;--acc:#d06a6a;--acc-ink:#151413;--ok:#7fc58f;--warn:#e0a54a;--err:#ff8a80;--chip:#2a2825}}
:root[data-theme="dark"]{--bg:#151413;--card:#1f1e1c;--ink:#ecebe7;--mute:#a19d95;--line:#33312d;--acc:#d06a6a;--acc-ink:#151413;--ok:#7fc58f;--warn:#e0a54a;--err:#ff8a80;--chip:#2a2825}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 system-ui,"Malgun Gothic","Apple SD Gothic Neo",sans-serif}
header{position:sticky;top:0;z-index:5;background:var(--bg);border-bottom:1px solid var(--line);padding:12px 16px}
.bar{display:flex;flex-wrap:wrap;gap:10px 16px;align-items:center;max-width:1100px;margin:0 auto}
h1{font-size:18px;margin:0 8px 0 0}
.counts{color:var(--mute);font-size:13px}
input[type=search]{flex:1 1 220px;min-width:0;padding:7px 10px;border:1px solid var(--line);border-radius:8px;background:var(--card);color:var(--ink);font:inherit}
label.vol{display:flex;align-items:center;gap:6px;font-size:13px;color:var(--mute)}
button{font:inherit;cursor:pointer;border:1px solid var(--line);background:var(--card);color:var(--ink);border-radius:8px;padding:5px 11px}
button:hover{border-color:var(--acc)}
button.playing{background:var(--acc);color:var(--acc-ink);border-color:var(--acc)}
button.stop{border-color:var(--acc);color:var(--acc)}
button[disabled]{opacity:.45;cursor:not-allowed;text-decoration:line-through}
main{max-width:1100px;margin:0 auto;padding:8px 16px 60px}
nav{display:flex;flex-wrap:wrap;gap:6px;margin:12px 0}
nav a{font-size:13px;color:var(--mute);text-decoration:none;background:var(--chip);padding:3px 9px;border-radius:999px}
nav a:hover{color:var(--ink)}
section h2{font-size:16px;margin:26px 0 10px;padding-bottom:4px;border-bottom:1px solid var(--line)}
section h2 small{color:var(--mute);font-weight:normal}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(310px,1fr));gap:10px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:10px 12px}
.card .top{display:flex;flex-wrap:wrap;gap:6px;align-items:baseline}
.card code{font-weight:600;font-size:14px}
.tag{font-size:11px;padding:1px 7px;border-radius:999px;background:var(--chip);color:var(--mute)}
.tag.hold{background:var(--warn);color:var(--bg)}
.tag.err{background:var(--err);color:var(--bg)}
.desc{margin:6px 0;font-size:13.5px}
.desc b{color:var(--mute);font-weight:600;margin-right:4px}
.note{font-size:12.5px;color:var(--mute);margin:4px 0;overflow-wrap:anywhere}
.card{min-width:0;overflow-wrap:anywhere}
.btns{display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin-top:6px}
.dur{font-size:12px;color:var(--mute)}
.errors{background:var(--card);border:1px solid var(--err);border-radius:10px;padding:10px 14px;color:var(--err)}
.errors li{margin:2px 0}
.row{display:flex;flex-wrap:wrap;gap:8px;align-items:center;padding:6px 0;border-bottom:1px solid var(--line);font-size:13px}
.row code{flex:1 1 260px;word-break:break-all}
.hidden{display:none!important}
label.lp{font-size:12.5px;color:var(--mute);display:flex;align-items:center;gap:4px}
</style>
</head>
<body>
<header><div class="bar">
<h1>flesh-pit 소리 모음</h1>
<span class="counts" id="counts"></span>
<input type="search" id="q" placeholder="검색: id, 언제, 느낌, 파일 이름">
<label class="vol">음량 <input type="range" id="vol" min="0" max="1" step="0.01" value="0.7"></label>
<button class="stop" id="stopall">모두 멈춤</button>
<button id="theme" title="밝게/어둡게">밝기</button>
</div></header>
<main>
<nav id="nav"></nav>
<div id="root"></div>
</main>
<script>
const DATA = __DATA__;
const $ = (t, a = {}, ...kids) => { const e = document.createElement(t); for (const [k, v] of Object.entries(a)) { if (k === "class") e.className = v; else if (k === "text") e.textContent = v; else if (k.startsWith("on")) e.addEventListener(k.slice(2), v); else e.setAttribute(k, v); } for (const c of kids) if (c != null) e.append(c); return e; };
const live = new Set();
let volume = 0.7;
function stopAll() { for (const p of [...live]) p.stop(); }
function fmt(s) { return s == null ? "" : s >= 60 ? `${Math.floor(s / 60)}:${(s % 60).toFixed(1).padStart(4, "0")}` : `${s.toFixed(2)} s`; }
// one player = one or more <audio> started together (beds play all layers in sync)
function makePlayer(btn, srcs, loopGetter) {
  let auds = null;
  const p = {
    stop() { if (auds) { for (const a of auds) { a.pause(); a.currentTime = 0; } } auds = null; btn.classList.remove("playing"); live.delete(p); },
    start() {
      auds = srcs.map(s => { const a = new Audio(s); a.preload = "auto"; a.volume = volume; a.loop = loopGetter(); return a; });
      auds[0].addEventListener("ended", () => { if (!auds || !auds[0].loop) p.stop(); });
      btn.classList.add("playing"); live.add(p);
      Promise.all(auds.map(a => new Promise(r => a.readyState >= 3 ? r() : a.addEventListener("canplaythrough", r, { once: true }))))
        .then(() => { if (auds) for (const a of auds) a.play().catch(e => { btn.title = "재생 실패: " + e.message; p.stop(); }); });
      auds.forEach(a => a.addEventListener("error", () => { btn.title = "파일을 열 수 없음"; p.stop(); }, { once: true }));
    },
    setLoop(v) { if (auds) for (const a of auds) a.loop = v; },
    setVol(v) { if (auds) for (const a of auds) a.volume = v; },
  };
  btn.addEventListener("click", () => { const was = live.has(p); if (was) p.stop(); else p.start(); });
  return p;
}
const groups = new Map();
function group(title, sub) {
  if (!groups.has(title)) { const g = $("div", { class: "grid" }); groups.set(title, { el: g, sub, n: 0 }); }
  return groups.get(title);
}
function soundCard(it) {
  const hay = [it.id, it.when, it.feel, it.kind, it.listKind, it.section, ...it.notes, ...it.files.map(f => f.path)].join(" ").toLowerCase();
  const loopBox = it.loop ? $("input", { type: "checkbox" }) : null;
  if (loopBox) loopBox.checked = true;
  const top = $("div", { class: "top" }, $("code", { text: it.id }),
    $("span", { class: "tag", text: it.listKind || it.kind }),
    it.spatial ? $("span", { class: "tag", text: "3D" }) : null,
    it.hold ? $("span", { class: "tag hold", text: "보류" }) : null,
    it.files.some(f => !f.ok) ? $("span", { class: "tag err", text: "파일 없음" }) : null,
    it.section ? $("span", { class: "tag", text: it.section.replace(/\s*\(.*$/, "") }) : null);
  const card = $("div", { class: "card" }, top);
  if (it.described) {
    card.append($("div", { class: "desc" }, $("b", { text: "언제" }), it.when));
    card.append($("div", { class: "desc" }, $("b", { text: "느낌" }), it.feel));
  } else card.append($("div", { class: "note", text: "SOUND_LIST.md에 설명 줄이 없음" }));
  for (const n of it.notes) card.append($("div", { class: "note", text: n }));
  const btns = $("div", { class: "btns" });
  const players = [];
  for (const f of it.files) {
    const b = $("button", { text: f.label, title: f.path });
    if (!f.ok) b.disabled = true; else players.push(makePlayer(b, [f.src], () => loopBox ? loopBox.checked : false));
    btns.append(b);
  }
  const secs = it.files.map(f => f.sec).filter(s => s != null);
  if (secs.length) btns.append($("span", { class: "dur", text: secs.length > 1 ? `${fmt(Math.min(...secs))}–${fmt(Math.max(...secs))}` : fmt(secs[0]) }));
  if (loopBox) { loopBox.addEventListener("change", () => players.forEach(p => p.setLoop(loopBox.checked))); btns.append($("label", { class: "lp" }, loopBox, "반복")); }
  card.append(btns);
  card.dataset.hay = hay;
  return card;
}
function render() {
  const c = DATA.counts;
  document.getElementById("counts").textContent = `id ${c.ids}개 · 파일 ${c.files}개 · 배경 묶음 ${c.beds}개 · 등록 안 됨 ${c.unreferenced}개` + (c.errors ? ` · 오류 ${c.errors}개` : "");
  if (DATA.errors.length) {
    const g = group("오류", "manifest에 있는데 디스크에 없는 파일");
    g.el.className = "errors"; g.el.append($("ul", {}, ...DATA.errors.map(e => $("li", { text: e }))));
  }
  for (const b of DATA.beds) {
    const g = group("배경 묶음", "누르면 모든 층이 함께 반복 재생");
    const btn = $("button", { text: "함께 재생" });
    if (!b.srcs.length) btn.disabled = true; else makePlayer(btn, b.srcs, () => true);
    const card = $("div", { class: "card" }, $("div", { class: "top" }, $("code", { text: b.id }), $("span", { class: "tag", text: `${b.layers.length}층` })),
      $("div", { class: "desc" }, $("b", { text: "층" }), b.layers.join(" + ")),
      b.missing.length ? $("div", { class: "note", text: "없는 층: " + b.missing.join(", ") }) : null,
      $("div", { class: "btns" }, btn));
    card.dataset.hay = (b.id + " " + b.layers.join(" ")).toLowerCase();
    g.el.append(card); g.n++;
  }
  for (const it of DATA.items) { const g = group(it.group); g.el.append(soundCard(it)); g.n++; }
  for (const u of DATA.unreferenced) {
    const g = group("등록 안 됨", "game/audio 아래 있지만 manifest가 쓰지 않는 wav");
    const btn = $("button", { text: "재생" }); makePlayer(btn, [u.src], () => false);
    const row = $("div", { class: "row" }, $("code", { text: u.path }), $("span", { class: "dur", text: fmt(u.sec) }), btn);
    row.dataset.hay = u.path.toLowerCase(); g.el.append(row); g.n++;
  }
  const ug = groups.get("등록 안 됨"); if (ug) ug.el.className = "";
  const root = document.getElementById("root"), nav = document.getElementById("nav");
  const titles = [...DATA.order.filter(t => groups.has(t)), ...[...groups.keys()].filter(t => !DATA.order.includes(t))];
  titles.forEach((t, i) => {
    const g = groups.get(t), id = "g" + i;
    g.sec = $("section", { id }, $("h2", {}, t + " ", $("small", { text: `${g.n}` + (g.sub ? " · " + g.sub : "") })), g.el);
    root.append(g.sec); g.link = $("a", { href: "#" + id, text: `${t} ${g.n}` }); nav.append(g.link);
  });
}
function filter(q) {
  q = q.trim().toLowerCase();
  for (const g of groups.values()) {
    if (g.el.className === "errors") continue;
    let shown = 0;
    for (const el of g.el.children) { const m = !q || el.dataset.hay.includes(q); el.classList.toggle("hidden", !m); shown += m; }
    g.sec.classList.toggle("hidden", !shown); g.link.classList.toggle("hidden", !shown);
  }
}
render();
document.getElementById("q").addEventListener("input", e => filter(e.target.value));
document.getElementById("vol").addEventListener("input", e => { volume = +e.target.value; for (const p of live) p.setVol(volume); });
document.getElementById("stopall").addEventListener("click", stopAll);
document.addEventListener("keydown", e => { if (e.key === "Escape") stopAll(); });
document.getElementById("theme").addEventListener("click", () => {
  const r = document.documentElement, dark = r.dataset.theme ? r.dataset.theme === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
  r.dataset.theme = dark ? "light" : "dark";
});
</script>
</body>
</html>
"""


def main() -> int:
    data = build()
    blob = json.dumps(data, ensure_ascii=False, sort_keys=True).replace("</", "<\\/")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(PAGE.replace("__DATA__", blob), encoding="utf-8", newline="\n")
    c = data["counts"]
    print(f"wrote {OUT.relative_to(ROOT).as_posix()}: {c['ids']} ids, {c['files']} files, "
          f"{c['beds']} beds, {c['unreferenced']} unreferenced, {c['errors']} errors")
    for e in data["errors"]:
        print("  ERROR", e)
    return 1 if data["errors"] else 0


if __name__ == "__main__":
    sys.exit(main())
