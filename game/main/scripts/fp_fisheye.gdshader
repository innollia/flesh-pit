shader_type canvas_item;
// T5 fish eye (docs/spec/05-mutations.md): an equidistant fisheye over the
// player's real view. Five 90-degree cameras (front, right, left, up, down,
// FPFisheyeView) cover the sphere out to 135 degrees from the view axis; this
// maps each screen pixel to an angle from the centre and samples the face that
// direction falls in. fov_deg is the full horizontal angle (200).

uniform sampler2D face_front : filter_nearest, repeat_disable;
uniform sampler2D face_right : filter_nearest, repeat_disable;
uniform sampler2D face_left : filter_nearest, repeat_disable;
uniform sampler2D face_up : filter_nearest, repeat_disable;
uniform sampler2D face_down : filter_nearest, repeat_disable;
uniform float fov_deg = 200.0;
uniform float aspect = 1.7778;

vec2 face_uv(vec3 l) {
	return vec2(l.x, -l.y) / -l.z * 0.5 + 0.5;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p.x *= aspect;
	float theta = length(p) / aspect * radians(fov_deg) * 0.5;
	vec2 dir2 = length(p) > 1e-5 ? normalize(p) : vec2(0.0);
	// camera space: x right, y up, looking down -z
	vec3 d = vec3(sin(theta) * dir2.x, -sin(theta) * dir2.y, -cos(theta));
	vec3 a = abs(d);
	vec4 c;
	if (-d.z >= a.x && -d.z >= a.y) {
		c = texture(face_front, face_uv(d));
	} else if (a.x >= a.y) {
		c = d.x > 0.0 ? texture(face_right, face_uv(vec3(d.z, d.y, -d.x)))
			: texture(face_left, face_uv(vec3(-d.z, d.y, d.x)));
	} else {
		c = d.y > 0.0 ? texture(face_up, face_uv(vec3(d.x, d.z, -d.y)))
			: texture(face_down, face_uv(vec3(d.x, -d.z, d.y)));
	}
	COLOR = vec4(c.rgb, 1.0);
}
