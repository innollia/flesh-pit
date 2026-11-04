class_name FPInteractions
extends RefCounted

const INPUT_MODES := preload("res://main/scripts/fp_input_modes.gd")
const ENTRY_INPUT_META := "settlement_inputs"

# A hit may be the fixture containing the target, never the whole room body.
static func check_aim(main: Node3D, point: Vector3, target_name: String = "", eye_override: Variant = null) -> bool:
	var eye: Vector3 = main.player.camera.global_position if eye_override == null else eye_override
	var q := PhysicsRayQueryParameters3D.create(eye, point)
	q.exclude = [main.player.get_rid()]
	q.hit_from_inside = true
	var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	var body := hit.collider as CollisionObject3D
	if body == null:
		return false
	var room_body: Node = main.restroom.get_node_or_null("RoomBody")
	var door_body: Node = main.restroom.door_pivot.get_node_or_null("DoorBody")
	var fixture_target := target_name in ["toilet", "lever", "tank_teeth", "sink", "mirror"]
	if (fixture_target and body == room_body) or (target_name == "door" and body == door_body):
		var owner_node := body.shape_owner_get_owner(body.shape_find_owner(int(hit.shape))) as CollisionShape3D
		if owner_node != null and owner_node.shape is BoxShape3D:
			var local: Vector3 = owner_node.to_local(point)
			var half: Vector3 = (owner_node.shape as BoxShape3D).size * 0.5 + Vector3.ONE * 0.025
			if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
				return true
	# Wall-mounted targets meet the wall at their actual endpoint.
	return eye.distance_to(hit.position) >= eye.distance_to(point) - 0.025

static func get_candidates(main: Node3D) -> Array:
	var candidates: Array = [
		["mirror", main.mirror_point(), 18.0, 1.3],
		["sink", main.sink_point(), 12.0, 1.25],
		["lever", main.lever_point(), 8.0, 1.25],
		["toilet", main.toilet_point(), 12.0, 1.35],
		["vent", FPRestroom.VENT_CENTER, 12.0, 2.0],
	]
	if main.vent.is_open and not main.vent.offers.is_empty():
		# the being's hand holds the offer out below the grate
		candidates.append(["vent", main.vent.offer_center(), 12.0, 2.0])
		# one hand per offered item, spread in front of the eye: each item is
		# an aim point of its own so the outer hands can be taken too
		for n in main.vent.offer_nodes():
			candidates.append(["vent", (n as Node3D).global_position, 9.0, 2.0])
	var pivot: Node3D = main.restroom.door_pivot
	var width := 2.0 * FPRestroom.DOOR_HALF_W - 0.01
	candidates.append(["door", pivot.to_global(Vector3(width - 0.095, 0.995, 0)), 30.0, 1.6])
	candidates.append(["door", pivot.to_global(Vector3(width * 0.5, FPRestroom.DOOR_H * 0.5, 0)), 30.0, 1.6])
	if not main.has_canary:
		candidates.append(["canary", main.canary_hole_point(), 10.0, 1.25])
	if main.tank_lid != null and main.tank_lid.can_pick():
		candidates.append(["tank_lid", main.tank_lid.lid.global_position, FPTankLid.AIM_DEGREES, FPTankLid.AIM_REACH])
	var tank_open: bool = main.tank_lid != null and not main.tank_lid.on_tank
	if tank_open and (main.progression.teeth > 0 or main.progression.teeth_in_hand > 0):
		candidates.append(["tank_teeth", main.restroom.tank_art.to_global(Vector3(0, 0.3, 0)), FPTankLid.AIM_DEGREES + 2.0, FPTankLid.AIM_REACH])
	var can: Node3D = main.nearest_rest_can(1.4)
	if can != null:
		candidates.append(["rest_can", can.global_position, 12.0, 1.4])
	var tumor: Node3D = main._nearest_tumor(1.25)
	if tumor != null:
		candidates.append(["tumor", tumor.global_position, 10.0, 1.25])
	return candidates

static func is_lever_aimed(main: Node3D, camera: Camera3D = null) -> bool:
	var point: Vector3 = main.lever_point()
	# The presentation camera cannot extend the player's physical reach.
	var physical_eye: Vector3 = main.player.camera.global_position
	if physical_eye.distance_to(point) > 1.25 or not check_aim(main, point, "lever", physical_eye):
		return false
	if camera == null:
		camera = main.player.camera
	var viewport := camera.get_viewport()
	var forward := -camera.global_basis.z
	var direction := (point - camera.global_position).normalized()
	if forward.dot(direction) > cos(deg_to_rad(8.0)):
		return true
	if camera == main.settle_camera and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		if camera.is_position_behind(point):
			return false
		var cursor_ray := camera.project_ray_normal(viewport.get_mouse_position())
		return cursor_ray.dot(direction) > cos(deg_to_rad(8.0))
	return false

