// 双钥港的水（路线图 7.1，D12）：河口一整片——灰绿、浑，河里往南慢慢淌，海那边有一层层的涌；
// 顶点的 UV2.x = 底下的地面多高，水深 = 潮位（tide）- 地面：浅的地方颜色淡、透出泥色，贴着岸一道碎浪的白沫；远处的水面反着阴天（菲涅耳）。
// 不读深度缓冲（兼容渲染器上不稳）：水深按预先记在顶点上的地面高度算。
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 deep_col : source_color = vec3(0.1, 0.14, 0.15);
uniform vec3 shallow_col : source_color = vec3(0.26, 0.27, 0.23);
uniform vec3 sky_col : source_color = vec3(0.42, 0.45, 0.48);
uniform vec3 foam_col : source_color = vec3(0.82, 0.83, 0.82);
uniform float tide = -0.5;
uniform float flow = 0.03;

varying vec3 wpos;
varying float depth;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	depth = tide - UV2.x;
	float swell = sin(wpos.z * 0.09 + TIME * 0.7) * 0.5 + sin(wpos.x * 0.05 + wpos.z * 0.04 - TIME * 0.45) * 0.5;
	VERTEX.y += swell * 0.06 * clamp(depth / 2.0, 0.0, 1.0);          // 深水那边一点点涌，浅处不动（不然泡沫那道线跟着跳）
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME * flow;
	float n1 = texture(noise_tex, vec2(p.x * 0.05, p.y * 0.03 - t)).r;
	float n2 = texture(noise_tex, vec2(p.x * 0.17 + 0.5, p.y * 0.11 - t * 1.6)).r;
	float n3 = texture(noise_tex, vec2(p.x * 0.6 + t * 2.0, p.y * 0.6)).r;
	float d = depth + (n2 - 0.5) * 0.12;
	if (d < -0.02) {
		discard;
	}
	float shallow = 1.0 - smoothstep(0.0, 1.6, d);
	vec3 water = mix(deep_col, shallow_col, shallow * 0.85 + n1 * 0.1);
	float foam = smoothstep(0.22, 0.0, d) * smoothstep(0.35, 0.6, n3 + n1 * 0.3);
	ALBEDO = mix(water, foam_col, foam * 0.75);
	ALPHA = clamp(0.55 + d * 0.9, 0.55, 1.0);                          // 很浅的地方透出底下的泥
	ROUGHNESS = mix(0.3 + n2 * 0.1, 0.65, foam);                       // 太光滑在阴天里整片反成白的（截图）
	SPECULAR = 0.22;
	vec3 nrm = normalize(vec3((n1 - 0.5) * 0.3 + (n3 - 0.5) * 0.08, 1.0, (n2 - 0.5) * 0.3));
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(ALBEDO, mix(ALBEDO, sky_col, 0.55), fres * 0.45 * (1.0 - foam));
}
