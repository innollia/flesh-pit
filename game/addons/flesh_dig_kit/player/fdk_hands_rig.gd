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

enum HandState { IDLE, GRAB, TEAR, RELEASE, SLIP }

const GRAB_TIME := 0.32
const TEAR_TIME := 0.34
const RELEASE_TIME := 0.4
## Grip refused (tissue too tough for this hand): reach, close, slip off, spring back.
const SLIP_TIME := 0.5
const SECOND_HAND_DELAY := 0.09
## Idle pose: wrist raised so the BACK of the hand faces the camera and the
## four-finger block + thumb read as a hand silhouette (the old pose showed
## the hand edge-on, like a plank). pitch, yaw, roll, f1, f2, f3, t1, t2, t3, t_opp
static var IDLE_POSE := [48.0, 14.0, -12.0, 12.0, 16.0, 12.0, -6.0, 6.0, 10.0, 0.0]
## 2026-11-03 user: the arms come down a little lower on the screen.
static var IDLE_POS := Vector3(0.16, -0.205, -0.31)

@export var skin_color: Color = Color(0.88, 0.72, 0.62)
@export var palm_color: Color = Color(0.9, 0.68, 0.6)
@export var nail_color: Color = Color(0.95, 0.8, 0.74)
@export var bob_follow: float = 0.9

var state: HandState = HandState.IDLE
## Optional situational-motion driver: shape_pose(rig, side, pose) -> pose.
var pose_hook: Object = null
var mutation: float = 0.0
## 0 = hands free; >0 = carrying a pile of torn flesh (pile size 0..1).
var carry_amount: float = 0.0
## Left hand grips a held one-handed tool (the blender) at HOLD_LEFT_POS,
## low on the left of the screen, instead of following idle/carry/chew.
## Taking it, the empty hand first drops out of view and comes back up
## holding it; putting it away runs the other way. The holder shows the
## tool only while left_grip_shown(), and hangs it on the left wrist so it
## moves, bobs and swings exactly with the hand.
var hold_left: bool = false
## Wrist root of the gripping hand: low left, so the forearm runs in from
## the lower-left corner like the idle arms instead of lying flat across.
static var HOLD_LEFT_POS := Vector3(-0.22, -0.165, -0.37)
## Grip on an upright handle: thumb up (roll past the free wrist limit, as
## a forearm turns), knuckles round the handle, the back of the hand to the
## camera. pitch, yaw, roll, f1, f2, f3, t1, t2, t3, t_opp
static var HOLD_LEFT_POSE := [4.0, -16.0, 88.0, 62.0, 78.0, 56.0, 40.0, 62.0, 62.0, 55.0]
## Wrist roll allowed while the left hand holds a tool (thumb up).
const HOLD_ROLL_LIMIT := 95.0
## Seconds for the empty hand to drop out of view, and to come back up
## with the tool (and the reverse when it is put away).
const GRIP_DROP_TIME := 0.12
const GRIP_RAISE_TIME := 0.26
## Where the hand goes below the frame to take or leave the tool.
const GRIP_DROP := Vector3(-0.04, -0.34, 0.08)
## Both hands grip a two-handed tool (the big saw) by its two upright
## handles. Both empty hands drop out of view together and come up holding
## it; putting it away runs the other way. The holder hangs the tool on the
## RIGHT wrist and shows it only while both_grip_shown(). The two hands take
## mirrored poses and share every offset (bob, aside, hold_shift, press), so
## a rigid tool hung on one wrist stays in the other hand too.
var hold_both: bool = false
## Right wrist root while holding with both hands; the left is its mirror.
## The holder sets x so the finger loops land on the tool's two handles.
var hold_both_pos := Vector3(0.34, -0.205, -0.42)
## Right-hand grip on an upright handle, thumb up (the left mirrors it).
## pitch, yaw, roll, f1, f2, f3, t1, t2, t3, t_opp
static var HOLD_BOTH_POSE := [4.0, 16.0, -88.0, 62.0, 78.0, 56.0, 40.0, 62.0, 62.0, 55.0]
## Shared drop below the frame for the two-handed take (no sideways part,
## so the two hands keep the tool's span while they rise).
const BOTH_DROP := Vector3(0.0, -0.34, 0.08)
## Shared offset of both gripping hands, set by the holder each frame (a saw
## stroke slides the tool, and so both hands, sideways).
var hold_shift: Vector3 = Vector3.ZERO
## 0..1: both hands swing out to the lower sides (looking down at the belt).
## Only the resting hands go aside: a grab, tear or slip comes back in to
## the flesh it works on (looking down at the floor used to tear it with
## both hands swung out below the screen).
var aside: float = 0.0
## The grabbed point (world), set by the game while a grab holds real
## contact (Vector3.INF = none). The leading hand reaches toward it and
## tears from there instead of a fixed spot in front of the camera.
var _reach_world: Vector3 = Vector3.INF
var _short_world: Vector3 = Vector3.INF
var _short_hold: float = 0.0
var _short_amount: float = 0.0
var crush: float = 0.0
var strain: float = 0.0
## Hand root to fingertip in the grab pose (m): the root stops this far short
## of the point so the curled fingers, not the wrist, meet the flesh.
const REACH_TIP := 0.16
## Root depth range in front of the eye for a reach (m), the arm's span.
const REACH_MIN := 0.3
const REACH_MAX := 0.56
const ASIDE_OFFSET := Vector3(0.2, -0.16, 0.14)
## Additions on top of the approved poses. Each is zero unless its game calls
## it, and at zero every pose below is exactly what it was.
## Out of reach: the flesh aimed at is farther than the arm. Both hands stretch
## toward it, fingers open (never the grab's curl, never a clutch at the air),
## and shake a little at full stretch. Only resting hands do it.
const SHORT_HOLD := 0.12 ## seconds the stretch outlives the last on_reach_short call
const SHORT_EASE := 0.22 ## seconds to stretch out / come back
const SHORT_TREMBLE := 0.004
## Crush (0..1): the resting hands are pressed together and toward the eye.
const CRUSH_OFFSET := Vector3(-0.06, 0.0, 0.04)
## Strain (0..1, an overfull stomach): the pull's tremble grows and slows.
const STRAIN_AMP := 1.5
const STRAIN_SLOW := 0.6
## Base/max scale of the carried-pile mesh (built at radius ~0.09/0.05/0.045m
## in _build_pile). 0.42 keeps the base pile within a hand's width and under
## ~20% of screen height at the default FOV/reach_distance; 0.62 is the cap
## for a fully-loaded pile so it never grows unbounded.
const PILE_SCALE_BASE := 0.38
const PILE_SCALE_MAX := 0.56

