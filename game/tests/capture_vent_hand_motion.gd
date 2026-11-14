extends SceneTree

## The grain of the vent being's hands in motion (2026-11-14): three hands
## come down one after another showing their backs and nails, turn over as
## the forearms swing out, the item's weight settles, and after the take
## the hands draw back at their ease. A frame every MOTION_STEP frames
## (motion_000.png ...), to be put together into a strip or an animation.
## Real rendering, isolated save.
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --script res://tests/capture_vent_hand_motion.gd
## VENT_BUILD=B shows build B; VENT_MOOD=1 a frantic being (the snatch);
## VENT_FLIP=0 the hands coming down palm first; VENT_VARIANT a candidate.

const MOTION_STEP := 3

var m: Node3D
var out := ""
var shot_n := 0

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	if OS.get_environment("VENT_BUILD") == "B":
		load("res://main/art/fp_vent.gd").set("build_b", true)
	# VENT_VARIANT=tone,grace,angle turns on candidates kept for the user's
	# pick (FPVent art HAND_TONE, HAND_GRACE, HAND_ANGLE); VENT_FLIP=0 has the
	# hands come down palm first
	for v in OS.get_environment("VENT_VARIANT").split(",", false):
		load("res://main/art/fp_vent.gd").set("hand_" + v, true)
	if OS.get_environment("VENT_FLIP") == "0":
		load("res://main/art/fp_vent.gd").set("hand_flip", false)
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.user_keybinds_path = "user://keybinds_capture_vent_hand_motion.json"
	m.save_path = "user://capture-vent-hand-motion.bin"
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func look_at_point(p: Vector3) -> void:
	var eye: Vector3 = m.player.camera.global_position
	var d := p - eye
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = atan2(d.y, Vector2(d.x, d.z).length())

## `n` frames, one saved every MOTION_STEP.
func film(n: int) -> void:
	for i in range(n):
		await process_frame
		# a narrow lens that follows the hands
		m.player.camera.fov = 40.0
		look_at_point(m.vent.offer_center() + Vector3(0, -0.08, 0))
		if i % MOTION_STEP == 0:
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png(out.path_join("motion_%03d.png" % shot_n))
			shot_n += 1

func _run() -> void:
	await frames(5)
	m.finish_opening()
	m.restroom.set_door_open(false, true)
	m.vent.instant_voice = true
	var V: Vector3 = FPRestroom.VENT_CENTER
	m.player.global_position = Vector3(V.x + 0.65, 0.9, V.z + 0.98)
	await frames(2)
	look_at_point(V + Vector3(0, -0.45, 0))
	m.vent.open(30)
	await frames(50)
	if OS.get_environment("VENT_MOOD") != "":
		m.vent.art.call("set_eye_mood", 1.0)
	var typed: Array[String] = ["knife", "spray_cheap", "barrier"]
	m.vent._set_offers(typed)
	# the offer: 1.4 s out, then held
	await film(108)
	# the take, straight from the art (the trade itself is not what is shown)
	m.vent.art.call("take_item", 1)
	await film(84)
	print("CAP motion frames ", shot_n)
	for f in ["user://capture-vent-hand-motion.bin", "user://keybinds_capture_vent_hand_motion.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	m.queue_free()
	quit(0)
