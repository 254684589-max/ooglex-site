// 余火高地的地面（路线图 5.1a，D12；ART.md 第十节「地面按坡度和位置混贴图」）：一块地形混四种写实贴图（Poly Haven CC0）——
// 平处积雪（snow_02）、路和村里踩出来的雪（snow_01，有脚印）、雪薄处的碎石（gray_rocks）、陡坡露出的岩石（mossy_rock，长地衣的灰岩）。
// 顶点色：r = 路 / 踩出来的地，g = 碎石斑块，b = 遮蔽（凹处暗一点）；岩石由坡度算（地形法线），边界用大尺度噪声打散，不是一条直线。
// 平铺的重复感：雪按两种尺度采样再混（近处细、远处粗），再乘一层很大的明暗噪声。岩石在两个竖直方向投影（陡坡不会拉丝），坡缓的岩面再混一次从上往下的投影（5.3a）。
shader_type spatial;
render_mode cull_back;

uniform sampler2D snow_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D track_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D track_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D scree_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scree_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;

uniform float snow_m = 5.5;
uniform float track_m = 2.6;
uniform float scree_m = 3.2;
uniform float rock_m = 7.0;
uniform vec3 snow_tint : source_color = vec3(0.78, 0.82, 0.89);
uniform vec3 track_tint : source_color = vec3(0.74, 0.75, 0.78);
uniform vec3 scree_tint : source_color = vec3(0.62, 0.62, 0.64);
uniform vec3 rock_tint : source_color = vec3(0.6, 0.62, 0.62);
uniform float rock_from = 0.24;      // 1 - 法线的 y：多陡开始露岩（约 40°）
uniform float rock_to = 0.36;
uniform float far_mix = 0.55;        // 远处雪用粗一档的尺度采样的比例

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(transpose(inverse(mat3(MODEL_MATRIX))) * NORMAL);   // 法线按逆转置变换：石圈的立石是拉高了的石头（多实例），直接乘模型矩阵法线会往上歪，侧面也被当成积雪（截图）
}

void fragment() {
	vec2 p = wpos.xz;
	float macro = texture(macro_noise, p / 90.0).r;
	float fine = texture(macro_noise, p / 9.0).r;
	float dist = length(VERTEX);
	float far_k = clamp((dist - 18.0) / 50.0, 0.0, 1.0) * far_mix;

	vec3 sn = mix(texture(snow_alb, p / snow_m).rgb, texture(snow_alb, p / (snow_m * 4.3) + 0.37).rgb, far_k);
	sn = mix(vec3(0.86), sn, 0.5) * snow_tint;      // 照片里的枯草茎、黑点压淡一半（大片铺开时一道道黑纹太扎眼）
	vec3 sn_n = mix(texture(snow_nrm, p / snow_m).rgb, vec3(0.5, 0.5, 1.0), far_k) * 2.0 - 1.0;
	vec3 tr = texture(track_alb, p / track_m).rgb * track_tint;
	vec3 tr_n = texture(track_nrm, p / track_m).rgb * 2.0 - 1.0;
	vec3 sc = texture(scree_alb, p / scree_m).rgb * scree_tint;
	vec3 sc_n = texture(scree_nrm, p / scree_m).rgb * 2.0 - 1.0;

	vec3 an = abs(wnrm);
	float wx = an.x / max(an.x + an.z, 0.001);
	vec3 rk = mix(texture(rock_alb, wpos.xy / rock_m).rgb, texture(rock_alb, wpos.zy / rock_m).rgb, wx) * rock_tint;
	// 坡不太陡的岩面（岩坎脚、坡上露岩的边）两个竖直投影都斜着拉成一道道（5.3a 截图：岩坎脚下一排琴键），再从上往下投一次，按坡度混
	float steep = smoothstep(0.22, 0.38, 1.0 - wnrm.y);
	rk = mix(texture(rock_alb, wpos.xz / rock_m).rgb * rock_tint, rk, steep);
	vec3 rn_xy = texture(rock_nrm, wpos.xy / rock_m).rgb * 2.0 - 1.0;
	vec3 rn_zy = texture(rock_nrm, wpos.zy / rock_m).rgb * 2.0 - 1.0;

	float slope = 1.0 - wnrm.y;
	float rock_w = smoothstep(rock_from, rock_to, slope + (fine - 0.5) * 0.14 + (macro - 0.5) * 0.08);
	float scree_w = clamp(COLOR.g * (0.7 + fine * 0.6), 0.0, 1.0) * (1.0 - COLOR.r);
	float track_w = clamp(COLOR.r * (0.75 + fine * 0.5), 0.0, 1.0);

	vec3 alb = mix(sn, sc, scree_w);
	vec3 tn = mix(sn_n, sc_n, scree_w);
	alb = mix(alb, tr, track_w);
	tn = mix(tn, tr_n, track_w);
	alb = mix(alb, rk, rock_w);

	// 法线贴图直接在世界空间里加到地形法线上（不用切线）：地面层贴图的 u = x、v = z（OpenGL 法线贴图绿色朝图上方 = -v）；
	// 岩石两个竖直投影各按自己的平面加，再按朝向混
	vec3 n_flat = wnrm + vec3(tn.x, 0.0, -tn.y) * 0.9;
	vec3 n_rock = wnrm + mix(vec3(rn_xy.x, -rn_xy.y, 0.0), vec3(0.0, -rn_zy.y, rn_zy.x), wx) * 1.2;
	vec3 nw = normalize(mix(n_flat, n_rock, rock_w));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	float shade = COLOR.b * (0.9 + 0.2 * macro);
	ALBEDO = alb * shade;
	ROUGHNESS = mix(mix(0.82, 0.92, scree_w + track_w * 0.5), 0.95, rock_w);
	SPECULAR = mix(0.45, 0.3, rock_w);
}
