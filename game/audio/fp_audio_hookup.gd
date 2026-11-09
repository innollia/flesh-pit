extends Node
const FPProfile := preload("res://main/scripts/fp_profile.gd")

## flesh-pit sound hookup. Lives under the main scene and only READS main's
## nodes and state (duck-typed, so main can change without breaking this).
## Add it once from main.gd _ready():
##     add_child(preload("res://audio/fp_audio_hookup.gd").new())
## See audio/HOOKUP.md.

const MANIFEST := "res://audio/manifest.json"

var director: FDKAudioDirector
var main: Node
var _door_open := false
var _lid_open := false
var _coin_active := false
var _in_room := true
var _vent_open := false
var _barrier_count := 0
var _hooked_barriers: Array = []
## Recently torn spots (newest last): the creak comes from one that is
## really growing back, never from nowhere.
var _torn: Array[Vector3] = []
const TORN_KEEP := 48
const CREAK_RANGE := 8.0
var _chirp_cool := 0.0
## Squeezing past flesh: a wet strain each time the body has to give way
## harder (player.squeeze() over half), at most every SQUEEZE_COOL seconds.
const SQUEEZE_COOL := 1.4
var _squeeze_cool := 0.0
var _squeeze_was := 0.0
## Every play_event name so far, in order (tests and the run log read it).
var played_events: Array[String] = []
## Steady layers the game only reports as levels (tools/build_song_layers.py):
## the M03 magnet hum (mutation_apply.magnet_hum_level) and the ending song
## (docs/spec/00-overview.md), whose melody is faint in the flesh and louder
## outward (main.melody_level), hummed at the ending, with a second voice
## when the codex is complete (ending.voice_layers). The three song layers
## start together so they stay in step.
const LAYER_IDS := ["magnet_hum", "song_melody", "song_hum", "song_voice2"]
## The in-flesh melody stays faint; at the ending the hum takes the tune
## over and the tine fades out (under the hum the two read as a siren).
const MELODY_IN_FLESH := 0.35
## Level change per second toward the wanted level.
const LAYER_GLIDE := 3.0
var _layers := {}
var _layer_level := {}

## Stage-5 events that the game has no signal for yet. The game calls
## play_event(<name>) (or the named helper below); nothing else is needed.
const EVENT_SOUNDS := {
	"mirror_mutate": "mirror_mutate", "tumor_eat": "tumor_eat",
	"barrier_deploy": "barrier_deploy", "barrier_strain": "barrier_strain",
	"barrier_break": "barrier_break", "spray": "spray_hiss",
	"blender_drink": "blender_drink", "vent_open": "vent_open",
	"scissors": "scissors_snip", "saw": "saw_stroke", "death": "player_death",
	"ending": "ending_roll", "settle_tick": "settle_tick", "ui_click": "ui_click",
	"echo_click": "echo_click",
	"canary_chirp": "canary_chirp", "canary_warn": "canary_warn", "canary_wrong": "canary_wrong",
	"squeeze": "chew_strain", "grab_refuse": "grab_refuse", "gag": "gag_dry",
	# one clatter of the settlement rattle (repeated for the rattle's length).
	# Its own unpitched teeth knock (round8-sfx): coin_drop's 2-5 kHz sine
	# tinks every quarter second over the flush read as a canary screaming.
	"tank_rattle": "teeth_rattle",
	# M23: the stiff arm hairs shiver before a squeeze
	"hair_shiver": "hair_rustle",
	# M15: the whole pile goes down in one gulp (not the stomach swallow)
	"gulp": "gulp_whole",
	# an absurd overpay: early items tumble out of the vent
	"vent_spill": "vent_spill",
	# the mirror refuses a part the hairs cannot pay for
	"mirror_denied": "ui_deny",
}

## Settlement rattle (spec 03 6): teeth keep clattering into the tank for
## the whole rattle the toilet reports (a whole tumor adds
## FPToiletSettlement.RATTLE_TUMOR_EXTRA), one clink every RATTLE_GAP s,
## until tank_rattle_finished. The duration is only a safety stop.
const RATTLE_GAP := Vector2(0.22, 0.45)
var _rattle_left := 0.0
var _rattle_next := 0.0
var _rng := RandomNumberGenerator.new()
## The water in the restroom's pipes: one-shots at long gaps (audio/fp_pipe_water.gd).
var _pipe_water: Node
var _voice: Node
## The flesh moving on its own: one-shots over the bed (audio/fp_body_events.gd).
var _body_events: Node
## The shell's song out in the flesh (audio/fp_flesh_music.gd).
var _flesh_music: Node

