extends Node3D

const K := preload("res://main/art/fp_art_kit.gd")

## Ceiling vent (the shop). Local frame: the vent face lies on y=0 and the
## duct goes UP (+Y), so it is seen from below. Grate hinges down on its -X
## edge. Two pale eyes sit in the dark duct and blink on their own; a long
## grey arm reaches down out of the dark below the ceiling and turns its open
## palm to whoever is below, the offered items lying in the hook of its fingers.
## Public: set_open(0..1), play_open(), blink(), set_eyes(visible),
## play_offer(), play_withdraw(), set_offer_items(kinds), take_item(i),
## item_node(i), set_eye_mood(0 calm..1 frantic).

const SIZE := 0.26
var _black_cover: MeshInstance3D
var _grate: Node3D
var _eyes: Array = []
var _lids: Array = []
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
            # slotted screw heads
            K.rbox(st, K.T(Vector3(sx * (SIZE + 0.03), -0.037, sz * (SIZE + 0.03)), Vector3(0, 45, 0)), Vector3(0.011, 0.0015, 0.0018), 0.0005, Color(0.2, 0.2, 0.21))
    # inner sleeve covering the seam between flange and duct walls
    K.rbox(st, K.T(Vector3(0, 0.012, SIZE + 0.004)), Vector3(SIZE + 0.008, 0.026, 0.005), 0.003, c, ce)
    K.rbox(st, K.T(Vector3(0, 0.012, -SIZE - 0.004)), Vector3(SIZE + 0.008, 0.026, 0.005), 0.003, c, ce)
    K.rbox(st, K.T(Vector3(SIZE + 0.004, 0.012, 0)), Vector3(0.005, 0.026, SIZE), 0.003, c, ce)
    K.rbox(st, K.T(Vector3(-SIZE - 0.004, 0.012, 0)), Vector3(0.005, 0.026, SIZE), 0.003, c, ce)
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
    # A closed vent reads as a clean black opening behind the grille.
    st = K.begin()
    K.quad(st, Transform3D.IDENTITY, Vector3(-SIZE, 0.01, -SIZE), Vector3(SIZE, 0.01, -SIZE), Vector3(SIZE, 0.01, SIZE), Vector3(-SIZE, 0.01, SIZE), Vector3.DOWN, Color.BLACK)
    _black_cover = K.add_mesh(self, "BlackOpening", K.finish(st), K.glow(Color.BLACK))
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
    # centre brace so the long slats do not read as loose sticks
    K.rbox(st, K.T(Vector3(SIZE, 0.012, 0)), Vector3(SIZE - 0.02, 0.006, 0.01), 0.003, gc)
    # hinge knuckles on the -X edge so the grate visibly hangs from something
    for hz in [-1, 1]:
        K.tube(st, Transform3D.IDENTITY, [Vector3(0, 0, hz * (SIZE - 0.09)), Vector3(0, 0, hz * (SIZE - 0.03))], [0.009, 0.009], 6, [Color(0.7, 0.71, 0.7)], true)
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
    # offered items: besides its eyes the being only ever shows the arm that
    # holds them out (docs/spec/03-restroom.md §7). The items ride in the hook
    # of its fingers; the player picks one up by hand, the rest go back up.
    _build_pile()
    _build_hand()
    for i in range(3):
        var slot := K.pivot(_palm, "Offer%d" % i, HOLD[i])
        _offers.append(slot)
    set_offer_items(["spray_cheap", "barrier", "junk"])
    set_offer_extend(0.0)

## Wrist height (vent frame) with the arm up in the black / held out below
## the ceiling where the room light falls on it, leaning REACH toward the
## camera (still through the opening). The hand is bigger than a person's.
const HAND_UP := 0.62
const HAND_DOWN := -0.3
const REACH := 0.2
const HAND_SCALE := 1.25
## Where each offered item lies on the open hand (palm frame: fingers point
## down -Y, the palm faces +Z). The first sits in the finger hook.
const HOLD := [Vector3(0.0, -0.178, 0.05), Vector3(0.0, -0.122, 0.045), Vector3(0.0, -0.066, 0.042)]
var _arm: Node3D
var _palm: Node3D
var _fingers: Array = []
var _extend := 0.0
var _curl := 0.0
var _hand_tw: Tween
var _snap_face := true
var _yaw := 0.0
var _tilt := 0.0

