extends Node3D

const K := preload("res://main/art/fp_art_kit.gd")

## The compass (docs/spec/07-danger-navigation.md 3): a cheap plastic
## wristwatch on the left wrist whose only hand is one needle that always
## points at the restroom; the way out is the other way. Local frame: the
## face looks up +Y from the back of the forearm, the strap wraps the arm
## below it. Dial and needle glow a little so they read in the dark flesh.
## Public: target (world point the needle points at).

var target := Vector3.ZERO
## Strap half extents round the forearm, from the watch origin (which sits
## on top of the arm). The arm there is round, about 3 cm across the radius
## (fp_arm_hair.gd forearm just short of the wrist).
const ARM_HALF := Vector2(0.0315, 0.0315)
## A chunky cheap watch: small ones vanished into a few pixels on screen.
const FACE_R := 0.02
var _needle: Node3D
var _angle := 0.0
var _time := 0.0

func _ready() -> void:
	var plastic := K.mat("tex_fixture_64.png", 0.25, false)
	var st := K.begin()
	# strap: a flat band round the arm cross-section, centred under the case
	var band := Color(0.12, 0.1, 0.09)
	var band_edge := Color(0.2, 0.17, 0.15)
	var c := Vector3(0, -ARM_HALF.y, 0)
	var n := 12
	for i in range(n):
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var p0 := c + Vector3(sin(a0) * ARM_HALF.x, cos(a0) * ARM_HALF.y, 0)
		var p1 := c + Vector3(sin(a1) * ARM_HALF.x, cos(a1) * ARM_HALF.y, 0)
		var out := ((p0 + p1) * 0.5 - c).normalized()
		K.quad(st, Transform3D.IDENTITY, p0 + Vector3(0, 0, -0.008), p1 + Vector3(0, 0, -0.008), p1 + Vector3(0, 0, 0.008), p0 + Vector3(0, 0, 0.008), out, band if i % 2 == 0 else band_edge)
	# case: a low drum, scratched grey plastic with a lighter bezel
	K.lathe(st, Transform3D.IDENTITY, [Vector2(0.0, 0.0), Vector2(0.024, 0.0), Vector2(0.025, 0.004), Vector2(0.023, 0.0078), Vector2(FACE_R, 0.008), Vector2(0.0, 0.008)], 12, [Color(0.36, 0.36, 0.38), Color(0.55, 0.55, 0.56)])
	K.add_mesh(self, "Watch", K.finish(st, 40.0), plastic)
	# face: a yellowed disc with four ticks
	st = K.begin()
	K.lathe(st, K.T(Vector3(0, 0.0082, 0)), [Vector2(0.0, 0.0), Vector2(FACE_R, 0.0), Vector2(0.0, 0.0002)], 12, [Color(0.86, 0.8, 0.62)])
	for i in range(4):
		var tick := Basis(Vector3.UP, i * PI * 0.5)
		K.rbox(st, Transform3D(tick, tick * Vector3(0, 0.0086, -FACE_R + 0.003)), Vector3(0.001, 0.0002, 0.0026), 0.0002, Color(0.18, 0.15, 0.12))
	# a cheap luminous dial: in the dark flesh a lit one read as a black blob
	K.add_mesh(self, "Face", K.finish(st, 40.0), K.glow(Color(0.72, 0.7, 0.66)))
	# the one needle, pointing along -Z, turning about the face axis
	_needle = K.pivot(self, "Needle", Vector3(0, 0.0092, 0))
	st = K.begin()
	var red := Color(0.95, 0.25, 0.12)
	K.tri(st, Transform3D.IDENTITY, Vector3(-0.003, 0, 0), Vector3(0.003, 0, 0), Vector3(0, 0, -0.0172), Vector3.UP, red)
	K.tri(st, Transform3D.IDENTITY, Vector3(0.002, 0, 0), Vector3(-0.002, 0, 0), Vector3(0, 0, 0.006), Vector3.UP, Color(0.25, 0.22, 0.2))
	K.lathe(st, K.T(Vector3(0, 0.0003, 0)), [Vector2(0.0, 0.0), Vector2(0.002, 0.0), Vector2(0.0, 0.0008)], 6, [Color(0.3, 0.28, 0.26)])
	K.add_mesh(_needle, "Hand", K.finish(st, 40.0), K.glow(Color(1, 1, 1)))

## Needle angle (radians about the face axis) that points at `target`.
func aim_angle() -> float:
	var local := global_transform.basis.inverse() * (target - global_position)
	return atan2(-local.x, -local.z)

func _process(delta: float) -> void:
	_time += delta
	if not is_visible_in_tree():
		return
	var want := aim_angle()
	if global_position.distance_to(target) < 1.5:
		# standing in the restroom: nothing to point at, it drifts round
		want = _angle + 1.4
	_angle = lerp_angle(_angle, want, 1.0 - exp(-6.0 * delta))
	# a cheap movement: the needle never quite settles
	_needle.rotation.y = _angle + sin(_time * 11.0) * 0.03