## Footsteps and tears play in the room the player is in: the Room bus, a
## short reverb sent to SFX (so the SFX slider still sets them). The tiled
## restroom rings a little and stays bright, the flesh is short and damped.
## They were dry samples that the louder beds before 2026-11-07 used to cover;
## over the quieter beds they stood bare on top (docs/design/sound-music.md
## "발소리와 뜯기의 방"). Chewing and swallowing are inside the head and stay dry.
const ROOM_BUS := &"Room"
const ROOMS := {
	"tile": {"room_size": 0.34, "damping": 0.4, "spread": 0.8, "hipass": 0.12, "dry": 1.0, "wet": 0.2},
	"flesh": {"room_size": 0.2, "damping": 0.85, "spread": 0.6, "hipass": 0.15, "dry": 1.0, "wet": 0.16},
}
## Footsteps in the flesh, dB: back toward where they sat in the old beds
## (own-band margin about 0..+6 dB instead of +1..+9), still over the bed.
const FLESH_STEP_DB := -3.0
var _room := ""

func _ready() -> void:
	main = get_parent()
	director = FDKAudioDirector.new()
	director.name = "AudioDirector"
	director.manifest_path = MANIFEST
	add_child(director)
	_ensure_room_bus()
	director.room_bus = ROOM_BUS
	_set_room("tile")
	# background music per place, never in the flesh (audio/fp_music.gd)
	var music: Node = preload("res://audio/fp_music.gd").new()
	music.name = "Music"
	add_child(music)
	# one song per shell out in the flesh (audio/fp_flesh_music.gd)
	_flesh_music = preload("res://audio/fp_flesh_music.gd").new()
	_flesh_music.name = "FleshMusic"
	add_child(_flesh_music)
	_pipe_water = preload("res://audio/fp_pipe_water.gd").new()
	_pipe_water.name = "PipeWater"
	_pipe_water.set("director", director)
	add_child(_pipe_water)
	# the recorded vent lines (audio/voice, audio/fp_vent_voice.gd)
	_voice = preload("res://audio/fp_vent_voice.gd").new()
	_voice.name = "Voice"
	add_child(_voice)
	_body_events = preload("res://audio/fp_body_events.gd").new()
	_body_events.name = "BodyEvents"
	_body_events.set("director", director)
	add_child(_body_events)
	call_deferred("_wire")

