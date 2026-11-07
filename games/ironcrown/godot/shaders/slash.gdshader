shader_type spatial;
// 刀光（路线图 C.1）：一条弧形的带子，progress 从 0 走到 1.4——亮的「刀头」顺着弧走过去，后面拖一段渐暗的尾巴；
// UV.x 沿弧（0 起手 → 1 收刀），UV.y 从内沿到外沿（外沿是刀尖划过的地方，最亮）。不受光、叠加混合、不写深度。
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float progress = 0.0;
uniform vec4 tint : source_color = vec4(0.86, 0.9, 0.96, 1.0);
uniform float energy = 1.0;
uniform float tail = 0.55;

void fragment() {
	float d = progress - UV.x;
	float a = step(0.0, d) * pow(1.0 - smoothstep(0.0, tail, d), 1.6);
	float edge = pow(UV.y, 2.6) * (1.0 - smoothstep(0.94, 1.0, UV.y));      // 内沿几乎透明，越往外沿（刀尖）越亮
	float ends = smoothstep(0.0, 0.08, UV.x) * (1.0 - smoothstep(0.9, 1.0, UV.x));
	float fade = 1.0 - smoothstep(0.85, 1.4, progress);
	float core = smoothstep(0.7, 0.97, UV.y) * 0.6;
	ALBEDO = mix(tint.rgb, vec3(1.0), core) * energy;
	ALPHA = clamp(a * edge * ends * fade * tint.a, 0.0, 1.0);
}
