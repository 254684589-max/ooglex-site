// 高地的冷杉、云杉的枝叶（路线图 5.1b，D12；ART.md 第十节「真树、真石头」「天气是活的」）：枝片贴图是用 Poly Haven「fir_tree_01」（CC0）的小枝照片拼成的整根枝条，
// 透明处剪掉（alpha scissor，不排序、不叠半透明，便宜）。上面积雪：朝上的那面（枝片的法线是从树干往外、往上的，见 HighlandFlora.tree_mesh）按噪声斑块盖白；
// 每棵树的雪多少、颜色深浅在实例数据里（INSTANCE_CUSTOM：r 深浅，g 雪，b 风的相位）。风：越往外、越往上摆得越多（顶点色 r = 离树干多远 0..1）。
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D branches : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float alpha_cut = 0.42;
uniform vec3 needle_tint : source_color = vec3(0.74, 0.82, 0.72);
uniform vec3 snow_color : source_color = vec3(0.86, 0.89, 0.94);
uniform float wind = 1.0;            // 0 = 不摆（「减少动态效果」）

varying vec3 wnrm;
varying vec3 wpos;
varying vec4 inst;

void vertex() {
	inst = INSTANCE_CUSTOM;
	float reach = COLOR.r;
	float sway = sin(TIME * 1.1 + inst.b * 6.2831) * 0.6 + sin(TIME * 2.3 + inst.b * 11.0 + VERTEX.y * 0.4) * 0.25;
	VERTEX.x += sway * wind * reach * 0.12 * (0.4 + VERTEX.y * 0.06);
	VERTEX.z += sway * wind * reach * 0.07 * (0.4 + VERTEX.y * 0.06);
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 t = texture(branches, UV);
	float cut = mix(alpha_cut, 0.18, clamp((length(VERTEX) - 20.0) / 80.0, 0.0, 1.0));   // 远处贴图的细一层透明处多，阈值放低（不然远处的树越看越稀）
	if (t.a < cut) {
		discard;
	}
	float shade = mix(0.72, 1.08, inst.r);
	vec3 alb = t.rgb * needle_tint * shade;
	float n = texture(noise_tex, wpos.xz * 0.35 + wpos.y * 0.2).r;
	float up = clamp(wnrm.y, 0.0, 1.0);
	float snow = smoothstep(0.35, 0.75, up * (0.55 + inst.g) + (n - 0.5) * 0.6) * inst.g;
	alb = mix(alb, snow_color, snow * 0.85);
	ALBEDO = alb * mix(0.62, 1.0, COLOR.g);     // 顶点色 g：靠里、靠下的枝叶暗一点（树冠里的遮蔽）
	ROUGHNESS = mix(0.85, 0.7, snow);
	SPECULAR = 0.2;
}
