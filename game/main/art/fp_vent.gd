extends Node3D

const K := preload("res://main/art/fp_art_kit.gd")

## Ceiling vent (the shop). Local frame: the vent face lies on y=0 and the
## duct goes UP (+Y), so it is seen from below. Grate hinges down on its -X
## edge. Two pale eyes sit in the dark duct and blink on their own; an arm
## reaches down out of the dark holding the offered item.
## Public: set_open(0..1), play_open(), blink(), set_eyes(visible),
## play_offer(), play_withdraw(), set_offer_items(kinds), take_item(i),
## set_eye_mood(0 calm..1 frantic).

const SIZE := 0.26
var _grate: Node3D
var _eyes: Array = []
var _lids: Array = []
var _offer_root: Node3D
var _offers: Array = []
var _blink_t := 0.0
var _next_blink := 2.2
var _mood := 0.0
var _time := 0.0

func _ready() -> void:
    var metal := K.mat("tex_chrome_128.png", 0.2, false)
    # flange frame, 4 bevelled bars
    var st := K.begin()
    var c := Color(0.78, 0.8, 0.8)
    var ce := Color(0.95, 0.96, 0.96)
    K.rbox(st, K.T(Vector3(0, -0.01, SIZE + 0.03)), Vector3(SIZE + 0.06, 0.015, 0.03), 0.012, c, ce)
    K.rbox(st, K.T(Vector3(0, -0.01, -SIZE - 0.03)), Vector3(SIZE + 0.06, 0.015, 0.03), 0.012, c, ce)
    K.rbox(st, K.T(Vector3(SIZE + 0.03, -0.01, 0)), Vector3(0.03, 0.015, SIZE), 0.012, c, ce)
    K.rbox(st, K.T(Vector3(-SIZE - 0.03, -0.01, 0)), Vector3(0.03, 0.015, SIZE), 0.012, c, ce)
    # screws
    for sx in [-1, 1]:
        for sz in [-1, 1]:
            K.lathe(st, K.T(Vector3(sx * (SIZE + 0.03), -0.028, sz * (SIZE + 0.03)), Vector3(180, 0, 0)), [Vector2(0.0, 0.0), Vector2(0.012, 0.0), Vector2(0.01, 0.006), Vector2(0.0, 0.008)], 6, [Color(0.6, 0.6, 0.62)])
    K.add_mesh(self, "Flange", K.finish(st, 6.0), metal)
    # duct: inward-facing walls going up into black
    st = K.begin()
    var dark := Color(0.12, 0.12, 0.13)
    var black := Color(0.01, 0.01, 0.01)
    var hgt := 0.7
    for i in range(4):
        var t := K.T(Vector3.ZERO, Vector3(0, 90 * i, 0))
        var a := Vector3(-SIZE, 0, -SIZE)
        var b := Vector3(SIZE, 0, -SIZE)
        K.quad(st, t, a, b, b + Vector3(0, 0.25, 0), a + Vector3(0, 0.25, 0), Vector3(0, 0, 1), dark)
        K.quad(st, t, a + Vector3(0, 0.25, 0), b + Vector3(0, 0.25, 0), b + Vector3(0, hgt, 0), a + Vector3(0, hgt, 0), Vector3(0, 0, 1), black)
    K.quad(st, Transform3D.IDENTITY, Vector3(-SIZE, hgt, -SIZE), Vector3(SIZE, hgt, -SIZE), Vector3(SIZE, hgt, SIZE), Vector3(-SIZE, hgt, SIZE), Vector3.DOWN, black)
    K.add_mesh(self, "Duct", K.finish(st, 4.0), K.mat("tex_fixture_64.png", 0.1, false))
    # grate on a hinge
    _grate = K.pivot(self, "GrateHinge", Vector3(-SIZE, -0.02, 0))
    st = K.begin()
    var gc := Color(0.86, 0.87, 0.86)
    K.rbox(st, K.T(Vector3(SIZE, 0, SIZE - 0.015)), Vector3(SIZE, 0.012, 0.015), 0.006, gc)
    K.rbox(st, K.T(Vector3(SIZE, 0, -SIZE + 0.015)), Vector3(SIZE, 0.012, 0.015), 0.006, gc)
    K.rbox(st, K.T(Vector3(0.015, 0, 0)), Vector3(0.015, 0.012, SIZE), 0.006, gc)
    K.rbox(st, K.T(Vector3(2 * SIZE - 0.015, 0, 0)), Vector3(0.015, 0.012, SIZE), 0.006, gc)
    for i in range(9):
        var x := 0.05 + i * (2 * SIZE - 0.1) / 8.0
        K.rbox(st, K.T(Vector3(x, 0.005, 0), Vector3(0, 0, 38)), Vector3(0.004, 0.018, SIZE - 0.02), 0.002, Color(0.8, 0.81, 0.8), Color(0.95, 0.95, 0.95))
    K.add_mesh(_grate, "Grate", K.finish(st, 8.0), metal)
    # eyes in the dark
    for sx in [-1, 1]:
        var e := K.pivot(self, "Eye" + ("R" if sx > 0 else "L"), Vector3(sx * 0.07, 0.24, 0.02))
        st = K.begin()
        K.lathe(st, K.T(Vector3.ZERO, Vector3(180, 0, 0)), [Vector2(0, -0.02), Vector2(0.018, -0.014), Vector2(0.024, 0.0), Vector2(0.018, 0.012), Vector2(0.0, 0.016)], 8, [Color(0.95, 0.9, 0.62)])
        K.add_mesh(e, "White", K.finish(st), K.glow(Color(1, 1, 1)))
        st = K.begin()
        K.lathe(st, K.T(Vector3(0, -0.017, 0), Vector3(180, 0, 0)), [Vector2(0, -0.004), Vector2(0.008, -0.002), Vector2(0.0, 0.003)], 6, [Color(0.03, 0.02, 0.01)])
        K.add_mesh(e, "Pupil", K.finish(st), K.glow(Color(1, 1, 1)))
        e.scale = Vector3(2.2, 1.6, 1.1)
        _eyes.append(e)
        _lids.append(e)
    # offered items: the being never shows more than its eyes; it pushes a
    # few items out of the dark onto the duct lip (docs/spec/03-restroom.md: "pushes
    # out a few items ... The player picks one up by hand; the rest are
    # pulled back")
    _offer_root = K.pivot(self, "Offers", Vector3(0, 0.02, 0))
    for i in range(3):
        var slot := K.pivot(_offer_root, "Offer%d" % i, Vector3(-0.12 + i * 0.12, 0.0, 0.0))
        _offers.append(slot)
    set_offer_items(["spray_cheap", "barrier", "junk"])
    set_offer_extend(0.0)