var _hands: Array = []
## Left-hand grip progress: 0 free, 0..1 the empty hand drops away, 1..2 it
## comes up holding the tool, 2 held. Putting it away goes 2 -> 1 -> 0.
var _grip_t: float = 0.0
## What the left hand holds while _grip_t > 1: 1 the one-handed tool, 2 the
## two-handed tool (with the right hand, _grip_r_t on the same clock).
var _left_kind: int = 0
var _grip_r_t: float = 0.0
var _time: float = 0.0
var _state_time: float = 0.0
var _chew: float = 0.0
## Seconds since the last tear showed the torn chunk; the chunk keeps its own
## clock so a release or new grab during the tear cannot leave it in the fist.
var _chunk_time: float = 0.0
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
    _material = FDKSkinMaterial.make(0.18)
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
    _chunk_time = 0.0
    var chunk: MeshInstance3D = _hands[_lead]["chunk"]
    # hands on a two-handed tool hold no torn chunk (it goes straight down)
    chunk.visible = not both_grip_shown()
    chunk.scale = Vector3.ONE

## The torn chunk mesh of the hand that tore last, while it is shown (else
## null). Games hang visuals off it (strands that snap from the wall).
func torn_chunk() -> Node3D:
    for h in _hands:
        if (h["chunk"] as Node3D).visible:
            return h["chunk"]
    return null

func on_released() -> void:
    if state == HandState.IDLE:
        return
    state = HandState.RELEASE
    _state_time = 0.0
    _chew = 0.0

## The flesh would not give: the fingers close on it, slip off and the hand
## springs back. Games call it when a grab is refused (no chewer signal).
func on_grab_refused() -> void:
    state = HandState.SLIP
    _state_time = 0.0
    _chew = 0.0

## Where the grab touches the flesh (world). Call every frame the contact is
## real; clear_reach_point() when the grab ends. The rig never reads the
## terrain itself.
func set_reach_point(world_pos: Vector3) -> void:
    _reach_world = world_pos

func clear_reach_point() -> void:
    _reach_world = Vector3.INF

func has_reach_point() -> bool:
    return _reach_world != Vector3.INF

## The flesh under the aim is real but beyond the arm (world point). Call
## every frame that holds; the stretch ends by itself SHORT_HOLD after the last
## call. No chewer signal belongs to it and it never closes the fingers.
func on_reach_short(world_pos: Vector3) -> void:
    _short_world = world_pos
    _short_hold = SHORT_HOLD

## 0..1 how far the out-of-reach stretch is out (tests, game cues).
func reach_short_amount() -> float:
    return _short_amount

## 0..1 how close a crush is: the resting hands press together.
func set_crush(amount: float) -> void:
    crush = clampf(amount, 0.0, 1.0)

## 0..1 how overfull the eater is: the pull trembles bigger and slower.
func set_strain(amount: float) -> void:
    strain = clampf(amount, 0.0, 1.0)

## Rig-local root position of a resting hand stretched at the out-of-reach
## point: the arm's full span toward it, the two hands side by side.
func _short_goal(side: float) -> Vector3:
    if _short_world == Vector3.INF or not is_inside_tree():
        return Vector3.INF
    var local := to_local(_short_world)
    var d := local.length()
    if d < 0.01 or local.z > -0.05:
        return Vector3.INF
    return local / d * REACH_MAX + Vector3(0.07 * side, -0.06, 0.0)

## Rig-local root position for a hand reaching the grabbed point, or INF.
func reach_goal(side: float, is_lead: bool) -> Vector3:
    if _reach_world == Vector3.INF or not is_inside_tree():
        return Vector3.INF
    var local := to_local(_reach_world)
    var d := local.length()
    if d < 0.01 or local.z > -0.05:
        return Vector3.INF
    var dir := local / d
    var goal := dir * clampf(d - REACH_TIP, REACH_MIN, REACH_MAX) + Vector3(0.05 * side, -0.06, 0.0)
    if not is_lead:
        # the other hand braces beside it, a little behind
        goal = goal.lerp(Vector3(0.12 * side, -0.1, -0.47), 0.6)
    return goal

