extends SceneTree

## Taking teeth from the tank, in the real game (isolated save): how far off
## the tank reads as a target, whether the view holds still while leaning in,
## and shots of the tank from the toilet front (shelf, cabinet, head).
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --script res://tests/capture_tank_teeth.gd

var m: Node3D
var out := ""
const SAVE := "user://capture-tank-teeth.bin"

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.user_keybinds_path = "user://keybinds_test_tank_teeth.json"
	m.save_path = SAVE
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String) -> void:
	await frames(2)
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("CAP ", name)

func look_at_point(target: Vector3) -> void:
	var eye: Vector3 = m.player.camera.global_position
	var d := target - eye
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = atan2(d.y, Vector2(d.x, d.z).length())

func _run() -> void:
	await frames(5)
	m.finish_opening()
	m.restroom.set_door_open(false, true)
	m.progression.teeth = 12
	var tank: Vector3 = m.restroom.tank_art.to_global(Vector3(0, 0.3, 0))
	# lid off, put down on the floor away from the tank
	m.player.global_position = Vector3(tank.x + 1.2, 0.95, tank.z - 0.6)
	await frames(3)
	m.tank_lid.pick()
	look_at_point(Vector3(tank.x + 1.6, 0.0, tank.z - 1.0))
	await frames(3)
	m.tank_lid.drop()
	# walk back from the tank: where does it stop being a target?
	for d in [0.6, 0.8, 1.0, 1.2, 1.4, 1.6]:
		m.player.global_position = Vector3(tank.x + d, 0.95, tank.z)
		await frames(3)
		look_at_point(tank)
		await frames(3)
		print("  dist %.1f eye-tank %.2f target '%s' lid_on %s" % [d, m.player.camera.global_position.distance_to(tank), m.interact_target(), m.tank_lid.on_tank])
	m.player.global_position = Vector3(tank.x + 0.7, 0.95, tank.z)
	await frames(3)
	look_at_point(tank)
	await frames(10)
	await shot("tank_front")
	var cams: Array[Vector3] = []
	var postures: Array[Vector2] = []
	for i in range(90):
		await process_frame
		cams.append(m.player.camera.global_position)
		postures.append(Vector2(m.player.duck, m.player.twist))
	print("  standing: cam spread %.4f posture %s..%s" % [_spread(cams), postures.min(), postures.max()])
	m._interact()
	cams.clear()
	postures.clear()
	for i in range(150):
		await process_frame
		if i >= 60:
			cams.append(m.player.camera.global_position)
		postures.append(Vector2(m.player.duck, m.player.twist))
	print("  leaning %s: cam spread %.4f posture %s..%s teeth_in_hand %d" % [m.hand_motions.tank_leaning(), _spread(cams), postures.min(), postures.max(), m.progression.teeth_in_hand])
	await shot("tank_lean")
	m.hand_motions.release_tank_lean()
	m.progression.put_back_tooth()
	await frames(60)
	# as a player does it: walk up to the tank, then hold F to take teeth
	m.player.global_position = Vector3(tank.x + 1.7, 0.95, tank.z + 0.2)
	await frames(3)
	look_at_point(tank)
	await frames(3)
	Input.action_press("fdk_move_forward")
	var walk := await _watch(45)
	Input.action_release("fdk_move_forward")
	print("  walk in: jitter %.4f duck %.2f..%.2f twist %.2f..%.2f, at %.2f m, target '%s'" % [walk[0], walk[1].x, walk[2].x, walk[1].y, walk[2].y, m.player.camera.global_position.distance_to(tank), m.interact_target()])
	look_at_point(tank)
	await frames(2)
	Input.action_press("fp_interact")
	var take := await _watch(150)
	Input.action_release("fp_interact")
	print("  hold F: jitter %.4f duck %.2f..%.2f twist %.2f..%.2f teeth_in_hand %d" % [take[0], take[1].x, take[2].x, take[1].y, take[2].y, m.progression.teeth_in_hand])
	quit(0)

## [summed frame-to-frame camera turn+move, min (duck, twist), max (duck, twist)]
func _watch(n: int) -> Array:
	var jitter := 0.0
	var lo := Vector2(9, 9)
	var hi := Vector2(-9, -9)
	var prev: Transform3D = m.player.camera.global_transform
	var prev_step := Vector3.ZERO
	for i in range(n):
		await process_frame
		var xf: Transform3D = m.player.camera.global_transform
		var step := xf.origin - prev.origin
		# direction changes of the motion, not steady walking
		jitter += (step - prev_step).length()
		prev_step = step
		prev = xf
		var pz := Vector2(m.player.duck, m.player.twist)
		lo = lo.min(pz)
		hi = hi.max(pz)
	return [jitter, lo, hi]

func _spread(ps: Array[Vector3]) -> float:
	var lo := ps[0]
	var hi := ps[0]
	for p in ps:
		lo = lo.min(p)
		hi = hi.max(p)
	return (hi - lo).length()