func _build_hand() -> void:
    _arm = K.pivot(self, "BeingArm", Vector3(0, HAND_UP, 0.02))
    var skin := K.mat("tex_skin_64.png", 0.25, false)
    var pale := Color(0.74, 0.78, 0.7)
    var grime := Color(0.5, 0.52, 0.45)
    var st := K.begin()
    # forearm, wrist at the pivot, running up past the top of the duct
    K.tube(st, Transform3D.IDENTITY, [Vector3(0, 0.0, 0), Vector3(0, 0.06, -0.004), Vector3(0, 0.3, -0.012), Vector3(0.01, 0.62, -0.03), Vector3(0.02, 1.05, -0.04)], [0.02, 0.023, 0.027, 0.025, 0.029], 6, [pale, grime, pale, grime, Color(0.05, 0.05, 0.05)], false, 0.8)
    # the knob of the wrist bone
    K.blob(st, Transform3D.IDENTITY, Vector3(0.012, 0.03, -0.012), Vector3(0.012, 0.014, 0.01), 0.3, 7, pale, grime)
    K.add_mesh(_arm, "Forearm", K.finish(st, 8.0), skin)
    _palm = K.pivot(_arm, "Palm")
    _palm.scale = Vector3.ONE * HAND_SCALE
    st = K.begin()
    K.rbox(st, K.T(Vector3(0, -0.06, 0)), Vector3(0.06, 0.062, 0.013), 0.01, pale, grime)
    # knuckle ridge on the back and a dirty crease across the palm
    K.rbox(st, K.T(Vector3(0, -0.112, -0.008)), Vector3(0.058, 0.01, 0.009), 0.005, grime)
    K.rbox(st, K.T(Vector3(0.004, -0.07, 0.012), Vector3(0, 0, 12)), Vector3(0.045, 0.003, 0.002), 0.001, Color(0.3, 0.24, 0.2))
    K.add_mesh(_palm, "Hand", K.finish(st, 8.0), skin)
    var lens := [0.1, 0.118, 0.112, 0.09]
    for f in range(4):
        var piv := K.pivot(_palm, "Finger%d" % f, Vector3(-0.045 + f * 0.03, -0.118, 0.0))
        _build_finger(piv, lens[f], 0.0085, pale, grime, skin)
        _fingers.append(piv)
    var thumb := K.pivot(_palm, "Thumb", Vector3(0.062, -0.035, 0.006))
    thumb.rotation_degrees = Vector3(0, 0, 34)
    _build_finger(thumb, 0.075, 0.011, pale, grime, skin)
    _fingers.append(thumb)
    _arm.visible = false

## A long three-jointed finger hanging down -Y, its tip hooked toward +Z,
## with a long yellowed nail.
func _build_finger(piv: Node3D, length: float, r: float, pale: Color, grime: Color, skin: Material) -> void:
    var st := K.begin()
    var pts := [Vector3(0, 0.004, 0), Vector3(0, -length * 0.4, 0.004), Vector3(0, -length * 0.72, 0.016), Vector3(0, -length * 0.95, 0.04)]
    K.tube(st, Transform3D.IDENTITY, pts, [r, r * 0.95, r * 0.85, r * 0.7], 5, [pale, grime, pale, grime], true)
    # knuckle bumps
    K.blob(st, Transform3D.IDENTITY, pts[1], Vector3.ONE * r * 1.15, 0.2, 3, grime, pale)
    K.blob(st, Transform3D.IDENTITY, pts[2], Vector3.ONE * r * 1.05, 0.2, 4, grime, pale)
    var tip: Vector3 = pts[3]
    K.tube(st, Transform3D.IDENTITY, [tip + Vector3(0, 0.004, 0.002), tip + Vector3(0, -0.006, 0.014), tip + Vector3(0, -0.009, 0.026)], [r * 0.75, r * 0.55, r * 0.15], 4, [Color(0.6, 0.55, 0.32), Color(0.5, 0.43, 0.22), Color(0.3, 0.24, 0.12)], true, 0.6)
    K.add_mesh(piv, "Bone", K.finish(st, 10.0), skin)

func item_node(index: int) -> Node3D:
    return _offers[index] if index >= 0 and index < _offers.size() else null

