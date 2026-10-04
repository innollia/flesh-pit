class_name FPMirrorReflection
extends Node

## The real restroom mirror (docs/spec/03-restroom.md 8). It only reflects:
## the glass shows the room and the player's own body, rendered by a
## reflection camera that mirrors the eye across the glass plane (off-axis
## frustum clipped exactly at the glass, low-res nearest filtered for the
## PS1 look). The body (FPMirrorBody) always stands in the world under the
## player on MIRROR_BODY_LAYER, which the eye camera culls, so only the
## mirror sees it; the first-person hands and waist are culled from the
## reflection instead. Mutations are bought on the forearm hologram
## (FPMirror), and the body here picks them up at once.

## Render layer of the world body (only the reflection camera sees it).
const MIRROR_BODY_LAYER := 1 << 12
## Hands inside the restroom (was ROOM_VISUAL_LAYER): eye camera only.
const HANDS_ROOM_LAYER := 1 << 13
## Glass in the mirror art's local space (fp_mirror.gd art: w 0.3, hh 0.38).
const GLASS_W := 0.4
const GLASS_HH := 0.6
const GLASS_CY := 1.78
const GLASS_Z := 0.016
const VP_SIZE := Vector2i(128, 192)

const REFLECT_SHADER := "shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : source_color, filter_nearest;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	vec3 c = texture(tex, UV).rgb;
	float streak = smoothstep(0.93, 1.0, sin((lp.x * 1.6 + lp.y) * 22.0) * 0.5 + 0.5) * 0.08;
	ALBEDO = mix(c, vec3(0.9, 0.95, 1.0), streak);
}"

var _owns_body := true
var prog: FPProgression
var body: FPMirrorBody
var cam: Camera3D ## reflection camera
var art: Node3D
var player: Node3D
var eye: Camera3D
var _vp: SubViewport
var _quad: MeshInstance3D
var _sig := ""
## 1인칭 소지 상태(main.has_canary). prog에는 없는 값이라 sync()가 매 프레임
## 전달한다(형님 2026-09-30: 거울 반영이 시작부터 카나리아를 붙여 보여줬음).
var _has_canary := false
var _blood: ShaderMaterial
var _held := {}
var _mouth_flesh: MeshInstance3D
var _carry_flesh: MeshInstance3D

func attach(mirror_art: Node3D, p: Node3D, eye_cam: Camera3D, progression: FPProgression, shared_body: FPMirrorBody = null) -> void:
	art = mirror_art
	player = p
	eye = eye_cam
	prog = progression
	eye.cull_mask &= ~MIRROR_BODY_LAYER
	_owns_body = shared_body == null
	if _owns_body:
		body = FPMirrorBody.new()
		body.name = "MirrorBody"
		player.add_child(body)
		body.build()
		_build_live_details()
		# the body faces +Z with the right hand at +X; flip Z so it faces the
		# player's forward (-Z) and the right hand stays on the player's right
		var feet := -0.9
		if player.get("config") != null:
			feet = -float(player.config.stand_height) * 0.5
		body.transform = Transform3D(Basis().scaled(Vector3(1, 1, -1)), Vector3(0, feet, 0))
		# the room light hangs overhead and the player lamp skips this layer, so
		# the body read dark brown in the glass (mut6): a soft front fill, only
		# for the body, where the player lamp would be
		var fill := OmniLight3D.new()
		fill.name = "MirrorBodyFill"
		fill.light_cull_mask = MIRROR_BODY_LAYER
		fill.light_color = Color(1.0, 0.9, 0.84)
		fill.light_energy = 1.1
		fill.omni_range = 2.5
		fill.shadow_enabled = false
		fill.position = Vector3(0, 1.45, 0.7) # body space: in front of the chest
		body.add_child(fill)
	else:
		body = shared_body
	_vp = SubViewport.new()
	_vp.name = "ReflectionView"
	_vp.size = VP_SIZE
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_vp)
	cam = Camera3D.new()
	cam.name = "ReflectionCamera"
	cam.projection = Camera3D.PROJECTION_FRUSTUM
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = GLASS_HH * 2.0
	cam.far = 40.0
	cam.cull_mask = 0xFFFFF & ~(1 << 11) & ~HANDS_ROOM_LAYER & ~FPMirror.HOLO_LAYER
	_vp.add_child(cam)
	cam.current = true
	_build_quad()
	refresh()
	sync()

