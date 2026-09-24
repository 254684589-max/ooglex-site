shader_type spatial;
// 路灯光锥（模拟体积光）：加法混合的半透明圆锥，正对视线处最亮、边缘淡出，靠近灯头亮、落到地面淡出。
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float intensity = 0.0;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = pow(facing, 2.0);
	float wy = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
	float h = smoothstep(0.0, 6.5, wy);
	float dist = length(VERTEX);
	float far_fade = 1.0 - smoothstep(40.0, 90.0, dist);
	ALBEDO = COLOR.rgb * edge * (0.25 + 0.75 * h) * intensity * far_fade;
}
