// 金穗平原的地面（路线图 6.1a，D12；ART.md 第十节「地面按坡度和位置混贴图」）：一块地形混四种写实贴图（Poly Haven CC0）——
// 雪盖着的田（snow_field_aerial，雪里透出土）、收割后的麦茬地露出来的土（snow_04）、踩成泥雪的路和村里（snow_03）、河边的泥岸（brown_mud_02，按坡度）。
// 顶点色：r = 路 / 踩出来的地，g = 田，b = 遮蔽。田里一垄一垄：每块田（按 40 × 34 米的格子）垄的方向不一样，
// 垄沟里雪薄、露出土和麦茬，垄背上积雪；远处垄淡掉（1 米多一道，远了会闪）。平铺的重复感：雪按两种尺度采样再混，再乘一层很大的明暗噪声。
shader_type spatial;
render_mode cull_back;

uniform sampler2D snow_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D track_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D track_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D soil_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D bank_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bank_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;

uniform float snow_m = 15.0;
uniform float track_m = 3.0;
uniform float soil_m = 3.4;
uniform float bank_m = 4.0;
uniform vec3 snow_tint : source_color = vec3(0.8, 0.81, 0.83);
uniform vec3 track_tint : source_color = vec3(0.86, 0.84, 0.81);
uniform vec3 soil_tint : source_color = vec3(0.66, 0.58, 0.5);
uniform vec3 bank_tint : source_color = vec3(0.72, 0.68, 0.62);
uniform float bank_from = 0.12;      // 1 - 法线的 y：多陡开始是泥岸
uniform float bank_to = 0.24;
uniform float furrow_gap = 1.35;     // 垄距（米）
uniform float furrow_fade = 45.0;    // 多远垄淡掉
uniform float far_mix = 0.6;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(transpose(inverse(mat3(MODEL_MATRIX))) * NORMAL);
}

