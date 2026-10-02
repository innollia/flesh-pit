extends Node3D

## Photo A: broad two-door mirror cabinet above a wall-mounted basin.
const K := preload("res://main/art/fp_art_kit.gd")
const LEAF_W := 0.40
const HH := 0.60
const CY := 1.78
var door_pivot: Node3D
var door_pivot_right: Node3D
var door_surface: Node3D
var door_surface_right: Node3D
var cabinet_open := false
var _glow: MeshInstance3D

func _ready() -> void:
	var chrome := K.mat("tex_chrome_128.png", 0.45, false)
	var ceramic := K.mat("tex_ceramic_128.png", 0.3, false)
	var st := K.begin()
	var white := Color(0.94, 0.94, 0.91)
	# Two mirror doors reach from over the toilet to the shower corner.
	var cabinet_center := -0.60
	for xx in [-0.81, 0.81]:
		K.rbox(st, K.T(Vector3(xx + cabinet_center, CY, 0.11)), Vector3(0.012, HH, 0.11), 0.004, white)
	for yy in [CY - HH, CY, CY + HH]:
		K.rbox(st, K.T(Vector3(cabinet_center, yy, 0.11)), Vector3(0.80, 0.012, 0.10), 0.004, white)
	K.rbox(st, K.T(Vector3(cabinet_center, CY, 0.025)), Vector3(0.80, HH, 0.012), 0.004, white)
	for xx in [-0.32, 0.40]:
		K.lathe(st, K.T(Vector3(xx, CY - HH + 0.014, 0.10)), [Vector2(0, 0), Vector2(0.025, 0), Vector2(0.025, 0.14), Vector2(0.01, 0.15), Vector2(0, 0.15)], 6, [Color(0.8, 0.85, 0.78)])
	K.add_mesh(self, "StorageCabinet", K.finish(st), ceramic)
	door_pivot = K.pivot(self, "MirrorDoorHinge", Vector3(cabinet_center - 0.80, 0, 0.235))
	door_surface = K.pivot(door_pivot, "MirrorDoor", Vector3(LEAF_W, 0, 0))
	door_pivot_right = K.pivot(self, "MirrorDoorHingeRight", Vector3(cabinet_center + 0.80, 0, 0.235))
	door_surface_right = K.pivot(door_pivot_right, "MirrorDoorRight", Vector3(-LEAF_W, 0, 0))
	for leaf in [door_surface, door_surface_right]:
		st = K.begin()
		for xx in [-LEAF_W, LEAF_W]:
			K.rbox(st, K.T(Vector3(xx, CY, 0)), Vector3(0.007, HH, 0.009), 0.002, Color(0.76, 0.78, 0.78))
		for yy in [CY - HH, CY + HH]:
			K.rbox(st, K.T(Vector3(0, yy, 0)), Vector3(LEAF_W, 0.007, 0.009), 0.002, Color(0.76, 0.78, 0.78))
		K.add_mesh(leaf, "MirrorFrame", K.finish(st), chrome)
		st = K.begin()
		K.quad(st, Transform3D.IDENTITY, Vector3(-LEAF_W, CY-HH, 0.01), Vector3(LEAF_W, CY-HH, 0.01), Vector3(LEAF_W, CY+HH, 0.01), Vector3(-LEAF_W, CY+HH, 0.01), Vector3.BACK, Color(0.7, 0.76, 0.8))
		K.add_mesh(leaf, "Glass", K.finish(st), chrome)
	# Full ledge follows the left wall under the cabinet as in Photo A.
	st = K.begin()
	K.rbox(st, K.T(Vector3(cabinet_center, 0.92, 0.07)), Vector3(0.80, 0.016, 0.075), 0.008, white)
	K.add_mesh(self, "WallLedge", K.finish(st), ceramic)
	# Tall single-lever faucet, not separate knob cylinders.
	st = K.begin()
	var c := Color(0.84, 0.85, 0.85)
	K.lathe(st, K.T(Vector3(0, 0.86, 0.10)), [Vector2(0.025, 0), Vector2(0.023, 0.20), Vector2(0.02, 0.24), Vector2(0, 0.245)], 8, [c])
	K.tube(st, Transform3D.IDENTITY, [Vector3(0, 1.04, 0.10), Vector3(0, 1.05, 0.21), Vector3(0, 1.025, 0.24)], [0.014, 0.013, 0.01], 6, [c])
	K.rbox(st, K.T(Vector3(0, 1.11, 0.12)), Vector3(0.018, 0.006, 0.045), 0.004, c)
	K.add_mesh(self, "Chrome", K.finish(st), chrome)
	# Bowl projects into the room and has a closed rounded ceramic underside.
	st = K.begin()
	var cw := Color(0.96, 0.96, 0.94)
	var ci := Color(0.84, 0.85, 0.84)
	K.lathe(st, K.T(Vector3(0, 0.34, 0.19), Vector3.ZERO, Vector3(1, 1, 0.8)), [Vector2(0, 0), Vector2(0.12, 0.09), Vector2(0.23, 0.28), Vector2(0.33, 0.50), Vector2(0.34, 0.54), Vector2(0.31, 0.545)], 12, [cw, cw, cw, cw, ci])
	K.lathe(st, K.T(Vector3(0, 0.34, 0.19), Vector3(180, 0, 0), Vector3(1, 1, 0.8)), [Vector2(0, -0.40), Vector2(0.13, -0.44), Vector2(0.25, -0.52), Vector2(0.31, -0.545)], 12, [ci, ci, ci])
	K.add_mesh(self, "Basin", K.finish(st), ceramic)

func set_focus(_on: bool) -> void:
	pass

func mirror_center() -> Vector3:
	return Vector3(-0.6, CY, 0.25)

func reflection_surface() -> Node3D:
	return door_surface

func toggle_cabinet() -> void:
	cabinet_open = not cabinet_open

func _process(delta: float) -> void:
	if door_pivot != null:
		door_pivot.rotation.y = move_toward(door_pivot.rotation.y, -1.25 if cabinet_open else 0.0, delta * 2.2)
		door_pivot_right.rotation.y = move_toward(door_pivot_right.rotation.y, 1.25 if cabinet_open else 0.0, delta * 2.2)

func capture_setup() -> Dictionary:
	return {"cam_pos": Vector3(1.3, 1.5, 2.5), "look_at": Vector3(0, 1.2, 0.2), "env": "restroom", "fov": 55.0}
