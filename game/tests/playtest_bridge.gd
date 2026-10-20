extends Node

## Clean-room playtest bridge (docs/operations.md "클린룸 플레이테스트").
## Only the isolated playtest copy adds it as an autoload
## (tools/playtest/run_session.py); the game itself never loads it. The game
## runs with --fixed-fps; between commands this node blocks the main loop, so
## no game time passes while the player agent thinks.
##
## Each step it writes, into PLAYTEST_DIR (the player agent's room):
##   obs_NNNN.png  the last rendered frame
##   obs_NNNN.json the on-screen text, the sounds heard since the last step
## and into PLAYTEST_EVIDENCE (out of the player's reach) the telemetry the
## evaluator reads: position, stomach, teeth, events, frame cost.
## It then waits for cmd_NNNN.json from tools/playtest/play.py and turns it
## into real input events (keys by name, mouse look, clicks) for the frames
## the command lasts. Real mouse and keyboard input never reaches the window:
## it is unfocusable and passes the mouse through.

const FPS := 30.0
const WARMUP_FRAMES := 90
## A player session may start hours after the game is up; it still quits
## on its own in the end so a forgotten window does not stay forever.
const IDLE_QUIT_MS := 8 * 60 * 60 * 1000
const MAX_SECS := 10.0

var dir := ""
var evidence := ""
var step := 0
var _main: Node
var _plan: Array = [] # one Array of InputEvents per frame
var _frame := 0
var _settle := WARMUP_FRAMES
var _mouse := Vector2.ZERO
var _heard: Array = []
var _log_prev: Array = []
var _events: Array = []
var _game_time := 0.0
var _step_wall_ms := 0
var _step_frames := 0
var _mid_at := -1

func _ready() -> void:
	dir = OS.get_environment("PLAYTEST_DIR")
	evidence = OS.get_environment("PLAYTEST_EVIDENCE")
	if dir == "" or evidence == "":
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000
	var win := get_window()
	win.unfocusable = true
	win.mouse_passthrough = true
	_mouse = Vector2(win.size) * 0.5
	AudioServer.set_bus_mute(0, true)
	RenderingServer.frame_pre_draw.connect(_keep_cursor_free)
	print("PLAYTEST bridge user dir ", OS.get_user_data_dir())

## The game captures the mouse in play; the playtest window must never take
## the real cursor. Mouse look still works: it reads motion events.
func _keep_cursor_free() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	if dir == "":
		return
	if _main == null and get_tree().current_scene != null:
		_main = get_tree().current_scene
		_hook_main()
	_game_time += delta
	_step_frames += 1
	_listen()
	if _frame < _plan.size():
		for ev in _plan[_frame]:
			Input.parse_input_event(ev)
		if _frame == _mid_at:
			_save_shot("obs_%04d_mid.png" % step)
		_frame += 1
		return
	if _settle > 0:
		_settle -= 1
		return
	_observe()
	_wait_for_command()

# --- observation ---------------------------------------------------------------

func _save_shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(dir.path_join(name))

func _observe() -> void:
	var shot := "obs_%04d.png" % step
	_save_shot(shot)
	var sounds := _new_sounds()
	var obs := {"step": step, "time": snappedf(_game_time, 0.1), "screenshot": shot,
		"text": _visible_text(), "sounds": sounds}
	if _mid_at >= 0:
		obs["mid_screenshot"] = "obs_%04d_mid.png" % step
	_write_json(dir.path_join("obs_%04d.json" % step), obs)
	var tel := _telemetry()
	tel["sounds"] = sounds
	tel["wall_ms_per_frame"] = snappedf(float(Time.get_ticks_msec() - _step_wall_ms) / maxf(1.0, float(_step_frames)), 0.1)
	_write_json(evidence.path_join("tel_%04d.json" % step), tel)
	_events.clear()

func _write_json(path: String, data: Dictionary) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, " "))
	f.close()
	DirAccess.rename_absolute(tmp, path)

