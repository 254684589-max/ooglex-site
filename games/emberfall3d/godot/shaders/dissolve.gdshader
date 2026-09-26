// 溶解（阶段 2.5）：怪物死亡时从身上「烧穿」出一个个洞，洞的边缘发出余烬的光，最后整个消失。
// 用世界坐标算三维噪声（每个部件的局部坐标太小，整块会一下子消失）（不用贴图，兼容渲染器 / WebGL 2 可用），progress 从 0 推到 1。
shader_type spatial;
render_mode cull_disabled;

uniform vec4 albedo : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.45, 0.12, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float edge_width = 0.07;

varying vec3 lpos;

void vertex() {
	lpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x),
				   mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x),
				   mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

void fragment() {
	float n = noise(lpos * 4.0) * 0.65 + noise(lpos * 11.0) * 0.35;
	float h = n - progress * 1.1;
	if (h < 0.0) {
		discard;
	}
	ALBEDO = albedo.rgb;
	ROUGHNESS = 1.0;
	if (h < edge_width && progress > 0.001) {
		ALBEDO = edge_color.rgb;
		EMISSION = edge_color.rgb * 3.5;
	}
}
