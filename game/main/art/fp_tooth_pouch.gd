extends Node3D

## The tooth pouch (decision 0016): a small hand-sewn drawstring pouch that
## hangs from the front left of the waistband by its cord. Out of the
## restroom the carried teeth ride in it; how full it is shows as one of four
## shapes, never a number: flat and limp when empty, the bottom sagging with
## a few teeth, round when it is well filled, and stuffed with teeth showing
## at the mouth. The stages are looks, not rules (it holds any number).
## Crooked stitches down the side seam and round the hem.
## Origin = the cord's knot at the waistband; the pouch hangs down (-Y) and
## sways with the walk. Visual only.
## Public: set_fill(teeth), fill_stage(), set_walk(0..1), swing().

const K := preload("res://main/art/fp_art_kit.gd")
## Teeth at which the look changes: 1 sags, 9 rounds, 25 shows teeth.
const STAGE_AT := [1, 9, 25]
const CORD := 0.035 ## the cord's length from the knot to the pouch mouth
const W := 0.034 ## half width of a filled pouch
const DEPTH := 0.09 ## mouth to bottom

var _stages: Array[Node3D] = []
var _hang: Node3D
var _stage := -1
var _walk := 0.0
var _swing := 0.0
var _time := 0.0

static func stage_of(teeth: int) -> int:
	var s := 0
	for at in STAGE_AT:
		if teeth >= int(at):
			s += 1
	return s

