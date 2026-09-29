extends Node3D

## Tumor codex (docs/spec/03-restroom.md 10): every tumor settled whole in
## the toilet makes the vent being send down a crayon drawing of it, which
## ends up taped to the restroom wall. Terrible drawings on purpose: wobbly
## waxy strokes, wrong proportions. One sheet per kind, in codex order.
## Origin = wall surface, sheets face +Z. Public: set_found(kinds: Array),
## found_count(), sheet(kind) -> Node3D.

const K := preload("res://main/art/fp_art_kit.gd")
const KINDS: Array[String] = ["core_knot", "core_bulb", "mantle_coil", "mantle_sac", "surface_star", "surface_ear"]
const W := 0.21
const H := 0.28

var _sheets := {}

func _ready() -> void:
	for i in range(KINDS.size()):
		var n := _build_sheet(KINDS[i], i)
		n.position = Vector3(-0.55 + (i % 3) * 0.3 + K.h(i, 1) * 0.04, -0.32 * floorf(i / 3.0) + K.h(i, 2) * 0.03, 0.004 + i * 0.0005)
		n.rotation.z = (K.h(i, 3) - 0.5) * 0.22
		n.visible = false
		_sheets[KINDS[i]] = n

func set_found(kinds: Array) -> void:
	for k in _sheets.keys():
		(_sheets[k] as Node3D).visible = k in kinds

func found_count() -> int:
	var n := 0
	for s in _sheets.values():
		if (s as Node3D).visible:
			n += 1
	return n

func sheet(kind: String) -> Node3D:
	return _sheets.get(kind, null)

## A crayon stroke: a flat, slightly wobbly tube pressed on the paper.
static func _stroke(st: SurfaceTool, pts: Array, col: Color, r: float = 0.0035, seed: int = 0) -> void:
	var wob: Array = []
	for i in range(pts.size()):
		var p: Vector2 = pts[i]
		wob.append(Vector3(p.x + (K.h(seed, i, 1) - 0.5) * 0.004, p.y + (K.h(seed, i, 2) - 0.5) * 0.004, 0.003))
	var radii: Array = []
	for i in range(wob.size()):
		radii.append(r * (0.7 + 0.5 * K.h(seed, i, 3)))
	K.tube(st, Transform3D.IDENTITY, wob, radii, 4, [col], true, 0.35)

static func _circle(c: Vector2, rx: float, ry: float, n: int = 14, start: float = 0.0, turns: float = 1.08) -> Array:
	var out: Array = []
	for i in range(n + 1):
		var a := start + TAU * turns * float(i) / n
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out

