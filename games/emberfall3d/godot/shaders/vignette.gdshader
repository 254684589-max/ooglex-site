shader_type canvas_item;
// 暗角（ART.md 第二节「暗角与雾」）：画面四周压暗，视线集中到中间的主角。
uniform float strength : hint_range(0.0, 1.0) = 0.7;
uniform float inner : hint_range(0.0, 1.0) = 0.35;
uniform vec3 tint : source_color = vec3(0.05, 0.02, 0.04);

void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 1.414;
	float a = smoothstep(inner, 1.05, r) * strength;
	COLOR = vec4(tint, a);
}
