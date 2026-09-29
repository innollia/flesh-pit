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
const SKIN := Color(1.0, 0.86, 0.76)
const SKIN_D := Color(0.95, 0.8, 0.7)

const SHIMMER_SHADER := "shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 col : source_color = vec4(0.75, 0.45, 1.0, 1.0);
uniform float strength = 0.7;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	float s = sin(dot(lp, vec3(21.0, 34.0, 13.0)) - TIME * 3.2) * 0.5 + 0.5;
	float s2 = sin(dot(lp, vec3(-17.0, 29.0, 23.0)) - TIME * 2.1) * 0.5 + 0.5;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.5);
	float glint = smoothstep(0.55, 1.0, s) * 0.6;
	ALBEDO = col.rgb * strength * (0.1 + glint) * (0.2 + rim * 1.6);
}"
const GHOST_SHADER := "shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
uniform vec4 col : source_color = vec4(0.55, 1.0, 1.0, 0.75);
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.2);
	ALBEDO = col.rgb;
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

func _ready() -> void:
	build()

func build() -> void:
	if not _parts.is_empty():
		return
	_paint = _matte("res://addons/flesh_dig_kit/textures/tex_skin_128.png", 0.0)
	_skin = _matte("res://addons/flesh_dig_kit/textures/tex_skin_128.png", 1.0)
	var I := Transform3D.IDENTITY
	# --- face (head, jaw, eyes, nose): smooth egg head, readable features
	var face := _part("face", Vector3(0, 1.62, 0))
	var st := K.begin()
	K.lathe(st, K.T(Vector3(0, -0.1, 0), Vector3.ZERO, Vector3(1.0, 1.0, 1.08)), [Vector2(0.0, 0.0), Vector2(0.05, 0.01), Vector2(0.085, 0.06), Vector2(0.097, 0.12), Vector2(0.093, 0.17), Vector2(0.07, 0.21), Vector2(0.035, 0.232), Vector2(0.0, 0.236)], 20, [SKIN_D, SKIN, SKIN, SKIN, SKIN])
	_mesh(face, "Head", st)

	st = K.begin()
	for sx in [-1, 1]:
		K.lathe(st, K.T(Vector3(sx * 0.097, 0.02, -0.005), Vector3(0, 0, 90 * sx), Vector3(1.0, 1.0, 0.5)), [Vector2(0.0, 0.0), Vector2(0.02, 0.004), Vector2(0.022, 0.012), Vector2(0.0, 0.016)], 10, [SKIN_D, SKIN]) # ears
		K.tube(st, I, [Vector3(sx * 0.02, 0.07, 0.098), Vector3(sx * 0.045, 0.074, 0.094), Vector3(sx * 0.064, 0.068, 0.085)], [0.004, 0.005, 0.003], 5, [Color(0.55, 0.4, 0.34)]) # brow ridges (bald: skin-toned)
	_mesh(face, "Head", st)
	var eyes := _subpivot(face, "eyes", Vector3(0, 0.045, 0.09))
	st = K.begin()
	for sx in [-1, 1]:
		K.lathe(st, K.T(Vector3(sx * 0.04, 0, 0), Vector3(90, 0, 0), Vector3(1.4, 1.0, 0.8)), [Vector2(0.0, -0.004), Vector2(0.012, 0.0), Vector2(0.0, 0.006)], 12, [Color(0.96, 0.95, 0.92)])
		K.lathe(st, K.T(Vector3(sx * 0.04, 0, 0.004), Vector3(90, 0, 0)), [Vector2(0.0, 0.0), Vector2(0.0075, 0.002), Vector2(0.0, 0.004)], 10, [Color(0.28, 0.18, 0.1)])
		K.lathe(st, K.T(Vector3(sx * 0.04, 0, 0.0065), Vector3(90, 0, 0)), [Vector2(0.0, 0.0), Vector2(0.0035, 0.001), Vector2(0.0, 0.002)], 8, [Color(0.04, 0.03, 0.03)])
	_mesh(eyes, "Eyes", st, true)
	st = K.begin()
	K.tube(st, I, [Vector3(0, 0.05, 0.1), Vector3(0, 0.02, 0.112), Vector3(0, 0.0, 0.117)], [0.009, 0.012, 0.015], 8, [SKIN, SKIN_D])
	_mesh(_subpivot(face, "nose", Vector3.ZERO), "Nose", st)
	var jaw := _subpivot(face, "jaw", Vector3(0, -0.05, 0.0))
	st = K.begin()
	K.lathe(st, K.T(Vector3(0, -0.05, 0.012), Vector3.ZERO, Vector3(1.0, 1.0, 1.0)), [Vector2(0.0, 0.0), Vector2(0.035, 0.006), Vector2(0.065, 0.035), Vector2(0.085, 0.07), Vector2(0.0, 0.07)], 18, [SKIN_D, SKIN, SKIN])
	K.tube(st, I, [Vector3(-0.024, -0.005, 0.098), Vector3(0.0, -0.009, 0.103), Vector3(0.024, -0.005, 0.098)], [0.004, 0.006, 0.004], 6, [Color(0.68, 0.36, 0.36)]) # lips
	_mesh(jaw, "Jaw", st)
	# --- neck
	var neck := _part("neck", Vector3(0, 1.47, 0))
	st = K.begin()
	K.lathe(st, K.T(Vector3(0, -0.07, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.9)), [Vector2(0.066, 0.0), Vector2(0.052, 0.05), Vector2(0.047, 0.1), Vector2(0.05, 0.14)], 16, [SKIN_D, SKIN])
	_mesh(neck, "Neck", st)
	# --- chest: one smooth lathed trunk, flattened front to back
	var chest := _part("chest", Vector3(0, 1.28, 0))
	st = K.begin()
	K.lathe(st, K.T(Vector3(0, -0.15, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.62)), [Vector2(0.16, 0.0), Vector2(0.17, 0.06), Vector2(0.185, 0.14), Vector2(0.19, 0.2), Vector2(0.16, 0.25), Vector2(0.09, 0.28), Vector2(0.0, 0.29)], 24, [SKIN_D, SKIN, SKIN, SKIN])
	for sx in [-1, 1]:
		K.lathe(st, K.T(Vector3(sx * 0.075, 0.015, 0.112), Vector3(90, 0, 0)), [Vector2(0.0, 0.0), Vector2(0.011, 0.002), Vector2(0.0, 0.004)], 10, [Color(0.72, 0.46, 0.42)])
		K.tube(st, I, [Vector3(sx * 0.02, 0.1, 0.1), Vector3(sx * 0.1, 0.11, 0.08), Vector3(sx * 0.16, 0.1, 0.05)], [0.006, 0.007, 0.004], 5, [SKIN_D]) # collarbones
	_mesh(chest, "Chest", st)
	var sh := _subpivot(chest, "shoulders", Vector3(0, 0.08, 0))
	st = K.begin()
	for sx in [-1, 1]:
		K.blob(st, I, Vector3(sx * 0.19, 0, 0), Vector3(0.07, 0.06, 0.065), 0.0, 13, SKIN, SKIN)
	_mesh(sh, "Shoulders", st)
	# --- belly: continues the trunk down to the waist
	var belly := _part("belly", Vector3(0, 1.06, 0.0))
	st = K.begin()
	K.lathe(st, K.T(Vector3(0, -0.12, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.66)), [Vector2(0.0, 0.0), Vector2(0.11, 0.004), Vector2(0.15, 0.03), Vector2(0.163, 0.08), Vector2(0.162, 0.14), Vector2(0.161, 0.2), Vector2(0.0, 0.205)], 24, [SKIN, SKIN, SKIN])
	K.lathe(st, K.T(Vector3(0, -0.02, 0.105), Vector3(90, 0, 0)), [Vector2(0.0, 0.004), Vector2(0.008, 0.0), Vector2(0.0, -0.003)], 10, [Color(0.55, 0.34, 0.3)]) # navel
	_mesh(belly, "Belly", st)
	# --- arms (upper arms hanging at the sides, both)
	var arms := _part("arms", Vector3(0, 1.36, 0))
	for sx in [-1, 1]:
		var ua := _subpivot(arms, "upper_" + ("r" if sx > 0 else "l"), Vector3(sx * 0.2, 0, 0))
		st = K.begin()
		K.tube(st, I, [Vector3(0, 0.01, 0), Vector3(sx * 0.03, -0.1, 0.01), Vector3(sx * 0.06, -0.2, 0.03), Vector3(sx * 0.08, -0.26, 0.08)], [0.066, 0.06, 0.053, 0.048], 12, [SKIN, SKIN, SKIN, SKIN_D])
		_mesh(ua, "UpperArm", st)
	# --- hands: arms hang relaxed at the sides, palms turned to the thighs
	for side in ["right_hand", "left_hand"]:
		var sx := 1.0 if side == "right_hand" else -1.0
		var hp := _part(side, Vector3(sx * 0.28, 1.1, 0.08))
		var s := "r" if sx > 0 else "l"
		var fa := _subpivot(hp, "forearm_" + s, Vector3.ZERO)
		st = K.begin()
		K.blob(st, I, Vector3.ZERO, Vector3(0.04, 0.04, 0.04), 0.0, 17, SKIN_D, SKIN_D) # elbow
		K.tube(st, I, [Vector3(0, 0, 0), Vector3(-sx * 0.004, -0.08, 0.018), Vector3(-sx * 0.01, -0.16, 0.035), Vector3(-sx * 0.014, -0.235, 0.045)], [0.05, 0.048, 0.04, 0.032], 12, [SKIN_D, SKIN, SKIN, SKIN])
		_mesh(fa, "Forearm", st)
		var hand := _subpivot(hp, "hand_" + s, Vector3(-sx * 0.014, -0.24, 0.045))
		hand.rotation_degrees = Vector3(-10.0, -sx * 75.0, 180.0)
		hand.set_meta("base_rot", hand.rotation)
		hand.scale = Vector3.ONE * 1.25
		hand.set_meta("base_scale", hand.scale)
		st = K.begin()
		K.lathe(st, K.T(Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.35)), [Vector2(0.024, 0.0), Vector2(0.036, 0.02), Vector2(0.042, 0.05), Vector2(0.041, 0.075), Vector2(0.034, 0.088), Vector2(0.0, 0.09)], 14, [SKIN_D, SKIN, SKIN])
		K.tube(st, I, [Vector3(-sx * 0.033, 0.018, 0.0), Vector3(-sx * 0.05, 0.04, 0.012), Vector3(-sx * 0.055, 0.063, 0.02), Vector3(-sx * 0.055, 0.08, 0.022)], [0.013, 0.012, 0.01, 0.009], 8, [SKIN, SKIN, SKIN_D]) # thumb
		_mesh(hand, "Palm", st)
		var fing := _subpivot(hand, "fingers_" + s, Vector3(0, 0.082, 0.0))
		st = K.begin()
		for i in range(4):
			var x := -0.027 + i * 0.018
			var ln := 0.066 - absf(i - 1.3) * 0.01
			K.tube(st, I, [Vector3(x, 0, 0), Vector3(x * 1.02, ln * 0.42, 0.012), Vector3(x * 1.03, ln * 0.68, 0.032), Vector3(x * 1.03, ln * 0.78, 0.055)], [0.0095, 0.009, 0.0083, 0.0072], 8, [SKIN, SKIN, SKIN, Color(0.93, 0.78, 0.72)])
		_mesh(fing, "Fingers", st)
	# --- legs (not a mirror part): hips in plain briefs, thighs, knees, feet
	var legs := _part("legs", Vector3(0, 0.95, 0))
	st = K.begin()
	var cloth := Color(0.82, 0.84, 0.86)
	var cloth_d := Color(0.66, 0.68, 0.72)
	K.lathe(st, K.T(Vector3(0, -0.12, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.66)), [Vector2(0.0, 0.0), Vector2(0.15, 0.02), Vector2(0.168, 0.09), Vector2(0.163, 0.14), Vector2(0.0, 0.14)], 24, [cloth_d, cloth, cloth])
	for sx in [-1, 1]:
		K.tube(st, I, [Vector3(sx * 0.085, -0.06, 0.0), Vector3(sx * 0.088, -0.14, 0.005)], [0.083, 0.08], 14, [cloth, cloth_d])
	_mesh(legs, "Briefs", st, true)
	st = K.begin()
	for sx in [-1, 1]:
		var hip := Vector3(sx * 0.085, -0.08, 0.0)
		K.tube(st, I, [hip, Vector3(sx * 0.09, -0.3, 0.01), Vector3(sx * 0.085, -0.46, 0.02)], [0.078, 0.066, 0.05], 14, [SKIN, SKIN, SKIN_D]) # thigh
		K.blob(st, I, Vector3(sx * 0.085, -0.47, 0.035), Vector3(0.045, 0.045, 0.04), 0.0, 60, SKIN, SKIN_D) # knee
		K.tube(st, I, [Vector3(sx * 0.085, -0.48, 0.015), Vector3(sx * 0.083, -0.6, -0.005), Vector3(sx * 0.08, -0.74, 0.0), Vector3(sx * 0.078, -0.87, 0.005)], [0.047, 0.05, 0.038, 0.03], 12, [SKIN_D, SKIN, SKIN, SKIN_D]) # shin
		K.tube(st, I, [Vector3(sx * 0.078, -0.9, -0.02), Vector3(sx * 0.082, -0.925, 0.04), Vector3(sx * 0.085, -0.935, 0.11)], [0.034, 0.036, 0.028], 10, [SKIN_D, SKIN, SKIN], true, 0.6) # foot
	_mesh(legs, "Legs", st)
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
	var n := K.pivot(self, "Part_" + p, at)
	_parts[p] = n
	_meshes[p] = []
	_base[p] = Vector3.ONE
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