## Item kinds: spray_cheap, spray_expensive, barrier, knife, blender_box,
## saw_box, junk (a crumpled useless thing). Replaces what is on the lip.
## An empty list sends the arm back up.
func set_offer_items(kinds: Array) -> void:
    for i in range(_offers.size()):
        var slot: Node3D = _offers[i]
        for ch in slot.get_children():
            slot.remove_child(ch)
            ch.queue_free()
        slot.visible = i < kinds.size()
        if i < kinds.size():
            var mi := K.add_mesh(slot, "Item", _item_mesh(str(kinds[i]), i), K.mat("tex_fixture_64.png", 0.2, false))
            # the same render layers as the rest of the vent (the restroom tags them)
            mi.layers = _black_cover.layers
    if kinds.is_empty():
        if _extend > 0.0 and is_inside_tree():
            _hand_to(0.0, 0.25, Tween.EASE_IN)
        else:
            set_offer_extend(0.0)
    else:
        _set_curl(0.0)
        if _arm != null:
            var lit := _black_cover.layers
            for n in _arm.find_children("*", "VisualInstance3D", true, false):
                (n as VisualInstance3D).layers = lit

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
        "canary_feed":
            # a small paper bag of seed, folded at the top
            K.rbox(st, I, Vector3(0.035, 0.05, 0.025), 0.006, Color(0.82, 0.74, 0.55), Color(0.7, 0.6, 0.42))
            K.rbox(st, K.T(Vector3(0, 0.055, 0)), Vector3(0.036, 0.008, 0.012), 0.003, Color(0.75, 0.66, 0.46))
        "tumor_bag":
            # a deflated basketball-like sack with a drawstring
            K.blob(st, I, Vector3.ZERO, Vector3(0.06, 0.045, 0.06), 0.25, 31, Color(0.62, 0.32, 0.18), Color(0.45, 0.22, 0.12))
            K.tube(st, I, [Vector3(-0.03, 0.045, 0), Vector3(0, 0.07, 0), Vector3(0.03, 0.045, 0)], [0.004], 3, [Color(0.2, 0.15, 0.1)], false)
        "blender_box", "saw_box":
            K.rbox(st, I, Vector3(0.07, 0.05, 0.06), 0.01, Color(0.68, 0.55, 0.38), Color(0.55, 0.42, 0.28))
            K.tube(st, I, [Vector3(-0.071, 0.051, 0), Vector3(0.071, 0.051, 0)], [0.004], 3, [Color(0.3, 0.1, 0.08)], false)
        _:
            K.blob(st, I, Vector3.ZERO, Vector3(0.035, 0.02, 0.03), 0.5, 60 + seed, Color(0.45, 0.42, 0.36), Color(0.3, 0.28, 0.25))
    return K.finish(st, 6.0)