func _ready() -> void:
	var cloth := K.mat("tissue_cloth_128.png", 0.05, true)
	var cloth_col := Color(0.74, 0.62, 0.44)
	var hem_col := Color(0.52, 0.41, 0.28)
	var cord := Color(0.3, 0.2, 0.12)
	var thread := Color(0.86, 0.3, 0.22)
	# the cord from the waistband, shared by every stage
	var st := K.begin()
	K.tube(st, Transform3D.IDENTITY, [Vector3(0, 0.012, 0.012), Vector3(0, 0.0, -0.004), Vector3(0.002, -CORD * 0.5, -0.006), Vector3(0, -CORD, -0.004)], [0.0035], 4, [cord], false)
	K.blob(st, Transform3D.IDENTITY, Vector3(0, -0.001, -0.004), Vector3(0.007, 0.006, 0.007), 0.3, 71, cord, cord.lightened(0.2))
	K.add_mesh(self, "Cord", K.finish(st, 8.0), K.mat("tex_fixture_64.png", 0.1, true))
	_hang = K.pivot(self, "Hang", Vector3(0, -CORD, -0.004))
	# [half width, half thickness, how far down the widest part sits (0..1), bottom droop]
	var shapes := [
		[W * 0.8, 0.006, 0.55, 0.0],
		[W * 0.9, 0.016, 0.74, 0.008],
		[W, 0.027, 0.6, 0.004],
		[W * 1.08, 0.031, 0.52, 0.004],
	]
	for i in range(shapes.size()):
		var sh: Array = shapes[i]
		var node := K.pivot(_hang, "Stage%d" % i)
		st = K.begin()
		# the sack: a gathered neck under the cord, the belly below it
		var prof: Array = [Vector2(0.0, -DEPTH - float(sh[3]))]
		for k in range(1, 7):
			var t := float(k) / 6.0 # 0 bottom .. 1 mouth
			var y := lerpf(-DEPTH - float(sh[3]), -0.012, t)
			var bulge := sin(clampf((1.0 - t) / maxf(0.05, float(sh[2])), 0.0, 1.0) * PI * 0.5) * sin(clampf(t / maxf(0.05, 1.0 - float(sh[2])), 0.0, 1.0) * PI * 0.5)
			var r := lerpf(0.009, float(sh[0]), bulge)
			prof.append(Vector2(r, y))
		prof.append(Vector2(0.011, -0.006))
		prof.append(Vector2(0.014, 0.0))
		var body := Transform3D(Basis.from_scale(Vector3(1.0, 1.0, float(sh[1]) / float(sh[0]))), Vector3.ZERO)
		K.lathe(st, body, prof, 7, [hem_col, cloth_col, cloth_col, cloth_col.lightened(0.08), cloth_col, hem_col, hem_col, cloth_col], 0.25)
		# the drawstring wound round the neck
		var ring: Array = []
		for a in range(9):
			var ang := float(a) / 8.0 * TAU
			ring.append(Vector3(cos(ang) * 0.012, -0.008 + sin(ang * 2.0) * 0.0015, sin(ang) * 0.012 * float(sh[1]) / float(sh[0])))
		K.tube(st, Transform3D.IDENTITY, ring, [0.0025], 3, [cord], false)
		K.add_mesh(node, "Sack", K.finish(st, 10.0), cloth)
		# crooked hand stitches down the front seam and along the bottom hem
		st = K.begin()
		var zf := -float(sh[1]) - 0.002
		for k in range(6):
			var y0 := -0.02 - float(k) * (DEPTH - 0.03) / 6.0
			var lean := (K.h(k, 17 + i) - 0.5) * 0.008
			var slen := 0.007 + K.h(k, 23) * 0.004
			K.tube(st, Transform3D.IDENTITY, [Vector3(-slen * 0.5 + lean, y0 + (K.h(k, 5) - 0.5) * 0.004, zf * (0.55 + 0.45 * sin(float(k + 1) / 7.0 * PI))), Vector3(slen * 0.5 + lean, y0 - 0.004 + (K.h(k, 6) - 0.5) * 0.004, zf * (0.55 + 0.45 * sin(float(k + 1) / 7.0 * PI)))], [0.0013], 3, [thread], false)
		for k in range(5):
			var x0 := -float(sh[0]) * 0.6 + float(k) * float(sh[0]) * 0.3
			K.tube(st, Transform3D.IDENTITY, [Vector3(x0, -DEPTH - float(sh[3]) + 0.012 + (K.h(k, 31) - 0.5) * 0.004, zf * 0.7), Vector3(x0 + 0.006, -DEPTH - float(sh[3]) + 0.006 + (K.h(k, 32) - 0.5) * 0.004, zf * 0.7)], [0.0013], 3, [thread], false)
		K.add_mesh(node, "Stitches", K.finish(st, 10.0), K.mat("tex_fixture_64.png", 0.1, true))
		if i == 3:
			# stuffed: a few teeth stand out of the gathered mouth
			st = K.begin()
			var enamel := Color(0.9, 0.84, 0.66)
			for k in range(4):
				var ang := float(k) * 1.7 + 0.4
				var at := Vector3(cos(ang) * 0.007, 0.004 + K.h(k, 41) * 0.004, sin(ang) * 0.005)
				K.lathe(st, K.T(at, Vector3((K.h(k, 42) - 0.5) * 50.0, 0.0, (K.h(k, 43) - 0.5) * 50.0)), [Vector2(0.0, -0.005), Vector2(0.0055, -0.003), Vector2(0.0065, 0.003), Vector2(0.003, 0.007), Vector2(0.0, 0.006)], 5, [Color(0.7, 0.55, 0.38), enamel, enamel, enamel])
			K.add_mesh(node, "Teeth", K.finish(st, 40.0), K.mat("tex_ceramic_64.png", 0.5, true))
		node.visible = false
		_stages.append(node)
	set_fill(0)

## Shows the look for this many teeth inside.
func set_fill(teeth: int) -> void:
	var s := stage_of(teeth)
	if s == _stage:
		return
	if _stage >= 0 and s > _stage:
		swing()
	_stage = s
	for i in range(_stages.size()):
		_stages[i].visible = i == s

func fill_stage() -> int:
	return _stage

## 0..1: how fast the body walks; the pouch sways with it.
func set_walk(amount: float) -> void:
	_walk = clampf(amount, 0.0, 1.0)

## A knock (teeth going in): it swings and settles.
func swing() -> void:
	_swing = 1.0

func _process(delta: float) -> void:
	_time += delta
	_swing = maxf(0.0, _swing - delta * 1.4)
	if _hang == null:
		return
	var weight := 1.0 + 0.25 * float(maxi(_stage, 0))
	# it bounces off the hip (outward only, never into the leg) and sways along it
	_hang.rotation.x = absf(sin(_time * 4.5 / weight)) * 0.22 * _walk + absf(sin(_time * 7.0)) * 0.3 * _swing * _swing
	_hang.rotation.z = sin(_time * 4.5 / weight + 0.6) * 0.12 * _walk

func capture_setup() -> Dictionary:
	set_fill(12)
	return {"cam_pos": Vector3(0.05, -0.05, -0.32), "look_at": Vector3(0, -0.07, 0), "env": "lit", "fov": 45.0}
