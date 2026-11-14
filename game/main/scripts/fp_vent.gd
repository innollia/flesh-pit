class_name FPVent
extends Node3D

## Ceiling vent shop (spec 03-restroom 7, content/vent-lines.md). No UI.
## Open the grate: only the dark shows, never the being's eyes (user
## 2026-11-03). The being wants "BONG" (teeth). Trade: open the tank lid,
## scoop a handful, place handfuls at the vent, the being holds a few items
## out, one hand per item; take one by hand, the rest go back.
## Prices are never shown and there is no change. Leaving without picking
## keeps the teeth and the same offer comes back next time.
## Every reaction is a line id from main/data/vent_lines.json, emitted on
## line_spoken for the voice/subtitle layer.

signal line_spoken(line_id: String)
signal offers_changed(ids: Array)
## Early items spilled out on an absurd overpay (already granted).
signal spilled(ids: Array)
## A crayon drawing of a settled tumor floats down (spec 03-restroom 10).
signal drawing_dropped(kind: String)

## Timings and line pools are editable in main/data/vent_rules.json.
const RULES_PATH := "res://main/data/vent_rules.json"
static var _rules: Dictionary = {}

static func _rule_data() -> Dictionary:
    if _rules.is_empty() and FileAccess.file_exists(RULES_PATH):
        var d = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
        _rules = d if d is Dictionary else {"_bad": true}
    return _rules

static func _num(key: String, fallback: float) -> float:
    var t = _rule_data().get("시간", {}).get(key, {})
    return float(t.get("값", fallback)) if t is Dictionary else fallback

static func _pool(key: String, fallback: Array) -> Array[String]:
    var out: Array[String] = []
    var p = _rule_data().get("대사묶음", {}).get(key, {})
    var ids = p.get("대사", fallback) if p is Dictionary else fallback
    for i in ids:
        out.append(String(i))
    return out

## A number from the 기준 table of vent_rules.json.
static func _lim(key: String, fallback: float) -> float:
    var t = _rule_data().get("기준", {}).get(key, {})
    return float(t.get("값", fallback)) if t is Dictionary else fallback

## Items spilled on an absurd overpay (쏟아지는물건 in vent_rules.json).
static func spill_list() -> Array[String]:
    return _pool_raw(_rule_data().get("쏟아지는물건", {}), "목록", ["barrier", "spray_cheap", "canary_feed", "knife"])

static func _pool_raw(p, field: String, fallback: Array) -> Array[String]:
    var out: Array[String] = []
    var ids = p.get(field, fallback) if p is Dictionary else fallback
    for i in ids:
        out.append(String(i))
    return out

static var TOGGLE_START: int = int(_lim("TOGGLE_START", 2))
static var TOGGLE_HIDE_COUNT: int = int(_lim("TOGGLE_HIDE_COUNT", 5))
static var TOGGLE_MEMORY: float = _lim("TOGGLE_MEMORY", 4.0)
static var EMPTY_AGAIN: int = int(_lim("EMPTY_AGAIN", 2))
static var EMPTY_THIRD: int = int(_lim("EMPTY_THIRD", 3))
static var IGNORED_LATE: float = _lim("IGNORED_LATE", 600.0)
static var OPEN_EARLY: float = _lim("OPEN_EARLY", 3.0)
static var ABSURD_MULT: float = _lim("ABSURD_MULT", 2.0)
static var ABSURD_MIN: int = int(_lim("ABSURD_MIN", 32))
static var LOTS_MULT: float = _lim("LOTS_MULT", 1.5)
static var LITTLE_STREAK: int = int(_lim("LITTLE_STREAK", 2))
static var BLOOD_REMARK: float = _lim("BLOOD_REMARK", 0.5)
static var HAIRS_REMARK: int = int(_lim("HAIRS_REMARK", 40))
static var LONG_ABSENT_MULT: float = _lim("LONG_ABSENT_MULT", 5.0)

