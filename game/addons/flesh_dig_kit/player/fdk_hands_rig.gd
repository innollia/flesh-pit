class_name FDKHandsRig
extends Node3D

## Two low-poly first-person hands glued to the camera (the in-world HUD).
## Joint hierarchy (plain Node3D joints):
##   Root -> Forearm mesh
##        -> Wrist (pitch/yaw/roll) -> Palm mesh (+ thenar/hypothenar pads)
##             -> Finger1 -> Finger2 -> Finger3   (index..pinky fused block, 3 joints)
##             -> Thumb1  -> Thumb2  -> Thumb3    (separate thumb, 3 joints + opposition)
## States: IDLE (slight curl) / GRAB (joints curl 1->2->3, thumb closes, pull
## back + tremble with chew_progress) / TEAR (jerk back with torn chunk) /
## RELEASE (spread open, settle) / CARRY (both hands cradle a pile of torn
## flesh in front of the chest). Every angle is clamped to LIMITS_DEG.

const LIMITS_DEG := {
    "wrist_pitch": [-45.0, 75.0],
    "wrist_yaw": [-30.0, 30.0],
    "wrist_roll": [-60.0, 60.0],
    "f1": [-15.0, 88.0],
    "f2": [-8.0, 100.0],
    "f3": [-8.0, 80.0],
    "t1": [-10.0, 45.0],
    "t2": [-8.0, 65.0],
    "t3": [-8.0, 80.0],
    "t_opp": [0.0, 55.0],
}
const JOINT_NAMES := ["wrist_pitch", "wrist_yaw", "wrist_roll", "f1", "f2", "f3", "t1", "t2", "t3", "t_opp"]

enum HandState { IDLE, GRAB, TEAR, RELEASE }

const GRAB_TIME := 0.32
const TEAR_TIME := 0.34
const RELEASE_TIME := 0.4
const SECOND_HAND_DELAY := 0.09

@export var skin_color: Color = Color(0.88, 0.72, 0.62)
@export var palm_color: Color = Color(0.9, 0.68, 0.6)
@export var nail_color: Color = Color(0.95, 0.8, 0.74)
@export var bob_follow: float = 0.9

var state: HandState = HandState.IDLE
var mutation: float = 0.0
## 0 = hands free; >0 = carrying a pile of torn flesh (pile size 0..1).
var carry_amount: float = 0.0
## Base/max scale of the carried-pile mesh (built at radius ~0.09/0.05/0.045m
## in _build_pile). 0.42 keeps the base pile within a hand's width and under
## ~20% of screen height at the default FOV/reach_distance; 0.62 is the cap
## for a fully-loaded pile so it never grows unbounded.
const PILE_SCALE_BASE := 0.38
const PILE_SCALE_MAX := 0.56

var _hands: Array = []
var _time: float = 0.0
var _state_time: float = 0.0
var _chew: float = 0.0
var _lead: int = 0
var _bob: Vector3 = Vector3.ZERO
var _wet: float = 0.0
var _material: ShaderMaterial
var _pile: MeshInstance3D
var _built: bool = false

func _ready() -> void:
    build()
    var cam := get_parent() as Camera3D
    if cam != null and cam.near > 0.02:
        cam.near = 0.02

func build() -> void:
    if _built:
        return
    _built = true
    _material = FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_skin_128.png", 6.0, false, 0.32, 0.55, 0.18)
    _hands.append(_build_hand(1.0))
    _hands.append(_build_hand(-1.0))
    _pile = _build_pile()
    for h in _hands:
        _apply_pose(h, _pose_for(h, 0.0), 1.0)

func _process(delta: float) -> void:
    step(delta)

# --- FDKChewer signal contract ------------------------------------------

func on_grab_started(_cell: Vector3i = Vector3i.ZERO) -> void:
    if state != HandState.GRAB:
        state = HandState.GRAB
        _state_time = 0.0

func on_chew_progress(ratio: float, _cell: Vector3i = Vector3i.ZERO) -> void:
    _chew = clampf(ratio, 0.0, 1.0)
    if state == HandState.IDLE or state == HandState.RELEASE:
        state = HandState.GRAB
        _state_time = 0.0

func on_cell_torn(_world_pos: Vector3 = Vector3.ZERO) -> void:
    state = HandState.TEAR
    _state_time = 0.0
    _chew = 0.0
    _wet = minf(1.0, _wet + 0.35)
    var chunk: MeshInstance3D = _hands[_lead]["chunk"]
    chunk.visible = true
    chunk.scale = Vector3.ONE

