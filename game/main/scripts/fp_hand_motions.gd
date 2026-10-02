class_name FPHandMotions
extends RefCounted

## Situational first-person hand / body motions, all procedural:
## scoop (grab a handful of teeth in the tank), pour (spill it at the vent
## grate), take (reach for an offered item, curl, pull it back; big items
## with both hands), vomit_toilet (lean over the bowl, both hands on the rim,
## 2-3 heaves, breathe, straighten), vomit_floor (hands on the knees, flesh
## onto the floor), wash (turn the tap, rub under the stream with laced
## fingers, shake, turn it off; the blood fades while rubbing), belt (reach
## down, hang the held tool, grab the other, bring it up) and cycle (a short
## dip for Tab / wheel). The hands rig asks shape_pose() every frame; the
## motion weight eases in and out, and cancel() fades it out so the hands
## glide back to where they were. Game rules never wait on a motion.

const DUR := {
    "scoop": 0.55, "pour": 0.85, "take": 0.65, "take2": 0.75,
    "vomit_toilet": 2.4, "vomit_floor": 2.4, "wash": 2.6,
    "belt": 0.75, "cycle": 0.35, "watch": 1.0e9,
}
const CANCEL_TIME := 0.25
## Mirror look (watch): the left arm comes up like checking a wristwatch and
## stays up until release_watch() (the mirror closes on interact / move / Esc).
const WATCH_RAISE := 0.3
const CANCEL_ACTIONS := ["fdk_move_forward", "fdk_move_back", "fdk_move_left", "fdk_move_right",
    "fdk_jump", "fp_interact", "fp_pick", "fdk_eat", "fp_tool_next", "fp_vomit", "ui_cancel"]
## Offer kinds held with both hands.
const BIG_ITEMS := ["blender", "big_saw", "blender_box", "saw_box"]
const FLESH := Color(0.55, 0.12, 0.13)

var m: Node3D
var kind: String = ""
var t: float = 0.0
var dur: float = 0.0
var cancelled: bool = false
var _cancel_w: float = 1.0
var _cam_pos := Vector3.ZERO
var _cam_rot := Vector3.ZERO
var _vomit_frame := Transform3D.IDENTITY
## 형님 2026-09-30: vomit_floor used to add its bow pitch on top of
## whatever pitch the player happened to be looking at when it started, so
## looking down made the camera clip through the body and looking up left
## it staring at nothing. The floor heave now uses a captured upright
## world frame, including a fixed yaw, independent of the head pivot.
const VOMIT_FLOOR_BASE_PITCH := -0.35
var _cam_saved := false
var _settle_base := Transform3D.IDENTITY
var _settle_saved := false
var rim_rig: Node3D
var _target := Vector3.ZERO ## take: rig-local point of the item
var _held_mesh: MeshInstance3D
var _wash_from := 0.0
var _stream: MeshInstance3D
var _heaves_done := 0
var _spill_n := 0
var _poured := false
var _swung := false
var belt_hook := -1

func _init(main: Node3D) -> void:
    m = main

func busy() -> bool:
    return kind != ""

func progress() -> float:
    return clampf(t / dur, 0.0, 1.0) if dur > 0.0 else 1.0

# --- starting -------------------------------------------------------------------

func _start(k: String) -> void:
    if busy():
        _finish()
    _save_cams()
    kind = k
    dur = float(DUR[k])
    t = 0.0
    cancelled = false
    _cancel_w = 1.0
    _heaves_done = 0
    _poured = false
    _swung = false
    if m.hands_rig != null:
        m.hands_rig.set("pose_hook", self)
    if m.art_hookup != null and m.art_hookup.mut_hands != null:
        m.art_hookup.mut_hands.call("rig").set("pose_hook", self)

func play_scoop() -> void:
    _start("scoop")

func play_pour(teeth: int) -> void:
    _start("pour")
    _spill_n = clampi(teeth, 3, 10)

