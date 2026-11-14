extends SceneTree

## Sealed in before the first settlement (decision 0013, amending 0009).
## Real Main, its own save and key files. Before the lever has ever been
## pulled the body sits at the end of a tunnel dug 3.9 m out of the door with
## the stomach at its end (160), and the tunnel behind it has grown shut.
## - the trap: 60 s on it has not died (nothing presses a body that can still
##   shift in its pocket), the way back is solid, every bite is refused, the
##   hands cannot carry
## - the way out: with the stomach at its end, vomiting outside empties it
##   (no teeth, no settlement, the lever still unpulled) and the next bite
##   tears; one unit short of the end it is still the dry heave of 0009

var m: Node3D
var passed := 0
var failed := 0
const DOOR_Z := 1.5
const END_Z := 6.0
const BODY := Vector3(0.0, 0.5, 5.4)

func _init() -> void:
	Engine.max_fps = 60
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = "user://keybinds_test_first_seal.json"
	m.save_path = "user://capture-first-seal-tests.bin"
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

func physics(n: int) -> void:
	for i in range(n):
		await physics_frame

func mouse(held: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = held
	Input.parse_input_event(e)

func set_fill(v: float) -> void:
	m.stomach.fill = v
	m.stomach.fill_changed.emit(v, m.stomach_config.capacity, m.stomach_config.overfill_capacity)

func face_door() -> void:
	m.player._yaw = 0.0
	m.player.rotation.y = 0.0
	m.player._pitch = 0.0
	m.player.camera_pivot.rotation.x = 0.0

## Solid cells on the tunnel's line between the door and the body's pocket.
func closed_cells() -> int:
	var n := 0
	var z := DOOR_Z + 0.25
	while z < BODY.z - 1.0:
		if m.terrain.density_at(Vector3(0.0, 0.5, z)) >= m.terrain_config.iso_level:
			n += 1
		z += 0.5
	return n

func run() -> void:
	await physics(5)
	m.save_path = "user://capture-first-seal-tests.bin"
	m.finish_opening()
	m.restroom.set_door_open(true, true)
	m.player.mouse_look_enabled = false
	check(not m.lever_settled and m.progression.teeth == 0, "fixture: a new game, the lever never pulled")
	check(not m.progression.owns("blender") and not m.progression.can_lift_without_blender(), "fixture: nothing to carry flesh with yet")
	# the tunnel: really dug (its flesh grows back), two cells wide, three high
	var z := DOOR_Z + 0.25
	while z < END_Z:
		for y in [0.25, 0.75, 1.25]:
			for x in [-0.25, 0.25]:
				m.terrain.dig_at(Vector3(x, y, z), 1.0)
		z += 0.5
	Input.action_press("fdk_crouch")
	m.player.global_position = BODY
	face_door()
	set_fill(m.stomach_config.capacity + m.stomach_config.overfill_capacity)
	# the tunnel behind grows shut: regrowth run by hand, the body's 0.9 m held
	for i in range(m.REGEN_STAGGER + 1):
		m.terrain.regenerate_all(2000.0, BODY, m.BODY_PROTECT_RADIUS)
	m.terrain.remesh_all()
	await physics(40)
	await frames(3)
	var away: float = m.player.global_position.z - DOOR_Z
	check(away > 3.0 and not m.restroom.contains(m.player.global_position), "fixture: the body is %.1f m out of the door" % away)
	check(closed_cells() >= 5, "fixture: the tunnel behind is solid again (%d cells on its line)" % closed_cells())
	check(m.stomach.is_full() and is_equal_approx(m.stomach.fill, 160.0), "fixture: the stomach is at its end (160)")
	var torn := [0]
	var refused := [0]
	var heaves := [0]
	m.chewer.cell_torn.connect(func(_p): torn[0] += 1)
	m.chewer.refused_full.connect(func(_p): refused[0] += 1)
	m.dry_heaved.connect(func(): heaves[0] += 1)
	var deaths0: int = m.deaths
	var crush_max := 0.0
	# --- 60 s of trying everything a new player has
	# walk at the way back
	Input.action_press("fdk_move_forward")
	var min_z: float = m.player.global_position.z
	for i in range(300):
		await physics_frame
		min_z = minf(min_z, m.player.global_position.z)
		crush_max = maxf(crush_max, m.crush_progress())
	Input.action_release("fdk_move_forward")
	# bite at it
	var hit: Dictionary = m._look_hit()
	var in_reach: bool = not hit.is_empty() and hit.collider.has_meta("fdk_terrain_chunk")
	mouse(true)
	for i in range(300):
		await process_frame
		crush_max = maxf(crush_max, m.crush_progress())
	mouse(false)
	await frames(2)
	var torn_full: int = torn[0]
	var refused_full: int = refused[0]
	# carry it instead
	m.toggle_carry()
	var carried: bool = m.carry_mode
	if carried:
		m.toggle_carry()
	# the rest of the minute
	for i in range(3000):
		await process_frame
		crush_max = maxf(crush_max, m.crush_progress())
	print("SEAL after 60 s: deaths %d, crush max %.2f, nearest to the door %.2f m, flesh in reach %s, torn %d, refused %d, carry %s, fill %.1f, closed cells %d" % [
		m.deaths - deaths0, crush_max, min_z - DOOR_Z, in_reach, torn_full, refused_full, carried, m.stomach.fill, closed_cells()])
	check(m.deaths == deaths0, "sealed in: 60 s on the body has not died (crush at most %.2f)" % crush_max)
	check(min_z - DOOR_Z > 2.0 and closed_cells() >= 5, "sealed in: walking at it does not open the way back (%.1f m from the door)" % (min_z - DOOR_Z))
	check(in_reach and torn_full == 0 and refused_full > 0, "sealed in: every bite at the flesh is refused (torn %d, refused %d)" % [torn_full, refused_full])
	check(not carried, "sealed in: the hands cannot carry flesh yet")
	check(is_equal_approx(m.stomach.fill, 160.0), "sealed in: the stomach is still at its end")
	# --- one unit short of the end: the dry heave of decision 0009
	set_fill(159.0)
	m.request_vomit()
	await frames(2)
	check(heaves[0] == 1 and is_equal_approx(m.stomach.fill, 159.0), "159 units outside before the first settlement: a dry heave, nothing comes up")
	# --- at the end: it comes up
	set_fill(160.0)
	m.request_vomit()
	check(is_equal_approx(m.stomach.fill, 160.0) and m.discard_holding(), "160 units outside: the press starts the bow, the stomach goes only with the key held")
	for i in range(17): # the key held 0.85 s (DISCARD_HOLD 0.8)
		m.discard_hold_step(0.05, true)
	await frames(2)
	print("SEAL vomit at the end: fill %.1f, heaves %d, teeth %d, lever %s" % [m.stomach.fill, heaves[0], m.progression.teeth, m.lever_settled])
	check(is_equal_approx(m.stomach.fill, 0.0) and heaves[0] == 1, "160 units outside before the first settlement: the stomach empties (%.1f)" % m.stomach.fill)
	check(m.progression.teeth == 0 and not m.lever_settled and not m.toilet.has_contents(), "nothing is settled by it: no teeth, the lever still unpulled")
	await frames(90) # the vomit's hand motion ends
	face_door()
	mouse(true)
	for i in range(240):
		await process_frame
		if torn[0] > torn_full:
			break
	mouse(false)
	await frames(2)
	check(torn[0] > torn_full and m.stomach.fill > 0.0, "and the next bite tears: the way back can be eaten open (fill %.1f)" % m.stomach.fill)
	Input.action_release("fdk_crouch")
	print("--- first seal: %d passed, %d failed ---" % [passed, failed])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture-first-seal-tests.bin"))
	quit(1 if failed else 0)