## Item kinds: spray_cheap, spray_expensive, barrier, knife, blender_box,
## saw_box, junk (a crumpled useless thing). Replaces what is on the lip.
func set_offer_items(kinds: Array) -> void:
    for i in range(_offers.size()):
        var slot: Node3D = _offers[i]
        for ch in slot.get_children():
            ch.queue_free()
        slot.visible = i < kinds.size()
        if i < kinds.size():
            K.add_mesh(slot, "Item", _item_mesh(str(kinds[i]), i), K.mat("tex_fixture_64.png", 0.2, false))

func _item_mesh(kind: String, seed: int) -> ArrayMesh:
    var st := K.begin()
    var I := Transform3D.IDENTITY
    match kind:
        "spray_cheap", "spray_expensive":
            var exp := kind == "spray_expensive"
            var body := Color(0.12, 0.1, 0.1) if exp else Color(0.9, 0.88, 0.8)
            var band := Color(0.75, 0.08, 0.06) if exp else Color(0.9, 0.75, 0.1)
            K.lathe(st, K.T(Vector3(0, 0.0, 0), Vector3(0, 0, 90)), [Vector2(0.0, -0.06), Vector2(0.026, -0.06), Vector2(0.026, 0.0), Vector2(0.026, 0.04), Vector2(0.012, 0.055), Vector2(0.0, 0.065)], 8, [body, band, body, Color(0.8, 0.8, 0.8)])
        "barrier":
            K.tube(st, I, [Vector3(-0.07, 0, 0), Vector3(0.07, 0, 0)], [0.028], 6, [Color(0.92, 0.72, 0.1), Color(0.1, 0.1, 0.1)])
            K.lathe(st, K.T(Vector3(0.075, 0, 0), Vector3(0, 0, -90)), [Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.035, 0.012), Vector2(0.0, 0.014)], 6, [Color(0.5, 0.5, 0.5)])
        "knife":
            K.tube(st, I, [Vector3(-0.06, 0, 0), Vector3(0.0, 0, 0)], [0.012], 6, [Color(0.38, 0.22, 0.12)], true)
            K.tube(st, I, [Vector3(0.0, 0, 0), Vector3(0.1, 0.0, 0)], [0.015, 0.001], 3, [Color(0.85, 0.86, 0.88)], true)
        "blender_box", "saw_box":
            K.rbox(st, I, Vector3(0.07, 0.05, 0.06), 0.01, Color(0.68, 0.55, 0.38), Color(0.55, 0.42, 0.28))
            K.tube(st, I, [Vector3(-0.071, 0.051, 0), Vector3(0.071, 0.051, 0)], [0.004], 3, [Color(0.3, 0.1, 0.08)], false)
        _:
            K.blob(st, I, Vector3.ZERO, Vector3(0.035, 0.02, 0.03), 0.5, 60 + seed, Color(0.45, 0.42, 0.36), Color(0.3, 0.28, 0.25))
    return K.finish(st, 6.0)

