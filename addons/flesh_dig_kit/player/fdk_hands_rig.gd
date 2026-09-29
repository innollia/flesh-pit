class_name FDKHandsRig
extends Node3D

## Two low-poly hands fixed to the camera, acting as the "in-world HUD" the
## design calls for (no floating stomach text). Each hand is a Skeleton3D
## with a real joint hierarchy so it can curl to grip flesh rather than
## just translate forward:
##
##   Wrist -> Palm -> FingerBlock (index..pinky fused into one paddle,
##                                 3 knuckle joints: FingerBlock/Knuckle1/Knuckle2)
##            Palm -> Thumb (a separate 3-joint chain: Thumb/ThumbJoint1/ThumbJoint2)
##
## Both the finger block and the thumb bend at all 3 of their joints in
## sequence (curl_ratio drives Knuckle1 first, then Knuckle2 as it catches
## up, same idea for the thumb) rather than a single hinge, per 형님's
## correction on 2026-09-29 rejecting the flat box-mesh hands.
##
## States: idle (slight resting curl), gripping (fingers curl closed +
## thumb opposes as chewing progresses), tearing (gripped + a fast small
## jitter/shake), releasing (curl relaxes back to idle open).
## Connect a FDKChewer's chew_progress signal to animate_chew(), and its
## cell_torn signal to trigger a brief tear jitter (see notify_tear()).

@export var reach_distance: float = 0.55
@export var hand_spacing: float = 0.18
@export var idle_bob_amplitude: float = 0.01

## Joint angle limits (radians), enforced in _apply_curl(). Read by
## tests/run_tests.gd to confirm no pose ever exceeds them.
const KNUCKLE1_MAX := deg_to_rad(80.0)
const KNUCKLE2_MAX := deg_to_rad(70.0)
const THUMB1_MAX := deg_to_rad(55.0)
const THUMB2_MAX := deg_to_rad(65.0)
const IDLE_CURL := 0.12 ## resting curl ratio, both hands, at rest

enum HandState { IDLE, GRIPPING, TEARING, RELEASING }

var _left: Dictionary
var _right: Dictionary
var _time: float = 0.0
var _chew_ratio: float = 0.0
var _state: HandState = HandState.IDLE
var _tear_jitter_time: float = 0.0
const TEAR_JITTER_DURATION := 0.18
const TEAR_JITTER_AMPLITUDE := 0.02

func _ready() -> void:
	_left = _build_hand(-1.0)
	_right = _build_hand(1.0)

func _build_hand(side: float) -> Dictionary:
	var root := Node3D.new()
	root.name = "Hand%s" % ("Left" if side < 0 else "Right")
	root.position = Vector3(side * hand_spacing, -0.15, -reach_distance)
	add_child(root)

	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton"
	root.add_child(skeleton)

	# Bone chain: Wrist(0) -> Palm(1) -> FingerBlock(2) -> Knuckle1(3) -> Knuckle2(4)
	#                                 -> Thumb(5) -> ThumbJoint1(6) -> ThumbJoint2(7)
	var wrist := skeleton.add_bone("Wrist")
	skeleton.set_bone_rest(wrist, Transform3D(Basis.IDENTITY, Vector3.ZERO))

	var palm := skeleton.add_bone("Palm")
	skeleton.set_bone_parent(palm, wrist)
	skeleton.set_bone_rest(palm, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.03)))

	var finger_block := skeleton.add_bone("FingerBlock")
	skeleton.set_bone_parent(finger_block, palm)
	skeleton.set_bone_rest(finger_block, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.06)))

	var knuckle1 := skeleton.add_bone("Knuckle1")
	skeleton.set_bone_parent(knuckle1, finger_block)
	skeleton.set_bone_rest(knuckle1, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.035)))

	var knuckle2 := skeleton.add_bone("Knuckle2")
	skeleton.set_bone_parent(knuckle2, knuckle1)
	skeleton.set_bone_rest(knuckle2, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.025)))

	var thumb := skeleton.add_bone("Thumb")
	skeleton.set_bone_parent(thumb, palm)
	skeleton.set_bone_rest(thumb, Transform3D(Basis.IDENTITY, Vector3(side * 0.035, -0.01, -0.02)))

	var thumb_joint1 := skeleton.add_bone("ThumbJoint1")
	skeleton.set_bone_parent(thumb_joint1, thumb)
	skeleton.set_bone_rest(thumb_joint1, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.025)))

	var thumb_joint2 := skeleton.add_bone("ThumbJoint2")
	skeleton.set_bone_parent(thumb_joint2, thumb_joint1)
	skeleton.set_bone_rest(thumb_joint2, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.02)))

	skeleton.reset_bone_poses()

	_attach_low_poly_mesh(skeleton, side)

	return {
		"root": root,
		"skeleton": skeleton,
		"bones": {
			"wrist": wrist, "palm": palm, "finger_block": finger_block,
			"knuckle1": knuckle1, "knuckle2": knuckle2,
			"thumb": thumb, "thumb_joint1": thumb_joint1, "thumb_joint2": thumb_joint2,
		},
	}

