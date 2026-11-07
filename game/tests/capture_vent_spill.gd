extends SceneTree

## An absurd overpay at the vent: "큭 켘." and early items tumble out of the
## duct onto the floor, then go to the waist (audit 1-2). Isolated save.
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --script res://tests/capture_vent_spill.gd

var m: Node3D
var out := ""
const SAVE := "user://capture-vent-spill.bin"

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.user_keybinds_path = "user://keybinds_test_vent_spill.json"
	m.save_path = SAVE
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String) -> void:
	await frames(1)
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("CAP ", name, " spill=", m.vent.art.call("spill_count"), " barriers=", m.progression.barriers, " knife=", m.progression.owns("knife"))

func look_at_point(p: Vector3) -> void:
	var eye: Vector3 = m.player.camera.global_position
	var d := p - eye
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = atan2(d.y, Vector2(d.x, d.z).length())

func _run() -> void:
	m.save_path = SAVE
	await frames(5)
	m.finish_opening()
	m.restroom.set_door_open(false, true)
	m.player.global_position = Vector3(0.45, 0.9, 0.55)
	await frames(2)
	look_at_point(FPRestroom.VENT_CENTER + Vector3(0, -1.25, 0))
	await frames(30)
	m.vent._met = true # past the first meeting: the trade lines, not the greeting
	m.vent.open(999)
	await frames(50)
	m.progression.teeth_in_hand = m.progression.vent_absurd_threshold()
	m.place_teeth_at_vent()
	for i in range(8):
		await frames(1 if i == 0 else 14)
		await shot("vent_spill_%02d" % i)
	# down at the floor under the vent, where they landed
	look_at_point(Vector3(FPRestroom.VENT_CENTER.x + 0.35, 0.0, FPRestroom.VENT_CENTER.z + 0.4))
	await frames(10)
	await shot("vent_spill_rest")
	var fov: float = m.player.camera.fov
	m.player.camera.fov = 28.0
	await frames(2)
	await shot("vent_spill_rest_zoom")
	m.player.camera.fov = fov
	# then each is swept up to the waist
	await frames(30)
	for i in range(5):
		await frames(9)
		await shot("vent_spill_stow_%d" % i)
	await frames(60)
	await shot("vent_spill_after")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	m.queue_free()
	quit(0)
