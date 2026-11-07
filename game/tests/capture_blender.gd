extends SceneTree

## Held blender and arm reach in the real game (isolated save). Windowed:
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60
##     --script res://tests/capture_blender.gd -- [prefix]
## Shots: idle hands, every held item, a belt-equip frame sequence of the
## blender, a direct equip sequence, and walking frames with the blender.
## Each frame also prints the screen gap between the left grip and the
## blender handle so the attach can be read as numbers too.

var m: Node3D
var out := ""
var prefix := ""
const SAVE := "user://capture-blender.bin"

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	var args := OS.get_cmdline_user_args()
	prefix = args[0] if args.size() > 0 else ""
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.user_keybinds_path = "user://keybinds_test_blender.json"
	m.save_path = SAVE
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String, zoom: Rect2i = Rect2i()) -> void:
	await frames(1)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out.path_join(prefix + name + ".png"))
	if zoom.size != Vector2i.ZERO:
		var crop := img.get_region(zoom)
		crop.resize(zoom.size.x * 2, zoom.size.y * 2, Image.INTERPOLATE_NEAREST)
		crop.save_png(out.path_join(prefix + name + "_zoom.png"))
	print("CAP ", prefix + name, " ", _gap())

## Screen distance (px) between the left hand's wrist and the blender origin
## and their screen positions, to show the blender travels with the hand.
func _gap() -> String:
	var cam: Camera3D = m.player.camera
	var bl: Node3D = m.art_hookup.blender
	var lw: Node3D = m.art_hookup._rig.get_node("HandLeft/Wrist")
	if not bl.is_visible_in_tree():
		return "blender hidden"
	var a := cam.unproject_position(lw.global_position)
	var b := cam.unproject_position(bl.global_position)
	var rel: Vector3 = lw.global_transform.affine_inverse() * bl.global_position
	var top := cam.unproject_position(bl.global_transform * Vector3(0, 0.34, 0))
	var dial := cam.unproject_position(bl.global_transform * Vector3(0, 0.06, 0.08))
	var grip := cam.unproject_position(bl.global_transform * (bl.call("hand_grip") as Vector3))
	return "wrist=(%d,%d) blender=(%d,%d) top=(%d,%d) dial=(%d,%d) grip=(%d,%d) rel_wrist=(%.3f,%.3f,%.3f)" % [a.x, a.y, b.x, b.y, top.x, top.y, dial.x, dial.y, grip.x, grip.y, rel.x, rel.y, rel.z]

func _run() -> void:
	await frames(5)
	m.finish_opening()
	m.restroom.set_door_open(true, true)
	m.player.global_position = Vector3(0.0, 0.95, 0.2)
	m.player._yaw = PI
	m.player._pitch = -0.1
	await frames(40)
	await shot("idle")
	var p = m.progression
	p.has_belt = true
	for id in ["spray_cheap", "spray_deep", "canary_feed", "barrier", "knife", "blender", "big_saw"]:
		p.grant_item(id)
	await frames(10)
	for id in ["spray_cheap", "spray_deep", "canary_feed", "barrier", "knife", "big_saw", "blender"]:
		m.belt_swap.swap_now(id)
		await frames(30)
		await shot("held_" + id, Rect2i(120, 240, 480, 300))
		if id == "blender" and OS.get_environment("CAP_DEBUG") != "":
			var cam: Camera3D = m.player.camera
			for n in cam.find_children("*", "VisualInstance3D", true, false):
				if (n as Node3D).is_visible_in_tree() and not cam.is_position_behind((n as Node3D).global_position):
					print("VIS ", cam.get_path_to(n), " at ", cam.unproject_position((n as Node3D).global_position))
	# direct equip from bare hands: the frames right after the swap
	m.belt_swap.swap_now("")
	await frames(40)
	m.belt_swap.swap_now("blender")
	for i in range(12):
		await shot("equip_f%02d" % (i * 3))
		await frames(2)
	# walking with the blender: the hand bob and the blender together
	m.player.global_position = Vector3(0.0, 0.95, -0.6)
	await frames(20)
	Input.action_press("fdk_move_forward")
	for i in range(8):
		await frames(4)
		await shot("walk_f%d" % i)
	Input.action_release("fdk_move_forward")
	await frames(30)
	# belt equip of the blender (reach down, come back up with it)
	m.belt_swap.swap_now("")
	m.player.global_position = Vector3(0.2, 0.95, 0.4)
	await frames(20)
	var found := false
	for yi in range(-12, 13):
		for pi in range(0, 12):
			m.player._yaw = PI + yi * 0.08
			m.player._pitch = -1.05 - pi * 0.04
			m.player.rotation.y = m.player._yaw
			m.player.camera_pivot.rotation.x = m.player._pitch
			m.player.force_update_transform()
			m.player.camera.force_update_transform()
			if m.belt_swap.aimed_hook() == 1:
				found = true
				break
		if found:
			break
	var began: bool = m.belt_swap.begin(0) if found else false
	print("belt hook found=", found, " begin=", began)
	for i in range(12):
		await frames(3)
		await shot("belt_f%02d" % i)
	m.player._pitch = -0.1
	await frames(30)
	await shot("belt_after")
	# charge lamps lit on the held blender (they face the player)
	m.art_hookup.blender.call("set_charge_lights", 6)
	await frames(2)
	await shot("held_blender_lamps", Rect2i(120, 240, 480, 300))
	# drinking: the jar tips about the handle, still in the hand
	m.art_hookup.blender.call("set_fill", 0.7)
	m.art_hookup.blender.call("play_drink")
	for i in range(4):
		await frames(8)
		await shot("drink_f%d" % i)
	await frames(80)
	# Tab (B pose) with the blender held: the arm rises without it and takes
	# it again after closing
	m.open_mirror()
	for i in range(6):
		await frames(8)
		await shot("tab_open_f%d" % i)
	m.mirror.close()
	for i in range(8):
		await frames(6)
		await shot("tab_close_f%d" % i)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(0)