## 1 while the hands rest (they may swing aside), 0 while they work flesh.
func _aside_weight(t: float) -> float:
    match state:
        HandState.GRAB, HandState.TEAR, HandState.SLIP:
            return 0.0
        HandState.RELEASE:
            return _ease(t / RELEASE_TIME)
    return 1.0

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

## Show/hide the carried flesh pile (docs/spec/01-body-eating.md: carried pile blocks
## two-handed tools). amount 0 = hands free.
func set_carry(amount: float) -> void:
    carry_amount = clampf(amount, 0.0, 1.0)

func is_carrying() -> bool:
    return carry_amount > 0.001

## True while the left hand has the held tool in it (see hold_left).
func left_grip_shown() -> bool:
    return _grip_t > 1.0 and _left_kind == 1

## True while both hands have the two-handed tool in them (see hold_both).
func both_grip_shown() -> bool:
    return _left_kind == 2 and _grip_t > 1.0 and _grip_r_t > 1.0

func _step_grip(delta: float) -> void:
    var want := 2 if hold_both else (1 if hold_left else 0)
    if _grip_t > 1.0 and want != 0 and want != _left_kind:
        # the other tool goes down out of view first, the new one comes up
        _grip_t -= delta / GRIP_DROP_TIME
        if _grip_t <= 1.0:
            _grip_t = 1.0001
            _left_kind = want
    else:
        _grip_t = _step_one(_grip_t, want != 0, delta)
        if _grip_t <= 1.0:
            _left_kind = want
    # same clock as the left: from empty (0 -> 1) or from a one-handed tool
    # (left 2 -> 1) both hands are out of view after GRIP_DROP_TIME
    _grip_r_t = _step_one(_grip_r_t, hold_both, delta)

## One hand's grip clock (see _grip_t).
func _step_one(t: float, want: bool, delta: float) -> float:
    if want:
        if t < 1.0:
            t = minf(1.0, t + delta / GRIP_DROP_TIME)
            return 1.0001 if t >= 1.0 else t # out of view: the tool is in the hand now
        return minf(2.0, t + delta / GRIP_RAISE_TIME)
    if t > 1.0:
        t -= delta / GRIP_DROP_TIME
        return 0.0 if t <= 1.0 else t # left below the frame; the empty hand comes back
    return 0.0

# --- animation -----------------------------------------------------------

