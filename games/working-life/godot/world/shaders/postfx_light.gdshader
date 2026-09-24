shader_type spatial;
// 叠加到画面上的光效（加法混合，不会遮住玻璃、招牌等透明物体）：
//   1. 光柱：从太阳在屏幕上的位置向外做径向模糊，只取天空像素（深度在远处）作为光源——黄昏阳光穿过楼缝；
//   2. 雨天路面反射：朝上的湿地面沿反射方向在屏幕空间步进，取到的画面颜色按菲涅耳加到路面上。
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec2 sun_uv = vec2(0.5, 0.2);
uniform float shafts = 0.0;
uniform vec3 sun_color : source_color = vec3(1.0, 0.7, 0.45);
uniform float wet = 0.0;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

vec3 view_pos(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec3 ndc = vec3(uv, d) * 2.0 - 1.0;
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return v.xyz / v.w;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 add = vec3(0.0);
	if (shafts > 0.001) {
		vec2 delta = (uv - sun_uv) / 28.0;
		vec2 p = uv;
		float decay = 1.0;
		float acc = 0.0;
		for (int i = 0; i < 28; i++) {
			p -= delta;
			if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) break;
			float sky = step(0.9995, texture(depth_tex, p).r);
			vec3 c = texture(screen_tex, p).rgb;
			acc += sky * dot(c, vec3(0.3, 0.5, 0.2)) * decay;
			decay *= 0.94;
		}
		float falloff = 1.0 - smoothstep(0.0, 0.9, distance(uv, sun_uv));
		add += sun_color * acc / 28.0 * shafts * falloff;
	}
	if (wet > 0.001) {
		vec3 pv = view_pos(uv, INV_PROJECTION_MATRIX);
		if (-pv.z < 90.0) {
			vec3 n = normalize(cross(dFdx(pv), dFdy(pv)));
			if (dot(n, -pv) < 0.0) n = -n;
			vec3 up_v = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
			float flat_ = smoothstep(0.9, 0.98, dot(n, up_v));
			if (flat_ > 0.0) {
				vec3 vdir = normalize(pv);
				vec3 r = reflect(vdir, up_v);
				vec3 q = pv;
				float stp = 0.6;
				for (int i = 0; i < 24; i++) {
					q += r * stp;
					stp *= 1.18;
					vec4 c = PROJECTION_MATRIX * vec4(q, 1.0);
					vec2 suv = c.xy / c.w * 0.5 + 0.5;
					if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) break;
					vec3 sp = view_pos(suv, INV_PROJECTION_MATRIX);
					if (sp.z > q.z && sp.z - q.z < stp * 2.0) {
						float fres = pow(1.0 - max(dot(-vdir, up_v), 0.0), 3.0);
						float edge = 1.0 - smoothstep(0.75, 1.0, max(abs(suv.x * 2.0 - 1.0), abs(suv.y * 2.0 - 1.0)));
						add += texture(screen_tex, suv).rgb * wet * flat_ * (0.15 + 0.6 * fres) * edge;
						break;
					}
				}
			}
		}
	}
	ALBEDO = add;
}