func _build_quad() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z := GLASS_Z - 0.001
	var pts := [Vector3(-GLASS_W, GLASS_CY - GLASS_HH, z), Vector3(GLASS_W, GLASS_CY - GLASS_HH, z), Vector3(GLASS_W, GLASS_CY + GLASS_HH, z), Vector3(-GLASS_W, GLASS_CY + GLASS_HH, z)]
	for i in [0, 1, 2, 0, 2, 3]:
		var v: Vector3 = pts[i]
		st.set_normal(Vector3.BACK)
		# camera X runs along the glass's -X, so u is mirrored here
		st.set_uv(Vector2(0.5 - v.x / (2.0 * GLASS_W), 0.5 - (v.y - GLASS_CY) / (2.0 * GLASS_HH)))
		st.add_vertex(v)
	_quad = MeshInstance3D.new()
	_quad.name = "Reflection"
	_quad.mesh = st.commit()
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = REFLECT_SHADER
	mat.shader = sh
	mat.set_shader_parameter("tex", _vp.get_texture())
	_quad.material_override = mat
	art.add_child(_quad)
	_quad.layers = FPRestroom.ROOM_VISUAL_LAYER

## Per frame (main): move the reflection camera, show the body only while
## standing in the room, and pick up mutation changes.
func sync(body_ok: bool = true, has_canary: bool = false) -> void:
	if art == null or cam == null:
		return
	_has_canary = has_canary
	body.visible = body_ok
	var xf := art.global_transform.orthonormalized()
	var g := xf * Vector3(0, GLASS_CY, GLASS_Z)
	var visible_in_eye := body_ok and eye.is_position_in_frustum(g) and xf.basis.z.dot(eye.global_position - g) >= 0.03
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible_in_eye else SubViewport.UPDATE_DISABLED
	_quad.visible = visible_in_eye
	# Both leaves show the same body. Updating equipment cannot depend on
	# the first leaf being on screen while only the second leaf is visible.
	var details_visible := visible_in_eye
	if _owns_body and body_ok:
		var other = player.get_parent().get("mirror_view_right")
		if other != null and other.art != null:
			details_visible = details_visible or eye.is_position_in_frustum(other.art.to_global(Vector3(0, GLASS_CY, GLASS_Z)))
	if _owns_body and details_visible:
		if _signature() != _sig:
			refresh()
		_sync_live_details()
		_sync_body_posture()
	if not visible_in_eye:
		return
	var n := xf.basis.z
	var up := xf.basis.y
	var e := eye.global_position
	var d := n.dot(e - g)
	if d < 0.03:
		return
	var e2 := e - n * (2.0 * d)
	var zc := -n
	var xc := up.cross(zc)
	cam.global_transform = Transform3D(Basis(xc, up, zc), e2)
	var rel := g - e2
	cam.near = d
	cam.frustum_offset = Vector2(rel.dot(xc), rel.dot(up))

func _signature() -> String:
	if prog == null:
		return ""
	return "%s|%d|%s|%s" % [str(prog.all_mutations()), prog.belly_bumps(), str(prog.has_belt), str(_has_canary)]

func refresh() -> void:
	if not _owns_body:
		return
	if prog == null or body == null:
		return
	_sig = _signature()
	body.apply(prog.all_mutations(), prog.belly_bumps())
	if body._belt != null:
		body._belt.call("set_worn", prog.has_belt)
		body._belt.call("set_canary", _has_canary)
	FPMirror.tag_layer(body, MIRROR_BODY_LAYER)

func _build_live_details() -> void:
	# Reflection uses depth-tested blood so it cannot paint through the body.
	_blood = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = FPHandBlood.SHADER.replace("depth_test_disabled, ", "")
	_blood.shader = shader
	for side in ["right_hand", "left_hand"]:
		for mesh in body.part_node(side).find_children("*", "MeshInstance3D", true, false):
			if mesh.name in ["Forearm", "Palm", "Fingers"]:
				mesh.material_overlay = _blood
				mesh.set_instance_shader_parameter("along", 0.1 if mesh.name == "Forearm" else 0.8)
	var flesh := SphereMesh.new()
	flesh.radius = 0.035
	flesh.height = 0.055
	flesh.radial_segments = 8
	flesh.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.1, 0.13)
	_mouth_flesh = MeshInstance3D.new()
	_mouth_flesh.visible = false
	_mouth_flesh.mesh = flesh
	_mouth_flesh.material_override = material
	_mouth_flesh.position = Vector3(0, -0.01, 0.115)
	body._sub["jaw"].add_child(_mouth_flesh)
	_carry_flesh = MeshInstance3D.new()
	_carry_flesh.visible = false
	_carry_flesh.mesh = flesh
	_carry_flesh.material_override = material
	_carry_flesh.position = Vector3(0, 0.1, 0.04)
	body._sub["hand_r"].add_child(_carry_flesh)

