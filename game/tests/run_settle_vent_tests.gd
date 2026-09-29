extends SceneTree

## W04 toilet settlement, W05 vent trade rules, W06 vent reactions.
## Run: Godot_console.exe --headless --path <project> --script tests/run_settle_vent_tests.gd

var _failures := 0
var _passed := 0
var _m: Node3D
var _frame := 0
var _ids: Dictionary = {}

func _assert(c: bool, msg: String) -> void:
    if c:
        _passed += 1
    else:
        _failures += 1
        print("FAIL: %s" % msg)

func _init() -> void:
    print("=== flesh-pit settlement + vent tests ===")
    var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://main/data/vent_lines.json"))
    for l in j["lines"]:
        _ids[String(l["id"])] = true
    _m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
    get_root().add_child(_m)

func _process(_d: float) -> bool:
    _frame += 1
    if _frame == 2:
        _m.finish_opening()
    if _frame < 6:
        return false
    _settlement()
    _hairs()
    _trade()
    _reactions()
    _m.queue_free()
    print("--- %d passed, %d failed ---" % [_passed, _failures])
    quit(1 if _failures > 0 else 0)
    return true

func _visible_text(n: Node) -> int:
    var c := 0
    if (n is Label or n is Button or n is RichTextLabel) and (n as CanvasItem).is_visible_in_tree():
        var t: String = n.text
        if t.strip_edges() != "":
            c += 1
    for ch in n.get_children():
        c += _visible_text(ch)
    return c

# --- W04 -----------------------------------------------------------------------

func _settlement() -> void:
    var m = _m
    var prog: FPProgression = m.progression
    prog.teeth = 0
    m.player.global_position = m.restroom.toilet.global_position + Vector3(0, 0.9, 0.6)
    m.stomach.add_flesh(100.0)
    prog.on_flesh_eaten(0, 100)
    m.request_vomit()
    _assert(m.is_settling() and prog.teeth == 0, "W04 before the lever: 0 teeth")
    _assert(_visible_text(m) == 0, "W04 the settlement shows no text or numbers")
    m.leave_settlement()
    _assert(not m.is_settling() and prog.teeth == 0 and prog.total_hairs() == 0 and m.toilet.has_contents(), "W04 standing up without the lever settles nothing; the bowl keeps it")
    m.start_settlement()
    var got: Dictionary = m.flush()
    _assert(prog.teeth == 8 and got["teeth"] == 8, "W04 the lever puts teeth in the tank (%d)" % prog.teeth)
    _assert(prog.hairs("core") == 2, "W04 the lever grows hairs (core %d)" % prog.hairs("core"))
    _assert(m.toilet.is_rattling() and m.toilet.last_rattle > 0.0, "W04 the tank rattles after the lever")
    var plain: float = m.toilet.last_rattle
    _assert(FPToiletSettlement.rattle_duration(8, 1) > plain * 2.0, "W04 a whole tumor makes the rattle much longer")
    _assert(FPToiletSettlement.rattle_duration(0, 0) == 0.0, "W04 an empty flush does not rattle")
    m.toilet.tick(10.0)
    _assert(not m.toilet.is_rattling(), "W04 the rattle ends")
    var fk := false
    for e in InputMap.action_get_events("fp_interact"):
        fk = fk or (e is InputEventKey and e.physical_keycode == KEY_F)
    _assert(fk, "keybinds.json gives fp_interact its default key")
    var t0: int = prog.teeth
    var empty: Dictionary = m.pull_lever()
    _assert(not empty.is_empty() and empty["teeth"] == 0 and prog.teeth == t0 and not m.is_settling(), "W04 the lever works standing with an empty bowl")
    m.stomach.add_flesh(100.0)
    m.toilet.vomit_into(m.stomach.vomit())
    _assert(not m.is_settling() and m.pull_lever()["teeth"] > 0, "W04 the lever settles the bowl while standing")

# --- 04-economy hairs ------------------------------------------------------------