func step(delta: float) -> void:
    if not _built:
        build()
    _time += delta
    _state_time += delta
    _chunk_time += delta
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
        HandState.SLIP:
            if _state_time >= SLIP_TIME:
                state = HandState.IDLE
                _state_time = 0.0
    _short_hold = maxf(0.0, _short_hold - delta)
    _short_amount = move_toward(_short_amount, 1.0 if _short_hold > 0.0 and state == HandState.IDLE else 0.0, delta / SHORT_EASE)
    if _short_amount <= 0.0 and _short_hold <= 0.0:
        _short_world = Vector3.INF
    _wet = maxf(0.0, _wet - delta * 0.08)
    _material.set_shader_parameter("wet", _wet)
    _material.set_shader_parameter("tint", Color(1, 1, 1).lerp(Color(0.78, 0.5, 0.55), mutation))
    _step_grip(delta)
    var k := 1.0 - exp(-delta * 22.0)
    for i in range(_hands.size()):
        var h: Dictionary = _hands[i]
        var delay := 0.0 if i == _lead else SECOND_HAND_DELAY
        var target := _pose_for(h, delay)
        if pose_hook != null:
            target = pose_hook.call("shape_pose", self, float(h["side"]), target)
        _apply_pose(h, target, k)
        var chunk: MeshInstance3D = h["chunk"]
        if chunk.visible:
            if _chunk_time >= TEAR_TIME:
                chunk.visible = false
            else:
                var s := clampf(1.0 - maxf(0.0, _chunk_time - TEAR_TIME * 0.55) / (TEAR_TIME * 0.45), 0.05, 1.0)
                chunk.scale = Vector3.ONE * s
    _pile.visible = is_carrying()
    if _pile.visible:
        # ?뺣떂 寃곗젙 2026-09-29: 湲곕낯 ?붾??????먮컮?μ뿉 ?щ씪媛???뺣룄(?먮옒
        # ?ш린????45%), ?붾㈃ ?믪씠 20% ?댄븯濡??좎?. ???ㅻ㈃ 議곌툑??而ㅼ???        # PILE_SCALE_MAX?먯꽌 ?곹븳.
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
        "wrist_pitch": IDLE_POSE[0] + breathe, "wrist_yaw": IDLE_POSE[1] * side, "wrist_roll": IDLE_POSE[2] * side,
        "f1": IDLE_POSE[3] + breathe, "f2": IDLE_POSE[4], "f3": IDLE_POSE[5],
        "t1": IDLE_POSE[6], "t2": IDLE_POSE[7], "t3": IDLE_POSE[8], "t_opp": IDLE_POSE[9],
        "pos": Vector3(IDLE_POS.x * side, IDLE_POS.y, IDLE_POS.z),
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
    if _left_kind == 2 and (_grip_t if side < 0.0 else _grip_r_t) > 1.0:
        return _pose_both(side)
    if side < 0.0 and _grip_t > 1.0 and _left_kind == 1:
        # fingers wrapped round the upright handle, thumb on top, rising from
        # below the frame while the tool is being taken
        var up := _ease(_grip_t - 1.0)
        return {
            "wrist_pitch": HOLD_LEFT_POSE[0] + breathe * 0.5, "wrist_yaw": HOLD_LEFT_POSE[1], "wrist_roll": HOLD_LEFT_POSE[2],
            "f1": HOLD_LEFT_POSE[3], "f2": HOLD_LEFT_POSE[4], "f3": HOLD_LEFT_POSE[5],
            "t1": HOLD_LEFT_POSE[6], "t2": HOLD_LEFT_POSE[7], "t3": HOLD_LEFT_POSE[8], "t_opp": HOLD_LEFT_POSE[9],
            "pos": _sway(HOLD_LEFT_POS + GRIP_DROP * (1.0 - up), side, aside),
        }
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
            p["t_opp"] = lerpf(idle["t_opp"], 52.0, ct)
            p["t1"] = lerpf(idle["t1"], 30.0, ct)
            p["t2"] = lerpf(idle["t2"], 46.0, ct)
            p["t3"] = lerpf(idle["t3"], 44.0, ct)
            p["wrist_pitch"] = lerpf(idle["wrist_pitch"], 62.0, reach)
            p["wrist_yaw"] = lerpf(idle["wrist_yaw"], 6.0 * side, reach)
            p["wrist_roll"] = lerpf(idle["wrist_roll"], -12.0 * side, reach)
            var goal := reach_goal(side, is_lead)
            if goal == Vector3.INF:
                goal = Vector3(0.12 * side, -0.1, -0.47)
            var pos: Vector3 = (idle["pos"] as Vector3).lerp(goal, reach)
            var r := _chew * reach
            p["f1"] += 14.0 * r
            p["f2"] += 12.0 * r
            p["f3"] += 10.0 * r
            p["t3"] += 14.0 * r
            p["wrist_pitch"] -= 22.0 * r
            pos += Vector3(0.015 * side * r, -0.02 * r, 0.075 * r)
            var amp := (0.0015 + 0.009 * r * r) * reach * (1.0 + STRAIN_AMP * strain)
            var slow := lerpf(1.0, STRAIN_SLOW, strain)
            pos += Vector3(sin(_time * 53.0 * slow + side * 2.0), cos(_time * 61.0 * slow + side), sin(_time * 47.0 * slow)) * amp
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
            # Snap: the fist leaves from where the pull held it and is
            # yanked back hard at once, then eases (fast attack, slow decay;
            # the old sine eased in and first moved the hand forward).
            var jerk := (1.0 - exp(-tt * 14.0)) * exp(-tt * 1.6) / 0.68
            p["wrist_pitch"] = 40.0 - 42.0 * jerk
            p["wrist_yaw"] = 6.0 * side
            p["wrist_roll"] = -14.0 * side - 22.0 * side * jerk
            var lead_scale := 1.0 if is_lead else 0.35
            # torn from where the hand held it, not from a fixed spot
            var held := reach_goal(side, is_lead)
            if held == Vector3.INF:
                held = Vector3(0.135 * side, -0.12, -0.4)
            p["pos"] = held + Vector3(0.035 * side, -0.06, 0.125) * jerk * lead_scale
        HandState.SLIP:
            var st := clampf(t / SLIP_TIME, 0.0, 1.0)
            var lead_k := 1.0 if is_lead else 0.6
            # 0..0.35 reach and close on the wall, 0.35..0.55 slip, then spring back
            var reach := _ease(st / 0.35)
            var slip := _ease((st - 0.35) / 0.2)
            var back := _ease((st - 0.55) / 0.45)
            var close := reach * (1.0 - slip)
            p["f1"] = lerpf(idle["f1"], 58.0, close) - 14.0 * slip * (1.0 - back)
            p["f2"] = lerpf(idle["f2"], 70.0, close) - 10.0 * slip * (1.0 - back)
            p["f3"] = lerpf(idle["f3"], 50.0, close) - 8.0 * slip * (1.0 - back)
            p["t_opp"] = lerpf(idle["t_opp"], 44.0, close)
            p["wrist_pitch"] = lerpf(idle["wrist_pitch"], 58.0, reach * (1.0 - back)) - 18.0 * slip * (1.0 - back)
            var press := Vector3(0.12 * side, -0.1, -0.5)
            var recoil := Vector3(0.17 * side, -0.16, -0.38)
            var pos: Vector3 = (idle["pos"] as Vector3).lerp(press, reach * lead_k)
            pos = pos.lerp(recoil, slip * lead_k).lerp(idle["pos"], back)
            # the strain before it slips: a fine tremble while pressing
            pos += Vector3(sin(_time * 57.0 + side), cos(_time * 49.0), 0.0) * 0.006 * close
            p["pos"] = pos
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
    var rest := _aside_weight(t)
    if _short_amount > 0.0 and state == HandState.IDLE and not is_carrying():
        var far := _short_goal(side)
        if far != Vector3.INF:
            var out := _ease(_short_amount)
            # joints stay the idle pose's: open fingers are what tells it from a grab
            var shake := Vector3(sin(_time * 43.0 + side * 2.0), cos(_time * 37.0 + side), 0.0) * SHORT_TREMBLE * out
            p["pos"] = (p["pos"] as Vector3).lerp(far, out) + shake
            rest *= 1.0 - out # stretched hands do not swing aside
    if crush > 0.0:
        p["pos"] = (p["pos"] as Vector3) + Vector3(CRUSH_OFFSET.x * side, CRUSH_OFFSET.y, CRUSH_OFFSET.z) * crush * rest
    p["pos"] = _sway(p["pos"] as Vector3, side, aside * rest)
    if side < 0.0 and hold_both:
        # both empty hands drop out of view together to take the tool
        p["pos"] = (p["pos"] as Vector3) + BOTH_DROP * _ease(_grip_t)
    elif side > 0.0 and hold_both:
        p["pos"] = (p["pos"] as Vector3) + BOTH_DROP * _ease(_grip_r_t)
    elif side < 0.0 and hold_left:
        # the empty hand drops out of view to take the tool
        p["pos"] = (p["pos"] as Vector3) + GRIP_DROP * _ease(_grip_t)
    return p

