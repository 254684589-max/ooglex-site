// 火苗（路线图 5.3b，第十九烽塔顶的火盆）：一张面片绕 Y 轴始终对着镜头（不躺倒），按噪声往上卷的一团火——
// 下宽上尖的水滴形遮罩被滚动的噪声扭动、啃掉边缘；颜色从底部的亮黄到中间的橙、顶上的暗红；叠加混合（不排序、不挡后面）。
// 每片的相位在 INSTANCE_CUSTOM.r 里（多实例）或 phase 参数里（单片），几片叠在一起看着不一样。
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;   // 不受雾影响：夜里雾是暗的，叠加的火被雾一盖就看不见了

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float phase = 0.0;
uniform float speed = 1.0;            // 0 = 不动（「减少动态效果」）
uniform float strength = 1.6;
uniform vec3 hot : source_color = vec3(1.0, 0.86, 0.48);
uniform vec3 mid : source_color = vec3(1.0, 0.5, 0.14);
uniform vec3 cool : source_color = vec3(0.55, 0.12, 0.03);

void vertex() {
	// 绕 Y 轴对着镜头：用镜头在模型空间里的水平方向重建面片的横轴
	vec3 cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec2 d = normalize(cam.xz + vec2(0.0001));
	vec3 right = vec3(d.y, 0.0, -d.x);
	VERTEX = right * VERTEX.x + vec3(0.0, VERTEX.y, 0.0);
}

void fragment() {
	float t = TIME * speed + phase * 13.0;
	vec2 uv = UV;
	float y = 1.0 - uv.y;                                         // 0 底 → 1 顶
	float n1 = texture(noise_tex, vec2(uv.x * 0.8 + phase, uv.y * 0.9 + t * 0.9)).r;
	float n2 = texture(noise_tex, vec2(uv.x * 1.7 - phase, uv.y * 1.6 + t * 1.6)).r;
	float wob = (n1 - 0.5) * 0.35 * y;
	float x = abs(uv.x - 0.5 + wob) * 2.0;
	float width = mix(0.95, 0.05, pow(y, 0.8));                   // 下宽上尖
	float body = smoothstep(width, width * 0.35, x);
	body *= smoothstep(0.0, 0.12, y) * smoothstep(1.0, 0.55, y + (n2 - 0.5) * 0.5);
	body *= 0.55 + 0.9 * n2;
	vec3 col = mix(hot, mid, smoothstep(0.1, 0.55, y));
	col = mix(col, cool, smoothstep(0.55, 0.95, y));
	ALBEDO = col * body * strength;
	ALPHA = clamp(body, 0.0, 1.0);
}
