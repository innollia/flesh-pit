extends SceneTree

## Chewing sounds stop when eating stops ("음식 씹는 소리가 안 멈추는 문제").
## Real Main, real doorway flesh, real LMB: every way eating ends (release,
## Tab mirror, Esc pause, death, load) leaves no chew voice playing, and the
## squeeze strain (a loop-kind sound fired as an event) ends on its own
## instead of looping forever. Save and key files are this suite's own.

var m: Node3D
var passed := 0
var failed := 0
var folder: String
const KEYS_PATH := "user://keybinds_test_chew_stop.json"

func _init() -> void:
	Engine.max_fps = 60
	folder = ProjectSettings.globalize_path("res://../.dryforge/evidence/chew-stop")
	DirAccess.make_dir_recursive_absolute(folder)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func frames(count: int) -> void:
	for i in range(count):
		await process_frame

func mouse(held: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = held
	Input.parse_input_event(e)

func key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)

func director() -> FDKAudioDirector:
	return m.get_node("AudioHookup").director

## Players under the director still sounding a looping stream that is not a
## bed layer: the chew loop/strain while chewing, or a stray endless voice.
func loop_voices() -> Array:
	var d := director()
	var beds: Array = d._bed_players.values()
	var out := []
	for c in d.get_children():
		if not (c is AudioStreamPlayer or c is AudioStreamPlayer3D) or c in beds:
			continue
		var s: AudioStream = c.stream
		if c.playing and s is AudioStreamWAV and (s as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED:
			out.append(c)
	return out

func chew_silent(label: String) -> void:
	var d := director()
	check(not m.chewer.is_chewing(), label + ": chewer stopped")
	check(not d.is_chew_active(), label + ": director left chewing")
	check(not d._chew.playing and not d._strain.playing, label + ": chew loop and strain players stopped")
	check(loop_voices().is_empty(), label + ": no looping voice left (%s)" % str(loop_voices()))

func new_game() -> void:
	if is_instance_valid(m):
		get_root().get_tree().paused = false
		m.queue_free()
		await frames(2)
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = KEYS_PATH
	m.save_path = folder.path_join("chew_stop.bin")
	m.rest_seed = 1337
	root.add_child(m)
	await frames(3)
	m.save_path = folder.path_join("chew_stop.bin")
	m.finish_opening()
	m.restroom.set_door_open(true, true)
	m.player.mouse_look_enabled = false
	m.player.global_position = Vector3(0.0, 0.95, 0.2)
	m.player._yaw = PI
	m.player._pitch = 0.0
	m.player.rotation.y = PI
	m.player.camera_pivot.rotation.x = 0.0
	await frames(40)

## Holds LMB on the doorway flesh until the chew loop sounds.
func start_chewing(label: String) -> bool:
	mouse(true)
	for i in range(30):
		await process_frame
		if m.chewer.is_chewing() and director().is_chew_active():
			break
	var ok: bool = m.chewer.is_chewing() and director().is_chew_active() and director()._chew.playing
	check(ok, label + ": LMB on the doorway flesh starts the chew loop")
	return ok

func run() -> void:
	await new_game()
	var hit: Dictionary = m._look_hit()
	check(not hit.is_empty() and hit.collider.has_meta("fdk_terrain_chunk"), "doorway flesh is in reach")

	# 1. plain release, after real tears
	if await start_chewing("release"):
		var torn := [0]
		m.chewer.cell_torn.connect(func(_p): torn[0] += 1)
		for i in range(150):
			await process_frame
			if torn[0] >= 2:
				break
		check(torn[0] >= 1, "release: flesh actually came away while chewing")
		mouse(false)
		await frames(3)
		chew_silent("release")

	# 2. Tab mirror while the button is still held
	await new_game()
	if await start_chewing("mirror"):
		key(KEY_TAB, true)
		await frames(3)
		key(KEY_TAB, false)
		await frames(3)
		check(m._mirror_open, "mirror: Tab opened the mirror while chewing")
		chew_silent("mirror")
		mouse(false)
		await frames(2)
		m.mirror.close()
		await frames(3)
		chew_silent("mirror closed")

	# 3. Esc pause while held
	await new_game()
	if await start_chewing("pause"):
		key(KEY_ESCAPE, true)
		await frames(2)
		key(KEY_ESCAPE, false)
		await frames(2)
		check(m.get_tree().paused, "pause: Esc paused while chewing")
		chew_silent("pause")
		mouse(false)
		m.pause_menu.resume()
		await frames(3)
		chew_silent("pause resumed")

	# 4. death while held, then let go
	await new_game()
	if await start_chewing("death"):
		m.die("test")
		await frames(1)
		check(not director().is_chew_active() and not director()._chew.playing, "death: chew loop stops at death")
		mouse(false)
		await frames(3)
		chew_silent("death")

	# 5. load the suite's own save while held, then let go
	await new_game()
	check(m.save_to_disk(), "load: suite save written to its own file")
	if await start_chewing("load"):
		check(m.load_from_disk(), "load: suite save read back while chewing")
		mouse(false)
		await frames(3)
		chew_silent("load")

	# 6. squeeze strain: the loop-kind chew_strain fired as an event must end
	var d := director()
	var hook: Node = m.get_node("AudioHookup")
	var before := d.get_child_count()
	hook.play_event("squeeze", m.player.global_position)
	var made: Node = d.get_child(d.get_child_count() - 1) if d.get_child_count() > before else null
	check(made != null and made.playing, "squeeze: the strain sounds")
	var s: AudioStream = made.stream if made != null else null
	check(s is AudioStreamWAV and (s as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED, "squeeze: the strain event plays once, not as a loop")
	check(loop_voices().is_empty(), "squeeze: no looping voice from the event")
	var chew_loop := d.bank.stream("chew_strain", 0) as AudioStreamWAV
	check(chew_loop != null and chew_loop.loop_mode == AudioStreamWAV.LOOP_FORWARD, "squeeze: the chew strain layer itself still loops")
	var length := s.get_length() if s != null else 0.0
	var deadline := Time.get_ticks_msec() + int((length + 1.5) * 1000.0)
	while is_instance_valid(made) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not is_instance_valid(made) or not made.playing, "squeeze: the strain voice finishes (%.1f s)" % length)
	# the chew loop played afterward still loops
	if await start_chewing("after squeeze"):
		var cs: AudioStreamWAV = d._chew.stream
		check(cs.loop_mode == AudioStreamWAV.LOOP_FORWARD, "after squeeze: chew loop still loops while held")
		mouse(false)
		await frames(3)
		chew_silent("after squeeze")

	print("%d passed, %d failed" % [passed, failed])
	m.queue_free()
	await frames(2)
	quit(0 if failed == 0 else 1)
