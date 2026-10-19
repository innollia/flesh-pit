extends Node3D

## The player's own legs seen looking down (2026-10-19 play: squeezing
## through flesh needs a body that ducks and twists, so the legs must be
## really there). Same proportions and skin as the mirror body's legs
## (fp_mirror_body.gd), built here so the approved mirror body is untouched.
## Origin = centre of the waist at belt height (as fp_belt.gd); the player
## faces -Z. Thighs, shins and feet are separate pivots: the knees bend so
## the feet stay on the floor however low the waist sits, the legs step with
## the walk, and a twisted body (squeezing sideways through a narrow gap)
## swings its hips, turns its knees in and crosses its steps.
## Public: set_pose(waist_above_feet, walk_phase, walk_weight, twist).

const K := preload("res://main/art/fp_art_kit.gd")
## Same skin as the first-person hands (fdk_hands_rig skin_color).
const SKIN := Color(0.88, 0.72, 0.62)
const SKIN_D := Color(0.8, 0.64, 0.55)
const THIGH := 0.39
const SHIN := 0.41
const ANKLE := 0.06 ## ankle pivot over the sole
const HIP := Vector3(0.087, -0.08, 0.0) ## hip pivot from the waist (x per side)
const STRIDE := 0.16

var _turn: Node3D
var _hips: Node3D
var _thigh := {}
var _shin := {}
var _foot := {}
var _skin_mat: Material

func _ready() -> void:
	_skin_mat = FDKSkinMaterial.make() # the hands' and belly's skin (fp_belt.gd)
	# built facing +Z like the mirror body, then turned to face -Z
	_turn = Node3D.new()
	_turn.name = "Turn"
	_turn.rotation.y = PI
	add_child(_turn)
	_hips = Node3D.new()
	_hips.name = "Hips"
	_turn.add_child(_hips)
	for sx in [-1, 1]:
		var s := "r" if sx > 0 else "l"
		var thigh := _pivot(_hips, "Thigh_" + s, Vector3(sx * HIP.x, HIP.y, HIP.z))
		var st := K.begin()
		var tr: Array = []
		for r in [[-0.12, 0.084, 0.086, 0.09, 0.0], [-0.2, 0.078, 0.082, 0.076, 0.012], [-0.32, 0.062, 0.066, 0.058, 0.02], [-0.42, 0.048, 0.05, 0.044, 0.025], [-0.47, 0.042, 0.046, 0.038, 0.03]]:
			tr.append(_ring(r[0] + 0.08, 0.0, r[1], r[2], r[3], 8, r[4]))
		# closed at the hip so a swung thigh never shows its open top
		FDKLowPoly.loft(st, tr, [SKIN, SKIN, SKIN, SKIN_D], true, false)
		K.add_mesh(thigh, "Thigh", K.finish(st, 30.0), _skin_mat)
		var shin := _pivot(thigh, "Shin_" + s, Vector3(0.0, -THIGH, 0.0))
		st = K.begin()
		var sr: Array = []
		for r in [[-0.47, 0.042, 0.046, 0.038, 0.03], [-0.53, 0.046, 0.04, 0.056, 0.005], [-0.62, 0.05, 0.04, 0.066, -0.01], [-0.72, 0.036, 0.034, 0.044, -0.004], [-0.82, 0.026, 0.026, 0.028, 0.0], [-0.88, 0.028, 0.027, 0.03, 0.0]]:
			sr.append(_ring(r[0] + 0.47, 0.0, r[1], r[2], r[3], 8, r[4] - 0.03))
		FDKLowPoly.loft(st, sr, [SKIN, SKIN, SKIN, SKIN, SKIN_D], false, false)
		# knee and ankle joints: the bent leg keeps a closed, round joint
		K.blob(st, Transform3D.IDENTITY, Vector3(0, 0.0, 0.0), Vector3(0.05, 0.05, 0.052), 0.05, 61, SKIN, SKIN_D)
		K.blob(st, Transform3D.IDENTITY, Vector3(0, -SHIN, -0.01), Vector3(0.03, 0.03, 0.032), 0.05, 62, SKIN_D, SKIN)
		K.add_mesh(shin, "Shin", K.finish(st, 30.0), _skin_mat)
		var foot := _pivot(shin, "Foot_" + s, Vector3(0.0, -SHIN, 0.0))
		st = K.begin()
		K.tube(st, Transform3D.IDENTITY, [Vector3(0, 0.0, -0.03), Vector3(sx * 0.002, -0.025, 0.03), Vector3(sx * 0.007, -0.04, 0.12)], [0.032, 0.036, 0.026], 6, [SKIN_D, SKIN, SKIN], true, 0.65)
		K.add_mesh(foot, "Foot", K.finish(st, 30.0), _skin_mat)
		_thigh[s] = thigh
		_shin[s] = shin
		_foot[s] = foot
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_pose(0.95, 0.0, 0.0, 0.0)