static var FRANTIC_TIME: float = _num("FRANTIC_TIME", 20.0)
static var CALM_TIME: float = _num("CALM_TIME", 30.0)
## Seconds between escalating nags while the player ignores the being.
static var NAG_INTERVAL: float = _num("NAG_INTERVAL", 6.0)
## Opens within this window count as "여닫기 반복".
static var TOGGLE_WINDOW: float = _num("TOGGLE_WINDOW", 5.0)
static var IDLE_TIME: float = _num("IDLE_TIME", 12.0)
static var STARE_TIME: float = _num("STARE_TIME", 5.0)
static var PICK_LONG_TIME: float = _num("PICK_LONG_TIME", 15.0)
## Away this long counts as "한참 뒤 돌아옴" / "오래 안 옴".
static var LONG_AWAY: float = _num("LONG_AWAY", 120.0)
static var SPRAY_SULK: float = _num("SPRAY_SULK", 40.0)
static var TOGGLE_HIDE: float = _num("TOGGLE_HIDE", 20.0)
static var REMARK_COOLDOWN: float = _num("REMARK_COOLDOWN", 90.0)
## Voice gate (2026-10-19 play: it talked too much and spoke the instant a
## condition matched). The being still decides a line at once (spoken,
## last_line: its memory; last_line is saved); line_spoken (subtitles, voice) comes after
## a reaction delay. Room chatter about what the player is doing is voiced
## only after a quiet spell, only sometimes, and not the same line again soon.
static var VOICE_DELAY_MIN: float = _num("VOICE_DELAY_MIN", 0.7)
static var VOICE_DELAY_MAX: float = _num("VOICE_DELAY_MAX", 1.6)
static var LINE_GAP: float = _num("LINE_GAP", 2.5)
static var CHATTER_QUIET: float = _num("CHATTER_QUIET", 15.0)
static var CHATTER_REPEAT: float = _num("CHATTER_REPEAT", 90.0)
static var CHATTER_CHANCE: float = _lim("CHATTER_CHANCE", 0.5)
## Line ids that are chatter (comments on the room), not replies to a trade.
const CHATTER_PREFIXES := ["distract.", "tank.", "lid.", "pick.long", "pick.hover", "player.", "surface.paid", "mantle.paid", "leave.walk", "biome.", "struct."]

static var FIRST_CHAIN: Array[String] = _pool("FIRST_CHAIN", ["first.heard", "first.nobody", "first.hello", "first.tsk"])
static var FLUSH_A: Array[String] = _pool("FLUSH_A", ["flush.a1", "flush.a2", "flush.a3", "flush.a4", "flush.a5"])
static var FLUSH_B: Array[String] = _pool("FLUSH_B", ["flush.b1", "flush.b2", "flush.b3", "flush.b4"])
static var OPEN_TEETH: Array[String] = _pool("OPEN_TEETH", ["open.teeth1", "open.teeth2", "open.teeth3"])
static var APPRAISE: Array[String] = _pool("APPRAISE", ["appraise.1", "appraise.2", "appraise.3", "appraise.4", "appraise.5", "appraise.6"])
static var UNAWARE: Array[String] = _pool("UNAWARE", ["empty.unaware1", "empty.unaware2", "empty.unaware3", "empty.unaware4", "empty.unaware5"])
static var AWARE: Array[String] = _pool("AWARE", ["empty.aware1", "empty.aware2", "empty.aware3"])
static var TAKE: Array[String] = _pool("TAKE", ["pick.take1", "pick.take2", "pick.take3"])
static var OPEN_HAND: Array[String] = _pool("OPEN_HAND", ["open.hand1", "open.hand2", "open.hand3"])
## open.teeth2 ("오늘은 빨리 열었네") only this soon after the flush.
const QUICK_OPEN := 15.0

var is_open: bool = false
var offers: Array[String] = []
## Teeth go on the vent lip one at a time (03-restroom.md 7). When the hand
## stops for APPRAISE_DELAY the being looks at the whole pile; more teeth
## after an offer pull the offer back and it looks again at the total.
const APPRAISE_DELAY := 0.9
## Teeth on the lip not yet looked at.
var pile: int = 0
## Teeth this trade has paid so far (kept, no change); reset when an item is taken.
var trade_paid: int = 0
var _pile_t: float = 0.0
var _pile_prog: FPProgression
## Deepest shell reached (0 core, 1 mantle, 2 surface); main keeps it set.
var shell: int = 0
## The last trade before the outermost shell (spec 12 마지막 거래).
var final_trade: bool = false
## Line ids the being has decided to say, oldest first (this session only).
var spoken: Array[String] = []
## The last line decided; saved, so it survives Continue.
var last_line: String = ""
## Line ids actually voiced (line_spoken), oldest first.
var voiced: Array[String] = []
## Tests of the line logic voice every decided line at once.
var instant_voice := false
var _pending: Array = [] # [id, clock to voice at]
var _voiced_t: float = -INF
var _chatter_t: Dictionary = {} # chatter id -> clock it was last voiced
## Eyes gone: after a spray or heavy toggling.
var absent_left: float = 0.0

var _since_flush: float = INF
var _since_paid: float = INF
var _offer_root: Node3D
var art: Node3D

var _met: bool = false
var _first_flush_heard: bool = false
var _chain: Array[String] = []
var _chain_step: int = 0
var _nag_t: float = 0.0
## Calling lines voiced through the shut grate since the flush (an open
## grate hears the flush line, which is not being ignored).
var _nagged: int = 0
var _chain_first: bool = false
var _open_times: Array[float] = []
var _clock: float = 0.0
var _empty_streak: int = 0
var _little_streak: int = 0
var _idle_t: float = 0.0
var _idle_said: bool = false
var _lid_open: bool = false
var _lid_t: float = 0.0
var _stare_said: bool = false
var _tank_visits: int = 0
var _tank_near: bool = false
var _offer_t: float = 0.0
var _pick_long_said: bool = false
## Offers left behind unpicked: shown again on the next open.
var _held: Array[String] = []
var _left_at: float = -1.0
var _silent_back: bool = false
var _remark_t: float = -INF
var _paid_ever: bool = false
var _hover_said: bool = false
var _walk_said: bool = false
## Tumor kinds drawn so far, oldest first.
var drawings: Array[String] = []
var _rng: int = 7331
## Player state for the occasional remarks (main keeps it fresh).
var player_state: Dictionary = {}

