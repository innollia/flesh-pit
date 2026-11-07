extends SceneTree

## Tear feel frame sequence (before -> pull -> snap -> after) through the
## normal Main input path: hold LMB on the unaltered procedural doorway flesh
## and record every rendered frame from the press until the second tear has
## settled. No animation or world tick is driven by hand. Also writes a
## contact sheet around the first tear (sheet_tear1.png) and timeline.json.
## Run windowed, isolated save:
##   FP_TEAR_OUT=<dir> godot_console --path game --resolution 960x540 --script res://tests/capture_tear_feel.gd
var m: Node3D
var destination: String
var started_usec := 0
var frames: Array = []
var tears: Array = []
var events: Array = []
var passed := 0
var failed := 0

func _init() -> void:
	destination = OS.get_environment("FP_TEAR_OUT")
	if destination.is_empty():
		destination = OS.get_user_data_dir().path_join("capture-tear")
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

func mouse(held: bool) -> void:
	var input := InputEventMouseButton.new()
	input.button_index = MOUSE_BUTTON_LEFT
	input.pressed = held
	Input.parse_input_event(input)

func on_tear(pos: Vector3) -> void:
	# Same frame as the removal: the real density must already be gone.
	tears.append({"seconds": time_s(), "frame": Engine.get_process_frames(), "position": pos, "density_after": m.terrain.density_at(pos), "image_index": frames.size()})

func run() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = "user://keybinds_test_tear_feel.json"
	m.rest_seed = 1337
	m.save_path = "user://capture-tear-feel.bin"
	root.add_child(m)
	await process_frame
	m.finish_opening()
	m.restroom.set_door_open(true, true)
	m.player.global_position = Vector3(0.0, 0.95, 0.2)
	m.player.mouse_look_enabled = false
	m.player._yaw = PI
	m.player._pitch = 0.0
	m.player.rotation.y = PI
	m.player.camera_pivot.rotation.x = 0.0
	for i in range(60):
		await process_frame
	await RenderingServer.frame_post_draw
	var hit: Dictionary = m._look_hit()
	check(not hit.is_empty() and hit.collider.has_meta("fdk_terrain_chunk"), "doorway flesh reachable")
	if failed > 0:
		finish()
		return
	m.chewer.cell_torn.connect(on_tear)
	started_usec = Time.get_ticks_usec()
	for i in range(6):
		await RenderingServer.frame_post_draw
		grab("before")
	mouse(true)
	var deadline := started_usec + 6000000
	while Time.get_ticks_usec() < deadline:
		await RenderingServer.frame_post_draw
		grab("hold")
		if tears.size() >= 2 and time_s() - float(tears[1].seconds) > 0.7:
			break
	mouse(false)
	for i in range(20):
		await RenderingServer.frame_post_draw
		grab("released")
	check(tears.size() >= 2, "two real tears happened")
	for t in tears:
		check(float(t.density_after) < m.terrain_config.iso_level, "tear removed real density at %s" % str(t.position))
	finish()

func grab(phase: String) -> void:
	var row := {"seconds": time_s(), "frame": Engine.get_process_frames(), "phase": phase, "chew_ratio": m._chew_ratio, "hand_state": m.hands_rig.state, "tears": tears.size(), "press": m.terrain.get_press_amount(), "image": root.get_texture().get_image()}
	if m.get("tear_feel") != null:
		row["feel"] = m.tear_feel.debug_state()
	frames.append(row)

func finish() -> void:
	for index in range(frames.size()):
		var row: Dictionary = frames[index]
		var image: Image = row.image
		row.erase("image")
		row["file"] = "frame_%04d.png" % index
		image.save_png(destination.path_join(row.file))
		row["image_obj"] = image
	if not tears.is_empty():
		_sheet(int(tears[0].image_index), "sheet_tear1.png")
	if tears.size() > 1:
		_sheet(int(tears[1].image_index), "sheet_tear2.png")
	for row in frames:
		row.erase("image_obj")
	var out_tears: Array = []
	for t in tears:
		var c: Dictionary = t.duplicate()
		c["position"] = str(c.position)
		out_tears.append(c)
	var file := FileAccess.open(destination.path_join("timeline.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"tears": out_tears, "frames": frames, "passed": passed, "failed": failed, "resolution": str(root.size)}, "\t"))
	file.close()
	print("%d passed, %d failed; %d frames -> %s" % [passed, failed, frames.size(), destination])
	quit(0 if failed == 0 else 1)

## 4x4 sheet: frames spread from ~0.45 s before the tear render to ~0.5 s after.
func _sheet(tear_index: int, file_name: String) -> void:
	var picks: Array = []
	var t0: float = float(frames[tear_index].seconds)
	var wanted := [-0.45, -0.3, -0.2, -0.12, -0.06, -0.02, 0.0, 0.03, 0.06, 0.1, 0.15, 0.2, 0.28, 0.36, 0.45, 0.6]
	for w in wanted:
		var best := 0
		var best_d := INF
		for i in range(frames.size()):
			var d := absf(float(frames[i].seconds) - (t0 + w))
			if w == 0.0:
				d = absf(float(i - tear_index))
			if d < best_d:
				best_d = d
				best = i
		picks.append(best)
	var cw := 480
	var ch := 270
	var sheet := Image.create(cw * 4, ch * 4, false, Image.FORMAT_RGBA8)
	for k in range(picks.size()):
		var img: Image = (frames[picks[k]].image_obj as Image).duplicate()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(cw, ch, Image.INTERPOLATE_BILINEAR)
		# marker strip: red = the tear render frame, else grey
		var col := Color(1, 0, 0) if picks[k] == tear_index else Color(0.3, 0.3, 0.3)
		img.fill_rect(Rect2i(0, 0, cw, 6), col)
		var ratio_w := int(cw * clampf(float(frames[picks[k]].chew_ratio), 0.0, 1.0))
		img.fill_rect(Rect2i(0, 6, ratio_w, 4), Color(0.2, 1, 0.2))
		sheet.blit_rect(img, Rect2i(0, 0, cw, ch), Vector2i((k % 4) * cw, (k / 4) * ch))
	sheet.save_png(destination.path_join(file_name))