func on_released() -> void:
    if state == HandState.IDLE:
        return
    state = HandState.RELEASE
    _state_time = 0.0
    _chew = 0.0

func animate_chew(ratio: float, cell: Vector3i) -> void:
    on_chew_progress(ratio, cell)

func notify_tear() -> void:
    on_cell_torn(Vector3.ZERO)

func reset_chew() -> void:
    on_released()

func apply_bob(offset: Vector3) -> void:
    _bob = offset

func set_mutation(amount: float) -> void:
    mutation = clampf(amount, 0.0, 1.0)

## Show/hide the carried flesh pile (design-core: carried pile blocks
## two-handed tools). amount 0 = hands free.
func set_carry(amount: float) -> void:
    carry_amount = clampf(amount, 0.0, 1.0)

func is_carrying() -> bool:
    return carry_amount > 0.001

# --- animation -----------------------------------------------------------

func step(delta: float) -> void:
    if not _built:
        build()
    _time += delta
    _state_time += delta
    match state:
        HandState.TEAR:
            if _state_time >= TEAR_TIME:
                _hands[_lead]["chunk"].visible = false
                _lead = 1 - _lead
                state = HandState.GRAB
                _state_time = 0.0
        HandState.RELEASE:
            if _state_time >= RELEASE_TIME:
                state = HandState.IDLE
                _state_time = 0.0
    _wet = maxf(0.0, _wet - delta * 0.08)
    _material.set_shader_parameter("wet", _wet)
    _material.set_shader_parameter("tint", Color(1, 1, 1).lerp(Color(0.78, 0.5, 0.55), mutation))
    var k := 1.0 - exp(-delta * 22.0)
    for i in range(_hands.size()):
        var h: Dictionary = _hands[i]
        var delay := 0.0 if i == _lead else SECOND_HAND_DELAY
        _apply_pose(h, _pose_for(h, delay), k)
        var chunk: MeshInstance3D = h["chunk"]
        if chunk.visible:
            var s := clampf(1.0 - maxf(0.0, _state_time - TEAR_TIME * 0.55) / (TEAR_TIME * 0.45), 0.05, 1.0)
            chunk.scale = Vector3.ONE * s
    _pile.visible = is_carrying()
    if _pile.visible:
        # 형님 결정 2026-09-29: 기본 더미는 두 손바닥에 올라가는 정도(원래
        # 크기의 약 45%), 화면 높이 20% 이하로 유지. 더 들면 조금씩 커지되
        # PILE_SCALE_MAX에서 상한.
        var ps := lerpf(PILE_SCALE_BASE, PILE_SCALE_MAX, carry_amount)
        _pile.scale = Vector3(ps, ps * (0.8 + 0.2 * sin(_time * 3.0) * 0.1 + 0.2), ps)
        _pile.position = Vector3(0, -0.2 + _bob.y * 1.1, -0.36)

func _ease(x: float) -> float:
    x = clampf(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)

