extends SceneTree

## Looking down at the belt with real mouse input (2026-11-07 "벨트에 있는
## 물건 목록을 아직 못 건드려"): the aimed item lights up, a left click takes
## it into the left hand, a right click into the right. Restroom and flesh.
## Run windowed with the movie writer (never headless):
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --write-movie <tmp>/f.png --script res://tests/capture_belt_reach.gd

var m: Node3D
var out := ""
const SAVE := "user://capture-belt-reach.bin"
const L := FDKToolKit.Hand.LEFT

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
	await frames(2)
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("CAP ", name, " aimed=", m.belt_swap.aimed_hook(), " focus=", m.belt_swap.focus, " L=", m.progression.hands.item(L), " R=", m.progression.hands.item(FDKToolKit.Hand.RIGHT))

func click(button: int) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	Input.parse_input_event(e)
	await frames(3)
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	await frames(3)
	for i in range(90):
		if not m.belt_swap.busy() and m.hand_motions.kind != "belt":
			break
		await frames(1)
	await frames(20)

## Real mouse motion toward where the item shows on screen.
func look_at_slot(i: int) -> void:
	var cam: Camera3D = m.player.camera
	for k in range(60):
		var p: Vector3 = m.belt_swap._slot_point(m.art_hookup.belt, i)
		var size := cam.get_viewport().get_visible_rect().size
		var f: float = size.y * 0.5 / tan(deg_to_rad(cam.fov) * 0.5)
		var off: Vector2 = Vector2(0, size.y) if cam.is_position_behind(p) else cam.unproject_position(p) - size * 0.5
		if off.length() < 2.0:
			break
		var e := InputEventMouseMotion.new()
		e.relative = Vector2(atan(off.x / f), atan(off.y / f)) * 0.6 / float(m.player.config.mouse_sensitivity)
		Input.parse_input_event(e)
		await frames(1)
	await frames(15)

func game_at(at: Vector3, flesh: bool) -> void:
	if is_instance_valid(m):
		m.queue_free()
		await frames(2)
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.user_keybinds_path = "user://keybinds_test_belt_reach_capture.json"
	m.save_path = SAVE
	root.add_child(m)
	await frames(6)
	m.finish_opening()
	m.player.mouse_look_enabled = true
	if flesh:
		m.terrain.carve_sphere(Vector3(0, 1.2, 4.2), 1.6)
		m.terrain.remesh_all()
	m.player.global_position = at
	m.player.velocity = Vector3.ZERO
	var p: FPProgression = m.progression
	p.has_belt = true
	for id in ["knife", "blender", "big_saw", "spray_cheap", "spray_cheap", "spray_deep", "canary_feed", "barrier"]:
		p.grant_item(id)
	m.equip_tool("")
	await frames(40)

func _run() -> void:
	for place in [["restroom", Vector3(0, 0.95, 0), false], ["flesh", Vector3(0, 0.6, 4.0), true]]:
		var where: String = place[0]
		await game_at(place[1], place[2])
		await look_at_slot(1)
		await shot("%s_0_look_down" % where)
		# the knife on the left hook: lit, then the left hand takes it
		await look_at_slot(0)
		await shot("%s_1_knife_aimed" % where)
		await click(MOUSE_BUTTON_LEFT)
		await shot("%s_2_knife_taken_left" % where)
		# a spray can on the right hip: lit, then the right hand takes it
		await look_at_slot(3)
		await shot("%s_3_can_aimed" % where)
		await click(MOUSE_BUTTON_RIGHT)
		await shot("%s_4_can_taken_right" % where)
		# the compass: lit, left hand
		await look_at_slot(7)
		await shot("%s_5_compass_aimed" % where)
		# put the knife back on its hook
		await look_at_slot(0)
		await shot("%s_6_empty_hook_aimed" % where)
		await click(MOUSE_BUTTON_LEFT)
		await shot("%s_7_knife_back" % where)
	m.queue_free()
	await frames(2)
	quit(0)
