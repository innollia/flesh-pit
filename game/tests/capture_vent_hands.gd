extends SceneTree

## The vent being's hands (user 2026-11-03): one hand per offered item, held
## out close in front of the eye, bright and slender, a straight wrist on the
## way down, and no eyes in the duct at any time. Seen from several places
## in the restroom, with 1, 3, 5 and 8 items, through the descent, and a bare
## hand up close. Isolated save.
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --script res://tests/capture_vent_hands.gd

var m: Node3D
var out := ""

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.user_keybinds_path = "user://keybinds_test_vent_hands.json"
	m.save_path = "user://capture-vent-hands.bin"
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String) -> void:
	await frames(2)
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("CAP ", name)

func look_at_point(p: Vector3) -> void:
	var eye: Vector3 = m.player.camera.global_position
	var d := p - eye
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = atan2(d.y, Vector2(d.x, d.z).length())

func stand(at: Vector3) -> void:
	m.player.global_position = at
	await frames(2)

func offer(ids: Array) -> void:
	var typed: Array[String] = []
	for id in ids:
		typed.append(String(id))
	m.vent._set_offers(typed)

func _run() -> void:
	await frames(5)
	m.finish_opening()
	m.restroom.set_door_open(false, true)
	var V: Vector3 = FPRestroom.VENT_CENTER
	print("VENT ", V, " player ", m.player.global_position, " eye ", m.player.camera.global_position)
	await stand(Vector3(0.1, 0.9, 0.2))
	look_at_point(V + Vector3(0, -0.2, 0))
	m.vent.open(30)
	await frames(50)
	# --- three items, the descent frame by frame
	offer(["knife", "spray_cheap", "barrier"])
	for f in [10, 20, 30, 40, 50, 60]:
		await frames(10)
		look_at_point(m.vent.offer_center())
		await shot("descent_%02d" % f)
	await frames(60)
	look_at_point(m.vent.offer_center())
	await shot("three_near")
	# from other places in the room
	for spot in [["three_far", Vector3(1.4, 0.9, 0.9)], ["three_grate_side", Vector3(-1.6, 0.9, -0.5)], ["three_under", Vector3(-0.5, 0.9, -0.7)], ["three_door", Vector3(0.6, 0.9, 1.2)]]:
		await stand(spot[1])
		await frames(150)
		look_at_point(m.vent.offer_center())
		await shot(spot[0])
		# the arms where they leave the opening, past the hanging grate
		look_at_point(V + Vector3(0, -0.3, 0))
		await shot(spot[0] + "_lip")
	# --- counts: one, five, eight
	await stand(Vector3(0.1, 0.9, 0.2))
	for set in [["one", ["spray_deep"]], ["five", ["knife", "spray_cheap", "barrier", "canary_feed", "junk"]], ["eight", ["barrier", "spray_cheap", "knife", "spray_deep", "blender", "big_saw", "canary_feed", "tumor_bag"]]]:
		offer(set[1])
		await frames(120)
		look_at_point(m.vent.offer_center())
		await shot("count_" + set[0])
		print("HANDS ", set[0], " offers ", m.vent.offers.size(), " hands ", m.vent.art.call("hand_count"))
	# --- the wrist on the way down, close (narrow lens, one hand)
	offer([])
	await frames(40)
	offer(["spray_cheap"])
	m.player.camera.fov = 34.0
	for f in range(8):
		await frames(10)
		look_at_point(m.vent.offer_center() + Vector3(0, 0.06, 0))
		await shot("wrist_%02d" % (f * 10 + 10))
	m.player.camera.fov = FPSettings.base_fov(m.player.camera)
	# --- a bare hand up close (narrow lens) and the duct with no eyes
	offer(["spray_cheap", "barrier", "knife"])
	await frames(120)
	var item: Node3D = m.vent.art.call("item_node", 1)
	m.player.camera.fov = FPSettings.base_fov(m.player.camera)
	look_at_point(item.global_position)
	var fov: float = m.player.camera.fov
	m.player.camera.fov = 22.0
	await frames(3)
	await shot("close_item")
	for s in m.vent.art.get("_offers"):
		s.visible = false
	await shot("close_bare")
	for s in m.vent.art.get("_offers"):
		s.visible = true
	m.player.camera.fov = fov
	# --- taking the middle one with F: the others go back up
	await stand(Vector3(0.1, 0.9, 0.2))
	look_at_point(m.vent.offer_center())
	await frames(30)
	m.take_vent_offer()
	for f in [6, 18, 30, 48]:
		await frames(6 if f == 6 else 12 if f < 30 else 18)
		await shot("take_%02d" % f)
	# eyes: none in the duct, open or not, calm or frantic
	m.vent.close()
	await frames(40)
	m.vent.on_flush()
	m.vent.open(0)
	await frames(60)
	look_at_point(V + Vector3(0, 0.25, 0))
	m.player.camera.fov = 30.0
	await shot("duct_open_frantic")
	m.player.camera.fov = fov
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture-vent-hands.bin"))
	m.queue_free()
	quit(0)