func _pose_for(h: Dictionary, delay: float) -> Dictionary:
    var side: float = h["side"]
    var is_lead: bool = h["index"] == _lead
    var breathe := sin(_time * 1.7 + side) * 1.5
    var idle := {
        "wrist_pitch": 14.0 + breathe, "wrist_yaw": 10.0 * side, "wrist_roll": -32.0 * side,
        "f1": 18.0 + breathe, "f2": 24.0, "f3": 14.0,
        "t1": 2.0, "t2": 8.0, "t3": 10.0, "t_opp": 3.0,
        "pos": Vector3(0.2 * side, -0.215, -0.4),
    }
    var p := idle.duplicate()
    var t := maxf(0.0, _state_time - delay)
    if is_carrying() and state == HandState.IDLE:
        # palms up under the pile, fingers cupped
        p["wrist_roll"] = 55.0 * side
        p["wrist_pitch"] = 5.0
        p["wrist_yaw"] = -12.0 * side
        p["f1"] = 30.0
        p["f2"] = 34.0
        p["f3"] = 20.0
        p["t_opp"] = 8.0
        p["pos"] = Vector3(0.1 * side, -0.24, -0.38)
    match state:
        HandState.GRAB:
            var g := t / GRAB_TIME
            var strength := 1.0 if is_lead else 0.82
            var c1 := _ease(g / 0.5)
            var c2 := _ease((g - 0.25) / 0.5)
            var c3 := _ease((g - 0.5) / 0.5)
            var ct := _ease((g - 0.35) / 0.65)
            var reach := _ease(g / 0.6)
            p["f1"] = lerpf(idle["f1"], 62.0 * strength, c1)
            p["f2"] = lerpf(idle["f2"], 82.0 * strength, c2)
            p["f3"] = lerpf(idle["f3"], 62.0 * strength, c3)
            p["t_opp"] = lerpf(idle["t_opp"], 44.0, ct)
            p["t1"] = lerpf(idle["t1"], 26.0, ct)
            p["t2"] = lerpf(idle["t2"], 40.0, ct)
            p["t3"] = lerpf(idle["t3"], 44.0, ct)
            p["wrist_pitch"] = lerpf(idle["wrist_pitch"], 62.0, reach)
            p["wrist_yaw"] = lerpf(idle["wrist_yaw"], 6.0 * side, reach)
            p["wrist_roll"] = lerpf(idle["wrist_roll"], -12.0 * side, reach)
            var pos: Vector3 = (idle["pos"] as Vector3).lerp(Vector3(0.12 * side, -0.1, -0.47), reach)
            var r := _chew * reach
            p["f1"] += 14.0 * r
            p["f2"] += 12.0 * r
            p["f3"] += 10.0 * r
            p["t3"] += 14.0 * r
            p["wrist_pitch"] -= 22.0 * r
            pos += Vector3(0.015 * side * r, -0.02 * r, 0.075 * r)
            var amp := (0.0015 + 0.009 * r * r) * reach
            pos += Vector3(sin(_time * 53.0 + side * 2.0), cos(_time * 61.0 + side), sin(_time * 47.0)) * amp
            p["pos"] = pos
        HandState.TEAR:
            var tt := clampf(t / TEAR_TIME, 0.0, 1.0)
            var fist := 1.0 if is_lead else 0.7
            p["f1"] = 84.0 * fist
            p["f2"] = 98.0 * fist
            p["f3"] = 76.0 * fist
            p["t_opp"] = 50.0
            p["t1"] = 34.0
            p["t2"] = 58.0
            p["t3"] = 62.0
            var jerk := sin(tt * PI) * exp(-tt * 2.0)
            p["wrist_pitch"] = 40.0 - 35.0 * jerk
            p["wrist_yaw"] = 6.0 * side
            p["wrist_roll"] = -14.0 * side - 18.0 * side * jerk
            var lead_scale := 1.0 if is_lead else 0.35
            p["pos"] = Vector3(0.13 * side, -0.11, -0.44) + Vector3(0.03 * side, -0.07, 0.11) * jerk * lead_scale
        HandState.RELEASE:
            var rt := clampf(t / RELEASE_TIME, 0.0, 1.0)
            var e := _ease(rt)
            p["f1"] = lerpf(-12.0, idle["f1"], e)
            p["f2"] = lerpf(-6.0, idle["f2"], e)
            p["f3"] = lerpf(-6.0, idle["f3"], e)
            p["t_opp"] = lerpf(0.0, idle["t_opp"], e)
            p["t1"] = lerpf(-8.0, idle["t1"], e)
            p["pos"] = Vector3(0.15 * side, -0.14, -0.44).lerp(idle["pos"], e)
            p["wrist_pitch"] = lerpf(45.0, idle["wrist_pitch"], e)
    var bob: Vector3 = _bob * bob_follow
    p["pos"] = (p["pos"] as Vector3) + Vector3(bob.y * 0.5 * side, bob.y * 1.1, 0.0)
    return p

func _clamp_joint(joint: String, value: float) -> float:
    var lim: Array = LIMITS_DEG[joint]
    return clampf(value, lim[0], lim[1])

