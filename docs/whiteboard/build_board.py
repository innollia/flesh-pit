"""flesh-pit 기획·시스템 화이트보드 생성기.

flesh_pit_design.excalidraw(+ 같은 내용의 flesh_pit_full_design.excalidraw)를
플로우차트 중심으로 다시 만든다. 내용은 아래 데이터에 있고, 이 스크립트는
배치·화살표 연결(바인딩)·글자 크기만 계산한다. Excalidraw에서 손으로 고친
뒤에는 이 스크립트를 다시 돌리면 그 수정이 덮이므로, 큰 구조를 바꿀 때만 쓴다.

usage: python -X utf8 build_board.py
"""
import json
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = ["flesh_pit_design.excalidraw", "flesh_pit_full_design.excalidraw"]
FONT = 2
LABEL_SCALE = 1.3 ## shape/arrow labels: the boxes are sized for this
INK = "#2b2622"
MUTED = "#6b625a"

# 칙칙한 살·타일 톤: (채움, 테두리)
C = {
    "frame": ("#f6f3ef", "#b7aea5"),
    "loop": ("#ead6cf", "#8e3b35"),
    "decide": ("#efe5c4", "#86691c"),
    "danger": ("#e6c6c3", "#7a1f1f"),
    "safe": ("#dde3dc", "#4f6b4a"),
    "teeth": ("#e8dfcd", "#7a5c27"),
    "hair": ("#ddd1e5", "#5a3e79"),
    "tumor": ("#e7cdcd", "#8a2b2b"),
    "core": ("#ecd3d7", "#8a3946"),
    "mantle": ("#dbd0e4", "#5b4380"),
    "surface": ("#e9e1bb", "#7d6a1e"),
    "membrane": ("#d6d3cf", "#5f5953"),
    "kit": ("#d4dde5", "#3f5a73"),
    "main": ("#d8e3d4", "#47633f"),
    "audio": ("#e4ddd0", "#6e5a3a"),
    "done": ("#d2e4d0", "#3f6b3a"),
    "later": ("#e2e0dd", "#6f6a64"),
    "keep": ("#d6dee8", "#45607d"),
    "note": ("#f2ecd9", "#8f7b45"),
    "never": ("#e3cfcf", "#7a2a2a"),
}

_rng = random.Random(20261012)
_els = []
_index = [0]


def _base(kind, eid, x, y, w, h):
    _index[0] += 1
    return {
        "id": eid, "type": kind, "x": x, "y": y, "width": w, "height": h, "angle": 0,
        "strokeColor": INK, "backgroundColor": "transparent", "fillStyle": "solid",
        "strokeWidth": 2, "strokeStyle": "solid", "roughness": 1, "opacity": 100,
        "groupIds": [], "frameId": None, "index": "b%05d" % _index[0],
        "roundness": None, "seed": _rng.randrange(1, 2**31), "version": 1,
        "versionNonce": _rng.randrange(1, 2**31), "isDeleted": False,
        "boundElements": [], "updated": 1791800000000, "link": None, "locked": False,
    }


def _text_size(text, size):
    lines = text.split("\n")
    def width(line):
        # measured against an Excalidraw export: Hangul ~0.88 em, Latin ~0.5 em
        return sum(size * (0.88 if ord(ch) > 0x2000 else 0.5) for ch in line)
    return max(width(l) for l in lines), len(lines) * size * 1.25


def text(eid, x, y, s, size=18, color=INK, container=None, align="left"):
    w, h = _text_size(s, size)
    e = _base("text", eid, x, y, w, h)
    e.update({"text": s, "originalText": s, "fontSize": size, "fontFamily": FONT,
              "textAlign": align, "verticalAlign": "middle" if container else "top",
              "containerId": container, "lineHeight": 1.25, "autoResize": True,
              "strokeColor": color})
    _els.append(e)
    return e


