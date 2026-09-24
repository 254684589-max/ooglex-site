shader_type sky;
// 天空：天顶→地平线渐变 + 太阳光晕 + 程序云层 + 夜间星空。
// 反射 / 环境用的立方体贴图里不画云和星星（省性能），只有屏幕上的天空才画。

uniform vec3 top_color : source_color = vec3(0.22, 0.42, 0.72);
uniform vec3 horizon_color : source_color = vec3(0.8, 0.82, 0.86);
uniform vec3 ground_color : source_color = vec3(0.2, 0.2, 0.22);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.7);
uniform vec3 sun_dir = vec3(0.0, 0.5, 0.5);
uniform float sun_visible = 1.0;
uniform float haze = 1.0;
uniform float cloud_cover = 0.45;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shadow : source_color = vec3(0.5, 0.55, 0.65);
uniform float stars = 0.0;
uniform float drift = 0.0;
uniform float energy = 1.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	vec3 sd = normalize(sun_dir);
	float mu = max(dot(d, sd), 0.0);
	// 地平线附近更亮更暖（大气散射 / 雾霾）
	float h = pow(1.0 - clamp(y, 0.0, 1.0), 5.0);
	vec3 col = mix(top_color, horizon_color, h);
	// 太阳方向的地平线更亮
	float side = pow(mu, 3.0) * h;
	col += sun_color * side * 0.55 * haze;
	// 太阳光晕与日轮
	col += sun_color * (pow(mu, 12.0) * 0.35 * haze + pow(mu, 180.0) * 1.2) * sun_visible;
	col += sun_color * smoothstep(0.9993, 0.9996, mu) * 8.0 * sun_visible;
	if (y < 0.0) {
		col = mix(horizon_color, ground_color, smoothstep(0.0, 0.25, -y));
	}
	if (!AT_CUBEMAP_PASS && y > 0.0) {
		// 星星
		if (stars > 0.01) {
			vec2 sp = d.xz / (y + 0.4) * 180.0;
			float s = hash(floor(sp));
			float tw = smoothstep(0.985, 1.0, s) * smoothstep(0.35, 0.05, length(fract(sp) - 0.5));
			col += vec3(0.9, 0.92, 1.0) * tw * stars * smoothstep(0.0, 0.25, y);
		}
		// 云：把视线投到一个高空平面上取噪声
		if (cloud_cover > 0.01) {
			vec2 uv = d.xz / (y + 0.12) * 1.6 + vec2(drift, drift * 0.3);
			float n = fbm(uv);
			float c = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.35, n);
			float thick = fbm(uv * 2.0 + 3.1);
			vec3 cc = mix(cloud_shadow, cloud_color, clamp(thick * 1.3 - 0.1 + pow(mu, 4.0) * 0.5, 0.0, 1.0));
			// 太阳附近云边发亮
			cc += sun_color * pow(mu, 8.0) * 0.6 * haze;
			// 远处的云淡进地平线雾里
			c *= smoothstep(0.0, 0.18, y);
			col = mix(col, cc, c * 0.9);
		}
	}
	COLOR = col * energy;
}