# --- One place that decides what a press does (docs/business-rules.md
# "조작 우선순위"). Modal states (opening, seated, settling, Tab, canary
# pull, menus) own every input before this runs (main._process). A press of
# one source does exactly one thing, the first that applies:
#   1. a held tank lid: F or the right hand holding it puts it down
#   2. the aimed belt hook (looking down): that hand swaps with it; F does not
#   3. the aimed fixture or object, nearest the crosshair (interact_target):
#      F or either hand acts on it; the hand that pressed reaches for it
#      (left click the left hand, right click and F the right). Two things
#      are not the left hand's: the lid (it goes to the right hand) and
#      anything while it grips the blender (right_hand_only). Only one
#      target action per frame, whichever source comes first; the later
#      press of that frame still keeps its hand off digging.
#   4. the item in that hand: spray, blender, feed, barrier
#   5. otherwise a bare, knife or saw hand digs while held; F settles when
#      standing by the toilet with something to give.
# A hand whose press did 1-4 stays blocked until released (the blender
# excepted: it charges while held): holding it never turns into digging or a
# second use.
const SOURCE_INTERACT := "interact"
const SOURCE_LEFT := "left"
const SOURCE_RIGHT := "right"
const ITEM_VERBS := ["spray_cheap", "spray_deep", "blender", "canary_feed", "barrier"]
const DIG_ITEMS := ["", "knife", "big_saw"]
const TARGET_FRAME_META := "fp_target_frame"
## press() result when another source already acted on a target this frame:
## nothing happens, but the hand stays blocked like a target press.
const TARGET_TAKEN := "target_taken"

static func source_hand(source: String) -> int:
	match source:
		SOURCE_LEFT: return FDKToolKit.Hand.LEFT
		SOURCE_RIGHT: return FDKToolKit.Hand.RIGHT
	return -1

## An aimed target F or a hand button acts on (the belt hooks take only
## the hand buttons, through the belt swap).
static func acts_on(target: String) -> bool:
	return target != "" and target != "belt"

## The left button leaves this target to the right hand: the lid is held in
## the right hand, and a left hand on the blender stays on it.
static func right_hand_only(main: Node3D, target: String) -> bool:
	return target == "tank_lid" or main.progression.hands.item(FDKToolKit.Hand.LEFT) == "blender"

## What a fresh press of `source` would do now, without doing it:
## "lid_down", "belt", "target:<name>", "item:<id>", "dig", "settle" or "none".
static func plan(main: Node3D, source: String) -> String:
	var hand := source_hand(source)
	if main.tank_lid != null and main.tank_lid.held:
		return "none" if source == SOURCE_LEFT else "lid_down"
	if main.belt_swap != null and main.belt_swap.busy():
		return "none"
	if hand >= 0 and main.belt_swap != null and main.belt_swap.aimed_hook() >= 0:
		return "belt"
	var target: String = main.interact_target()
	if acts_on(target) and not (source == SOURCE_LEFT and right_hand_only(main, target)):
		return "target:" + target
	if hand < 0:
		if main._near_toilet() and main.has_settle_contents():
			return "settle"
		return "none"
	var id: String = main.progression.hands.item(hand)
	if id in ITEM_VERBS:
		return "item:" + id
	if id in DIG_ITEMS:
		return "dig"
	return "none"

## Do what plan() says for a fresh press and return the verb. "dig" is left
## to the caller, which keeps digging while the button stays held.
static func press(main: Node3D, source: String) -> String:
	var verb := plan(main, source)
	var hand := source_hand(source)
	if verb.begins_with("target:"):
		var frame := Engine.get_process_frames()
		if int(main.get_meta(TARGET_FRAME_META, -1)) == frame:
			return TARGET_TAKEN
		main.set_meta(TARGET_FRAME_META, frame)
		main.activate_target(verb.substr(7), source)
		return verb
	match verb:
		"lid_down":
			main.tank_lid.drop()
		"belt":
			main.belt_swap.begin(hand)
		"item:spray_cheap", "item:spray_deep":
			main.use_spray(verb == "item:spray_deep")
		"item:blender":
			main.use_blender()
		"item:canary_feed":
			main.feed_canary()
		"item:barrier":
			main.place_barrier()
		"settle":
			main.start_settlement()
	return verb

## Whether the verb keeps its hand from digging until the button is released.
static func blocks_hand(verb: String) -> bool:
	if verb == "item:blender":
		return false # it charges while the button is held
	return verb in ["lid_down", "belt", TARGET_TAKEN] or verb.begins_with("target:") or verb.begins_with("item:")

static func begin_settlement(main: Node3D) -> void:
	main.set_meta(ENTRY_INPUT_META, INPUT_MODES.settlement_inputs())

static func handle_settling_input(main: Node3D, entry_frame: int, _entry_action: String = "") -> String:
	var current: Dictionary = INPUT_MODES.settlement_inputs()
	var previous: Dictionary = main.get_meta(ENTRY_INPUT_META, current)
	main.set_meta(ENTRY_INPUT_META, current)
	if Engine.get_process_frames() == entry_frame:
		return "guard"
	var fresh: Array[String] = []
	for action in current:
		if bool(current[action]) and not bool(previous.get(action, false)):
			fresh.append(action)
	if fresh.is_empty():
		return "none"
	# Over the bowl the lever is out of view: the right hand (R / right
	# click) reaches back and presses it, as it does seated. F presses it
	# only when the cursor is on it; anything else stands up.
	for action in ["fp_pick", "key_r", "mouse_right"]:
		if fresh.has(action):
			main.flush()
			return "flush"
	if is_lever_aimed(main, main.settle_camera):
		# the left hand button (left click / E) on the aimed lever, as F
		for action in ["fp_interact", "key_f", "fdk_eat"]:
			if fresh.has(action):
				main.flush()
				return "flush"
	main.leave_settlement()
	return "exit"