func _apply_pose(h: Dictionary, target: Dictionary, k: float) -> void:
    var cur: Dictionary = h["pose"]
    for joint in JOINT_NAMES:
        var v: float = lerpf(cur.get(joint, target[joint]), target[joint], k)
        cur[joint] = _clamp_joint(joint, v)
    var cur_pos: Vector3 = cur.get("pos", target["pos"])
    cur["pos"] = cur_pos.lerp(target["pos"], k)
    var ts: float = h["thumb_side"]
    (h["root"] as Node3D).position = cur["pos"]
    (h["wrist"] as Node3D).basis = Basis.from_euler(Vector3(deg_to_rad(cur["wrist_pitch"]), deg_to_rad(cur["wrist_yaw"]), deg_to_rad(cur["wrist_roll"])), EULER_ORDER_YXZ)
    (h["f1"] as Node3D).basis = Basis(Vector3.RIGHT, -deg_to_rad(cur["f1"]))
    (h["f2"] as Node3D).basis = Basis(Vector3.RIGHT, -deg_to_rad(cur["f2"]))
    (h["f3"] as Node3D).basis = Basis(Vector3.RIGHT, -deg_to_rad(cur["f3"]))
    var base: Basis = h["thumb_base"]
    var opp := Basis(Vector3.UP, deg_to_rad(cur["t_opp"]) * -ts * 0.8) * Basis(Vector3.FORWARD, deg_to_rad(cur["t_opp"]) * ts * 0.5)
    (h["t1"] as Node3D).basis = base * opp * Basis(Vector3.RIGHT, -deg_to_rad(cur["t1"]))
    (h["t2"] as Node3D).basis = Basis(Vector3.RIGHT, -deg_to_rad(cur["t2"]))
    (h["t3"] as Node3D).basis = Basis(Vector3.RIGHT, -deg_to_rad(cur["t3"]))
    (h["f1"] as Node3D).scale = Vector3(1.0, 1.0 + 0.25 * mutation, 1.0)

func get_joint_angles(hand_side: String) -> Dictionary:
    var h: Dictionary = _hands[0] if hand_side == "right" else _hands[1]
    var out := {}
    for joint in JOINT_NAMES:
        out[joint] = float(h["pose"][joint])
    return out

func get_joint_angle(hand_side: String, joint_name: String) -> float:
    var a := get_joint_angles(hand_side)
    var map := {"knuckle1": "f1", "knuckle2": "f2", "thumb_joint1": "t1", "thumb_joint2": "t2"}
    return deg_to_rad(a.get(map.get(joint_name, joint_name), 0.0))

func get_hand_root(hand_side: String) -> Node3D:
    return _hands[0]["root"] if hand_side == "right" else _hands[1]["root"]

## World-space fingertip positions (finger block tip, thumb tip) for tests.
func get_tip_positions(hand_side: String) -> Array:
    var h: Dictionary = _hands[0] if hand_side == "right" else _hands[1]
    var f3: Node3D = h["f3"]
    var t3: Node3D = h["t3"]
    return [_to_rig(f3) * Vector3(0, 0, -0.025), _to_rig(t3) * Vector3(0, 0, -0.025)]

## Transform of a joint relative to this rig (works outside the scene tree).
func _to_rig(n: Node3D) -> Transform3D:
    var t := Transform3D.IDENTITY
    var cur: Node = n
    while cur != null and cur != self:
        t = (cur as Node3D).transform * t
        cur = cur.get_parent()
    return t

# --- mesh building ---------------------------------------------------------

## Cross-section of the fused finger block: four rounded fingers side by
## side, with grooves between them on the back AND the palm side.
const FINGER_PROFILE := [
    Vector2(1.0, -0.1), Vector2(0.95, 0.55), Vector2(0.75, 1.0), Vector2(0.5, 0.58),
    Vector2(0.25, 1.0), Vector2(0.0, 0.6), Vector2(-0.25, 1.0), Vector2(-0.5, 0.58),
    Vector2(-0.75, 0.95), Vector2(-0.95, 0.5), Vector2(-1.0, -0.15), Vector2(-0.92, -0.72),
    Vector2(-0.75, -1.0), Vector2(-0.5, -0.66), Vector2(-0.25, -1.0), Vector2(0.0, -0.66),
    Vector2(0.25, -1.0), Vector2(0.5, -0.66), Vector2(0.75, -1.0), Vector2(0.92, -0.72),
]

