shader_type canvas_item;
// 暗角（复制自 games/emberfall3d/godot/shaders/vignette.gdshader，ART.md 第二节）：画面四周压暗，颜色改为本作的冷蓝。
uniform float strength : hint_range(0.0, 1.0) = 0.55;
uniform float inner : hint_range(0.0, 1.0) = 0.4;
uniform vec3 tint : source_color = vec3(0.02, 0.04, 0.07);

void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 1.414;
	float a = smoothstep(inner, 1.05, r) * strength;
	COLOR = vec4(tint, a);
}
