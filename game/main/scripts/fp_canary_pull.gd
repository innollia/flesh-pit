class_name FPCanaryPull
extends RefCounted

## One reaching arm, one bracing arm. Possession begins only after tucking.
const DURATION := 5.6
var m: Node3D
var elapsed := 0.0
var saved_pivot: Transform3D
var saved_camera: Transform3D
var saved_shape: Transform3D
var saved_physics: bool
var saved_look: bool
var saved_pitch: float
var saved_yaw: float
var saved_radius: float
var saved_height: float
var bird: Node3D
var tucked := false
var arm_rest: Dictionary = {}
var arm_mesh_rest: Dictionary = {}
var reflection_bird: Node3D

func _init(main: Node3D) -> void:
	m = main
	saved_pivot = m.player.camera_pivot.transform
	saved_camera = m.player.camera.transform
	saved_shape = m.player.collision_shape.transform
	saved_radius = m.player.collision_shape.shape.radius
	saved_height = m.player.collision_shape.shape.height
	saved_physics = m.player.is_physics_processing()
	saved_look = m.player.is_processing_unhandled_input()
	saved_pitch = m.player._pitch
	saved_yaw = m.player._yaw
	m.chewer.stop()
	m.hand_motions.cancel()
	m.player.velocity = Vector3.ZERO
	m.player.set_physics_process(false)
	m.player.set_process_unhandled_input(false)
	m.hands_rig.pose_hook = m.hand_motions
	if m.art_hookup != null:
		m.art_hookup.mut_hands.call("rig").pose_hook = m.hand_motions
	var toward: Vector3 = m.canary_hole_point() - m.player.global_position
	m.player.rotation.y = atan2(-toward.x, -toward.z)
	make_bird()

func progress() -> float:
	return clampf(elapsed / DURATION, 0.0, 1.0)

static func phase(u: float, a: float, b: float) -> float:
	return smoothstep(a, b, u)

func prone() -> float:
	var u := progress()
	return phase(u, 0.0, 0.18) * (1.0 - phase(u, 0.59, 0.75))

func step(delta: float) -> bool:
	elapsed += delta
	var u := progress()
	var down := prone()
	var feet_local: float = -m.player.config.stand_height * 0.5
	m.player.collision_shape.rotation.x = lerpf(saved_shape.basis.get_euler().x, -PI * 0.5, down)
	var radius := lerpf(saved_radius, 0.22, down)
	var height := lerpf(saved_height, m.player.config.stand_height, down)
	m.player.collision_shape.shape.radius = radius
	m.player.collision_shape.shape.height = height
	var vertical_extent := radius + (height * 0.5 - radius) * absf(cos(m.player.collision_shape.rotation.x))
	m.player.collision_shape.position = Vector3(0, feet_local + vertical_extent, 0.45 * down)
	m.player.camera_pivot.position = saved_pivot.origin.lerp(Vector3(0, feet_local + 0.24, -0.30), down)
	m.player.camera.position = saved_camera.origin * (1.0 - down)
	var eye: Vector3 = m.player.camera.global_position
	var to_hole: Vector3 = (m.canary_hole_point() - eye).normalized()
	var reach_pitch := asin(clampf(to_hole.y, -1.0, 1.0))
	var toward_briefs := phase(u, 0.58, 0.76) * (1.0 - phase(u, 0.90, 1.0))
	m.player.camera_pivot.rotation.x = lerpf(saved_pitch, reach_pitch, down)
	m.player.camera_pivot.rotation.x = lerpf(m.player.camera_pivot.rotation.x, -1.50, toward_briefs)
	m.player.camera.position = m.hand_motions._cam_rest_offset() * (1.0 - down)
	m.player.camera.rotation = saved_camera.basis.get_euler()
	if bird != null:
		bird.visible = u >= 0.51 and not tucked
		var wrist: Node3D = active_rig().get_node("HandRight/Wrist")
		bird.global_transform = wrist.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.04, -0.075))
		reflection_bird.visible = bird.visible
	if u >= 0.84 and not tucked:
		tucked = true
		m.take_canary()
		bird.visible = false
		reflection_bird.visible = false
	# Mirror detail updates are normally culled when the glass is offscreen.
	# This full-body action must still pose the actual body while prone.
	m.mirror_view._sync_body_posture()
	if u < 1.0:
		return false
	restore()
	return true

func active_rig() -> FDKHandsRig:
	if m.art_hookup != null and m.art_hookup._rig != null:
		return m.art_hookup._rig as FDKHandsRig
	return m.hands_rig