func _wire() -> void:
	var chewer = main.get("chewer")
	var stomach = main.get("stomach")
	var player = main.get("player")
	director.terrain = main.get("terrain")
	_body_events.set("terrain", main.get("terrain"))
	_body_events.set("listener", player)
	if chewer is FDKChewer:
		director.connect_chewer(chewer)
		chewer.cell_torn.connect(_remember_torn)
		director.creak_source = _regrowing_spot
	if stomach is FDKStomach:
		director.connect_stomach(stomach)
		stomach.vomited.connect(_on_vomited)
	if player != null:
		director.connect_player(player)
	var restroom = main.get("restroom")
	if restroom != null and restroom.has_method("is_door_open"):
		_door_open = restroom.is_door_open()
	_in_room = _player_in_room()
	director.set_surface("tile" if _in_room else "flesh")
	director.set_bed("restroom" if _in_room else director.body_bed_for_shell(), 0.0)
	var toilet = main.get("toilet")
	if toilet != null and toilet.has_signal("lever_pulled"):
		toilet.connect("lever_pulled", func(_teeth, _hairs): director.play("toilet_flush", _toilet_pos()))
	# stage-5 events that already exist as signals on main or its children
	if main.has_signal("died"):
		main.connect("died", func(_cause): play_event("death"))
	if main.has_signal("ending_reached"):
		main.connect("ending_reached", func(): play_event("ending"))
	var mirror = main.get("mirror")
	if mirror != null and mirror.has_signal("mutated"):
		mirror.connect("mutated", func(_id): play_event("mirror_mutate"))
	var field = main.get("barrier_field")
	if field != null and field.has_signal("barrier_broke"):
		field.connect("barrier_broke", func(_b, pos): play_event("barrier_break", pos))
	var vent = main.get("vent")
	_voice.call("listen", vent)
	if vent != null and vent.get("is_open") != null:
		_vent_open = bool(vent.get("is_open"))
	# the seven events that got their own signals in main (5th pass hookup)
	var ma = main.get("mutation_apply")
	if ma != null and ma.has_signal("tumor_eaten"):
		ma.connect("tumor_eaten", on_tumor_eaten)
	# canary: chirps as the way back narrows, cries at something wrong
	_hook("canary_chirp", func(u): _on_canary_chirp(float(u)))
	_hook("canary_cry", func(frightened): play_event("canary_wrong" if frightened else "canary_warn"))
	# the opening: water still running in the bowl
	_hook("opening_flush", func(): director.play("toilet_flush", _toilet_pos()))
	# a contractile wall about to squeeze creaks first, where it is
	var tf = main.get("terrain")
	if tf != null and tf.has_signal("contraction_warning"):
		tf.connect("contraction_warning", func(pos): director.play("regen_creak", pos))
	# teeth rattling down into the tank
	if toilet != null and toilet.has_signal("tank_rattle_started"):
		toilet.connect("tank_rattle_started", _on_rattle_started)
	if toilet != null and toilet.has_signal("tank_rattle_finished"):
		toilet.connect("tank_rattle_finished", _on_rattle_finished)
	# T1: every echolocation pulse starts with the tongue click
	if ma != null and ma.has_signal("echo_click"):
		ma.connect("echo_click", func(): play_event("echo_click"))
	# (echo_pulsed, the pulse's sorted result, has no sound of its own in the
	# spec: 05 T1 / 08 1 only show it, so it stays unheard)
	# M22: the left hand tears on its own; it sounds like any other tear
	if ma != null and ma.has_signal("alien_hand_tore"):
		ma.connect("alien_hand_tore", _on_alien_tore)
	if ma != null and ma.has_signal("hair_shiver_started"):
		ma.connect("hair_shiver_started", func(): play_event("hair_shiver"))
	if ma != null and ma.has_signal("gulped"):
		ma.connect("gulped", func(): play_event("gulp"))
	if vent != null and vent.has_signal("spilled"):
		vent.connect("spilled", _on_vent_spilled)
	if mirror != null and mirror.has_signal("denied"):
		mirror.connect("denied", func(_part): play_event("mirror_denied"))
	_hook("spray_used", func(pos): on_spray(pos))
	_hook("blender_drunk", on_blender_drink)
	_hook("scissors_snipped", on_scissors)
	_hook("saw_stroked", on_saw_stroke)
	_hook("settle_ticked", func(_teeth): on_settle_tick())
	_hook("ui_clicked", on_ui_click)
	# look-down belt swap: the steel ring clinks (reuses the coin clink)
	_hook("belt_swapped", func(_from, _to): play_event("coin_drop"))
	_hook("belt_refused", func(): play_event("ui_click"))
	# bare fingers slip off muscle or membrane: rubber stretches and springs back
	_hook("grab_refused", func(_tissue, pos): play_event("grab_refuse", pos))
	# V out in the flesh before the first settlement: retching, nothing comes up
	_hook("dry_heaved", func(): play_event("gag"))
	# teeth shut in the tank knock its lid before the first trade: a clink
	# and a second one just after, the settlement's tooth clink at the tank
	_hook("tank_teeth_knocked", func():
		play_event("tank_rattle", _toilet_pos())
		_rattle_left = maxf(_rattle_left, 0.3)
		_rattle_next = 0.12)
	for id in LAYER_IDS:
		_start_layer(id)

func _start_layer(id: String) -> void:
	if _layers.has(id) or director.bank == null or not director.bank.has(id):
		return
	var p := AudioStreamPlayer.new()
	p.name = "Layer_" + id
	p.bus = director.bus
	p.stream = director.bank.stream(id, 0)
	p.volume_db = FDKAudioDirector.SILENT_DB
	add_child(p)
	p.play()
	_layers[id] = p
	_layer_level[id] = 0.0

