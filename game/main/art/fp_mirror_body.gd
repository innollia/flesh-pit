class_name FPMirrorBody
extends Node3D

## The player's upper body as seen in the restroom mirror (docs/spec/03 8,
## 05). Low-poly, built in code. Every mirror part is a pivot so a mutation
## can reshape it (scale) and hang extra pieces on it. Also used for the
## per-mutation look captures. Faces +Z (towards the mirror camera); the
## image is a reflection, so the player's right hand is at +X.
## Public: part_node(part), part_center(part), apply(ids, bumps),
## ghost(id) -> Node3D (translucent preview), set_shimmer(part, on),
## set_red(part, t), static look(id) -> Dictionary.

const K := preload("res://main/art/fp_art_kit.gd")
const BELT_SCENE := preload("res://main/art/fp_belt.tscn")
const BAG_SCENE := preload("res://main/art/fp_tumor_bag.tscn")
## Same skin as the first-person hands (fdk_hands_rig skin_color).
const SKIN := Color(0.88, 0.72, 0.62)
const SKIN_D := Color(0.8, 0.64, 0.55)

const SHIMMER_SHADER := "shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 col : source_color = vec4(0.75, 0.45, 1.0, 1.0);
uniform float strength = 0.7;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	// soft glow on the silhouette only, with one slow broad sweep; no
	// dense diagonal bands across the skin (read as pink stripes)
	float s = sin(dot(lp, vec3(2.5, 4.0, 1.5)) - TIME * 1.2) * 0.5 + 0.5;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float glint = smoothstep(0.6, 1.0, s) * 0.35;
	ALBEDO = col.rgb * strength * (0.25 + glint) * rim * 1.1;
}"
const GHOST_SHADER := "shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
uniform vec4 col : source_color = vec4(0.55, 1.0, 1.0, 0.75);
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.2);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = col.rgb * (0.45 + 0.55 * facing);
	ALPHA = col.a * (0.45 + 0.55 * rim) * (0.85 + 0.15 * sin(TIME * 5.0));
}"

var _skin: Material
var _paint: Material
var _parts := {}   ## part -> pivot Node3D
var _base := {}    ## part -> base scale
var _meshes := {}  ## part -> Array[MeshInstance3D] (base meshes)
var _shim := {}    ## part -> Array[MeshInstance3D]
var _shim_mat := {} ## part -> ShaderMaterial
var _red := {}     ## part -> seconds left
var _extras: Array[Node3D] = []
var _sub := {}     ## sub pivot name -> Node3D (jaw, shoulders, hand, fingers, forearm...)
var _time := 0.0
var applied: Array[String] = []
var _belt: Node3D
var _rest_pose := {} ## mutation-adjusted transforms, before posture composition

## World-y trunk rings [y, half width, front depth, back depth], hips to collar.
const TRUNK := [
	[0.97, 0.165, 0.098, 0.115],
	[1.02, 0.152, 0.098, 0.095],
	[1.07, 0.142, 0.1, 0.088],
	[1.12, 0.15, 0.105, 0.09],
	[1.16, 0.162, 0.11, 0.092],
	[1.22, 0.175, 0.12, 0.1],
	[1.29, 0.185, 0.122, 0.102],
	[1.35, 0.192, 0.11, 0.1],
	[1.4, 0.19, 0.085, 0.085],
	[1.435, 0.12, 0.065, 0.065],
	[1.45, 0.058, 0.055, 0.052],
]

