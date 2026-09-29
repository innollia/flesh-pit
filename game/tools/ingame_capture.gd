extends SceneTree

## In-game captures of the main/art models wired into main.tscn. Run WINDOWED
## with the movie writer, one shot per run:
##   Godot_console --path game --windowed --resolution 1280x720
##     --write-movie captures/ingame/<shot>/f.png --fixed-fps 10
##     --quit-after <N> --script res://tools/ingame_capture.gd -- <shot>
## Shots: restroom, vent, mirror, blender, rest_point, ending.

var _main: Node3D
var _shot := "restroom"
var _frame := 0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot = args[0]
	_main = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)

func _pose(pos: Vector3, yaw: float, pitch: float = 0.0) -> void:
	var p = _main.player
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.set("_yaw", yaw)
	p.set("_pitch", pitch)
	p.rotation.y = yaw
	p.camera_pivot.rotation.x = pitch

## Yaw/pitch that aim the camera from `eye` at `target`.
func _aim(eye: Vector3, target: Vector3) -> Vector2:
	var d := (target - eye).normalized()
	return Vector2(atan2(-d.x, -d.z), asin(clampf(d.y, -1.0, 1.0)))

func _eye_offset() -> float:
	return _main.player.camera.global_position.y - _main.player.global_position.y

func _look(pos: Vector3, target: Vector3) -> void:
	var a := _aim(pos + Vector3(0, _eye_offset(), 0), target)
	_pose(pos, a.x, a.y)

func _dig_tunnel() -> void:
	var t = _main.terrain
	for zi in range(9):
		for xi in range(-1, 2):
			for yi in range(0, 4):
				t.dig_at(Vector3(xi * 0.5 + 0.25, yi * 0.5 + 0.25, 1.9 + zi * 0.5), 1.0)
	t.remesh_all()

func _setup() -> void:
	var m = _main
	var prog: FPProgression = m.progression
	m.finish_opening()
	match _shot:
		"restroom":
			m.restroom.set_door_open(false, true)
			_pose(m.START_POS, m.START_YAW, m.START_PITCH)
		"vent":
			m.restroom.set_door_open(false, true)
			prog.teeth = 40
			m.restroom.set_tank_open(true, true)
			prog.teeth_in_hand = 8
			m.use_vent()
			m.place_teeth_at_vent()
			_look(Vector3(0.7, 0.95, 0.2), m.vent.global_position + Vector3(0, 0.02, 0))
		"mirror":
			m.restroom.set_door_open(false, true)
			_look(Vector3(-0.55, 0.95, -0.3), m.mirror_point() + Vector3(0, -0.25, 0))
		"blender":
			m.restroom.set_door_open(true, true)
			_dig_tunnel()
			prog.grant_item("blender")
			m.equip_tool("blender")
			m.toggle_carry()
			m.carried_flesh = 26.0
			m.blender_charge = 1.0
			for pool in [FPProgression.COMMON, "core", "mantle", "surface"]:
				prog.mutation_tree.add_points(pool, 9)
			_pose(Vector3(0.0, 0.95, 3.2), PI, deg_to_rad(-12.0))
		"rest_point":
			var r: Vector3 = m.rest_points[0]
			_pose(r + Vector3(0, -0.2, 1.6), 0.0, deg_to_rad(-8.0))
		"ending":
			m.reach_ending()
	m.apply_atmosphere_now()

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_setup()
	if _frame > 2 and _shot == "rest_point":
		var r: Vector3 = _main.rest_points[0]
		_pose(r + Vector3(0, -0.2, 1.6), 0.0, deg_to_rad(-8.0))
	if _frame > 2 and _shot == "blender":
		_main.carried_flesh = 26.0
	return false