func _pivot(parent: Node3D, n: String, at: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = n
	p.position = at
	parent.add_child(p)
	return p

## Elliptical ring at height y (front depth zf, back depth zb), as the mirror body.
func _ring(y: float, cx: float, hw: float, zf: float, zb: float, n: int, cz: float = 0.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var z := sin(a)
		out.append(Vector3(cx + cos(a) * hw, y, cz + z * (zf if z > 0.0 else zb)))
	return out

## waist_above_feet: belt height over the soles (0.95 standing, lower when
## crouching or ducking). walk_phase/walk_weight: the player's bob phase and
## 0..1 walking. twist: 0..1 how sideways the body is squeezing.
func set_pose(waist_above_feet: float, walk_phase: float, walk_weight: float, twist: float) -> void:
	var w := clampf(walk_weight, 0.0, 1.0)
	var tw := clampf(twist, 0.0, 1.0)
	var step := sin(walk_phase * 0.5)
	# the twisted body worms on: hips swing round, knees turn in
	_hips.rotation = Vector3(0.0, step * 0.55 * tw * maxf(w, 0.35), 0.0)
	var hip_h := waist_above_feet + HIP.y - ANKLE
	var bend := clampf((0.95 - waist_above_feet) / 0.48, 0.0, 1.0)
	for s in ["r", "l"]:
		var sx := 1.0 if s == "r" else -1.0
		var ph := step * (1.0 if s == "r" else -1.0)
		# foot target from the hip: under it, a little forward when crouched,
		# swinging with the stride, lifting on the forward swing
		var fwd := 0.04 + bend * 0.14 + ph * STRIDE * w * (1.0 - bend * 0.5)
		var lift := maxf(0.0, cos(walk_phase * 0.5 + (0.0 if s == "r" else PI))) * 0.07 * w
		_leg_ik(s, Vector2(fwd, -(hip_h - lift)))
		# cross-steps and knees in when twisted
		var thigh: Node3D = _thigh[s]
		thigh.rotate_object_local(Vector3.FORWARD, -sx * 0.22 * tw)
		thigh.position.x = sx * HIP.x * (1.0 - 0.45 * tw)

## Two-bone leg in the hip's (forward z, up y) plane: the knee bends forward,
## the foot stays flat.
func _leg_ik(s: String, target: Vector2) -> void:
	var d := clampf(target.length(), absf(THIGH - SHIN) + 0.01, THIGH + SHIN - 0.001)
	var aim := atan2(target.x, -target.y) # 0 = straight down, + = forward
	var hip_a := acos(clampf((THIGH * THIGH + d * d - SHIN * SHIN) / (2.0 * THIGH * d), -1.0, 1.0))
	var knee_a := acos(clampf((THIGH * THIGH + SHIN * SHIN - d * d) / (2.0 * THIGH * SHIN), -1.0, 1.0))
	var thigh_fwd := aim + hip_a
	var bend := PI - knee_a
	(_thigh[s] as Node3D).basis = Basis(Vector3.RIGHT, -thigh_fwd)
	(_shin[s] as Node3D).basis = Basis(Vector3.RIGHT, bend)
	(_foot[s] as Node3D).basis = Basis(Vector3.RIGHT, thigh_fwd - bend)

func capture_setup() -> Dictionary:
	set_pose(0.95, 1.2, 1.0, 0.0)
	var b: Node3D = get_script().new()
	add_child(b)
	b.position = Vector3(0.6, 0, 0)
	b.call_deferred("set_pose", 0.55, 2.0, 1.0, 0.0)
	var c: Node3D = get_script().new()
	add_child(c)
	c.position = Vector3(-0.6, 0, 0)
	c.call_deferred("set_pose", 0.7, 2.6, 1.0, 1.0)
	return {"cam_pos": Vector3(0.4, -0.1, -1.9), "look_at": Vector3(0, -0.5, 0), "env": "lit", "fov": 50.0}