## One cross-section ring at height y: `n` points around, pinched to a
## squarish human section (sides flatter than a circle); front (+Z) and back
## depths differ so chest, belly and buttocks read.
func _ring(y: float, cx: float, hw: float, zf: float, zb: float, n: int, cz: float = 0.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	for j in range(n):
		var a := TAU * float(j) / float(n)
		var c := cos(a)
		var s := sin(a)
		var k := pow(absf(c), 0.75) * signf(c)
		out.append(Vector3(cx + k * hw, y, cz + s * (zf if s > 0.0 else zb)))
	return out

func _ready() -> void:
	build()

func build() -> void:
	if not _parts.is_empty():
		return
	_paint = _matte("res://addons/flesh_dig_kit/textures/tex_skin_128.png", 0.0)
	_skin = FDKSkinMaterial.make()
	var I := Transform3D.IDENTITY
	# PS1-style body: every part is a hand-pinched ring loft (few sides, flat
	# faces) whose end rings match the next part, so the silhouette reads as
	# one joined low-poly mesh instead of spheres and cylinders.
	# --- face (head, jaw, eyes, nose): low-poly egg head
	var face := _part("face", Vector3(0, 1.62, 0))
	var st := K.begin()
	var hr: Array = []
	for r in [[-0.1, 0.05, 0.05, 0.055], [-0.07, 0.078, 0.085, 0.08], [-0.02, 0.092, 0.098, 0.095], [0.04, 0.096, 0.1, 0.1], [0.09, 0.088, 0.092, 0.094], [0.12, 0.066, 0.07, 0.074], [0.138, 0.03, 0.032, 0.034]]:
		hr.append(_ring(r[0], 0.0, r[1], r[2], r[3], 6))
	FDKLowPoly.loft(st, hr, [SKIN_D, SKIN, SKIN, SKIN, SKIN, SKIN], true, true)
	for sx in [-1, 1]:
		K.lathe(st, K.T(Vector3(sx * 0.094, 0.02, -0.005), Vector3(0, 0, 90 * sx), Vector3(1.0, 1.0, 0.5)), [Vector2(0.0, 0.0), Vector2(0.022, 0.006), Vector2(0.0, 0.016)], 6, [SKIN_D]) # ears
	_mesh(face, "Head", st)
	_face_texture(face.get_node("Head"))
	# Keep mutation and mouth-effect anchors; ordinary features cost no geometry.
	var eyes := _subpivot(face, "eyes", Vector3(0, 0.02, 0.096))
	# Image eyes gain geometry only for mutations that change their depth/size.
	for side in [-1, 1]:
		var eye_st := K.begin()
		var cx: float = side * 0.034
		var points := [Vector3(cx-0.018, -0.014, 0.014), Vector3(cx+0.018, -0.014, 0.014), Vector3(cx+0.018, 0.014, 0.014), Vector3(cx-0.018, 0.014, 0.014)]
		var uvs := [Vector2(0,1), Vector2(1,1), Vector2(1,0), Vector2(0,0)]
		for index in [0,2,1,0,3,2]:
			eye_st.set_normal(Vector3.BACK)
			eye_st.set_color(SKIN)
			var center := 0.325 if side < 0 else 0.675
			eye_st.set_uv(Vector2(center + (uvs[index].x-0.5)*0.22, 0.50+(uvs[index].y-0.5)*0.20))
			eye_st.add_vertex(points[index])
		var eye_mesh := _mesh(eyes, "EyeImageLeft" if side < 0 else "EyeImageRight", eye_st)
		eye_mesh.mesh = eye_st.commit()
		var eye_mat := FDKSkinMaterial.make(1.0, false)
		eye_mat.set_shader_parameter("face", true)
		eye_mat.set_shader_parameter("eye_patch", true)
		eye_mat.set_shader_parameter("face_tex", load("res://main/art/textures/player_face_ps1.png"))
		eye_mesh.material_override = eye_mat
		eye_mesh.visible = false
	_subpivot(face, "nose", Vector3(0, -0.025, 0))
	_subpivot(face, "jaw", Vector3(0, -0.05, 0.0))
	# --- neck: its end rings meet the jaw line and the collar
	var neck := _part("neck", Vector3(0, 1.47, 0))
	st = K.begin()
	FDKLowPoly.loft(st, [_ring(-0.035, 0.0, 0.062, 0.056, 0.054, 10), _ring(0.0, 0.0, 0.058, 0.052, 0.05, 10), _ring(0.06, 0.0, 0.05, 0.05, 0.047, 10), _ring(0.1, 0.0, 0.055, 0.055, 0.052, 10)], [SKIN_D, SKIN, SKIN], false, false)
	_mesh(neck, "Neck", st)
	# --- chest: ribcage, pecs, shoulder slope (world 1.16 .. 1.44)
	var chest := _part("chest", Vector3(0, 1.28, 0))
	st = K.begin()
	var cr: Array = []
	for r in TRUNK:
		if r[0] >= 1.16 - 0.001:
			cr.append(_ring(r[0] - 1.28, 0.0, r[1], r[2], r[3], 12))
	FDKLowPoly.loft(st, cr, [SKIN, SKIN, SKIN, SKIN_D, SKIN_D], false, true)
	for sx in [-1, 1]:
		K.lathe(st, K.T(Vector3(sx * 0.08, 0.01, 0.121), Vector3(90, 0, 0)), [Vector2(0.0, 0.0), Vector2(0.011, 0.002), Vector2(0.0, 0.004)], 6, [Color(0.72, 0.46, 0.42)])
	_mesh(chest, "Chest", st)
	# shoulders: small deltoid caps melted into the trunk edge (no joint balls)
	var sh := _subpivot(chest, "shoulders", Vector3(0, 0.1, 0))
	st = K.begin()
	for sx in [-1, 1]:
		FDKLowPoly.loft(st, [_ring(-0.07, sx * 0.19, 0.035, 0.045, 0.045, 6), _ring(-0.02, sx * 0.2, 0.05, 0.052, 0.05, 6), _ring(0.02, sx * 0.175, 0.04, 0.045, 0.045, 6)], [SKIN, SKIN], false, true)
	_mesh(sh, "Shoulders", st)
	# --- belly: waist pinch down to the top of the hips (world 0.97 .. 1.16)
	var belly := _part("belly", Vector3(0, 1.06, 0.0))
	st = K.begin()
	var br: Array = []
	for r in TRUNK:
		if r[0] <= 1.22 + 0.001 and r[0] >= 0.97 - 0.001:
			br.append(_ring(r[0] - 1.06, 0.0, r[1], r[2], r[3], 12))
	FDKLowPoly.loft(st, br, [SKIN, SKIN, SKIN], false, false)
	K.lathe(st, K.T(Vector3(0, -0.02, 0.104), Vector3(90, 0, 0)), [Vector2(0.0, 0.004), Vector2(0.008, 0.0), Vector2(0.0, -0.003)], 6, [Color(0.55, 0.34, 0.3)]) # navel
	_mesh(belly, "Belly", st)
	# --- arms: upper arms from the deltoid down to the elbow
	var arms := _part("arms", Vector3(0, 1.36, 0))
	for sx in [-1, 1]:
		var ua := _subpivot(arms, "upper_" + ("r" if sx > 0 else "l"), Vector3(sx * 0.2, 0, 0))
		st = K.begin()
		var ar: Array = []
		for r in [[0.02, 0.0, 0.0, 0.05, 0.05], [-0.04, 0.012, 0.008, 0.054, 0.056], [-0.1, 0.03, 0.02, 0.058, 0.062], [-0.16, 0.047, 0.03, 0.05, 0.05], [-0.21, 0.06, 0.048, 0.04, 0.042], [-0.245, 0.07, 0.06, 0.036, 0.038]]:
			ar.append(_ring(r[0], sx * r[1], r[3], r[4], r[4], 8, r[2]))
		FDKLowPoly.loft(st, ar, [SKIN, SKIN, SKIN, SKIN, SKIN_D], true, false)
		_mesh(ua, "UpperArm", st)
		# --- hands: child of upper arm (elbow joint), full articulated arm chain
		var side := "right_hand" if sx > 0 else "left_hand"
		var hp := _part_child(ua, side, Vector3(sx * 0.08, -0.26, 0.08))
		var s := "r" if sx > 0 else "l"
		var fa := _subpivot(hp, "forearm_" + s, Vector3.ZERO)
		st = K.begin()
		var fr: Array = []
		for r in [[0.04, 0.0, -0.01, 0.038, 0.04], [-0.005, -0.002, 0.004, 0.036, 0.036], [-0.05, -0.005, 0.014, 0.05, 0.046], [-0.11, -0.008, 0.026, 0.042, 0.036], [-0.18, -0.011, 0.038, 0.03, 0.026], [-0.235, -0.014, 0.045, 0.024, 0.02]]:
			fr.append(_ring(r[0], sx * r[1], r[3], r[4], r[4], 8, r[2]))
		FDKLowPoly.loft(st, fr, [SKIN_D, SKIN, SKIN, SKIN, SKIN], false, true)
		_mesh(fa, "Forearm", st)
		var hand := _subpivot(hp, "hand_" + s, Vector3(-sx * 0.014, -0.24, 0.045))
		hand.rotation_degrees = Vector3(-10.0, -sx * 75.0, 180.0)
		hand.set_meta("base_rot", hand.rotation)
		hand.scale = Vector3.ONE * 1.25
		hand.set_meta("base_scale", hand.scale)
		st = K.begin()
		K.lathe(st, K.T(Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.35)), [Vector2(0.024, 0.0), Vector2(0.04, 0.025), Vector2(0.042, 0.07), Vector2(0.034, 0.088), Vector2(0.0, 0.09)], 8, [SKIN_D, SKIN, SKIN])
		K.tube(st, I, [Vector3(-sx * 0.033, 0.018, 0.0), Vector3(-sx * 0.052, 0.045, 0.014), Vector3(-sx * 0.055, 0.078, 0.022)], [0.013, 0.011, 0.009], 4, [SKIN, SKIN_D]) # thumb
		_mesh(hand, "Palm", st)
		var fing := _subpivot(hand, "fingers_" + s, Vector3(0, 0.082, 0.0))
		st = K.begin()
		for i in range(4):
			var x := -0.027 + i * 0.018
			var ln := 0.066 - absf(i - 1.3) * 0.01
			K.tube(st, I, [Vector3(x, 0, 0), Vector3(x * 1.02, ln * 0.5, 0.016), Vector3(x * 1.03, ln * 0.8, 0.05)], [0.0095, 0.0088, 0.0075], 4, [SKIN, SKIN, Color(0.93, 0.78, 0.72)])
		_mesh(fing, "Fingers", st)
	# --- legs (not a mirror part): briefs over the hips, then articulated
	# thigh and shin/foot preserving exact original profile and mesh lengths
	var legs := _part("legs", Vector3(0, 0.95, 0))
	st = K.begin()
	var cloth := Color(0.82, 0.84, 0.86)
	var cloth_d := Color(0.66, 0.68, 0.72)
	var lr: Array = []
	for r in [[0.97, 0.165, 0.098, 0.115], [0.92, 0.172, 0.1, 0.125], [0.87, 0.165, 0.095, 0.115]]:
		lr.append(_ring(r[0] - 0.95, 0.0, r[1], r[2], r[3], 12))
	FDKLowPoly.loft(st, lr, [cloth, cloth_d], false, true)
	for sx in [-1, 1]:
		FDKLowPoly.loft(st, [_ring(-0.08, sx * 0.085, 0.084, 0.085, 0.09, 8), _ring(-0.13, sx * 0.087, 0.082, 0.083, 0.088, 8)], [cloth_d], false, false)
	_mesh(legs, "Briefs", st, true)
	for sx in [-1, 1]:
		var s := "r" if sx > 0 else "l"
		var thigh := _subpivot(legs, "thigh_" + s, Vector3(sx * 0.087, -0.08, 0.0))
		st = K.begin()
		var tr: Array = []
		for r in [
			[-0.12, 0.087, 0.0, 0.084, 0.086, 0.09],
			[-0.2, 0.092, 0.012, 0.078, 0.082, 0.076],
			[-0.32, 0.089, 0.02, 0.062, 0.066, 0.058],
			[-0.42, 0.086, 0.025, 0.048, 0.05, 0.044],
			[-0.47, 0.085, 0.03, 0.042, 0.046, 0.038]
		]:
			tr.append(_ring(r[0] + 0.08, sx * (r[1] - 0.087), r[3], r[4], r[5], 8, r[2]))
		FDKLowPoly.loft(st, tr, [SKIN, SKIN, SKIN, SKIN_D], false, false)
		_mesh(thigh, "Thigh", st)

		var shin := _subpivot(thigh, "shin_" + s, Vector3(-sx * 0.002, -0.39, 0.03))
		st = K.begin()
		var sr: Array = []
		for r in [
			[-0.47, 0.085, 0.03, 0.042, 0.046, 0.038],
			[-0.53, 0.084, 0.005, 0.046, 0.04, 0.056],
			[-0.62, 0.083, -0.01, 0.05, 0.04, 0.066],
			[-0.72, 0.081, -0.004, 0.036, 0.034, 0.044],
			[-0.82, 0.079, 0.0, 0.026, 0.026, 0.028],
			[-0.88, 0.078, 0.0, 0.028, 0.027, 0.03]
		]:
			sr.append(_ring(r[0] + 0.47, sx * (r[1] - 0.085), r[3], r[4], r[5], 8, r[2] - 0.03))
		FDKLowPoly.loft(st, sr, [SKIN, SKIN, SKIN, SKIN, SKIN_D], false, false)
		_mesh(shin, "Shin", st)
		# The foot keeps its full original shape and stays flat as the knee bends.
		var foot := _subpivot(shin, "foot_" + s, Vector3(-sx * 0.007, -0.41, -0.03))
		st = K.begin()
		K.tube(st, I, [Vector3(0, -0.01, -0.03), Vector3(sx * 0.002, -0.035, 0.03), Vector3(sx * 0.007, -0.05, 0.12)], [0.032, 0.036, 0.026], 6, [SKIN_D, SKIN, SKIN], true, 0.65)
		_mesh(foot, "Foot", st)
	# --- belt: the same first-person waist belt (fp_belt.gd: leather band,
	# buckle, spray cans, canary pocket) plus the tumor bag, worn over the
	# briefs so the mirror shows the gear the player carries. Reused scenes,
	# not a copy. The belt faces -Z; the mirror body faces +Z, so it is
	# turned 180 and dropped to the briefs waistline.
	_belt = BELT_SCENE.instantiate()
	_belt.name = "Belt"
	# band sits on the briefs' top edge (world 0.97); scaled so the loop
	# wraps just outside the hip ring there (half width 0.165)
	_belt.position = Vector3(0, 0.962, 0.0)
	_belt.rotation_degrees = Vector3(0, 180, 0)
	# fitted to this trunk's own waist (TRUNK at 0.97) so the band hugs the
	# skin instead of floating in front of the belly
	_belt.set("wx", 0.172)
	_belt.set("wzf", 0.104)
	_belt.set("wzb", 0.118)
	add_child(_belt)
	_belt.set_meta("base_pos", _belt.position)
	_belt.set_meta("base_rot", _belt.rotation)
	_belt.set_meta("base_scale", _belt.scale)
	var bag := BAG_SCENE.instantiate()
	bag.name = "TumorBag"
	bag.position = Vector3(-0.2, -0.02, 0.06)
	bag.scale = Vector3.ONE * 0.8
	_belt.add_child(bag)
	# the belt scene carries its own dark work trousers for the first-person
	# look-down; the mirror already shows the briefs, so hide those trousers
	# and keep only the band, buckle, cans, canary and bag. _ready ran on
	# add_child, so the Trousers mesh already exists.
	for own in ["Trousers", "Torso"]:  # the mirror builds its own body
		var tr := _belt.get_node_or_null(own)
		if tr != null:
			(tr as Node3D).visible = false
	# --- whole: no mesh of its own; its shimmer covers every part
	_part("whole", Vector3.ZERO)
	# shimmer shells
	for part in _parts.keys():
		var mat := ShaderMaterial.new()
		var sh2 := Shader.new()
		sh2.code = SHIMMER_SHADER
		mat.shader = sh2
		_shim_mat[part] = mat
		_shim[part] = []
		var src: Array = _meshes[part] if part != "whole" else _all_meshes()
		for mi in src:
			var s2 := MeshInstance3D.new()
			s2.name = "Shimmer"
			s2.mesh = (mi as MeshInstance3D).mesh
			s2.material_override = mat
			s2.scale = Vector3.ONE * 1.02
			s2.visible = false
			(mi as MeshInstance3D).add_child(s2)
			_shim[part].append(s2)
	_capture_rest_pose()

