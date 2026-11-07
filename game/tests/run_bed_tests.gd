extends SceneTree

## The flesh beds (tools/build_biome_beds.py) and the events over them
## (audio/fp_body_events.gd). Owner, listening 2026-11-07: "a set of different
## white noises": 8 s loops, 3 dB of movement, one bed all under 60 Hz. The real
## main scene and manifest, an isolated save, a stand-in only for the walls.
##   godot_console --headless --path game --script res://tests/run_bed_tests.gd

const SAVE := "user://bed-test.bin"
const MANIFEST := "res://audio/manifest.json"
const FLESH_BEDS := ["body_a", "body_b", "fat_caves", "rib_vault", "gut_folds", "cloth_wads", "hair_thicket"]
const OWN_LAYER := ["amb_body_a", "amb_body_b", "amb_fat_caves", "amb_rib_vault", "amb_gut_folds", "amb_cloth_wads", "amb_hair_thicket"]
## Longest a bed may run on one cycle's worth of sound: the old 8 s is the fault.
const MIN_LOOP_S := 20.0
## Level range of a bed's own layer, in the band a laptop plays (200 Hz up).
const MIN_RANGE_DB := 8.0
const MIN_OVER_200 := 0.4
## Biome layers once carried the body layer, so all of them were one colour.
const BODY_LAYERS := ["amb_body_a", "amb_body_b"]
## Before this work a biome bed ran 3 layers; a take may not make it more.
const MAX_VOICES := 3
const SIM_MINUTES := 30.0
var _passed := 0
var _failed := 0
var m: Node3D

class Walls extends Node:
	var solid_from := 3.0
	var origin := Vector3.ZERO
	func density_at(p: Vector3) -> float:
		return 1.0 if p.distance_to(origin) >= solid_from else 0.0

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = SAVE
	m.user_keybinds_path = "user://keybinds_test_beds.json"
	root.add_child(m)
	_run.call_deferred()

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  ok   ", msg)
	else:
		_failed += 1
		print("  FAIL ", msg)

