extends SceneTree

## The wrist compass on the left forearm: in the restroom, out in the flesh
## (needle toward the restroom), and on the Tab screen with and without it
## (the doll on the forearm must not change). Isolated save.
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --script res://tests/capture_wrist_compass.gd

var m: Node3D
var out := ""

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = "user://capture-wrist-compass.bin"
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String) -> void:
	await frames(2)
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("CAP ", name, " needle ", snappedf(rad_to_deg(m.art_hookup.wrist_compass.call("aim_angle")), 1.0))

func _run() -> void:
	await frames(5)
	m.finish_opening()
	m.player.global_position = Vector3(0.3, 0.9, 0.6)
	m.player._yaw = PI * 0.85
	m.player._pitch = -0.35
	await frames(60)
	await shot("compass_restroom")
	# hands reaching to tear (grab pose)
	m.hands_rig.on_grab_started()
	m.hands_rig.on_chew_progress(0.6)
	await frames(12)
	await shot("compass_grab")
	m.hands_rig.on_released()
	# out in the flesh: dig a pocket 4 m past the door and stand in it
	var p: Vector3 = m.RESTROOM_CENTER + Vector3(1.0, -0.5, 4.5)
	for x in range(-3, 4):
		for y in range(-3, 4):
			for z in range(-3, 4):
				m.terrain.dig_at(p + Vector3(x, y, z) * 0.35, 1.0)
	m.terrain.remesh_all()
	m.player.global_position = p
	m.player._pitch = -0.45
	for yaw in [0.0, PI * 0.5, PI]:
		m.player._yaw = yaw
		await frames(40)
		await shot("compass_flesh_%d" % int(rad_to_deg(yaw)))
	m.player.global_position = Vector3(0.3, 0.9, 0.6)
	await frames(20)
	m.open_mirror()
	await frames(90)
	await shot("compass_tab")
	m.art_hookup.wrist_compass.visible = false
	await frames(5)
	await shot("compass_tab_without")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture-wrist-compass.bin"))
	m.queue_free()
	quit(0)
