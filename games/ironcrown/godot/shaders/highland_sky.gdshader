// 余火高地的天空（路线图 5.1a，D12；ART.md 第十节「天空和远景」）：一张阴云的照片全景（Poly Haven「kloofendal_overcast_puresky」CC0，
// 只取上半球、压成普通照片放进第二章章节包）按时段染色、调亮暗；地平线附近渐变到雾的颜色，和远处被雾吞掉的山接得上。
// 没有太阳的圆盘：本章一直是阴天（「冬天不走了」），日光的方向只在地上的明暗里看得出来。
shader_type sky;

uniform sampler2D pano : source_color, filter_linear, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float energy = 1.0;
uniform vec3 horizon : source_color = vec3(0.6, 0.63, 0.68);
uniform float horizon_fade = 0.22;   // 地平线往上多高（EYEDIR.y）完全是照片
uniform float spin = 0.0;            // 照片转多少（0..1 一圈）：让亮的那片云对着太阳那边

void sky() {
	vec3 d = normalize(EYEDIR);
	float u = fract(atan(d.x, -d.z) / 6.2831853 + 0.5 + spin);
	float v = 1.0 - asin(clamp(d.y, 0.0, 1.0)) / 1.5707963;
	vec3 c = textureLod(pano, vec2(u, clamp(v, 0.002, 0.998)), 0.0).rgb * tint * energy;   // 固定用最细一层：照片左右接缝处导数跳变，自动选层会画出一道竖线
	float k = smoothstep(-0.02, horizon_fade, d.y);
	COLOR = mix(horizon, c, k);
}
