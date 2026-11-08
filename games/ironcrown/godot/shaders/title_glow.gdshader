// 主菜单的光：光柱（圆台，上下两头淡、边上淡）、远处的冷光、火光的晕（2026-11-08）
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.7, 0.82, 1.0);
uniform float strength = 0.6;
uniform int mode = 0;          // 0 = 光柱（UV.y 上下淡），1 = 圆晕（面片，中心亮）
uniform float flicker = 0.0;
uniform float motion = 1.0;

void fragment() {
	float a = 0.0;
	if (mode == 0) {
		float v = UV.y;
		a = smoothstep(0.0, 0.25, v) * smoothstep(1.0, 0.55, v);
		float edge = abs(dot(normalize(NORMAL), normalize(VIEW)));
		a *= pow(edge, 2.2);
		a *= 0.85 + 0.15 * sin(TIME * motion * 0.7 + UV.x * 18.0);
	} else {
		float r = length(UV - vec2(0.5)) * 2.0;
		a = pow(max(1.0 - r, 0.0), 2.4);
	}
	a *= strength * (1.0 + flicker * (sin(TIME * 13.0) * 0.08 + sin(TIME * 7.3) * 0.1));
	ALBEDO = tint * a;
	ALPHA = a;
}