## Game item id -> the art model's item kind.
const ART_KIND := {
    "spray_cheap": "spray_cheap", "spray_deep": "spray_expensive", "barrier": "barrier",
    "knife": "knife", "blender": "blender_box", "big_saw": "saw_box",
    "canary_feed": "canary_feed", "tumor_bag": "tumor_bag", "pouch": "pouch",
}

func _ready() -> void:
    art = (load("res://main/art/fp_vent.tscn") as PackedScene).instantiate()
    art.name = "VentArt"
    add_child(art)
    # Vent art hangs on the restroom ceiling's door-toilet line (main.gd places
    # FPVent at FPRestroom.VENT_CENTER) but is not a child of FPRestroom, so
    # restroom.gd's room-layer pass never reaches it and it stays on the
    # default render layer, catching rest-container lamp light that is meant
    # to stay out of the room (green corner seam near the vent, 형님 2026-09-30).
    FPRestroom.tag_room_layer(art)
    art.call("set_open", 0.0)
    art.call("set_eyes", false)
    _offer_root = Node3D.new()
    _offer_root.name = "Offers"
    add_child(_offer_root)

func _rand(n: int) -> int:
    _rng = (_rng * 1103515245 + 12345) & 0x7fffffff
    return (_rng >> 8) % maxi(n, 1)

func _say(id: String) -> void:
    spoken.append(id)
    last_line = id
    if instant_voice:
        _voice(id)
        return
    if is_chatter(id):
        # chatter never queues behind anything and never interrupts
        var steer := is_steering(id) and not _chatter_t.has(id)
        if not _pending.is_empty() or _clock - _voiced_t < (STEER_QUIET if steer else CHATTER_QUIET):
            return
        if _clock - float(_chatter_t.get(id, -INF)) < CHATTER_REPEAT:
            return
        if not steer and _rand(1000) >= int(CHATTER_CHANCE * 1000.0):
            return
        _chatter_t[id] = _clock
    else:
        # a reply drops chatter still waiting to be voiced
        _pending = _pending.filter(func(p): return not is_chatter(String(p[0])))
        if _pending.size() >= 2:
            _pending.pop_front()
    var at := _clock + lerpf(VOICE_DELAY_MIN, VOICE_DELAY_MAX, float(_rand(1000)) / 1000.0)
    at = maxf(at, _voiced_t + LINE_GAP)
    if not _pending.is_empty():
        at = maxf(at, float(_pending[_pending.size() - 1][1]) + LINE_GAP)
    _pending.append([id, at])

## Chatter that steers the player back to the teeth (sink, mirror, door,
## sitting, standing idle): the first time each is said it skips the chance
## and only needs a short quiet (2026-11-02 play: wandering got no word).
static var STEER_QUIET: float = _num("STEER_QUIET", 5.0)
static func is_steering(id: String) -> bool:
    return id.begins_with("distract.")

static func is_chatter(id: String) -> bool:
    for p in CHATTER_PREFIXES:
        if id.begins_with(p):
            return true
    return false

func _voice(id: String) -> void:
    voiced.append(id)
    _voiced_t = _clock
    line_spoken.emit(id)

## Lines decided but not voiced yet.
func pending_lines() -> Array[String]:
    var out: Array[String] = []
    for p in _pending:
        out.append(String(p[0]))
    return out

## The line for an event from the 사건 table (random one if several).
func _ev(key: String, fallback: String) -> String:
    var e = _rule_data().get("사건", {}).get(key, {})
    var ids := _pool_raw(e, "대사", [fallback])
    return fallback if ids.is_empty() else ids[_rand(ids.size())] if ids.size() > 1 else ids[0]

## A random line of a pool, never the one this pool gave last time.
var _last_pick: Dictionary = {}
func _pick(arr: Array[String]) -> String:
    var key := arr[0] if not arr.is_empty() else ""
    var id := arr[_rand(arr.size())]
    if arr.size() > 1 and id == _last_pick.get(key, ""):
        id = arr[(arr.find(id) + 1 + _rand(arr.size() - 1)) % arr.size()]
    _last_pick[key] = id
    return id

# --- time --------------------------------------------------------------------