func _build_hand(side: float) -> Dictionary:
    var thumb_side := -side
    var root := Node3D.new()
    root.name = "HandRight" if side > 0.0 else "HandLeft"
    add_child(root)
    _add_mesh(root, "Forearm", _forearm_mesh())
    var wrist := Node3D.new()
    wrist.name = "Wrist"
    root.add_child(wrist)
    _add_mesh(wrist, "Palm", _palm_mesh(thumb_side))

    var palm_len := 0.088
    var f_len := [0.044, 0.031, 0.025]
    var f_half := [Vector2(0.047, 0.0215), Vector2(0.044, 0.0195), Vector2(0.04, 0.017)]
    var f1 := _joint(wrist, "Finger1", Vector3(0, 0.001, -palm_len))
    _add_mesh(f1, "Seg", _finger_mesh(f_len[0], f_half[0], f_half[1], thumb_side, false))
    var f2 := _joint(f1, "Finger2", Vector3(0, 0, -f_len[0]))
    _add_mesh(f2, "Seg", _finger_mesh(f_len[1], f_half[1], f_half[2], thumb_side, false))
    var f3 := _joint(f2, "Finger3", Vector3(0, 0, -f_len[1]))
    _add_mesh(f3, "Seg", _finger_mesh(f_len[2], f_half[2], f_half[2] * 0.8, thumb_side, true))

    var t_len := [0.04, 0.03, 0.025]
    var t1 := _joint(wrist, "Thumb1", Vector3(thumb_side * 0.036, -0.008, -0.016))
    _add_mesh(t1, "Seg", _thumb_mesh(t_len[0], Vector2(0.02, 0.0175), Vector2(0.0175, 0.0155), false))
    var t2 := _joint(t1, "Thumb2", Vector3(0, 0, -t_len[0]))
    _add_mesh(t2, "Seg", _thumb_mesh(t_len[1], Vector2(0.0175, 0.0155), Vector2(0.0155, 0.0135), false))
    var t3 := _joint(t2, "Thumb3", Vector3(0, 0, -t_len[1]))
    _add_mesh(t3, "Seg", _thumb_mesh(t_len[2], Vector2(0.0155, 0.0135), Vector2(0.013, 0.011), true))

    var thumb_base := Basis(Vector3.UP, deg_to_rad(-38.0) * thumb_side) * Basis(Vector3.FORWARD, deg_to_rad(-55.0) * thumb_side) * Basis(Vector3.RIGHT, deg_to_rad(-12.0))

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    FDKLowPoly.add_blob(st, Vector3.ZERO, Vector3(0.03, 0.026, 0.034), 0.35, 7 + int(side), Color(0.62, 0.07, 0.1), Color(0.85, 0.2, 0.2))
    var chunk := _add_mesh(wrist, "TornChunk", st.commit())
    chunk.material_override = FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_torn_chunk_128.png", 2.0, false, 0.7, 0.4, 0.18)
    chunk.position = Vector3(0, -0.03, -0.105)
    chunk.visible = false

    return {
        "side": side, "thumb_side": thumb_side, "index": 0 if side > 0.0 else 1,
        "root": root, "wrist": wrist, "f1": f1, "f2": f2, "f3": f3,
        "t1": t1, "t2": t2, "t3": t3, "thumb_base": thumb_base, "chunk": chunk,
        "pose": {},
    }

func _joint(parent: Node3D, joint_name: String, pos: Vector3) -> Node3D:
    var n := Node3D.new()
    n.name = joint_name
    n.position = pos
    parent.add_child(n)
    return n

func _build_pile() -> MeshInstance3D:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var a := Color(0.55, 0.06, 0.09)
    var b := Color(0.86, 0.22, 0.22)
    FDKLowPoly.add_blob(st, Vector3(0, 0, 0), Vector3(0.09, 0.05, 0.07), 0.3, 11, a, b)
    FDKLowPoly.add_blob(st, Vector3(0.05, 0.035, 0.01), Vector3(0.05, 0.04, 0.045), 0.35, 12, a, b)
    FDKLowPoly.add_blob(st, Vector3(-0.045, 0.03, -0.015), Vector3(0.045, 0.035, 0.04), 0.35, 13, a, b)
    FDKLowPoly.add_blob(st, Vector3(0.0, 0.06, 0.0), Vector3(0.035, 0.03, 0.035), 0.4, 14, a, b)
    var mi := _add_mesh(self, "CarriedPile", st.commit())
    mi.material_override = FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_torn_chunk_128.png", 2.5, false, 0.7, 0.4, 0.18)
    mi.visible = false
    return mi

func _add_mesh(parent: Node3D, mesh_name: String, mesh: Mesh) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.name = mesh_name
    mi.mesh = FDKLowPoly.planar_uv_mesh(mesh as ArrayMesh, 5.0)
    mi.material_override = _material
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(mi)
    return mi

func _forearm_mesh() -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var prof := FDKLowPoly.round_profile(8, 0.15)
    var rings := [
        FDKLowPoly.ring(prof, 0.34, Vector2(0.037, 0.031), Vector2(0, -0.004)),
        FDKLowPoly.ring(prof, 0.18, Vector2(0.034, 0.028), Vector2(0, -0.003)),
        FDKLowPoly.ring(prof, 0.06, Vector2(0.029, 0.022), Vector2(0, -0.001)),
        FDKLowPoly.ring(prof, 0.008, Vector2(0.026, 0.018)),
    ]
    FDKLowPoly.loft(st, rings, [skin_color.darkened(0.12), skin_color.darkened(0.05), skin_color], true, true)
    return st.commit()

