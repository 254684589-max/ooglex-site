class_name Mats
extends RefCounted
## 材质库。城市几何体的颜色写在顶点色里，整座城市只需要十来种材质，渲染批次少，网页和手机上也能跑。
## 赛博朋克风格：深色混凝土 + 霓虹（不受光照、配合 Glow 泛光）+ 夜间亮起的窗户 + 雨天湿滑反光的路面。
## 以后换正式美术素材时只需要替换这里。

static var _cache: Dictionary = {}
static var window_energy := 0.0
static var wetness := 0.0
const FACADES := ["fac_glass", "fac_office", "fac_res", "fac_cyber"]


static func batch(kind: String) -> Material:
	var key := "batch_" + kind
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	match kind:
		"metal":
			m.metallic = 0.6
			m.roughness = 0.35
		"neon", "holo":
			# 霓虹：不受光照，颜色即亮度；配合环境泛光
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			if kind == "holo":
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.albedo_color = Color(1, 1, 1, 0.55)
		"win_warm", "win_cool":
			m.roughness = 0.3
			m.metallic = 0.2
			m.emission_enabled = true
			m.emission = Color(1.0, 0.7, 0.42) if kind == "win_warm" else Color(0.4, 0.85, 1.0)
			m.emission_energy_multiplier = window_energy
		"glass":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 0.08
			m.metallic = 0.5
			m.albedo_color = Color(1, 1, 1, 0.45)
		"decal":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.albedo_color = Color(1, 1, 1, 0.5)
		"water":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.05
			m.metallic = 0.6
			m.albedo_color = Color(1, 1, 1, 0.8)
		"skin":
			# 人物：顶点色按 sRGB 解释，与原来用 albedo_color 的颜色一致
			m.vertex_color_is_srgb = true
			m.roughness = 0.7
		"road", "walk":
			# 水平面的 UV 是世界坐标 (x, z)：沥青 8 米一张，地砖 4.8 米一张
			m.albedo_texture = ProcTex.asphalt() if kind == "road" else ProcTex.paving()
			var sc := 1.0 / 8.0 if kind == "road" else 1.0 / 4.8
			m.uv1_scale = Vector3(sc, sc, 1)
			m.normal_enabled = true
			m.normal_texture = ProcTex.bumps()
			m.normal_scale = 0.3
			m.roughness = 0.8 if kind == "road" else 0.85
			m.metallic = 0.05
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		"leaf":
			m.albedo_texture = ProcTex.palm_leaf()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.4
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 0.7
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_:
			if kind.begins_with("fac_"):
				_facade(m, kind.substr(4))
			else:
				m.roughness = 0.88
	_cache[key] = m
	return m


## 建筑立面：程序贴图按世界坐标平铺（24 米 × 28.8 米一张 = 8 开间 × 8 层），夜里窗户按灯光图亮起
static func _facade(m: StandardMaterial3D, style: String) -> void:
	var texs := ProcTex.facade(style)
	m.albedo_texture = texs[0]
	m.uv1_scale = Vector3(1.0 / (ProcTex.BAYS * ProcTex.BAY_W), -1.0 / (ProcTex.FLOORS * ProcTex.FLOOR_H), 1)
	m.emission_enabled = true
	# 默认的 ADD 运算是「颜色 + 贴图」，所以颜色要是黑的，只让灯光图发光
	m.emission = Color.BLACK
	m.emission_texture = texs[1]
	m.emission_energy_multiplier = window_energy
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if style == "glass":
		m.metallic = 0.45
		m.roughness = 0.22
	elif style == "cyber":
		m.metallic = 0.3
		m.roughness = 0.45
	else:
		m.roughness = 0.82


static func set_window_energy(energy: float) -> void:
	window_energy = energy
	for k in ["win_warm", "win_cool"] + FACADES:
		var m: StandardMaterial3D = batch(k)
		m.emission_energy_multiplier = energy


## 雨天路面变湿：粗糙度降低、带一点金属感，反射霓虹与灯光
static func set_wetness(w: float) -> void:
	wetness = w
	var road: StandardMaterial3D = batch("road")
	road.roughness = lerpf(0.8, 0.12, w)
	road.metallic = lerpf(0.05, 0.45, w)
	var walk: StandardMaterial3D = batch("walk")
	walk.roughness = lerpf(0.85, 0.2, w)
	walk.metallic = lerpf(0.05, 0.3, w)
	var g := _cache.get("ground_main") as StandardMaterial3D
	if g != null:
		g.roughness = lerpf(0.95, 0.2, w)
		g.metallic = lerpf(0.0, 0.35, w)


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


## 自发光纯色（霓虹招牌、角色身上的发光条）
static func glow(c: Color) -> StandardMaterial3D:
	var key := "glow_%s" % c.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if c.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = m
	return m


## 不受光照的半透明材质（任务标记、光柱）
static func marker(c: Color) -> StandardMaterial3D:
	var key := "u_%s" % c.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = m
	return m


## 地面材质：带噪声纹理，避免大片纯色
static func ground(id: String, base: Color, variation: Color, scale := 0.08) -> StandardMaterial3D:
	var key := "ground_" + id
	if _cache.has(key):
		return _cache[key]
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.03
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
	m.roughness = 0.95
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_cache[key] = m
	return m


static func hex(s: String, fallback := Color.WHITE) -> Color:
	if s == "" or not Color.html_is_valid(s):
		return fallback
	return Color.html(s)


static func clear() -> void:
	_cache.clear()
