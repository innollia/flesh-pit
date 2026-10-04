class_name FPInteractions
extends RefCounted

## T5 interaction helper module (R01, R02, R03, R04, R05, R16).
## Handles fixture-specific aiming, occlusion predicates, candidate selection,
## and toilet settlement inputs.

## True if the ray from eye to canary hole passes under the sink apron (y <= APRON_BOTTOM).
static func check_canary_apron_los(eye: Vector3, hole_pt: Vector3) -> bool:
	var x_apron := -FPRestroom.HALF.x + 0.34
	var dx := hole_pt.x - eye.x
	if absf(dx) > 0.001:
		var t := (x_apron - eye.x) / dx
		if t > 0.0 and t < 1.0:
			var y_at_apron := eye.y + t * (hole_pt.y - eye.y)
			if y_at_apron > FPRestroom.APRON_BOTTOM:
				return false
	return true

## Checks raycast occlusion for candidate targets with fixture collider tolerances.
static func check_aim(main: Node3D, point: Vector3, target_name: String = "") -> bool:
	if main == null or not is_instance_valid(main):
		return false
	var eye: Vector3 = main.player.camera.global_position
	var space_state := main.get_world_3d().direct_space_state

	# Canary hole special predicate (R05):
	var is_canary := (target_name == "canary") or (point.distance_to(main.canary_hole_point()) < 0.15)
	if is_canary:
		if not check_canary_apron_los(eye, point):
			return false
		var q := PhysicsRayQueryParameters3D.create(eye, point)
		q.exclude = [main.player.get_rid()]
		var hit := space_state.intersect_ray(q)
		if hit.is_empty():
			return true
		var room_body: Node3D = main.restroom.get_node_or_null("RoomBody") if main.restroom != null else null
		# Shape 9 is the sink fixture bounding box in RoomBody.
		# The authored collision box filled y = 0..0.9, but the real apron ends at y = 0.34.
		# If the hit on the sink box is below APRON_BOTTOM, the space is open underneath.
		if room_body != null and hit.collider == room_body and hit.shape == 9 and hit.position.y < FPRestroom.APRON_BOTTOM:
			var ray_dir := (point - eye).normalized()
			var q2 := PhysicsRayQueryParameters3D.create(hit.position + ray_dir * 0.05, point)
			q2.exclude = [main.player.get_rid()]
			var hit2 := space_state.intersect_ray(q2)
			return hit2.is_empty() or eye.distance_to(hit2.position) >= eye.distance_to(point) - 0.25
		return eye.distance_to(hit.position) >= eye.distance_to(point) - 0.25

	# Door special predicate (R16):
	var is_door := (target_name == "door")
	if is_door:
		var q := PhysicsRayQueryParameters3D.create(eye, point)
		q.exclude = [main.player.get_rid()]
		var hit := space_state.intersect_ray(q)
		if hit.is_empty():
			return true
		if hit.collider != null and hit.collider.name == "DoorBody":
			return true
		return eye.distance_to(hit.position) >= eye.distance_to(point) - 0.25

	# Standard target raycast:
	var q := PhysicsRayQueryParameters3D.create(eye, point)
	q.exclude = [main.player.get_rid()]
	var hit := space_state.intersect_ray(q)
	return hit.is_empty() or eye.distance_to(hit.position) >= eye.distance_to(point) - 0.30