func _palm_mesh(thumb_side: float) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var prof := FDKLowPoly.round_profile(10, 0.35)
    var rings := [
        FDKLowPoly.ring(prof, 0.014, Vector2(0.027, 0.018)),
        FDKLowPoly.ring(prof, -0.022, Vector2(0.042, 0.02), Vector2(thumb_side * 0.002, 0)),
        FDKLowPoly.ring(prof, -0.058, Vector2(0.049, 0.02)),
        FDKLowPoly.ring(prof, -0.086, Vector2(0.05, 0.021), Vector2(0, 0.001)),
        FDKLowPoly.ring(prof, -0.093, Vector2(0.048, 0.0215), Vector2(0, 0.001)),
    ]
    FDKLowPoly.loft(st, rings, [skin_color, skin_color, skin_color.lightened(0.04), skin_color], true, true)
    FDKLowPoly.add_blob(st, Vector3(thumb_side * 0.02, -0.011, -0.03), Vector3(0.017, 0.011, 0.026), 0.18, 3, palm_color, palm_color.darkened(0.08))
    FDKLowPoly.add_blob(st, Vector3(-thumb_side * 0.024, -0.01, -0.035), Vector3(0.013, 0.008, 0.028), 0.15, 5, palm_color, palm_color.darkened(0.06))
    return st.commit()

func _finger_mesh(length: float, half_start: Vector2, half_end: Vector2, thumb_side: float, tip: bool) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var prof := PackedVector2Array(FINGER_PROFILE)
    # knuckle bulge at the joint, slimmer in the middle of the segment
    var r0 := FDKLowPoly.ring(prof, 0.007, half_start * Vector2(1.02, 1.07), Vector2(0, half_start.y * 0.03))
    var r1 := FDKLowPoly.ring(prof, -length * 0.5, (half_start + half_end) * 0.5 * Vector2(1.0, 0.97))
    var r2 := FDKLowPoly.ring(prof, -length, half_end * Vector2(1.0, 1.08))
    if tip:
        _shape_tip(r0, prof, thumb_side, -0.007, 0.0)
        _shape_tip(r1, prof, thumb_side, length * 0.5, 0.35)
        _shape_tip(r2, prof, thumb_side, length, 1.0)
        var r3 := FDKLowPoly.ring(prof, -length - 0.007, half_end * Vector2(0.9, 0.55), Vector2(0, -0.001))
        _shape_tip(r3, prof, thumb_side, length + 0.007, 1.0)
        FDKLowPoly.loft(st, [r0, r1, r2, r3], [skin_color, skin_color.lightened(0.03), nail_color], false, true)
    else:
        FDKLowPoly.loft(st, [r0, r1, r2], [skin_color, skin_color.lightened(0.02)], false, false)
    return st.commit()

func _shape_tip(r: PackedVector3Array, prof: PackedVector2Array, thumb_side: float, depth: float, amount: float) -> void:
    for i in range(r.size()):
        var u := prof[i].x * thumb_side
        var f := 1.0 - 0.28 * smoothstep(-0.2, -1.0, u) - 0.07 * smoothstep(0.4, 1.0, u)
        var p := r[i]
        p.z = -depth * lerpf(1.0, f, amount)
        r[i] = p

func _thumb_mesh(length: float, half_start: Vector2, half_end: Vector2, tip: bool) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var prof := FDKLowPoly.round_profile(7, 0.25)
    var r0 := FDKLowPoly.ring(prof, 0.006, half_start * 1.05)
    var r1 := FDKLowPoly.ring(prof, -length * 0.5, (half_start + half_end) * 0.5 * Vector2(1.0, 1.05))
    var r2 := FDKLowPoly.ring(prof, -length, half_end)
    if tip:
        var r3 := FDKLowPoly.ring(prof, -length - 0.007, half_end * Vector2(0.75, 0.55))
        FDKLowPoly.loft(st, [r0, r1, r2, r3], [skin_color, skin_color, nail_color], true, true)
    else:
        FDKLowPoly.loft(st, [r0, r1, r2], [skin_color, skin_color], true, false)
    return st.commit()