## `pos` carried by the walk bob and swung aside by `away` (0..1) for the
## hand on `side`.
func _sway(pos: Vector3, side: float, away: float) -> Vector3:
    var bob: Vector3 = _bob * bob_follow
    return pos + Vector3(bob.y * 0.5 * side - bob.x * 0.6, bob.y * 1.1, 0.0) + Vector3(ASIDE_OFFSET.x * side, ASIDE_OFFSET.y, ASIDE_OFFSET.z) * away

## Both hands on the two upright handles of a two-handed tool, rising from
## below the frame while it is taken. Mirrored angles, and every offset is
## shared (no per-side bob or breathing), so the span between the two grips
## never changes. Working flesh, the tool is pressed in and trembles with
## the strain; it never leaves the hands for the grab/tear poses.
func _pose_both(side: float) -> Dictionary:
    var gt := _grip_t if side < 0.0 else _grip_r_t
    var up := _ease(gt - 1.0)
    var gb: Vector3 = _bob * bob_follow
    var press := 0.0
    if state == HandState.GRAB:
        press = _ease(_state_time / GRAB_TIME)
    elif state == HandState.TEAR:
        press = 1.0 - _ease(_state_time / TEAR_TIME)
    var amp := (0.0012 + 0.006 * _chew * _chew) * press
    var pos := Vector3(hold_both_pos.x * side, hold_both_pos.y, hold_both_pos.z)
    pos += BOTH_DROP * (1.0 - up)
    pos += Vector3(-gb.x * 0.6, gb.y * 1.1 + sin(_time * 1.7) * 0.002, 0.0)
    pos += Vector3(0.0, ASIDE_OFFSET.y, ASIDE_OFFSET.z) * aside
    pos += hold_shift + Vector3(0.0, 0.01, -0.06) * press
    pos += Vector3(sin(_time * 53.0), cos(_time * 61.0), sin(_time * 47.0)) * amp
    return {
        "wrist_pitch": HOLD_BOTH_POSE[0], "wrist_yaw": HOLD_BOTH_POSE[1] * side, "wrist_roll": HOLD_BOTH_POSE[2] * side,
        "f1": HOLD_BOTH_POSE[3], "f2": HOLD_BOTH_POSE[4], "f3": HOLD_BOTH_POSE[5],
        "t1": HOLD_BOTH_POSE[6], "t2": HOLD_BOTH_POSE[7], "t3": HOLD_BOTH_POSE[8], "t_opp": HOLD_BOTH_POSE[9],
        "pos": pos,
    }

## The right wrist's rest basis (rig frame) in the two-handed hold; the left
## is its mirror. Holders place the tool on the right wrist with it.
static func hold_both_wrist_basis() -> Basis:
    return Basis.from_euler(Vector3(deg_to_rad(HOLD_BOTH_POSE[0]), deg_to_rad(HOLD_BOTH_POSE[1]), deg_to_rad(HOLD_BOTH_POSE[2])), EULER_ORDER_YXZ)

func _clamp_joint(joint: String, value: float, wide_roll: bool = false) -> float:
    var lim: Array = LIMITS_DEG[joint]
    if wide_roll and joint == "wrist_roll":
        return clampf(value, -HOLD_ROLL_LIMIT, HOLD_ROLL_LIMIT)
    return clampf(value, lim[0], lim[1])

func _apply_pose(h: Dictionary, target: Dictionary, k: float) -> void:
    var cur: Dictionary = h["pose"]
    var wide := (_grip_t > 0.0) if float(h["side"]) < 0.0 else (_grip_r_t > 0.0)
    for joint in JOINT_NAMES:
        var v: float = lerpf(cur.get(joint, target[joint]), target[joint], k)
        cur[joint] = _clamp_joint(joint, v, wide)
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

