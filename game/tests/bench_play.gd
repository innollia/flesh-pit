extends SceneTree
const FPProfile := preload("res://main/scripts/fp_profile.gd")

## Play benchmark: the same scripted play every run (restroom look-around,
## digging out of the door, walking a long dug tunnel, standing in a dug
## cave), real rendering, vsync off. Prints one JSON line per phase:
## frame ms avg / p95 / max, engine process and physics ms, CPU and GPU
## render ms, draw calls, primitives, objects. Run windowed, isolated save:
##   godot_console --path game --resolution 1280x720 --script res://tests/bench_play.gd
## Compare before/after on the same machine and resolution only.

var m: Node3D
var phase := ""
var samples: Array = []
var results := {}

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = "user://bench-play.bin"
	root.add_child(m)
	_run.call_deferred()

func _begin(name: String) -> void:
	phase = name
	samples = []
	FPProfile.take()
	# phase marks for tools/perf/godot_profile.py (script profiler capture)
	if EngineDebugger.is_active():
		EngineDebugger.send_message("bench:phase", [name, "begin"])

func _sample() -> void:
	var vp := root.get_viewport_rid()
	FPProfile.add("terrain_publish", m.terrain.last_process_us)
	FPProfile.add("player_physics", m.player.last_physics_us)
	samples.append({
		"frame": get_root().get_process_delta_time() * 1000.0,
		"process": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"cpu_render": RenderingServer.viewport_get_measured_render_time_cpu(vp),
		"gpu_render": RenderingServer.viewport_get_measured_render_time_gpu(vp),
		"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"prims": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
	})

func _end() -> void:
	if EngineDebugger.is_active():
		EngineDebugger.send_message("bench:phase", [phase, "end"])
	var out := {"phase": phase, "frames": samples.size()}
	for k in ["frame", "process", "physics", "cpu_render", "gpu_render", "draws", "prims", "objects"]:
		var v: Array = []
		for s in samples:
			v.append(float(s[k]))
		v.sort()
		var sum := 0.0
		for x in v:
			sum += x
		out[k] = {"avg": snappedf(sum / maxf(1.0, v.size()), 0.01), "p95": snappedf(v[int(v.size() * 0.95)] if v.size() > 0 else 0.0, 0.01), "max": snappedf(v.back() if v.size() > 0 else 0.0, 0.01)}
	results[phase] = out
	print("BENCH ", JSON.stringify(out))
	# where the CPU time went: ms per frame by section, biggest first
	var prof: Dictionary = FPProfile.take()
	var rows: Array = []
	for k in prof["totals"]:
		rows.append([k, float(prof["totals"][k]) / 1000.0 / maxf(1.0, samples.size())])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	var top := []
	for r in rows.slice(0, 12):
		top.append("%s %.2f" % [r[0], r[1]])
	print("BENCH_SECTIONS ", phase, " ", ", ".join(top))

func frames_for(seconds: float, each: Callable = Callable()) -> void:
	var t := 0.0
	while t < seconds:
		await process_frame
		t += get_root().get_process_delta_time()
		if each.is_valid():
			each.call(t)
		_sample()

func _run() -> void:
	FPProfile.enabled = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	for i in range(10):
		await process_frame
	m.finish_opening()
	for i in range(30):
		await process_frame
	# A: restroom, turning slowly round
	_begin("restroom")
	m.player.global_position = Vector3(0.3, 0.9, 0.2)
	await frames_for(5.0, func(t): m.player._yaw = t * 1.25)
	_end()
	# B: digging out of the door
	_begin("dig_out")
	m.restroom.set_door_open(true, true)
	m.player.global_position = Vector3(0, 0.9, FPRestroom.HALF.z - 0.3)
	m.player._yaw = PI
	for round in range(4):
		m.player._pitch = -0.45 if round % 2 == 0 else -0.05
		Input.action_press("fdk_eat")
		await frames_for(2.5)
		Input.action_release("fdk_eat")
		m.player._pitch = -0.1
		Input.action_press("fdk_move_forward")
		await frames_for(0.8)
		Input.action_release("fdk_move_forward")
	_end()
	# C: a long dug tunnel deeper in, walking it
	var base := Vector3(-8, 0, -4)
	for z in range(0, 24):
		for y in range(0, 4):
			for x in range(-1, 2):
				m.terrain.dig_at(base + Vector3(x * 0.5 + 0.25, y * 0.5 + 0.25, -z * 0.5 - 0.25), 1.0)
	m.terrain.remesh_all()
	for i in range(5):
		await physics_frame
	_begin("tunnel_walk")
	m.player.global_position = base + Vector3(0, 0.95, -0.5)
	m.player._yaw = 0.0
	m.player._pitch = -0.05
	Input.action_press("fdk_move_forward")
	await frames_for(4.0)
	Input.action_release("fdk_move_forward")
	_end()
	# D: standing in a dug cave, looking round while the flesh regrows
	# (the digging is setup, measured from the first frame after it)
	var cave := Vector3(8, 0, 6)
	for z in range(-4, 4):
		for y in range(0, 5):
			for x in range(-4, 4):
				m.terrain.dig_at(cave + Vector3(x * 0.5 + 0.25, y * 0.5 + 0.25, z * 0.5 + 0.25), 1.0)
	m.terrain.remesh_all()
	m.player.global_position = cave + Vector3(0, 0.95, 0)
	await process_frame
	_begin("cave_look")
	await frames_for(5.0, func(t):
		m.player._yaw = t * 1.0
		m.player._pitch = sin(t) * 0.4)
	_end()
	var all := {}
	for k in results:
		all[k] = results[k]["frame"]
	print("BENCH_SUMMARY ", JSON.stringify(all))
	m.queue_free()
	quit(0)