def shape(kind, eid, x, y, w, h, label, style, size=18, dashed=False, round_=True):
    fill, stroke = C[style]
    e = _base(kind, eid, x, y, w, h)
    e.update({"backgroundColor": fill, "strokeColor": stroke,
              "strokeStyle": "dashed" if dashed else "solid"})
    if kind == "rectangle" and round_:
        e["roundness"] = {"type": 3}
    if kind == "diamond":
        e["roundness"] = {"type": 2}
    _els.append(e)
    if label:
        size = round(size * LABEL_SCALE)
        tw, th = _text_size(label, size)
        t = text(eid + "-t", x + (w - tw) / 2, y + (h - th) / 2, label, size, INK, container=eid, align="center")
        e["boundElements"].append({"type": "text", "id": t["id"]})
    return e


def box(eid, x, y, w, h, label, style, size=18, **kw):
    return shape("rectangle", eid, x, y, w, h, label, style, size, **kw)


def diamond(eid, x, y, w, h, label, style="decide", size=17):
    return shape("diamond", eid, x, y, w, h, label, style, size)


def ellipse(eid, x, y, w, h, label, style, size=18):
    return shape("ellipse", eid, x, y, w, h, label, style, size)


def frame(eid, x, y, w, h, title, sub=""):
    fill, stroke = C["frame"]
    e = _base("rectangle", eid, x, y, w, h)
    e.update({"backgroundColor": fill, "strokeColor": stroke, "roundness": {"type": 3}, "strokeWidth": 1})
    _els.append(e)
    text(eid + "-title", x + 30, y + 22, title, 30, INK)
    if sub:
        text(eid + "-sub", x + 32, y + 66, sub, 17, MUTED)


def _by_id(eid):
    return next(e for e in _els if e["id"] == eid)


def _anchor(e, side):
    x, y, w, h = e["x"], e["y"], e["width"], e["height"]
    return {"r": (x + w, y + h / 2), "l": (x, y + h / 2), "t": (x + w / 2, y), "b": (x + w / 2, y + h)}[side]


