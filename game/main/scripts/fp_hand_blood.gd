class_name FPHandBlood
extends RefCounted

## Blood on the first-person hands (spec 01: tearing flesh bloodies the hands;
## spec 03 §5: washing at the sink wipes it off). A translucent overlay
## material on the hand meshes: patchy dark-red smears that start at the
## fingertips and creep toward the wrist as `amount` (0..1) rises.

const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, depth_test_disabled, cull_back, specular_disabled, unshaded;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
instance uniform float along = 0.5; // 1 = fingertip segment .. 0 = forearm
varying vec3 p;
float h(vec3 q) { return fract(sin(dot(q, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float n3(vec3 q) {
	vec3 i = floor(q); vec3 f = fract(q); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h(i), h(i + vec3(1,0,0)), f.x), mix(h(i + vec3(0,1,0)), h(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h(i + vec3(0,0,1)), h(i + vec3(1,0,1)), f.x), mix(h(i + vec3(0,1,1)), h(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() { p = VERTEX; }
void fragment() {
	float n = n3(p * 60.0) * 0.6 + n3(p * 170.0) * 0.4;
	
	float m = smoothstep(0.0, 0.1, amount - (1.0 - along) * 0.7 - n * 0.6);
	m *= step(0.001, amount);
	vec3 fresh = vec3(0.42, 0.02, 0.03);
	vec3 dried = vec3(0.22, 0.03, 0.03);
	ALBEDO = mix(fresh, dried, n);
	ALPHA = m * 0.82;
}
"""

static var _shader: Shader

## Overlay material with the blood shader. One per rig so amounts differ.
static func make_material() -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	return m

## Puts `mat` as the overlay on every hand mesh (palm, finger segments,
## forearm) under HandRight/HandLeft of `rig`.
static func attach(rig: Node, mat: ShaderMaterial) -> int:
	var n := 0
	for side in ["HandRight", "HandLeft"]:
		var root := rig.get_node_or_null(side)
		if root == null:
			continue
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var nm := String(mi.name)
			if nm == "Palm" or nm == "Seg" or nm == "Forearm":
				(mi as MeshInstance3D).material_overlay = mat
				(mi as MeshInstance3D).set_instance_shader_parameter("along", _along_of(mi))
				n += 1
	return n

static func set_amount(mat: ShaderMaterial, amount: float) -> void:
	if mat != null:
		mat.set_shader_parameter("amount", clampf(amount, 0.0, 1.0))

## How close to the fingertips a hand mesh is, from its joint name.
static func _along_of(mi: Node) -> float:
	var nm := String(mi.name)
	if nm == "Forearm":
		return 0.05
	if nm == "Palm":
		return 0.4
	var j := String(mi.get_parent().name)
	match j:
		"Finger3", "Thumb3":
			return 1.0
		"Finger2", "Thumb2":
			return 0.8
		_:
			return 0.62