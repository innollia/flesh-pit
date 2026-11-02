extends SceneTree

## A whole vent trade with real input (isolated save): open the grate, put
## teeth on the lip, wait for the offer, take it with F or the right button,
## and check the item really arrived. Prints every line the being voices.
##   CAP_OUT=<dir> [TAKE=fp_interact|fp_pick] godot_console --path game --resolution 960x540 --fixed-fps 60 --script res://tests/capture_vent_trade.gd

var m: Node3D
var out := ""
const SAVE := "user://capture-vent-trade.bin"

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = SAVE
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String) -> void:
	await frames(1)
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("CAP ", name)

func look_at_point(target: Vector3) -> void:
	var eye: Vector3 = m.player.camera.global_position
	var d := target - eye
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = atan2(d.y, Vector2(d.x, d.z).length())

func press(action: String, hold: int = 3) -> void:
	Input.action_press(action)
	await frames(hold)
	Input.action_release(action)
	await frames(2)

func items() -> String:
	var p = m.progression
	return "knife %s barriers %d sprays %d feed %d bag %s junk %d belt %s" % [p.tools.has("knife") if p.tools.has_method("has") else "?", p.barriers, p.sprays.count() if p.sprays.has_method("count") else -1, p.canary_feed, p.has_bag, p.junk_taken, p.has_belt]

func _run() -> void:
	var take := OS.get_environment("TAKE")
	if take == "":
		take = "fp_interact"
	await frames(5)
	m.finish_opening()
	m.vent.line_spoken.connect(func(id): print("  VOICE ", id, " | ", FPSubtitles.line_text(id)))
	m.restroom.set_door_open(false, true)
	m.lever_settled = true
	m.vent._first_flush_heard = true
	m.progression.teeth = 0
	m.progression.teeth_in_hand = 30
	# under the vent, looking up at it
	var vent: Vector3 = FPRestroom.VENT_CENTER
	m.player.global_position = Vector3(vent.x - 0.5, 0.95, vent.z - 0.5)
	await frames(3)
	look_at_point(vent)
	await frames(3)
	print("  target ", m.interact_target(), " | ", items())
	await press("fp_interact")
	await frames(60)
	print("  open ", m.vent.is_open, " target ", m.interact_target())
	# hold to put teeth one by one
	look_at_point(vent)
	Input.action_press("fp_interact")
	await frames(240)
	Input.action_release("fp_interact")
	await frames(150)
	print("  in hand ", m.progression.teeth_in_hand, " offers ", m.vent.offers)
	await shot("offer")
	look_at_point(m.vent.offer_center())
	await frames(3)
	print("  target ", m.interact_target(), " pick_ok ", m.interact_ring.get("pick_ok"))
	await press(take)
	await frames(90)
	print("  after ", take, ": offers ", m.vent.offers, " | ", items(), " | hands ", m.progression.hands.left, "/", m.progression.hands.right)
	await shot("taken")
	quit(0)
