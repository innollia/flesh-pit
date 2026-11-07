extends SceneTree

## Every flesh bed as the engine really mixes it, heart and events and buses,
## for tools/measure_beds.py-style comparison and for listening. The movie writer
## records the engine's own audio. Isolated save. The player stands in the flesh
## on real terrain; the bed is forced so one take covers all seven in a few
## minutes, and the first event of each comes after 3 s instead of 6-20 s, the
## later ones at their real gaps. Prints "SEG <bed> <start frame>" and the most
## voices that ran at once in each.
##   godot_console --path game --resolution 480x270 --write-movie <dir>/beds.avi --fixed-fps 30 --script res://tests/capture_beds.gd

const SAVE := "user://capture-beds.bin"
const BEDS := ["body_a", "body_b", "fat_caves", "rib_vault", "gut_folds", "cloth_wads", "hair_thicket"]
const SECONDS_EACH := 24
var m: Node3D
var _frame := 0

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = SAVE
	m.user_keybinds_path = "user://keybinds_test_beds.json"
	root.add_child(m)
	_run.call_deferred()

func _run() -> void:
	for i in range(5):
		await process_frame
		_frame += 1
	m.finish_opening()
	var hk: Node = m.get_node("AudioHookup")
	var d: FDKAudioDirector = hk.get("director")
	var ev: Node = hk.get_node("BodyEvents")
	hk.set_process(false)
	m.set_process(false)
	m.set_physics_process(false)
	m.player.set_physics_process(false)
	m.player.global_position = m.RESTROOM_CENTER + Vector3(0, 0, -6.0)
	for bed in BEDS:
		print("SEG %s %d" % [bed, _frame])
		d.set_bed(bed, 0.5)
		ev.call("step", 0.0, bed)
		ev.set("_wait", 3.0)
		var most := 0
		for i in range(SECONDS_EACH * 30):
			ev.call("step", 1.0 / 30.0, bed)
			await process_frame
			_frame += 1
			if i > 30:
				var voices := 0
				for layer in d._bed_players.keys():
					if d.bed_layer_db(layer) > -60.0:
						voices += 1
				most = maxi(most, voices + (1 if ev.call("voice") != null else 0))
		print("VOICES %s %d spot %s" % [bed, most, str(ev.get("last_spot"))])
	print("SEG end %d" % _frame)
	print("TAKES ", ev.get("played"))
	print("READS ", ev.get("density_reads"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit()
