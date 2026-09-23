class_name Mats
extends RefCounted
## 材质库。灰盒阶段全部用纯色材质：颜色写在顶点色里，整片工地只需要少数几种材质，
## 渲染批次少，网页和手机上也能跑得动。以后换正式美术素材时只需要替换这里。

static var _cache: Dictionary = {}
static var glow_energy := 0.0


static func batch(kind: String) -> Material:
	var key := "batch_" + kind
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	match kind:
		"metal":
			m.metallic = 0.55
			m.roughness = 0.45
		"glow":
			# 夜间发光：灯头、城市窗户。亮度由 DayNight 调节
			m.roughness = 0.6
			m.emission_enabled = true
			m.emission = Color(1.0, 0.86, 0.6)
			m.emission_energy_multiplier = glow_energy
		"glass":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 0.35
		"net":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 1.0
		_:
			m.roughness = 0.92
	_cache[key] = m
	return m


static func set_glow(energy: float) -> void:
	glow_energy = energy
	var m: StandardMaterial3D = batch("glow")
	m.emission_energy_multiplier = energy


## 普通纯色材质（角色、可交互物体等单独的网格使用）
static func color(c: Color, roughness := 0.85) -> StandardMaterial3D:
	var key := "c_%s_%.2f" % [c.to_html(), roughness]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = roughness
	if c.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cache[key] = m
	return m


## 不受光照的半透明材质（卸货区地标、引导光柱、放置预览）
static func marker(c: Color) -> StandardMaterial3D:
	var key := "u_%s" % c.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	_cache[key] = m
	return m


## 地面材质：带一点噪声纹理，避免大片纯色
static func ground(base: Color, variation: Color, scale := 0.08) -> StandardMaterial3D:
	var key := "g_%s_%s" % [base.to_html(), variation.to_html()]
	if _cache.has(key):
		return _cache[key]
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var grad := Gradient.new()
	grad.set_color(0, variation)
	grad.set_color(1, base)
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = grad
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_cache[key] = m
	return m


static func clear() -> void:
	_cache.clear()
