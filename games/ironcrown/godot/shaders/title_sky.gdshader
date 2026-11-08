// 主菜单的天（2026-11-08）：深蓝到地平线发青的渐变、星、慢慢飘的极光、月晕；北边地平线上冬井那一点冷光
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.012, 0.02, 0.055);
uniform vec3 mid_color : source_color = vec3(0.04, 0.07, 0.13);
uniform vec3 horizon_color : source_color = vec3(0.16, 0.22, 0.30);
uniform vec3 ground_color : source_color = vec3(0.05, 0.06, 0.08);
uniform vec3 aurora_a : source_color = vec3(0.10, 0.75, 0.55);
uniform vec3 aurora_b : source_color = vec3(0.35, 0.45, 0.95);
uniform vec3 moon_dir = vec3(0.35, 0.5, -0.8);
uniform vec3 well_dir = vec3(0.05, 0.0, -1.0);
uniform float motion = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	float t = TIME * motion;
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon_color, mid_color, smoothstep(0.0, 0.18, h));
		col = mix(col, top_color, smoothstep(0.15, 0.75, h));
		// 星：按方向分格，每格一颗，亮度不一，慢慢闪
		vec2 sp = vec2(atan(d.x, d.z) * 90.0, h * 140.0);
		vec2 cell = floor(sp);
		float r = hash(cell);
		vec2 c = fract(sp) - 0.5 - (vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5) * 0.6;
		float star = smoothstep(0.09, 0.0, length(c)) * step(0.93, r) * smoothstep(0.05, 0.35, h);
		star *= 0.6 + 0.4 * sin(t * (1.0 + r * 3.0) + r * 40.0);
		col += vec3(0.85, 0.9, 1.0) * star * 1.4;
		// 极光：几道帘子，从左上往右垂
		vec2 ap = vec2(atan(d.x, d.z), h);
		float curtain = 0.0;
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float wave = sin(ap.x * (3.0 + fi) + t * (0.04 + fi * 0.015) + fbm(vec2(ap.x * 2.0 + fi * 5.0, t * 0.03)) * 3.0);
			float band = smoothstep(0.32, 0.0, abs(h - (0.30 + 0.08 * fi + 0.06 * wave)));
			float rays = 0.55 + 0.45 * fbm(vec2(ap.x * 40.0 + fi * 9.0, t * 0.08));
			curtain += band * rays * (0.55 - fi * 0.13);
		}
		float side = smoothstep(-0.2, 0.9, -d.x * 0.6 - d.z * 0.5);       // 北边、西北边强一些
		col += mix(aurora_a, aurora_b, smoothstep(0.25, 0.6, h)) * curtain * side * 0.22;
		// 月晕
		float m = max(dot(d, normalize(moon_dir)), 0.0);
		col += vec3(0.75, 0.82, 1.0) * (smoothstep(0.99965, 0.99975, m) * 2.2 + pow(m, 220.0) * 0.25 + pow(m, 12.0) * 0.06);
		// 北边地平线上冬井那一点冷光
		float w = max(dot(normalize(vec3(d.x, 0.0, d.z)), normalize(well_dir)), 0.0);
		col += vec3(0.55, 0.75, 1.0) * pow(w, 60.0) * exp(-h * 18.0) * 0.55;
	} else {
		col = mix(horizon_color * 0.6, ground_color, smoothstep(0.0, -0.2, h));
	}
	COLOR = col;
}
