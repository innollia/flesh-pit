class_name FPMirror
extends CanvasLayer

## The real restroom mirror (docs/spec/03-restroom.md 8, 05-mutations.md).
## No screen panel: the glass itself shows the room and the player's own body,
## rendered by a reflection camera that mirrors the eye across the glass
## plane (off-axis frustum clipped exactly at the glass, low-res nearest
## filtered for the PS1 look). The body (FPMirrorBody) always stands in the
## world under the player on MIRROR_BODY_LAYER, which the eye camera culls, so
## only the mirror sees it; the first-person hands and waist are culled from
## the reflection instead.
## Picking: aim (screen centre, or the mouse while it is free) at a part of
## the reflected body -> it glows and is selected. The part's open mutations
## sprout as small buds around it on the reflected skin (colour = hair kind,
## shrunk and faint when you cannot pay). Aiming at a bud grows that mutation
## as a ghost over the whole body; clicking buys it. Keyboard: Left/Right
## walk the parts, Up/Down walk the buds, Enter buys, Esc leaves.

signal closed
signal mutated(id: String)
signal denied(part: String)

const POOL_COLOR := {
	"common": Color(0.2, 0.16, 0.15),
	"core": Color(0.95, 0.35, 0.55),
	"mantle": Color(0.5, 0.3, 0.62),
	"surface": Color(0.95, 0.85, 0.3),
}
const HOVER_PX := 60.0
const BUD_PX := 26.0
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
const BUD_SHADER := "shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back;
uniform vec4 col : source_color = vec4(1.0);
uniform float glow = 0.0;
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.5);
	ALBEDO = col.rgb * (0.55 + 0.45 * dot(NORMAL, VIEW)) + vec3(rim * 0.35 + glow * (0.5 + 0.2 * sin(TIME * 6.0)));
	ALPHA = col.a;
}"

var prog: FPProgression
var body: FPMirrorBody
var cam: Camera3D ## reflection camera
var art: Node3D
var player: Node3D
var eye: Camera3D
var _vp: SubViewport
var _quad: MeshInstance3D
var _buds: Array[MeshInstance3D] = []
var _part: String = ""
var _cand: Dictionary = {} ## part -> index into open ids
var _ghost: Node3D
var _ghost_id := ""
var _order: Array[String] = []
var _sig := ""
var _body_ok := true
var _aim_mouse := false

func _ready() -> void:
	layer = 6
	visible = false

## Wire the mirror into the world: the glass art, the player (the body hangs
## under it) and the eye camera. Safe to call once.
func attach(mirror_art: Node3D, p: Node3D, eye_cam: Camera3D, progression: FPProgression = null) -> void:
	art = mirror_art
	player = p
	eye = eye_cam
	if progression != null:
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
	cam.cull_mask = 0xFFFFF & ~(1 << 11) & ~HANDS_ROOM_LAYER
	_vp.add_child(cam)
	cam.current = true
	_build_quad()
	_retag()
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
## standing in the room, and pick up mutation changes made elsewhere.
func sync(body_ok: bool = true) -> void:
	if art == null or cam == null:
		return
	_body_ok = body_ok
	body.visible = body_ok
	var s := _signature()
	if s != _sig:
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
	return "%s|%d|%s" % [str(prog.all_mutations()), prog.belly_bumps(), str(prog.has_belt)]

func _retag(n: Node = null) -> void:
	if n == null:
		n = body
	if n is VisualInstance3D and not (n is Light3D):
		(n as VisualInstance3D).layers = MIRROR_BODY_LAYER
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_retag(c)

func open(p: FPProgression) -> void:
	prog = p
	visible = true
	_cand.clear()
	_kb_hold = false
	_aim_mouse = false
	refresh()
	var first := ""
	for part in _order:
		if part_available(part):
			first = part
			break
	focus_part(first if first != "" else (_order[0] if not _order.is_empty() else ""))

func close() -> void:
	visible = false
	_clear_ghost()
	_clear_buds()
	_part = ""
	if body != null:
		for part in FPProgression.PARTS:
			body.set_shimmer(part, false)
	closed.emit()