## PS1-style matte: texture times vertex paint, no gloss, nearest filtering.
func _matte(tex: String, tex_amount: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	if tex_amount > 0.0:
		m.albedo_texture = load(tex)
		m.uv1_scale = Vector3(3, 3, 3)
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	return m

func _part(p: String, at: Vector3) -> Node3D:
	return _part_child(self, p, at)

func _part_child(parent: Node3D, p: String, at: Vector3) -> Node3D:
	var n := K.pivot(parent, "Part_" + p, at)
	_parts[p] = n
	_meshes[p] = []
	_base[p] = Vector3.ONE
	n.set_meta("base_pos", at)
	n.set_meta("base_rot", Vector3.ZERO)
	n.set_meta("base_scale", Vector3.ONE)
	return n

func _subpivot(parent: Node3D, sub: String, at: Vector3) -> Node3D:
	var n := K.pivot(parent, sub, at)
	_sub[sub] = n
	n.set_meta("base_scale", Vector3.ONE)
	n.set_meta("base_pos", at)
	n.set_meta("base_rot", Vector3.ZERO)
	return n

func _mesh(parent: Node3D, mname: String, st: SurfaceTool, painted: bool = false) -> MeshInstance3D:
	var mi := K.add_mesh(parent, mname, K.finish(st, 4.0), _paint if painted else _skin)
	var p := parent
	while p != null and not String(p.name).begins_with("Part_"):
		p = p.get_parent() as Node3D
	if p != null:
		(_meshes[String(p.name).substr(5)] as Array).append(mi)
	return mi

func _all_meshes() -> Array:
	var out: Array = []
	for p in _meshes.keys():
		out.append_array(_meshes[p])
	return out

func part_node(part: String) -> Node3D:
	return _parts.get(part, null)

func sub_node(sub: String) -> Node3D:
	return _sub.get(sub, null)

func part_center(part: String) -> Vector3:
	match part:
		"whole": return global_transform * Vector3(0.0, 0.62, 0.02)
		"arms": return global_transform * Vector3(0.25, 1.24, 0.05)
		"right_hand": return (_sub["hand_r"] as Node3D).global_position + Vector3(0, 0.04, 0)
		"left_hand": return (_sub["hand_l"] as Node3D).global_position + Vector3(0, 0.04, 0)
		"tumor": return (_parts["belly"] as Node3D).global_position + Vector3(0.07, -0.02, 0.1)
	var n: Node3D = _parts.get(part, null)
	return n.global_position if n != null else global_position

func set_shimmer(part: String, on: bool, strength: float = 0.7) -> void:
	for s in _shim.get(part, []):
		(s as MeshInstance3D).visible = on or float(_red.get(part, 0.0)) > 0.0
	var mat: ShaderMaterial = _shim_mat.get(part, null)
	if mat != null and float(_red.get(part, 0.0)) <= 0.0:
		mat.set_shader_parameter("col", Color(0.75, 0.45, 1.0))
		mat.set_shader_parameter("strength", strength)

func shimmer_on(part: String) -> bool:
	var arr: Array = _shim.get(part, [])
	return not arr.is_empty() and (arr[0] as MeshInstance3D).visible

## Red blink for "not enough hairs".
func blink_red(part: String) -> void:
	_red[part] = 0.7

func is_red(part: String) -> bool:
	return float(_red.get(part, 0.0)) > 0.0

func _process(delta: float) -> void:
	_time += delta
	for part in _red.keys():
		var t: float = _red[part]
		if t <= 0.0:
			continue
		t -= delta
		_red[part] = t
		var mat: ShaderMaterial = _shim_mat[part]
		var on := t > 0.0 and fmod(t, 0.23) > 0.08
		mat.set_shader_parameter("col", Color(1.0, 0.1, 0.08))
		mat.set_shader_parameter("strength", 1.4 if on else 0.25)
		for s in _shim[part]:
			(s as MeshInstance3D).visible = t > 0.0 or (s as MeshInstance3D).visible
	# living mutations: cud belly ripple, alien left-hand twitch, trunk sway
	if "M16" in applied or "M19" in applied:
		var b: Node3D = _parts["belly"]
		b.scale = (_base["belly"] as Vector3) * Vector3(1.0 + sin(_time * 3.0) * 0.03, 1.0 + sin(_time * 3.0 + 1.5) * 0.03, 1.0)
	if "M22" in applied:
		var h: Node3D = _sub["hand_l"]
		h.rotation.z = (h.get_meta("base_rot") as Vector3).z + sin(_time * 9.0) * 0.12 * maxf(0.0, sin(_time * 1.3))

## Applies real crouch/feet/eye posture and actual walk gait to the mirror reflection body.
## Smoothly returns to idle when stopped, without creating any forward-reaching arm pose.
func set_posture(crouch: float, walk_phase: float, walk_weight: float, pitch: float, _delta: float = 0.0) -> void:
	var c := clampf(crouch, 0.0, 1.0)
	var w := clampf(walk_weight, 0.0, 1.0)
	for n in _rest_pose:
		(n as Node3D).transform = _rest_pose[n]
	# Solve the full-length leg segments for the deep squat once. Interpolate
	# joint angles, then derive pelvis position from the planted ankle, rather
	# than scaling legs or sinking the feet through the floor.
	var upper_vector := Vector2(-0.39, 0.03)
	var lower_vector := Vector2(-0.41, -0.03)
	var target := Vector2(-0.17, 0.38) # crouched hip -> planted ankle
	var reach := target.length()
	var along := (upper_vector.length_squared() - lower_vector.length_squared() + reach * reach) / (2.0 * reach)
	var unit := target / reach
	var knee := unit * along + Vector2(unit.y, -unit.x) * sqrt(maxf(0.0, upper_vector.length_squared() - along * along))
	var thigh_angle := wrapf(knee.angle() - upper_vector.angle(), -PI, PI) * c
	var shin_angle := wrapf((target - knee).angle() - lower_vector.angle(), -PI, PI) * c
	var thigh_basis := Basis(Vector3.RIGHT, thigh_angle)
	var shin_basis := Basis(Vector3.RIGHT, shin_angle)
	var pelvis := Vector3(0, 0.07, 0) - thigh_basis * Vector3(0, -0.39, 0.03) - shin_basis * Vector3(0, -0.41, -0.03) + Vector3(0, 0.08, 0)
	var gait := sin(walk_phase * 0.5) * 0.22 * w * (1.0 - c * 0.65)
	var sway := sin(walk_phase * 0.5) * 0.012 * w
	var bounce := sin(walk_phase) * 0.012 * w
	pelvis += Vector3(sway, bounce, 0)
	_parts["legs"].position = pelvis
	for s in ["r", "l"]:
		var swing: float = gait if s == "r" else -gait
		_sub["thigh_" + s].basis = Basis(Vector3.RIGHT, thigh_angle + swing)
		_sub["shin_" + s].basis = Basis(Vector3.RIGHT, shin_angle - thigh_angle - swing * 0.5)
		_sub["foot_" + s].basis = Basis(Vector3.RIGHT, -shin_angle - swing * 0.5)
	# The torso folds at the hips with its original dimensions. Its connected
	# collar/head chain follows the crouched eye height; part mutation scales
	# and offsets remain in the saved rest transforms.
	# The unscaled head is 0.138 m tall above its pivot. At full crouch
	# place that pivot at 0.76 m so the visible head fits the 0.9 m capsule.
	var fold := acos((0.76 - 0.32) / 0.67) * c
	var spine := Transform3D(Basis(Vector3.RIGHT, fold), pelvis)
	for p in ["belly", "chest", "arms"]:
		var n: Node3D = _parts[p]
		var rest: Transform3D = _rest_pose[n]
		n.transform = spine * Transform3D(rest.basis, rest.origin - Vector3(0, 0.95, 0))
	if _belt != null:
		_belt.position = pelvis + Vector3(0, 0.012, 0)
	# Forearms are elbow children of the corresponding upper arm, including
	# the original hand rotation and attached tools. No independent hand root
	# translation can tear the elbow seam during walking or crouching.
	for s in ["r", "l"]:
		var swing: float = -gait if s == "r" else gait
		var upper: Node3D = _sub["upper_" + s]
		var upper_rest: Transform3D = _rest_pose[upper]
		upper.basis = Basis(Vector3.RIGHT, -fold + swing) * upper_rest.basis
		var forearm_root: Node3D = _parts["right_hand" if s == "r" else "left_hand"]
		var forearm_rest: Transform3D = _rest_pose[forearm_root]
		forearm_root.basis = Basis(Vector3.RIGHT, -0.85 * c) * forearm_rest.basis
	var neck: Node3D = _parts["neck"]
	var neck_rest: Transform3D = _rest_pose[neck]
	neck.transform = spine * Transform3D(neck_rest.basis, neck_rest.origin - Vector3(0, 0.95, 0))
	neck.basis = spine.basis * Basis(Vector3.RIGHT, -pitch * 0.25) * neck_rest.basis
	var face: Node3D = _parts["face"]
	var face_rest: Transform3D = _rest_pose[face]
	face.position = neck.position + neck.basis * (face_rest.origin - neck_rest.origin)
	# This model faces +Z (the reflection flips only Z). A positive local
	# X rotation lowers its gaze, whereas the camera's down pitch is negative.
	face.basis = Basis(Vector3.RIGHT, -pitch * 0.65) * face_rest.basis
	if "M22" in applied:
		var hand: Node3D = _sub["hand_l"]
		hand.rotation.z += sin(_time * 9.0) * 0.12 * maxf(0.0, sin(_time * 1.3))

func _capture_rest_pose() -> void:
	_rest_pose.clear()
	for n in _parts.values() + _sub.values():
		_rest_pose[n] = (n as Node3D).transform
	if _belt != null:
		_rest_pose[_belt] = _belt.transform

# --- mutation looks -------------------------------------------------------

## id -> {sub: node to reshape, scale, pos (offset), rot (deg)}; extras are
## built by _extra(). Part pivots use the part name as sub.
static func look(id: String) -> Dictionary:
	match id:
		"M01": return {"sub": "belly", "scale": Vector3(1.4, 1.35, 1.9), "pos": Vector3(0, -0.06, 0.03)}
		"M02": return {"sub": "neck", "scale": Vector3(1.9, 1.05, 1.9)}
		"M04": return {"sub": "jaw", "scale": Vector3(1.75, 1.2, 1.3)}
		"M05": return {"sub": "shoulders", "scale": Vector3(0.55, 0.8, 1.0), "pos": Vector3(0, -0.03, 0.05)}
		"M06": return {"sub": "chest", "scale": Vector3(1.15, 1.18, 1.45)}
		"M07": return {"sub": "hand_r", "scale": Vector3(1.9, 1.1, 1.3)}
		"M10": return {"sub": "fingers_r", "scale": Vector3(1.0, 2.3, 1.0)}
		"M12": return {"sub": "forearm_r", "scale": Vector3(2.3, 1.0, 2.3)}
		"M14": return {"sub": "chest", "scale": Vector3(1.25, 1.08, 1.2)}
		"M15": return {"sub": "jaw", "scale": Vector3(1.1, 1.3, 1.15), "pos": Vector3(0, -0.3, 0.06)}
		"M18": return {"sub": "hand_r", "scale": Vector3(2.0, 0.7, 1.8), "rot": Vector3(0, 0, -70)}
		"M20": return {"sub": "upper_r", "rot": Vector3(-55, 0, 45)}
		"M24": return {"sub": "eyes", "scale": Vector3(2.4, 2.8, 1.6)}
		"M28": return {"sub": "forearm_l", "scale": Vector3(0.6, 1.25, 0.6), "rot": Vector3(70, 0, -45)}
		"T4": return {"sub": "belly", "scale": Vector3(1.9, 1.6, 2.1)}
		"T5": return {"sub": "eyes", "scale": Vector3(3.2, 1.3, 0.6), "pos": Vector3(0, 0.0, -0.06)}
	return {}
func _reset_shapes() -> void:
	for n in _sub.values():
		(n as Node3D).scale = n.get_meta("base_scale")
		(n as Node3D).position = n.get_meta("base_pos")
		(n as Node3D).rotation = n.get_meta("base_rot")
	for p in _parts.keys():
		var part: Node3D = _parts[p]
		part.position = part.get_meta("base_pos")
		part.rotation = part.get_meta("base_rot")
		part.scale = part.get_meta("base_scale")
		_base[p] = Vector3.ONE
	for e in _extras:
		e.queue_free()
	_extras.clear()

func _target(sub: String) -> Node3D:
	if _sub.has(sub):
		return _sub[sub]
	return _parts.get(sub, null)

## Reshape the body for every owned mutation; `bumps` tumor bumps on the belly.
func apply(ids: Array, bumps: int = 0) -> void:
	_reset_shapes()
	applied.clear()
	for id in ids:
		applied.append(String(id))
		_apply_one(String(id), self, false)
	for i in range(bumps):
		_extras.append(_bump(i, false))
	for p in _parts.keys():
		_base[p] = (_parts[p] as Node3D).scale
	var face_mat: ShaderMaterial = _parts["face"].get_node("Head").material_override
	face_mat.set_shader_parameter("eye_scale", Vector2(_sub["eyes"].scale.x, _sub["eyes"].scale.y))
	face_mat.set_shader_parameter("jaw_scale", _sub["jaw"].scale)
	face_mat.set_shader_parameter("jaw_offset", _sub["jaw"].position - _sub["jaw"].get_meta("base_pos"))
	var mutated_eyes := "M24" in applied or "T5" in applied
	face_mat.set_shader_parameter("hide_eyes", mutated_eyes)
	for mesh in _sub["eyes"].get_children():
		mesh.visible = mutated_eyes
	_capture_rest_pose()

func _apply_one(id: String, _root: Node3D, ghost: bool) -> Node3D:
	var lk := look(id)
	var made: Node3D = null
	if not lk.is_empty() and not ghost:
		var n := _target(String(lk["sub"]))
		if n != null:
			n.scale *= lk.get("scale", Vector3.ONE)
			n.position += lk.get("pos", Vector3.ZERO)
			n.rotation_degrees += lk.get("rot", Vector3.ZERO)
	var e := _extra(id, ghost)
	if e != null:
		_extras.append(e)
		made = e
	return made

## Translucent preview of one mutation over the body (hover in the mirror).
## Built from a second copy of THIS body with the mutation applied on top of
## what is already owned, so the preview always has the current body shape
## and the real resulting form; only the changed part (and its extra pieces)
## is shown, slightly inflated so it reads over the skin.
func ghost(id: String) -> Node3D:
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GHOST_SHADER
	mat.shader = sh
	var g: FPMirrorBody = get_script().new()
	g.name = "Ghost_" + id
	g.set_process(false)
	add_child(g)
	g.build()
	if g._belt != null:
		g._belt.visible = false
	var ids: Array = applied.duplicate()
	if not id in ids:
		ids.append(id)
	g.apply(ids, 0)
	# which parts does this mutation change?
	var show := {}
	var lk := look(id)
	if not lk.is_empty():
		var n := g._target(String(lk["sub"]))
		var p := g._part_of(n)
		if p != "":
			show[p] = true
	for e in g._extras:
		if String(e.name) == "Mut_" + id:
			var p2 := g._part_of(e)
			if p2 != "":
				show[p2] = true
	var any := not show.is_empty()
	for p in g._parts.keys():
		var on := (not any) or show.has(p)
		for mi in (g._parts[p] as Node3D).find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			if m3.name == "Shimmer":
				m3.visible = false
				continue
			if m3.name == "Head" or String(m3.name).begins_with("EyeImage"):
				var original := m3.material_override as ShaderMaterial
				var face_preview := FDKSkinMaterial.make(1.0, true, true)
				for uniform in original.shader.get_shader_uniform_list():
					var value = original.get_shader_parameter(uniform.name)
					if value != null:
						face_preview.set_shader_parameter(uniform.name, value)
				face_preview.set_shader_parameter("ghost", true)
				m3.material_override = face_preview
			else:
				m3.material_override = mat
			m3.visible = on and (not String(m3.name).begins_with("EyeImage") or "M24" in ids or "T5" in ids)
		if on:
			(g._parts[p] as Node3D).scale *= 1.03
	return g

## Name of the mirror part a node sits under ("" if none).
func _part_of(n: Node) -> String:
	var p := n
	while p != null and p != self:
		if String(p.name).begins_with("Part_"):
			return String(p.name).substr(5)
		p = p.get_parent()
	return ""

func _bump(i: int, _ghost: bool) -> Node3D:
	var st := K.begin()
	var a := float(i) * 1.9
	var at := Vector3(0.06 + cos(a) * 0.05, -0.02 + sin(a) * 0.04, 0.105)
	K.blob(st, Transform3D.IDENTITY, at, Vector3(0.022, 0.02, 0.018), 0.2, 30 + i, Color(0.78, 0.48, 0.5), Color(0.62, 0.32, 0.36))
	var mi := K.add_mesh(_parts["belly"], "TumorBump%d" % i, K.finish(st), _skin)
	return mi

## Extra pieces a mutation adds (webbing, nails, trunk...). Built under the
## part they belong to.
func _extra(id: String, _ghost: bool) -> Node3D:
	var I := Transform3D.IDENTITY
	var st := K.begin()
	var parent: Node3D = null
	match id:
		"M03": # iron-filing irises: spiky grey star over each eye
			parent = _sub["eyes"]
			for sx in [-1, 1]:
				for k in range(8):
					var a := k * TAU / 8.0
					K.tube(st, I, [Vector3(sx * 0.04 + cos(a) * 0.004, sin(a) * 0.004, 0.008), Vector3(sx * 0.04 + cos(a) * 0.014, sin(a) * 0.014, 0.01)], [0.002, 0.0008], 3, [Color(0.3, 0.3, 0.34)], false)
		"M08": # webbing between fingers, reaching the tips
			parent = _sub["fingers_r"]
			for i in range(3):
				var x := -0.027 + i * 0.018
				K.quad(st, I, Vector3(x, 0.0, 0.0), Vector3(x + 0.018, 0.0, 0.0), Vector3(x + 0.018, 0.055, 0.045), Vector3(x, 0.055, 0.045), Vector3.BACK, Color(0.95, 0.55, 0.5))
		"M09": # thick yellow claws of nail
			parent = _sub["fingers_r"]
			for i in range(4):
				var x := -0.027 + i * 0.018
				var ln := 0.066 - absf(i - 1.3) * 0.01
				K.tube(st, I, [Vector3(x, ln * 0.7, 0.05), Vector3(x, ln * 0.85, 0.07), Vector3(x, ln * 0.8, 0.09)], [0.011, 0.009, 0.004], 4, [Color(0.85, 0.72, 0.28), Color(0.6, 0.5, 0.18)])
		"M13": # deep suction wrinkles on the palm
			parent = _sub["hand_r"]
			for k in range(6):
				var y := 0.008 + k * 0.013
				K.tube(st, I, [Vector3(-0.038, y, 0.016), Vector3(0.0, y + 0.005, 0.02), Vector3(0.038, y, 0.016)], [0.0035, 0.0045, 0.0035], 4, [Color(0.62, 0.36, 0.36)])
		"M14": # huge muscle lumps on the upper arms and pecs
			parent = _parts["arms"]
			for sx in [-1, 1]:
				K.blob(st, I, Vector3(sx * 0.25, -0.1, 0.03), Vector3(0.075, 0.085, 0.07), 0.3, 45, SKIN, SKIN_D)
				K.blob(st, I, Vector3(sx * 0.1, -0.08, 0.1), Vector3(0.09, 0.06, 0.05), 0.25, 44, SKIN, SKIN_D)
		"M15": # the jaw unhinges and hangs ~30 cm: stretched cheek skin and a
			# dark open throat down to the dropped chin
			parent = _parts["face"]
			for sx in [-1, 1]:
				K.tube(st, I, [Vector3(sx * 0.078, -0.03, 0.03), Vector3(sx * 0.07, -0.14, 0.09), Vector3(sx * 0.068, -0.28, 0.11), Vector3(sx * 0.082, -0.4, 0.1), Vector3(sx * 0.07, -0.45, 0.08)], [0.02, 0.016, 0.015, 0.02, 0.018], 5, [SKIN, SKIN_D, SKIN_D, SKIN, SKIN])
			K.quad(st, I, Vector3(-0.068, -0.05, 0.05), Vector3(0.068, -0.05, 0.05), Vector3(0.075, -0.42, 0.11), Vector3(-0.075, -0.42, 0.11), Vector3.BACK, Color(0.22, 0.03, 0.05))
			K.tube(st, I, [Vector3(0, -0.07, 0.06), Vector3(0.01, -0.2, 0.13), Vector3(0.0, -0.33, 0.155)], [0.022, 0.02, 0.016], 5, [Color(0.75, 0.3, 0.36)]) # slack tongue
		"M16", "M19": # heavy rippling folds across the belly
			parent = _parts["belly"]
			for k in range(4):
				var y := -0.07 + k * 0.04
				K.tube(st, I, [Vector3(-0.14, y, 0.07), Vector3(0.0, y + (0.015 if id == "M16" else -0.015), 0.118), Vector3(0.14, y, 0.07)], [0.01, 0.016, 0.01], 5, [SKIN_D])
		"M21": # plate-like muscle bands on the left forearm
			parent = _sub["forearm_l"]
			for k in range(6):
				var y := -0.02 - k * 0.035
				K.rbox(st, K.T(Vector3(0.0, y, 0.02 + k * 0.004)), Vector3(0.052, 0.01, 0.05), 0.004, Color(0.72, 0.55, 0.48), Color(0.55, 0.38, 0.34))
		"M22": # the alien hand: purple bruised knuckles
			parent = _sub["hand_l"]
			K.blob(st, I, Vector3(0, 0.08, 0.016), Vector3(0.045, 0.014, 0.012), 0.4, 46, Color(0.5, 0.3, 0.5), Color(0.4, 0.22, 0.4))
		"M23": # long stiff bristles on both arms
			parent = _parts["arms"]
			for sx in [-1, 1]:
				for k in range(14):
					var tt := float(k) / 13.0
					var base := Vector3(sx * (0.24 + 0.05 * tt), -0.26 * tt, 0.03 + 0.05 * tt)
					K.tube(st, I, [base, base + Vector3(sx * 0.06, 0.02, 0.03)], [0.003, 0.0008], 3, [Color(0.1, 0.08, 0.06)], false)
		"M25": # swollen veins across the forehead and temples
			parent = _parts["face"]
			var vc := Color(0.35, 0.3, 0.6)
			K.tube(st, I, [Vector3(-0.06, 0.09, 0.07), Vector3(-0.02, 0.06, 0.096), Vector3(0.01, 0.1, 0.09), Vector3(0.04, 0.07, 0.092)], [0.005, 0.006, 0.005, 0.004], 4, [vc])
			K.tube(st, I, [Vector3(0.02, 0.12, 0.06), Vector3(0.05, 0.09, 0.08), Vector3(0.085, 0.05, 0.06)], [0.005, 0.005, 0.004], 4, [vc])
			K.tube(st, I, [Vector3(-0.085, 0.05, 0.05), Vector3(-0.07, 0.1, 0.06)], [0.005, 0.004], 4, [vc])
		"M26": # little budding fingers all over the hand edge
			parent = _sub["hand_r"]
			for k in range(5):
				K.tube(st, I, [Vector3(0.04, 0.01 + k * 0.015, 0.0), Vector3(0.062, 0.016 + k * 0.015, 0.004)], [0.006, 0.004], 4, [SKIN])
		"M27": # elephant trunk nose hanging down past the chin
			parent = _sub["nose"]
			var pts: Array = []
			for k in range(8):
				var tt := float(k) / 7.0
				pts.append(Vector3(sin(tt * 2.0) * 0.02, -0.005 - tt * 0.34, 0.11 + sin(tt * PI) * 0.07))
			K.tube(st, I, pts, [0.024, 0.022, 0.02, 0.018, 0.016, 0.014, 0.012, 0.011], 6, [SKIN, SKIN_D])
		"M28": # boneless left arm: floppy wobble folds
			parent = _sub["forearm_l"]
			for k in range(4):
				K.blob(st, I, Vector3(0.0, -0.03 - k * 0.055, 0.02 + k * 0.008), Vector3(0.05, 0.022, 0.05), 0.45, 47 + k, SKIN, SKIN_D)
		"M30": # big pelican pouch under the chin
			parent = _parts["neck"]
			K.blob(st, I, Vector3(0, -0.02, 0.08), Vector3(0.1, 0.1, 0.08), 0.12, 48, Color(0.92, 0.7, 0.62), Color(0.8, 0.55, 0.5))
		"T1": # clicking tongue in an open mouth
			parent = _sub["jaw"]
			K.blob(st, I, Vector3(0, -0.01, 0.085), Vector3(0.03, 0.02, 0.01), 0.0, 49, Color(0.25, 0.04, 0.06), Color(0.2, 0.03, 0.05))
			K.blob(st, I, Vector3(0, -0.012, 0.1), Vector3(0.016, 0.006, 0.02), 0.0, 50, Color(0.8, 0.35, 0.4), Color(0.7, 0.3, 0.35))
		"T2": # third arm from the chest, with a hand
			parent = _parts["chest"]
			K.tube(st, I, [Vector3(0.0, -0.03, 0.1), Vector3(0.03, -0.1, 0.24), Vector3(0.0, -0.04, 0.4)], [0.05, 0.042, 0.034], 6, [SKIN_D, SKIN])
			K.rbox(st, K.T(Vector3(0.0, 0.0, 0.44), Vector3(-60, 0, 0)), Vector3(0.045, 0.055, 0.016), 0.01, SKIN, SKIN_D)
		"T3": # a toothy mouth across the right palm
			parent = _sub["hand_r"]
			K.blob(st, I, Vector3(0, 0.045, 0.016), Vector3(0.034, 0.018, 0.006), 0.1, 51, Color(0.6, 0.2, 0.22), Color(0.5, 0.15, 0.18))
			K.blob(st, I, Vector3(0, 0.045, 0.02), Vector3(0.026, 0.008, 0.004), 0.0, 52, Color(0.2, 0.02, 0.04), Color(0.15, 0.02, 0.03))
			for k in range(6):
				K.blob(st, I, Vector3(-0.02 + k * 0.008, 0.054, 0.022), Vector3(0.003, 0.004, 0.003), 0.0, 53, Color(0.95, 0.9, 0.75), Color(0.9, 0.85, 0.7))
		"T6": # jaw split top to bottom, open like a flower, lined with teeth
			parent = _sub["jaw"]
			K.quad(st, I, Vector3(-0.012, 0.03, 0.095), Vector3(0.012, 0.03, 0.095), Vector3(0.018, -0.075, 0.08), Vector3(-0.018, -0.075, 0.08), Vector3.BACK, Color(0.22, 0.02, 0.05))
			for sy in range(6):
				for sx in [-1, 1]:
					K.blob(st, I, Vector3(sx * 0.016, 0.02 - sy * 0.017, 0.1), Vector3(0.005, 0.006, 0.005), 0.0, 54, Color(0.95, 0.9, 0.75), Color(0.9, 0.85, 0.7))
		"T7": # thick, long ribs fanning out of the chest like a fan
			parent = _parts["chest"]
			var bone := Color(0.93, 0.88, 0.78)
			var bone_d := Color(0.78, 0.7, 0.6)
			for sx in [-1, 1]:
				for k in range(5):
					var y := 0.07 - k * 0.055
					var sp := 1.0 - k * 0.08
					K.tube(st, I, [Vector3(sx * 0.1, y, 0.09), Vector3(sx * 0.24 * sp, y + 0.03, 0.17), Vector3(sx * 0.4 * sp, y + 0.07, 0.19), Vector3(sx * 0.52 * sp, y + 0.12, 0.13)], [0.026, 0.024, 0.019, 0.012], 5, [bone, bone, bone_d])
		_:
			return null
	var mi := K.add_mesh(parent, "Mut_" + id, K.finish(st, 6.0), _skin)
	return mi

func _face_texture(head: MeshInstance3D) -> void:
	var arrays := head.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv := PackedVector2Array()
	for v in verts:
		uv.append(Vector2(v.x / 0.192 + 0.5, (0.138 - v.y) / 0.238))
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	head.mesh = mesh
	var mat := FDKSkinMaterial.make()
	mat.set_shader_parameter("face", true)
	mat.set_shader_parameter("face_tex", load("res://main/art/textures/player_face_ps1.png"))
	head.material_override = mat