## Builds candidates for interact_target() adhering to R01, R02, R05, R16.
static func get_candidates(main: Node3D) -> Array:
	var candidates: Array = [
		["mirror", main.mirror_point(), 18.0, 1.3],
		["sink", main.sink_point(), 12.0, 1.25],
		["lever", main.lever_point(), 8.0, 1.25],
		["toilet", main.toilet_point(), 12.0, 1.35],
		["vent", FPRestroom.VENT_CENTER, 12.0, 2.0],
	]

	# Door: actual rotated geometry (R16)
	if main.restroom != null and main.restroom.door_pivot != null:
		var w := 2.0 * FPRestroom.DOOR_HALF_W - 0.01
		var handle_pt: Vector3 = main.restroom.door_pivot.to_global(Vector3(w - 0.095, 0.995, 0.0))
		var center_pt: Vector3 = main.restroom.door_pivot.to_global(Vector3(w * 0.5, FPRestroom.DOOR_H * 0.5, 0.0))
		candidates.append(["door", handle_pt, 30.0, 1.6])
		candidates.append(["door", center_pt, 30.0, 1.6])
	else:
		candidates.append(["door", Vector3(0, 1, FPRestroom.HALF.z), 30.0, 1.6])

	# Canary: under-sink hidden hole (R05)
	if not main.has_canary:
		candidates.append(["canary", main.canary_hole_point(), 10.0, 1.25])

	# Tank lid: pick up from tank or floor (R02)
	if main.tank_lid != null and main.tank_lid.can_pick():
		candidates.append(["tank_lid", main.tank_lid.lid.global_position, 12.0, 1.35])

	# Tank teeth: open tank with teeth inside (R02)
	if main.restroom != null and main.restroom.tank_art != null:
		var tank_open := (main.tank_lid != null and not main.tank_lid.on_tank) or main.restroom._lid_target != 0.0
		if tank_open and (main.progression.teeth > 0 or main.progression.teeth_in_hand > 0):
			var teeth_pt: Vector3 = main.restroom.tank_art.to_global(Vector3(0, 0.3, 0))
			candidates.append(["tank_teeth", teeth_pt, 12.0, 1.35])

	# Tumor
	var tumor := main._nearest_tumor(1.25)
	if tumor != null:
		candidates.append(["tumor", tumor.global_position, 10.0, 1.25])

	return candidates

## Checks if the lever is aimed from settle_camera or cursor during settlement.
static func is_lever_aimed(main: Node3D, camera: Camera3D = null) -> bool:
	if main == null or not is_instance_valid(main):
		return false
	var lp: Vector3 = main.lever_point()
	if camera == null:
		camera = main.settle_camera if main.settle_camera != null and main.settle_camera.current else main.player.camera

	if camera == null:
		return false

	# 1. Screen / mouse ray check
	var vp := main.get_viewport()
	if vp != null:
		var mouse_pos := vp.get_mouse_position()
		var origin := camera.project_ray_origin(mouse_pos)
		var dir := camera.project_ray_normal(mouse_pos)
		var diff := lp - origin
		var d := diff.dot(dir)
		if d > 0.0:
			var closest := origin + dir * d
			if closest.distance_to(lp) < 0.25:
				return true

		# 2. Viewport center ray check (gamepad / crosshair)
		var center := vp.get_visible_rect().size * 0.5
		var corigin := camera.project_ray_origin(center)
		var cdir := camera.project_ray_normal(center)
		var cdiff := lp - corigin
		var cd := cdiff.dot(cdir)
		if cd > 0.0:
			var cclosest := corigin + cdir * cd
			if cclosest.distance_to(lp) < 0.28:
				return true

		# 3. 2D unproject distance check
		if not camera.is_position_behind(lp):
			var spos := camera.unproject_position(lp)
			var scale: float = main.interact_ring.ui_scale() if main.interact_ring != null else 1.0
			if mouse_pos.distance_to(spos) < 65.0 * scale or center.distance_to(spos) < 65.0 * scale:
				return true

	# 4. Fallback camera look angle
	var to_lever := lp - camera.global_position
	if to_lever.length() <= 1.4:
		var fwd := -camera.global_transform.basis.z
		if to_lever.normalized().dot(fwd) > cos(deg_to_rad(20.0)):
			return true

	return false

## Handles input during settlement (R03).
static func handle_settling_input(main: Node3D, entry_frame: int, entry_action: String) -> String:
	if Engine.get_process_frames() == entry_frame:
		return "guard"

	# If the entry press is still held, ignore it to prevent immediate exit
	if entry_action != "" and Input.is_action_pressed(entry_action):
		return "holding"

	# If aiming at the lever, F or R/RMB flushes (priority)
	var aiming_lever := is_lever_aimed(main, main.settle_camera)
	if aiming_lever:
		if Input.is_action_just_pressed("fp_interact") or Input.is_action_just_pressed("fp_pick"):
			main.flush()
			return "flush"

	# Exit settlement inputs (V, WASD, Space, Esc, LMB, F/RMB not on lever, gamepad move/cancel)
	if FPInputModes.is_settle_exit_requested(entry_frame, entry_action):
		main.leave_settlement()
		return "exit"

	return "none"