def arrow(eid, a, b, sa="r", sb="l", label="", color=INK, dashed=False, via=None, size=15):
    ea, eb = _by_id(a), _by_id(b)
    x0, y0 = _anchor(ea, sa)
    x1, y1 = _anchor(eb, sb)
    pts = [(0, 0)] + [(px - x0, py - y0) for px, py in (via or [])] + [(x1 - x0, y1 - y0)]
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    e = _base("arrow", eid, x0, y0, max(xs) - min(xs), max(ys) - min(ys))
    e.update({"points": [list(p) for p in pts], "strokeColor": color, "strokeWidth": 2,
              "strokeStyle": "dashed" if dashed else "solid", "roundness": {"type": 2},
              "startArrowhead": None, "endArrowhead": "arrow", "elbowed": False,
              "lastCommittedPoint": None,
              "startBinding": {"elementId": a, "focus": 0, "gap": 4},
              "endBinding": {"elementId": b, "focus": 0, "gap": 4}})
    _els.append(e)
    ea["boundElements"].append({"type": "arrow", "id": eid})
    eb["boundElements"].append({"type": "arrow", "id": eid})
    if label:
        size = round(size * LABEL_SCALE)
        mx, my = pts[len(pts) // 2] if len(pts) > 2 else ((pts[0][0] + pts[-1][0]) / 2, (pts[0][1] + pts[-1][1]) / 2)
        tw, th = _text_size(label, size)
        t = text(eid + "-t", x0 + mx - tw / 2, y0 + my - th / 2, label, size, INK, container=eid, align="center")
        e["boundElements"].append({"type": "text", "id": t["id"]})
    return e


# ---------------------------------------------------------------- 제목
text("title", 60, -170, "flesh-pit  기획 · 시스템 화이트보드", 52, INK)
text("subtitle", 64, -96, "화장실에서 출발해 재생하는 살을 먹고 파며 바깥으로 나간다.  위에서 아래로: 루프 → 경제 → 세계·위험 → 도구·변이 → 코드 구조 → 이슈 현황", 20, MUTED)

# ---------------------------------------------------------------- A. 핵심 루프
frame("fa", 0, 0, 2620, 1360, "A. 원정 핵심 루프", "원정 3~5분 / 전체 4~6시간.  실선 = 진행, 점선 = 부수 효과, 빨강 = 위험 분기")
L = 110  # 루프 노드 높이 기준
box("dig", 120, 260, 360, 190, "1  굴착\n좌클릭 잡기 → 유지 0.6초×경도\n1셀(4살단위) 뜯기\n먹은 살 = 제거 밀도 = 구멍", "loop")
box("stom", 720, 260, 360, 190, "2  위장 & 과식\n용량 100 / 과식 +60\n씹기 최대 ×3.0, 이동 감속\n목까지 살이 차오름", "loop")
diamond("full", 1300, 255, 300, 200, "위장 가득?\n통로가 좁아짐?")
box("ret", 1820, 260, 360, 190, "3  귀환\n카나리아 울음 경고\n손목시계 나침반\n화장실 문틀 등대 불빛", "loop")
box("vomit", 1820, 760, 360, 190, "4  변기 구토 (V)\n변기 앞에서만 보상\n야외 구토 = 보상 0\n종양 투척 시 긴 달그락", "loop")
box("settle", 1040, 760, 360, 190, "5  이빨 정산\n변기 레버 직접 누름\n1살 = 0.08이빨 물탱크\n레버로는 털 0", "loop")
box("shop", 380, 760, 400, 190, "6  강화 & 구매\n환풍구 존재: 이빨 → 도구\n탭 인형: 털 → 신체 변이\n물탱크 뚜껑 분리 흥정", "loop")
ellipse("deeper", 120, 1070, 380, 150, "더 깊은 껍질로 재출발", "safe", 20)
box("hairnow", 720, 40, 360, 110, "털은 먹는 즉시 팔에 자람\n(바이옴 50 / 공통 150 살단위)", "hair", 17)
box("crush", 1300, 560, 300, 120, "압사 위험\n막힘 ≥ 0.8 이 6초", "danger", 17)
box("death", 1520, 1080, 360, 150, "사망\n위장 살·소모품 유실물 드롭\n화장실 부활 (털·도구 보존)", "danger", 17)
arrow("a-dig-stom", "dig", "stom", label="먹은 만큼")
arrow("a-stom-full", "stom", "full")
arrow("a-full-ret", "full", "ret", label="예")
arrow("a-full-dig", "full", "dig", "t", "t", label="아니오: 계속 판다", via=[(1450, 205), (300, 205)], color=MUTED)
arrow("a-ret-vomit", "ret", "vomit", "b", "t", label="화장실 / 쉼터 도착")
arrow("a-vomit-settle", "vomit", "settle", "l", "r")
arrow("a-settle-shop", "settle", "shop", "l", "r")
arrow("a-shop-deeper", "shop", "deeper", "b", "r", via=[(580, 1145)])
arrow("a-deeper-dig", "deeper", "dig", "t", "b")
arrow("a-dig-hair", "dig", "hairnow", "t", "l", dashed=True, color=C["hair"][1], via=[(300, 95)])
arrow("a-full-crush", "full", "crush", "b", "t", label="재생에 갇힘", color=C["danger"][1])
arrow("a-crush-death", "crush", "death", "b", "t", color=C["danger"][1])
arrow("a-death-shop", "death", "shop", "l", "b", color=C["danger"][1], via=[(580, 1155)], dashed=True)
box("ending", 2260, 1080, 320, 200, "엔딩\n27m 바깥 껍질 돌파\n낮의 도시 길바닥으로 추락\n단일 회차 (다회차 없음)", "safe", 17)
arrow("a-ret-end", "ret", "ending", "r", "t", label="충분히 강해지면", via=[(2420, 355)], color=C["safe"][1], dashed=True)

# ---------------------------------------------------------------- H. 원칙
frame("fh", 2720, 0, 1180, 1360, "원칙", "모든 결정은 이 두 칸에 비춰 본다")
box("keep", 2780, 130, 520, 560, "반드시 지키는 것\n\n먹고 파기\n재생 압박\n위장 시계\n화장실 안식처\n눈에 보이는 신체 변이\n껍질 돌파와 탈출", "keep", 22)
box("never", 3340, 130, 520, 560, "절대 하지 않는 것\n\n생존 크래프팅 / 기지 건설\n거대 전투 / 점프 스케어\n공원 경영 / 복잡한 대화 트리\n도덕적 무게 · 고뇌 연출\n(살은 그냥 살)\n숫자·글자 화면 범람\n(몸이 곧 상태창)", "never", 20)
box("body-ui", 2780, 740, 1080, 280, "몸이 곧 상태창\n위장 부풂 · 허리띠 스프레이 잔량 · 손목시계 나침반\n멍과 상처 = 체력,  털 길이 = 변이 시점\n예외: 도감, 환풍구 자막, 승인된 위장 %", "note", 19)
box("tone", 2780, 1060, 1080, 250, "톤: 초기 콘솔 로우폴리 바디 호러\n투박한 로우폴리 + 극사실 살 텍스처, 64~256px, 밉맵 없음\n소리: 축축하고 가까운 소리, 파는 동안 배경음악 없음", "note", 18)

# ---------------------------------------------------------------- B. 3원 화폐
Y = 1480
frame("fb", 0, Y, 1900, 1180, "B. 3원 화폐 흐름 (서로 교환 불가)", "어디서 생겨서 어디로 쓰이는가")
box("eat", 80, Y + 150, 300, 120, "살을 먹는다\n(실제 섭취량)", "loop")
box("hair", 520, Y + 150, 360, 120, "털\n바이옴 50 / 공통 150\n살단위당 1가닥", "hair", 17)
box("tab", 1020, Y + 150, 340, 120, "탭 인형 화면\n(왼팔 시계 자세)", "hair")
box("mut", 1500, Y + 150, 340, 120, "신체 변이\nM01~M30 (29종)", "hair")
arrow("b1", "eat", "hair", label="즉시")
arrow("b2", "hair", "tab")
arrow("b3", "tab", "mut", label="구매")
box("belly", 80, Y + 420, 300, 120, "위장 속 살", "loop")
box("toilet", 520, Y + 420, 360, 120, "변기 구토 → 레버\n1살단위 = 0.08이빨", "teeth", 17)
box("teeth", 1020, Y + 420, 340, 120, "이빨\n물탱크에 쌓임", "teeth")
box("vent", 1500, Y + 420, 340, 120, "환풍구 존재\n도구 · 소모품 흥정", "teeth")
arrow("b4", "belly", "toilet", label="귀환")
arrow("b5", "toilet", "teeth")
arrow("b6", "teeth", "vent", label="최대 3개 제안")
arrow("b-eat-belly", "eat", "belly", "b", "t", label="위장으로")
box("tumor", 80, Y + 700, 300, 120, "종양 발견\n(가방 or 한 손 운반)", "tumor")
diamond("tchoice", 500, Y + 670, 300, 180, "먹을까\n가져갈까?", "decide")
box("tpoint", 1020, Y + 640, 340, 120, "종양 포인트\n배에 불룩 솟은 혹", "tumor")
box("tmut", 1500, Y + 640, 340, 120, "탭에서 터뜨림\n먹은 종양의 변이", "tumor")
box("tsell", 1020, Y + 900, 340, 120, "변기 정산\n종양 1개 = 24이빨 (원정 3회분)", "teeth", 17)
arrow("b7", "tumor", "tchoice")
arrow("b8", "tchoice", "tpoint", "r", "l", label="먹는다")
arrow("b9", "tpoint", "tmut")
arrow("b10", "tchoice", "tsell", "b", "l", label="가져간다", via=[(650, Y + 960)])
arrow("b11", "tsell", "teeth", "r", "b", dashed=True, color=C["teeth"][1], via=[(1440, Y + 960), (1440, Y + 600), (1190, Y + 600)])

# ---------------------------------------------------------------- C. 세계 구조
frame("fc", 2000, Y, 1900, 1180, "C. 세계 구조: 3중 구체 껍질", "안에서 바깥으로. 껍질 경계는 칼로만 뚫는 질긴 막")
box("room", 2060, Y + 150, 300, 230, "화장실 안식처\n4.5×2.6×3.0m 흰 타일\n살 침입 불가\n압사 진행 0\n문틀 앞 살 0.04m", "safe", 17)
box("core", 2420, Y + 150, 300, 230, "핵 0~9m\n압축 조직 (부푼 살)\n경도 1.0 · 재생 ×1.5\n진분홍 털\n쉼터 2", "core", 17)
box("m1", 2760, Y + 150, 110, 230, "막\n0.9m\n경도2.0", "membrane", 15)
box("mantle", 2910, Y + 150, 300, 230, "맨틀 9~18m\n수축 조직 (근육 살)\n경도 1.4 · 8초 파동 협착\n멍 보라 털\n쉼터 4", "mantle", 17)
box("m2", 3250, Y + 150, 110, 230, "막\n0.9m\n경도2.0", "membrane", 15)
box("surf", 3400, Y + 150, 300, 230, "지표면 18~27m\n신경 밀집 조직\n경도 1.2 · 신경 돌출\n믹서기 충전처\n노랑 털 · 쉼터 6", "surface", 17)
arrow("c1", "room", "core", label="문")
arrow("c2", "core", "m1")
arrow("c3", "m1", "mantle", label="칼")
arrow("c4", "mantle", "m2")
arrow("c5", "m2", "surf", label="칼")
box("outside", 3400, Y + 470, 300, 110, "바깥 껍질 돌파 → 엔딩", "safe", 18)
arrow("c6", "surf", "outside", "b", "t")
box("regen", 2060, Y + 660, 860, 220, "연속 재생 (쿨다운 없음)\n기본률 초당 0.003 × 조직 · 깊이 · 이웃 · 스프레이 배율\n배율 1.0에서 밀도 0 → 0.5 약 167초\n몸 0.9m · 방벽 0.9m · 화장실/쉼터 완전 보호, 영구 용해는 자라지 않음", "core", 17)
box("terrain-rule", 2980, Y + 660, 860, 220, "실제 살점 면 원칙\n먹은 살 = 제거 밀도 = 렌더 구멍 = 이동 공간\n껍질 돌파 전 살 내부의 외부 배경 노출 금지\n미게시 뜯김은 실제 밀도의 임시 면으로 즉시 표시", "membrane", 17)
box("shelter", 2060, Y + 930, 1780, 160, "쉼터 = 공사장 컨테이너 2.2×2.2×4.4m:  구토 + 레버 정산 전용,  살 침입 불가 / 압사 0,  피보나치 구 배치 (90도 분산)", "safe", 18)

# ---------------------------------------------------------------- D. 위험 / E. 첫 10분
Y2 = 2780
frame("fd", 0, Y2, 1900, 980, "D. 위험과 대응 흐름", "재생은 멈추지 않는다. 대응은 시간을 버는 것뿐")
box("regrow", 80, Y2 + 160, 300, 120, "살이 계속 재생", "core")
box("narrow", 460, Y2 + 160, 300, 120, "통로 협착\n(맨틀은 8초 파동)", "danger")
diamond("blocked", 840, Y2 + 130, 300, 180, "막힘 ≥ 0.8\n6초 유지?", "decide")
box("die", 1240, Y2 + 160, 300, 120, "압사 → 사망", "danger")
box("drop", 1240, Y2 + 380, 300, 150, "유실물 드롭\n지형 드리프트로 이동\n마지막 위치만 표시", "danger", 17)
box("respawn", 1240, Y2 + 620, 300, 120, "화장실 부활\n털 · 도구 보존", "safe")
arrow("d1", "regrow", "narrow")
arrow("d2", "narrow", "blocked")
arrow("d3", "blocked", "die", label="예", color=C["danger"][1])
arrow("d4", "die", "drop", "b", "t", color=C["danger"][1])
arrow("d5", "drop", "respawn", "b", "t")
box("canary", 80, Y2 + 400, 300, 140, "카나리아\n막힘 경고 울음\n먹이 = 경고 120초 강화", "teeth", 17)
box("tools-r", 460, Y2 + 400, 380, 180, "시간 벌기\n공업용 방벽 (최대 3, 4단계 변형)\n스프레이 영구 용해 (주변 재생 ×2)\n2배 속도 탈출 회복", "keep", 17)
box("nerve", 80, Y2 + 640, 720, 150, "신경 공격: 접촉 0.45m, 수축 1.3m (밀도 +0.45)\n체력 100, 초당 12 회복, 손의 멍·상처로 확인", "danger", 17)
arrow("d6", "canary", "narrow", "t", "b", dashed=True, color=C["teeth"][1], label="미리 알림")
arrow("d7", "tools-r", "blocked", "r", "b", dashed=True, color=C["keep"][1], label="아니오로 바꾼다", via=[(990, Y2 + 490)])

frame("fe", 2000, Y2, 1900, 980, "E. 첫 10분", "하나의 선으로 읽는다")
items = [
    ("t0", "0:00 암전 & 물소리\n변기에서 일어남\n팬티춤에 카나리아"),
    ("t1", "문 개방 & 첫 뜯기\n문틀 4cm 앞 살벽\n뒤돌면 재생 확인"),
    ("t2", "과식 & 첫 귀환\n배 차오름 · 통로 협착\n20초 어둠 뒤 눈부심"),
    ("t3", "레버 정산 & 환풍구\n물탱크 이빨 달그락\n천장 존재와 대화 → 칼"),
    ("t4", "2차 원정 & 첫 변이\n칼로 질긴 막 절단\n탭 인형 오른손 마디 변이"),
]
for i, (eid, s) in enumerate(items):
    col, row = i % 3, i // 3
    box(eid, 2070 + col * 610, Y2 + 170 + row * 380, 520, 230, s, "note", 19)
arrow("e1", "t0", "t1")
arrow("e2", "t1", "t2")
arrow("e3", "t2", "t3", "b", "t", via=[(3590, Y2 + 470), (2330, Y2 + 470)])
arrow("e4", "t3", "t4")

# ---------------------------------------------------------------- F. 도구·변이
Y3 = 3880
frame("ff", 0, Y3, 2400, 1240, "F. 도구 해금과 변이 가지", "깊이에 따라 열리고, 털 종류가 가지를 정한다")
box("u-core", 80, Y3 + 150, 340, 300, "핵에서 해금\n공업용 방벽 4이빨\n싼 스프레이 8이빨\n칼 16이빨\n카나리아 먹이 4이빨", "core", 18)
box("u-mantle", 480, Y3 + 150, 340, 300, "맨틀에서 해금\n비싼 스프레이 24이빨\n믹서기 40이빨\n종양 가방 16이빨", "mantle", 18)
box("u-surf", 880, Y3 + 150, 340, 300, "지표면에서 해금\n대형 톱 80이빨\n(양손, 한 번에 6셀)", "surface", 18)
arrow("f1", "u-core", "u-mantle")
arrow("f2", "u-mantle", "u-surf")
box("blender", 80, Y3 + 520, 1140, 200, "믹서기 (왼손): 뜯은 살을 들고 → 갈기 1.5초 + 마시기 1.5초 → 60%만 섭취\n충전: 신경을 믹서기 바닥 소켓에 끼워 초당 25 (1.5초마다 수축 위험)\nM21 발전 근육: 손에 들고 있을 때만 초당 5 자동 충전", "keep", 17)
box("hands", 80, Y3 + 770, 1140, 160, "허리띠 몸 인터페이스: 왼손 물건 / 오른손 물건 / 벨트 교환\n좌클릭·E = 왼손,  우클릭·R = 오른손,  Space = 살 속 상승 4.5m/s", "note", 17)
box("br-common", 1300, Y3 + 150, 1040, 150, "공통 털 12가닥 · 6종\nM01 늘어난 위 · M02 넓은 목구멍 · M03 자기장 눈 · M04 불거진 턱 · M05 접히는 어깨 · M06 긴 숨", "hair", 16)
box("br-core", 1300, Y3 + 330, 1040, 150, "핵 분홍 털 5가닥 · 6종\nM07 넓은 손바닥 · M08 물갈퀴 · M09 두꺼운 손톱 · M10 긴 마디 · M12 부푼 팔뚝 · M13 빨판 주름", "core", 16)
box("br-mantle", 1300, Y3 + 510, 1040, 150, "맨틀 보라 털 10가닥 · 7종\nM14 근육 과다 · M15 빠지는 턱 · M16 되새김 위 · M17 무통각증\nM18 두더지 앞발 · M19 연동 기기 · M20 과유연 관절", "mantle", 16)
box("br-surf", 1300, Y3 + 690, 1040, 170, "지표면 노랑 털 15가닥 / 조합 1.5배 · 10종\nM21 발전 근육 · M22 외계인 손 · M23 감각털 · M24 올빼미 눈 · M25 과잉 기억\nM26 도롱뇽 재생 · M27 코끼리 코 · M28 뼈없는 팔 · M29 휴면 · M30 목주머니", "surface", 16)
box("br-tumor", 1300, Y3 + 890, 1040, 300, "종양 변이 (포인트 1개) · 7종\nT1 반향정위: 화면이 라이다처럼 어두워지고 혀 클릭마다\n     몸에서 파동이 퍼져 벽을 타는 선으로 3D를 읽음\nT2 세 번째 팔 · T3 손바닥 입 · T4 부푼 몸통\nT5 어안: 200도 물고기 눈 왜곡 · T6 세로 턱 · T7 부채 갈비", "tumor", 16)

# ---------------------------------------------------------------- G. 코드 구조
frame("fg", 2500, Y3, 1400, 1240, "G. 코드 구조와 대표 흐름", "Kit는 Main을 모른다. 소리는 읽기와 신호 구독만")
box("g-in", 2560, Y3 + 150, 380, 100, "입력 (좌클릭 유지)", "main")
box("g-main", 2560, Y3 + 300, 380, 120, "Main\n거리 · 가구 차폐 · 도구 검사", "main")
box("g-chew", 2560, Y3 + 470, 380, 120, "FDKChewer (Kit)\n잡기 → 진행 → 뜯기 신호", "kit")
box("g-terr", 2560, Y3 + 640, 380, 140, "FDKTerrainField (Kit)\n공유 경계 밀도 제거\n같은 스냅샷 게시", "kit")
box("g-out", 2560, Y3 + 830, 380, 120, "표면 · 충돌 갱신\n위장 · 털 · 진행", "main")
arrow("g1", "g-in", "g-main", "b", "t")
arrow("g2", "g-main", "g-chew", "b", "t")
arrow("g3", "g-chew", "g-terr", "b", "t", label="cell_torn")
arrow("g4", "g-terr", "g-out", "b", "t")
box("g-hands", 3060, Y3 + 470, 380, 120, "손 리그 · 상황 모션\n(신호 구독, 표현만)", "kit")
box("g-audio", 3060, Y3 + 640, 380, 140, "fp_audio_hookup\n신호 → 소리 디렉터\n게임 상태를 바꾸지 않음", "audio")
box("g-save", 3060, Y3 + 830, 380, 120, "단일 로컬 슬롯 저장\nMain v5 / 진행 v3, 설정 분리", "main")
arrow("g5", "g-chew", "g-hands", dashed=True, color=C["kit"][1])
arrow("g6", "g-terr", "g-audio", dashed=True, color=C["audio"][1])
arrow("g7", "g-out", "g-save", dashed=True, color=C["main"][1], label="자동저장")
box("g-rule", 2560, Y3 + 1010, 880, 180, "검사는 사용자 슬롯을 읽거나 덮지 않는다 (별도 save_path)\n팔 B 자세 · Tab 0.20 · 피부 · 문은 다른 수정에 섞지 않는다\n먹은 양과 실제 제거 불일치, 살 내부 누출은 즉시 보고", "never", 16)

# ---------------------------------------------------------------- I. 이슈 현황
Y4 = 5240
frame("fi", 0, Y4, 3900, 1500, "I. 기획 대조 이슈 현황 (2026-10-12)", "녹색 = 이번에 해결,  파랑 = 지금 상태 유지 승인,  회색 = 나중에 할 일.  사용자 코멘트는 원문 그대로")
issues = [
    ("D01 어안 T5", "done", "해결: 실제 200도 등거리 어안 (5면 카메라 합성), 압사 시 같은 비율로 좁아짐",
     "문제"),
    ("D02 반향정위 T1", "done", "해결: 기본 화면에 라이다식 필터, 혀 클릭마다 몸에서 구형 파동 →\n벽을 타고 오르는 선 + 등고선 잔광, 분류 색 · 벽 너머 종양 표시, 혀 클릭 소리 연결",
     "윤곽 전용 화면이 아니라 기본 화면 자체가 게리모드 lider처럼 필터?가 씌워지는거지.\nlider처럼 점이 찍히는게 아니라 몸에서 원형으로 파가 나와서\n벽 타고 선이 올라가서 3D를 인식하게 되는거야"),
    ("D06 발전 근육 M21", "done", "해결: 손에 들었을 때만 충전.  신경에 믹서기를 대면\n노란 신경 가닥이 뽑혀 바닥 소켓에 꽂히는 모션 (왼손이 따라감)",
     "손에 있으면 충전되는게 맞음. 소유만 해서 충전되는건 문제임. 신경에 끼우는 모션도 있어야지.\n살점에 있는 신경에 믹서기 든 채로 상호작용하면 신경을 믹서기 바닥에 끼우고 충전을 해"),
    ("D07 게임패드 LB 충돌", "done", "해결: 웅크리기 = 왼쪽 스틱 누르기(L3), LB = 변이 화면", "문제가 맞음"),
    ("D10 외계인 손 M22", "done", "해결: 왼손만 떨며 뻗어 쥐고 → 뜯고 → 살을 입으로 가져감 (실제 뜯김 시점과 일치)", "문제임"),
    ("D11 변이 추가 뜯김", "done", "해결: M07 · M14 · M22 추가 제거도 첫 뜯김 렌더에 같이 게시", ""),
    ("V01 환풍구 NPC 뒤 살점 (대화로 보고)", "done", "해결: 덕트 모델에 닿는 지형 칸을 모두 비움 (모델 + 한 칸 0.5m)\n기존 저장도 불러올 때 덕트 영역만 비움",
     "환풍구에 npc 뒤쪽으로 살점 보이는 문제가 안 고쳐져 있음"),
    ("D08 문 상호작용 범위", "keep", "유지 (반각 30도 / 1.6m)", "실제로 사용하면서 바뀌는거라 괜찮음"),
    ("D09 거울 몸", "keep", "유지 (최적화용 별도 반사 몸)", "최적화 목적이라 괜찮음. tab화면과 거울 몸이 같기만 하면 됨"),
    ("D03 자기장 눈 윙 소리", "later", "나중에", "나중에 할 todo"),
    ("D04 NPC 한국어 음성", "later", "나중에", "나중에 할 todo임"),
    ("D05 엔딩 허밍 · 선율 · 목소리", "later", "나중에", "todo"),
]
for i, (name, st, result, quote) in enumerate(issues):
    col, row = i % 3, i // 3
    x = 60 + col * 1280
    y = Y4 + 130 + row * 330
    body = name + "\n" + result
    if quote:
        body += "\n\n사용자: “" + quote + "”"
    box("iss%d" % i, x, y, 1220, 300, body, st, 15)

doc = {"type": "excalidraw", "version": 2, "source": "flesh-pit docs/whiteboard/build_board.py",
       "elements": _els, "appState": {"viewBackgroundColor": "#fbfaf8", "gridSize": None}, "files": {}}
for name in OUT:
    with open(os.path.join(HERE, name), "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
print("elements", len(_els), "->", ", ".join(OUT))
