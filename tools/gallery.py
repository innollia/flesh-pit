"""Build a self-contained browser gallery for every generated asset.

    py -3 -B tools/gallery.py        -> writes gallery.html next to the repo root

Why the data is embedded rather than fetched:

  the gallery has to work when opened straight off the disk with file://, and a
  fetch() of a local manifest is blocked by CORS in every current browser.  So
  the metadata is inlined into the HTML and only the PNGs are referenced by
  relative path.  That also means the page is a single file you can copy or
  attach, which is what you want when reviewing art with someone.

The gallery scans the assets tree rather than trusting the manifests alone, so
files that no manifest claims -- and files whose size contradicts the spec --
still show up, flagged.  Silently hiding them would make the gallery a worse
review tool than the filesystem.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from fleshkit.build import ASSETS, OUT, ROOT

MANIFESTS = ["manifest.json", "manifest_sto.json", "manifest_dep.json",
             "manifest_cmp.json", "manifest_rst.json", "manifest_tex.json",
             "manifest_vfx.json", "manifest_tut.json", "manifest_mnu.json",
             "manifest_hnd.json", "manifest_acc.json", "manifest_cdx.json",
             "manifest_dth.json", "manifest_ldg.json", "manifest_band.json",
             "manifest_brd.json"]

GROUPS = {
    "STO": "Stomach / fullness", "HND": "First-person hands", "DEP": "Depth UI",
    "CMP": "Compass & canary", "ICO": "Tissue icons", "CDX": "Codex",
    "RST": "Restroom", "BAND": "Band cards", "MNU": "Menu & settings",
    "DTH": "Death & recovery", "TUT": "Tutorial", "LDG": "Loading",
    "TEX": "World textures", "VFX": "VFX", "BRD": "Brand", "ACC": "Accessibility",
}

STYLE = """
:root{
  --bg:#0b0908; --bg2:#151110; --card:#191413; --line:#2a2122;
  --fg:#c9bdb4; --dim:#7d6f68; --hot:#c9a613; --bad:#a8402f; --ok:#6f8f5a;
  --clean:#c9cecb;
}
*{box-sizing:border-box}
html,body{margin:0;background:var(--bg);color:var(--fg);
  font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
a{color:var(--hot)}
header{padding:22px 26px 14px;border-bottom:1px solid var(--line);background:var(--bg2)}
h1{margin:0 0 4px;font-size:17px;letter-spacing:.14em;text-transform:uppercase;color:#e2d6cb}
h1 span{color:var(--hot)}
.sub{color:var(--dim);font-size:12px}
.stats{display:flex;gap:22px;margin-top:14px;flex-wrap:wrap}
.stat b{display:block;font-size:19px;color:#e2d6cb;font-weight:600}
.stat i{color:var(--dim);font-style:normal;font-size:11px;letter-spacing:.08em}
.bar{position:sticky;top:0;z-index:5;display:flex;gap:8px;flex-wrap:wrap;
  padding:10px 26px;background:rgba(11,9,8,.96);border-bottom:1px solid var(--line);
  backdrop-filter:blur(6px)}
.bar input,.bar select,.bar button{background:#141010;color:var(--fg);
  border:1px solid var(--line);padding:5px 9px;font:inherit;border-radius:3px}
.bar input{min-width:230px}
.bar button{cursor:pointer}
.bar button.on{background:var(--hot);color:#141000;border-color:var(--hot)}
.bar .sp{flex:1}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(184px,1fr));
  gap:14px;padding:18px 26px 60px}
.card{background:var(--card);border:1px solid var(--line);border-radius:4px;
  overflow:hidden;cursor:pointer;display:flex;flex-direction:column}
.card:hover{border-color:#4a3b3a}
.thumb{height:132px;display:flex;align-items:center;justify-content:center;
  background-color:#0e0b0a;
  background-image:linear-gradient(45deg,#171312 25%,transparent 25%,transparent 75%,#171312 75%),
                   linear-gradient(45deg,#171312 25%,#0e0b0a 25%,#0e0b0a 75%,#171312 75%);
  background-size:16px 16px;background-position:0 0,8px 8px;overflow:hidden}
.thumb img{max-width:100%;max-height:100%;object-fit:contain;display:block}
.meta{padding:7px 9px 9px;border-top:1px solid var(--line)}
.id{color:#e2d6cb;font-size:11.5px;letter-spacing:.05em;display:flex;
  justify-content:space-between;gap:6px;align-items:baseline}
.id em{font-style:normal;font-size:9.5px;padding:1px 4px;border-radius:2px;
  letter-spacing:.06em;flex:none}
.mvp{background:#2a2210;color:var(--hot)}
.p1{background:#1a2226;color:#7fa3c9}
.p2{background:#201a1a;color:var(--dim)}
.bad{background:#331512;color:#d98070}
.nm{color:var(--dim);font-size:10px;margin-top:3px;overflow:hidden;
  text-overflow:ellipsis;white-space:nowrap}
.group{color:#6b5c55;font-size:9.5px;letter-spacing:.12em;margin-top:4px}
/* lightbox */
#lb{position:fixed;inset:0;background:rgba(6,5,5,.97);display:none;
  z-index:20;flex-direction:column}
#lb.on{display:flex}
#lb .top{display:flex;gap:14px;align-items:center;padding:12px 20px;
  border-bottom:1px solid var(--line)}
#lb .top b{color:#e2d6cb;letter-spacing:.06em}
#lb .top span{color:var(--dim)}
#lb .stage{flex:1;display:flex;align-items:center;justify-content:center;
  overflow:auto;padding:20px;
  background-color:#0e0b0a;
  background-image:linear-gradient(45deg,#171312 25%,transparent 25%,transparent 75%,#171312 75%),
                   linear-gradient(45deg,#171312 25%,#0e0b0a 25%,#0e0b0a 75%,#171312 75%);
  background-size:22px 22px;background-position:0 0,11px 11px}
#lb img{max-width:100%;max-height:100%;object-fit:contain;
  box-shadow:0 0 0 1px #2a2122,0 20px 60px rgba(0,0,0,.8)}
#lb .bot{padding:11px 20px;border-top:1px solid var(--line);color:var(--dim);
  display:flex;gap:26px;flex-wrap:wrap;font-size:11.5px}
#lb .bot b{color:#b8a99f;font-weight:400}
.empty{color:var(--dim);padding:40px 26px}
.chk{accent-color:var(--hot)}
"""

JS = """
const A = window.__ASSETS__;
const el = (t,c,h)=>{const e=document.createElement(t);if(c)e.className=c;
  if(h!=null)e.innerHTML=h;return e;};
let filt={g:'',p:'',k:'',q:''}, sel=null, cur=0;

function match(a){
  if(filt.g && a.group!==filt.g) return false;
  if(filt.p && a.pri!==filt.p) return false;
  if(filt.k && a.kind!==filt.k) return false;
  if(filt.q){
    const q=filt.q.toLowerCase();
    if(!(a.id.toLowerCase().includes(q)||a.file.toLowerCase().includes(q)
         ||(a.note||'').toLowerCase().includes(q))) return false;
  }
  return true;
}
function render(){
  const g=document.getElementById('grid'); g.innerHTML='';
  const list=A.filter(match);
  document.getElementById('count').textContent=list.length+' / '+A.length;
  if(!list.length){g.appendChild(el('div','empty','nothing matches'));return;}
  const frag=document.createDocumentFragment();
  for(const a of list){
    const c=el('div','card');
    const t=el('div','thumb');
    const im=new Image();
    im.loading='lazy';
    im.src=a.src; im.alt=a.id;
    im.onerror=()=>{t.innerHTML='<span style="color:#a8402f;font-size:10px">failed</span>';};
    t.appendChild(im); c.appendChild(t);
    const m=el('div','meta');
    const pri = a.bad ? 'bad' : a.pri;
    const priTxt = a.bad ? 'SPEC!' : a.pri;
    m.appendChild(el('div','id','<span>'+a.id+'</span><em class="'+pri+'">'+priTxt+'</em>'));
    m.appendChild(el('div','nm',a.file));
    m.appendChild(el('div','group',a.group+(a.kind?' / '+a.kind:'')));
    c.appendChild(m);
    c.onclick=()=>open(list,a);
    frag.appendChild(c);
  }
  g.appendChild(frag);
}
function open(list,a){
  sel=a; cur=list.indexOf(a);
  document.getElementById('lbimg').src=a.src;
  document.getElementById('lbid').textContent=a.id;
  document.getElementById('lbnote').textContent=a.note||'';
  document.getElementById('lbmeta').innerHTML=
    '<span><b>file</b> '+a.file+'</span>'+
    '<span><b>size</b> '+a.w+'x'+a.h+'</span>'+
    '<span><b>declared</b> '+a.dw+'x'+a.dh+'</span>'+
    '<span><b>kind</b> '+a.kind+'</span>'+
    '<span><b>frames</b> '+a.frames+'</span>'+
    (a.fps?'<span><b>fps</b> '+a.fps+'</span>':'')+
    '<span><b>pri</b> '+a.pri+'</span>'+
    (a.bad?'<span style="color:#d98070"><b>size does not match the spec row</b></span>':'');
  document.getElementById('lb').classList.add('on');
}
function step(d){
  if(!sel) return;
  const list=A.filter(match); if(!list.length) return;
  cur=(cur+d+list.length)%list.length;
  open(list,list[cur]);
}
document.getElementById('lb').onclick=e=>{if(e.target.id==='lb'||e.target.id==='stage')
  document.getElementById('lb').classList.remove('on');};
document.addEventListener('keydown',e=>{
  if(!document.getElementById('lb').classList.contains('on')) return;
  if(e.key==='Escape')document.getElementById('lb').classList.remove('on');
  if(e.key==='ArrowRight'||e.key==='ArrowDown')step(1);
  if(e.key==='ArrowLeft'||e.key==='ArrowUp')step(-1);
});
document.getElementById('q').oninput=e=>{filt.q=e.target.value;render();};
const gb=document.getElementById('groups');
for(const [k,v] of Object.entries(GROUPS)){
  const b=el('button','',k+' &middot; '+v);
  b.onclick=()=>{document.querySelectorAll('#groups button').forEach(x=>x.classList.remove('on'));
    if(filt.g===k){filt.g='';b.classList.remove('on');}else{filt.g=k;b.classList.add('on');}
    render();};
  gb.appendChild(b);
}
const pb=document.getElementById('pris');
for(const p of ['MVP','P1','P2']){
  const b=el('button','',p);
  b.onclick=()=>{document.querySelectorAll('#pris button').forEach(x=>x.classList.remove('on'));
    if(filt.p===p){filt.p='';b.classList.remove('on');}else{filt.p=p;b.classList.add('on');}render();};
  pb.appendChild(b);
}
const kb=document.getElementById('kinds');
for(const k of ['png32','9slice','atlas','flipbook','png']){
  const b=el('button','',k);
  b.onclick=()=>{document.querySelectorAll('#kinds button').forEach(x=>x.classList.remove('on'));
    if(filt.k===k){filt.k='';b.classList.remove('on');}else{filt.k=k;b.classList.add('on');}render();};
  kb.appendChild(b);
}
render();
"""


def main() -> int:
    reg: dict = {}
    for name in MANIFESTS:
        p = OUT / name
        if p.exists():
            reg.update(json.loads(p.read_text(encoding="utf-8"))["assets"])
    reg_by_path = {v["path"]: (k, v) for k, v in reg.items()}

    from PIL import Image

    items = []
    orphan = 0
    for png in sorted(ASSETS.rglob("*.png")):
        rel = png.relative_to(ASSETS).as_posix()
        aid, entry = reg_by_path.get(rel, (None, None))
        if entry is None:
            # id guessed from the filename so orphans are still filterable
            stem = png.stem
            m = re.match(r"^([a-z]{3,4})[_-]", stem)
            aid = (m.group(1).upper() if m else "?") + "-unregistered"
            orphan += 1
            pri, kind, frames, note, dw, dh, fps = "P2", "png32", 1, \
                "NOT IN ANY MANIFEST - generated outside the build scripts", 0, 0, 0
        else:
            pri = entry.get("pri", "P1")
            kind = entry.get("kind", "png32")
            frames = entry.get("frames", 1)
            note = entry.get("note", "")
            dw, dh = entry.get("w", 0), entry.get("h", 0)
            fps = entry.get("fps", 0)
        with Image.open(png) as im:
            w, h = im.size
        bad = bool(dw and (w, h) != (dw, dh))
        items.append({
            "id": aid, "file": rel, "src": "assets/" + rel,
            "w": w, "h": h, "dw": dw, "dh": dh,
            "pri": pri, "kind": kind, "frames": frames, "fps": fps or 0,
            "note": note, "group": aid.split("-")[0] if aid else "?",
            "bad": bad,
        })

    data = json.dumps(items, ensure_ascii=False).replace("</", "<\\/")
    mvp = sum(1 for a in items if a["pri"] == "MVP")
    bad = sum(1 for a in items if a["bad"] or "unregistered" in a["id"])
    orphan_n = sum(1 for a in items if "unregistered" in a["id"])

    html = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>flesh-pit &middot; asset gallery</title>
<style>{STYLE}</style></head>
<body>
<header>
  <h1>flesh<span>-pit</span> &middot; asset gallery</h1>
  <div class="sub">every generated image asset &middot; click any card to inspect &middot;
    arrow keys to step &middot; esc to close</div>
  <div class="stats">
    <div class="stat"><b>{len(items)}</b><i>FILES</i></div>
    <div class="stat"><b>{len(reg)}</b><i>REGISTERED</i></div>
    <div class="stat"><b>{mvp}</b><i>MVP</i></div>
    <div class="stat"><b>{len(GROUPS)}</b><i>GROUPS</i></div>
    <div class="stat"><b style="color:{'#d98070' if bad else '#6f8f5a'}">{bad}</b>
      <i>NEEDS REVIEW</i></div>
  </div>
</header>
<div class="bar">
  <input id="q" placeholder="search id, file, note...">
  <div id="pris"></div><div id="kinds"></div>
  <span class="sp"></span>
  <span class="sub" id="count"></span>
</div>
<div class="bar" id="groups"></div>
<div class="grid" id="grid"></div>
<div id="lb">
  <div class="top"><b id="lbid"></b><span id="lbnote"></span><span style="flex:1"></span>
    <span class="sub">esc close &middot; arrows step</span></div>
  <div class="stage" id="stage"><img id="lbimg"></div>
  <div class="bot" id="lbmeta"></div>
</div>
<script>const GROUPS={json.dumps(GROUPS)};
window.__ASSETS__={data};</script>
<script>{JS}</script>
</body></html>"""

    out = ROOT / "gallery.html"
    out.write_text(html, encoding="utf-8")
    # A sidecar index the page re-reads when it is served over http.  The embedded
    # copy is the file:// fallback; this one stays current, which matters because
    # other tooling does write into assets/ while a review is in progress.
    (ROOT / "assets_index.json").write_text(
        json.dumps(items, ensure_ascii=False), encoding="utf-8")
    print(f"wrote {out}  ({out.stat().st_size / 1024:.0f} KB)")
    print(f"  {len(items)} files, {len(reg)} registered, {mvp} MVP, "
          f"{orphan_n} unregistered, {bad} flagged")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