## Take the item in `index` (the player's hand picks it); the others are
## pulled back into the dark at once.
func take_item(index: int) -> void:
    if _hand_tw != null:
        _hand_tw.kill()
    _hand_tw = create_tween()
    var slot: Node3D = item_node(index)
    # the player's hand closes on it about 0.3 s in; then it is gone from the palm
    _hand_tw.tween_interval(0.3)
    if slot != null:
        _hand_tw.tween_callback(func(): slot.visible = false)
    # the fingers close on what is left and the arm snatches it back up
    _hand_tw.tween_method(_set_curl, 0.0, 1.0, 0.16)
    _hand_tw.tween_method(set_offer_extend, _extend, 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

func _set_curl(c: float) -> void:
    _curl = clampf(c, 0.0, 1.0)
    for i in range(_fingers.size()):
        var f: Node3D = _fingers[i]
        f.rotation.x = -_curl * (1.2 if i < 4 else 0.7)

func _hand_to(target: float, secs: float, ease_type: Tween.EaseType) -> void:
    if _hand_tw != null:
        _hand_tw.kill()
    _hand_tw = create_tween()
    _hand_tw.tween_method(set_offer_extend, _extend, target, secs).set_trans(Tween.TRANS_SINE).set_ease(ease_type)

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
    _face_hand(delta)

## The held-out arm slowly turns its palm to the camera below it and sways.
func _face_hand(delta: float) -> void:
    if _arm == null or not _arm.visible:
        _snap_face = true
        return
    var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
    if cam == null:
        return
    var to := global_transform.basis.inverse() * (cam.global_position - (global_position + Vector3(0, HAND_DOWN, 0)))
    var yaw := atan2(to.x, to.z)
    var tilt := clampf(atan2(-to.y, Vector2(to.x, to.z).length()) * 0.45, 0.0, 0.45)
    var k := 1.0 if _snap_face else 1.0 - exp(-3.0 * delta)
    _snap_face = false
    _yaw = lerp_angle(_yaw, yaw, k)
    _tilt = lerpf(_tilt, tilt, k)
    _place_arm()
    _palm.rotation.z = sin(_time * 1.3) * 0.05 * _extend
    for i in range(4):
        (_fingers[i] as Node3D).rotation.x = -_curl * 1.2 + sin(_time * 2.1 + i * 0.9) * 0.05

func set_open(amount: float) -> void:
    _black_cover.visible = amount < 0.02
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
## Teeth the player put on the lip, waiting to be looked at (one per tooth).
const PILE_MAX := 60
var _pile: MultiMeshInstance3D

func _build_pile() -> void:
    _pile = MultiMeshInstance3D.new()
    _pile.name = "TeethPile"
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    var st := K.begin()
    K.lathe(st, Transform3D.IDENTITY, [Vector2(0.0, -0.004), Vector2(0.0075, -0.003), Vector2(0.009, 0.002), Vector2(0.008, 0.006), Vector2(0.004, 0.0085), Vector2(0.0, 0.007)], 6, [Color(0.9, 0.84, 0.66)])
    mm.mesh = K.finish(st, 60.0)
    mm.instance_count = PILE_MAX
    for i in range(PILE_MAX):
        # a small heap on the near lip, growing in rings
        var ring := int(sqrt(float(i)))
        var a := float(i) * 2.39996
        var r := 0.012 * float(ring)
        var pos := Vector3(cos(a) * r, -0.004 - 0.006 * float(ring % 3), SIZE - 0.05 + sin(a) * r * 0.6)
        mm.set_instance_transform(i, Transform3D(Basis.from_euler(Vector3(K.h(i, 1), K.h(i, 2), K.h(i, 3)) * TAU).scaled(Vector3.ONE * 2.2), pos))
    mm.visible_instance_count = 0
    _pile.multimesh = mm
    _pile.material_override = K.mat("tex_ceramic_64.png", 0.5, false)
    _pile.custom_aabb = AABB(Vector3(-0.2, -0.1, -0.2), Vector3(0.4, 0.2, 0.6))
    add_child(_pile)

func set_pile(n: int) -> void:
    if _pile != null:
        _pile.multimesh.visible_instance_count = clampi(n, 0, PILE_MAX)

func pile_count() -> int:
    return _pile.multimesh.visible_instance_count if _pile != null else 0

## 0 = the arm is up in the black duct, 1 = held out below the ceiling.
func set_offer_extend(t: float) -> void:
    _extend = clampf(t, 0.0, 1.0)
    _arm.visible = _extend > 0.001
    _place_arm()
    for i in range(_offers.size()):
        var slot: Node3D = _offers[i]
        slot.position = HOLD[i]
        slot.rotation_degrees = Vector3(0, 8.0 - i * 9.0, (i - 1) * 6.0)

## Wrist down and toward the camera; the forearm leans back up into the duct
## and the palm keeps facing the camera.
func _place_arm() -> void:
    var e := _extend
    var dir := Vector3(sin(_yaw), 0.0, cos(_yaw))
    # the open grate hangs on the -X side: reach less over it
    var reach := REACH * e * clampf(1.0 + dir.x * 1.2, 0.0, 1.0)
    _arm.position = Vector3(0, lerpf(HAND_UP, HAND_DOWN, e), 0.02) + dir * reach
    var lean := -atan2(reach, HAND_UP - HAND_DOWN + 0.1)
    _arm.basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, lean)
    _palm.rotation.x = _tilt - lean

func play_offer() -> void:
    _hand_to(1.0, 1.1, Tween.EASE_IN_OUT)

func play_withdraw() -> void:
    _hand_to(0.0, 0.35, Tween.EASE_IN)

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