## Rebuild body shape (and, while open, the glow) after a change.
func refresh() -> void:
	if prog == null or body == null:
		return
	_sig = _signature()
	body.apply(prog.all_mutations(), prog.belly_bumps())
	if body._belt != null:
		body._belt.call("set_worn", prog.has_belt)
	_retag()
	_order.clear()
	for part in FPProgression.PARTS:
		if not prog.mutations_for_part(part).is_empty():
			_order.append(part)
	if prog.belly_bumps() > 0:
		_order.append("tumor")
	_update_glow()

## Mutable parts glow faintly while looking; the selected part glows stronger.
func _update_glow() -> void:
	for part in FPProgression.PARTS:
		var avail := part_available(part) or (part == "belly" and part_available("tumor"))
		var sel := part == _part or (part == "belly" and _part == "tumor")
		body.set_shimmer(part, visible and (avail or sel), 1.3 if sel else 0.45)

func part_available(part: String) -> bool:
	if prog == null:
		return false
	if part == "tumor":
		return prog.belly_bumps() > 0 and prog.tumor_mutations.size() < FPProgression.TUMOR_MUTATIONS.size()
	for id in prog.mutations_for_part(part):
		if not prog.mutation_tree.is_purchased(id):
			return true
	return false

func _open_ids(part: String) -> Array[String]:
	var out: Array[String] = []
	if prog == null or part == "tumor":
		return out
	for id in prog.mutations_for_part(part):
		if not prog.mutation_tree.is_purchased(id):
			out.append(id)
	return out

func candidate(part: String = "") -> String:
	if part == "":
		part = _part
	if part == "tumor":
		return "tumor"
	var ids := _open_ids(part)
	if ids.is_empty():
		return ""
	return ids[clampi(int(_cand.get(part, 0)), 0, ids.size() - 1)]

func current_part() -> String:
	return _part

func show_part(part: String) -> void:
	focus_part(part)

func focus_part(part: String) -> void:
	_part = part
	_rebuild_buds()
	_update_glow()
	_show_ghost(candidate())

func listed_ids() -> Array[String]:
	return prog.mutations_for_part(_part) if prog != null and _part != "tumor" else ([] as Array[String])

# --- buds: the candidates sprouting on the reflected skin ------------------

func buds() -> Array[MeshInstance3D]:
	return _buds

func _clear_buds() -> void:
	for b in _buds:
		b.queue_free()
	_buds.clear()

func _rebuild_buds() -> void:
	_clear_buds()
	if prog == null or body == null or _part == "" or _part == "tumor":
		return
	var ids := _open_ids(_part)
	var c := body.to_local(body.part_center(_part))
	var nb := ids.size()
	for i in range(nb):
		var id := ids[i]
		var mi := MeshInstance3D.new()
		mi.name = "Bud_" + id
		var sm := SphereMesh.new()
		sm.radius = 0.026
		sm.height = 0.05
		sm.radial_segments = 6
		sm.rings = 3
		mi.mesh = sm
		var info: Dictionary = prog.mutation_info[id]
		var pools: Array = info["alt"] if not (info["alt"] as Array).is_empty() else [info["pool"]]
		var col: Color = POOL_COLOR.get(pools[0], Color.GRAY)
		var ok := prog.can_buy_mutation(id)
		col.a = 1.0 if ok else 0.4
		var mat := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = BUD_SHADER
		mat.shader = sh
		mat.set_shader_parameter("col", col)
		mi.material_override = mat
		mi.set_meta("mut_id", id)
		mi.set_meta("afford", ok)
		# a ring around the part, a hand's width out, on the front (+Z) skin
		var a := -PI * 0.5 + TAU * (float(i) + 0.5) / float(maxi(nb, 1))
		var r := 0.1 if _part != "face" else 0.13
		mi.position = c + Vector3(cos(a) * r, sin(a) * r, 0.1)
		body.add_child(mi)
		_buds.append(mi)
	_retag()
	_style_buds()

func _style_buds() -> void:
	var sel := clampi(int(_cand.get(_part, 0)), 0, maxi(_buds.size() - 1, 0))
	for k in range(_buds.size()):
		var b := _buds[k]
		var ok: bool = b.get_meta("afford")
		var s := (1.0 if ok else 0.6) * (1.5 if k == sel else 1.0)
		b.scale = Vector3.ONE * s
		(b.material_override as ShaderMaterial).set_shader_parameter("glow", 1.0 if k == sel else 0.0)

func select_candidate(i: int, _rebuild: bool = true) -> void:
	var n := _open_ids(_part).size()
	if n == 0:
		return
	_cand[_part] = posmod(i, n)
	_style_buds()
	_show_ghost(candidate())

