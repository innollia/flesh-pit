shader_type spatial;
// T1 echolocation (docs/spec/05-mutations.md, D02): the whole picture goes
// dark like a lidar view, and each tongue click sends a sphere out from the
// body. Where that sphere meets the walls a bright line runs over them, so the
// line climbs the walls as it grows, and it leaves fading contour lines behind
// that show the shape of the space. Spots the pulse sorted (thin, regrowing,
// about to squeeze, nerve) tint the lines near them; tumors blink through the
// flesh. Drawn as a quad that fills whatever camera renders it (the player's
// eye or each T5 fisheye face), reading that camera's own depth.
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 origin;
uniform float radius = 0.0; // the front of the newest click (m)
uniform float fade = 0.0; // 1 at the click, 0 by the next one
uniform float band = 0.14; // width of the front line (m)
uniform float spacing = 0.5; // contour lines left behind it (m)
uniform float darkness = 0.07; // how much of the normal picture shows
uniform vec4 line_color : source_color = vec4(0.55, 0.85, 1.0, 1.0);
uniform vec4 kind_colors[5];
uniform int mark_count = 0;
uniform vec4 marks[48]; // xyz world position, w = FPMutationApply.Echo kind
const int TUMOR = 4;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

void fragment() {
	vec3 base = texture(screen_tex, SCREEN_UV).rgb;
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	float lum = dot(base, vec3(0.3, 0.59, 0.11));
	vec3 col = vec3(lum * darkness) * vec3(0.6, 0.75, 1.0);
	if (-view.z < 0.12) {
		// the view-model hands sit squashed right at the eye: keep them readable
		col = base * 0.55;
	} else if (depth < 0.99999) {
		float d = distance(world, origin);
		float front = 1.0 - smoothstep(0.0, band, abs(d - radius));
		float behind = step(d, radius);
		float w = 0.03 * (1.0 + d * 0.15);
		float ring = 1.0 - smoothstep(0.0, w, abs(fract(d / spacing + 0.5) - 0.5) * spacing);
		float trail = behind * ring * fade * exp(-(radius - d) * 0.3);
		vec3 lc = line_color.rgb;
		for (int i = 0; i < mark_count; i++) {
			int kind = int(marks[i].w + 0.5);
			if (kind == TUMOR) {
				continue;
			}
			float k = 1.0 - smoothstep(0.25, 0.7, distance(world, marks[i].xyz));
			lc = mix(lc, kind_colors[kind].rgb, k);
		}
		col += lc * (front * 1.6 + trail * 0.9) * (0.35 + 0.65 * fade);
	}
	// tumors the front has passed blink through the flesh as red rings
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	for (int i = 0; i < mark_count; i++) {
		if (int(marks[i].w + 0.5) != TUMOR || distance(marks[i].xyz, origin) > radius) {
			continue;
		}
		vec4 c = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(marks[i].xyz, 1.0));
		if (c.w <= 0.0) {
			continue;
		}
		vec2 at = c.xy / c.w * 0.5 + 0.5;
		float r = length((SCREEN_UV - at) * vec2(aspect, 1.0));
		float blip = 1.0 - smoothstep(0.0, 0.006, abs(r - 0.035));
		col = mix(col, kind_colors[TUMOR].rgb, blip * (0.4 + 0.6 * fade));
	}
	ALBEDO = col;
	ALPHA = 1.0;
}