## Text a player could read: every visible, opaque enough Label, Button,
## RichTextLabel or LineEdit on screen (text drawn by hand only shows in the
## screenshot).
func _visible_text() -> Array:
	var out: Array = []
	var seen := {}
	var view := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	for n in get_tree().root.find_children("*", "Control", true, false):
		var c := n as Control
		if c == null or not c.is_visible_in_tree() or not _layer_visible(c):
			continue
		var t := ""
		if c is Label:
			t = (c as Label).text
		elif c is Button:
			t = (c as Button).text
		elif c is RichTextLabel:
			t = (c as RichTextLabel).get_parsed_text()
		elif c is LineEdit:
			t = (c as LineEdit).text
		t = t.strip_edges()
		if t == "" or _alpha(c) < 0.1:
			continue
		var at = null
		if c.get_viewport() == get_viewport():
			# menus are scaled Controls on canvas layers: screen rect via the canvas transform
			var r := c.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, c.size)
			if not view.intersects(r):
				continue
			at = [int(r.get_center().x), int(r.get_center().y)]
		# else: drawn onto a 3D surface through a SubViewport (the title wall);
		# where it is shows only in the screenshot
		var key := "%s@%s" % [t, str(at)]
		if seen.has(key):
			continue
		seen[key] = true
		out.append({"text": t, "at": at})
	return out

func _alpha(c: CanvasItem) -> float:
	var a := 1.0
	var n: Node = c
	while n != null:
		if n is CanvasItem:
			a *= (n as CanvasItem).modulate.a
			if n == c:
				a *= (n as CanvasItem).self_modulate.a
		n = n.get_parent()
	return a

func _layer_visible(c: Control) -> bool:
	var n: Node = c.get_parent()
	while n != null:
		if n is CanvasLayer and not (n as CanvasLayer).visible:
			return false
		n = n.get_parent()
	return true

func _new_sounds() -> Array:
	var out := _heard.duplicate()
	_heard.clear()
	return out

## Every one-shot the audio director starts (tears, swallows, doors, the
## vent, refusals), not only the game's named events. The director keeps a
## capped log, so new entries are found by matching the old tail each frame.
func _listen() -> void:
	if _main == null:
		return
	var director := _main.get_node_or_null("AudioHookup/AudioDirector")
	if director == null:
		return
	var log: Array = director.get("played_log")
	var n := _log_prev.size()
	for k in range(0, mini(n, 16) + 1):
		if log.size() >= n - k and log.slice(0, n - k) == _log_prev.slice(k):
			_heard.append_array(log.slice(n - k))
			break
	_log_prev = log.duplicate()

# --- telemetry (evaluator only) ---------------------------------------------------

func _hook_main() -> void:
	for sig in ["died", "ending_reached", "flushed", "opening_flush", "spray_used", "blender_drunk",
			"settle_ticked", "belt_swapped", "belt_refused", "canary_cry"]:
		if _main.has_signal(sig):
			_main.connect(sig, _on_event.bind(sig))
	var vent = _main.get("vent")
	if vent != null and vent.has_signal("line_spoken"):
		vent.connect("line_spoken", func(id): _events.append({"event": "vent_line", "args": [id], "t": snappedf(_game_time, 0.1)}))

## bind() puts the signal name after the signal's own arguments.
func _on_event(...args: Array) -> void:
	var sig := String(args.pop_back())
	_events.append({"event": sig, "args": args.map(func(a): return str(a)), "t": snappedf(_game_time, 0.1)})