func tick(delta: float) -> void:
    _clock += delta
    while not _pending.is_empty() and float(_pending[0][1]) <= _clock:
        _voice(String(_pending.pop_front()[0]))
    _since_flush += delta
    _since_paid += delta
    if absent_left > 0.0:
        absent_left = maxf(absent_left - delta, 0.0)
        if is_open and art != null:
            art.call("set_eyes", absent_left <= 0.0)
    var md := mood()
    if art != null:
        art.call("set_eye_mood", 1.0 if md == "frantic" else (0.0 if md == "calm" else 0.5))
    # ignored after a flush: escalate while closed
    if not is_open and _chain_step < _chain.size():
        _nag_t += delta
        if _nag_t >= NAG_INTERVAL:
            _nag_t = 0.0
            _say(_chain[_chain_step])
            _chain_step += 1
            _nagged += 1
    if is_open and pile > 0:
        _pile_t += delta
        if _pile_t >= APPRAISE_DELAY:
            appraise()
    if is_open:
        _idle_t += delta
        if _idle_t >= IDLE_TIME and not _idle_said and _wants_teeth():
            _idle_said = true
            _say(_ev("열고_가만히", "distract.idle"))
        if _lid_open and not _stare_said:
            _lid_t += delta
            if _lid_t >= STARE_TIME:
                _stare_said = true
                _say(_ev("물통_쳐다만", "lid.stare"))
        if not offers.is_empty():
            _offer_t += delta
            if _offer_t >= PICK_LONG_TIME and not _pick_long_said:
                _pick_long_said = true
                _say(_ev("고르기_오래", "pick.long"))

## "frantic" right after a flush, "calm" after being paid, else "demanding".
func mood() -> String:
    if _since_paid < CALM_TIME:
        return "calm"
    if _since_flush < FRANTIC_TIME:
        return "frantic"
    return "demanding"

func _wants_teeth() -> bool:
    return _since_paid >= CALM_TIME and offers.is_empty()

# --- flush and opening --------------------------------------------------------

func on_flush() -> void:
    # Opening the grate and hearing the first flush are distinct first events.
    # Repeated flushing must not restart the introduction while it is playing.
    if _first_flush_heard and _chain_first and not is_open and _chain_step < _chain.size():
        return
    _since_flush = 0.0
    _nag_t = 0.0
    _nagged = 0
    _chain_step = 0
    _chain_first = not _met and not _first_flush_heard
    if final_trade:
        _chain = []
    elif _chain_first:
        _first_flush_heard = true
        _chain = FIRST_CHAIN.duplicate()
    elif shell >= 2:
        _chain = [_ev("겉껍질_물내림", "surface.flush")] as Array[String]
    elif shell == 1:
        _chain = [_ev("맨틀_물내림", "mantle.flush")] as Array[String]
    else:
        _chain = (FLUSH_A if _rand(2) == 0 else FLUSH_B).duplicate()
    if is_open:
        _say(_chain[0] if not _chain.is_empty() else _ev("부르기_기본", "flush.a1"))
        _chain_step = _chain.size()
    else:
        # the first line comes at once through the ceiling
        if not _chain.is_empty():
            _say(_chain[0])
            _chain_step = 1

## Open the grate. `teeth_available` = teeth in the tank or in hand;
## `in_hand` of them already in the hand; `lid_off` = the tank stands open.
func open(teeth_available: int = 0, in_hand: int = 0, lid_off: bool = false) -> void:
    if is_open:
        return
    is_open = true
    if art != null:
        art.call("play_open")
        art.call("set_eyes", absent_left <= 0.0)
    _idle_t = 0.0
    _idle_said = false
    _open_times.append(_clock)
    while not _open_times.is_empty() and _clock - _open_times[0] > TOGGLE_WINDOW * TOGGLE_MEMORY:
        _open_times.pop_front()
    var toggles := 0
    for i in range(_open_times.size() - 1, -1, -1):
        if i == _open_times.size() - 1 or _open_times[i + 1] - _open_times[i] <= TOGGLE_WINDOW:
            toggles += 1
        else:
            break
    if toggles >= TOGGLE_START:
        if toggles >= TOGGLE_HIDE_COUNT:
            _say(_ev("여닫기_5", "toggle.5"))
            absent_left = TOGGLE_HIDE
            if art != null:
                art.call("set_eyes", false)
        else:
            _say(_ev("여닫기_%d" % toggles, "toggle.%d" % toggles))
        _chain_step = _chain.size()
        if not _held.is_empty() and absent_left <= 0.0 and in_hand <= 0:
            _set_offers(_held)
            _held = []
        return
    if absent_left > 0.0:
        return
    if final_trade:
        _say(_ev("마지막_열기", "final.before"))
        _chain_step = _chain.size()
        return
    if not _held.is_empty():
        var away := _clock - _left_at if _left_at >= 0.0 else 0.0
        if _left_at >= 0.0 and away >= LONG_AWAY:
            _silent_back = true # silently pushes the items out; "골라" when near
        elif _left_at >= 0.0:
            _say(_ev("잠깐_갔다옴", "leave.back"))
        _left_at = -1.0
        # teeth in the hand come first (user 2026-11-09 "이빨을 넣기도 전에
        # 화면이 보상 받을 때 화면"): the held offer stays up the duct until
        # they are on the lip (the being then looks at the whole) or the
        # hand is empty (bring_out_held)
        if in_hand <= 0:
            _set_offers(_held)
            _held = []
        _chain_step = _chain.size()
        return
    if not _met:
        _met = true
        # "open the tank" only when the teeth are still shut in it
        if in_hand > 0:
            _say(_ev("첫_열기_손에", "first.open_hand"))
        elif lid_off:
            _say(_ev("첫_열기_뚜껑", "first.open_lid"))
        else:
            _say(_ev("첫_열기", "first.open") if _chain_step <= 1 else _ev("첫_열기_늦게", "first.open_late"))
        _chain_step = _chain.size()
        return
    # every calling line went unanswered through the shut grate
    var ignored_all := _chain.size() > 1 and _nagged >= _chain.size() - 1
    _chain = []
    _chain_step = 0
    if teeth_available <= 0:
        _empty_open()
        return
    _empty_streak = 0
    if ignored_all and _since_flush < IGNORED_LATE:
        _say(_ev("무시후_열기", "flush.a_late"))
    elif _since_flush < OPEN_EARLY:
        _say(_ev("바로_열기", "open.early"))
    elif in_hand > 0:
        _say(_pick(OPEN_HAND))
    else:
        var pool := OPEN_TEETH.duplicate()
        if _since_flush >= QUICK_OPEN and pool.size() > 1:
            pool.erase("open.teeth2")
        _say(_pick(pool))