## The level each steady layer wants now (0..1), read from the game.
func _layer_target(id: String) -> float:
	var ended := _ending_active()
	match id:
		"magnet_hum":
			var ma = main.get("mutation_apply")
			return 0.0 if ended or ma == null or not ma.has_method("magnet_hum_level") else float(ma.magnet_hum_level())
		"song_melody":
			if ended:
				return 0.0
			# the tine fills the flesh music's rests and gives way to its songs
			return float(main.melody_level()) * MELODY_IN_FLESH * (1.0 - flesh_music_level()) if main.has_method("melody_level") else 0.0
		"song_hum":
			return 1.0 if ended else 0.0
		"song_voice2":
			return 1.0 if ended and int(main.get("ending").get("voice_layers")) >= 2 else 0.0
	return 0.0

## 0..1, how far the flesh's song is up (0 in its rests and outside the flesh).
func flesh_music_level() -> float:
	return float(_flesh_music.call("level")) if _flesh_music != null else 0.0

## The ending (main.ending, FPEnding) is playing.
func _ending_active() -> bool:
	var ending = main.get("ending")
	return ending != null and bool(ending.get("active"))

func _step_layers(delta: float) -> void:
	for id in _layers.keys():
		var lv: float = move_toward(float(_layer_level[id]), _layer_target(id), LAYER_GLIDE * delta)
		_layer_level[id] = lv
		(_layers[id] as AudioStreamPlayer).volume_db = FDKAudioDirector.SILENT_DB if lv <= 0.0001 else maxf(linear_to_db(lv), FDKAudioDirector.SILENT_DB)

## Current 0..1 level of a steady layer (tests read it), -1 when absent.
func layer_level(id: String) -> float:
	return float(_layer_level.get(id, -1.0))

func _remember_torn(pos: Vector3) -> void:
	_torn.append(pos)
	if _torn.size() > TORN_KEEP:
		_torn.pop_front()

## A torn spot near the listener whose flesh is coming back, or null.
func _regrowing_spot() -> Variant:
	var t = main.get("terrain")
	var player = main.get("player")
	if t == null or player == null:
		return null
	var p: Vector3 = (player as Node3D).global_position
	for i in range(_torn.size() - 1, -1, -1):
		var at: Vector3 = _torn[i]
		if at.distance_to(p) > CREAK_RANGE:
			continue
		var d: float = t.density_at(at)
		if d > 0.15 and d < 0.95:
			return at
	return null

func _on_canary_chirp(urgency: float) -> void:
	if _chirp_cool > 0.0:
		return
	_chirp_cool = 2.5
	play_event("canary_warn" if urgency > 0.6 else "canary_chirp")

## The bed for where the player stands outside the restroom: the biome's own
## (read from main.biome_life) when the manifest has it, else the shell's.
func _body_bed() -> String:
	var life = main.get("biome_life")
	if life != null and life.has_method("current_bed"):
		var b := String(life.current_bed())
		if b != "" and director.bank != null and director.bank.beds.has(b):
			return b
	return director.body_bed_for_shell()

func _ensure_room_bus() -> void:
	FPSettings.ensure_buses()
	if AudioServer.get_bus_index(ROOM_BUS) >= 0:
		return
	var i := AudioServer.bus_count
	AudioServer.add_bus(i)
	AudioServer.set_bus_name(i, ROOM_BUS)
	AudioServer.set_bus_send(i, &"SFX")
	AudioServer.add_bus_effect(i, AudioEffectReverb.new())

## The Room bus's reverb for "tile" or "flesh", and the footstep level there.
func _set_room(room: String) -> void:
	if room == _room:
		return
	_room = room
	director.step_gain_db = FLESH_STEP_DB if room == "flesh" else 0.0
	var i := AudioServer.get_bus_index(ROOM_BUS)
	if i < 0 or AudioServer.get_bus_effect_count(i) < 1:
		return
	var rv := AudioServer.get_bus_effect(i, 0) as AudioEffectReverb
	if rv == null:
		return
	var p: Dictionary = ROOMS[room]
	for k in p.keys():
		rv.set(k, p[k])

