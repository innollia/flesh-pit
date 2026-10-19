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
	"squeeze": "chew_strain",
}

func _ready() -> void:
	main = get_parent()
	director = FDKAudioDirector.new()
	director.name = "AudioDirector"
	director.manifest_path = MANIFEST
	add_child(director)
	call_deferred("_wire")

func _wire() -> void:
	var chewer = main.get("chewer")
	var stomach = main.get("stomach")
	var player = main.get("player")
	director.terrain = main.get("terrain")
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
		toilet.connect("tank_rattle_started", func(_d, _tumor): director.play("coin_drop", _toilet_pos()))
	# T1: every echolocation pulse starts with the tongue click
	if ma != null and ma.has_signal("echo_click"):
		ma.connect("echo_click", func(): play_event("echo_click"))
	_hook("spray_used", func(pos): on_spray(pos))
	_hook("blender_drunk", on_blender_drink)
	_hook("scissors_snipped", on_scissors)
	_hook("saw_stroked", on_saw_stroke)
	_hook("settle_ticked", func(_teeth): on_settle_tick())
	_hook("ui_clicked", on_ui_click)
	# look-down belt swap: the steel ring clinks (reuses the coin clink)
	_hook("belt_swapped", func(_from, _to): play_event("coin_drop"))
	_hook("belt_refused", func(): play_event("ui_click"))

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
		director.set_bed("restroom" if in_room else director.body_bed_for_shell(), 2.0)
	# depth shell
	if player != null and not in_room:
		var center: Vector3 = main.get("RESTROOM_CENTER") if main.get("RESTROOM_CENTER") != null else Vector3(0, 1, 0)
		var thick: float = main.get("SHELL_THICKNESS") if main.get("SHELL_THICKNESS") != null else 9.0
		director.set_shell(int((player as Node3D).global_position.distance_to(center) / thick))
	elif director.shell < 0:
		director.set_shell(0)
	# mutation stage from how much of the body has changed (0..1, as the hands)
	var prog = main.get("progression")
	if prog != null and prog.has_method("mutation_amount"):
		director.set_mutation_stage(int(clampf(float(prog.mutation_amount()), 0.0, 0.999) * 3.0))
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
