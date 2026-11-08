// 主菜单的石头、王座、地（2026-11-08）：朝上的面盖雪，侧面露出深色的石头；噪声打散雪线；可选沿法线鼓起来（石头不圆）
shader_type spatial;
render_mode diffuse_burley;

uniform vec3 rock_color : source_color = vec3(0.16, 0.16, 0.18);
uniform vec3 rock_color2 : source_color = vec3(0.26, 0.25, 0.27);
uniform vec3 snow_color : source_color = vec3(0.86, 0.9, 0.98);
uniform float snow_line = 0.55;
uniform float bumps = 0.0;
uniform float scale = 1.0;

varying vec3 wpos;
varying vec3 wnorm;

float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash3(i);
	float n100 = hash3(i + vec3(1, 0, 0));
	float n010 = hash3(i + vec3(0, 1, 0));
	float n110 = hash3(i + vec3(1, 1, 0));
	float n001 = hash3(i + vec3(0, 0, 1));
	float n101 = hash3(i + vec3(1, 0, 1));
	float n011 = hash3(i + vec3(0, 1, 1));
	float n111 = hash3(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}
float fbm3(vec3 p) {
	return vnoise3(p) * 0.55 + vnoise3(p * 2.1) * 0.28 + vnoise3(p * 4.3) * 0.17;
}

void vertex() {
	if (bumps > 0.0) {
		VERTEX += NORMAL * (fbm3(VERTEX * 1.6 * scale) - 0.5) * bumps;
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n = fbm3(wpos * 0.9);
	float fine = fbm3(wpos * 6.0);
	float up = wnorm.y + (n - 0.5) * 0.5;
	float snow = smoothstep(snow_line - 0.08, snow_line + 0.08, up);
	vec3 rock = mix(rock_color, rock_color2, fine) * (0.8 + 0.4 * n);
	ALBEDO = mix(rock, snow_color * (0.92 + 0.08 * fine), snow);
	ROUGHNESS = mix(0.92, 0.55, snow);
	SPECULAR = mix(0.25, 0.5, snow);
}
