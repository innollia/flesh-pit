class_name FPCanaryPull
extends RefCounted

## Canary retrieval (user 2026-11-08): prone at the hole, the LEFT hand goes
## deep in. The hole holds a crowd of canaries: they swarm and wrap the hand,
## it comes out covered, one hard shake throws them back in, the hand goes in
## again, stirs, closes on one bird and pulls out holding it, then tucks it
## into the briefs. The right palm braces on the floor. Possession begins
## only after tucking; a move/action press before that cancels it.
const K := preload("res://main/art/fp_art_kit.gd")
const DURATION := 7.2
const SWARM := 20
## Phase marks (progress 0..1).
const P_REACH := Vector2(0.13, 0.22)
const P_OUT := Vector2(0.30, 0.38)
const P_SHAKE := Vector2(0.46, 0.54)
const SHAKE_RELEASE := 0.49
const P_BACK_IN := Vector2(0.54, 0.60)
const P_STIR := Vector2(0.58, 0.72)
const P_GRAB := Vector2(0.70, 0.74)
const P_PULL := Vector2(0.74, 0.82)
const P_TUCK := Vector2(0.82, 0.89)
const TUCK_AT := 0.89
const CANCEL_TIME := 0.4
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
## The crowd in the hole: SWARM birds, each with a perch on the left hand.
var swarm: Array[Node3D] = []
var _perch: Array[Transform3D] = []
var _home: Array[Vector3] = []
var _land_at: Array[float] = []
var _fly_from: Array[Vector3] = []
var _fly_out: Array[Vector3] = []
var cancelled := false
var _fade := 1.0

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
	make_swarm()

func progress() -> float:
	return clampf(elapsed / DURATION, 0.0, 1.0)

static func phase(u: float, a: float, b: float) -> float:
	return smoothstep(a, b, u)

static func span(u: float, p: Vector2) -> float:
	return smoothstep(p.x, p.y, u)

func prone() -> float:
	var u := progress()
	return phase(u, 0.0, 0.13) * (1.0 - phase(u, 0.87, 0.97)) * _fade

## "reach" "swarm" "shake" "stir" "pull" "tuck" "stand", or "cancel".
func stage() -> String:
	var u := progress()
	if cancelled: return "cancel"
	if u < P_REACH.y: return "reach"
	if u < P_SHAKE.x: return "swarm"
	if u < P_BACK_IN.y: return "shake"
	if u < P_PULL.x: return "stir"
	if u < P_TUCK.x: return "pull"
	if not tucked: return "tuck"
	return "stand"

## Birds sitting on the left hand right now.
func perched_count() -> int:
	var n := 0
	var u := progress()
	for i in swarm.size():
		if swarm[i].visible and u >= _land_at[i] + 0.03 and u < SHAKE_RELEASE:
			n += 1
	return n

## Birds flying back off the hand after the shake.
func flying_count() -> int:
	var n := 0
	var u := progress()
	for i in swarm.size():
		if swarm[i].visible and u >= SHAKE_RELEASE:
			n += 1
	return n

func _check_cancel() -> void:
	if cancelled or tucked or elapsed < 0.15:
		return
	for a in FPHandMotions.CANCEL_ACTIONS:
		if InputMap.has_action(a) and Input.is_action_just_pressed(a):
			cancelled = true
			return

func step(delta: float) -> bool:
	_check_cancel()
	if cancelled:
		_fade = maxf(0.0, _fade - delta / CANCEL_TIME)
	else:
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
	var toward_briefs := phase(u, P_TUCK.x - 0.02, P_TUCK.y - 0.01) * (1.0 - phase(u, 0.92, 1.0)) * _fade
	m.player.camera_pivot.rotation.x = lerpf(saved_pitch, reach_pitch, down)
	m.player.camera_pivot.rotation.x = lerpf(m.player.camera_pivot.rotation.x, -1.50, toward_briefs)
	m.player.camera.position = m.hand_motions._cam_rest_offset() * (1.0 - down)
	m.player.camera.rotation = saved_camera.basis.get_euler()
	var wrist: Node3D = active_rig().get_node("HandLeft/Wrist")
	if bird != null:
		bird.visible = u >= P_GRAB.y - 0.01 and not tucked and not cancelled
		bird.global_transform = held_transform(wrist)
		_flap(bird, 0.6, 0)
		reflection_bird.visible = bird.visible
	_step_swarm(u, wrist)
	if u >= TUCK_AT and not tucked and not cancelled:
		tucked = true
		m.take_canary()
		bird.visible = false
		reflection_bird.visible = false
	# Mirror detail updates are normally culled when the glass is offscreen.
	# This full-body action must still pose the actual body while prone.
	m.mirror_view._sync_body_posture()
	if cancelled and _fade > 0.0:
		return false
	if not cancelled and u < 1.0:
		return false
	restore()
	return true

