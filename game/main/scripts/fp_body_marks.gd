class_name FPBodyMarks
extends RefCounted

## Body hair and blood painted over the whole body (mirror body, Tab doll,
## first-person belly and briefs). One overlay material per body so the hair
## density and the blood amount are body-wide uniforms; each mesh says with
## instance uniforms how early it bleeds (`reach`), how hairy it is
## (`hair_w`), which side is its front and which hair/blood pattern it uses.
##
## Hair: short dark vertical dashes whose density follows the arm hair (the
## mutation-point currency): hair = arm hair points / FPBodyHair.BODY_FULL.
## Blood: the same patchy smear as FPHandBlood plus downward drip runs,
## creeping from the hands and mouth over chest and belly to the legs as the
## hand blood amount rises (0..1). The hands keep their own FPHandBlood.

const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_disabled, unshaded;
uniform float blood : hint_range(0.0, 1.0) = 0.0;
uniform float hair : hint_range(0.0, 1.0) = 0.0;
uniform vec4 hair_col : source_color = vec4(0.1, 0.065, 0.045, 1.0);
uniform bool face = false;
uniform vec3 jaw_scale = vec3(1.0);
uniform vec3 jaw_offset = vec3(0.0);
instance uniform float reach = 0.3;   // 1 = bloodied first .. 0 = last
instance uniform float hair_w = 0.0;  // how hairy this part is
instance uniform float front = 1.0;   // +1: the mesh's front is +Z, -1: -Z
instance uniform float shape = 0.0;   // 0 all over, 1 chest, 2 belly, 3 mouth, 4 back of limb sparse
varying vec3 p;
float h(vec3 q) { return fract(sin(dot(q, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float n3(vec3 q) {
	vec3 i = floor(q); vec3 f = fract(q); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h(i), h(i + vec3(1,0,0)), f.x), mix(h(i + vec3(0,1,0)), h(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h(i + vec3(0,0,1)), h(i + vec3(1,0,1)), f.x), mix(h(i + vec3(0,1,1)), h(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() {
	if (face) {
		// the same jaw reshape as the face skin (FDKSkinMaterial)
		float jaw_weight = 1.0 - smoothstep(-0.07, 0.01, VERTEX.y);
		vec3 jaw_pivot = vec3(0.0, -0.05, 0.0);
		VERTEX += ((VERTEX - jaw_pivot) * (jaw_scale - vec3(1.0)) + jaw_offset) * jaw_weight;
	}
	p = VERTEX;
}
void fragment() {
	float zf = p.z * front;
	// --- hair: short vertical dashes, thicker where the part is hairier
	float region = 1.0;
	if (shape == 1.0) region = smoothstep(-0.01, 0.05, zf) * (1.0 - smoothstep(0.05, 0.13, abs(p.x)));
	else if (shape == 2.0) region = smoothstep(0.0, 0.05, zf) * (0.3 + 0.7 * (1.0 - smoothstep(0.012, 0.04, abs(p.x))));
	else if (shape == 3.0) region = 0.0;
	float dens = clamp(hair * hair_w * region, 0.0, 1.0);
	float hs = n3(vec3(p.x * 300.0, p.y * 55.0, p.z * 300.0)) * 0.8 + n3(vec3(p.x * 90.0, p.y * 20.0, p.z * 90.0)) * 0.2;
	// sqrt: a few dozen arm hairs already show on the body, a full arm is thick
	float t = 1.0 - 0.42 * sqrt(dens);
	float mh = smoothstep(t, t + 0.03, hs) * step(0.001, dens);
	// a soft darker tone where it is hairy: what still reads in the low-res
	// mirror, where single hairs are smaller than a texel
	float tone = dens * 0.5 * (0.55 + 0.45 * n3(p * 35.0));
	// --- blood: smears plus runs dripping down
	float n = n3(p * 24.0) * 0.65 + n3(p * 80.0) * 0.35;
	float drip = n3(vec3(p.x * 90.0, p.y * 6.0, p.z * 90.0));
	float r = reach;
	if (shape == 3.0) {
		// mouth: lips, chin and the front of the jaw only
		float mouth = smoothstep(0.03, 0.07, zf) * (1.0 - smoothstep(-0.02, 0.0, p.y)) * (1.0 - smoothstep(0.035, 0.07, abs(p.x)));
		r = mix(-2.0, reach, mouth);
	}
	float b = blood - (1.0 - r) - 0.36 - (n - 0.5) * 0.9 - (0.5 - drip) * 0.5;
	float mb = smoothstep(0.0, 0.08, b) * step(0.001, blood);
	vec3 fresh = vec3(0.42, 0.02, 0.03);
	vec3 dried = vec3(0.22, 0.03, 0.03);
	vec3 bc = mix(fresh, dried, n);
	ALBEDO = mix(hair_col.rgb, bc, mb);
	ALPHA = max(max(mh * 0.92, tone), mb * 0.85);
}
"""

static var _shader: Shader

static func make_material() -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	return m

## Overlay `mat` on `mi` with this part's blood reach and hair weight.
static func paint(mi: MeshInstance3D, mat: ShaderMaterial, reach: float, hair_w: float, front: float = 1.0, shape: float = 0.0) -> void:
	mi.material_overlay = mat
	mi.set_instance_shader_parameter("reach", reach)
	mi.set_instance_shader_parameter("hair_w", hair_w)
	mi.set_instance_shader_parameter("front", front)
	mi.set_instance_shader_parameter("shape", shape)

## Body hair density from the arm hair (mutation points): 0..1.
static func hair_density(points: int) -> float:
	return clampf(float(points) / float(FPBodyHair.BODY_FULL), 0.0, 1.0)