# --- mutation looks -------------------------------------------------------

## id -> {sub: node to reshape, scale, pos (offset), rot (deg)}; extras are
## built by _extra(). Part pivots use the part name as sub.
static func look(id: String) -> Dictionary:
	match id:
		"M01": return {"sub": "belly", "scale": Vector3(1.18, 1.3, 1.25), "pos": Vector3(0, -0.035, 0.01)}
		"M02": return {"sub": "neck", "scale": Vector3(1.45, 1.0, 1.45)}
		"M04": return {"sub": "jaw", "scale": Vector3(1.4, 1.1, 1.15)}
		"M05": return {"sub": "shoulders", "scale": Vector3(0.78, 1.0, 1.0), "pos": Vector3(0, -0.015, 0.02)}
		"M06": return {"sub": "chest", "scale": Vector3(1.08, 1.12, 1.18)}
		"M07": return {"sub": "hand_r", "scale": Vector3(1.35, 1.05, 1.1)}
		"M10": return {"sub": "fingers_r", "scale": Vector3(1.0, 1.55, 1.0)}
		"M12": return {"sub": "forearm_r", "scale": Vector3(1.6, 1.0, 1.6)}
		"M14": return {"sub": "chest", "scale": Vector3(1.14, 1.06, 1.12)}
		"M15": return {"sub": "jaw", "scale": Vector3(1.05, 1.7, 1.1), "pos": Vector3(0, -0.03, 0.0)}
		"M18": return {"sub": "hand_r", "scale": Vector3(1.55, 0.75, 1.4), "rot": Vector3(0, 0, -35)}
		"M20": return {"sub": "upper_r", "rot": Vector3(-25, 0, 18)}
		"M24": return {"sub": "eyes", "scale": Vector3(1.6, 2.0, 1.4)}
		"M28": return {"sub": "forearm_l", "scale": Vector3(0.75, 1.0, 0.75), "rot": Vector3(40, 0, -25)}
		"T4": return {"sub": "belly", "scale": Vector3(1.45, 1.35, 1.5)}
		"T5": return {"sub": "eyes", "scale": Vector3(2.9, 1.2, 0.6), "pos": Vector3(0, 0.0, -0.05)}
	return {}