## `world_pos` = the aimed item, `item` = its art mesh to carry back.
func play_take(world_pos: Vector3, art_kind: String, item: MeshInstance3D = null) -> void:
    _start("take2" if art_kind in BIG_ITEMS else "take")
    var rig: Node3D = m.hands_rig
    var local: Vector3 = rig.to_local(world_pos) if rig != null and rig.is_inside_tree() else Vector3(0, 0.1, -0.6)
    if local.length() > 0.62:
        local = local.normalized() * 0.62
    local.z = minf(local.z, -0.3)
    _target = local
    _clear_held()
    if item != null and item.mesh != null and rig != null:
        _held_mesh = MeshInstance3D.new()
        _held_mesh.name = "TakenItem"
        _held_mesh.mesh = item.mesh
        _held_mesh.material_override = item.material_override
        for i in range(item.get_surface_override_material_count()):
            _held_mesh.set_surface_override_material(i, item.get_surface_override_material(i))
        _held_mesh.visible = false
        var hand: Node3D = rig.call("get_hand_root", "right")
        hand.add_child(_held_mesh)
        _held_mesh.position = Vector3(-0.02, -0.03, -0.1)

func play_vomit(at_toilet: bool, fill: float) -> void:
    _start("vomit_toilet" if at_toilet else "vomit_floor")
    _vomit_frame = Transform3D(Basis(Vector3.UP, m.player.global_rotation.y), m.player.camera_pivot.global_position)
    _spill_n = clampi(int(round(fill * 6.0)) + 2, 2, 8)
    if at_toilet:
        _ensure_rim_rig()
        rim_rig.visible = true

func play_wash(blood: float) -> void:
    _start("wash")
    _wash_from = blood
    _ensure_stream()

func play_belt(hook: int) -> void:
    _start("belt")
    dur = FPBeltSwap.SWAP_TIME
    belt_hook = hook

## Raise the left arm as if reading a wristwatch; held until release_watch().
func play_watch() -> void:
    _start("watch")

func release_watch() -> void:
    if kind == "watch":
        cancel()

func watch_raised() -> float:
    return weight() if kind == "watch" else 0.0

func play_cycle() -> void:
    _start("cycle")

## Fade out now; the hands glide back from wherever they are.
func cancel() -> void:
    if not busy() or cancelled:
        return
    cancelled = true
    _cancel_w = 1.0
    if kind == "wash":
        m.hand_blood = maxf(m.hand_blood, blood_visual())

## Any move / action pressed after the motion started interrupts it.
func check_cancel() -> void:
    # Tab owns this held pose; clicking mutation rows uses the same mouse
    # buttons as tools and must not lower the arm. Closing Tab releases it.
    if kind == "watch":
        return
    if not busy() or cancelled or t < 0.06:
        return
    for a in CANCEL_ACTIONS:
        if InputMap.has_action(a) and Input.is_action_just_pressed(a):
            cancel()
            return

# --- per frame --------------------------------------------------------------------

func tick(delta: float) -> void:
    if not busy():
        return
    t += delta
    if cancelled:
        _cancel_w -= delta / CANCEL_TIME
    var u := progress()
    _events(u)
    _apply_cams(u)
    _update_stream(u)
    _apply_watch_arm()
    if _held_mesh != null:
        _held_mesh.visible = u >= 0.45 and weight() > 0.3
    if (cancelled and _cancel_w <= 0.0) or (not cancelled and t >= dur):
        _finish()

func _finish() -> void:
    kind = ""
    t = 0.0
    _apply_cams(1.0, true)
    if rim_rig != null:
        rim_rig.visible = false
    if _stream != null:
        _stream.visible = false
    _clear_held()
    cancelled = false
    _apply_watch_arm()

## Left-arm roll for the watch look: the hand root turns so the forearm lies
## slanted across the lower third (elbow low-left, wrist in the middle) with
## its hairy top facing the camera, tipped a little up so the strands lie
## visible instead of pointing into the lens (형님 지시, mirror 3).
## Root basis only; the rig itself never writes it, so it is reset here.
const WATCH_ARM_TIP := 0.35 ## rad, hairy top tipped from the camera toward up
## Wrist direction (camera space): right, a little up and AWAY from the eye,
## so the elbow 0.34 m back comes close and low-left, past the frame edge,
## and the forearm reads as running in from off-screen (mirror 4).
const WATCH_ARM_DIR := Vector3(0.745, 0.186, -0.641)
static func _watch_basis() -> Basis:
    var d := WATCH_ARM_DIR.normalized() # wrist direction
    var up := Vector3(0.0, sin(WATCH_ARM_TIP), cos(WATCH_ARM_TIP))
    up = (up - d * up.dot(d)).normalized()
    var z := -d
    return Basis(up.cross(z).normalized(), up, z).orthonormalized()
