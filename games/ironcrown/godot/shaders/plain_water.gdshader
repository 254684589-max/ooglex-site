// 麦河的水（路线图 6.1a，D12）：冬天的河，水深色、几乎不动，慢慢往南流（法线上一层按噪声移动的细纹）；
// 两边结着一道薄冰（顶点色 r = 离河心多远：靠岸那三成是冰，冰的边不齐，冰上有裂纹）；远处的水面反着天光（菲涅耳）。
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 deep_col : source_color = vec3(0.2, 0.24, 0.26);
uniform vec3 shallow_col : source_color = vec3(0.3, 0.33, 0.33);
uniform vec3 sky_col : source_color = vec3(0.62, 0.66, 0.7);
uniform vec3 ice_col : source_color = vec3(0.78, 0.82, 0.86);
uniform float flow = 0.025;
uniform float ice_from = 0.62;

void fragment() {
	vec2 p = UV;                       // u = 横着（米，河心 0）、v = 沿河（米）
	float t = TIME * flow;
	float n1 = texture(noise_tex, vec2(p.x * 0.11, p.y * 0.05 - t)).r;
	float n2 = texture(noise_tex, vec2(p.x * 0.31 + 0.5, p.y * 0.17 - t * 1.7)).r;
	float edge = COLOR.r + (n1 - 0.5) * 0.22 + (n2 - 0.5) * 0.08;
	float ice = smoothstep(ice_from, ice_from + 0.06, edge);
	float crack = smoothstep(0.47, 0.5, n2) * smoothstep(0.53, 0.5, n2);
	vec3 water = mix(deep_col, shallow_col, smoothstep(0.2, 0.6, COLOR.r) * 0.7 + n1 * 0.15);
	vec3 icec = ice_col * (0.92 + n1 * 0.12) - crack * 0.18;
	ALBEDO = mix(water, icec, ice);
	ROUGHNESS = mix(0.22 + n2 * 0.08, 0.55, ice);           // 太光滑在低角度整片反成白的（截图）
	SPECULAR = mix(0.35, 0.3, ice);
	METALLIC = 0.0;
	vec3 nrm = normalize(vec3((n1 - 0.5) * 0.18 * (1.0 - ice), 1.0, (n2 - 0.5) * 0.18 * (1.0 - ice)));
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(ALBEDO, mix(ALBEDO, sky_col, 0.5), fres * 0.6 * (1.0 - ice));   // 远处的水面淡淡反着天光
}
