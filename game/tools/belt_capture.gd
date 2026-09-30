extends SceneTree

## Belt swap captures, one shot per run (windowed + movie writer):
##   Godot_console --path game --windowed --resolution 1280x720
##     --write-movie <dir>/f.png --fixed-fps 10 --quit-after 30
##     --script res://tools/belt_capture.gd -- <look|aim|after>
## look  = head bowed ~62 deg, belt with knife + blender, empty saw ring
## aim   = aim dot on the blender hook, interact ring lit
## after = the swap done: knife in hand, its ring empty, blender + saw hung

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
		_measure()
	return false

func _setup() -> void:
	var m = _m
	m.finish_opening()
	m.player.set_physics_process(false)
	m.player.global_position = m.START_POS
	_yaw = m.player.rotation.y + 2.4
	var prog: FPProgression = m.progression
	prog.has_belt = _shot != "nobelt"
	prog.grant_item("knife")
	prog.grant_item("blender")
	m.equip_tool("")
	match _shot:
		"aim":
			_aim = 1
		"after":
			prog.grant_item("big_saw")
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
## Screen-space report (1280x720): each hook's ring+tool box, spacing between
## hook centres, and where the hands' boxes sit.
func _measure() -> void:
	var cam: Camera3D = _m.player.camera
	var belt: Node3D = _m.art_hookup.belt
	var xs: Array = []
	for i in range(3):
		var hook: Node3D = belt.get_node("Hook%d" % i)
		var tool := hook.get_node_or_null("Tool") as Node3D
		var r := _screen_box(cam, tool if tool != null else hook)
		var c := cam.unproject_position(hook.global_position)
		xs.append(c.x)
		print("HOOK %d centre %s tool=%s box %s size %dx%d" % [i, c.round(), tool != null, r.position.round(), int(r.size.x), int(r.size.y)])
	print("SPACING %d %d" % [int(xs[1] - xs[0]), int(xs[2] - xs[1])])
	var bb := _screen_box(cam, belt.get_node("Belt"))
	print("BELT box %s size %dx%d" % [bb.position.round(), int(bb.size.x), int(bb.size.y)])
	var tb := _screen_box(cam, belt.get_node("Torso"))
	print("TORSO box %s size %dx%d" % [tb.position.round(), int(tb.size.x), int(tb.size.y)])
	var rig: Node3D = _m.hands_rig if _m.hands_rig.visible else _m.art_hookup.mut_hands.call("rig")
	for side in ["HandLeft", "HandRight"]:
		var h := _screen_box(cam, rig.get_node(side))
		print("%s box %s size %dx%d aside %.2f" % [side, h.position.round(), int(h.size.x), int(h.size.y), float(rig.get("aside"))])
	print("PITCH %.1f ring %s hung %s eq %s" % [rad_to_deg(_pitch), _m.interact_target(), belt.call("hung"), _m.progression.equipped()])

func _screen_box(cam: Camera3D, n: Node3D) -> Rect2:
	var pts: Array = []
	var nodes: Array = [n]
	nodes.append_array(n.find_children("*", "MeshInstance3D", true, false))
	for mi in nodes:
		if not (mi is MeshInstance3D) or (mi as MeshInstance3D).mesh == null or not (mi as MeshInstance3D).is_visible_in_tree():
			continue
		var b: AABB = (mi as MeshInstance3D).mesh.get_aabb()
		for k in range(8):
			var p: Vector3 = (mi as MeshInstance3D).global_transform * (b.position + b.size * Vector3(k & 1, (k >> 1) & 1, (k >> 2) & 1))
			if not cam.is_position_behind(p):
				pts.append(cam.unproject_position(p))
	if pts.is_empty():
		return Rect2()
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r.intersection(Rect2(0, 0, 1280, 720))