func _sync_live_details() -> void:
	var main := player.get_parent()
	FPHandBlood.set_amount(_blood, float(main.get("hand_blood")))
	var scenes := {"knife": "fp_knife", "blender": "fp_blender", "big_saw": "fp_big_saw", "tumor": "fp_tumor", "scissors": "fp_scissors"}
	for id in scenes:
		var shown: bool = prog.tumor_in_hand() if id == "tumor" else prog.hands.holds(id)
		if id == "scissors":
			shown = prog.hands.right == "knife" and prog.hands.left == "" and main.carried_flesh <= 0.0
		if shown and not _held.has(id):
			var prop: Node3D = (load("res://main/art/%s.tscn" % scenes[id]) as PackedScene).instantiate()
			body._sub["hand_l" if id in ["blender", "scissors"] else "hand_r"].add_child(prop)
			prop.position = Vector3(0, 0.07, 0.035)
			prop.scale = Vector3.ONE * (0.45 if id in ["blender", "big_saw", "tumor"] else 1.0)
			_held[id] = prop
			FPMirror.tag_layer(prop, MIRROR_BODY_LAYER)
		if _held.has(id):
			_held[id].visible = shown
			var parent: Node3D = body._sub["hand_l" if id == "scissors" or (prog.hands.left == id and id != "big_saw") else "hand_r"]
			if _held[id].get_parent() != parent:
				_held[id].reparent(parent, false)
			_held[id].position = Vector3(0, 0.055, 0.02)
			_held[id].rotation = Vector3.ZERO
			if id == "knife":
				_held[id].call("set_bloody", main.hand_blood)
			elif id == "blender":
				_held[id].call("set_fill", clampf(main.carried_flesh / 40.0, 0.0, 1.0))
				_held[id].call("set_spin", main.blender_charge > 0.0 and main.carried_flesh > 0.0)
	for hand in range(2):
		var id := prog.hands.item(hand)
		for kind in ["spray_cheap", "spray_deep", "canary_feed", "barrier"]:
			var key := "%s/%d" % [kind, hand]
			if id == kind and not _held.has(key):
				var prop := FPConsumable.make(kind)
				body._sub["hand_l" if hand == 0 else "hand_r"].add_child(prop)
				prop.position = Vector3(0, 0.07, 0.035)
				_held[key] = prop
				FPMirror.tag_layer(prop, MIRROR_BODY_LAYER)
			if _held.has(key):
				_held[key].visible = id == kind
				if id == kind and main.art_hookup._consumables[hand].has(kind):
					_held[key].position = Vector3(0, 0.055, 0.02)
	var rig: FDKHandsRig = main.get("hands_rig")
	_mouth_flesh.visible = rig != null and rig.state == FDKHandsRig.HandState.TEAR
	var carry := float(main.get("carried_flesh"))
	_carry_flesh.visible = carry > 0.0
	_carry_flesh.scale = Vector3.ONE * lerpf(1.0, 2.0, clampf(carry / 40.0, 0.0, 1.0))
	if main.tank_lid != null:
		if main.tank_lid.held and not _held.has("lid"):
			var copy: Node3D = main.tank_lid.lid.duplicate()
			body._sub["hand_r"].add_child(copy)
			copy.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.07, 0.04))
			_held["lid"] = copy
			FPMirror.tag_layer(copy, MIRROR_BODY_LAYER)
		if _held.has("lid"):
			_held["lid"].visible = main.tank_lid.held
			_held["lid"].position = Vector3(0, 0.055, 0.04)
	if body._belt != null:
		body._belt.call("set_spray_count", prog.sprays.count_of_tier(FDKSprayCan.Tier.CHEAP) - int(prog.hands.holds("spray_cheap")), prog.sprays.count_of_tier(FDKSprayCan.Tier.DEEP) - int(prog.hands.holds("spray_deep")))
		body._belt.call("set_supplies", prog.canary_feed > 0 and not prog.hands.holds("canary_feed"), prog.barriers > 0 and not prog.hands.holds("barrier"))
		body._belt.call("set_hung", main.belt_swap.hung_ids())
		FPMirror.tag_layer(body._belt, MIRROR_BODY_LAYER)

func _sync_body_posture() -> void:
	if body == null or player == null or not is_instance_valid(player):
		return
	var feet_y := -0.9
	if player.has_method("get_feet_position"):
		feet_y = player.to_local(player.call("get_feet_position")).y
	var pivot: Node3D = player.get_node_or_null("CameraPivot")
	var crouch := 0.0
	var pitch := 0.0
	if pivot != null:
		# Bob affects the eye, not the capsule's posture. Reading the animated
		# eye height here makes a standing walker repeatedly bend their knees.
		crouch = 1.0 if bool(player.get("_is_crouching")) else 0.0
		pitch = pivot.rotation.x
	var walk_phase := float(player.get("_bob_time")) if player.get("_bob_time") != null else 0.0
	var walk_weight := float(player.get("_bob_weight")) if player.get("_bob_weight") != null else 0.0
	body.position.y = feet_y
	if body.has_method("set_posture"):
		body.call("set_posture", crouch, walk_phase, walk_weight, pitch)

## Where a world point appears on screen in the mirror (its image across
## the glass plane, projected by the eye camera).
func image_screen(world: Vector3) -> Vector2:
	var xf := art.global_transform.orthonormalized()
	var n := xf.basis.z
	var g := xf * Vector3(0, GLASS_CY, GLASS_Z)
	return eye.unproject_position(world - n * (2.0 * n.dot(world - g)))
