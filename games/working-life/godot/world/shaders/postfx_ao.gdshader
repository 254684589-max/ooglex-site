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

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec3 ndc = vec3(uv, d) * 2.0 - 1.0;
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float d = lin_depth(uv, INV_PROJECTION_MATRIX);
	float ao = 1.0;
	if (d < max_distance) {
		// 世界空间半径 → 屏幕空间半径
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
			float sd = lin_depth(uv + o, INV_PROJECTION_MATRIX);
			float diff = d - sd;
			// 比当前点更靠近相机、且在半径范围内的采样点 = 遮挡
			occ += smoothstep(0.03, 0.25, diff) * (1.0 - smoothstep(radius, radius * 2.5, diff));
		}
		ao = 1.0 - strength * occ / 10.0;
		ao = mix(ao, 1.0, smoothstep(max_distance * 0.6, max_distance, d));
	}
	ALBEDO = vec3(0.0);
	ALPHA = clamp(1.0 - ao, 0.0, 1.0);
}
