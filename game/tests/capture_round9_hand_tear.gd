extends SceneTree

## A bare-hand tear in the real game, as the engine mixes it, for listening
## (round9-hand-tear). Holds LMB on the doorway flesh with empty hands through
## the normal input path for 7 s (a slow sweep keeps new flesh in reach), then
## lets go. Prints every chewer signal and every id the director plays with
## its frame, so the clip can be read as a list too. Movie writer audio,
## isolated save and key file:
##   godot_console --path game --resolution 480x270 --write-movie <dir>/r9.avi --fixed-fps 30 --script res://tests/capture_round9_hand_tear.gd

const SAVE := "user://capture-round9.bin"
var m: Node3D
var _frame := 0
var _seen := 0

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = SAVE
	m.user_keybinds_path = "user://keybinds_test_round9.json"
	m.rest_seed = 1337
	root.add_child(m)
	_run.call_deferred()

func _log_plays(d: FDKAudioDirector) -> void:
	var total: int = d.played_log.size()
	# played_log keeps the last 128; count from what is new this frame
	var fresh := total - _seen
	if fresh > 0:
		for i in range(total - fresh, total):
			print("PLAY %d %s" % [_frame, d.played_log[i]])
	_seen = total

func _wait(seconds: float, d: FDKAudioDirector = null) -> void:
	var t := 0.0
	while t < seconds:
		await process_frame
		_frame += 1
		t += 1.0 / 30.0
		if d != null:
			_log_plays(d)

func _mouse(held: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = held
	Input.parse_input_event(ev)

func _run() -> void:
	await _wait(0.2)
	m.finish_opening()
	var hk: Node = m.get_node("AudioHookup")
	var d: FDKAudioDirector = hk.get("director")
	hk.get_node("BodyEvents").set_process(false)
	m.restroom.set_door_open(true, true)
	m.player.global_position = Vector3(0.0, 0.95, 0.2)
	m.player.mouse_look_enabled = false
	m.player._yaw = PI
	m.player._pitch = 0.0
	m.player.rotation.y = PI
	m.player.camera_pivot.rotation.x = 0.0
	print("HANDS ", m.progression.equipped())
	m.chewer.grab_started.connect(func(_c): print("SIG %d grab_started" % _frame))
	m.chewer.cell_torn.connect(func(_p): print("SIG %d cell_torn tissue=%d" % [_frame, m.terrain.tissue_at(_p)]))
	m.chewer.released.connect(func(): print("SIG %d released" % _frame))
	m.grab_refused.connect(func(t, _p): print("SIG %d grab_refused tissue=%d" % [_frame, t]))
	await _wait(2.0)
	_seen = d.played_log.size()
	print("SEG hold %d" % _frame)
	_mouse(true)
	var t := 0.0
	while t < 7.0:
		m.player._yaw = PI + 0.35 * sin(t * 0.55)
		m.player._pitch = -0.05 + 0.2 * sin(t * 0.37)
		await _wait(1.0 / 30.0, d)
		t += 1.0 / 30.0
	_mouse(false)
	print("SEG release %d" % _frame)
	await _wait(1.5, d)
	print("SEG end %d" % _frame)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit()