func _telemetry() -> Dictionary:
	var d := {"step": step, "game_time": snappedf(_game_time, 0.1), "events": _events.duplicate()}
	var m := _main
	if m == null:
		return d
	d["opening"] = m.call("is_opening") if m.has_method("is_opening") else null
	d["ended"] = m.get("ended")
	d["paused"] = get_tree().paused
	var title = m.get("title_screen")
	d["title_open"] = title != null and is_instance_valid(title) and bool(title.get("visible"))
	var pause = m.get("pause_menu")
	d["pause_open"] = pause != null and pause.has_method("is_open") and pause.call("is_open")
	var player = m.get("player")
	if player != null:
		var p: Vector3 = player.global_position
		d["pos"] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]
		var center = m.get("RESTROOM_CENTER")
		if center is Vector3:
			var depth: float = p.distance_to(center)
			d["depth"] = snappedf(depth, 0.01)
			d["shell"] = FPWorldFeatures.shell_of_depth(depth)
		d["yaw_deg"] = snappedf(rad_to_deg(float(player.get("_yaw"))), 0.1)
		d["pitch_deg"] = snappedf(rad_to_deg(float(player.get("_pitch"))), 0.1)
		d["crouching"] = player.get("_is_crouching")
	var restroom = m.get("restroom")
	if restroom != null and player != null and restroom.has_method("contains"):
		d["in_restroom"] = restroom.call("contains", player.global_position)
	var stomach = m.get("stomach")
	if stomach != null:
		d["stomach_fill"] = snappedf(float(stomach.get("fill")), 0.1)
	var prog = m.get("progression")
	if prog != null:
		d["teeth"] = prog.get("teeth")
		d["teeth_in_hand"] = prog.get("teeth_in_hand")
		d["barriers"] = prog.get("barriers")
		var sprays = prog.get("sprays")
		if sprays != null and sprays.has_method("count"):
			d["spray_cans"] = sprays.call("count")
		if prog.has_method("all_mutations"):
			d["mutations"] = prog.call("all_mutations")
		d["has_belt"] = prog.get("has_belt")
	d["deaths"] = m.get("deaths")
	d["carry_mode"] = m.get("carry_mode")
	d["has_canary"] = m.get("has_canary")
	if m.has_method("interact_target"):
		d["interact_target"] = m.call("interact_target")
	var vent = m.get("vent")
	if vent != null:
		d["vent_open"] = vent.get("is_open")
		d["vent_offers"] = vent.get("offers")
	d["looted_rest_cans"] = m.get("looted_rest_cans")
	d["crush_t"] = m.get("_crush_t")
	var tools = m.get("tissue_tools")
	if tools != null:
		d["grip_refusals"] = tools.get("membrane_refusals")
	if player != null and m.has_method("_look_hit"):
		var hit: Dictionary = m.call("_look_hit")
		if not hit.is_empty() and m.get("terrain") != null:
			var dir: Vector3 = player.call("get_look_ray")[1]
			var at: Vector3 = hit["position"] + dir * 0.2
			d["aim_dist"] = snappedf(player.camera.global_position.distance_to(hit["position"]), 0.01)
			d["aim_tissue"] = m.terrain.tissue_at(at)
			d["aim_depth"] = snappedf(at.distance_to(m.get("RESTROOM_CENTER")), 0.01)
	return d

# --- commands -----------------------------------------------------------------------

func _wait_for_command() -> void:
	var path := dir.path_join("cmd_%04d.json" % (step + 1))
	var waited := 0
	while not FileAccess.file_exists(path):
		OS.delay_msec(25)
		waited += 25
		if waited > IDLE_QUIT_MS:
			_close("no command for %d hours" % (IDLE_QUIT_MS / 3600000))
			return
	var cmd = JSON.parse_string(FileAccess.get_file_as_string(path))
	step += 1
	DirAccess.copy_absolute(path, evidence.path_join("cmd_%04d.json" % step))
	_step_wall_ms = Time.get_ticks_msec()
	_step_frames = 0
	if not cmd is Dictionary:
		cmd = {"wait": 0.1}
	if bool(cmd.get("quit", false)):
		_close("the test was stopped")
		return
	_plan_command(cmd)