## The footstep room now: "tile" or "flesh".
func room() -> String:
	return _room

func _hook(sig: String, cb: Callable) -> void:
	if main.has_signal(sig):
		main.connect(sig, cb)

func _process(_delta: float) -> void:
	FPProfile.begin("audio_hookup")
	_process_inner(_delta)
	FPProfile.end("audio_hookup")

func _process_inner(_delta: float) -> void:
	if main == null or director == null:
		return
	var restroom = main.get("restroom")
	var player = main.get("player")
	# inside the white room or out in the flesh
	var in_room := _player_in_room()
	if in_room != _in_room:
		_in_room = in_room
		director.set_surface("tile" if in_room else "flesh")
		_set_room("tile" if in_room else "flesh")
		director.set_bed("restroom" if in_room else director.body_bed_for_shell(), 2.0)
	# depth shell
	if player != null and not in_room:
		var center: Vector3 = main.get("RESTROOM_CENTER") if main.get("RESTROOM_CENTER") != null else Vector3(0, 1, 0)
		var thick: float = main.get("SHELL_THICKNESS") if main.get("SHELL_THICKNESS") != null else 9.0
		director.set_shell(int((player as Node3D).global_position.distance_to(center) / thick))
	elif director.shell < 0:
		director.set_shell(0)
	# out in the flesh the biome's bed layers over the shell's (biomes.json "bed")
	var want := "restroom" if in_room else _body_bed()
	# out on the street (ending): no bed is named "ending", so the body's
	# drone fades out under the hum
	if _ending_active():
		want = "ending"
	if want != director.current_bed:
		director.set_bed(want, 2.0)
	_pipe_water.call("step", _delta, director.current_bed == "restroom")
	_body_events.call("step", _delta, director.current_bed)
	# mutation stage from how much of the body has changed (0..1, as the hands)
	var prog = main.get("progression")
	if prog != null and prog.has_method("mutation_amount"):
		director.set_mutation_stage(int(clampf(float(prog.mutation_amount()), 0.0, 0.999) * 3.0))
	# the body's bed steps back while a song of the flesh is up (flesh_music.json bed_duck_db)
	if _flesh_music != null:
		director.bed_gain_db = float(_flesh_music.call("data").get("bed_duck_db", 0.0)) * flesh_music_level()
	_step_layers(_delta)
	_step_rattle(_delta)
	_chirp_cool = maxf(0.0, _chirp_cool - _delta)
	_squeeze_cool = maxf(0.0, _squeeze_cool - _delta)
	if player != null and player.has_method("squeeze") and not in_room:
		var sq := float(player.squeeze())
		if sq > 0.5 and sq > _squeeze_was + 0.05 and _squeeze_cool <= 0.0:
			_squeeze_cool = SQUEEZE_COOL
			play_event("squeeze", (player as Node3D).global_position)
		_squeeze_was = sq if sq > _squeeze_was or _squeeze_cool <= 0.0 else _squeeze_was
	if restroom != null:
		if restroom.has_method("is_door_open"):
			var d: bool = restroom.is_door_open()
			if d != _door_open:
				_door_open = d
				var dp = restroom.get("door_pivot")
				director.play("door_open" if d else "door_close", dp.global_position if dp != null else null)
		var lid = main.get("tank_lid")
		if lid != null:
			var lo: bool = not lid.on_tank
			if lo and not _lid_open:
				director.play("tank_lid", _toilet_pos())
			_lid_open = lo
	var coin_t = main.get("_coin_t")
	if coin_t != null:
		var active := float(coin_t) >= 0.0
		if active and not _coin_active:
			director.play("coin_drop", _toilet_pos())
		_coin_active = active

	# vent opening (FPVent.is_open flips) and barriers placed / straining
	var vent = main.get("vent")
	if vent != null and vent.get("is_open") != null:
		var vo := bool(vent.get("is_open"))
		if vo and not _vent_open:
			play_event("vent_open", (vent as Node3D).global_position if vent is Node3D else null)
		_vent_open = vo
	var field = main.get("barrier_field")
	if field != null and field.has_method("get_barriers"):
		var bs: Array = field.get_barriers()
		if bs.size() > _barrier_count:
			play_event("barrier_deploy", _node_pos(bs[bs.size() - 1]))
		_barrier_count = bs.size()
		for b in bs:
			if b is Object and not _hooked_barriers.has(b) and b.has_signal("damage_step_changed"):
				_hooked_barriers.append(b)
				b.connect("damage_step_changed", func(_step): play_event("barrier_strain", _node_pos(b)))

