shader_type spatial;
// 贴地雾带（TECH.md 4.6）：兼容渲染器没有体积雾，用几片水平的半透明面片冒充。
// 两层噪声按世界坐标缓慢飘动；面片四边、离相机很近的地方都淡出（走进雾里不会看到一张「纸」）。
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 color : source_color = vec4(0.42, 0.52, 0.62, 1.0);
uniform float density = 0.35;
uniform vec2 drift = vec2(0.012, 0.004);
uniform float near_fade = 3.0;
uniform float edge = 0.2;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n1 = texture(noise_tex, world_pos.xz * 0.05 + TIME * drift).r;
	float n2 = texture(noise_tex, world_pos.xz * 0.11 - TIME * drift * 1.7).r;
	float m = smoothstep(0.3, 0.8, n1 * 0.6 + n2 * 0.4);
	vec2 e = smoothstep(vec2(0.0), vec2(edge), UV) * smoothstep(vec2(0.0), vec2(edge), vec2(1.0) - UV);
	float d = length(world_pos - CAMERA_POSITION_WORLD);
	float cam = smoothstep(near_fade * 0.4, near_fade, d);
	ALBEDO = color.rgb;
	ALPHA = m * density * e.x * e.y * cam;
}