static var WATCH_ARM_BASIS := _watch_basis()
## Wrist spot (camera space) while looking: 0.35-0.45 m out, lower third.
const WATCH_WRIST_POS := Vector3(0.0, -0.13, -0.4)
## Right hand drops out of view under the frame while looking.
const WATCH_RIGHT_POS := Vector3(0.2, -0.62, -0.25)
func watch_arm_basis() -> Basis:
    var w := weight() if kind == "watch" else 0.0
    return Basis.IDENTITY.slerp(WATCH_ARM_BASIS, w) if w > 0.0 else Basis.IDENTITY

func _apply_watch_arm() -> void:
    var b := watch_arm_basis()
    var rigs: Array = [m.hands_rig]
    var hook = m.get("art_hookup")
    if hook != null and hook.get("mut_hands") != null:
        var r2 = (hook.mut_hands as Node).call("rig") if (hook.mut_hands as Node).has_method("rig") else null
        if r2 != null:
            rigs.append(r2)
    for rig in rigs:
        if rig == null or not (rig as Node).has_method("get_hand_root"):
            continue
        var lr: Node3D = rig.call("get_hand_root", "left")
        if lr != null:
            lr.basis = b
            var forearm := lr.get_node_or_null("Forearm") as Node3D
            var hair_arm := lr.get_node_or_null("ArmHair/Forearm") as MeshInstance3D
            if hair_arm != null:
                var raised := watch_raised() > 0.01
                hair_arm.visible = raised
                if forearm != null:
                    forearm.visible = not raised

func _clear_held() -> void:
    if _held_mesh != null:
        if _held_mesh.get_parent() != null:
            _held_mesh.get_parent().remove_child(_held_mesh)
        _held_mesh.queue_free()
        _held_mesh = null

static func seg(u: float, a: float, b: float) -> float:
    var x := clampf((u - a) / (b - a), 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)

## 0..1 blend of the motion over the rig's own pose.
func weight() -> float:
    if not busy():
        return 0.0
    var u := progress()
    if kind == "watch":
        var ww := seg(t, 0.0, WATCH_RAISE)
        if cancelled:
            ww *= clampf(_cancel_w, 0.0, 1.0)
        return ww
    var w := seg(u, 0.0, 0.14) * (1.0 - seg(u, 0.86, 1.0))
    if kind in ["vomit_toilet", "vomit_floor", "wash"]:
        w = seg(u, 0.0, 0.08) * (1.0 - seg(u, 0.92, 1.0))
    if cancelled:
        w *= clampf(_cancel_w, 0.0, 1.0)
    return w

## Blood still on the hands while washing (the rule value is already 0).
func blood_visual() -> float:
    if kind != "wash":
        return 0.0
    return _wash_from * (1.0 - seg(progress(), 0.25, 0.72))

## Heave amount 0..1 at u (three pulses for the vomits).
func _heave(u: float) -> float:
    var h := 0.0
    for c in [0.36, 0.55, 0.72]:
        h = maxf(h, exp(-pow((u - c) / 0.045, 2.0)))
    return h

func _events(u: float) -> void:
    match kind:
        "vomit_toilet", "vomit_floor":
            var marks := [0.36, 0.55, 0.72]
            while _heaves_done < marks.size() and u >= marks[_heaves_done] and not cancelled:
                _heaves_done += 1
                _spill(kind == "vomit_toilet", maxi(1, _spill_n / 3 + (1 if _heaves_done == 1 else 0)))
        "pour":
            if u >= 0.55 and not _poured and not cancelled:
                _poured = true
                _pour_teeth()
        "belt":
            if u >= 0.5 and not _swung:
                _swung = true
                var belt = m.art_hookup.belt if m.art_hookup != null else null
                if belt != null and belt.has_method("swing") and belt_hook >= 0:
                    belt.call("swing", belt_hook)

