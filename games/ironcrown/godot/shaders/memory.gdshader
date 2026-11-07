shader_type canvas_item;
// 回忆的画面（路线图 C.5，过场里 memory = true 的镜头）：褪色成旧照片的暖褐色、四角压暗、一点点颗粒，像隔着很多年看过去。
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 1.0;
uniform float time_s = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 sep = vec3(g * 1.08, g * 0.94, g * 0.74) * 1.05;
	vec2 d = SCREEN_UV - 0.5;
	float vig = clamp(1.0 - dot(d, d) * 1.9, 0.0, 1.0);
	float grain = (hash(SCREEN_UV * 900.0 + time_s) - 0.5) * 0.06;
	vec3 o = mix(c, sep, amount) * mix(1.0, vig, amount) + grain * amount;
	COLOR = vec4(o, 1.0);
}
