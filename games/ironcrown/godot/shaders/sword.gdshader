shader_type spatial;
// 主角的剑（路线图 C.3，combat/sword_kit.gd）：顶点色记材质槽——红 = 钢（剑身）、绿 = 铁（护手、剑首）、蓝 = 握柄（缠绳 / 木片）。
render_mode cull_disabled;

uniform float glow = 0.0;

void fragment() {
	vec3 steel = vec3(0.66, 0.69, 0.72);
	vec3 iron = vec3(0.32, 0.30, 0.28);
	vec3 grip = vec3(0.22, 0.14, 0.09);
	vec3 c = steel * COLOR.r + iron * COLOR.g + grip * COLOR.b;
	ALBEDO = c;
	METALLIC = 0.45 * COLOR.r + 0.4 * COLOR.g;          // 不能太高：夜里四周没什么可反射，全金属的剑身会黑成一根棍（第一版截图）
	ROUGHNESS = 0.3 * COLOR.r + 0.45 * COLOR.g + 0.85 * COLOR.b;
	EMISSION = c * glow;
}
