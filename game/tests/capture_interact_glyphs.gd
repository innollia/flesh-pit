extends SceneTree

## The aim ring's glyph (spec 08 §1): both buttons at the door, the right one
## at the lid and past the blender, the key cap when looking with the arrow
## keys, V alone at the bowl. Real Main; isolated save.
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --script res://tests/capture_interact_glyphs.gd

var m: Node3D
var out := ""
const SAVE := "user://capture-glyphs.bin"

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

func shot(name: String) -> void:
	await frames(25)
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	var c := Vector2i(img.get_width() / 2, img.get_height() / 2)
	img.get_region(Rect2i(c - Vector2i(120, 80), Vector2i(240, 160))).save_png(out.path_join(name + ".png"))
	print("CAP ", name, " target=", m.interact_target(), " device=", m.interact_ring.device, " L=", m.interact_ring.hand_left, " R=", m.interact_ring.hand_right)

func aim(point: Vector3) -> void:
	for i in range(4):
		var d: Vector3 = (point - m.player.camera.global_position).normalized()
		m.player._yaw = atan2(-d.x, -d.z)
		m.player._pitch = asin(clampf(d.y, -1.0, 1.0))
		m.player.rotation.y = m.player._yaw
		m.player.camera_pivot.rotation.x = m.player._pitch
		await frames(2)

func game_at(at: Vector3) -> void:
	if is_instance_valid(m):
		m.queue_free()
		await frames(2)
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = SAVE
	root.add_child(m)
	await frames(6)
	m.save_path = SAVE
	m.finish_opening()
	m.player.mouse_look_enabled = false
	m.player.global_position = at
	m.player.velocity = Vector3.ZERO
	await frames(4)

func _run() -> void:
	await game_at(Vector3(0, 0.9, 0.8))
	var door: Vector3 = m.door_handle_point()
	await aim(door)
	await shot("door-both")
	m.interact_ring.device = "keyboard"
	m.interact_ring.queue_redraw()
	await shot("door-key")
	m.interact_ring.device = "mouse"
	m.progression.grant_item("blender")
	m.equip_hand("blender", FDKToolKit.Hand.LEFT)
	await frames(40)
	await aim(door)
	await shot("door-blender-right-only")
	await game_at(Vector3(-1.25, 0.9, 0.72))
	await aim(m.tank_lid.lid.global_position)
	await shot("lid-right-only")
	await aim(m.toilet_point())
	await shot("bowl-V")
	quit()