func _empty_open() -> void:
    _empty_streak += 1
    if _empty_streak == EMPTY_AGAIN:
        _say(_ev("빈손_2번", "empty.again"))
    elif _empty_streak >= EMPTY_THIRD:
        _say(_ev("빈손_3번", "empty.third"))
    elif shell >= 2:
        _say(_ev("겉껍질_빈손", "surface.hum"))
    elif _rand(2) == 0:
        _say(_pick(UNAWARE))
    else:
        _say(_pick(AWARE))

# --- vomit left in the bowl ---------------------------------------------------

## Seconds of vomit waiting in the bowl (player in the room) before each
## "flush it" line (guide.flush.*, main/data/vent_guide_lines.json). Only
## once the being has heard a flush: before that it does not know anyone is
## there, and the first flush is what startles it (first.heard). The first
## lever is shown on screen instead (main: FPOnboarding lever hint).
const BOWL_NAG_AT := [3.0, 11.0]
var _bowl_t: float = 0.0
var _bowl_step: int = 0

func watch_bowl(delta: float, waiting: bool) -> void:
    if not waiting or not (_first_flush_heard or _met):
        _bowl_t = 0.0
        _bowl_step = 0
        return
    _bowl_t += delta
    if _bowl_step >= BOWL_NAG_AT.size() or _bowl_t < float(BOWL_NAG_AT[_bowl_step]):
        return
    _bowl_step += 1
    if absent_left > 0.0 or final_trade:
        return
    if _bowl_step == 1:
        _say("guide.flush.met.%d" % (1 + _rand(2)))
    else:
        _say("guide.flush.met.3")

## Conversation milestones survive Continue; transient offers do not become payments.
## The offer left unpicked (held, or still held out when the game was saved)
## comes back on the next open after a load, as it would without one
## (spec 03-restroom §7: 다음에 같은 물건을 다시 내민다).
func serialize_progress() -> Dictionary:
    var keep: Array[String] = offers if is_open and not offers.is_empty() else _held
    return {"met": _met, "first_flush_heard": _first_flush_heard, "paid_ever": _paid_ever, "trade_paid": trade_paid + pile, "held": keep.duplicate(), "last_line": last_line}

func restore_progress(data: Dictionary, has_trade_belt: bool) -> void:
    _met = bool(data.get("met", has_trade_belt))
    _paid_ever = bool(data.get("paid_ever", has_trade_belt))
    _first_flush_heard = bool(data.get("first_flush_heard", _met or _paid_ever))
    trade_paid = int(data.get("trade_paid", 0))
    # older saves have neither: no held offer, nothing said yet
    _held = []
    for id in data.get("held", []):
        if id is String and (FPProgression.PRICE_UNITS.has(id) or id == "junk"):
            _held.append(id)
    _left_at = -1.0
    last_line = str(data.get("last_line", ""))
    pile = 0
    _chain.clear()
    _chain_step = 0
    _chain_first = false

func close() -> void:
    if is_open and pile > 0:
        appraise() # teeth on the lip are paid even if the grate shuts
    var was_open := is_open
    is_open = false
    # chatter about the open grate no longer applies once it is shut
    _pending = _pending.filter(func(p): return not is_chatter(String(p[0])))
    if was_open and not offers.is_empty():
        _say(_ev("물건두고_닫기", "leave.close"))
        _held = offers.duplicate()
    elif was_open and final_trade:
        _say(_ev("마지막_닫기", "final.close"))
    _clear_offers()
    _lid_t = 0.0
    if art != null:
        art.call("set_offer_items", [])
        art.call("set_eyes", false)
        if was_open and is_inside_tree():
            create_tween().tween_method(func(v): art.call("set_open", v), 1.0, 0.0, 0.35)
        else:
            art.call("set_open", 0.0)

# --- trade --------------------------------------------------------------------