## Cross-section of the fused finger block: four fingers side by side, each
## a flat-topped ridge, with grooves between them on the back AND the palm
## side. The grooves are deep and get a darker vertex colour (_tint_points),
## so the block reads as four fingers under the flat PS1 shading and not as
## one plank or a row of saw teeth.
const FINGER_PROFILE := [
    Vector2(1.0, -0.1), Vector2(0.97, 0.6), Vector2(0.9, 1.0), Vector2(0.6, 1.0), Vector2(0.5, 0.2),
    Vector2(0.4, 1.0), Vector2(0.1, 1.0), Vector2(0.0, 0.22), Vector2(-0.1, 1.0), Vector2(-0.4, 1.0),
    Vector2(-0.5, 0.2), Vector2(-0.6, 0.97), Vector2(-0.9, 0.97), Vector2(-0.97, 0.55), Vector2(-1.0, -0.15),
    Vector2(-0.95, -0.75), Vector2(-0.86, -1.0), Vector2(-0.64, -1.0), Vector2(-0.5, -0.3), Vector2(-0.36, -1.0),
    Vector2(-0.14, -1.0), Vector2(0.0, -0.3), Vector2(0.14, -1.0), Vector2(0.36, -1.0), Vector2(0.5, -0.3),
    Vector2(0.64, -1.0), Vector2(0.86, -1.0), Vector2(0.95, -0.75),
]
## How far each fingertip ends behind the middle finger (m): index, middle,
## ring, little. The joints are shared by the fused block, so only the tip
## segment rings move; joint places and lengths stay as they were.
const TIP_SETBACK := [0.006, 0.0, 0.004, 0.016]
## Row centres across the block, in FINGER_PROFILE x times thumb_side.
const FINGER_ROWS := [0.75, 0.25, -0.25, -0.75]

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
    var f_half := [Vector2(0.047, 0.025), Vector2(0.044, 0.0228), Vector2(0.041, 0.0205)]
    var f1 := _joint(wrist, "Finger1", Vector3(0, 0.001, -palm_len))
    _add_mesh(f1, "Seg", _finger_mesh(f_len[0], f_half[0], f_half[1], thumb_side, false))
    var f2 := _joint(f1, "Finger2", Vector3(0, 0, -f_len[0]))
    _add_mesh(f2, "Seg", _finger_mesh(f_len[1], f_half[1], f_half[2], thumb_side, false))
    var f3 := _joint(f2, "Finger3", Vector3(0, 0, -f_len[1]))
    _add_mesh(f3, "Seg", _finger_mesh(f_len[2], f_half[2], f_half[2] * 0.8, thumb_side, true))

    var t_len := [0.04, 0.03, 0.025]
    var t1 := _joint(wrist, "Thumb1", Vector3(thumb_side * 0.036, -0.008, -0.016))
    _add_mesh(t1, "Seg", _thumb_mesh(t_len[0], Vector2(0.019, 0.016), Vector2(0.0145, 0.013), false))
    var t2 := _joint(t1, "Thumb2", Vector3(0, 0, -t_len[0]))
    _add_mesh(t2, "Seg", _thumb_mesh(t_len[1], Vector2(0.0145, 0.013), Vector2(0.013, 0.012), false))
    var t3 := _joint(t2, "Thumb3", Vector3(0, 0, -t_len[1]))
    _add_mesh(t3, "Seg", _thumb_mesh(t_len[2], Vector2(0.013, 0.012), Vector2(0.0125, 0.0115), true))

    var thumb_base := Basis(Vector3.UP, deg_to_rad(-38.0) * thumb_side) * Basis(Vector3.FORWARD, deg_to_rad(-55.0) * thumb_side) * Basis(Vector3.RIGHT, deg_to_rad(-12.0))

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    # A fistful of torn flesh: wider than the fist so it bulges out between
    # fingers and palm on both sides, with ragged shreds hanging under it
    # (the old 3 cm pebble sat hidden inside the fist; 2026-11-03 "뿅").
    var ca := Color(0.62, 0.07, 0.1)
    var cb := Color(0.85, 0.2, 0.2)
    FDKLowPoly.add_blob(st, Vector3.ZERO, Vector3(0.052, 0.04, 0.05), 0.4, 7 + int(side), ca, cb)
    FDKLowPoly.add_blob(st, Vector3(0.038 * side, -0.018, 0.012), Vector3(0.026, 0.024, 0.03), 0.45, 9 + int(side), ca, cb)
    FDKLowPoly.add_blob(st, Vector3(-0.03 * side, -0.03, -0.018), Vector3(0.022, 0.026, 0.024), 0.45, 11 + int(side), ca, cb)
    FDKLowPoly.add_blob(st, Vector3(0.012 * side, -0.058, 0.004), Vector3(0.011, 0.03, 0.012), 0.3, 13 + int(side), ca.darkened(0.2), cb)
    FDKLowPoly.add_blob(st, Vector3(-0.022 * side, -0.05, 0.02), Vector3(0.008, 0.022, 0.009), 0.3, 15 + int(side), ca.darkened(0.2), cb)
    var chunk := _add_mesh(wrist, "TornChunk", FDKLowPoly.with_box_uvs(st.commit(), 24.0))
    chunk.material_override = FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_torn_chunk_128.png", 1.0, false, 0.7, 0.4, 0.18)
    chunk.position = Vector3(0, -0.04, -0.1)
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
    var mi := _add_mesh(self, "CarriedPile", FDKLowPoly.with_box_uvs(st.commit(), 14.0))
    mi.material_override = FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_torn_chunk_128.png", 1.0, false, 0.7, 0.4, 0.18)
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
    # elbow end, the thick of the forearm, the taper, the narrow wrist and a
    # slight flare into the hand; z stays 0.008..0.34 (the Tab pose shoulder
    # lean and the arm hair are placed on that range)
    var rings := [
        FDKLowPoly.ring(prof, 0.34, Vector2(0.036, 0.031), Vector2(0, -0.004)),
        FDKLowPoly.ring(prof, 0.25, Vector2(0.040, 0.034), Vector2(0, -0.0035)),
        FDKLowPoly.ring(prof, 0.15, Vector2(0.036, 0.029), Vector2(0, -0.003)),
        FDKLowPoly.ring(prof, 0.07, Vector2(0.029, 0.022), Vector2(0, -0.0015)),
        FDKLowPoly.ring(prof, 0.03, Vector2(0.0255, 0.0185), Vector2(0, -0.0005)),
        FDKLowPoly.ring(prof, 0.008, Vector2(0.027, 0.019)),
    ]
    FDKLowPoly.loft(st, rings, [skin_color.darkened(0.12), skin_color.darkened(0.09), skin_color.darkened(0.06), skin_color.darkened(0.03), skin_color], true, true)
    return st.commit()

