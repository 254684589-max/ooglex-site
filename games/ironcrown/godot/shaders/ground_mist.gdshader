shader_type spatial;
// 长眠者脚下贴地的一层薄白雾（2026-11-07）：每个人脚下一片平放的方片（多实例，一次画完），
// 中间浓、边上淡成圆，再叠一层慢慢流动的噪声，许多片连起来就是一股贴地走的寒气。不写深度、不受光。
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.82, 0.88, 0.95, 1.0);
uniform float strength = 0.55;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 c = UV - vec2(0.5);
	float r = length(c) * 2.0;
	float disc = smoothstep(1.0, 0.25, r);
	vec2 wp = world_pos.xz * 0.35;
	float n = noise(wp + vec2(TIME * 0.12, TIME * 0.05)) * 0.6 + noise(wp * 2.3 - vec2(TIME * 0.09, 0.0)) * 0.4;
	ALBEDO = tint.rgb;
	ALPHA = disc * smoothstep(0.25, 0.85, n) * strength * COLOR.a;
}
