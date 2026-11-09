extends SceneTree

## Teeth in hand at the vent (user 2026-11-09 "손에 봉을 쥐고 환풍구 문을
##열면 ... 이빨을 못 넣어줌"): the frames a player sees opening the vent
## with teeth in the right hand, paying them, and the offer coming out; the
## same with an offer the being held from last time; and the shut vent's
## pull for teeth in the first loop. Real input events, real rendering,
## isolated save and keys.
##   CAP_OUT=<dir> godot_console --path game --resolution 1280x720 --fixed-fps 60 --script res://tests/capture_vent_teeth.gd

var m: Node3D
var out := ""

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out)
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = "user://capture-vent-teeth.bin"
	m.user_keybinds_path = "user://capture-vent-teeth-keys.json"
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("CAP ", name, " open=", m.vent.is_open, " look=", m.hand_motions.vent_looking(), " pile=", m.vent.pile, " hand=", m.progression.teeth_in_hand, " offers=", m.vent.offers)

func send(action: String, down: bool) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			var ev: InputEvent = e.duplicate()
			ev.pressed = down
			Input.parse_input_event(ev)
			return

func press(action: String) -> void:
	send(action, true)
	await frames(3)
	send(action, false)
	await frames(3)

func look_at_point(p: Vector3) -> void:
	var eye: Vector3 = m.player.camera.global_position
	var d: Vector3 = p - eye
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = atan2(d.y, Vector2(d.x, d.z).length())

func reset() -> void:
	m._end_lean()
	await frames(50)
	while m.hand_motions.busy():
		await process_frame
	if m.vent.is_open:
		m.vent.close()
	m.vent._held.clear()
	m.vent._open_times.clear()
	m.vent.absent_left = 0.0
	m.player.global_position = Vector3(0.3, 0.9, 0.3)
	await frames(3)
	for i in range(4):
		look_at_point(FPRestroom.VENT_CENTER + Vector3(0, -0.2, 0))
		await physics_frame
	await frames(40)

func _flow(prefix: String, held: bool) -> void:
	await reset()
	if held:
		m.vent._held = ["knife", "spray_cheap"] as Array[String]
	m.progression.teeth_in_hand = 6
	await frames(10)
	await shot(prefix + "_0_teeth_in_hand")
	await press("fp_interact")
	await frames(18)
	await shot(prefix + "_1_opened")
	await frames(60)
	await shot(prefix + "_2_after_open")
	for i in range(3):
		await press("fp_interact")
		await frames(6)
	await shot(prefix + "_3_paid_three")
	await frames(90)
	await shot(prefix + "_4_offer")

func _run() -> void:
	await frames(5)
	m.finish_opening()
	m.player.mouse_look_enabled = false
	m.restroom.set_door_open(false, true)
	m.vent.instant_voice = true
	await _flow("a_fresh", false)
	await _flow("b_held_offer", true)
	# every tooth given: the offer comes out and the head goes in by itself
	await reset()
	m.progression.teeth_in_hand = 3
	await press("fp_interact")
	await frames(30)
	for i in range(3):
		await press("fp_interact")
		await frames(6)
	await shot("c_all_paid")
	await frames(70)
	await shot("c_offer_out")
	await frames(50)
	await shot("c_head_in")
	# the nudges: the open grate's empty grasping hand (teeth in the tank,
	# none in hand), the glinting lip (teeth in hand), the tank lid knocking
	await reset()
	m.progression.teeth = 10
	m.progression.teeth_in_hand = 0
	await press("fp_interact")
	await frames(80)
	await shot("d_beg_open")
	await frames(25)
	await shot("d_beg_closed")
	m.progression.teeth -= 4
	m.progression.teeth_in_hand = 4
	await frames(40)
	await shot("e_lip_glint")
	m.vent.close()
	m.progression.teeth += 4
	m.progression.teeth_in_hand = 0
	m.vent._paid_ever = false
	await frames(30)
	m.player.global_position = m.restroom.toilet.to_global(Vector3(0, 0.9, 0.95))
	await frames(3)
	look_at_point(m.restroom.tank_art.to_global(Vector3(0, 0.34, 0)))
	var t := 0
	while not m.restroom.tank_art.call("jostling") and t < 600:
		await process_frame
		t += 1
	await frames(5)
	await shot("f_tank_knock")
	await frames(40)
	await shot("f_tank_still")
	for f in ["user://capture-vent-teeth.bin", "user://capture-vent-teeth-keys.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	m.queue_free()
	await frames(2)
	quit(0)