func _hairs() -> void:
    for shell in [0, 1, 2]:
        var p := FPProgression.new()
        p.on_flesh_eaten(shell, 100)
        p.settle(0.0)
        var b := FPProgression.biome_for_shell(shell)
        var want: int = [2, 4, 6][shell]
        _assert(p.hairs(b) == want, "hairs: one %s expedition grows %d biome hairs (%d)" % [b, want, p.hairs(b)])
        _assert(p.hairs(FPProgression.COMMON) == [0, 1, 2][shell], "hairs: %s common hair %d" % [b, p.hairs(FPProgression.COMMON)])
    var q := FPProgression.new()
    for i in range(3):
        q.on_flesh_eaten(0, 100)
        q.settle(0.0)
    _assert(q.hairs(FPProgression.COMMON) == 2 and q.hairs("core") == 6, "hairs: fractions carry over (3 core expeditions -> 2 common)")
    var r := FPProgression.new()
    r.on_flesh_eaten(0, 100)
    r.discard_stomach()
    r.settle(0.0)
    _assert(r.total_hairs() == 0, "hairs: vomiting outside loses the pending hairs")
    var s := FPProgression.new()
    s.on_flesh_eaten(0, 30)
    s.settle(0.0)
    var t := FPProgression.new()
    t.deserialize(s.serialize())
    t.on_flesh_eaten(0, 20)
    t.settle(0.0)
    _assert(t.hairs("core") == 1, "hairs: the carried fraction survives a save")

# --- W05 -----------------------------------------------------------------------

func _new_vent() -> FPVent:
    var v := FPVent.new()
    get_root().add_child(v)
    return v

func _trade() -> void:
    var p := FPProgression.new()
    var v := _new_vent()
    # 1. scoop a handful from the tank (lid must be open: main guards it)
    p.teeth = 12
    _assert(p.scoop_handful() == 4 and p.teeth_in_hand == 4, "W05 one handful is 4 teeth")
    # 2. several handfuls stack in the hand: that is the haggling
    p.scoop_handful()
    _assert(p.teeth_in_hand == 8 and p.teeth == 4, "W05 handfuls stack before placing")
    # 3. few teeth -> junk only
    v.open(4)
    var few := v.place_teeth(1, p)
    _assert(few == ["junk"], "W05 too few teeth buy junk only (%s)" % [few])
    _assert(v.take("junk", p) and p.junk_taken == 1, "W05 junk can be taken and does nothing")
    # 4. many teeth -> an expensive item among the offers, at most 3
    p.deepest_shell = 1
    var many := v.place_teeth(40, p)
    _assert(many.size() <= FPProgression.VENT_MAX_OFFER and "blender" in many, "W05 many teeth mix in an expensive item (%s)" % [many])
    var cheap_in := false
    for id in many:
        if id == "junk" or p.price_for(id) < 40:
            cheap_in = true
    _assert(cheap_in, "W05 no change: cheaper things than paid come out too")
    # 5. take one, the rest go back
    _assert(v.take("blender", p) and v.offers.is_empty() and p.owns("blender"), "W05 taking one pulls the rest back")
    # 6. closing without picking keeps the teeth and shows the same offer again
    var o := v.place_teeth(8, p)
    var o_copy := o.duplicate()
    v.close()
    _assert(v.offers.is_empty() and v.held_offers() == o_copy, "W05 closing unpicked keeps the offer for next time")
    v.open(0)
    _assert(v.offers == o_copy, "W05 the same offer comes back on the next open")
    # 7. leaving the room with it open: teeth are not returned, offer held
    v.notice("left_room")
    _assert(v.held_offers() == o_copy and v.last_line == "leave.out", "W05 walking out with it open keeps the offer")
    v.notice("returned")
    v.take(o_copy[0], p)
    v.close()
    # 8. absurd overpay: laugh + early items spill out
    var q := FPProgression.new()
    var w := _new_vent()
    w.open(999)
    q.barriers = 0
    w.place_teeth(q.vent_absurd_threshold(), q)
    _assert("amount.absurd" in w.spoken and q.barriers == 1 and q.owns("knife") and q.canary_feed == 1, "W05 an absurd overpay laughs and spills early items")
    # 9. mood: frantic after a flush, calm after pay
    var x := _new_vent()
    x.on_flush()
    _assert(x.mood() == "frantic", "W05 frantic right after a flush")
    x.tick(FPVent.FRANTIC_TIME + 1.0)
    _assert(x.mood() == "demanding", "W05 frantic wears off")
    x.open(4)
    x.place_teeth(4, q)
    _assert(x.mood() == "calm", "W05 calm after being paid")
    # 10. prices never shown: nothing placed when closed
    x.close()
    _assert(x.place_teeth(4, q).is_empty(), "W05 nothing can be placed on a closed vent")
    # 11. depth unlocks
    var r := FPProgression.new()
    _assert(not ("big_saw" in r.vent_offer(1000)), "W05 the big saw stays locked before the surface")
    for n in [v, w, x]:
        n.queue_free()

