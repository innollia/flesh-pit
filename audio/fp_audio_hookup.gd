extends Node

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
var _settling := false
var _in_room := true

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

func _process(_delta: float) -> void:
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
	# mutation stage from points (same 0..400 scale the hands use)
	var pts = main.get("mutation_points")
	if pts != null:
		director.set_mutation_stage(int(clampf(float(pts) / 400.0, 0.0, 0.999) * 3.0))
	if restroom != null:
		if restroom.has_method("is_door_open"):
			var d: bool = restroom.is_door_open()
			if d != _door_open:
				_door_open = d
				var dp = restroom.get("door_pivot")
				director.play("door_open" if d else "door_close", dp.global_position if dp != null else null)
		var lid = restroom.get("_lid_target")
		if lid != null:
			var lo := float(lid) != 0.0
			if lo and not _lid_open:
				director.play("tank_lid", _toilet_pos())
			_lid_open = lo
	var coin_t = main.get("_coin_t")
	if coin_t != null:
		var active := float(coin_t) >= 0.0
		if active and not _coin_active:
			director.play("coin_drop", _toilet_pos())
		_coin_active = active
	if main.has_method("is_settling"):
		var s: bool = main.is_settling()
		if _settling and not s:
			director.play("toilet_flush", _toilet_pos())
		_settling = s

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