## A frame on the left wrist whose +Y faces the eye and +Z runs up the
## forearm: the crowd perches on the side the player sees.
func arm_frame(wrist: Node3D) -> Transform3D:
	var along := wrist.global_basis.z.normalized()
	var eye: Vector3 = m.player.camera.global_position
	var toward := eye - wrist.global_position
	toward = (toward - along * toward.dot(along))
	if toward.length_squared() < 1e-6:
		toward = Vector3.UP
	var y := toward.normalized()
	var x := y.cross(along).normalized()
	return Transform3D(Basis(x, y, along), wrist.global_position)

## The caught bird in the closed left fist: body in the fist, head and back
## showing on the side toward the eye.
func held_transform(wrist: Node3D) -> Transform3D:
	var f := arm_frame(wrist)
	var fist: Vector3 = wrist.global_transform * Vector3(0, -0.03, -0.085)
	var up := (f.basis.y + Vector3.UP * 0.6).normalized()
	return Transform3D(Basis.looking_at(f.basis.x, up), fist + f.basis.y * 0.06)

func active_rig() -> FDKHandsRig:
	if m.art_hookup != null and m.art_hookup._rig != null:
		return m.art_hookup._rig as FDKHandsRig
	return m.hands_rig

## Where the left wrist goes at progress u (world space).
func reach_point(u: float) -> Vector3:
	var hole: Vector3 = m.canary_hole_point()
	var into := Vector3(-1, 0, 0) # the hole runs into the -X wall
	var outside := hole - into * 0.16
	var deep := hole + into * 0.20
	var covered := hole - into * 0.15 + Vector3(0, 0.05, 0)
	var stir_at := hole + into * 0.09
	var t := elapsed
	var point := outside.lerp(deep, span(u, P_REACH))
	# deep in: the hand wriggles while the crowd closes on it
	point += Vector3(0, sin(t * 13.0) * 0.012, cos(t * 9.0) * 0.016) * span(u, Vector2(P_REACH.y, 0.25)) * (1.0 - span(u, P_OUT))
	point = point.lerp(covered, span(u, P_OUT))
	# covered: it trembles under the weight of the birds
	point += Vector3(0, sin(t * 31.0) * 0.006, sin(t * 23.0) * 0.008) * span(u, P_OUT) * (1.0 - span(u, P_SHAKE))
	# one hard shake: up and back, one snap across and back
	var s := clampf((u - P_SHAKE.x) / (P_SHAKE.y - P_SHAKE.x), 0.0, 1.0)
	var shake_w := sin(s * PI)
	point += Vector3(0.05, 0.04, 0.0) * shake_w + Vector3(0, 0, 0.11) * sin(s * TAU) * shake_w
	point = point.lerp(stir_at, span(u, P_BACK_IN))
	# stirring: circles inside the hole, two and a half turns
	var stir_w := span(u, Vector2(P_BACK_IN.y - 0.02, P_STIR.x + 0.03)) * (1.0 - span(u, P_GRAB))
	var a := (u - P_STIR.x) / (P_STIR.y - P_STIR.x) * TAU * 2.5
	point += Vector3(0, sin(a) * 0.035, cos(a) * 0.04) * stir_w
	var held: Vector3 = m.player.camera.to_global(Vector3(-0.07, -0.05, -0.30))
	point = point.lerp(held, span(u, P_PULL))
	var briefs: Vector3 = m.art_hookup.belt.to_global(Vector3(-0.07, -0.07, -m.art_hookup.belt.wzf + 0.01))
	point = point.lerp(briefs, span(u, P_TUCK))
	# lying on the tiles, the fist never sinks into them
	point.y = maxf(point.y, m.player.get_feet_position().y + 0.08)
	return point

