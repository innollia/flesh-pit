extends SceneTree

## Tear benchmark: hold LMB on the unaltered doorway flesh through the normal
## input path for a fixed time, real rendering, and report frame ms
## (avg / p95 / max) and the number of real tears. Run windowed, isolated
## save, same machine and resolution before/after:
##   godot_console --path game --resolution 1280x720 --script res://tests/bench_tear.gd
var m: Node3D
var tears := 0

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.rest_seed = 1337
	m.save_path = "user://bench-tear.bin"
	root.add_child(m)
	_run.call_deferred()

func _run() -> void:
	await process_frame
	m.finish_opening()
	m.restroom.set_door_open(true, true)
	m.player.global_position = Vector3(0.0, 0.95, 0.2)
	m.player.mouse_look_enabled = false
	m.player._yaw = PI
	m.player._pitch = 0.0
	m.player.rotation.y = PI
	m.player.camera_pivot.rotation.x = 0.0
	for i in range(120):
		await process_frame
	m.chewer.cell_torn.connect(func(_p): tears += 1)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	Input.parse_input_event(press)
	var samples: Array = []
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < 8000000:
		await process_frame
		samples.append(get_root().get_process_delta_time() * 1000.0)
		# a slow fixed sweep over the doorway so new flesh keeps coming in reach
		var t := float(Time.get_ticks_usec() - start) / 1000000.0
		m.player._yaw = PI + 0.45 * sin(t * 0.55)
		m.player._pitch = -0.1 + 0.3 * sin(t * 0.37)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	Input.parse_input_event(release)
	samples.remove_at(0)
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for s in samples:
		total += s
	print(JSON.stringify({"phase": "tear_hold", "frames": samples.size(), "avg_ms": total / samples.size(), "p95_ms": sorted[int(sorted.size() * 0.95)], "max_ms": sorted[-1], "tears": tears}))
	quit(0)
