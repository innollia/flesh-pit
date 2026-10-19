extends SceneTree

## HUD and pause frames for review: stomach at a few fills, past capacity
## with the vomit button, and the Esc screen over play. Isolated save.
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --script res://tests/capture_hud.gd

var m: Node3D
var out := ""

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = "user://capture-hud.bin"
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String) -> void:
	await frames(2)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("CAP ", name)

func _run() -> void:
	await frames(5)
	m.finish_opening()
	m.vent.instant_voice = true
	m.player.global_position = Vector3(0.3, 0.9, 0.6)
	m.player._yaw = PI * 0.85
	m.player._pitch = -0.15
	await frames(60)
	var cap: float = m.stomach.config.capacity
	for pair in [[0.25, "stomach_25"], [0.7, "stomach_70"], [1.0, "stomach_100"]]:
		m.stomach.fill = cap * float(pair[0])
		await frames(50)
		await shot(pair[1])
	m.stomach.fill = cap + m.stomach.config.overfill_capacity * 0.7
	await frames(90)
	await shot("stomach_over")
	m.stomach.fill = cap * 0.4
	await frames(30)
	m.open_pause_menu()
	await frames(6)
	await shot("pause_closing")
	await frames(20)
	await shot("pause")
	(m.pause_menu.buttons[2] as Button).grab_focus()
	await frames(10)
	await shot("pause_focus2")
	m.pause_menu.resume()
	await frames(4)
	await shot("pause_opening")
	await frames(20)
	# bits and blood out of a tear, just in front of the eye
	m.stomach.fill = 0.0
	var eye: Vector3 = m.player.camera.global_position
	var fwd: Vector3 = -m.player.camera.global_basis.z
	var at := eye + fwd * 0.7 + Vector3.DOWN * 0.15
	m.gore.burst(at, -fwd, 3, 7)
	await frames(5)
	await shot("tear_burst")
	await frames(40)
	await shot("tear_landed")
	# vomit onto the floor
	m.player._pitch = -1.1
	await frames(3)
	m.hand_motions._spill(false, 6)
	await frames(30)
	await shot("vomit_floor")
	# waking after a death
	m.wake_lids.play()
	await frames(30)
	await shot("wake_shut")
	await frames(36)
	await shot("wake_opening")
	await frames(60)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture-hud.bin"))
	m.queue_free()
	quit(0)
