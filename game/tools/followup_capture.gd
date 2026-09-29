extends SceneTree

## Session C follow-up captures: T1 echo marks, M23 hair shiver, M25 marker.
## Godot_console --path game --windowed --resolution 1280x720
##   --write-movie <dir>/f.png --fixed-fps 10 --quit-after 30
##   --script res://tools/followup_capture.gd -- <echo|shiver|marker>

var _main: Node3D
var _shot := "echo"
var _frame := 0
var _c := Vector3(10, 1, -10)

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot = args[0]
	_main = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)

func _arena() -> void:
	var t: FDKTerrainField = _main.terrain
	var c := _c
	t.fill_box_uniform(AABB(c - Vector3.ONE * 6.0, Vector3.ONE * 12.0), 1.0, FPProgression.TISSUE_COMPRESSIVE)
	t.fill_box_uniform(AABB(c + Vector3(0.9, -0.6, -1.6), Vector3(1.2, 1.6, 1.2)), 1.0, FPProgression.TISSUE_NERVE)
	t.fill_box_uniform(AABB(c + Vector3(-0.8, -2.4, -2.2), Vector3(1.6, 1.2, 1.6)), 1.0, FPProgression.TISSUE_CONTRACTILE)
	t.carve_sphere(c, 1.6)
	t.carve_sphere(c + Vector3(0, 0, -1.0), 1.4)
	t.carve_sphere(c + Vector3(-0.3, 0.2, -4.2), 1.3) # thin wall ahead
	t.fill_box_uniform(AABB(c + Vector3(-1.4, -0.4, -1.4), Vector3(0.6, 0.6, 0.6)), 0.3, FPProgression.TISSUE_COMPRESSIVE)
	t.remesh_all()

func _pose(pos: Vector3, yaw: float, pitch: float = 0.0) -> void:
	var p = _main.player
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.set("_yaw", yaw)
	p.set("_pitch", pitch)
	p.rotation.y = yaw
	p.camera_pivot.rotation.x = pitch

func _process(_d: float) -> bool:
	_frame += 1
	var m = _main
	var prog: FPProgression = m.progression
	if _frame == 2:
		m.finish_opening()
		m.restroom.set_door_open(false, true)
		match _shot:
			"echo":
				_arena()
				prog.tumor_mutations.append("T1")
				var fake := MeshInstance3D.new()
				fake.mesh = SphereMesh.new()
				m.add_child(fake)
				fake.global_position = _c + Vector3(-1.8, 0.2, -3.2)
				m.tumor_nodes.append(fake)
				m.terrain.contract_time = FDKTissueRules.CONTRACT_PERIOD - FDKTissueRules.contract_phase(_c + Vector3(0, -1.2, -1.4)) - 1.0
			"shiver":
				_arena()
				prog.mutation_tree._purchased["M23"] = true
			"marker":
				prog.mutation_tree._purchased["M25"] = true
	if _frame >= 3 and _frame < 40:
		match _shot:
			"echo":
				_pose(_c - Vector3(0, 1.4, 0) + Vector3(0, 0, 0.6), 0.0, deg_to_rad(-8.0))
				if _frame == 12:
					var t0 := Time.get_ticks_usec()
					var n: Dictionary = m.mutation_apply.echo_pulse()
					print("echo_pulse %d us %s" % [Time.get_ticks_usec() - t0, n])
			"shiver":
				_pose(_c - Vector3(0, 1.0, 0), 0.0, deg_to_rad(-35.0))
				if _frame >= 12:
					m.terrain.contract_time = FDKTissueRules.CONTRACT_PERIOD - FDKTissueRules.contract_phase(_c + Vector3(0, -1.9, -1.4)) - 1.0
				if _frame == 20:
					print("shiver %.2f warnings %d bristles %d" % [m.mutation_apply.hair_shiver, m.mutation_apply.hair_warnings, m.hands_rig.find_children("MutDeco_Bristles*", "Node3D", true, false).size()])
			"marker":
				if _frame == 3:
					m.player.global_position = Vector3(0.0, 0.95, -0.6)
					m.die("test")
				_pose(m.START_POS, -0.61, deg_to_rad(-20.0))
				if _frame >= 5:
					m.death_drop.carry_along(Vector3(0.05, 0, 0))
	return false