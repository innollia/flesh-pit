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
	var pivot: Node3D = main.restroom.door_pivot
	var width := 2.0 * FPRestroom.DOOR_HALF_W - 0.01
	candidates.append(["door", pivot.to_global(Vector3(width - 0.095, 0.995, 0)), 30.0, 1.6])
	candidates.append(["door", pivot.to_global(Vector3(width * 0.5, FPRestroom.DOOR_H * 0.5, 0)), 30.0, 1.6])
	if not main.has_canary:
		candidates.append(["canary", main.canary_hole_point(), 10.0, 1.25])
	if main.tank_lid != null and main.tank_lid.can_pick():
		candidates.append(["tank_lid", main.tank_lid.lid.global_position, 8.0, 1.25])
	var tank_open: bool = main.tank_lid != null and not main.tank_lid.on_tank
	if tank_open and (main.progression.teeth > 0 or main.progression.teeth_in_hand > 0):
		candidates.append(["tank_teeth", main.restroom.tank_art.to_global(Vector3(0, 0.3, 0)), 10.0, 1.25])
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
	if is_lever_aimed(main, main.settle_camera):
		for action in ["fp_interact", "fp_pick", "key_f", "key_r", "mouse_right"]:
			if fresh.has(action):
				main.flush()
				return "flush"
	main.leave_settlement()
	return "exit"
