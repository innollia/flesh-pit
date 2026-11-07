extends SceneTree

## The room's music as the engine really plays it (audio/fp_music.gd): the
## movie writer records the mix through the room, the bowl and the situations.
## Isolated save. Prints "SEG <name> <frame>" for each segment. It runs on the
## old music code as well, for the before-and-after of the bowl.
## FP_CAPTURE_BOWL=1 stops after the bowl and mutes every bus but Music, so the
## measurement of the seam is not the sound effects of kneeling down.
##   godot_console --path game --resolution 480x270 --write-movie <dir>/room.avi --fixed-fps 30 --script res://tests/capture_room_music.gd

const SAVE := "user://capture-room-music.bin"
var m: Node3D
var _frame := 0

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.user_keybinds_path = "user://keybinds_test_room_music.json"
	m.save_path = SAVE
	root.add_child(m)
	_run.call_deferred()

func secs(s: float) -> void:
	for i in range(int(s * 30.0)):
		await process_frame
		_frame += 1

func seg(name: String) -> void:
	print("SEG %s %d" % [name, _frame])

## Out and back with main held, as in run_music_tests.gd.
func trip(out: Callable) -> void:
	m.player.global_position = m.RESTROOM_CENTER + Vector3(0, 0, -6.0)
	await secs(5.5)
	out.call()
	await secs(0.2)
	m.player.global_position = m.RESTROOM_CENTER

func hold() -> void:
	m.set_process(false)
	m.set_physics_process(false)
	m.player.set_physics_process(false)

func _run() -> void:
	var bowl_only := OS.get_environment("FP_CAPTURE_BOWL") == "1"
	if bowl_only:
		for i in range(AudioServer.bus_count):
			var bus := AudioServer.get_bus_name(i)
			AudioServer.set_bus_mute(i, bus != &"Music" and bus != &"Master")
	await secs(0.2)
	m.finish_opening()
	await secs(1.0)
	hold()
	seg("start")
	await secs(19.0)
	seg("quiet")
	await secs(12.0)
	seg("settle_in")
	m.start_settlement()
	await secs(12.0)
	seg("settle_out")
	m.leave_settlement()
	hold()
	await secs(14.0)
	if bowl_only:
		seg("end")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
		m.queue_free()
		quit(0)
		return
	seg("dread_trip")
	await trip(func(): m.excavated_cells += 60)
	seg("dread")
	await secs(36.0)
	seg("gut")
	m.stomach.fill = m.stomach_config.capacity
	await secs(16.0)
	m.stomach.fill = 0.0
	seg("wrong_trip")
	await trip(func(): m.progression.eat_tumor_kind("T1"))
	seg("wrong")
	await secs(30.0)
	seg("gold")
	m.toilet.vomit_into(240.0)
	m.pull_lever()
	hold()
	await secs(22.0)
	seg("cold_trip")
	await trip(func(): pass)
	m.player.global_position = m.RESTROOM_CENTER + Vector3(0, 0, -6.0)
	await secs(1.0)
	m.die("capture")
	hold()
	seg("cold")
	await secs(1.0)
	m.wake_lids.set("_t", -1.0)
	await secs(31.0)
	seg("end")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	m.queue_free()
	quit(0)