func _palm_mesh(thumb_side: float) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var prof := FDKLowPoly.round_profile(10, 0.35)
    var rings := [
        FDKLowPoly.ring(prof, 0.014, Vector2(0.03, 0.022)),
        FDKLowPoly.ring(prof, -0.022, Vector2(0.043, 0.026), Vector2(thumb_side * 0.002, 0)),
        FDKLowPoly.ring(prof, -0.058, Vector2(0.049, 0.027)),
        FDKLowPoly.ring(prof, -0.086, Vector2(0.05, 0.027), Vector2(0, 0.001)),
        FDKLowPoly.ring(prof, -0.093, Vector2(0.048, 0.026), Vector2(0, 0.001)),
    ]
    FDKLowPoly.loft(st, rings, [skin_color, skin_color, skin_color.lightened(0.04), skin_color], true, true)
    # ball of the thumb: big enough to swallow the root of the first thumb
    # segment, so the thumb grows out of the hand and not out of the wrist
    FDKLowPoly.add_blob(st, Vector3(thumb_side * 0.027, -0.010, -0.026), Vector3(0.021, 0.014, 0.030), 0.18, 3, palm_color, palm_color.darkened(0.08))
    FDKLowPoly.add_blob(st, Vector3(-thumb_side * 0.024, -0.01, -0.035), Vector3(0.013, 0.008, 0.028), 0.15, 5, palm_color, palm_color.darkened(0.06))
    # wrist bone on the little-finger side
    FDKLowPoly.add_blob(st, Vector3(-thumb_side * 0.022, 0.012, 0.008), Vector3(0.008, 0.006, 0.009), 0.1, 7, skin_color.lightened(0.03), skin_color.lightened(0.03))
    return st.commit()

func _finger_mesh(length: float, half_start: Vector2, half_end: Vector2, thumb_side: float, tip: bool) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var prof := PackedVector2Array(FINGER_PROFILE)
    # knuckle bulge at the joint, slimmer in the middle of the segment
    var r0 := FDKLowPoly.ring(prof, 0.007, half_start * Vector2(1.02, 1.07), Vector2(0, half_start.y * 0.03))
    var r1 := FDKLowPoly.ring(prof, -length * 0.5, (half_start + half_end) * 0.5 * Vector2(1.0, 0.97))
    var r2 := FDKLowPoly.ring(prof, -length, half_end * Vector2(1.0, 1.08))
    var rings: Array = [r0, r1, r2]
    if tip:
        var r3 := FDKLowPoly.ring(prof, -length - 0.007, half_end * Vector2(0.9, 0.55), Vector2(0, -0.001))
        # each finger ends at its own length: a stair of four fingertips
        _shape_tip(r1, prof, thumb_side, 0.35)
        _shape_tip(r2, prof, thumb_side, 1.0)
        _shape_tip(r3, prof, thumb_side, 1.0)
        # notch the tip between fingers so the silhouette ends in four
        # rounded fingertips instead of one straight edge
        _notch_tip(r2, prof, 0.003)
        _notch_tip(r3, prof, 0.009)
        rings.append(r3)
        FDKLowPoly.loft(st, rings, [skin_color, skin_color.lightened(0.03), skin_color.lightened(0.03)], false, true)
        for row in range(4):
            _add_nail(st, rings, prof, FINGER_ROWS[row] * thumb_side, 0.005)
    else:
        FDKLowPoly.loft(st, rings, [skin_color, skin_color.lightened(0.02)], false, false)
    # grooves between the fingers sit in shade; the knuckles are a little red
    var marks := {}
    var groove := skin_color.darkened(0.16)
    var knuckle := skin_color.lerp(Color(0.86, 0.56, 0.5), 0.14)
    for ri in range(rings.size()):
        var r: PackedVector3Array = rings[ri]
        for i in range(r.size()):
            var q: Vector2 = prof[i]
            if absf(q.y) < 0.5 and absf(q.x) < 0.9:
                marks[r[i]] = groove
            elif ri == 0 and not tip and q.y > 0.9:
                marks[r[i]] = knuckle
    return _tint_points(st.commit(), marks)

## Repaints the vertices that sit on the given points (the loft helper only
## takes one colour per band).
func _tint_points(mesh: ArrayMesh, marks: Dictionary) -> ArrayMesh:
    var arrays := mesh.surface_get_arrays(0)
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
    for i in range(verts.size()):
        if marks.has(verts[i]):
            cols[i] = marks[verts[i]]
    arrays[Mesh.ARRAY_COLOR] = cols
    var out := ArrayMesh.new()
    out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return out