func hand_pose(rig: Node3D, side: float, original: Dictionary) -> Dictionary:
	var u := progress()
	var result := original.duplicate()
	var down := prone()
	var point: Vector3
	if side > 0:
		# The right palm stays on the floor beside the shoulder; it never fishes.
		point = m.player.to_global(Vector3(0.24, -m.player.config.stand_height * 0.5 + 0.09, -0.12))
		result["pos"] = (original["pos"] as Vector3).lerp(rig.to_local(point), down)
		result["wrist_pitch"] = lerpf(float(original["wrist_pitch"]), -30.0, down)
		align_arm(rig, side, point, down)
		FPHandMotions._fingers(result, 0.08)
		return result
	point = reach_point(u)
	var weight := phase(u, 0.11, 0.20) * (1.0 - phase(u, 0.88, 0.98)) * _fade
	result["pos"] = (original["pos"] as Vector3).lerp(rig.to_local(point), weight)
	align_arm(rig, side, point, weight)
	var s := clampf((u - P_SHAKE.x) / (P_SHAKE.y - P_SHAKE.x), 0.0, 1.0)
	result["wrist_pitch"] = lerpf(-8.0, 20.0, span(u, P_TUCK)) + 35.0 * sin(s * TAU) * sin(s * PI)
	result["wrist_roll"] = 8.0 + 40.0 * sin(s * TAU * 1.5) * sin(s * PI)
	result["wrist_yaw"] = 0.0
	# spread under the birds, flung open in the shake, closed on one bird
	var curl := lerpf(0.15, 0.35, span(u, P_OUT)) * (1.0 - span(u, P_SHAKE))
	curl += 0.1 * span(u, P_BACK_IN) * (1.0 - span(u, P_GRAB))
	curl = lerpf(curl, 0.72, span(u, P_GRAB)) * (1.0 - phase(u, TUCK_AT - 0.02, TUCK_AT + 0.02))
	FPHandMotions._fingers(result, curl)
	return result

# --- the crowd ------------------------------------------------------------------

func make_swarm() -> void:
	var hole: Vector3 = m.canary_hole_point()
	for i in SWARM:
		var b := _bird_node("SwarmCanary%d" % i, 0.75 + 0.25 * K.h(i, 3))
		b.visible = false
		m.add_child(b)
		m._tag_hands_layer(b, FPMirrorReflection.HANDS_ROOM_LAYER)
		swarm.append(b)
		# perch on the hand, wrist and forearm (arm_frame: -Z to the fingers,
		# +Y toward the eye), over the half of the arm the player sees
		var along := lerpf(-0.16, 0.24, (float(i) + 0.5 * K.h(i, 5)) / float(SWARM))
		var ang := (fmod(float(i) * 0.618034, 1.0) * 2.0 - 1.0) * 1.75
		var r := 0.05 + 0.012 * K.h(i, 11) + maxf(0.0, along) * 0.11
		var radial := Vector3(sin(ang), cos(ang), 0.0)
		var facing := Vector3(0, 0, -1).rotated(radial, (K.h(i, 13) - 0.5) * 2.4)
		facing = (facing - radial * facing.dot(radial)).normalized()
		_perch.append(Transform3D(Basis.looking_at(facing, radial), radial * r + Vector3(0, 0, along)))
		_home.append(hole + Vector3(-0.07 - 0.08 * K.h(i, 17), (K.h(i, 19) - 0.5) * 0.08, (K.h(i, 23) - 0.5) * 0.10))
		_land_at.append(lerpf(0.23, 0.37, K.h(i, 29)))
		_fly_from.append(Vector3.ZERO)
		_fly_out.append(Vector3.UP)

func _step_swarm(u: float, wrist: Node3D) -> void:
	for i in swarm.size():
		var b := swarm[i]
		if cancelled:
			b.visible = false
			continue
		var la: float = _land_at[i]
		var perch: Transform3D = arm_frame(wrist) * _perch[i]
		perch.basis = perch.basis.orthonormalized()
		if u < la:
			b.visible = false
			continue
		b.visible = true
		if u < la + 0.03:
			# out of the dark onto the hand
			var k := smoothstep(0.0, 1.0, (u - la) / 0.03)
			var pos: Vector3 = _home[i].lerp(perch.origin, k) + Vector3(0.03, 0.03, 0) * sin(k * PI)
			b.global_transform = Transform3D(perch.basis, pos)
			_flap(b, 1.0, i)
		elif u < SHAKE_RELEASE:
			# clinging: shuffles a little, wings never still
			var j := Vector3(sin(elapsed * 17.0 + i), sin(elapsed * 13.0 + i * 2.0), 0) * 0.004
			b.global_transform = Transform3D(perch.basis.rotated(perch.basis.y, sin(elapsed * 5.0 + i) * 0.4), perch.origin + perch.basis * j)
			_flap(b, 0.45, i)
			_fly_from[i] = b.global_position
			_fly_out[i] = perch.basis.y
		else:
			# flung off: a short arc out, then back into the hole
			var dur := 0.07 + 0.04 * K.h(i, 31)
			var k := (u - SHAKE_RELEASE) / dur
			if k >= 1.0:
				b.visible = false
				continue
			var p0: Vector3 = _fly_from[i]
			var p1: Vector3 = p0 + _fly_out[i] * 0.16 + Vector3(0.04, 0.07, 0)
			var p2: Vector3 = _home[i]
			var pos := p0.lerp(p1, k).lerp(p1.lerp(p2, k), k)
			var vel := (p1 - p0).lerp(p2 - p1, k)
			if vel.length_squared() > 1e-6:
				b.global_transform = Transform3D(Basis.looking_at(vel.normalized(), Vector3.UP if absf(vel.normalized().y) < 0.95 else Vector3.RIGHT), pos)
			else:
				b.global_position = pos
			_flap(b, 1.0, i)

