// 双钥港的地面（路线图 7.1，D12；ART.md 第十节「地面按坡度和位置混贴图」）：一块地形混五种写实贴图（Poly Haven CC0）——
// 城里踩成泥雪的地（snow_03）、铺石的街和码头边（cobblestone_floor_08）、退潮露出来的泥滩和沟底（brown_mud_03，湿的、反着一点天光）、
// 沙嘴和海滩的沙（coast_sand_01）、潮线上一道卵石（coast_sand_rocks_02）。
// 顶点色：r = 铺石，g = 沙，b = 遮蔽，a = 0 是远处网格的裙边。泥按高度（低于 mud_y 的都是泥 / 沙）；陡的地方（码头的石岸、潮沟两壁）贴成石头砌的墙（铺石的贴图竖着投）。
// 被水泡过的地方颜色深、更光滑（潮位以下 wet_band 米到潮位以上一点，按潮位 uniform tide）。
shader_type spatial;
render_mode cull_back;

uniform sampler2D ground_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D paved_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paved_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D mud_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D shingle_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shingle_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;

uniform float ground_m = 3.2;
uniform float paved_m = 2.6;
uniform float mud_m = 4.5;
uniform float sand_m = 6.0;
uniform float shingle_m = 3.0;
uniform float wall_m = 1.6;
uniform vec3 ground_tint : source_color = vec3(0.64, 0.63, 0.62);
uniform vec3 paved_tint : source_color = vec3(0.78, 0.77, 0.76);
uniform vec3 mud_tint : source_color = vec3(0.62, 0.58, 0.54);
uniform vec3 sand_tint : source_color = vec3(0.86, 0.83, 0.78);
uniform vec3 wall_tint : source_color = vec3(0.62, 0.62, 0.62);
uniform float mud_y = 0.4;           // 比这低：泥（沙的地方是湿沙）
uniform float tide = -0.5;
uniform float wet_band = 0.35;       // 潮位以上多高还是湿的
uniform float wall_from = 0.35;      // 1 - 法线的 y：多陡贴成石墙
uniform float wall_to = 0.55;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(transpose(inverse(mat3(MODEL_MATRIX))) * NORMAL);
}

void fragment() {
	vec2 p = wpos.xz;
	float macro = texture(macro_noise, p / 120.0).r;
	float fine = texture(macro_noise, p / 9.0).r;
	float dist = length(VERTEX);
	float far_k = clamp((dist - 25.0) / 60.0, 0.0, 1.0) * 0.6;

	vec3 gr = mix(texture(ground_alb, p / ground_m).rgb, texture(ground_alb, p / (ground_m * 3.1) + 0.27).rgb, far_k);
	gr = mix(gr, vec3(0.7, 0.69, 0.67), 0.2) * ground_tint;            // 泥雪照片很花：往灰的雪色拉一点（海边的雪是脏的、半化的）
	vec3 gr_n = mix(texture(ground_nrm, p / ground_m).rgb, vec3(0.5, 0.5, 1.0), far_k) * 2.0 - 1.0;
	gr_n.xy *= 0.6;
	vec3 pv = mix(texture(paved_alb, p / paved_m).rgb, texture(paved_alb, p / (paved_m * 2.7) + 0.5).rgb, far_k) * paved_tint;
	vec3 pv_n = texture(paved_nrm, p / paved_m).rgb * 2.0 - 1.0;
	vec3 md = mix(texture(mud_alb, p / mud_m).rgb, texture(mud_alb, p / (mud_m * 3.3) + 0.4).rgb, far_k) * mud_tint;
	vec3 md_n = texture(mud_nrm, p / mud_m).rgb * 2.0 - 1.0;
	vec3 sd = mix(texture(sand_alb, p / sand_m).rgb, texture(sand_alb, p / (sand_m * 3.0) + 0.6).rgb, far_k) * sand_tint;
	vec3 sd_n = texture(sand_nrm, p / sand_m).rgb * 2.0 - 1.0;
	vec3 sh = texture(shingle_alb, p / shingle_m).rgb * sand_tint;
	vec3 sh_n = texture(shingle_nrm, p / shingle_m).rgb * 2.0 - 1.0;
	// 石墙：两个竖直方向投影（码头的石岸、潮沟两壁）
	vec3 an = abs(wnrm);
	float wx = an.x / max(an.x + an.z, 0.001);
	vec3 wall = mix(texture(paved_alb, wpos.xy / wall_m).rgb, texture(paved_alb, wpos.zy / wall_m).rgb, wx) * wall_tint;     // 朝东西的墙面投在 zy 上、朝南北的投在 xy 上
	vec3 wall_n = mix(texture(paved_nrm, wpos.xy / wall_m).rgb, texture(paved_nrm, wpos.zy / wall_m).rgb, wx) * 2.0 - 1.0;

	float paved_w = clamp(COLOR.r * (0.85 + fine * 0.3), 0.0, 1.0);
	float sand_w = clamp(COLOR.g, 0.0, 1.0);
	float low = 1.0 - smoothstep(mud_y - 0.25, mud_y + 0.25, wpos.y + (fine - 0.5) * 0.3);
	float mud_w = low * (1.0 - sand_w);
	float strand = smoothstep(0.6, 0.15, abs(wpos.y - (tide + 0.55) + (fine - 0.5) * 0.25)) * sand_w * 0.8;    // 潮线上一道卵石
	float slope = 1.0 - wnrm.y;
	float wall_w = smoothstep(wall_from, wall_to, slope);

	vec3 alb = mix(gr, pv, paved_w);
	vec3 tn = mix(gr_n, pv_n, paved_w);
	alb = mix(alb, sd, sand_w);
	tn = mix(tn, sd_n, sand_w);
	alb = mix(alb, md, mud_w);
	tn = mix(tn, md_n, mud_w);
	alb = mix(alb, sh, strand);
	tn = mix(tn, sh_n, strand);
	alb = mix(alb, wall, wall_w);
	tn = mix(tn, wall_n, wall_w);

	// 湿：潮位以下和潮位上面一点（退潮以后泥滩还湿着），颜色深、光滑
	float wet = 1.0 - smoothstep(tide, tide + wet_band + 0.4 * fine, wpos.y);
	wet = max(wet, low * 0.6);
	alb *= mix(1.0, 0.62, wet);

	vec3 nw = normalize(wnrm + vec3(tn.x, 0.0, -tn.y) * mix(0.85, 0.45, wet));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float shade = COLOR.b * (0.84 + 0.32 * macro);                     // 大片的明暗起伏（城里的雪一块踩脏一块没踩）
	alb = mix(vec3(0.5, 0.48, 0.46), alb, COLOR.a);
	ALBEDO = alb * shade;
	ROUGHNESS = mix(mix(0.88, 0.8, paved_w), 0.32, wet);
	SPECULAR = mix(0.35, 0.55, wet);
}