## Pulls a tip ring back by each finger TIP_SETBACK times `amount`. A groove
## point between two fingers goes with the shorter of the two.
func _shape_tip(r: PackedVector3Array, prof: PackedVector2Array, thumb_side: float, amount: float) -> void:
    for i in range(r.size()):
        var u := prof[i].x * thumb_side
        var back := 0.0
        for row in range(4):
            if absf(u - FINGER_ROWS[row]) <= 0.2501:
                back = maxf(back, TIP_SETBACK[row])
        var p := r[i]
        p.z += back * amount
        r[i] = p

func _notch_tip(r: PackedVector3Array, prof: PackedVector2Array, back: float) -> void:
    for i in range(r.size()):
        var q: Vector2 = prof[i]
        if absf(q.y) < 0.5 and absf(q.x) < 0.9:
            var p := r[i]
            p.z += back
            r[i] = p

## Index of the back-of-finger (flat top) profile point nearest to row `u`.
func _top_index(prof: PackedVector2Array, u: float) -> int:
    var best := -1
    for i in range(prof.size()):
        if prof[i].y > 0.9 and (best < 0 or absf(prof[i].x - u) < absf(prof[best].x - u)):
            best = i
    return best

## Height of the tip mesh surface at depth z along the flat top of row `u`.
func _top_at(rings: Array, top: int, z: float) -> float:
    for i in range(rings.size() - 1):
        var a: Vector3 = (rings[i] as PackedVector3Array)[top]
        var b: Vector3 = (rings[i + 1] as PackedVector3Array)[top]
        if z <= a.z and z >= b.z:
            return lerpf(a.y, b.y, (a.z - z) / maxf(a.z - b.z, 1e-6))
    return ((rings[rings.size() - 1] as PackedVector3Array)[top]).y

## A fingernail on the back of one fingertip: a small plate lifted 0.8 mm off
## the skin, the last 2 mm paler (the free edge). Lives in the tip segment
## mesh, so it bends, bleeds and scales with the finger. Kept two snap cells
## wide: smaller detail crawls on the 130-step view-model grid.
func _add_nail(st: SurfaceTool, rings: Array, prof: PackedVector2Array, u: float, half_width: float) -> void:
    var r1: PackedVector3Array = rings[1]
    var r2: PackedVector3Array = rings[2]
    var top := _top_index(prof, u)
    var z_mid := r2[top].z
    var x := 0.0
    var n := 0
    for i in range(prof.size()):
        if prof[i].y > 0.9 and absf(prof[i].x - u) <= 0.16:
            x += r2[i].x
            n += 1
    x /= float(maxi(n, 1))
    var z_back := z_mid + minf(0.007, (r1[top].z - z_mid) + 0.003)
    var edge := Color(0.97, 0.9, 0.86)
    var rows: Array = []
    for z in [z_back, z_mid, z_mid - 0.002, z_mid - 0.004]:
        var y: float = _top_at(rings, top, z) + 0.0008
        rows.append([Vector3(x - half_width, y, z), Vector3(x + half_width, y, z)])
    for i in range(3):
        var c: Color = nail_color if i < 2 else edge
        FDKLowPoly.add_quad(st, rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0], Vector3.UP, c)

func _thumb_mesh(length: float, half_start: Vector2, half_end: Vector2, tip: bool) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var prof := FDKLowPoly.round_profile(7, 0.25)
    var r0 := FDKLowPoly.ring(prof, 0.006, half_start * 1.12)
    var r1 := FDKLowPoly.ring(prof, -length * 0.5, (half_start + half_end) * 0.5 * Vector2(1.0, 1.05))
    var r2 := FDKLowPoly.ring(prof, -length, half_end)
    if tip:
        # a blunt rounded end, not a spike
        var r3 := FDKLowPoly.ring(prof, -length - 0.006, half_end * Vector2(0.9, 0.8))
        var r4 := FDKLowPoly.ring(prof, -length - 0.009, half_end * Vector2(0.55, 0.5))
        FDKLowPoly.loft(st, [r0, r1, r2, r3, r4], [skin_color, skin_color, skin_color.lightened(0.03), skin_color.lightened(0.03)], true, true)
        # thumbnail: a shallow roof over the top facets of the 7-sided tube
        var top := half_end.y + 0.0008
        var side := half_end.y * 0.72 + 0.0008
        var hw := 0.0065
        var edge := Color(0.97, 0.9, 0.86)
        var zs := [-length + 0.007, -length - 0.003, -length - 0.005]
        var ys := [1.0, 0.86, 0.8]
        for i in range(2):
            var c: Color = nail_color if i == 0 else edge
            for sx in [-1.0, 1.0]:
                FDKLowPoly.add_quad(st,
                    Vector3(0, top * ys[i], zs[i]), Vector3(sx * hw, side * ys[i], zs[i]),
                    Vector3(sx * hw, side * ys[i + 1], zs[i + 1]), Vector3(0, top * ys[i + 1], zs[i + 1]),
                    Vector3(sx * 0.4, 1, 0), c)
    else:
        FDKLowPoly.loft(st, [r0, r1, r2], [skin_color, skin_color], true, false)
    return st.commit()