func _run() -> void:
	for i in range(5):
		await process_frame
	m.finish_opening()
	var bank := FDKSoundBank.from_file(MANIFEST)
	_test_layers(bank)
	_test_beds(bank)
	await _test_events(m.get_node("AudioHookup"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 or _passed == 0 else 0)

## Left channel at 12 kHz: enough for the level above 200 Hz.
func _wav_left(path: String) -> PackedFloat32Array:
	var b := FileAccess.get_file_as_bytes(path)
	var at := 12
	while at + 8 < b.size():
		var size := b.decode_u32(at + 4)
		if b.slice(at, at + 4).get_string_from_ascii() == "data":
			var ch := b.decode_u16(22)
			var out := PackedFloat32Array()
			out.resize(size / (8 * ch))
			for i in range(out.size()):
				out[i] = b.decode_s16(at + 8 + i * 8 * ch) / 32768.0
			return out
		at += 8 + size + (size & 1)
	return PackedFloat32Array()

## x less its 5 ms running mean: a high-pass near 200 Hz.
func _over_200(x: PackedFloat32Array) -> PackedFloat32Array:
	var w := 60
	var out := PackedFloat32Array()
	out.resize(x.size())
	var acc := 0.0
	for i in range(x.size()):
		acc += x[i]
		if i >= w:
			acc -= x[i - w]
		out[i] = x[i] - acc / float(mini(i + 1, w))
	return out

func _energy(x: PackedFloat32Array) -> float:
	var e := 0.0
	for v in x:
		e += v * v
	return e

func _range_db(x: PackedFloat32Array) -> float:
	var size := 4800  # 400 ms
	var lv: Array[float] = []
	var i := 0
	while i + size <= x.size():
		lv.append(10.0 * log(_energy(x.slice(i, i + size)) / size + 1e-12) / log(10.0))
		i += size / 2
	lv.sort()
	return lv[int(lv.size() * 0.95)] - lv[int(lv.size() * 0.1)]

func _test_layers(bank: FDKSoundBank) -> void:
	var lengths := {}
	for id in OWN_LAYER:
		var sec := float(bank.sounds[id].get("loop_seconds", 0.0))
		lengths[sec] = true
		_ok(sec >= MIN_LOOP_S, "%s is a long loop (%.0f s)" % [id, sec])
		var x := _wav_left(String(bank.sounds[id]["files"][0]))
		var hi := _over_200(x)
		var share := _energy(hi) / maxf(_energy(x), 1e-9)
		_ok(share >= MIN_OVER_200, "%s lives where a laptop plays (%.0f%% over 200 Hz)" % [id, share * 100.0])
		var r := _range_db(hi)
		_ok(r >= MIN_RANGE_DB, "%s swells and falls, not a level noise (%.1f dB)" % [id, r])
	_ok(lengths.size() == OWN_LAYER.size(), "no two beds share a loop length")

func _test_beds(bank: FDKSoundBank) -> void:
	for bed in FLESH_BEDS:
		var layers: Array = bank.beds[bed]
		_ok(layers.size() == 2 and String(layers[1]).begins_with("amb_heart_"), "%s is its own layer and the heart %s" % [bed, str(layers)])
		if not String(bed).begins_with("body"):
			_ok(not layers.has(BODY_LAYERS[0]) and not layers.has(BODY_LAYERS[1]), "%s does not sit on the body layer" % bed)

func _test_events(hk: Node) -> void:
	var ev: Node = hk.get_node("BodyEvents")
	var d: FDKAudioDirector = hk.get("director")
	var table: Dictionary = ev.call("bed_table")
	for bed in FLESH_BEDS:
		_ok(table.has(bed), "%s has events" % bed)
	# the room has none, however long the player stays
	_ok(d.current_bed == "restroom", "the test starts in the restroom")
	for i in range(600):
		ev.call("step", 0.5, "restroom")
	_ok((ev.get("played") as Array).is_empty(), "no body events in the restroom")
	# the hookup drives this node by itself; from here the test does
	hk.set_process(false)
	var walls := Walls.new()
	walls.origin = (m.player as Node3D).global_position
	ev.set("terrain", walls)
	var r := RandomNumberGenerator.new()
	r.seed = 7
	ev.set("rng", r)
	for bed in FLESH_BEDS:
		d.set_bed(bed, 0.0)
		d.advance(0.016)
		var before: int = (ev.get("played") as Array).size()
		var reads_before: int = ev.get("density_reads")
		var own: Array = (table[bed]["takes"] as Array).map(func(t): return String(t["id"]))
		var t := 0.0
		var gaps_ok := true
		var off_table := 0
		var last_end := -1.0
		var last_n := before
		var gap_min: float = table[bed]["gap"][0]
		var most_voices := 0
		while t < SIM_MINUTES * 60.0:
			ev.call("step", 0.25, bed)
			t += 0.25
			var played: Array = ev.get("played")
			var v: Node = ev.call("voice")
			if played.size() != last_n:
				last_n = played.size()
				if last_end >= 0.0 and t - last_end < gap_min - 1.0:
					gaps_ok = false
				if not own.has(String(played.back())):
					off_table += 1
			if v != null:
				last_end = t
			var voices := 0
			for layer in d._bed_players.keys():
				if d.bed_layer_db(layer) > -60.0:
					voices += 1
			most_voices = maxi(most_voices, voices + (1 if v != null else 0))
		var n: int = (ev.get("played") as Array).size() - before
		_ok(n >= 20 and n <= 150, "%s: %d takes in %.0f min, now and then" % [bed, n, SIM_MINUTES])
		_ok(off_table == 0, "%s plays only its own takes" % bed)
		_ok(gaps_ok, "%s leaves at least %.0f s between takes" % [bed, gap_min])
		_ok(most_voices <= MAX_VOICES, "%s never runs more than %d voices (%d)" % [bed, MAX_VOICES, most_voices])
		var reads: int = int(ev.get("density_reads")) - reads_before
		_ok(reads <= n * 32, "%s: %d density reads for %d takes" % [bed, reads, n])
		await process_frame
	var played_all: Array = (ev.get("played") as Array).duplicate()
	var twice := 0
	for i in range(1, played_all.size()):
		if played_all[i] == played_all[i - 1]:
			twice += 1
	_ok(twice == 0, "no take twice in a row")
	# a spatial take comes from a solid spot, a take with no wall from nowhere
	ev.call("play_take", "body_glug", "body_a")
	var at: Variant = ev.get("last_spot")
	_ok(at is Vector3 and walls.density_at(at) > 0.5, "a spatial take sits in a real wall (%s)" % str(at))
	_ok(ev.call("voice") is AudioStreamPlayer3D, "...and plays from there")
	walls.solid_from = 100.0
	ev.call("play_take", "body_glug", "body_a")
	_ok(ev.get("last_spot") == null and ev.call("voice") is AudioStreamPlayer, "no wall in reach: it plays without a place")
	await process_frame
	await process_frame
	_ok(String((ev.call("voice") as Node).get("bus")) == "Music", "a take is on the Music bus with its bed")
	# it follows the bed out
	d.set_bed("restroom", 0.0)
	d.advance(0.016)
	ev.call("step", 0.016, "restroom")
	_ok(ev.call("voice") == null, "a take under way goes with its bed")
