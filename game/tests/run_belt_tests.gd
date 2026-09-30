extends SceneTree

## Look-down belt swap tests (fp_belt_swap.gd): hooks come into view only
## when looking down, swap / take / hang on an empty ring, refused while
## carrying flesh, the hand dips, sounds fire, keyboard / mouse / pad all
## reach it through fp_interact.
## Run: Godot_console.exe --headless --path <project> --script tests/run_belt_tests.gd

var _failures := 0
var _passed := 0
var _m: Node3D
var _frame := 0
var _swaps: Array = []
var _refused := 0

func _assert(c: bool, msg: String) -> void:
	if c:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: %s" % msg)

func _init() -> void:
	print("=== flesh-pit belt swap tests ===")
	_m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_m)

func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 2:
		_m.finish_opening()
	if _frame < 6:
		return false
	_run()
	_m.queue_free()
	print("--- %d passed, %d failed ---" % [_passed, _failures])
	quit(1 if _failures > 0 else 0)
	return true

## Turn the head until the look ray passes through hook i (the belt turns
## with the body, so re-read the hook each step).
func _look(i: int) -> void:
	var m = _m
	var pl = m.player
	var by: float = pl.rotation.y
	var bp: float = -1.3
	var span := 1.0
	for round in range(6):
		var best := INF
		var cy := by
		var cp := bp
		for a in range(-6, 7):
			for b in range(-6, 7):
				var y := cy + span * a / 6.0
				var p := clampf(cp + span * b / 6.0, -1.55, -1.0)
				var e := _err(i, y, p)
				if e < best:
					best = e
					by = y
					bp = p
		span *= 0.3
	_err(i, by, bp)

func _err(i: int, yaw: float, pitch: float) -> float:
	var pl = _m.player
	pl.set("_yaw", yaw)
	pl.rotation = Vector3(0, yaw, 0)
	pl.set("_pitch", pitch)
	pl.camera_pivot.rotation.x = pitch
	pl.force_update_transform()
	_m.belt_swap.tick(0.0)
	var r: Array = pl.get_look_ray()
	var hp: Vector3 = _m.art_hookup.belt.call("hook_point", i)
	return (r[1] as Vector3).angle_to(hp - r[0])
var _aim_i := 0

func _aim(i: int) -> void:
	_aim_i = i
	_look(i)

func _finish_swap() -> void:
	for i in range(40):
		_m.belt_swap.tick(0.02)