## One tooth onto the lip. Returns false when the grate is shut.
func add_tooth(prog: FPProgression) -> bool:
    if not is_open:
        return false
    if pile == 0 and not offers.is_empty():
        # more teeth on top of an offer: it pulls the offer back to look again
        if art != null:
            art.call("set_offer_items", [])
        _clear_offers()
    # an offer held back for the teeth in the hand: it looks again at the total
    _held = []
    pile += 1
    _pile_t = 0.0
    _pile_prog = prog
    _idle_t = 0.0
    if art != null and art.has_method("set_pile"):
        art.call("set_pile", pile)
    return true

## The being looks at everything paid this trade (earlier teeth plus the
## new pile) and pushes out an offer.
func appraise(prog: FPProgression = null) -> Array[String]:
    if prog == null:
        prog = _pile_prog
    if pile <= 0 or prog == null:
        return []
    trade_paid += pile
    pile = 0
    _pile_t = 0.0
    if art != null and art.has_method("set_pile"):
        art.call("set_pile", 0)
    return place_teeth(trade_paid, prog)

## Player places `placed` teeth. The being keeps them (no change) and
## returns what it pushes out. [] only when closed or nothing was placed.
func place_teeth(placed: int, prog: FPProgression) -> Array[String]:
    if not is_open or placed <= 0:
        return []
    _idle_t = 0.0
    _since_paid = 0.0
    var first_pay := not _paid_ever
    _paid_ever = true
    # the first trade hands over the work belt (tool hooks from now on)
    prog.has_belt = true
    if final_trade:
        _say(_ev("마지막_이빨", "final.given"))
        var all: Array[String] = []
        for id in FPProgression.PRICE_UNITS.keys():
            if prog.vent.is_unlocked(id, float(prog.deepest_shell)) and not prog._maxed(id):
                all.append(id)
        _set_offers(all)
        offer_after_pay = true
        return all
    if placed >= prog.vent_absurd_threshold():
        _say(_ev("터무니없이", "amount.absurd"))
        var sp := prog.vent_spill()
        for id in sp:
            prog.grant_item(id)
        _show_spill(sp)
        spilled.emit(sp)
    else:
        _say(_ev("첫_이빨", "place.accept") if first_pay else _pick(APPRAISE))
    var ids := prog.vent_offer(placed)
    if placed < prog.vent_absurd_threshold():
        if ids == ["junk"]:
            _little_streak += 1
            _say(_ev("적게_연속", "amount.little2") if _little_streak >= LITTLE_STREAK else _ev("적게", "amount.little"))
        else:
            _little_streak = 0
            var top := prog.price_for(ids[0])
            _say(_ev("많이", "amount.lots") if float(placed) >= float(top) * LOTS_MULT else _ev("적당히", "amount.fair"))
        _maybe_remark()
    _set_offers(ids)
    offer_after_pay = true
    return ids

## The granted spill tumbles out of the duct onto the floor and is then
## swept to the player's waist (art play_spill).
func _show_spill(ids: Array[String]) -> void:
    if art == null or ids.is_empty() or not art.has_method("play_spill"):
        return
    var kinds: Array = []
    for id in ids:
        kinds.append(ART_KIND.get(id, "junk"))
    # the room floor (y = 0) in the vent's frame; main puts the vent just
    # under the ceiling at FPRestroom.VENT_CENTER
    var drop := position.y if position.y > 0.5 else FPRestroom.VENT_CENTER.y - 0.03
    art.call("play_spill", kinds, -drop)

## Take one offered item; the others are pulled back.
func take(id: String, prog: FPProgression) -> bool:
    if id not in offers:
        return false
    var ok := prog.grant_item(id)
    if not ok:
        # already full (max barriers, sprays ...): it stays on the lip, paid teeth stay credited
        _say(_ev("적게", "amount.little"))
        return false
    trade_paid = 0
    _say(_pick(TAKE))
    if offers.size() > 1:
        _say(_ev("나머지_회수", "pick.withdraw"))
    if art != null:
        art.call("take_item", offers.find(id))
    _held = []
    _clear_offers()
    return ok

## Put something that is not teeth on the vent: flesh, tumor, canary.
func place_weird(kind: String) -> void:
    if not is_open:
        return
    match kind:
        "flesh": _say(_ev("살점_올림", "weird.flesh"))
        "tumor": _say(_ev("종양_올림", "weird.tumor"))
        "canary": _say(_ev("카나리아_올림", "weird.canary"))

