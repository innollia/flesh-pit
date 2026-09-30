extends SceneTree

## Belt swap captures, one shot per run (windowed + movie writer):
##   Godot_console --path game --windowed --resolution 1280x720
##     --write-movie <dir>/f.png --fixed-fps 10 --quit-after 30
##     --script res://tools/belt_capture.gd -- <look|aim|after>
## look  = head bowed ~62 deg, belt with knife + blender, empty saw ring
## aim   = aim dot on the blender hook, interact ring lit
## after = the swap done: knife in hand, its ring empty, blender still hung

var _m: Node3D
var _shot := "look"
var _frame := 0
var _yaw := 0.0
var _pitch := -1.08
var _aim := -1

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot = args[0]
	_m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_m)

func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 2:
		_setup()
	if _frame >= 2:
		_hold()
	if _frame == 25:
		var cam: Camera3D = _m.player.camera
		var belt: Node3D = _m.art_hookup.belt
		for i in range(3):
			var hp: Vector3 = belt.call("hook_point", i)
			print("HOOK %d %s behind=%s" % [i, cam.unproject_position(hp), cam.is_position_behind(hp)])
		print("BUCKLE %s pitch %.1f ring %s hung %s eq %s" % [cam.unproject_position(belt.global_transform * Vector3(0, 0, -0.14)), rad_to_deg(_pitch), _m.interact_target(), belt.call("hung"), _m.progression.equipped()])
	return false

func _setup() -> void:
	var m = _m
	m.finish_opening()
	m.player.set_physics_process(false)
	m.player.global_position = m.START_POS
	_yaw = m.player.rotation.y + 2.4
	var prog: FPProgression = m.progression
	prog.grant_item("knife")
	prog.grant_item("blender")
	m.equip_tool("")
	match _shot:
		"aim":
			_aim = 1
		"after":
			m.belt_swap.swap_now("knife")
			_aim = 0

func _hold() -> void:
	var p = _m.player
	if _aim >= 0 and _frame % 5 == 2:
		_solve(_aim)
	p.set("_yaw", _yaw)
	p.rotation.y = _yaw
	p.set("_pitch", _pitch)
	p.camera_pivot.rotation.x = _pitch

func _solve(i: int) -> void:
	var span := 1.0
	for round in range(6):
		var best := INF
		var cy := _yaw
		var cp := _pitch
		for a in range(-6, 7):
			for b in range(-6, 7):
				var y := cy + span * a / 6.0
				var pp := clampf(cp + span * b / 6.0, -1.55, -1.0)
				var e := _err(i, y, pp)
				if e < best:
					best = e
					_yaw = y
					_pitch = pp
		span *= 0.3
	_err(i, _yaw, _pitch)

func _err(i: int, yaw: float, pitch: float) -> float:
	var pl = _m.player
	pl.rotation = Vector3(0, yaw, 0)
	pl.camera_pivot.rotation.x = pitch
	pl.force_update_transform()
	_m.belt_swap.tick(0.0)
	var r: Array = pl.get_look_ray()
	var hp: Vector3 = _m.art_hookup.belt.call("hook_point", i)
	return (r[1] as Vector3).angle_to(hp - r[0])