## {"keys": ["W", "Shift"], "mouse": ["LMB"], "secs": 1.5, "look": [right_deg, up_deg],
##  "tap": ["F"], "at": [x, y], "click": "LMB", "wait": 2}
## The player's client reads closed.json and says the game is closed (s3: a
## silent idle quit looked to the player like a freeze in the settings menu).
func _close(reason: String) -> void:
	_write_json(dir.path_join("closed.json"), {"step": step, "reason": reason})
	get_tree().quit()

func _plan_command(cmd: Dictionary) -> void:
	var secs := clampf(float(cmd.get("secs", cmd.get("wait", 0.4))), 0.1, MAX_SECS)
	var n := maxi(2, int(round(secs * FPS)))
	var lead := 0
	_plan = []
	for i in range(n + 3):
		_plan.append([])
	if cmd.has("at"):
		var at: Array = cmd["at"]
		var to := Vector2(float(at[0]), float(at[1])) * _view_scale()
		var mm := InputEventMouseMotion.new()
		mm.position = to
		mm.global_position = to
		mm.relative = to - _mouse
		_mouse = to
		_plan[0].append(mm)
		lead = 1
	# held keys and mouse buttons for the whole duration
	var held: Array = []
	for k in cmd.get("keys", []):
		held.append(String(k))
	for b in cmd.get("mouse", []):
		held.append(String(b))
	for name in held:
		var down := _event_for(name, true)
		var up := _event_for(name, false)
		if down != null:
			_plan[lead].append(down)
			_plan[lead + n - 1].append(up)
	# taps: down one frame, up the next
	var taps: Array = []
	for k in cmd.get("tap", []):
		taps.append(String(k))
	if cmd.has("click"):
		taps.append(String(cmd["click"]))
	for name in taps:
		var down := _event_for(name, true)
		if down != null:
			_plan[lead].append(down)
			_plan[lead + 1].append(_event_for(name, false))
	# mouse look spread over the duration
	if cmd.has("look"):
		var look: Array = cmd["look"]
		var sens := 0.0025
		var player = _main.get("player") if _main != null else null
		if player != null and player.get("config") != null:
			sens = float(player.get("config").get("mouse_sensitivity"))
		var px := Vector2(deg_to_rad(float(look[0])), -deg_to_rad(float(look[1]))) / sens
		for i in range(n):
			var mm := InputEventMouseMotion.new()
			mm.relative = px / float(n)
			mm.position = _mouse
			mm.global_position = _mouse
			_plan[lead + i].append(mm)
	_frame = 0
	_mid_at = lead + n / 2 if n >= 45 else -1
	_settle = 2

func _view_scale() -> Vector2:
	var shot := get_viewport().get_texture().get_size()
	var view := get_viewport().get_visible_rect().size
	return Vector2(view.x / maxf(1.0, shot.x), view.y / maxf(1.0, shot.y))

func _event_for(name: String, pressed: bool) -> InputEvent:
	var buttons := {"LMB": MOUSE_BUTTON_LEFT, "RMB": MOUSE_BUTTON_RIGHT, "MMB": MOUSE_BUTTON_MIDDLE,
		"WHEELUP": MOUSE_BUTTON_WHEEL_UP, "WHEELDOWN": MOUSE_BUTTON_WHEEL_DOWN}
	var up := name.to_upper()
	if buttons.has(up):
		var mb := InputEventMouseButton.new()
		mb.button_index = buttons[up]
		mb.pressed = pressed
		mb.position = _mouse
		mb.global_position = _mouse
		return mb
	var aliases := {"ESC": "Escape", "CTRL": "Ctrl", "CONTROL": "Ctrl", "SHIFT": "Shift", "ALT": "Alt",
		"SPACE": "Space", "ENTER": "Enter", "RETURN": "Enter", "TAB": "Tab", "UP": "Up", "DOWN": "Down",
		"LEFT": "Left", "RIGHT": "Right", "BACKSPACE": "Backspace"}
	var key_name: String = aliases.get(up, name)
	var code := OS.find_keycode_from_string(key_name)
	if code == KEY_NONE:
		return null
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.pressed = pressed
	return k