# --- cameras ------------------------------------------------------------------------

func _save_cams() -> void:
    var cam: Camera3D = m.player.camera if m.player != null else null
    if cam != null and not _cam_saved:
        _cam_saved = true
        _cam_pos = cam.position
        _cam_rot = cam.rotation
    if m.settle_camera != null and not _settle_saved:
        _settle_saved = true
        _settle_base = m.settle_camera.transform

## Additive body motion on the player camera (floor) or the bowl camera.
func _apply_cams(u: float, reset: bool = false) -> void:
    var cam: Camera3D = m.player.camera if m.player != null else null
    if cam != null and _cam_saved:
        var off := Vector3.ZERO
        var pitch := 0.0
        var roll := 0.0
        if not reset and kind == "vomit_floor":
            var w := weight()
            var h := _heave(u)
            var bow := seg(u, 0.0, 0.25) * (1.0 - seg(u, 0.8, 1.0) * 0.85)
            var shake := sin(t * 37.0) * 0.004 * h
            off = Vector3(0.0, -0.42 * bow - 0.05 * h, -0.12 * bow - 0.04 * h) * w
            # pitch is measured from a fixed base, not the player's pitch at
            # the moment vomiting started -- looking down or up beforehand
            # no longer changes where the camera ends up pointing.
            pitch = (VOMIT_FLOOR_BASE_PITCH - _cam_rot.x) + (-0.62 * bow - 0.12 * h + shake) * w
            roll = sin(t * 29.0) * 0.006 * h * w
        elif not reset and kind == "wash":
            var w2 := weight()
            off = Vector3(0.0, -0.06, -0.03) * w2
            pitch = -0.22 * w2
        elif not reset and kind == "belt":
            pitch = -0.06 * sin(progress() * PI) * weight()
        cam.position = _cam_pos + off
        cam.rotation = _cam_rot + Vector3(pitch, 0.0, roll)
        if not reset and kind == "vomit_floor":
            # Camera-local rotation still inherits the head pivot's pitch.
            # Apply the heave in the upright body's frame, captured once.
            cam.global_transform = Transform3D(_vomit_frame.basis * Basis.from_euler(Vector3(_cam_rot.x + pitch, 0, roll)), _vomit_frame.origin + _vomit_frame.basis * (_cam_pos + off))
    var sc: Camera3D = m.settle_camera
    if sc != null and _settle_saved:
        if reset or kind != "vomit_toilet":
            sc.transform = _settle_base
            return
        var w3 := weight()
        var h2 := _heave(u)
        var lean := 1.0 - seg(u, 0.0, 0.28) # 1 = still upright above the bowl
        var up := seg(u, 0.8, 1.0) * 0.35 # breathing, half up again
        var b := _settle_base.basis
        var back := b.z
        var p := _settle_base.origin + (Vector3.UP * (0.34 * lean + 0.08 * up) + back * (0.22 * lean) - back * 0.05 * h2 - Vector3.UP * 0.04 * h2) * w3
        var rot := Basis(b.x, (0.55 * lean + 0.12 * up) * w3 - 0.1 * h2 * w3) * b
        rot = Basis(rot.z, sin(t * 31.0) * 0.008 * h2 * w3) * rot
        sc.transform = Transform3D(rot.orthonormalized(), p)

# --- the rig asks for its pose ------------------------------------------------------

## `p` = the rig's own target pose for one hand; returns it blended toward
## the motion pose. `rig` tells the main hands from the bowl-rim hands.
func shape_pose(rig: Node3D, side: float, p: Dictionary) -> Dictionary:
    if rig == rim_rig:
        return _rim_pose(side, p)
    var w := weight()
    if w <= 0.0 or kind == "vomit_toilet":
        return p
    var q := _motion_pose(side, p)
    if q.is_empty():
        return p
    var out := p.duplicate()
    for key in q:
        if key == "pos":
            out["pos"] = (p["pos"] as Vector3).lerp(q["pos"], w)
        else:
            out[key] = lerpf(float(p[key]), float(q[key]), w)
    return out

