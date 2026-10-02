class_name FDKSkinMaterial
extends RefCounted

## One colour pipeline for world body, face, belly and camera-attached hands.
const SHADER := """shader_type spatial;
render_mode unshaded, cull_back, blend_mix;
uniform sampler2D skin_tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D face_tex : source_color, filter_nearest;
uniform bool face = false;
uniform bool painted = true;
uniform bool use_vertex_color = true;
uniform vec2 eye_scale = vec2(1.0);
uniform vec3 jaw_scale = vec3(1.0);
uniform vec3 jaw_offset = vec3(0.0);
uniform bool eye_patch = false;
uniform bool hide_eyes = false;
uniform bool ghost = false;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 skin_color : source_color = vec4(0.88, 0.72, 0.62, 1.0);
uniform float viewmodel_squash = 1.0;
uniform float wet = 0.0;
varying vec3 local_normal;
void vertex() {
    local_normal = NORMAL;
    if (face && !eye_patch) {
        float jaw_weight = 1.0 - smoothstep(-0.07, 0.01, VERTEX.y);
        vec3 jaw_pivot = vec3(0.0, -0.05, 0.0);
        VERTEX += ((VERTEX-jaw_pivot)*(jaw_scale-vec3(1.0))+jaw_offset)*jaw_weight;
    }
    vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    v.xyz *= viewmodel_squash;
    POSITION = PROJECTION_MATRIX * v;
    if (viewmodel_squash < 1.0 && POSITION.w > 0.0001) {
        POSITION.xy = floor(POSITION.xy / POSITION.w * 130.0 + 0.5) / 130.0 * POSITION.w;
    }
}
void fragment() {
    vec3 base = painted && use_vertex_color ? COLOR.rgb : skin_color.rgb;
    // Original body paint and original body texture are authoritative.
    vec3 tex = texture(skin_tex, UV).rgb;
    vec3 col = base * mix(vec3(1.0), tex, 0.5);
    ALPHA = 1.0;
    if (face) {
        vec2 uv = UV;
        vec3 ink = texture(face_tex, uv).rgb;
        // Keep the image's dark facial markings, discard its generated skin tint.
        float marking = clamp(dot(ink, vec3(0.299,0.587,0.114)) / 0.55, 0.0, 1.0);
        if (hide_eyes && UV.y > 0.39 && UV.y < 0.60 && (abs(UV.x-0.325)<0.14 || abs(UV.x-0.675)<0.14)) marking = 1.0;
        col *= mix(1.0, marking, smoothstep(0.05, 0.30, local_normal.z));
        if (eye_patch) {
            col = skin_color.rgb * marking;
            ALPHA = 1.0 - smoothstep(0.65, 0.95, marking);
        }
    }
    vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
    float light = 0.8 + 0.25 * max(dot(wn, normalize(vec3(0.0, 1.0, -0.4))), 0.0);
    ALBEDO = col * tint.rgb * light;
    // Preserve wet highlights on the camera-attached hands.
    float spec = pow(max(dot(normalize(NORMAL), normalize(VIEW+vec3(0.25,0.45,1.0))),0.0), 24.0);
    ALBEDO += vec3(0.16) * wet * spec;
    if (ghost) {
        ALBEDO = mix(ALBEDO, vec3(0.55,1.0,1.0), 0.55);
        ALPHA *= 0.70;
    }
}
"""
static var _shader: Shader
static var _transparent_shader: Shader
static func make(squash: float = 1.0, painted: bool = true, transparent: bool = false) -> ShaderMaterial:
    if _shader == null:
        _shader = Shader.new()
        # Solid skin must write depth: transparent double-sided skin lets the
        # back of the head paint over its image face and wastes a sorting pass.
        var opaque_code := SHADER.replace("cull_back, blend_mix", "cull_disabled")
        var lines := PackedStringArray()
        for line in opaque_code.split("\n"):
            if not "ALPHA" in line:
                lines.append(line)
        _shader.code = "\n".join(lines)
        _transparent_shader = Shader.new()
        _transparent_shader.code = SHADER
    var mat := ShaderMaterial.new()
    mat.shader = _transparent_shader if transparent or not painted else _shader
    mat.set_shader_parameter("skin_tex", load("res://addons/flesh_dig_kit/textures/tex_skin_128.png"))
    mat.set_shader_parameter("viewmodel_squash", squash)
    mat.set_shader_parameter("painted", painted)
    mat.set_shader_parameter("use_vertex_color", true)
    return mat