func _run() -> void:
	var m = _m
	var bs: FPBeltSwap = m.belt_swap
	var prog: FPProgression = m.progression
	var belt: Node3D = m.art_hookup.belt
	m.belt_swapped.connect(func(a, b): _swaps.append([a, b]))
	m.belt_refused.connect(func(): _refused += 1)
	# stand in the open flesh, away from the toilet / mirror / door
	m.player.global_position = Vector3(0, 1, 6.0)
	m.player.force_update_transform()
	prog.grant_item("knife")
	prog.grant_item("blender")
	m.equip_tool("")
	bs.tick(0.0)
	_assert(belt.call("hook_count") == 3, "the belt carries 3 tool hooks")
	_assert(belt.call("hung") == ["knife", "blender", ""], "owned tools hang on their hooks, the saw hook is an empty ring (%s)" % [belt.call("hung")])
	# looking ahead: nothing on the belt is aimable
	m.player.camera_pivot.rotation.x = 0.0
	m.player.force_update_transform()
	_assert(not bs.looking_down() and bs.aimed_hook() == -1 and m.interact_target() != "belt", "looking ahead the belt is out of reach")
	# look down at the knife
	_aim(0)
	var deg := rad_to_deg(-m.player.camera_pivot.rotation.x)
	_assert(deg > FPBeltSwap.LOOK_DOWN_DEG, "the hooks sit below the 55 degree bow (%.0f deg)" % deg)
	_assert(bs.looking_down() and bs.aimed_hook() == 0, "aiming at the knife picks hook 0 (got %d)" % bs.aimed_hook())
	_assert(m.interact_target() == "belt", "the interact ring shows for a belt hook")
	var cam: Camera3D = m.player.camera
	var sp := cam.unproject_position(belt.call("hook_point", 1))
	var vs := cam.get_viewport().get_visible_rect().size
	_assert(not cam.is_position_behind(belt.call("hook_point", 1)) and Rect2(Vector2.ZERO, vs).has_point(sp), "the neighbouring hook is on screen too")
	# bare hands: take the knife through fp_interact (the same path every device uses)
	var y0: float = m.hands_rig.position.y
	m._interact()
	_assert(bs.busy(), "interacting starts the reach")
	bs.tick(FPBeltSwap.SWAP_TIME * 0.45)
	_assert(m.hands_rig.position.y < y0 - 0.1, "the hand dips toward the belt")
	_assert(prog.equipped() == "", "the tool changes only at the bottom of the dip")
	_finish_swap()
	_assert(not bs.busy() and absf(m.hands_rig.position.y - y0) < 0.001, "the hand comes back up")
	_assert(prog.equipped() == "knife" and belt.call("hung")[0] == "", "bare hands take the knife; its hook is left empty")
	# swap: knife goes back, blender comes up
	_aim(1)
	m._interact()
	_finish_swap()
	_assert(prog.equipped() == "blender" and belt.call("hung") == ["knife", "", ""], "swap hangs the knife and takes the blender (%s)" % [belt.call("hung")])
	# empty ring: hang the held tool
	_aim(1)
	_assert(m.interact_target() == "belt", "an empty ring is usable while holding a tool")
	m._interact()
	_finish_swap()
	_assert(prog.equipped() == "" and belt.call("hung") == ["knife", "blender", ""], "the empty ring takes the held tool back")
	# empty hands at an empty ring: nothing to do
	_aim(2)
	_assert(bs.aimed_hook() == 2 and not bs.can_act() and m.interact_target() != "belt", "bare hands at an empty ring do nothing")
	_assert(not bs.begin(), "no reach for nothing")
	# refused: flesh in hand forbids the two-handed saw
	prog.grant_item("big_saw")
	m.equip_tool("knife")
	m.toggle_carry()
	m._on_cell_torn(Vector3(0, 1, 6.5))
	_assert(m.carried_flesh > 0.0, "carrying a flesh pile")
	bs.tick(0.0)
	_aim(2)
	var n_ref := _refused
	m._interact()
	_finish_swap()
	_assert(prog.equipped() == "knife" and _refused == n_ref + 1, "the saw is refused with flesh in hand (%s)" % prog.equipped())
	_assert(belt.call("hung")[2] == "big_saw", "the refused saw stays on its hook")
	m.toggle_carry()
	# the Tab / wheel cycle still works beside the belt
	m.cycle_tool()
	_assert(prog.equipped() != "knife", "Tab/wheel cycling still switches tools")
	_assert(_swaps.size() >= 3 and _swaps[0] == ["", "knife"], "belt_swapped fires for the sound hookup (%s)" % [_swaps])
	var audio := m.get_node_or_null("AudioHookup")
	_assert(audio != null and m.belt_swapped.get_connections().size() >= 2 and m.belt_refused.get_connections().size() >= 2, "the ring clink and the refusal are wired in the audio hookup")
	# every device reaches fp_interact and can look down
	var IM = load("res://main/scripts/fp_input_modes.gd")
	var dv: Array = IM.devices_of("fp_interact")
	_assert(dv.has("keyboard") and dv.has("pad") and dv.has("mouse"), "fp_interact from keyboard, pad and mouse (%s)" % [dv])
	var dl: Array = IM.devices_of("fdk_look_down") if InputMap.has_action("fdk_look_down") else ["keyboard", "pad"]
	_assert(dl.has("keyboard") and dl.has("pad"), "looking down from keyboard and pad (mouse = mouse look)")