static func _fingers(q: Dictionary, curl: float) -> void:
    q["f1"] = lerpf(-10.0, 72.0, curl)
    q["f2"] = lerpf(-6.0, 90.0, curl)
    q["f3"] = lerpf(-6.0, 68.0, curl)
    q["t1"] = lerpf(-8.0, 30.0, curl)
    q["t2"] = lerpf(-6.0, 48.0, curl)
    q["t3"] = lerpf(-6.0, 50.0, curl)
    q["t_opp"] = lerpf(0.0, 48.0, curl)

func _motion_pose(side: float, p: Dictionary) -> Dictionary:
    var u := progress()
    var right := side > 0.0
    var q := {}
    var idle: Vector3 = p["pos"]
    match kind:
        "scoop":
            if not right:
                return {}
            var reach := seg(u, 0.0, 0.4) * (1.0 - seg(u, 0.6, 1.0))
            _fingers(q, seg(u, 0.38, 0.6))
            q["wrist_pitch"] = lerpf(48.0, 72.0, reach)
            q["wrist_roll"] = -8.0
            q["pos"] = idle.lerp(Vector3(0.1, -0.32, -0.44), reach)
        "pour":
            if not right:
                return {}
            var reach2 := seg(u, 0.0, 0.45) * (1.0 - seg(u, 0.8, 1.0))
            var tip := seg(u, 0.45, 0.62) * (1.0 - seg(u, 0.8, 1.0))
            _fingers(q, 0.85 - 0.95 * tip)
            q["wrist_pitch"] = lerpf(40.0, 5.0, reach2) - 20.0 * tip
            q["wrist_roll"] = lerpf(-10.0, -58.0, tip)
            q["wrist_yaw"] = -10.0 * tip
            var shake := Vector3(sin(t * 41.0), cos(t * 37.0), 0.0) * 0.006 * tip
            q["pos"] = idle.lerp(Vector3(0.05, -0.02, -0.55), reach2) + shake
        "take", "take2":
            var two := kind == "take2"
            if not right and not two:
                return {}
            var reach3 := seg(u, 0.0, 0.45) * (1.0 - seg(u, 0.5, 1.0) * 0.8)
            var grip := seg(u, 0.32, 0.5)
            _fingers(q, 0.12 + 0.6 * grip)
            q["wrist_pitch"] = lerpf(48.0, 25.0, reach3)
            q["wrist_roll"] = (-20.0 if two else -8.0) * side
            q["wrist_yaw"] = (-18.0 if two else 0.0) * side
            var goal := _target + Vector3(0.07 * side if two else 0.0, -0.04, 0.05)
            var back := Vector3(0.1 * side if two else 0.1, -0.15, -0.38)
            var at := idle.lerp(goal, reach3)
            q["pos"] = at.lerp(back, seg(u, 0.5, 0.86))
        "vomit_floor":
            var bow := seg(u, 0.05, 0.3) * (1.0 - seg(u, 0.82, 1.0))
            var h := _heave(u)
            q["wrist_pitch"] = lerpf(48.0, -12.0, bow)
            q["wrist_roll"] = 18.0 * side * bow
            q["wrist_yaw"] = -10.0 * side * bow
            _fingers(q, 0.35 + 0.35 * h)
            q["pos"] = idle.lerp(Vector3(0.2 * side, -0.27 - 0.02 * h, -0.43), bow)
        "wash":
            var turn_on := seg(u, 0.0, 0.1) * (1.0 - seg(u, 0.14, 0.22))
            var turn_off := seg(u, 0.84, 0.9) * (1.0 - seg(u, 0.95, 1.0))
            var rub := seg(u, 0.18, 0.26) * (1.0 - seg(u, 0.7, 0.76))
            var shake2 := seg(u, 0.72, 0.76) * (1.0 - seg(u, 0.82, 0.86))
            var tap := Vector3(-0.08, -0.12, -0.46)
            var mid := Vector3(0.03 * side + sin(t * 13.0) * 0.022 * side, -0.2 + cos(t * 13.0) * 0.008, -0.4)
            var shp := Vector3(0.1 * side, -0.16 + sin(t * 38.0) * 0.025, -0.4)
            var pos: Vector3 = idle.lerp(mid, rub).lerp(shp, shake2)
            if right:
                pos = pos.lerp(tap, maxf(turn_on, turn_off))
            q["pos"] = pos
            var laced := 0.45 + 0.1 * sin(t * 13.0 + side)
            _fingers(q, lerpf(0.2, laced, rub))
            q["wrist_yaw"] = lerpf(float(p["wrist_yaw"]), -26.0 * side, rub)
            q["wrist_roll"] = lerpf(float(p["wrist_roll"]), 45.0 * side, rub)
            q["wrist_pitch"] = lerpf(float(p["wrist_pitch"]), 20.0, rub) + sin(t * 40.0) * 28.0 * shake2
            if right and maxf(turn_on, turn_off) > 0.01:
                var tw := maxf(turn_on, turn_off)
                q["wrist_roll"] = lerpf(float(q["wrist_roll"]), -50.0 + 40.0 * sin(u * 40.0), tw)
                _fingers(q, lerpf(lerpf(0.2, laced, rub), 0.55, tw))
        "belt":
            if not right:
                return {}
            var down := sin(u * PI)
            var open := seg(u, 0.4, 0.48) * (1.0 - seg(u, 0.54, 0.64))
            _fingers(q, 0.75 - 0.8 * open)
            q["wrist_pitch"] = lerpf(48.0, 75.0, down)
            q["wrist_yaw"] = 12.0 * down
            q["wrist_roll"] = -20.0 * down + 10.0 * open
            q["pos"] = idle + Vector3(-0.03, -0.05, 0.06) * down + Vector3(0.0, 0.01, 0.0) * sin(u * 30.0) * open
        "watch":
            if right:
                _fingers(q, 0.4)
                q["pos"] = WATCH_RIGHT_POS
                return q
            var sway := Vector3(sin(t * 1.3) * 0.003, sin(t * 1.9) * 0.002, 0.0)
            # hand relaxed and loosely curled, back of the hand up (like
            # reading a wristwatch)
            _fingers(q, 0.45)
            # the root is turned (watch_arm_basis): the forearm lies across
            # the lower-left view, hairy top to the camera; the wrist sits
            # just left of the middle so the mirror panel (right) stays clear
            q["wrist_pitch"] = 4.0
            q["wrist_yaw"] = 0.0
            q["wrist_roll"] = 0.0
            q["pos"] = WATCH_WRIST_POS + sway
        "cycle":
            if not right:
                return {}
            var d := sin(u * PI)
            _fingers(q, 0.5)
            q["wrist_pitch"] = 48.0 + 25.0 * d
            q["pos"] = idle + Vector3(0.04, -0.2, 0.05) * d
    return q

