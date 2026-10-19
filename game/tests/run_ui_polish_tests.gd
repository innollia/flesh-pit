extends SceneTree

## UI and effect polish (2026-10-19: "Esc screen and stomach UI are not
## pretty and not this game"): the Esc screen shuts the eyes and opens them
## over the running game; the stomach gauge and its mouth sit together
## bottom left; textured blobs really carry UVs; bits fly out of a tear and
## go away; the opening's vomit key goes once used; death wakes with lids.

var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.save_path = "user://ui-polish-test.bin"
	root.add_child(m)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func run() -> void:
	await frames(5)
	m.finish_opening()
	# --- Esc: eyes shut, then open over the running game
	var pm: FPPauseMenu = m.pause_menu
	m._esc_guard_frame = -10
	m.open_pause_menu()
	check(pm.is_open() and paused, "Esc shuts the eyes and holds the world")
	await frames(40)
	check(pm.shut > 0.99, "the lids close (%.2f)" % pm.shut)
	check(pm.column.modulate.a > 0.99, "the items show on the shut lids")
	check((pm.buttons[0] as Button).text == "눈 뜨기", "the first item opens the eyes")
	check(pm.root.get_viewport().gui_get_focus_owner() == pm.buttons[0], "and has focus")
	pm.resume()
	check(not pm.is_open() and not paused, "눈 뜨기 lets the world run at once")
	check(pm.visible and pm.root.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the lids open over the game, passing input")
	check(pm.root.get_viewport().gui_get_focus_owner() == null, "no menu item keeps focus while the eyes open")
	await frames(40)
	check(not pm.visible and pm.shut <= 0.0, "fully open, the layer is gone")
	# --- stomach gauge and the mouth at its end
	var hud: FPStomachHUD = m.stomach_hud
	m.stomach.fill = m.stomach.config.capacity + m.stomach.config.overfill_capacity * 0.8
	await frames(30)
	check(m.vomit_button.shown and m.vomit_button.visible, "past the threshold the mouth shows")
	var gut_rect: Rect2 = hud.gut.get_global_rect()
	var mouth_rect: Rect2 = m.vomit_button.get_global_rect()
	check(absf(mouth_rect.position.x - gut_rect.end.x) < 12.0 * FPStomachHUD.ui_scale(hud.size.y), "the mouth sits at the gauge's end")
	check(absf(mouth_rect.get_center().y - gut_rect.get_center().y) < 8.0 * FPStomachHUD.ui_scale(hud.size.y), "level with the gauge")
	check(mouth_rect.position.y + mouth_rect.size.y <= hud.size.y + 0.5, "inside the screen")
	m.stomach.fill = 0.0
	await frames(5)
	# --- textured blobs carry UVs
	var mass: MeshInstance3D = m.stomach_view.get_node("Mass")
	var uvs: PackedVector2Array = mass.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var spread := Rect2(uvs[0], Vector2.ZERO)
	for uv in uvs:
		spread = spread.expand(uv)
	check(uvs.size() > 0 and spread.size.length() > 0.5, "the stomach mass has real UVs (spread %s)" % spread.size)
	var chunk: MeshInstance3D = m.hands_rig.find_child("TornChunk", true, false)
	check(chunk != null and (chunk.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() > 0, "the torn chunk in the hand has UVs")
	# --- bits out of a tear fly and go
	var at: Vector3 = m.player.camera.global_position + Vector3(0, -0.2, -0.6)
	m.gore.burst(at, Vector3(0, 0, 1), 3, 7)
	check(m.gore.live_count() == 10, "a tear throws bits and drops")
	await frames(3)
	check(m.gore.get_node("Bits").multimesh.visible_instance_count == 3, "drawn as MultiMesh instances")
	var t := 0.0
	while t < 3.0 and m.gore.live_count() > 0:
		await process_frame
		t += get_root().get_process_delta_time()
	check(m.gore.live_count() == 0, "and they are gone within a few seconds (%.1f s)" % t)
	# --- the opening's vomit key goes once used
	var hints = m.opening_view.hints
	hints.vomit_learned = false
	var ev := InputEventAction.new()
	ev.action = "fp_vomit"
	ev.pressed = true
	hints._input(ev)
	check(hints.vomit_learned, "pressing V once retires the opening's V icon")
	# --- death wakes with the lids
	m.die("test")
	check(m.wake_lids.playing() and m.wake_lids.visible, "waking in the restroom starts with shut eyes")
	t = 0.0
	while t < 4.0 and m.wake_lids.playing():
		await process_frame
		t += get_root().get_process_delta_time()
	check(not m.wake_lids.playing() and not m.wake_lids.visible, "and the eyes are open within a few seconds (%.1f s)" % t)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.save_path))
	print("--- ui polish: %d passed, %d failed ---" % [passed, failed])
	m.queue_free()
	quit(1 if failed else 0)
