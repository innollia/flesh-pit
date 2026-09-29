extends RefCounted

## W27: danger shown without words (spec 07 §1).
## - Tissue attack: health lives on the hands. Bruise overlay (blue-purple
##   blotches from the back of the hand outward) grows as health drops and
##   fades as it regenerates. Chained as next_pass on the blood overlay so
##   both show at once.
## - Crush: no screen-edge effect (spec 07 §1). The body shows it: the hands
##   are pressed together, the view is squeezed (FOV narrows) and trembles
##   as crush_progress() rises. The canary cry carries the early warning.

const BRUISE_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, depth_test_disabled, cull_back, unshaded;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
instance uniform float along = 0.5;
varying vec3 p;
float h(vec3 q) { return fract(sin(dot(q, vec3(12.9, 78.2, 37.7))) * 43758.5453); }
float n3(vec3 q) {
	vec3 i = floor(q); vec3 f = fract(q); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h(i), h(i + vec3(1,0,0)), f.x), mix(h(i + vec3(0,1,0)), h(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h(i + vec3(0,0,1)), h(i + vec3(1,0,1)), f.x), mix(h(i + vec3(0,1,1)), h(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() { p = VERTEX; }
void fragment() {
	float n = n3(p * 160.0) * 0.7 + n3(p * 520.0) * 0.3;
	// bruises bloom on palm/back of hand first (along ~0.4), then spread
	float m = smoothstep(0.0, 0.08, amount * 0.55 - n * 0.95 + 0.08);
	m *= step(0.001, amount);
	vec3 fresh = vec3(0.30, 0.10, 0.28);
	vec3 deep = vec3(0.14, 0.10, 0.26);
	ALBEDO = mix(fresh, deep, n);
	ROUGHNESS = 0.7;
	ALPHA = m * 0.55;
}
"""

var main: Node
var bruise_mat: ShaderMaterial
var _base_fov: float = -1.0
var _t: float = 0.0

func setup(p_main: Node) -> void:
	main = p_main
	var sh := Shader.new()
	sh.code = BRUISE_SHADER
	bruise_mat = ShaderMaterial.new()
	bruise_mat.shader = sh
	var blood = main.get("hand_blood_mat")
	if blood is ShaderMaterial:
		(blood as ShaderMaterial).next_pass = bruise_mat
	else:
		_attach_own()
	main.set_meta("bruise_attached", true)

## No blood overlay in this build: put the bruise overlay on the hand meshes
## itself (chained after any overlay already there).
func _attach_own() -> void:
	var rig: Node = main.get("hands_rig")
	if rig == null:
		return
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.material_overlay == null:
			m.material_overlay = bruise_mat
		elif m.material_overlay is ShaderMaterial and (m.material_overlay as ShaderMaterial).next_pass == null:
			(m.material_overlay as ShaderMaterial).next_pass = bruise_mat

## 0 = unhurt .. 1 = about to die, from hazard health.
func bruise_amount() -> float:
	var hz = main.get("hazard")
	if hz == null:
		return 0.0
	return clampf(1.0 - float(hz.get("health")) / 100.0, 0.0, 1.0)

func tick(delta: float) -> void:
	if main == null:
		return
	_t += delta
	bruise_mat.set_shader_parameter("amount", bruise_amount())
	var cam: Camera3D = main.player.camera
	if _base_fov < 0.0:
		_base_fov = cam.fov
	var c := clampf(float(main.call("crush_progress")), 0.0, 1.0)
	cam.fov = _base_fov * (1.0 - 0.22 * c)
	cam.h_offset = sin(_t * 31.0) * 0.006 * c
	cam.v_offset = sin(_t * 23.0 + 1.3) * 0.005 * c
	# (hands stay in view so the bruises read; the squeeze is the camera's)