func hand_pose(rig: Node3D, side: float, original: Dictionary) -> Dictionary:
	var u := progress()
	var result := original.duplicate()
	var down := prone()
	var point: Vector3
	if side < 0:
		# Left palm stays on the floor beside the shoulder; it never fishes.
		point = m.player.to_global(Vector3(-0.24, -m.player.config.stand_height * 0.5 + 0.09, -0.12))
		result["pos"] = (original["pos"] as Vector3).lerp(rig.to_local(point), down)
		result["wrist_pitch"] = lerpf(float(original["wrist_pitch"]), -30.0, down)
		align_arm(rig, side, point, down)
		FPHandMotions._fingers(result, 0.08)
		return result
	var hole: Vector3 = m.canary_hole_point()
	var outside := hole + Vector3(0.12, 0.0, 0.0)
	var inside := hole - Vector3(0.04, 0.0, 0.0)
	var reach := phase(u, 0.17, 0.31)
	var search := phase(u, 0.30, 0.36) * (1.0 - phase(u, 0.48, 0.53))
	point = outside.lerp(inside, reach)
	point += Vector3(0.0, sin(elapsed * 10.0) * 0.018, cos(elapsed * 8.0) * 0.028) * search
	var held: Vector3 = m.player.camera.to_global(Vector3(0.14, -0.14, -0.36))
	point = point.lerp(held, phase(u, 0.51, 0.66))
	var briefs: Vector3 = m.art_hookup.belt.to_global(Vector3(-0.07, -0.07, -m.art_hookup.belt.wzf + 0.01))
	point = point.lerp(briefs, phase(u, 0.70, 0.83))
	var weight := phase(u, 0.15, 0.26) * (1.0 - phase(u, 0.87, 1.0))
	result["pos"] = (original["pos"] as Vector3).lerp(rig.to_local(point), weight)
	align_arm(rig, side, point, weight)
	result["wrist_pitch"] = lerpf(-8.0, 20.0, phase(u, 0.70, 0.83))
	result["wrist_roll"] = -8.0
	result["wrist_yaw"] = 0.0
	FPHandMotions._fingers(result, lerpf(0.1, 0.72, phase(u, 0.48, 0.53)) * (1.0 - phase(u, 0.83, 0.87)))
	return result

func align_arm(rig: Node3D, side: float, wrist: Vector3, weight: float) -> void:
	# The forearm's +Z end belongs at the shoulder, not behind the eye.
	# Rotate the existing arm rather than translating a camera-facing tube.
	var shoulder_y: float = 0.42 - (0.75 if m.player._is_crouching else 0.0)
	var shoulder: Vector3 = m.player.to_global(Vector3(0.23 * side, lerpf(shoulder_y, -0.62, prone()), lerpf(-0.06, -0.16, prone())))
	# The elbow stays beside and in front of the torso. A straight wrist-to-
	# shoulder tube would cut through the belly when reaching the left briefs.
	var elbow: Vector3 = m.player.to_global(Vector3(0.30 * side, lerpf(shoulder_y - 0.10, -0.68, prone()), lerpf(-0.32, -0.40, prone())))
	var direction := (wrist - elbow).normalized()
	var world_basis := Basis.looking_at(direction, Vector3.UP)
	var local_basis: Basis = rig.global_basis.inverse() * world_basis
	var root: Node3D = rig.get_hand_root("right" if side > 0.0 else "left")
	root.basis = Basis.IDENTITY.slerp(local_basis.orthonormalized(), weight)
	deform_arm(root, wrist, elbow, shoulder, weight)
	var hair: Node3D = root.get_node_or_null("ArmHair")
	if hair != null:
		if not arm_rest.has(hair): arm_rest[hair] = hair.transform
		var rest: Transform3D = arm_rest[hair]
		hair.position = rest.origin.lerp(root.global_basis.inverse() * (elbow - wrist), weight)
		hair.scale.z = rest.basis.get_scale().z * lerpf(1.0, wrist.distance_to(elbow) / 0.33, weight)

func deform_arm(root: Node3D, wrist: Vector3, elbow: Vector3, shoulder: Vector3, weight: float) -> void:
	var mesh: MeshInstance3D = root.get_node("Forearm")
	if not arm_rest.has(mesh):
		arm_rest[mesh] = mesh.transform
		arm_mesh_rest[mesh] = mesh.mesh
	var source: ArrayMesh = arm_mesh_rest[mesh]
	var rest: Transform3D = arm_rest[mesh]
	var posed := ArrayMesh.new()
	var inverse: Basis = root.global_basis.inverse()
	for surface in range(source.get_surface_count()):
		var arrays: Array = source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in range(vertices.size()):
			var v := vertices[i]
			var upper := v.z > 0.0
			var u := clampf(v.z / 0.32 if upper else (v.z + 0.33) / 0.33, 0.0, 1.0)
			var center := elbow.lerp(shoulder, u) if upper else wrist.lerp(elbow, u)
			var segment := shoulder - elbow if upper else elbow - wrist
			var basis := Basis.looking_at(-segment.normalized(), Vector3.UP)
			var source_y := -0.10 * u if upper else sin(u * PI) * 0.006
			var radial := Vector3(v.x, v.y - source_y, 0)
			var target: Vector3 = rest.affine_inverse() * (inverse * (center + basis * radial - wrist))
			vertices[i] = v.lerp(target, weight)
			if i < normals.size():
				var target_normal: Vector3 = rest.basis.inverse() * inverse * basis * normals[i]
				normals[i] = normals[i].lerp(target_normal, weight).normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		posed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.mesh = posed