func _reset_shapes() -> void:
	for n in _sub.values():
		(n as Node3D).scale = n.get_meta("base_scale")
		(n as Node3D).position = n.get_meta("base_pos")
		(n as Node3D).rotation = n.get_meta("base_rot")
	for p in _parts.keys():
		(_parts[p] as Node3D).scale = Vector3.ONE
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
func ghost(id: String) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Ghost_" + id
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GHOST_SHADER
	mat.shader = sh
	var lk := look(id)
	if not lk.is_empty():
		var n := _target(String(lk["sub"]))
		if n != null:
			for c in n.get_children():
				if c is MeshInstance3D:
					var g := MeshInstance3D.new()
					g.mesh = (c as MeshInstance3D).mesh
					g.material_override = mat
					holder.add_child(g)
			var t := n.global_transform
			t.basis = t.basis * Basis.from_euler(lk.get("rot", Vector3.ZERO) * PI / 180.0).scaled(lk.get("scale", Vector3.ONE) * 1.02)
			t.origin += n.get_parent().global_transform.basis * lk.get("pos", Vector3.ZERO)
			holder.transform = global_transform.affine_inverse() * t
	add_child(holder)
	var e := _extra(id, true)
	if e != null:
		for mi in e.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = mat
		var t2 := e.global_transform
		e.get_parent().remove_child(e)
		holder.add_child(e)
		e.global_transform = t2
	if holder.get_child_count() == 0:
		# no visible change (e.g. no pain, dormancy): a faint whole-body veil
		for mi in _all_meshes():
			var g := MeshInstance3D.new()
			g.mesh = (mi as MeshInstance3D).mesh
			g.material_override = mat
			holder.add_child(g)
			g.global_transform = (mi as MeshInstance3D).global_transform.scaled_local(Vector3.ONE * 1.02)
	return holder

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
		"M03": # iron-filing irises
			parent = _sub["eyes"]
			for sx in [-1, 1]:
				for k in range(6):
					var a := k * TAU / 6.0
					K.blob(st, I, Vector3(sx * 0.037 + cos(a) * 0.009, sin(a) * 0.009, 0.012), Vector3(0.003, 0.003, 0.002), 0.3, 40 + k, Color(0.35, 0.35, 0.38), Color(0.2, 0.2, 0.22))
		"M08": # webbing between fingers
			parent = _sub["fingers_r"]
			for i in range(3):
				var x := -0.02 + i * 0.02
				K.quad(st, I, Vector3(x, 0.0, -0.002), Vector3(x + 0.02, 0.0, -0.002), Vector3(x + 0.02, 0.035, -0.006), Vector3(x, 0.035, -0.006), Vector3.BACK, Color(0.95, 0.6, 0.55, 0.8))
		"M09": # thick yellow nails
			parent = _sub["fingers_r"]
			for i in range(4):
				var x := -0.03 + i * 0.02
				var ln := 0.06 - absf(i - 1.5) * 0.008
				K.rbox(st, K.T(Vector3(x, ln - 0.004, 0.004)), Vector3(0.009, 0.011, 0.004), 0.002, Color(0.85, 0.75, 0.3), Color(0.65, 0.55, 0.2))
		"M13": # suction wrinkles on the palm
			parent = _sub["hand_r"]
			for k in range(5):
				var y := 0.012 + k * 0.014
				K.tube(st, I, [Vector3(-0.034, y, 0.016), Vector3(0.0, y + 0.004, 0.019), Vector3(0.034, y, 0.016)], [0.0025, 0.003, 0.0025], 4, [Color(0.7, 0.45, 0.42)])
		"M14": # muscle lumps on arms and chest
			parent = _parts["arms"]
			for sx in [-1, 1]:
				K.blob(st, I, Vector3(sx * 0.26, -0.1, 0.03), Vector3(0.06, 0.07, 0.055), 0.25, 45, SKIN, SKIN_D)
		"M16", "M19": # rippling folds across the belly
			parent = _parts["belly"]
			for k in range(3):
				var y := -0.05 + k * 0.045
				K.tube(st, I, [Vector3(-0.13, y, 0.07), Vector3(0.0, y + (0.01 if id == "M16" else -0.01), 0.112), Vector3(0.13, y, 0.07)], [0.006, 0.01, 0.006], 5, [SKIN_D])
		"M21": # plate-like muscle bands on the left forearm
			parent = _sub["forearm_l"]
			for k in range(5):
				var t := 0.15 + k * 0.15
				K.rbox(st, K.T(Vector3(0.03 * t, 0.12 * t + 0.02, 0.2 * t + 0.02)), Vector3(0.036, 0.008, 0.02), 0.003, Color(0.78, 0.6, 0.5), Color(0.6, 0.42, 0.36))
		"M22": # the alien hand: twitch marks on the left knuckles
			parent = _sub["hand_l"]
			K.blob(st, I, Vector3(0, 0.08, 0.016), Vector3(0.04, 0.008, 0.006), 0.4, 46, Color(0.62, 0.38, 0.4), Color(0.5, 0.3, 0.34))
		"M23": # stiff bristles on both arms
			parent = _parts["arms"]
			for sx in [-1, 1]:
				for k in range(10):
					var t := float(k) / 9.0
					var base := Vector3(sx * (0.24 + 0.05 * t), -0.26 * t, 0.03 + 0.05 * t)
					K.tube(st, I, [base, base + Vector3(sx * 0.03, 0.01, 0.02)], [0.002, 0.0008], 3, [Color(0.1, 0.08, 0.06)], false)
		"M25": # veins on the forehead
			parent = _parts["face"]
			K.tube(st, I, [Vector3(-0.04, 0.08, 0.085), Vector3(-0.01, 0.06, 0.098), Vector3(0.02, 0.085, 0.09)], [0.003, 0.004, 0.002], 4, [Color(0.35, 0.3, 0.55)])
			K.tube(st, I, [Vector3(0.01, 0.095, 0.085), Vector3(0.04, 0.07, 0.09)], [0.003, 0.002], 4, [Color(0.35, 0.3, 0.55)])
		"M26": # tiny budding fingers on the hands
			parent = _sub["hand_r"]
			for k in range(3):
				K.tube(st, I, [Vector3(0.042, 0.02 + k * 0.015, 0.0), Vector3(0.056, 0.024 + k * 0.015, 0.0)], [0.004, 0.003], 4, [SKIN])
		"M27": # elephant trunk nose
			parent = _sub["nose"]
			var pts: Array = []
			for k in range(8):
				var t := float(k) / 7.0
				pts.append(Vector3(sin(t * 2.0) * 0.015, -0.005 - t * 0.2, 0.1 + sin(t * PI) * 0.05))
			K.tube(st, I, pts, [0.02, 0.019, 0.017, 0.015, 0.013, 0.011, 0.01, 0.009], 7, [SKIN, SKIN_D])
		"M28": # boneless left arm: soft wobble folds
			parent = _sub["forearm_l"]
			for k in range(3):
				var t := 0.25 + k * 0.25
				K.blob(st, I, Vector3(0.03 * t, 0.12 * t, 0.2 * t), Vector3(0.04, 0.02, 0.04), 0.4, 47 + k, SKIN, SKIN_D)
		"M30": # pelican pouch under the chin
			parent = _parts["neck"]
			K.blob(st, I, Vector3(0, 0.0, 0.07), Vector3(0.07, 0.06, 0.055), 0.12, 48, Color(0.92, 0.7, 0.62), Color(0.8, 0.55, 0.5))
		"T1": # clicking tongue in an open mouth
			parent = _sub["jaw"]
			K.blob(st, I, Vector3(0, -0.01, 0.085), Vector3(0.022, 0.014, 0.008), 0.0, 49, Color(0.25, 0.04, 0.06), Color(0.2, 0.03, 0.05))
			K.blob(st, I, Vector3(0, -0.012, 0.092), Vector3(0.012, 0.005, 0.01), 0.0, 50, Color(0.8, 0.35, 0.4), Color(0.7, 0.3, 0.35))
		"T2": # third arm from the chest
			parent = _parts["chest"]
			K.tube(st, I, [Vector3(0.0, -0.03, 0.09), Vector3(0.02, -0.08, 0.2), Vector3(0.0, -0.02, 0.32)], [0.04, 0.035, 0.03], 8, [SKIN_D, SKIN])
			K.rbox(st, K.T(Vector3(0.0, 0.01, 0.35), Vector3(-60, 0, 0)), Vector3(0.04, 0.045, 0.014), 0.01, SKIN, SKIN_D)
		"T3": # a mouth in the right palm
			parent = _sub["hand_r"]
			K.blob(st, I, Vector3(0, 0.04, 0.016), Vector3(0.026, 0.012, 0.004), 0.1, 51, Color(0.6, 0.2, 0.22), Color(0.5, 0.15, 0.18))
			K.blob(st, I, Vector3(0, 0.04, 0.019), Vector3(0.018, 0.005, 0.003), 0.0, 52, Color(0.2, 0.02, 0.04), Color(0.15, 0.02, 0.03))
			for k in range(5):
				K.blob(st, I, Vector3(-0.012 + k * 0.006, 0.046, 0.02), Vector3(0.0025, 0.003, 0.002), 0.0, 53, Color(0.95, 0.9, 0.75), Color(0.9, 0.85, 0.7))
		"T6": # vertical split through the jaw
			parent = _sub["jaw"]
			K.tube(st, I, [Vector3(0, 0.02, 0.09), Vector3(0, -0.02, 0.098), Vector3(0, -0.065, 0.07)], [0.005, 0.007, 0.004], 5, [Color(0.25, 0.03, 0.05)])
			for sy in range(4):
				for sx in [-1, 1]:
					K.blob(st, I, Vector3(sx * 0.008, 0.01 - sy * 0.018, 0.096), Vector3(0.003, 0.004, 0.003), 0.0, 54, Color(0.95, 0.9, 0.75), Color(0.9, 0.85, 0.7))
		"T7": # ribs fanning out of the chest
			parent = _parts["chest"]
			for sx in [-1, 1]:
				for k in range(4):
					var y := 0.04 - k * 0.04
					K.tube(st, I, [Vector3(sx * 0.12, y, 0.07), Vector3(sx * 0.24, y + 0.02, 0.1), Vector3(sx * 0.33, y + 0.05, 0.08)], [0.01, 0.008, 0.004], 5, [Color(0.93, 0.88, 0.78)])
		_:
			return null
	var mi := K.add_mesh(parent, "Mut_" + id, K.finish(st, 6.0), _skin)
	return mi