## Bowl-rim hands under the settle camera: they grab the rim, squeeze on each
## heave and slide down out of view as the player straightens.
func _rim_pose(side: float, p: Dictionary) -> Dictionary:
    var u := progress() if kind == "vomit_toilet" else 1.0
    var h := _heave(u) if kind == "vomit_toilet" else 0.0
    var inn := seg(u, 0.12, 0.3) * (1.0 - seg(u, 0.84, 1.0))
    var q := p.duplicate()
    _fingers(q, 0.45 + 0.4 * h)
    q["wrist_pitch"] = 30.0 - 18.0 * h
    q["wrist_yaw"] = -14.0 * side
    q["wrist_roll"] = -24.0 * side
    q["pos"] = Vector3(0.17 * side, lerpf(-0.5, -0.12, inn) - 0.012 * h, -0.3)
    return q

func _ensure_rim_rig() -> void:
    if rim_rig != null or m.settle_camera == null:
        return
    rim_rig = FDKHandsRig.new()
    rim_rig.name = "RimHands"
    rim_rig.set("pose_hook", self)
    m.settle_camera.add_child(rim_rig)
    if m.get("hand_blood_mat") != null:
        FPHandBlood.attach(rim_rig, m.hand_blood_mat)
    rim_rig.visible = false

# --- props --------------------------------------------------------------------------

func _chunk(color: Color, r: float) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    var sm := SphereMesh.new()
    sm.radius = r
    sm.height = r * 1.6
    sm.radial_segments = 6
    sm.rings = 3
    mi.mesh = sm
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = 0.35
    mi.material_override = mat
    return mi

