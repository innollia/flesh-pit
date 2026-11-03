extends SceneTree

## Held big saw in the real game (isolated save). Windowed:
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60
##     --script res://tests/capture_saw.gd -- [prefix]
## Shots: idle hands, the take sequence from bare hands, held, walking, a
## real saw dig at the flesh behind the door, the belt take, and Tab.
## Each frame prints where both finger loops and both saw handles land on
## screen, so the grip can be read as numbers too.

var m: Node3D
var out := ""
var prefix := ""
const SAVE := "user://capture-saw.bin"

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	var args := OS.get_cmdline_user_args()
	prefix = args[0] if args.size() > 0 else ""
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = SAVE
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String) -> void:
	await frames(1)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out.path_join(prefix + name + ".png"))
	print("CAP ", prefix + name, " ", _gap())

## Screen px of each finger loop (FPArtHookup.SAW_GRIP in each wrist) and of
## each saw handle, and their 3D gap (m).
func _gap() -> String:
	var cam: Camera3D = m.player.camera
	var saw: Node3D = m.art_hookup.saw
	if not saw.is_visible_in_tree():
		return "saw hidden"
	var rig: Node3D = m.art_hookup._rig
	var s := ""
	for side in [["L", "HandLeft/Wrist", "grip_left"], ["R", "HandRight/Wrist", "grip_right"]]:
		var w := rig.get_node(side[1]) as Node3D
		var loop := w.global_transform * FPArtHookup.SAW_GRIP
		var handle := saw.global_transform * (saw.call(side[2]) as Vector3)
		var a := cam.unproject_position(loop)
		var b := cam.unproject_position(handle)
		s += "%s loop=(%d,%d) handle=(%d,%d) gap=%.3fm  " % [side[0], a.x, a.y, b.x, b.y, loop.distance_to(handle)]
	return s

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
	for id in ["knife", "blender", "big_saw"]:
		p.grant_item(id)
	await frames(10)
	# take from bare hands: both drop, both come up on the handles
	m.belt_swap.swap_now("big_saw")
	for i in range(14):
		await shot("take_f%02d" % (i * 2))
		await frames(1)
	await frames(30)
	await shot("held")
	# walking: the hands bob and the saw goes with them
	m.player.global_position = Vector3(0.0, 0.95, -0.6)
	await frames(20)
	Input.action_press("fdk_move_forward")
	for i in range(8):
		await frames(4)
		await shot("walk_f%d" % i)
	Input.action_release("fdk_move_forward")
	await frames(30)
	# using it: hold the dig button on the flesh in the doorway
	m.player.global_position = Vector3(0.0, 0.95, -0.55)
	m.player._pitch = -0.15
	await frames(20)
	var fill0: float = m.stomach.fill
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	Input.parse_input_event(ev)
	for i in range(16):
		await frames(6)
		await shot("use_f%02d" % i)
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_LEFT
	ev2.pressed = false
	Input.parse_input_event(ev2)
	print("saw dig: stomach ", fill0, " -> ", m.stomach.fill)
	await frames(40)
	# put away, then swap straight from the blender to the saw
	m.belt_swap.swap_now("blender")
	await frames(40)
	await shot("blender_before_swap")
	m.belt_swap.swap_now("big_saw")
	for i in range(8):
		await shot("from_blender_f%02d" % (i * 3))
		await frames(2)
	await frames(30)
	# Tab (B pose) with the saw: the arm rises without it, takes it back
	m.player.global_position = Vector3(0.0, 0.95, 0.2)
	await frames(20)
	m.open_mirror()
	for i in range(4):
		await frames(10)
		await shot("tab_open_f%d" % i)
	m.mirror.close()
	for i in range(5):
		await frames(8)
		await shot("tab_close_f%d" % i)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(0)
