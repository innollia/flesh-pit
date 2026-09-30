extends SceneTree

## In-game captures of the main/art models wired into main.tscn. Run WINDOWED
## with the movie writer, one shot per run:
##   Godot_console --path game --windowed --resolution 1280x720
##     --write-movie captures/ingame/<shot>/f.png --fixed-fps 10
##     --quit-after <N> --script res://tools/ingame_capture.gd -- <shot>
## Shots: restroom, vent, mirror, mirror_look, mirror_belt, mirror_after, blender, rest_point, ending.

var _main: Node3D
var _shot := "restroom"
var _frame := 0
## Extra user args: `ring` forces the interact ring on (with its button
## glyph); `size=WxH` sizes the window (the movie writer records it).
var _ring := false
## `noring` forces it off (for a with/without comparison).
var _noring := false
var _size := Vector2i.ZERO

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot = args[0]
	for a in args:
		if a == "ring":
			_ring = true
		elif a == "noring":
			_noring = true
		elif a.begins_with("size="):
			var wh := a.substr(5).split("x")
			_size = Vector2i(int(wh[0]), int(wh[1]))
	if _size != Vector2i.ZERO:
		DisplayServer.window_set_size(_size)
		get_root().size = _size
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
		"mirror_belt":
			m.restroom.set_door_open(false, true)
			prog.has_belt = true
			_look(Vector3(-0.55, 0.95, -0.3), m.mirror_point() + Vector3(0, -0.25, 0))
			m.open_mirror()
		"mirror_look", "mirror_after":
			m.restroom.set_door_open(false, true)
			# some hairs of every kind so the watch-look arm shows its count
			for pool in [FPProgression.COMMON, "core", "mantle", "surface"]:
				prog.mutation_tree.add_points(pool, 6)
			_look(Vector3(-0.55, 0.95, -0.3), m.mirror_point() + Vector3(0, -0.25, 0))
			m.open_mirror()
		"mirror_hover", "mutate_hover":
			m.restroom.set_door_open(false, true)
			for pool in [FPProgression.COMMON, "core", "mantle", "surface"]:
				prog.mutation_tree.add_points(pool, 6)
			_look(Vector3(-0.62, 0.95, -0.35), m.mirror_point() + Vector3(0, -0.12, 0))
			if _shot == "mutate_hover":
				m.open_mirror()
		"look_down":
			# mut6: bare belly in briefs, belt on (first-person look-down)
			m.restroom.set_door_open(false, true)
			prog.has_belt = true
			_pose(Vector3(0.0, 0.95, 0.4), 0.0, deg_to_rad(-80.0))
		"mirror_corner":
			m.restroom.set_door_open(false, true)
			_look(Vector3(-1.2, 0.0, 0.3), Vector3(-FPRestroom.HALF.x, 1.3, FPRestroom.HALF.z))
		"mirror_corner_back":
			m.restroom.set_door_open(false, true)
			_look(Vector3(-1.2, 0.0, 0.3), Vector3(-FPRestroom.HALF.x, 1.3, -FPRestroom.HALF.z))
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
		"canary_pull":
			m.restroom.set_door_open(false, true)
			_look(Vector3(-0.3, 0.95, -0.2), m.canary_hole_point())
			m.begin_canary_pull()
		"crushed":
			m.restroom.set_door_open(true, true)
			_dig_tunnel()
			_pose(Vector3(0.0, 0.95, 3.2), PI, deg_to_rad(-5.0))
	m.apply_atmosphere_now()

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_setup()
	if _frame > 4 and _shot == "mutate_hover":
		# right hand hovered: its list open, the second row's ghost on the doll
		if _main.mirror.current_part() != "right_hand":
			_main.mirror.focus_part("right_hand")
			_main.mirror.select_candidate(1)
	if _frame == 12 and _shot == "mirror_after":
		_main.mirror.close()
	if _frame == 1 and _size != Vector2i.ZERO:
		DisplayServer.window_set_size(_size)
	if _frame == 3 and (_ring or _noring):
		# Detach the ring from main's per-frame update so it stays lit.
		var r: Control = _main.interact_ring
		_main.interact_ring = null
		r.set("shown", _ring)
	# The movie writer keeps its start size, so a sized run also saves the
	# real viewport itself: <shot>_<W>x<H>.png beside the movie frames.
	if _frame == 25 and _size != Vector2i.ZERO:
		var out := "user://capture_%s%s_%dx%d.png" % [_shot, "_ring" if _ring else ("_noring" if _noring else ""), _size.x, _size.y]
		get_root().get_texture().get_image().save_png(out)
		print("saved ", ProjectSettings.globalize_path(out))
	if _frame > 2 and _shot == "rest_point":
		var r: Vector3 = _main.rest_points[0]
		_pose(r + Vector3(0, -0.2, 1.6), 0.0, deg_to_rad(-8.0))
	if _frame > 2 and _shot == "canary_pull":
		_main.canary_pull_t = 0.75
	if _frame > 2 and _shot == "crushed":
		_main.hazard.health = 25.0
		_main._crush_t = _main.progression.crush_time() * 0.85
	if _frame > 2 and _shot == "blender":
		_main.carried_flesh = 26.0
	return false