func pose_reflection(body: Node3D) -> void:
	# Keep the reflection's original connected shoulder/elbow chain; solve
	# its two joints toward the same world-space wrists as the visible rig.
	for side in ["r", "l"]:
		var upper: Node3D = body._sub["upper_" + side]
		var forearm: Node3D = body._parts["right_hand" if side == "r" else "left_hand"]
		var hand: Node3D = body._sub["hand_" + side]
		var wrist: Node3D = active_rig().get_node("HandRight/Wrist" if side == "r" else "HandLeft/Wrist")
		var start := upper.global_position
		var to_wrist := wrist.global_position - start
		var first: Vector3 = (body._rest_pose[forearm] as Transform3D).origin
		var second: Vector3 = (body._rest_pose[hand] as Transform3D).origin
		var reach := clampf(to_wrist.length(), 0.02, first.length() + second.length() - 0.001)
		var axis := to_wrist.normalized()
		var bend := Vector3.UP - axis * axis.dot(Vector3.UP)
		if bend.length_squared() < 0.01: bend = Vector3.RIGHT
		var along := (first.length_squared() - second.length_squared() + reach * reach) / (2.0 * reach)
		var elbow := start + axis * along + bend.normalized() * sqrt(maxf(0.0, first.length_squared() - along * along))
		var upper_direction: Vector3 = upper.get_parent().global_basis.inverse() * (elbow - start)
		upper.basis = Basis(Quaternion(first.normalized(), upper_direction.normalized()))
		var fore_direction: Vector3 = upper.global_basis.inverse() * (start + axis * reach - forearm.global_position)
		forearm.basis = Basis(Quaternion(second.normalized(), fore_direction.normalized()))
	if is_instance_valid(reflection_bird):
		reflection_bird.global_transform = body._sub["hand_r"].global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0.02))

func make_bird() -> void:
	const K := preload("res://main/art/fp_art_kit.gd")
	bird = Node3D.new()
	bird.name = "CaughtCanary"
	m.add_child(bird)
	var st := K.begin()
	var yellow := Color(0.98, 0.84, 0.18)
	K.blob(st, Transform3D.IDENTITY, Vector3.ZERO, Vector3(0.027, 0.035, 0.025), 0.1, 3, yellow, Color(0.9, 0.72, 0.1))
	K.blob(st, Transform3D.IDENTITY, Vector3(0, 0.035, 0), Vector3(0.018, 0.019, 0.018), 0.1, 5, yellow, yellow)
	K.lathe(st, K.T(Vector3(0, 0.035, -0.018), Vector3(-90, 0, 0)), [Vector2(0.005, 0), Vector2(0, 0.015)], 4, [Color(0.95, 0.55, 0.2)])
	K.add_mesh(bird, "Bird", K.finish(st), K.mat("tex_skin_64.png", 0.1, true))
	m._tag_hands_layer(bird, FPMirrorReflection.HANDS_ROOM_LAYER)
	bird.visible = false
	reflection_bird = bird.duplicate()
	reflection_bird.name = "ReflectedCaughtCanary"
	m.mirror_view.body.add_child(reflection_bird)
	FPMirror.tag_layer(reflection_bird, FPMirrorReflection.MIRROR_BODY_LAYER)

func restore() -> void:
	for node in arm_mesh_rest:
		if is_instance_valid(node): node.mesh = arm_mesh_rest[node]
	for node in arm_rest:
		if is_instance_valid(node): node.transform = arm_rest[node]
	for side in ["right", "left"]:
		active_rig().get_hand_root(side).basis = Basis.IDENTITY
	m.player.collision_shape.transform = saved_shape
	m.player.collision_shape.shape.radius = saved_radius
	m.player.collision_shape.shape.height = saved_height
	m.player.camera_pivot.transform = saved_pivot
	m.player.camera.transform = saved_camera
	m.player._pitch = saved_pitch
	m.player._yaw = saved_yaw
	m.player.rotation.y = saved_yaw
	m.player.set_physics_process(saved_physics)
	m.player.set_process_unhandled_input(saved_look)
	if is_instance_valid(bird): bird.queue_free()
	if is_instance_valid(reflection_bird): reflection_bird.queue_free()
