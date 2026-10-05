extends RefCounted

## W27: danger shown without words (spec 07 §1).
## - Tissue attack: health lives on the hands. Bruise overlay (blue-purple
##   small spots on the back of the hand and fingers; more spots, a little
##   larger, as health drops) grows as health drops and
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
	// a few small bruise spots on the back of the hand and fingers, not a
	// coat over the whole hand: the hand is cut into small cells and only
	// some cells (more as health drops) carry one round spot
	vec3 q = p * 22.0;
	vec3 cell = floor(q);
	vec3 f = fract(q) - 0.5;
	float pick = h(cell + vec3(7.1, 3.3, 5.9));
	float on = step(1.0 - amount * 0.28, pick);
	vec3 off = (vec3(h(cell + 1.7), h(cell + 4.1), h(cell + 9.3)) - 0.5) * 0.35;
	float r = 0.2 + 0.14 * h(cell + 2.2) * amount;
	float spot = 1.0 - smoothstep(r * 0.2, r, length(f - off));
	float n = n3(p * 420.0);
	float m = spot * on * (0.65 + 0.35 * n) * step(0.001, amount);
	vec3 fresh = vec3(0.42, 0.14, 0.24);
	vec3 deep = vec3(0.22, 0.12, 0.30);
	ALBEDO = mix(fresh, deep, n);
	ROUGHNESS = 0.7;
	ALPHA = m * 0.55;
}
"""

var main: Node
var bruise_mat: ShaderMaterial
var _base_fov: float = -1.0
var _t: float = 0.0
var _applied_offset := Vector2.ZERO
var _written_offset := Vector2(INF, INF)
var _written_fov := -1.0
var _camera: Camera3D

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
	apply_camera()

## Remove only this effect before the next frame's camera writers. An
## external absolute write is respected instead of subtracting a stale
## contribution from its new base. Calling this or apply_camera twice is safe.
func restore_camera() -> void:
	if not is_instance_valid(_camera): return
	if is_equal_approx(_camera.h_offset, _written_offset.x):
		_camera.h_offset -= _applied_offset.x
	if is_equal_approx(_camera.v_offset, _written_offset.y):
		_camera.v_offset -= _applied_offset.y
	if is_equal_approx(_camera.fov, _written_fov) and _base_fov >= 0.0:
		_camera.fov = _base_fov
	_applied_offset = Vector2.ZERO
	_written_offset = Vector2(INF, INF)
	_written_fov = -1.0

## Compose after hand/mutation camera writers, then constrain the terrain
## eye and sync mirrors. Production frame_pre_draw repeats this composition
## without advancing time, after a mutation's later child _process write.
## Shake lives in camera offsets; it never replaces the head/vomit pose.
func apply_camera(base_fov: float = -1.0) -> void:
	if main == null or not is_instance_valid(main.player) or not is_instance_valid(main.player.camera): return
	restore_camera()
	var cam: Camera3D = main.player.camera
	_camera = cam
	if base_fov >= 0.0:
		_base_fov = base_fov
	else:
		# Restore removes our previous squeeze only when no other writer has
		# changed it. Thus a live mutation FOV or a 66-degree toilet pose is
		# the new base, while repeated predraw composition cannot compound.
		_base_fov = cam.fov
	var c := clampf(float(main.call("crush_progress")), 0.0, 1.0)
	cam.fov = _base_fov * (1.0 - 0.22 * c)
	_applied_offset = Vector2(sin(_t * 31.0) * 0.006 * c, sin(_t * 23.0 + 1.3) * 0.005 * c)
	cam.h_offset += _applied_offset.x
	cam.v_offset += _applied_offset.y
	_written_offset = Vector2(cam.h_offset, cam.v_offset)
	_written_fov = cam.fov
	# (hands stay in view so the bruises read; the squeeze is the camera's)