float cell_hash(vec2 c) {
	return fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 p = wpos.xz;
	float macro = texture(macro_noise, p / 110.0).r;
	float fine = texture(macro_noise, p / 9.0).r;
	float dist = length(VERTEX);
	float far_k = clamp((dist - 20.0) / 60.0, 0.0, 1.0) * far_mix;

	vec3 sn = mix(texture(snow_alb, p / snow_m).rgb, texture(snow_alb, p / (snow_m * 3.3) + 0.31).rgb, far_k);
	sn = mix(vec3(0.9, 0.91, 0.92), sn, 0.45) * snow_tint;      // 航拍的雪地照片颗粒粗：压淡一半多（不然整片是灰的噪点，截图）
	vec3 sn_n = mix(texture(snow_nrm, p / snow_m).rgb, vec3(0.5, 0.5, 1.0), far_k) * 2.0 - 1.0;
	vec3 so = mix(texture(soil_alb, p / soil_m).rgb, texture(soil_alb, p / (soil_m * 3.7) + 0.6).rgb, far_k) * soil_tint;
	vec3 so_n = texture(soil_nrm, p / soil_m).rgb * 2.0 - 1.0;
	// 踩出来的路：泥雪照片很花（站在坠星院的路上一大片黑点，截图）——细节只留三成（其余取模糊的那层 mip），再往雪色拉，一段一段地露出泥
	float mud = smoothstep(0.35, 0.0, abs(texture(macro_noise, p / 23.0).g - 0.5));
	vec2 tuv = p / track_m;
	vec3 tr_raw = mix(textureLod(track_alb, tuv, 4.0).rgb, texture(track_alb, tuv).rgb, 0.3 + mud * 0.3);
	vec3 tr = mix(tr_raw, vec3(0.8, 0.8, 0.8), 0.35 - mud * 0.25) * track_tint;
	// 法线也一样：黄昏太阳低，泥雪照片的法线把整条路照成一片黑点（截图）——取模糊的 mip、再压一半
	vec3 tr_n = mix(textureLod(track_nrm, tuv, 3.0).rgb, texture(track_nrm, tuv).rgb, 0.35) * 2.0 - 1.0;
	tr_n.xy *= 0.5;
	// 泥岸：两个竖直方向投影 + 从上往下投，按朝向混（只从上往下投在斜坡上拉成一道道，截图）
	vec3 an = abs(wnrm);
	float wx = an.x / max(an.x + an.z, 0.001);
	float vert = smoothstep(0.1, 0.35, 1.0 - wnrm.y);
	vec3 bk_side = mix(texture(bank_alb, wpos.xy / bank_m).rgb, texture(bank_alb, wpos.zy / bank_m).rgb, wx);
	vec3 bk = mix(texture(bank_alb, p / bank_m).rgb, bk_side, vert) * bank_tint;
	vec3 bk_n = texture(bank_nrm, p / bank_m).rgb * 2.0 - 1.0;

	// 田：每块田垄的方向不一样（格子编号 → 四个方向之一），块边上一道田埂（垄停住，雪厚一点）
	vec2 cell = floor((p + vec2(7.0, -3.0)) / vec2(40.0, 34.0));
	float h = cell_hash(cell);
	float ang = h < 0.25 ? 0.12 : (h < 0.5 ? 1.62 : (h < 0.75 ? 0.5 : 1.2));
	vec2 dir = vec2(cos(ang), sin(ang));
	float across = dot(p, dir) / furrow_gap;
	float wave = 0.5 + 0.5 * sin(across * 6.2831853 + fine * 1.4);
	float ridge = smoothstep(0.25, 0.75, wave);                     // 垄背、垄沟分得清一点（一道一道的麦茬露在雪外面）
	vec2 inc = fract((p + vec2(7.0, -3.0)) / vec2(40.0, 34.0));
	float edge = min(min(inc.x, 1.0 - inc.x) * 40.0, min(inc.y, 1.0 - inc.y) * 34.0);   // 离田埂几米
	float in_field = smoothstep(0.6, 1.8, edge);
	float furrow_k = (1.0 - smoothstep(furrow_fade * 0.6, furrow_fade, dist)) * in_field;
	float field = COLOR.g;
	// 雪薄的地方（大尺度噪声）整片露出麦茬地；垄沟里露、垄背上积雪
	float bare = smoothstep(0.66, 0.9, macro + (fine - 0.5) * 0.2) * 0.8;   // 露出麦茬地的大片：少一点、边软一点（黄昏时一大块黑，截图）
	float soil_w = field * clamp(mix(0.38 + bare * 0.4, (1.0 - ridge) * (0.7 + bare * 0.3) + bare * 0.2, furrow_k), 0.0, 1.0);
	so *= mix(1.0, 0.72, (1.0 - ridge) * furrow_k);               // 垄沟里的麦茬根更暗
	float track_w = clamp(COLOR.r * (0.75 + fine * 0.5), 0.0, 1.0);
	float slope = 1.0 - wnrm.y;
	float bank_w = smoothstep(bank_from, bank_to, slope + (fine - 0.5) * 0.08) * (1.0 - track_w * 0.5);

	vec3 alb = mix(sn, so, soil_w);
	vec3 tn = mix(sn_n, so_n, soil_w);
	alb = mix(alb, tr, track_w);
	tn = mix(tn, tr_n, track_w);
	alb = mix(alb, bk, bank_w);
	tn = mix(tn, bk_n, bank_w);

	// 垄的起伏用法线做出来（不真的改高度）：垄背朝两边斜
	float slope_r = cos(across * 6.2831853 + fine * 1.4) * 0.22 * furrow_k * field * (1.0 - track_w);
	vec3 n_furrow = vec3(dir.x, 0.0, dir.y) * slope_r;
	vec3 nw = normalize(wnrm + vec3(tn.x, 0.0, -tn.y) * 0.85 + n_furrow);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	float shade = COLOR.b * (0.9 + 0.2 * macro);
	alb = mix(vec3(0.74, 0.75, 0.77), alb, COLOR.a);     // 远处网格的裙边（a = 0）：只给平均的雪色
	ALBEDO = alb * shade;
	ROUGHNESS = mix(0.84, 0.95, max(soil_w, max(track_w, bank_w)));
	SPECULAR = mix(0.42, 0.28, max(soil_w, bank_w));
}
