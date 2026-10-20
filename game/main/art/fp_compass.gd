extends Node3D

const K := preload("res://main/art/fp_art_kit.gd")

## The compass (docs/spec/07-danger-navigation.md 3): a cheap plastic pocket
## compass clipped to the waist by its ring, taken into the left hand to be
## read (decision 0009). Its one needle always points at the restroom; the
## way out is the other way. Local frame: the dial looks up +Y, the ring
## sticks out at -Z. Dial and needle glow a little so they read in the dark
## flesh. Public: target (world point the needle points at).

var target := Vector3.ZERO
## Chunky: a small dial vanished into a few pixels on screen.
const FACE_R := 0.02
var _needle: Node3D
var _angle := 0.0
var _time := 0.0

func _ready() -> void:
	var plastic := K.mat("tex_fixture_64.png", 0.25, false)
	var st := K.begin()
	# case: a low drum, scratched grey plastic with a lighter bezel
	K.lathe(st, Transform3D.IDENTITY, [Vector2(0.0, -0.002), Vector2(0.024, -0.002), Vector2(0.025, 0.003), Vector2(0.023, 0.0078), Vector2(FACE_R, 0.008), Vector2(0.0, 0.008)], 12, [Color(0.36, 0.36, 0.38), Color(0.55, 0.55, 0.56)])
	# the ring it hangs by, and the knob under it
	K.lathe(st, K.T(Vector3(0, 0.003, -0.026), Vector3(90, 0, 0)), [Vector2(0.0, 0.0), Vector2(0.004, 0.0), Vector2(0.004, 0.005), Vector2(0.0, 0.005)], 6, [Color(0.5, 0.5, 0.52)])
	var ring: Array = []
	for j in range(11):
		var r := TAU * j / 10.0
		ring.append(Vector3(sin(r) * 0.007, 0.003, -0.037 + cos(r) * 0.007))
	K.tube(st, Transform3D.IDENTITY, ring, [0.0015], 4, [Color(0.7, 0.71, 0.72)], false)
	K.add_mesh(self, "Case", K.finish(st, 40.0), plastic)
	# a cheap luminous dial with four ticks: lit, it read as a black blob
	st = K.begin()
	K.lathe(st, K.T(Vector3(0, 0.0082, 0)), [Vector2(0.0, 0.0), Vector2(FACE_R, 0.0), Vector2(0.0, 0.0002)], 12, [Color(0.86, 0.8, 0.62)])
	for i in range(4):
		var tick := Basis(Vector3.UP, i * PI * 0.5)
		K.rbox(st, Transform3D(tick, tick * Vector3(0, 0.0086, -FACE_R + 0.003)), Vector3(0.001, 0.0002, 0.0026), 0.0002, Color(0.18, 0.15, 0.12))
	K.add_mesh(self, "Face", K.finish(st, 40.0), K.glow(Color(0.72, 0.7, 0.66)))
	# the one needle, pointing along -Z, turning about the dial axis
	_needle = K.pivot(self, "Needle", Vector3(0, 0.0092, 0))
	st = K.begin()
	var red := Color(0.95, 0.25, 0.12)
	K.tri(st, Transform3D.IDENTITY, Vector3(-0.003, 0, 0), Vector3(0.003, 0, 0), Vector3(0, 0, -0.0172), Vector3.UP, red)
	K.tri(st, Transform3D.IDENTITY, Vector3(0.002, 0, 0), Vector3(-0.002, 0, 0), Vector3(0, 0, 0.006), Vector3.UP, Color(0.25, 0.22, 0.2))
	K.lathe(st, K.T(Vector3(0, 0.0003, 0)), [Vector2(0.0, 0.0), Vector2(0.002, 0.0), Vector2(0.0, 0.0008)], 6, [Color(0.3, 0.28, 0.26)])
	K.add_mesh(_needle, "Hand", K.finish(st, 40.0), K.glow(Color(1, 1, 1)))

## Needle angle (radians about the dial axis) that points at `target`.
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
