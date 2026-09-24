shader_type spatial;
// 屏幕空间环境光遮蔽（SSAO，近似）：只读深度缓冲，墙角、楼缝、车底、树下自然变暗。
// 输出黑色 + 透明度 = 遮蔽量（普通混合）：兼容渲染器会对透明物体的颜色做色调映射，乘法混合会整体变暗，
// 黑色经过色调映射仍是黑色，透明度不受影响，所以用这种方式得到准确的「画面 × 遮蔽系数」。
// 全屏四边形：顶点直接写裁剪坐标；不做深度测试、不受雾影响。
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float strength = 0.8;
uniform float radius = 1.4;
uniform float max_distance = 140.0;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

vec3 view_pos(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec3 ndc = vec3(uv, d) * 2.0 - 1.0;
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return v.xyz / v.w;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 p = view_pos(uv, INV_PROJECTION_MATRIX);
	float d = -p.z;
	float ao = 1.0;
	if (d < max_distance) {
		// 由深度重建的表面法线；只统计「高出表面」的采样点（平地上不会自己遮自己）
		vec3 n = normalize(cross(dFdx(p), dFdy(p)));
		if (dot(n, -p) < 0.0) n = -n;
		float r = radius * PROJECTION_MATRIX[1][1] * 0.5 / d;
		r = min(r, 0.08);
		float rot = hash(FRAGCOORD.xy) * 6.2831;
		float occ = 0.0;
		for (int i = 0; i < 10; i++) {
			float fi = float(i);
			float a = rot + fi * 2.39996;
			float s = sqrt((fi + 0.5) / 10.0);
			vec2 o = vec2(cos(a), sin(a)) * r * s;
			o.x *= VIEWPORT_SIZE.y / VIEWPORT_SIZE.x;
			vec3 v = view_pos(uv + o, INV_PROJECTION_MATRIX) - p;
			float dist = length(v);
			if (dist > 0.001) {
				occ += max(dot(n, v / dist) - 0.2, 0.0) * (1.0 - smoothstep(radius * 0.6, radius * 1.6, dist));
			}
		}
		ao = 1.0 - strength * clamp(occ / 10.0 * 1.8, 0.0, 1.0);
		ao = mix(ao, 1.0, smoothstep(max_distance * 0.6, max_distance, d));
	}
	ALBEDO = vec3(0.0);
	ALPHA = clamp(1.0 - ao, 0.0, 1.0);
}