## Take the item in `index` (the player's hand picks it); the others are
## pulled back into the dark at once.
func take_item(index: int) -> void:
    var tw := create_tween().set_parallel(true)
    for i in range(_offers.size()):
        var slot: Node3D = _offers[i]
        if i == index:
            # the hand closes on it about 0.3 s in; then it is gone from the grate
            tw.tween_callback(func(): slot.visible = false).set_delay(0.3)
        else:
            # the rest are snatched back in the same instant: a quick pop inward
            tw.tween_property(slot, "position:y", 0.45, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN).set_delay(0.32)
func _process(delta: float) -> void:
    _time += delta
    _blink_t -= delta
    if _blink_t <= 0.0 and _time > _next_blink:
        blink()
        _next_blink = _time + lerpf(2.8, 0.7, _mood) + fmod(_time * 7.3, 1.3)
    var lid := clampf(_blink_t / 0.12, 0.0, 1.0)
    var closed := sin(lid * PI)
    for i in range(_eyes.size()):
        var e: Node3D = _eyes[i]
        e.scale.z = lerpf(1.1, 0.06, closed)
        # frantic mood: eyes jitter
        e.position.x = (0.07 if i == 1 else -0.07) + sin(_time * 31.0 + i) * 0.004 * _mood

func set_open(amount: float) -> void:
    _grate.rotation_degrees.z = -100.0 * clampf(amount, 0.0, 1.0)

func play_open() -> void:
    var tw := create_tween()
    tw.tween_method(set_open, 0.0, 1.0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func blink() -> void:
    _blink_t = 0.12

func set_eyes(show: bool) -> void:
    for e in _eyes:
        (e as Node3D).visible = show

func set_eye_mood(frantic: float) -> void:
    _mood = clampf(frantic, 0.0, 1.0)

## 0 = items still up in the dark duct, 1 = pushed out onto the lip where
## the hand can reach them (slid down out of the black, slightly staggered).
func set_offer_extend(t: float) -> void:
    var k := clampf(t, 0.0, 1.0)
    _offer_root.visible = k > 0.001
    for i in range(_offers.size()):
        var slot: Node3D = _offers[i]
        var ki := clampf(k * 1.3 - i * 0.15, 0.0, 1.0)
        slot.position = Vector3(-0.12 + i * 0.12, lerpf(0.45, 0.0, ki), sin(i * 2.1) * 0.03)
        slot.rotation_degrees.y = i * 23.0

func play_offer() -> void:
    var tw := create_tween()
    tw.tween_method(set_offer_extend, 0.0, 1.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func play_withdraw() -> void:
    var tw := create_tween()
    tw.tween_method(set_offer_extend, 1.0, 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func capture_setup() -> Dictionary:
    set_open(1.0)
    set_offer_extend(1.0)
    # capture only: the restroom ceiling tiles around the opening
    var st := K.begin()
    for i in range(4):
        var t := K.T(Vector3.ZERO, Vector3(0, 90 * i, 0))
        K.quad(st, t, Vector3(-1.2, 0, -1.2), Vector3(1.2, 0, -1.2), Vector3(SIZE + 0.06, 0, -SIZE - 0.06), Vector3(-SIZE - 0.06, 0, -SIZE - 0.06), Vector3.DOWN, Color(0.9, 0.9, 0.9))
    K.add_mesh(self, "CaptureCeiling", K.finish(st, 2.0), K.mat("tex_tile_wall_64.png", 0.1, false))
    return {"cam_pos": Vector3(0.42, -0.95, 0.68), "look_at": Vector3(0, 0.05, 0), "env": "restroom", "fov": 60.0}