## Plays a stage-5 event sound by its game name (EVENT_SOUNDS). Unknown names
## and ids missing from the manifest are skipped silently.
func play_event(event_name: String, world_pos: Variant = null) -> void:
	if director == null:
		return
	played_events.append(event_name)
	if OS.is_debug_build() and OS.get_environment("FP_AUDIO_LOG") != "":
		print("[audio] play_event ", event_name)
	director.play(String(EVENT_SOUNDS.get(event_name, event_name)), world_pos)

## Early items tumble out of the vent on an absurd overpay (FPVent.spilled).
func _on_vent_spilled(ids: Array) -> void:
	if not ids.is_empty():
		play_event("vent_spill", _node_pos(main.get("vent")))

func _on_rattle_started(duration: float, _tumor: bool) -> void:
	_rattle_left = duration + 0.5
	_rattle_next = _rng.randf_range(RATTLE_GAP.x, RATTLE_GAP.y)
	play_event("tank_rattle", _toilet_pos())

func _on_rattle_finished() -> void:
	_rattle_left = 0.0

func _step_rattle(delta: float) -> void:
	if _rattle_left <= 0.0:
		return
	_rattle_left -= delta
	_rattle_next -= delta
	if _rattle_next <= 0.0 and _rattle_left > 0.0:
		_rattle_next = _rng.randf_range(RATTLE_GAP.x, RATTLE_GAP.y)
		play_event("tank_rattle", _toilet_pos())

## Whether teeth are still clattering into the tank (tests read it).
func is_rattling() -> bool:
	return _rattle_left > 0.0

## M22 tore a cell without the chewer: the same tear (by tissue, nerve
## twitch, the swallow after) as a chewer tear, where the hand is reaching.
func _on_alien_tore(world_pos: Variant = null) -> void:
	played_events.append("alien_tear")
	var at: Variant = world_pos if world_pos is Vector3 else _look_point()
	director._on_cell_torn(at if at is Vector3 else Vector3.ZERO)

## Where the player looks within reach (the wall just behind a fresh tear).
func _look_point() -> Variant:
	if main.has_method("_look_hit"):
		var hit = main.call("_look_hit")
		if hit is Dictionary and hit.has("position"):
			return hit.position
	var player = main.get("player")
	return (player as Node3D).global_position if player is Node3D else null

func on_tumor_eaten() -> void: play_event("tumor_eat")
func on_spray(world_pos: Variant = null) -> void: play_event("spray", world_pos)
func on_blender_drink() -> void: play_event("blender_drink")
func on_scissors() -> void: play_event("scissors")
func on_saw_stroke() -> void: play_event("saw")
func on_settle_tick() -> void: play_event("settle_tick")
func on_ui_click() -> void: play_event("ui_click")

func _node_pos(n) -> Variant:
	return (n as Node3D).global_position if n is Node3D and (n as Node3D).is_inside_tree() else null

func _on_vomited(_amount: float) -> void:
	var near := false
	if main.has_method("_near_toilet"):
		near = main.call("_near_toilet")
	director.play_vomit(near)

func _toilet_pos() -> Variant:
	var restroom = main.get("restroom")
	var t = restroom.get("toilet") if restroom != null else null
	return t.global_position if t is Node3D else null

func _player_in_room() -> bool:
	var restroom = main.get("restroom")
	var player = main.get("player")
	if restroom == null or player == null:
		return true
	var local: Vector3 = (restroom as Node3D).to_local((player as Node3D).global_position)
	var half: Vector3 = restroom.get("HALF") if restroom.get("HALF") != null else Vector3(1.5, 1.3, 1.5)
	return absf(local.x) <= half.x + 0.1 and absf(local.z) <= half.z + 0.1 and local.y > -0.5 and local.y < half.y * 2.0 + 0.5
