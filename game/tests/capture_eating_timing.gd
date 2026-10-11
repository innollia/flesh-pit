extends SceneTree

# Read-only observations after normal Main/hand/terrain processing. Initial
# scene pose and door state are fixture setup; no animation/world ticks are
# called manually. PNG writes happen after the observed interval.
var m: Node3D
var destination: String
var events: Array = []
var samples: Array = []
var images: Array = []
var started_usec := 0
var last_tear_usec := -1000000
var tears := 0
var last_tear_position := Vector3.INF
var passed := 0
var failed := 0
var scenario := "continuous"

func _init() -> void:
	if "--validate-only" in OS.get_cmdline_user_args():
		print("Timing observer parsed; gameplay was not run")
		quit.call_deferred(0)
		return
	root.size = Vector2i(1152, 648)
	destination = OS.get_environment("FP_EATING_TIMING_OUT")
	var requested := OS.get_environment("FP_EATING_TIMING_SCENARIO")
	if not requested.is_empty():
		scenario = requested
	if scenario not in ["continuous", "early-release", "after-tear", "look-away", "regrab"]:
		push_error("Unknown timing scenario")
		quit.call_deferred(2)
		return
	if destination.is_empty() or not OS.get_user_data_dir().contains("flesh-pit-eating-timing-"):
		push_error("Timing observation requires explicit output and isolated userdata")
		quit.call_deferred(2)
		return
	DirAccess.make_dir_recursive_absolute(destination)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func time_s() -> float:
	return float(Time.get_ticks_usec() - started_usec) / 1000000.0

func event(kind: String, extra: Dictionary = {}) -> void:
	var row := {"kind": kind, "seconds": time_s(), "frame": Engine.get_process_frames()}
	row.merge(extra)
	events.append(row)

func tear(position: Vector3) -> void:
	tears += 1
	last_tear_position = position
	last_tear_usec = Time.get_ticks_usec()
	event("actual_tear", {"position": str(position), "density_after": m.terrain.density_at(position), "hand_state": m.hands_rig.state})

func mouse(held: bool) -> void:
	var input := InputEventMouseButton.new()
	input.button_index = MOUSE_BUTTON_LEFT
	input.pressed = held
	Input.parse_input_event(input)
	event("LMB_down" if held else "LMB_up")

func sample() -> void:
	var poses: Array = []
	for hand in m.hands_rig._hands:
		poses.append({"root": str(hand.root.position), "finger1": hand.pose.f1, "wrist_pitch": hand.pose.wrist_pitch})
	var batch = m.terrain.get("_mesh_batch")
	var surface_epoch = null
	if last_tear_position != Vector3.INF:
		var coords: Array = m.terrain.world_to_cell(last_tear_position)
		surface_epoch = m.terrain._chunks[coords[0]].get("_surface_edit_epoch")
	samples.append({"seconds": time_s(), "frame": Engine.get_process_frames(), "hand_state": m.hands_rig.state, "hand_state_s": m.hands_rig._state_time, "chew_ratio": m._chew_ratio, "elapsed": m.chewer._elapsed, "chewing": m.chewer.is_chewing(), "tears": tears, "fill": m.stomach.fill, "camera": str(m.player.camera.global_position), "poses": poses, "dig_epoch": m.terrain.get_dig_epoch() if m.terrain.has_method("get_dig_epoch") else -1, "snapshot_epoch": m.terrain.get_mesh_snapshot_epoch() if m.terrain.has_method("get_mesh_snapshot_epoch") else -1, "batch_cursor": m.terrain.get("_mesh_batch_cursor"), "batch_count": batch.size() if batch != null else 0, "patch": m.terrain.get("_surface_patch") != null, "surface_epoch": surface_epoch})