## Flesh falls: into the bowl (toilet) or onto the floor in front of the feet.
func _spill(toilet: bool, n: int) -> void:
    if not m.is_inside_tree():
        return
    var from: Vector3
    var to: Vector3
    if toilet:
        var sc: Camera3D = m.settle_camera
        var fwd := -_settle_base.basis.z
        # 형님 2026-09-30: was spawning right at the camera lens (reads as
        # "falling from the top of the screen"). Start lower and closer --
        # roughly where the mouth/chin would be, below and just in front of
        # the camera -- so it falls from the bottom of the screen into the
        # bowl instead.
        from = sc.global_transform * Vector3(0, -0.16, -0.06)
        to = m.restroom.bowl_center + Vector3.UP * 0.025
    else:
        var cam: Camera3D = m.player.camera
        var fwd2 := -cam.global_basis.z
        fwd2.y = 0.0
        fwd2 = fwd2.normalized() if fwd2.length() > 0.01 else Vector3.FORWARD
        from = cam.global_transform * Vector3(0, -0.13, -0.07)
        to = from + fwd2 * 0.15 + Vector3.DOWN * 3.0
        var q := PhysicsRayQueryParameters3D.create(from, to)
        q.exclude = [m.player.get_rid()]
        var hit: Dictionary = m.get_world_3d().direct_space_state.intersect_ray(q)
        to = hit.position + Vector3.UP * 0.02 if not hit.is_empty() else m.player.global_position + fwd2 * 0.4
    for i in range(n):
        var c := _chunk(FLESH.lerp(Color(0.8, 0.35, 0.3), 0.3 * (i % 3) / 2.0), 0.018 + 0.01 * (i % 3))
        c.name = "Spill"
        m.add_child(c)
        var jit := Vector3(sin(i * 2.3) * 0.05, 0.0, cos(i * 1.7) * 0.05)
        c.global_position = from + jit * 0.3
        var tw := c.create_tween()
        tw.tween_interval(0.04 * i)
        tw.tween_property(c, "global_position", to + jit, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
        tw.tween_interval(3.0 if not toilet else 1.2)
        tw.tween_callback(c.queue_free)

## The handful spills from the fist onto the grate, where the being takes it.
func _pour_teeth() -> void:
    if not m.is_inside_tree() or m.hands_rig == null:
        return
    var hand: Node3D = m.hands_rig.call("get_hand_root", "right")
    var from := hand.global_position + (-hand.global_basis.z) * 0.08
    var to: Vector3 = m.vent.global_position + Vector3(0, -0.03, 0)
    for i in range(_spill_n):
        var c := _chunk(Color(0.93, 0.9, 0.8), 0.009)
        c.name = "PourTooth"
        m.add_child(c)
        var jit := Vector3(sin(i * 3.1) * 0.05, 0.0, cos(i * 2.1) * 0.03)
        c.global_position = from
        var tw := c.create_tween()
        tw.tween_interval(0.025 * i)
        tw.tween_property(c, "global_position", to + jit, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
        tw.tween_interval(0.35)
        tw.tween_callback(c.queue_free)

func _ensure_stream() -> void:
    if _stream != null or not m.is_inside_tree():
        return
    _stream = MeshInstance3D.new()
    _stream.name = "TapStream"
    var cy := CylinderMesh.new()
    cy.top_radius = 0.007
    cy.bottom_radius = 0.011
    cy.height = 0.2
    cy.radial_segments = 6
    _stream.mesh = cy
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.75, 0.85, 0.95, 0.55)
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.roughness = 0.05
    _stream.material_override = mat
    m.add_child(_stream)
    _stream.global_position = Vector3(-FPRestroom.HALF.x + 0.12, 0.8, -0.35)
    _stream.visible = false

func _update_stream(u: float) -> void:
    if _stream == null:
        return
    var on := kind == "wash" and u > 0.12 and u < 0.88 and not cancelled
    _stream.visible = on
    if on:
        _stream.scale = Vector3(1.0 + 0.15 * sin(t * 50.0), 1.0, 1.0 + 0.15 * cos(t * 47.0))