func _clear_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	_ghost_id = ""

func _show_ghost(id: String) -> void:
	if id == _ghost_id:
		return
	_clear_ghost()
	if id == "" or id == "tumor" or body == null:
		return
	_ghost = body.ghost(id)
	_retag(_ghost)
	_ghost_id = id

func ghost_id() -> String:
	return _ghost_id

func buy_current() -> String:
	if prog == null or _part == "":
		return ""
	if _part == "tumor":
		var got := prog.buy_tumor_mutation()
		if got == "":
			body.blink_red("belly")
			denied.emit("tumor")
			return ""
		_after_buy(got)
		return got
	var id := candidate()
	if id == "" or not prog.can_buy_mutation(id):
		body.blink_red(_part)
		denied.emit(_part)
		return ""
	prog.buy_mutation(id)
	_after_buy(id)
	return id

func _after_buy(id: String) -> void:
	_clear_ghost()
	mutated.emit(id)
	refresh()
	if not part_available(_part):
		for p in _order:
			if part_available(p):
				focus_part(p)
				return
	focus_part(_part)

func _move_part(step: int) -> void:
	if _order.is_empty():
		return
	var i := _order.find(_part)
	focus_part(_order[posmod(i + step, _order.size())])

# --- aiming through the glass ----------------------------------------------

## Where a world point appears on screen in the mirror: its mirror image
## (reflected across the glass plane) projected by the eye camera.
func image_screen(world: Vector3) -> Vector2:
	var xf := art.global_transform.orthonormalized()
	var n := xf.basis.z
	var g := xf * Vector3(0, GLASS_CY, GLASS_Z)
	var img := world - n * (2.0 * n.dot(world - g))
	return eye.unproject_position(img)

func _visible_image(world: Vector3) -> bool:
	var xf := art.global_transform.orthonormalized()
	var n := xf.basis.z
	var g := xf * Vector3(0, GLASS_CY, GLASS_Z)
	return not eye.is_position_behind(world - n * (2.0 * n.dot(world - g)))

func part_at(screen: Vector2) -> String:
	if body == null:
		return ""
	var best := ""
	var bd := HOVER_PX
	for part in _order:
		var c := body.part_center(part)
		if not _visible_image(c):
			continue
		var d := image_screen(c).distance_to(screen)
		if d < bd:
			bd = d
			best = part
	return best

## Index of the bud under a screen point, -1 if none.
func bud_at(screen: Vector2) -> int:
	var best := -1
	var bd := BUD_PX
	for k in range(_buds.size()):
		var d := image_screen(_buds[k].global_position).distance_to(screen)
		if d < bd:
			bd = d
			best = k
	return best

func part_screen(part: String) -> Vector2:
	return image_screen(body.part_center(part))

func bud_screen(k: int) -> Vector2:
	return image_screen(_buds[k].global_position)

## Aim at a screen point: a bud first (grows its ghost), else a part.
func aim(screen: Vector2) -> void:
	var k := bud_at(screen)
	if k >= 0:
		if k != int(_cand.get(_part, 0)):
			select_candidate(k)
		return
	var p := part_at(screen)
	if p != "" and p != _part:
		focus_part(p)

func _aim_point() -> Vector2:
	if _aim_mouse:
		return get_viewport().get_mouse_position()
	return get_viewport().get_visible_rect().size * 0.5

func _process(_delta: float) -> void:
	if visible and art != null and not _kb_hold:
		aim(_aim_point())

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		_aim_mouse = true
		_kb_hold = false
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if art != null:
				aim(mb.position)
			if _part != "":
				buy_current()
				get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			select_candidate(int(_cand.get(_part, 0)) - 1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select_candidate(int(_cand.get(_part, 0)) + 1)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			close()
	elif event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_focus_next"):
		_keyboard()
		_move_part(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_focus_prev"):
		_keyboard()
		_move_part(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_keyboard()
		select_candidate(int(_cand.get(_part, 0)) + 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_keyboard()
		select_candidate(int(_cand.get(_part, 0)) - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		buy_current()
		get_viewport().set_input_as_handled()

## Keyboard takes over: stop aiming until the mouse moves again, so the
## focus the arrows picked stays put (the aim would snap it back).
func _keyboard() -> void:
	_kb_hold = true

var _kb_hold := false