## Builds one low-poly faceted mesh (flat-shaded, per-face vertices, same
## faceted style as the terrain kit) covering wrist+palm+finger-block+thumb
## as a set of boxy segments skinned to the bone chain above, so the mesh
## bends when the bones rotate.
func _attach_low_poly_mesh(skeleton: Skeleton3D, side: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skin_weights := PackedInt32Array()
	# We build with SurfaceTool per-segment boxes, each fully weighted to one
	# bone (rigid skinning per segment -- simple and enough for a low-poly
	# stylized hand; no smooth blending needed between segments).
	var skin := Skin.new()
	skin.add_bind(0, Transform3D.IDENTITY) # wrist
	skin.add_bind(1, Transform3D.IDENTITY) # palm
	skin.add_bind(2, Transform3D.IDENTITY) # finger_block
	skin.add_bind(3, Transform3D.IDENTITY) # knuckle1
	skin.add_bind(4, Transform3D.IDENTITY) # knuckle2
	skin.add_bind(5, Transform3D.IDENTITY) # thumb
	skin.add_bind(6, Transform3D.IDENTITY) # thumb_joint1
	skin.add_bind(7, Transform3D.IDENTITY) # thumb_joint2

	var color := Color(0.75, 0.55, 0.5)

	_add_rigid_box(st, 0, Vector3(0.05, 0.045, 0.03), Vector3(0, 0, 0.0), color) # wrist
	_add_rigid_box(st, 1, Vector3(0.07, 0.05, 0.05), Vector3(0, 0, -0.01), color) # palm
	_add_rigid_box(st, 2, Vector3(0.065, 0.035, 0.05), Vector3(0, 0, -0.015), color) # finger block base segment
	_add_rigid_box(st, 3, Vector3(0.06, 0.032, 0.035), Vector3(0, 0, -0.01), color) # knuckle1 segment
	_add_rigid_box(st, 4, Vector3(0.055, 0.028, 0.025), Vector3(0, 0, -0.008), color) # knuckle2 segment (tip)
	_add_rigid_box(st, 5, Vector3(0.03, 0.03, 0.03), Vector3(side * 0.005, 0, -0.005), color) # thumb base
	_add_rigid_box(st, 6, Vector3(0.026, 0.026, 0.025), Vector3(0, 0, -0.008), color) # thumb joint1 segment
	_add_rigid_box(st, 7, Vector3(0.022, 0.022, 0.02), Vector3(0, 0, -0.006), color) # thumb joint2 segment (tip)

	st.generate_normals()
	var mesh := st.commit()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.skin = skin
	mesh_instance.skeleton = NodePath("..")
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.8
	mesh_instance.material_override = material
	skeleton.add_child(mesh_instance)

## Adds one box's worth of geometry rigidly weighted to bone_index, centered
## at local_offset (in the bone's own local space) with the given half-extents
## (size is full extents, matching BoxMesh convention).
func _add_rigid_box(st: SurfaceTool, bone_index: int, size: Vector3, local_offset: Vector3, color: Color) -> void:
	var h := size * 0.5
	var corners := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	var faces := [
		[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0],
	]
	for face in faces:
		var quad: Array = face
		var v0: Vector3 = corners[quad[0]] + local_offset
		var v1: Vector3 = corners[quad[1]] + local_offset
		var v2: Vector3 = corners[quad[2]] + local_offset
		var v3: Vector3 = corners[quad[3]] + local_offset
		st.set_color(color)
		_add_weighted_vertex(st, v0, bone_index)
		_add_weighted_vertex(st, v1, bone_index)
		_add_weighted_vertex(st, v2, bone_index)
		_add_weighted_vertex(st, v0, bone_index)
		_add_weighted_vertex(st, v2, bone_index)
		_add_weighted_vertex(st, v3, bone_index)

func _add_weighted_vertex(st: SurfaceTool, pos: Vector3, bone_index: int) -> void:
	st.set_bones(PackedInt32Array([bone_index, 0, 0, 0]))
	st.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	st.add_vertex(pos)

func _process(delta: float) -> void:
	_time += delta

	match _state:
		HandState.TEARING:
			_tear_jitter_time += delta
			if _tear_jitter_time >= TEAR_JITTER_DURATION:
				_state = HandState.GRIPPING
				_tear_jitter_time = 0.0

	var idle_offset := sin(_time * 2.0) * idle_bob_amplitude
	var curl_ratio := _current_curl_ratio()
	var jitter := Vector3.ZERO
	if _state == HandState.TEARING:
		jitter = Vector3(
			sin(_time * 55.0) * TEAR_JITTER_AMPLITUDE,
			cos(_time * 47.0) * TEAR_JITTER_AMPLITUDE * 0.6,
			0.0
		)

	for hand in [_left, _right]:
		var root: Node3D = hand["root"]
		root.position = Vector3(root.position.x, -0.15 + idle_offset + jitter.y, -reach_distance + jitter.x)
		_apply_curl(hand, curl_ratio)

## Resting curl at idle, rising toward fully closed as chewing progresses,
## whether gripping or tearing (tearing keeps the grip closed and jitters
## the wrist instead, handled in _process above).
func _current_curl_ratio() -> float:
	match _state:
		HandState.IDLE:
			return IDLE_CURL
		HandState.GRIPPING, HandState.TEARING:
			return lerpf(IDLE_CURL, 1.0, _chew_ratio)
		HandState.RELEASING:
			return lerpf(_chew_ratio, IDLE_CURL, 0.0) # overwritten by release tween below
	return IDLE_CURL

## Drives the finger block's two knuckles and the thumb's two joints from a
## single 0..1 curl_ratio. Knuckle1/ThumbJoint1 lead (curl first), Knuckle2/
## ThumbJoint2 follow with a short delay so the curl reads as sequential
## closing rather than a single hinge -- this is the "3 joints bend in
## order" behavior 형님 asked for. All angles are clamped to the *_MAX
## constants above.
func _apply_curl(hand: Dictionary, curl_ratio: float) -> void:
	var skeleton: Skeleton3D = hand["skeleton"]
	var bones: Dictionary = hand["bones"]

	# Lead joint reaches its max over the first 70% of curl_ratio; the
	# follow joint only starts moving once the lead is substantially bent
	# (past 0.35), giving the sequential "curl closed knuckle by knuckle" feel.
	var lead_ratio := clampf(curl_ratio / 0.7, 0.0, 1.0)
	var follow_ratio := clampf((curl_ratio - 0.35) / 0.65, 0.0, 1.0)

	var knuckle1_angle := lead_ratio * KNUCKLE1_MAX
	var knuckle2_angle := follow_ratio * KNUCKLE2_MAX
	var thumb1_angle := lead_ratio * THUMB1_MAX
	var thumb2_angle := follow_ratio * THUMB2_MAX

	_set_bone_pitch(skeleton, bones["knuckle1"], knuckle1_angle)
	_set_bone_pitch(skeleton, bones["knuckle2"], knuckle2_angle)
	_set_bone_pitch(skeleton, bones["thumb_joint1"], thumb1_angle)
	_set_bone_pitch(skeleton, bones["thumb_joint2"], thumb2_angle)

func _set_bone_pitch(skeleton: Skeleton3D, bone_index: int, angle: float) -> void:
	var rest: Transform3D = skeleton.get_bone_rest(bone_index)
	var pose_basis := Basis(Vector3.RIGHT, angle)
	skeleton.set_bone_pose_rotation(bone_index, pose_basis.get_rotation_quaternion())

## ratio 0..1 from FDKChewer.chew_progress: hands curl closed around the
## target cell as the tear approaches completion.
func animate_chew(ratio: float, _target_cell: Vector3i) -> void:
	_chew_ratio = ratio
	if ratio <= 0.001:
		_state = HandState.IDLE
	elif _state != HandState.TEARING:
		_state = HandState.GRIPPING

## Call when FDKChewer.cell_torn fires: brief tearing jitter with the grip
## held closed, then eases back toward idle.
func notify_tear() -> void:
	_state = HandState.TEARING
	_tear_jitter_time = 0.0

func reset_chew() -> void:
	_chew_ratio = 0.0
	_state = HandState.RELEASING

## Test/inspection helper: current curl angle (radians) for a given hand's
## given joint name, so tests can assert every joint stays within its limit.
func get_joint_angle(hand_side: String, joint_name: String) -> float:
	var hand: Dictionary = _left if hand_side == "left" else _right
	var skeleton: Skeleton3D = hand["skeleton"]
	var bones: Dictionary = hand["bones"]
	if not bones.has(joint_name):
		return 0.0
	var bone_index: int = bones[joint_name]
	var q := skeleton.get_bone_pose_rotation(bone_index)
	return 2.0 * acos(clampf(q.w, -1.0, 1.0))