## The occasional remark on how the player looks, after being paid.
func _maybe_remark() -> void:
    if _clock - _remark_t < REMARK_COOLDOWN:
        return
    var st := player_state
    var id := ""
    if bool(st.get("died", false)):
        id = _ev("혼잣말_죽었다옴", "player.died")
    elif float(st.get("away", 0.0)) >= LONG_AWAY * LONG_ABSENT_MULT:
        id = _ev("혼잣말_오래안옴", "player.long_absent")
    elif bool(st.get("extra_arm", false)):
        id = _ev("혼잣말_팔더", "player.extra_arm")
    elif bool(st.get("mutated", false)):
        id = _ev("혼잣말_변이", "player.mutated")
    elif st.has("new_biome") or st.has("new_struct"):
        # where the player has been for the first time (FPBiomeLife):
        # biome.<id>.1..3 / struct.<kind>.1..2 in vent_biome_lines.json
        id = _place_line(String(st.get("new_struct", "")), String(st.get("new_biome", "")))
        player_state.erase("new_biome")
        player_state.erase("new_struct")
    elif float(st.get("blood", 0.0)) >= BLOOD_REMARK:
        id = _ev("혼잣말_피", "player.blood")
    elif int(st.get("hairs", 0)) >= HAIRS_REMARK:
        id = _ev("혼잣말_털", "player.hairs")
    elif shell >= 2:
        id = _ev("혼잣말_겉껍질", "surface.paid")
    elif shell == 1:
        id = _ev("혼잣말_맨틀", "mantle.paid")
    if id != "":
        _remark_t = _clock
        player_state.erase("died")
        player_state.erase("mutated")
        _say(id)

## A remark on a structure (preferred) or biome the player just found; ""
## when the line data has no text for it yet.
func _place_line(kind: String, biome_id: String) -> String:
    for pick in [["struct.%s.%d", kind, 2], ["biome.%s.%d", biome_id, 3]]:
        if String(pick[1]) == "":
            continue
        var ids: Array[String] = []
        for n in range(1, int(pick[2]) + 1):
            var id := String(pick[0]) % [pick[1], n]
            if FPSubtitles.line_text(id) != "":
                ids.append(id)
        if not ids.is_empty():
            return _pick(ids)
    return ""

# --- player actions main reports ----------------------------------------------

## Main reports what the player does in the room. Events:
## near_sink, wash, mirror, sit, door, tank_near, tank_far, lid_open,
## lid_close, grab, walk_with, put_back, walk_away, left_room, returned,
## near_vent, spray, hand_in.
func notice(event: String) -> void:
    # standing about (near or far from things, under the grate) is not doing
    # something; it must not keep resetting the idle clock every frame
    if event not in ["tank_far", "tank_near", "near_vent"]:
        _idle_t = 0.0
    match event:
        "spray":
            if is_open:
                _say(_ev("스프레이_맞음", "weird.spray"))
                absent_left = SPRAY_SULK
                if art != null:
                    art.call("set_eyes", false)
            return
        "hand_in":
            if is_open:
                _say(_ev("손_넣음", "weird.hand"))
            return
        "left_room":
            if is_open and not offers.is_empty():
                _say(_ev("물건두고_나감", "leave.out"))
                _held = offers.duplicate()
                _left_at = _clock
            return
        "returned":
            if is_open and _left_at >= 0.0:
                if _clock - _left_at >= LONG_AWAY:
                    _silent_back = true # says nothing, only holds the items out
                else:
                    _say(_ev("잠깐_갔다옴", "leave.back"))
                _left_at = -1.0
                _held = []
            return
        "near_vent":
            if _silent_back and is_open and not offers.is_empty():
                _silent_back = false
                _say(_ev("오래뒤_다가옴", "leave.back_long_near"))
            return
    if not is_open or absent_left > 0.0:
        return
    if not offers.is_empty():
        if (event == "walk_away" or event == "door") and not _walk_said:
            _walk_said = true
            _say(_ev("물건두고_멀어짐", "leave.walk"))
        elif event == "hover" and not _hover_said:
            _hover_said = true
            _say(_ev("물건_만지작", "pick.hover"))
        return
    if not _wants_teeth():
        return
    match event:
        "near_sink": _say(_ev("딴짓_세면대", "distract.sink"))
        "wash": _say(_ev("딴짓_손씻기", "distract.wash"))
        "mirror": _say(_ev("딴짓_거울", "distract.mirror"))
        "sit": _say(_ev("딴짓_앉기", "distract.sit"))
        "door": _say(_ev("딴짓_문", "distract.door"))
        "tank_near":
            if _tank_near:
                return
            _tank_near = true
            _say(_ev("물통_다가감", "tank.approach") if _tank_visits == 0 else _ev("물통_또다가감", "tank.approach_again"))
        "tank_far":
            if not _tank_near:
                return
            _tank_near = false
            _say(_ev("물통_멀어짐", "tank.leave") if _tank_visits == 0 else _ev("물통_또멀어짐", "tank.leave_again"))
            _tank_visits += 1
        "lid_open":
            _lid_open = true
            _lid_t = 0.0
            _stare_said = false
            _say(_ev("물통_뚜껑열기", "lid.open"))
        "lid_close":
            _lid_open = false
        "grab":
            _stare_said = true
            _say(_ev("이빨_집기", "lid.grab"))
        "walk_with": _say(_ev("이빨_들고감", "lid.walk_with"))
        "put_back": _say(_ev("이빨_도로넣기", "lid.put_back"))

