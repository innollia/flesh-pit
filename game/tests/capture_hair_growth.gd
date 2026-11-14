extends SceneTree

## Hairs grown by eating, seen in play (isolated save): after 0, 60 and 300
## swallowed units, the Tab watch look at the left forearm.
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --script res://tests/capture_hair_growth.gd

var m: Node3D
var out := ""
const SAVE := "user://capture-hair-growth.bin"

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.user_keybinds_path = "user://keybinds_test_hair_growth.json"
	m.save_path = SAVE
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String) -> void:
	await frames(1)
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("CAP ", name, " hairs ", m.progression.total_hairs(), " shown ", m.art_hookup.arm_hair.call("hair_total"))

func look(units: float, name: String) -> void:
	var eaten := 0.0
	while eaten < units:
		m.swallow_torn(1, 2.0)
		eaten += 2.0
		await frames(1)
	m.open_mirror()
	await frames(50)
	await shot(name)
	var lroot: Node3D = m.hands_rig.call("get_hand_root", "left")
	var hair: Node3D = m.art_hookup.arm_hair
	var cam: Camera3D = m.player.camera
	var up_cam: Vector3 = cam.global_basis.inverse() * (hair.global_basis * Vector3.UP)
	print("  hair parent %s, hair top in camera space %s (z>0 faces the camera), hair pos cam %s" % [hair.get_parent().name, up_cam.snapped(Vector3.ONE * 0.01), (cam.global_transform.affine_inverse() * hair.global_position).snapped(Vector3.ONE * 0.01)])
	m.close_mirror() if m.has_method("close_mirror") else m.mirror.close()
	await frames(30)

func _run() -> void:
	await frames(5)
	m.finish_opening()
	m.player.global_position = Vector3(0.0, 0.95, 0.0)
	await frames(10)
	await look(0.0, "hair_0")
	await look(60.0, "hair_60")
	await look(240.0, "hair_300")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(0)