# --- W06 -----------------------------------------------------------------------

func _all_known(v: FPVent) -> bool:
    for id in v.spoken:
        if not _ids.has(id):
            print("  unknown line id: " + id)
            return false
    return true

func _reactions() -> void:
    var p := FPProgression.new()
    var used: Dictionary = {}
    var vents: Array = []
    var mk := func() -> FPVent:
        var nv := _new_vent()
        vents.append(nv)
        return nv
    # first meeting: heard, then escalating while ignored
    var v: FPVent = mk.call()
    v.on_flush()
    _assert(v.last_line == "first.heard", "W06 first flush: the being hears it")
    v.tick(FPVent.NAG_INTERVAL + 0.1)
    _assert(v.last_line == "first.nobody", "W06 not opening: 거기 누구 없어요")
    v.tick(FPVent.NAG_INTERVAL + 0.1)
    v.tick(FPVent.NAG_INTERVAL + 0.1)
    _assert(v.last_line == "first.tsk", "W06 ignored to the end: 쯧")
    v.open(8)
    _assert(v.last_line == "first.open_late", "W06 opening late on the first meeting")
    var v2: FPVent = mk.call()
    v2.on_flush()
    v2.open(8)
    _assert(v2.last_line == "first.open", "W06 opening at once on the first meeting")
    # distractions while open and unpaid
    for pair in [["near_sink", "distract.sink"], ["wash", "distract.wash"], ["mirror", "distract.mirror"], ["sit", "distract.sit"], ["door", "distract.door"]]:
        v2.notice(pair[0])
        _assert(v2.last_line == pair[1], "W06 %s -> %s" % pair)
    v2.tick(FPVent.IDLE_TIME + 0.1)
    _assert(v2.last_line == "distract.idle", "W06 doing nothing for long")
    # tank distance teasing
    v2.notice("tank_near")
    _assert(v2.last_line == "tank.approach", "W06 approaching the tank")
    v2.notice("tank_far")
    _assert(v2.last_line == "tank.leave", "W06 walking away from the tank")
    v2.notice("tank_near")
    _assert(v2.last_line == "tank.approach_again", "W06 approaching again")
    v2.notice("tank_far")
    _assert(v2.last_line == "tank.leave_again", "W06 walking away again")
    # lid
    v2.notice("lid_open")
    _assert(v2.last_line == "lid.open", "W06 opening the tank lid")
    v2.tick(FPVent.STARE_TIME + 0.1)
    _assert(v2.last_line == "lid.stare", "W06 only staring into the tank")
    v2.notice("grab")
    _assert(v2.last_line == "lid.grab", "W06 grabbing teeth")
    v2.notice("walk_with")
    _assert(v2.last_line == "lid.walk_with", "W06 walking off with teeth in hand")
    v2.notice("put_back")
    _assert(v2.last_line == "lid.put_back", "W06 putting the teeth back")
    # first payment, then appraisal and amounts
    v2.place_teeth(4, p)
    _assert("place.accept" in v2.spoken, "W06 the first payment line")
    _assert(v2.last_line in ["amount.fair", "amount.lots", "amount.little"], "W06 an amount line follows (%s)" % v2.last_line)
    v2.notice("hover")
    _assert(v2.last_line == "pick.hover", "W06 hovering over offers")
    v2.tick(FPVent.PICK_LONG_TIME + 0.1)
    _assert(v2.last_line == "pick.long", "W06 choosing for too long")
    var took: String = v2.offers[0]
    var several: bool = v2.offers.size() > 1
    v2.take(took, p)
    _assert(v2.spoken[-1] == ("pick.withdraw" if several else v2.spoken[-1]) and (v2.spoken[-2] if several else v2.spoken[-1]) in FPVent.TAKE, "W06 taking: a pick line then the others go back")
    v2.tick(FPVent.CALM_TIME + 1.0)
    v2.place_teeth(4, p)
    _assert(v2.spoken[-2] in FPVent.APPRAISE, "W06 later payments appraise the teeth (%s)" % v2.spoken[-2])
    v2.take(v2.offers[0], p)
    v2.tick(FPVent.CALM_TIME + 1.0)
    v2.place_teeth(1, p)
    _assert(v2.last_line == "amount.little", "W06 too few teeth")
    v2.take("junk", p)
    v2.place_teeth(1, p)
    _assert(v2.last_line == "amount.little2", "W06 too few twice")
    v2.take("junk", p)
    var lots_p := FPProgression.new()
    v2.place_teeth(28, lots_p)
    _assert("amount.lots" in v2.spoken.slice(-3), "W06 many teeth (%s)" % [v2.spoken.slice(-3)])
    # leaving without picking
    v2.close()
    _assert(v2.last_line == "leave.close", "W06 closing without picking")
    v2.open(0)
    v2.notice("walk_away")
    _assert(v2.last_line == "leave.walk", "W06 walking off with it open")
    v2.notice("left_room")
    _assert(v2.last_line == "leave.out", "W06 walking out of the room")
    v2.tick(1.0)
    v2.notice("returned")
    _assert(v2.last_line == "leave.back", "W06 coming back soon")
    v2.notice("left_room")
    v2.tick(FPVent.LONG_AWAY + 1.0)
    var before := v2.spoken.size()
    v2.notice("returned")
    _assert(v2.spoken.size() == before, "W06 coming back much later: silent")
    v2.notice("near_vent")
    _assert(v2.last_line == "leave.back_long_near", "W06 then 골라 when near")
    v2.take(v2.offers[0], p)
    v2.close()
    # later flushes: chain A or B, ignored, then late open
    var v3: FPVent = mk.call()
    v3.on_flush()
    v3.open(4)
    v3.close()
    v3.on_flush()
    _assert(v3.last_line in ["flush.a1", "flush.b1"], "W06 a later flush heard through the ceiling (%s)" % v3.last_line)
    var chain: Array = FPVent.FLUSH_A if v3.last_line == "flush.a1" else FPVent.FLUSH_B
    for i in range(chain.size()):
        v3.tick(FPVent.NAG_INTERVAL + 0.1)
    _assert(v3.last_line == chain[-1], "W06 ignored after a flush: the chain runs to its end")
    v3.open(4)
    _assert(v3.last_line == "flush.a_late", "W06 opening long after: 봉")
    v3.close()
    v3.tick(10.0)
    v3.open(4)
    _assert(v3.last_line in FPVent.OPEN_TEETH, "W06 opening with teeth")
    v3.close()
    v3.tick(10.0)
    v3.on_flush()
    v3.open(4)
    _assert(v3.last_line == "open.early" or v3.last_line.begins_with("toggle"), "W06 opening right after the flush (%s)" % v3.last_line)
    v3.close()
    # empty opens
    var v4: FPVent = mk.call()
    v4.on_flush()
    v4.open(4)
    v4.close()
    v4.tick(30.0)
    v4.open(0)
    _assert(v4.last_line in FPVent.UNAWARE or v4.last_line in FPVent.AWARE, "W06 opening with no teeth")
    v4.close()
    v4.tick(30.0)
    v4.open(0)
    _assert(v4.last_line == "empty.again", "W06 empty twice: 또?")
    v4.close()
    v4.tick(30.0)
    v4.open(0)
    _assert(v4.last_line == "empty.third", "W06 empty three times")
    v4.close()
    # toggling
    v4.tick(60.0)
    v4.open(4)
    v4.close()
    for n in [2, 3, 4]:
        v4.tick(0.5)
        v4.open(4)
        _assert(v4.last_line == "toggle.%d" % n, "W06 toggling %d times" % n)
        v4.close()
    v4.tick(0.5)
    v4.open(4)
    _assert(v4.last_line == "toggle.5" and v4.absent_left > 0.0, "W06 toggling 5 times: the eyes are gone")
    # weird things and the spray
    var v5: FPVent = mk.call()
    v5.on_flush()
    v5.open(4)
    for pair in [["flesh", "weird.flesh"], ["tumor", "weird.tumor"], ["canary", "weird.canary"]]:
        v5.place_weird(pair[0])
        _assert(v5.last_line == pair[1], "W06 putting a %s up" % pair[0])
    v5.notice("hand_in")
    _assert(v5.last_line == "weird.hand", "W06 a hand into the vent")
    v5.notice("spray")
    _assert(v5.last_line == "weird.spray" and v5.absent_left > 0.0, "W06 spraying the being: it hides")
    # remarks on the player after pay
    for pair in [[{"died": true}, "player.died"], [{"away": 9999.0}, "player.long_absent"], [{"extra_arm": true}, "player.extra_arm"], [{"mutated": true}, "player.mutated"], [{"blood": 1.0}, "player.blood"], [{"hairs": 30}, "player.hairs"]]:
        var pv: FPVent = mk.call()
        pv.on_flush()
        pv.open(4)
        pv.tick(1.0)
        pv.player_state = pair[0]
        pv.place_teeth(8, FPProgression.new())
        _assert(pair[1] in pv.spoken, "W06 remark %s" % pair[1])
    # shells
    var sm: FPVent = mk.call()
    sm.on_flush(); sm.open(4); sm.close()
    sm.shell = 1
    sm.on_flush()
    _assert(sm.last_line == "mantle.flush", "W06 mantle flush line")
    sm.open(4)
    sm.place_teeth(8, FPProgression.new())
    _assert("mantle.paid" in sm.spoken, "W06 mantle paid line")
    var ss: FPVent = mk.call()
    ss.on_flush(); ss.open(4); ss.close()
    ss.shell = 2
    ss.on_flush()
    _assert(ss.last_line == "surface.flush", "W06 surface flush line")
    ss.tick(30.0)
    ss.open(0)
    _assert(ss.last_line == "surface.hum", "W06 surface: humming instead of unaware")
    ss.close()
    ss.tick(30.0)
    ss.open(4)
    ss.place_teeth(8, FPProgression.new())
    _assert("surface.paid" in ss.spoken, "W06 surface paid line")
    var sf: FPVent = mk.call()
    sf.on_flush(); sf.open(4); sf.close()
    sf.final_trade = true
    sf.tick(30.0)
    sf.open(4)
    _assert(sf.last_line == "final.before", "W06 final trade: 안 줘도 돼")
    var all := sf.place_teeth(4, FPProgression.new())
    _assert(sf.last_line == "final.given" and all.size() >= 4, "W06 final trade: everything is offered")
    sf.take(all[0], FPProgression.new())
    sf.close()
    _assert(sf.last_line == "final.close", "W06 final trade: 잘 가")
    var va: FPVent = mk.call()
    va.on_flush()
    va.open(99)
    var ap := FPProgression.new()
    va.place_teeth(ap.vent_absurd_threshold(), ap)
    _assert(va.spoken.has("amount.absurd"), "W06 absurd overpay: 큭 켘")
    # every spoken id exists in the line data; every data id is reachable
    for n in vents + [v2]:
        _assert(_all_known(n), "W06 all spoken ids exist in vent_lines.json")
        for id in n.spoken:
            used[id] = true
    var pools: Array = FPVent.FLUSH_A + FPVent.FLUSH_B + FPVent.OPEN_TEETH + FPVent.APPRAISE + FPVent.UNAWARE + FPVent.AWARE + FPVent.TAKE
    var missing: Array = []
    for id in _ids.keys():
        if not used.has(id) and not (id in pools):
            missing.append(id)
    _assert(missing.is_empty(), "W06 every non-random line id is triggered by a test (unreached %s)" % [missing])
    for n in vents:
        n.queue_free()