func run() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.rest_seed = 1337
	m.save_path = destination.path_join("isolated.bin")
	root.add_child(m)
	await process_frame
	m.finish_opening()
	# Unmodified procedural doorway flesh, not an authored density substitute.
	m.restroom.set_door_open(true, true)
	m.player.global_position = Vector3(0.0, 0.95, 0.2)
	m.player.mouse_look_enabled = scenario == "look-away"
	m.player._yaw = PI
	m.player._pitch = 0.0
	m.player.rotation.y = PI
	m.player.camera_pivot.rotation.x = 0.0
	for i in range(60):
		await process_frame
	await RenderingServer.frame_post_draw
	var hit: Dictionary = m._look_hit()
	check(not hit.is_empty() and hit.collider.has_meta("fdk_terrain_chunk"), "normal doorway has reachable flesh")
	if failed > 0:
		finish()
		return
	m.chewer.grab_started.connect(func(cell): event("grab", {"cell": str(cell)}))
	m.chewer.released.connect(func(): event("released"))
	m.chewer.cell_torn.connect(tear)
	started_usec = Time.get_ticks_usec()
	# Observation-only capture, identical readback policy on both versions.
	images.append({"seconds": time_s(), "frame": Engine.get_process_frames(), "image": root.get_texture().get_image()})
	mouse(true)
	var deadline := started_usec + 5000000
	var interrupted := false
	var resumed := false
	while Time.get_ticks_usec() < deadline:
		await RenderingServer.frame_post_draw
		sample()
		if m._chew_ratio >= 0.75 or Time.get_ticks_usec() - last_tear_usec < 450000:
			var read_start := Time.get_ticks_usec()
			images.append({"seconds": time_s(), "frame": Engine.get_process_frames(), "image": root.get_texture().get_image(), "readback_usec": Time.get_ticks_usec() - read_start})
		if not interrupted:
			if scenario in ["early-release", "regrab"] and time_s() >= 0.25:
				mouse(false)
				interrupted = true
			elif scenario == "after-tear" and tears == 1:
				mouse(false)
				interrupted = true
			elif scenario == "look-away" and time_s() >= 0.25:
				var motion := InputEventMouseMotion.new()
				motion.relative = Vector2(650, 0)
				Input.parse_input_event(motion)
				event("look_away_input")
				interrupted = true
		if scenario == "regrab" and interrupted and not resumed and time_s() >= 0.8:
			check(tears == 0 and not m.chewer.is_chewing(), "release before regrab cancelled without removal")
			mouse(true)
			resumed = true
		if scenario == "regrab" and tears == 1:
			break
		if interrupted and scenario != "regrab" and time_s() > 1.2:
			break
		if tears >= 3 and Time.get_ticks_usec() - last_tear_usec > 450000:
			break
	mouse(false)
	var release_deadline := Time.get_ticks_usec() + 550000
	while Time.get_ticks_usec() < release_deadline:
		await RenderingServer.frame_post_draw
		sample()
	if scenario in ["early-release", "look-away"]:
		check(tears == 0, "interrupted normal input did not remove flesh")
	elif scenario in ["after-tear", "regrab"]:
		check(tears == 1, "release immediately after tear did not duplicate removal")
	else:
		check(tears >= 3, "continuous normal LMB removed three cells")
	check(not m.chewer.is_chewing(), "actual release stopped chewing")
	check(m.deaths == 0, "death did not reset observations")
	check(is_equal_approx(m.stomach.fill, float(tears) * m.stomach_config.flesh_per_cell), "actual food matches tears")
	finish()

func finish() -> void:
	for index in range(images.size()):
		var row: Dictionary = images[index]
		var image: Image = row.image
		row.erase("image")
		row["file"] = "frame_%04d.png" % index
		image.save_png(destination.path_join(row.file))
	var file := FileAccess.open(destination.path_join("timeline.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"scenario": scenario, "events": events, "samples": samples, "images": images, "passed": passed, "failed": failed, "engine": Engine.get_version_info(), "userdata": OS.get_user_data_dir(), "resolution": str(root.size), "fixture": "unaltered procedural doorway, seed 1337, initial pose (0,.95,.2), open door", "warning": "observation check success is not restored-timing approval"}, "\t"))
	file.close()
	print("%d passed, %d failed; timeline observations only" % [passed, failed])
	quit(0 if failed == 0 else 1)
