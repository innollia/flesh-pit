"""Writes build/voice_sheet.html: the recording script for the vent voice.
Every line with its file name, when it comes up and whether it is recorded.

Run:  python -X utf8 tools/build_voice_sheet.py
"""
from __future__ import annotations

import argparse
import html
import json
from pathlib import Path

from voice_lines import REPO, clip_ids, load_lines, read_stamp, voice_dir

PAGE = """<!doctype html>
<html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>환풍구 녹음 대본</title>
<style>
:root { --bg:#faf7f2; --ink:#231c18; --dim:#6d625a; --line:#ddd3c8; --band:#efe7dc; --todo:#9b2c1d; --done:#2c6e3f; --warn:#94610a; }
@media (prefers-color-scheme: dark) { :root { --bg:#1a1614; --ink:#efe8e0; --dim:#a79b90; --line:#3b332e; --band:#2a2420; --todo:#ef8c79; --done:#79c790; --warn:#e0b05c; } }
body { margin:0; background:var(--bg); color:var(--ink); font:16px/1.55 "Malgun Gothic", system-ui, sans-serif; }
main { max-width:1100px; margin:0 auto; padding:24px 16px 80px; }
h1 { font-size:26px; margin:0 0 4px; }
.count { color:var(--dim); margin:0 0 16px; }
.how { background:var(--band); border-radius:6px; padding:12px 16px; margin-bottom:16px; }
.how ul { margin:0; padding-left:20px; }
code { font:14px Consolas, monospace; overflow-wrap:anywhere; }
.bar { position:sticky; top:0; background:var(--bg); padding:10px 0; display:flex; flex-wrap:wrap; gap:16px; align-items:center; border-bottom:1px solid var(--line); z-index:1; }
.bar input[type=search] { font:inherit; padding:4px 8px; }
.bar select { font:inherit; padding:4px; }
table { width:100%; border-collapse:collapse; margin-top:8px; }
th, td { text-align:left; vertical-align:top; padding:8px 10px 8px 0; border-bottom:1px solid var(--line); }
th { color:var(--dim); font-weight:normal; font-size:14px; }
td.ko { font-size:18px; }
td.when { color:var(--dim); font-size:14px; }
button.file { font:14px Consolas, monospace; background:none; border:0; padding:0; color:inherit; cursor:copy; text-align:left; overflow-wrap:anywhere; }
button.file:hover { text-decoration:underline; }
tr.group td { background:var(--band); font-weight:bold; padding:6px 10px; }
.st-todo { color:var(--todo); } .st-done { color:var(--done); } .st-stale { color:var(--warn); }
@media (max-width:700px) {
  thead { display:none; }
  table, tbody, tr, td { display:block; width:100%; }
  tr { padding:8px 0; border-bottom:1px solid var(--line); }
  td { border:0; padding:2px 0; }
}
</style></head>
<body><main>
<h1>환풍구 녹음 대본</h1>
<p class="count" id="count"></p>
<div class="how"><ul>
<li>저장할 곳: <code>{folder}</code></li>
<li>파일 이름: <code>대사 id.wav</code> 또는 <code>대사 id.ogg</code>. 표의 이름을 누르면 복사된다. 같은 이름의 파일을 넣으면 다음 실행부터 그 대사에서 나온다. 둘 다 있으면 ogg가 나온다.</li>
<li>권장 형식: 48 kHz, 모노, 24비트 WAV(또는 Ogg Vorbis 품질 6 이상).</li>
<li>음량: 파일마다 통합 -18 LUFS(±3), 트루 피크 -1.5 dBTP 이하. 앞뒤 무음은 0.1초 안쪽으로 자른다. 자막이 파일 길이를 따라간다.</li>
<li>다음 대사가 나오면 나오던 음성은 끊긴다. 대사 사이 최소 간격은 2.5초다.</li>
<li>대사의 괄호는 소리·행동 표기이고 자막에도 그대로 나온다.</li>
<li>넣은 뒤 검사: <code>python -X utf8 tools/check_voice_files.py</code>(EXTENSIBLE WAV라고 나오면 <code>--fix</code>를 붙인다), 다 끝나면 <code>--stamp</code>를 붙여 한 번 더(문구가 나중에 바뀌면 찾아 준다).</li>
<li>이 표는 만든 때의 상태다. 파일을 넣은 뒤 <code>python -X utf8 tools/build_voice_sheet.py</code>로 다시 만든다.</li>
</ul></div>
<div class="bar">
<label><input type="checkbox" id="todo"> 녹음 안 한 것만</label>
<label>묶기 <select id="by"><option value="">없음</option><option value="section">조건</option><option value="mood">감정(초벌 분류)</option></select></label>
<input type="search" id="q" placeholder="찾기" aria-label="대사 찾기">
</div>
<table><thead><tr><th>파일 이름</th><th>대사</th><th>나오는 조건</th><th>감정</th><th>녹음</th></tr></thead><tbody id="rows"></tbody></table>
</main>
<script id="data" type="application/json">{data}</script>
<script>
const lines = JSON.parse(document.getElementById('data').textContent);
const LABEL = { todo: '없음', done: '있음', stale: '문구 바뀜' };
const $ = id => document.getElementById(id);
const esc = s => s.replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
function row(l) {
  const name = l.id + '.' + (l.ext || 'wav');
  return `<tr><td><button class="file" data-name="${esc(name)}" title="눌러서 복사">${esc(name)}</button></td>`
    + `<td class="ko">${esc(l.ko)}</td><td class="when">${esc(l.when)}</td><td>${esc(l.mood)}</td>`
    + `<td class="st-${l.state}">${LABEL[l.state]}</td></tr>`;
}
function draw() {
  const q = $('q').value.trim();
  const by = $('by').value;
  const shown = lines.filter(l => (!$('todo').checked || l.state !== 'done')
    && (!q || (l.id + l.ko + l.when).includes(q)));
  let out = '';
  if (by) {
    const groups = new Map();
    for (const l of shown) (groups.get(l[by]) || groups.set(l[by], []).get(l[by])).push(l);
    for (const [name, ls] of groups) {
      out += `<tr class="group"><td colspan="5">${esc(name)} (${ls.length})</td></tr>` + ls.map(row).join('');
    }
  } else {
    out = shown.map(row).join('');
  }
  $('rows').innerHTML = out;
  const done = lines.filter(l => l.state === 'done').length;
  $('count').textContent = `대사 ${lines.length}줄, 녹음 ${done}줄, 남은 ${lines.length - done}줄. 지금 보이는 줄 ${shown.length}.`;
}
for (const id of ['todo', 'by']) $(id).addEventListener('change', draw);
$('q').addEventListener('input', draw);
$('rows').addEventListener('click', e => {
  const b = e.target.closest('button.file');
  if (!b) return;
  navigator.clipboard.writeText(b.dataset.name).then(() => {
    const was = b.textContent;
    b.textContent = '복사됨';
    setTimeout(() => { b.textContent = was; }, 700);
  });
});
draw();
</script></body></html>
"""


def rows(game: Path) -> list[dict]:
    present = clip_ids(game)
    stamp = read_stamp(game)
    out = []
    for line in load_lines(game):
        ext = present.get(line["id"], "")
        stale = ext and line["id"] in stamp and stamp[line["id"]] != line["ko"]
        state = "stale" if stale else ("done" if ext else "todo")
        out.append({**line, "ext": ext, "state": state})
    return out


def build(game: Path, out: Path) -> int:
    data = rows(game)
    payload = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    page = PAGE.replace("{folder}", html.escape(str(voice_dir(game)))).replace("{data}", payload)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page, encoding="utf-8")
    return len(data)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, default=REPO / "game")
    parser.add_argument("--out", type=Path, default=REPO / "build/voice_sheet.html")
    args = parser.parse_args()
    count = build(args.game, args.out)
    print(f"{count} lines -> {args.out}")


if __name__ == "__main__":
    main()
