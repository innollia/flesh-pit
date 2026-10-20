extends SceneTree

## The compass (decision 0009): on the waistband looking down, held in the
## left hand in the restroom and out in the flesh (needle toward the
## restroom), and the Tab screen with and without it held (the forearm doll
## must not change). Isolated save.
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --script res://tests/capture_compass.gd

var m: Node3D
var out := ""

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = "user://capture-compass.bin"
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String) -> void:
	await frames(2)
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("CAP ", name, " needle ", snappedf(rad_to_deg(m.art_hookup.hand_compass.call("aim_angle")), 1.0))

func _run() -> void:
	await frames(5)
	m.finish_opening()
	m.player.global_position = Vector3(0.3, 0.9, 0.6)
	m.player._yaw = PI * 0.85
	m.player._pitch = -1.15
	await frames(60)
	await shot("compass_waist")
	m.player._pitch = -0.35
	m.equip_hand("compass", FDKToolKit.Hand.LEFT)
	await frames(40)
	await shot("compass_held_restroom")
	# out in the flesh: dig a pocket 4 m past the door and stand in it
	var p: Vector3 = m.RESTROOM_CENTER + Vector3(1.0, -0.5, 4.5)
	for x in range(-3, 4):
		for y in range(-3, 4):
			for z in range(-3, 4):
				m.terrain.dig_at(p + Vector3(x, y, z) * 0.35, 1.0)
	m.terrain.remesh_all()
	m.player.global_position = p
	for yaw in [0.0, PI * 0.5, PI]:
		m.player._yaw = yaw
		await frames(40)
		await shot("compass_held_flesh_%d" % int(rad_to_deg(yaw)))
	m.player.global_position = Vector3(0.3, 0.9, 0.6)
	m.player._pitch = 0.0
	await frames(20)
	m.open_mirror()
	await frames(90)
	await shot("compass_tab_held")
	m.close_mirror() if m.has_method("close_mirror") else null
	await frames(30)
	m.equip_hand("", FDKToolKit.Hand.LEFT)
	await frames(20)
	m.open_mirror()
	await frames(90)
	await shot("compass_tab_not_held")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture-compass.bin"))
	m.queue_free()
	quit(0)
