extends SceneTree

## The head in under the vent (user 2026-11-07): the being's hands held out
## in the middle of the view with 3, 5 and 8 items, and the head going in
## and coming out frame by frame. Real rendering, isolated save.
##   CAP_OUT=<dir> godot_console --path game --resolution 1280x720 --fixed-fps 60 --script res://tests/capture_vent_look.gd

const THREE := ["knife", "spray_cheap", "barrier"]
const FIVE := ["knife", "spray_cheap", "barrier", "canary_feed", "junk"]
const EIGHT := ["barrier", "spray_cheap", "knife", "spray_deep", "big_saw", "junk", "canary_feed", "blender"]

var m: Node3D
var out := ""

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = "user://capture-vent-look.bin"
	m.user_keybinds_path = "user://capture-vent-look-keys.json"
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("CAP ", name, " eye=", m.player.camera.global_position, " w=", m.hand_motions.vent_eye_weight())

func look_at_point(p: Vector3) -> void:
	var eye: Vector3 = m.player.camera.global_position
	var d := p - eye
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = atan2(d.y, Vector2(d.x, d.z).length())

func offer(ids: Array) -> void:
	var typed: Array[String] = []
	for id in ids:
		typed.append(String(id))
	m.vent._set_offers(typed)

## How much of each middle finger's length the eye sees (1 = lying across
## the view, 0 = seen end on), printed for the record.
func shown(tag: String) -> void:
	var art: Node3D = m.vent.art
	var eye: Vector3 = m.player.camera.global_position
	var out_s := ""
	for i in range(int(art.call("hand_count"))):
		var hand: Node3D = (art.call("item_node", i) as Node3D).get_parent()
		var knuckle: Vector3 = (hand.get_node("Finger1") as Node3D).global_position
		var tip: Node3D = hand.get_node("Finger1/Mid/Tip")
		var length: float = art.FINGERS[1][2]
		var end: Vector3 = tip.global_transform * Vector3(0, -length * float(art.PHALANX[2]), 0)
		var view := ((knuckle + end) * 0.5 - eye).normalized()
		var chord := end - knuckle
		out_s += " %.2f" % ((chord - view * chord.dot(view)).length() / length)
	print("INFO shown ", tag, out_s)

func _run() -> void:
	await frames(5)
	m.finish_opening()
	m.restroom.set_door_open(false, true)
	m.vent.instant_voice = true
	m.player.global_position = Vector3(0.3, 0.9, 0.3)
	await frames(2)
	look_at_point(FPRestroom.VENT_CENTER + Vector3(0, -0.2, 0))
	m.vent.open(30)
	await frames(50)
	offer(THREE)
	await frames(80)
	await shot("out_before")
	# going in
	m.use_vent()
	for i in range(8):
		await frames(6)
		await shot("in_%d" % i)
	await frames(60)
	await shot("hands_3")
	shown("hands_3")
	offer(FIVE)
	await frames(90)
	await shot("hands_5")
	shown("hands_5")
	offer(EIGHT)
	await frames(90)
	await shot("hands_8")
	shown("hands_8")
	# CAP_QUICK=1: only the normal view and the three counts (hand iteration)
	if OS.get_environment("CAP_QUICK") != "":
		m.queue_free()
		quit(0)
		return
	offer(THREE)
	await frames(90)
	# the eye turned to the outer hand
	m.player._yaw -= 0.5
	await frames(4)
	await shot("pan_right")
	m.player._yaw += 0.5
	await frames(4)
	# coming out
	m.hand_motions.release_vent_look()
	for i in range(6):
		await frames(6)
		await shot("out_%d" % i)
	await frames(30)
	# the take with bare hands: the hand goes out, the head comes back with it
	m.use_vent()
	await frames(60)
	m.use_vent()
	for i in range(8):
		await frames(9)
		await shot("bare_take_%d" % i)
	await frames(60)
	m.vent.close()
	await frames(30)
	m.vent.open(30)
	await frames(30)
	offer(THREE)
	await frames(80)
	# back in, with the big saw in both hands: nothing of it in the frame
	m.progression.grant_item("big_saw")
	m.equip_tool("big_saw")
	await frames(30)
	await shot("saw_outside")
	m.use_vent()
	await frames(60)
	await shot("hands_3_again")
	# the take: the hand goes out to the item, the head comes back with it
	m.use_vent()
	for i in range(8):
		await frames(9)
		await shot("take_%d" % i)
	for f in ["user://capture-vent-look.bin", "user://capture-vent-look-keys.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	m.queue_free()
	quit(0)
