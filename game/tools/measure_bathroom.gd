extends SceneTree

var m: Node3D

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(m)
	_run.call_deferred()

func sample(label: String) -> void:
	for i in range(60):
		await process_frame
	var start := Time.get_ticks_usec()
	var last := start
	var frames: Array[float] = []
	for i in range(120):
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
	frames.sort()
	var elapsed := (Time.get_ticks_usec() - start) / 1000000.0
	print("%s: %.1f FPS, %.2f ms/frame" % [label, 120.0 / elapsed, elapsed * 1000.0 / 120.0])
	print("  p95 %.2f ms; max %.2f ms" % [frames[113], frames[119]])

func _run() -> void:
	for i in range(5):
		await process_frame
	m.finish_opening()
	m.save_path = "user://bathroom_benchmark.bin"
	m.player.set_physics_process(false)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	m.player.global_position = Vector3(0, 0.95, 0)
	m.player.rotation.y = PI
	m.player.camera_pivot.rotation.x = 0
	await sample("bathroom / mirror offscreen")
	m.player.global_position = Vector3(-FPRestroom.HALF.x + 0.85, 0.95, FPRestroom.SINK_Z)
	m.player.rotation.y = PI * 0.5
	m.player.camera_pivot.rotation.x = -0.1
	await sample("bathroom / mirror visible")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.save_path))
	m.queue_free()
	quit()
