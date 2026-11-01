// 金穗平原的树、篱笆、麦垛、木栅（路线图 6.1b，D12；world/plain_flora.gd）。一个着色器三种用法（mode）：
//   0 树皮：树干、枝、柳树干、木栅（主包里的 bark_brown_02），朝上的面按噪声斑块积雪；
//   1 枝条片：贴图 chapters/ch3/trees/plain_twigs.png（代码画的三格：细枝、柳条、整棵树剪影），透明处剪掉（不排序、便宜），远处阈值放低（细枝在小的 mipmap 里变淡，不然远处的树越看越稀）；
//     朝上的枝落一点雪，风吹着轻轻摆（顶点色 r = 离根多远）；
//   2 麦垛：麦秆的竖纹（噪声拉长）、底下潮得发暗、顶上积雪。
// 每个实例的数据（INSTANCE_CUSTOM）：r 深浅，g 雪多少，b 风的相位。
shader_type spatial;
render_mode cull_disabled;

uniform int mode = 0;
uniform sampler2D bark_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D twig_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float wind = 1.0;
uniform vec3 bark_tint : source_color = vec3(0.58, 0.55, 0.52);
uniform vec3 snow_color : source_color = vec3(0.88, 0.9, 0.94);
uniform vec3 straw_a : source_color = vec3(0.66, 0.56, 0.38);
uniform vec3 straw_b : source_color = vec3(0.45, 0.38, 0.28);

varying vec3 wnrm;
varying vec3 wpos;
varying vec4 inst;

void vertex() {
	inst = INSTANCE_CUSTOM;
	if (mode == 1) {
		float reach = COLOR.r;
		float sway = sin(TIME * 0.9 + inst.b * 6.2831) * 0.6 + sin(TIME * 2.1 + inst.b * 9.0 + VERTEX.y * 1.3) * 0.3;
		VERTEX.x += sway * wind * reach * 0.04;
		VERTEX.z += sway * wind * reach * 0.025;
	}
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float shade = mix(0.8, 1.1, inst.r);
	float n = texture(noise_tex, wpos.xz * 0.4 + wpos.y * 0.25).r;
	float up = clamp(wnrm.y, 0.0, 1.0);
	vec3 alb;
	float snow;
	if (mode == 1) {
		vec4 t = texture(twig_tex, UV);
		float cut = mix(0.5, 0.32, clamp((length(VERTEX) - 15.0) / 90.0, 0.0, 1.0));   // 0.14 时远处整片填实，像一朵朵黑蘑菇、一把把扇子（截图）
		if (t.a < cut) {
			discard;
		}
		alb = t.rgb * shade;
		snow = smoothstep(0.75, 0.95, up * (0.4 + inst.g * 0.5) + (n - 0.5) * 0.5) * inst.g * 0.35;
		alb *= mix(0.7, 1.0, COLOR.g);
		// 远处的树往天色里退（照片里冬天远处的光秃树是一团团灰紫的，不是黑的；不然地平线上一排黑蘑菇，截图）
		float aerial = clamp((length(VERTEX) - 22.0) / 150.0, 0.0, 0.7);
		alb = mix(alb, vec3(0.5, 0.49, 0.52), aerial);
		ROUGHNESS = 0.9;
	} else if (mode == 2) {
		float streak = texture(noise_tex, vec2(UV.x * 7.0, UV.y * 0.25)).r;
		float fine = texture(noise_tex, vec2(UV.x * 31.0, UV.y * 1.2)).r;
		alb = mix(straw_b, straw_a, smoothstep(0.25, 0.8, streak * 0.7 + fine * 0.5)) * shade;
		alb *= mix(0.62, 1.0, smoothstep(0.0, 1.0, UV.y));                     // 贴地那一圈潮得发暗
		snow = smoothstep(0.6, 0.88, up + (n - 0.5) * 0.3) * inst.g;     // 只盖顶上一顶（0.3 起整个垛都白了，截图）
		ROUGHNESS = 0.95;
	} else {
		alb = texture(bark_tex, UV * vec2(1.0, 1.0)).rgb * bark_tint * shade;
		snow = smoothstep(0.45, 0.8, up + (n - 0.5) * 0.4) * inst.g;
		// 树干的法线往上偏一点：阴天里背光那面也吃得到天光（不然逆光的柳树干一根根黑柱子，截图）
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(wnrm + vec3(0.0, 0.7, 0.0)), 0.0)).xyz);
		ROUGHNESS = 0.9;
	}
	ALBEDO = mix(alb, snow_color, snow);
	SPECULAR = mix(0.25, 0.4, snow);
}