## The lever settled whole tumors: the being draws each one in crayon and
## sends the paper down (works with the grate shut, it slides through).
func on_tumors_settled(kinds: Array) -> void:
    for k in kinds:
        if drawings.has(String(k)):
            continue # one crayon drawing per kind; the teeth still came
        var first := drawings.is_empty()
        drawings.append(String(k))
        _say(_ev("그림_처음", "drawing.drop") if first else _ev("그림_또", "drawing.again"))
        drawing_dropped.emit(String(k))

## A distance from the 거리 table of vent_rules.json.
static func dist(key: String, fallback: float) -> float:
    var t = _rule_data().get("거리", {}).get(key, {})
    return float(t.get("값", fallback)) if t is Dictionary else fallback

## Where drawing number `i` hangs on the wall (그림종이 in vent_rules.json).
static func drawing_spot(i: int) -> Vector3:
    var p = _rule_data().get("그림종이", {})
    if not p is Dictionary:
        p = {}
    var per := maxi(int(p.get("한줄_장수", 7)), 1)
    return Vector3(FPRestroom.HALF.x - 0.025, float(p.get("y", 1.55)) - float(p.get("줄_간격", 0.34)) * (i / per), float(p.get("z_시작", -1.0)) + float(p.get("간격", 0.27)) * (i % per))

func _set_offers(ids: Array[String]) -> void:
    _clear_offers()
    offers = ids.duplicate()
    _offer_t = 0.0
    _pick_long_said = false
    _hover_said = false
    _walk_said = false
    for i in range(offers.size()):
        var b := MeshInstance3D.new()
        var bm := BoxMesh.new()
        bm.size = Vector3(0.07, 0.05, 0.07)
        b.mesh = bm
        b.position = Vector3((i - (offers.size() - 1) * 0.5) * 0.1, -0.04, 0.0)
        b.set_meta("offer_id", offers[i])
        b.visible = false # aim anchor only; the art arm holds the real item
        _offer_root.add_child(b)
    var kinds: Array = []
    for id in offers:
        kinds.append(ART_KIND.get(id, "junk"))
    if art != null:
        art.call("set_offer_items", kinds)
        art.call("play_offer")
    offers_changed.emit(offers)

func _clear_offers() -> void:
    offers.clear()
    for c in _offer_root.get_children():
        c.queue_free()
        _offer_root.remove_child(c)
    offers_changed.emit(offers)

## Aim anchors, kept on the items the being's hand holds out (the hand turns
## toward the player, so the items move).
func offer_nodes() -> Array:
    var nodes := _offer_root.get_children()
    if art != null and art.has_method("item_node"):
        for i in range(nodes.size()):
            var item: Node3D = art.call("item_node", i)
            if item != null and item.is_inside_tree() and nodes[i].is_inside_tree():
                (nodes[i] as Node3D).global_position = item.global_position
    return nodes

## Middle of the offer held out (the vent centre when nothing is offered).
func offer_center() -> Vector3:
    var nodes := offer_nodes()
    if nodes.is_empty() or not is_inside_tree():
        return FPRestroom.VENT_CENTER
    var sum := Vector3.ZERO
    for n in nodes:
        sum += (n as Node3D).global_position
    return sum / float(nodes.size())

## Offers waiting for the next open (left unpicked).
func held_offers() -> Array[String]:
    return _held

## The offer held back while the player stood there with teeth in hand
## (open), pushed out now the hand is empty. False when there is none.
func bring_out_held() -> bool:
    if not is_open or _held.is_empty() or not offers.is_empty() or pile > 0 or absent_left > 0.0:
        return false
    _set_offers(_held)
    _held = []
    return true

# --- asking for teeth without a word ------------------------------------------

## The open grate asks for teeth with what it shows, not with words (user
## 2026-11-09 "이빨을 챙겨야 한다는 것에 대한 넛지가 부족함"; the being's
## own word for them, 봉, does not say "teeth"):
##   "beg"  one empty hand comes down and grasps at the air: teeth wait in
##          the tank and the player's hand is empty;
##   "lip"  the near lip glints where teeth go: the player holds teeth and
##          none are on it yet;
##   ""     otherwise (shut, gone, an offer out, teeth on the lip, nothing
##          to bring).
var nudge := ""
## An offer pushed out for teeth just paid (place_teeth): main puts the head
## in under it once the player's hand is empty, then clears this.
var offer_after_pay := false

static func nudge_for(open: bool, away: bool, offering: bool, on_lip: int, held_back: bool, in_tank: int, in_hand: int) -> String:
    if not open or away or offering or on_lip > 0:
        return ""
    if in_hand > 0:
        return "lip"
    if in_tank > 0 and not held_back:
        return "beg"
    return ""

## Main calls this every frame with the teeth in the tank and in the hand.
func update_nudge(in_tank: int, in_hand: int) -> void:
    var k := nudge_for(is_open, absent_left > 0.0, not offers.is_empty(), pile, not _held.is_empty(), in_tank, in_hand)
    if k == nudge:
        return
    nudge = k
    if art != null and art.has_method("set_nudge"):
        art.call("set_nudge", k)

## Whether the player has ever paid teeth (the first trade done).
func paid_ever() -> bool:
    return _paid_ever
