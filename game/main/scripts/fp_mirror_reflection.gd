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
const GLASS_W := 0.3
const GLASS_HH := 0.38
const GLASS_CY := 1.45
const GLASS_Z := 0.016
const VP_SIZE := Vector2i(150, 190)

const REFLECT_SHADER := "shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : source_color, filter_nearest;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	vec3 c = texture(tex, UV).rgb * vec3(0.9, 0.95, 0.97);
	float streak = smoothstep(0.93, 1.0, sin((lp.x * 1.6 + lp.y) * 22.0) * 0.5 + 0.5) * 0.08;
	ALBEDO = c + vec3(streak);
}"

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

func attach(mirror_art: Node3D, p: Node3D, eye_cam: Camera3D, progression: FPProgression) -> void:
	art = mirror_art
	player = p
	eye = eye_cam
	prog = progression
	eye.cull_mask &= ~MIRROR_BODY_LAYER
	body = FPMirrorBody.new()
	body.name = "MirrorBody"
	player.add_child(body)
	body.build()
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
	_vp = SubViewport.new()
	_vp.name = "ReflectionView"
	_vp.size = VP_SIZE
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
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
	if _signature() != _sig:
		refresh()
	var xf := art.global_transform.orthonormalized()
	var n := xf.basis.z
	var up := xf.basis.y
	var g := xf * Vector3(0, GLASS_CY, GLASS_Z)
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
	if prog == null or body == null:
		return
	_sig = _signature()
	body.apply(prog.all_mutations(), prog.belly_bumps())
	if body._belt != null:
		body._belt.call("set_worn", prog.has_belt)
		body._belt.call("set_canary", _has_canary)
	FPMirror.tag_layer(body, MIRROR_BODY_LAYER)

## Where a world point appears on screen in the mirror (its image across
## the glass plane, projected by the eye camera).
func image_screen(world: Vector3) -> Vector2:
	var xf := art.global_transform.orthonormalized()
	var n := xf.basis.z
	var g := xf * Vector3(0, GLASS_CY, GLASS_Z)
	return eye.unproject_position(world - n * (2.0 * n.dot(world - g)))