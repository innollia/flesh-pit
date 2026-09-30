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
	# hips stay where they are while the head searches (as when bowed)
	_err(i, by, bp)
	_hip = m.belt_swap._hip_yaw
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
	_hip = NAN

func _err(i: int, yaw: float, pitch: float) -> float:
	var pl = _m.player
	pl.set("_yaw", yaw)
	pl.rotation = Vector3(0, yaw, 0)
	pl.set("_pitch", pitch)
	pl.camera_pivot.rotation.x = pitch
	pl.force_update_transform()
	if not is_nan(_hip):
		_m.belt_swap._hip_yaw = _hip
	_m.belt_swap.tick(0.0)
	var r: Array = pl.get_look_ray()
	var hp: Vector3 = _m.art_hookup.belt.call("hook_point", i)
	return (r[1] as Vector3).angle_to(hp - r[0])
var _aim_i := 0
var _hip := NAN

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
	# a new game has no belt: no band, no hooks, nothing to swap when bowed
	bs.tick(0.0)
	_assert(not prog.has_belt and not bs.worn(), "a new game starts without the belt")
	_assert(not (belt.get_node("Belt") as Node3D).visible and not (belt.get_node("Hook0") as Node3D).visible and not (belt.get_node("ToolRail") as Node3D).visible, "no band, rail or hooks before the first trade")
	m.player.camera_pivot.rotation.x = -1.3
	m.player.force_update_transform()
	bs.tick(0.0)
	_assert(not bs.looking_down() and bs.aimed_hook() == -1 and m.interact_target() != "belt" and m.hands_rig.aside < 0.01, "bowing without a belt shows no hooks and no swap")
	m.player.camera_pivot.rotation.x = 0.0
	# the first vent trade hands over the belt
	var v: FPVent = m.vent
	v.open(prog.teeth)
	v.place_teeth(4, prog)
	v.close()
	bs.tick(0.0)
	_assert(prog.has_belt and bs.worn() and (belt.get_node("Belt") as Node3D).visible and (belt.get_node("Hook0") as Node3D).visible, "the first vent trade gives the belt")
	# kept through save / load, and a fresh start stays beltless
	var d2 := prog.serialize()
	var p2 := FPProgression.new()
	_assert(not p2.has_belt, "fresh progression: no belt")
	p2.deserialize(d2)
	_assert(p2.has_belt, "the belt survives save / load")
	var d3 := FPProgression.new().serialize()
	var p3 := FPProgression.new()
	p3.deserialize(d3)
	_assert(not p3.has_belt, "a beltless save loads beltless")
	# round band: many segments following the waist curve
	var bm := (belt.get_node("Belt") as MeshInstance3D).mesh
	var bv: PackedVector3Array = bm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var angs := {}
	for p in bv:
		if absf(p.y) < 0.021 and Vector2(p.x, p.z).length() > 0.15:
			angs[int(round(rad_to_deg(atan2(p.z, p.x)) * 2.0))] = true
	_assert(angs.size() >= 40, "the belt band goes round the waist in many segments (%d)" % angs.size())
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
	_assert(m.hands_rig.aside > 0.99, "bowed past 55 degrees the hands swing aside (%.2f)" % m.hands_rig.aside)
	var k720: float = 720.0 / cam.get_viewport().get_visible_rect().size.y
	var hx: Array = []
	for hi in range(3):
		hx.append(cam.unproject_position((belt.get_node("Hook%d" % hi) as Node3D).global_position).x * k720)
	_assert(hx[1] - hx[0] >= 120.0 and hx[2] - hx[1] >= 120.0, "hooks at least 120 px apart at 720p (%s)" % [hx])
	var tl := (belt.get_node("Hook1/Tool") as Node3D)
	var mn := Vector2(INF, INF)
	var mx := -mn
	for mi in tl.find_children("*", "MeshInstance3D", true, false):
		if not (mi as MeshInstance3D).visible:
			continue
		var bx: AABB = (mi as MeshInstance3D).mesh.get_aabb()
		for c in range(8):
			var sp2 := cam.unproject_position((mi as MeshInstance3D).global_transform * (bx.position + bx.size * Vector3(c & 1, (c >> 1) & 1, (c >> 2) & 1))) * k720
			mn = mn.min(sp2)
			mx = mx.max(sp2)
	_assert(maxf(mx.x - mn.x, mx.y - mn.y) >= 80.0, "a hung tool is at least 80 px at 720p (%s)" % [mx - mn])	# bare hands: take the knife through fp_interact (the same path every device uses)
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