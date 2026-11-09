extends SceneTree

## The vent trade with the tags over the offered items (isolated save): put
## teeth on the lip with real input, the head goes in, then shots of the
## tags for every item set, and after the pick (no tags).
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --script res://tests/capture_vent_trade_labels.gd

var m: Node3D
var out := ""
const SAVE := "user://capture-vent-trade-labels.bin"

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.user_keybinds_path = "user://keybinds_test_vent_trade_labels.json"
	m.save_path = SAVE
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String) -> void:
	await frames(1)
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	var tags: Array = m.offer_labels.tag_rects()
	var texts := []
	for i in range(m.vent.offers.size()):
		texts.append(" / ".join(m.offer_labels.tag_texts(i)))
	print("CAP ", name, " tags ", tags.size(), " ", tags, " ", texts)

func look_at_point(target: Vector3) -> void:
	var d: Vector3 = target - m.player.camera.global_position
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = atan2(d.y, Vector2(d.x, d.z).length())

func offer(ids: Array) -> void:
	var typed: Array[String] = []
	for id in ids:
		typed.append(String(id))
	m.vent._set_offers(typed)

func _run() -> void:
	await frames(5)
	m.finish_opening()
	m.restroom.set_door_open(false, true)
	m.lever_settled = true
	m.vent._first_flush_heard = true
	m.progression.teeth = 0
	m.progression.teeth_in_hand = 30
	var vent: Vector3 = FPRestroom.VENT_CENTER
	m.player.global_position = Vector3(vent.x - 0.5, 0.95, vent.z - 0.5)
	await frames(3)
	look_at_point(vent)
	await frames(3)
	Input.action_press("fp_interact")
	await frames(3)
	Input.action_release("fp_interact")
	await frames(60)
	look_at_point(vent)
	Input.action_press("fp_interact")
	await frames(240)
	Input.action_release("fp_interact")
	await frames(30)
	await shot("labels_offer_out")
	await frames(150)
	print("  offers ", m.vent.offers, " looking ", m.hand_motions.vent_looking())
	await shot("labels_trade_paid")
	for group in [["canary_feed", "spray_deep", "tumor_bag"], ["blender", "junk"], ["big_saw"], ["barrier", "spray_cheap", "knife"]]:
		offer(group)
		await frames(90)
		await shot("labels_" + "_".join(group))
	look_at_point(m.vent.offer_center())
	await frames(3)
	Input.action_press("fp_interact")
	await frames(3)
	Input.action_release("fp_interact")
	await frames(90)
	await shot("labels_after_take")
	for f in [SAVE, "user://keybinds_test_vent_trade_labels.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	quit(0)