func _flap(b: Node3D, amount: float, seed: int) -> void:
	var a := (0.25 + 0.9 * amount * (0.5 + 0.5 * sin(elapsed * 46.0 + seed * 1.7)))
	var wl: Node3D = b.get_node_or_null("WingL")
	var wr: Node3D = b.get_node_or_null("WingR")
	if wl != null: wl.rotation.z = a
	if wr != null: wr.rotation.z = -a

## A low-poly canary: body, head, beak and two wings that flap.
func _bird_node(node_name: String, size: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	var yellow := Color(1.0, 0.93, 0.32)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var st := K.begin()
	K.blob(st, Transform3D.IDENTITY, Vector3.ZERO, Vector3(0.027, 0.025, 0.035) * size, 0.1, 3, yellow, Color(1.0, 0.84, 0.2))
	K.blob(st, Transform3D.IDENTITY, Vector3(0, 0.018, -0.03) * size, Vector3(0.018, 0.018, 0.018) * size, 0.1, 5, yellow, yellow)
	K.lathe(st, K.T(Vector3(0, 0.018, -0.046) * size, Vector3(-90, 0, 0)), [Vector2(0.006 * size, 0), Vector2(0, 0.014 * size)], 4, [Color(0.95, 0.55, 0.2)])
	# tail
	K.tri(st, Transform3D.IDENTITY, Vector3(-0.012, 0.004, 0.03) * size, Vector3(0.012, 0.004, 0.03) * size, Vector3(0, 0.012, 0.065) * size, Vector3.UP, Color(0.85, 0.68, 0.1))
	K.tri(st, Transform3D.IDENTITY, Vector3(0.012, 0.004, 0.03) * size, Vector3(-0.012, 0.004, 0.03) * size, Vector3(0, 0.012, 0.065) * size, Vector3.DOWN, Color(0.85, 0.68, 0.1))
	# eyes
	K.blob(st, Transform3D.IDENTITY, Vector3(0.013, 0.024, -0.036) * size, Vector3.ONE * 0.004 * size, 0.0, 7, Color(0.03, 0.02, 0.02), Color(0.03, 0.02, 0.02))
	K.blob(st, Transform3D.IDENTITY, Vector3(-0.013, 0.024, -0.036) * size, Vector3.ONE * 0.004 * size, 0.0, 9, Color(0.03, 0.02, 0.02), Color(0.03, 0.02, 0.02))
	K.add_mesh(root, "Bird", K.finish(st), mat)
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "WingL" if side < 0.0 else "WingR"
		pivot.position = Vector3(0.022 * side, 0.01, -0.005) * size
		root.add_child(pivot)
		var ws := K.begin()
		var c := Color(0.97, 0.86, 0.25)
		var a := Vector3(0, 0, -0.018) * size
		var bpt := Vector3(0.042 * side, 0.0, 0.0) * size
		var cpt := Vector3(0.03 * side, 0.0, 0.028) * size
		var d := Vector3(0, 0, 0.022) * size
		K.quad(ws, Transform3D.IDENTITY, a, bpt, cpt, d, Vector3.UP, c)
		K.quad(ws, Transform3D.IDENTITY, d, cpt, bpt, a, Vector3.DOWN, c.darkened(0.15))
		K.add_mesh(pivot, "Wing", K.finish(ws), mat)
	return root

func make_bird() -> void:
	bird = _bird_node("CaughtCanary")
	m.add_child(bird)
	m._tag_hands_layer(bird, FPMirrorReflection.HANDS_ROOM_LAYER)
	bird.visible = false
	reflection_bird = bird.duplicate()
	reflection_bird.name = "ReflectedCaughtCanary"
	m.mirror_view.body.add_child(reflection_bird)
	FPMirror.tag_layer(reflection_bird, FPMirrorReflection.MIRROR_BODY_LAYER)

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
		reflection_bird.global_transform = body._sub["hand_l"].global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0.02))

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
	for b in swarm:
		if is_instance_valid(b): b.queue_free()
	swarm.clear()
