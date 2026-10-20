extends SceneTree

## The spray can left on a rest point's chair (core and mantle), seen from the
## container door side. Isolated save.
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --script res://tests/capture_rest_can.gd

var m: Node3D
var out := ""

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = "user://capture-rest-can.bin"
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String) -> void:
	await frames(2)
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("CAP ", name)

func _run() -> void:
	await frames(5)
	m.finish_opening()
	for i in [0, 3]:
		var rest: Node3D = m.rest_cans[i].get_parent()
		var can: Vector3 = m.rest_cans[i].global_position
		# stand in the container a metre and a half from the chair, toward the door side
		m.player.global_position = rest.to_global(Vector3(0.4, -0.2, -0.3))
		await frames(3)
		var eye: Vector3 = m.player.camera.global_position
		var d := can - eye
		m.player._yaw = atan2(-d.x, -d.z)
		m.player._pitch = atan2(d.y, Vector2(d.x, d.z).length())
		# the terrain streams in around the new spot first
		await frames(400)
		await shot("rest_can_%d" % i)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture-rest-can.bin"))
	m.queue_free()
	quit(0)
