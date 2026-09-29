extends SceneTree

## Session D in-game captures (W21 tissue per shell + boundary membrane, W22
## rest point, W23 barrier stages, W24 spray melt, W25 blender, W26 saw, W28
## death marker). WINDOWED with the movie writer, one shot per run:
##   Godot_console --path game --windowed --resolution 1280x720
##     --write-movie <dir>/f.png --fixed-fps 10 --quit-after 60
##     --script res://tools/session_d_capture.gd -- <shot>

var _m: Node3D
var _shot := "shell_0"
var _frame := 0
var _eye := Vector3.ZERO
var _target := Vector3.ZERO
var _barrier: FDKBarrier

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot = args[0]
	_m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_m)

func _hold() -> void:
	var p = _m.player
	var d := (_target - _eye).normalized()
	var off: float = p.camera.global_position.y - p.global_position.y
	p.global_position = _eye - Vector3(0, off, 0)
	p.velocity = Vector3.ZERO
	var yaw := atan2(-d.x, -d.z)
	p.set("_yaw", yaw)
	p.set("_pitch", asin(clampf(d.y, -1, 1)))
	p.rotation.y = yaw
	if _m.tissue_tools.blend_state != FPTissueTools.Blend.DRINK:
		p.camera_pivot.rotation.x = asin(clampf(d.y, -1, 1))

## Eats out a round room (regrows slowly, like the player's digging).
func _cave(c: Vector3, r: float) -> void:
	var s := 0.25
	var n := int(ceil(r / s))
	for z in range(-n, n + 1):
		for y in range(-n, n + 1):
			for x in range(-n, n + 1):
				var q := c + Vector3(x, y, z) * s
				if q.distance_to(c) <= r:
					_m.terrain.dig_at(q, 1.0)

func _tube(a: Vector3, b: Vector3, r: float) -> void:
	var l := a.distance_to(b)
	var k := 0.0
	while k <= l:
		_cave(a.lerp(b, k / l), r)
		k += 0.5

func _setup() -> void:
	var m = _m
	var prog: FPProgression = m.progression
	m.finish_opening()
	m.player.set_physics_process(false)
	var c: Vector3 = m.RESTROOM_CENTER
	var out := Vector3(-1, 0.05, -0.35).normalized()
	match _shot:
		"shell_0", "shell_1", "shell_2":
			var depth: float = [5.2, 13.5, 21.5][int(_shot.right(1))]
			var mid := c + out * depth
			_cave(mid, 1.7)
			_eye = mid - out * 0.9 + Vector3(0, 0.3, 0)
			_target = mid + out * 1.7 + Vector3(0.2, -0.2, 0.4)
		"boundary":
			# tunnel from the core out through the membrane band at 9 m
			var a := c + out * 6.2
			var b := c + out * 10.5
			_tube(a, b, 0.95)
			_eye = c + out * 6.6 + Vector3(0, 0.25, 0)
			_target = c + out * 9.0 + Vector3(0, 0.55, 0.0)
		"membrane_knife":
			m.restroom.set_door_open(true, true)
			prog.grant_item("knife")
			m.equip_tool("knife")
			_eye = Vector3(1.0, 1.55, 0.3)
			_target = Vector3(1.7, 1.2, 0.5)
		"rest_point":
			var r: Vector3 = m.rest_points[3]
			var dir := (r - c).normalized()
			var side := dir.cross(Vector3.UP).normalized()
			var front: Vector3 = r + Vector3(0, 0, FPWorldFeatures.CONTAINER_HALF.z + 2.2)
			_tube(r + Vector3(0, 0, FPWorldFeatures.CONTAINER_HALF.z), front, 1.1)
			_eye = front + Vector3(0.9, 0.3, 0)
			_target = r + Vector3(0, -0.2, 0)
		"rest_inside":
			var r2: Vector3 = m.rest_points[3]
			_eye = r2 + Vector3(0.3, 0.2, 1.7)
			_target = r2 + Vector3(-0.2, -0.7, -1.8)
		"barrier":
			var a2 := c + out * 5.0
			_tube(a2, c + out * 8.0, 0.8)
			m.terrain.remesh_all()
			_eye = a2 + Vector3(0, 0.1, 0)
			_target = c + out * 6.8
			_hold()
			m.player.force_update_transform()
			prog.barriers = 1
			_barrier = m.place_barrier()
		"spray":
			var mid2 := c + out * 5.2
			_cave(mid2, 1.7)
			_eye = mid2 - out * 0.9 + Vector3(0, 0.3, 0)
			_target = mid2 + out * 1.7
			var wall := mid2 + out * 1.55
			for off in [Vector3.ZERO, Vector3(0, 0.6, 0.5), Vector3(0, -0.5, -0.4)]:
				m.terrain.spray_surface(wall + off, out, 0.75, 1.5)
		"blender_charge", "blender_spin", "blender_drink":
			m.restroom.set_door_open(true, true)
			prog.grant_item("blender")
			m.equip_tool("blender")
			m.toggle_carry()
			m.blender_charge = 0.6
			_eye = Vector3(0.0, 1.5, 3.0)
			_target = Vector3(-0.35, 0.9, 1.9)
			if _shot != "blender_charge":
				m.blender_charge = 1.0
				m.carried_flesh = 24.0
				m.carried_units = {0: 6}
				m.tissue_tools.start_blend()
				if _shot == "blender_drink":
					m.tissue_tools.blend_t = FPTissueTools.SPIN_TIME - 0.05
		"saw":
			m.restroom.set_door_open(true, true)
			prog.grant_item("big_saw")
			m.equip_tool("big_saw")
			_eye = Vector3(0.0, 1.5, 2.6)
			_target = Vector3(0.0, 1.2, 5.0)
		"death":
			var at := c + out * 5.2
			_cave(at, 1.8)
			m.stomach.add_flesh(20.0)
			m.player.global_position = at + Vector3(0, -0.6, 0)
			m.die("crush")
			m.player.set_physics_process(false)
			_eye = at - out * 1.2 + Vector3(0.3, 0.4, 0.3)
			_target = at + Vector3(0, -0.9, 0)
	m.terrain.remesh_all()
	m.apply_atmosphere_now()
	_hold()

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_setup()
	if _frame > 2:
		_hold()
		if _shot == "barrier" and _barrier != null:
			# 10 frames per stage: intact, bent, cracked, broken
			var st := clampi((_frame - 3) / 12, 0, 3)
			if st < 3:
				_barrier.stress = _barrier.break_threshold * [0.1, 0.45, 0.8][st]
				_barrier.absorb_pressure(0.0, 0.0)
			elif not _barrier.is_broken():
				_barrier.absorb_pressure(_barrier.break_threshold, 0.0)
		if _shot == "blender_charge":
			_m.blender_charge = 0.6
	return false