extends SceneTree

## The vent being's hand as a model (FPVent art HAND_MODEL: 0 the tube hand,
## 1 the Godot XR Tools hand, 2 the Blender hand), in the real restroom: the
## offer as the player sees it standing and with the head in, the hands up
## close with and without their items, and their backs on the way down.
## Real rendering, isolated save.
##   VENT_HAND_MODEL=<0|1|2> CAP_OUT=<dir> godot_console --path game --resolution 1280x720 --fixed-fps 60 --script res://tests/capture_vent_hand_models.gd

const THREE := ["knife", "spray_cheap", "barrier"]

var m: Node3D
var out := ""

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	var art_script: Script = load("res://main/art/fp_vent.gd")
	art_script.set("hand_model", int(OS.get_environment("VENT_HAND_MODEL")))
	print("INFO model asked ", int(OS.get_environment("VENT_HAND_MODEL")), " in use ", art_script.call("_model_kind"))
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = "user://capture-vent-hand-models.bin"
	m.user_keybinds_path = "user://capture-vent-hand-models-keys.json"
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("CAP ", name)

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

## A narrow lens on `p` for one picture, then the game's own lens again.
func zoom_shot(name: String, p: Vector3, fov: float) -> void:
	var yaw: float = m.player._yaw
	var pitch: float = m.player._pitch
	var was: float = m.player.camera.fov
	look_at_point(p)
	m.player.camera.fov = fov
	await frames(3)
	await shot(name)
	m.player.camera.fov = was
	m.player._yaw = yaw
	m.player._pitch = pitch
	await frames(2)

func show_items(on: bool) -> void:
	for s in m.vent.art.get("_offers"):
		(s as Node3D).visible = on

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
	# on the way down: the backs of the hands and the nails
	for f in [40, 48, 56]:
		await frames(8 if f > 40 else 40)
		await zoom_shot("down_%d" % f, m.vent.offer_center() + Vector3(0, 0.04, 0), 32.0)
	await frames(80)
	# standing, before the head goes in
	look_at_point(m.vent.offer_center())
	await frames(3)
	await shot("stand_3")
	await zoom_shot("stand_3_zoom", m.vent.offer_center(), 30.0)
	# the head in: the view the player picks from
	m.use_vent()
	await frames(110)
	await shot("look_3")
	await zoom_shot("look_3_zoom", m.vent.offer_center(), 38.0)
	show_items(false)
	await zoom_shot("look_3_bare", m.vent.offer_center(), 38.0)
	show_items(true)
	offer(["spray_cheap"])
	await frames(90)
	await shot("look_1")
	await zoom_shot("look_1_zoom", m.vent.offer_center(), 24.0)
	show_items(false)
	await zoom_shot("look_1_bare", m.vent.offer_center(), 24.0)
	for f in ["user://capture-vent-hand-models.bin", "user://capture-vent-hand-models-keys.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	m.queue_free()
	quit(0)