func _build_sheet(kind: String, idx: int) -> Node3D:
	var n := Node3D.new()
	n.name = "Sheet_" + kind
	add_child(n)
	var st := K.begin()
	var paper := Color(0.96, 0.94, 0.86)
	K.quad(st, Transform3D.IDENTITY, Vector3(-W * 0.5, -H * 0.5, 0), Vector3(W * 0.5, -H * 0.5, 0), Vector3(W * 0.5, H * 0.5, 0), Vector3(-W * 0.5, H * 0.5, 0), Vector3.BACK, paper)
	# a strip of tape at the top
	K.quad(st, Transform3D.IDENTITY, Vector3(-0.03, H * 0.5 - 0.015, 0.001), Vector3(0.03, H * 0.5 - 0.012, 0.001), Vector3(0.03, H * 0.5 + 0.012, 0.001), Vector3(-0.03, H * 0.5 + 0.009, 0.001), Vector3.BACK, Color(0.92, 0.88, 0.7))
	K.add_mesh(n, "Paper", K.finish(st, 1.0), K.mat("tex_ceramic_64.png", 0.05, false))
	st = K.begin()
	var red := Color(0.75, 0.12, 0.14)
	var pink := Color(0.92, 0.45, 0.55)
	var ink := Color(0.12, 0.1, 0.1)
	var s := idx * 17
	match kind:
		"core_knot": # smooth ball with teeth and a hair tuft
			_stroke(st, _circle(Vector2(0, -0.01), 0.07, 0.065), pink, 0.004, s)
			for i in range(4):
				var x := -0.035 + i * 0.022
				_stroke(st, [Vector2(x, 0.0), Vector2(x + 0.006, -0.018), Vector2(x + 0.012, 0.0)], Color(0.95, 0.95, 0.9), 0.003, s + i)
			_stroke(st, [Vector2(0.02, 0.05), Vector2(0.035, 0.08), Vector2(0.02, 0.1), Vector2(0.045, 0.11), Vector2(0.03, 0.13)], ink, 0.0025, s + 9)
		"core_bulb": # see-through water balloon, something floating
			_stroke(st, _circle(Vector2(0, 0), 0.075, 0.085, 16), Color(0.55, 0.7, 0.85), 0.004, s)
			_stroke(st, _circle(Vector2(0.01, -0.01), 0.02, 0.012, 8), ink, 0.003, s + 3)
			_stroke(st, [Vector2(-0.01, 0.085), Vector2(0.0, 0.1), Vector2(0.01, 0.085)], Color(0.55, 0.7, 0.85), 0.003, s + 4)
		"mantle_coil": # muscle yarn ball
			var pts: Array = []
			for i in range(40):
				var t := float(i) / 39.0
				var a := t * TAU * 4.5
				pts.append(Vector2(cos(a) * 0.075 * (0.3 + 0.7 * t), sin(a) * 0.06 * (0.3 + 0.7 * t)))
			_stroke(st, pts, Color(0.5, 0.25, 0.55), 0.003, s)
			_stroke(st, [Vector2(0.07, 0.0), Vector2(0.09, -0.03), Vector2(0.085, -0.07)], red, 0.003, s + 2)
		"mantle_sac": # pouch with a little hand showing through
			_stroke(st, _circle(Vector2(0, -0.005), 0.07, 0.08, 16), Color(0.55, 0.28, 0.5), 0.004, s)
			_stroke(st, [Vector2(-0.02, -0.03), Vector2(-0.02, 0.01), Vector2(-0.01, 0.03), Vector2(-0.005, 0.0), Vector2(0.002, 0.035), Vector2(0.01, 0.0), Vector2(0.018, 0.03), Vector2(0.025, -0.005), Vector2(0.035, 0.01), Vector2(0.03, -0.03), Vector2(-0.02, -0.03)], pink, 0.0028, s + 5)
		"surface_star": # yellow nerve star with shine marks
			for i in range(7):
				var a := TAU * i / 7.0
				_stroke(st, [Vector2.ZERO, Vector2(cos(a), sin(a)) * 0.05, Vector2(cos(a + 0.2), sin(a + 0.2)) * 0.09], Color(0.95, 0.8, 0.15), 0.0035, s + i)
			for i in range(3):
				var a2 := 0.5 + i * 0.6
				_stroke(st, [Vector2(cos(a2), sin(a2)) * 0.105, Vector2(cos(a2), sin(a2)) * 0.125], Color(0.95, 0.85, 0.4), 0.0025, s + 20 + i)
		"surface_ear": # grape bunch of little ears
			for i in range(7):
				var c := Vector2(-0.04 + (i % 3) * 0.04 + (0.02 if floori(i / 3.0) == 1 else 0.0), 0.045 - floorf(i / 3.0) * 0.04)
				_stroke(st, _circle(c, 0.018, 0.022, 9, 0.8, 0.85), pink, 0.0028, s + i)
				_stroke(st, [c + Vector2(0.004, 0.008), c + Vector2(-0.004, 0.0), c + Vector2(0.003, -0.008)], red, 0.002, s + 30 + i)
	# the being "signs" every sheet with a scribble in the corner
	_stroke(st, [Vector2(0.06, -0.12), Vector2(0.07, -0.108), Vector2(0.078, -0.122), Vector2(0.09, -0.11)], ink, 0.002, s + 99)
	K.add_mesh(n, "Crayon", K.finish(st, 2.0), K.mat("tex_ceramic_64.png", 0.1, false))
	return n

func capture_setup() -> Dictionary:
	set_found(KINDS)
	var st := K.begin()
	K.quad(st, Transform3D.IDENTITY, Vector3(-1, -0.6, -0.002), Vector3(1, -0.6, -0.002), Vector3(1, 0.6, -0.002), Vector3(-1, 0.6, -0.002), Vector3.BACK, Color(0.88, 0.9, 0.91))
	K.add_mesh(self, "CaptureWall", K.finish(st, 3.0), K.mat("tex_tile_wall_128.png", 0.2, false))
	return {"cam_pos": Vector3(-0.25, -0.05, 1.05), "look_at": Vector3(-0.25, -0.05, 0), "env": "restroom", "fov": 50.0}
