extends SceneTree

## The first loop's nudges, in the real game (isolated save):
## settle_vomit (mid heave over the bowl, no second body in view),
## near_toilet (back at the bowl with a part-full stomach: the V key shows),
## door_open (the door just opened onto the flesh: the eat nudge shows).
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --script res://tests/capture_first_loop_nudges.gd

var m: Node3D
var out := ""
const SAVE := "user://capture-first-loop.bin"

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.user_keybinds_path = "user://keybinds_test_first_loop_nudges.json"
	m.save_path = SAVE
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String) -> void:
	await frames(2)
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("CAP ", name)

func look_at_point(target: Vector3) -> void:
	var eye: Vector3 = m.player.camera.global_position
	var d := target - eye
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = atan2(d.y, Vector2(d.x, d.z).length())

func _run() -> void:
	await frames(5)
	m.finish_opening()
	m.restroom.set_door_open(false, true)
	# back at the bowl, a third full, never settled
	m.stomach.add_flesh(50.0)
	# standing in front of the bowl, as a player walks up to it
	m.player.global_position = m.restroom.toilet.global_position + Vector3(0.0, 0.95, 0.75)
	await frames(2)
	look_at_point(m.restroom.toilet.global_position + Vector3(0.0, 0.4, 0.0))
	await frames(30)
	print("  vomit_hint ", m.opening_view.hints.vomit_hint, " fill ", snappedf(m.stomach.fill_ratio(), 0.01))
	await shot("near_toilet")
	m.request_vomit()
	await frames(8)
	await shot("settle_start")
	await frames(40)
	await shot("settle_vomit")
	await frames(400)
	print("  settling ", m.is_settling(), " voiced ", m.vent.voiced)
	await shot("settle_wait")
	m.leave_settlement()
	m.toilet.bowl_flesh = 0.0 # a clean bowl: nothing left for the being to nag about
	# the stall door, opened from inside, the flesh beyond it
	var door: Vector3 = m.restroom.door_pivot.global_position
	m.player.global_position = Vector3(door.x + FPRestroom.DOOR_HALF_W, 0.95, door.z - 0.7)
	look_at_point(Vector3(door.x + FPRestroom.DOOR_HALF_W, 0.9, door.z + 1.0))
	await frames(10)
	m.restroom.set_door_open(true)
	await frames(90)
	print("  eat_hint ", m.opening_view.hints.eat_hint)
	await shot("door_open")
	quit(0)
