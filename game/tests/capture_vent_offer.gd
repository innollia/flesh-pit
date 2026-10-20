extends SceneTree

## The vent being's hand pushing out an offer, seen from where the player
## stands to trade (near, under the vent) and from across the room. Isolated save.
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --script res://tests/capture_vent_offer.gd

var m: Node3D
var out := ""

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = "user://capture-vent-offer.bin"
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
	look_at_point(FPRestroom.VENT_CENTER + Vector3(0, -0.12, 0))
	await frames(2)

func _run() -> void:
	await frames(5)
	m.finish_opening()
	m.restroom.set_door_open(false, true)
	await stand(Vector3(0.1, 0.9, 0.2))
	await frames(30)
	m.vent.open(30)
	await frames(50)
	m.progression.teeth_in_hand = 30
	m.place_teeth_at_vent()
	await frames(40)
	await shot("vent_offer_mid")
	await frames(60)
	await shot("vent_offer_near")
	await stand(Vector3(1.2, 0.9, 0.9))
	await shot("vent_offer_far")
	await stand(Vector3(-0.2, 0.9, -0.1))
	await shot("vent_offer_under")
	await stand(Vector3(0.1, 0.9, 0.2))
	m.take_vent_offer()
	await frames(20)
	await shot("vent_offer_take")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture-vent-offer.bin"))
	m.queue_free()
	quit(0)
