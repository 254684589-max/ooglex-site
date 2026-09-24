class_name Mats
extends RefCounted
## 材质库。城市几何体的颜色写在顶点色里，整座城市只需要十来种材质，渲染批次少，网页和手机上也能跑。
## 赛博朋克风格：深色混凝土 + 霓虹（不受光照、配合 Glow 泛光）+ 夜间亮起的窗户 + 雨天湿滑反光的路面。
## 以后换正式美术素材时只需要替换这里。

static var _cache: Dictionary = {}
static var window_energy := 0.0
static var wetness := 0.0
## 路灯亮度：黄昏开始亮，夜里最亮（DayNight 每帧设置）
static var lamp_energy := 0.0
const LAMP_WARM := Color(1.0, 0.66, 0.32)
const LAMP_COOL := Color(0.86, 0.92, 1.0)
const FACADES := ["fac_glass", "fac_office", "fac_res", "fac_cyber"]


static func batch(kind: String) -> Material:
	var key := "batch_" + kind
	if _cache.has(key):
		return _cache[key]
	if kind == "beam":
		var sm := ShaderMaterial.new()
		sm.shader = load("res://world/shaders/light_beam.gdshader")
		_cache[key] = sm
		return sm
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
		"roof":
			m.albedo_texture = photo("roof_albedo")
			m.uv1_scale = Vector3(1.0 / 8.0, 1.0 / 8.0, 1)
			m.roughness = 0.92
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		"ad":
			# 广告牌画面：白天是印刷画面，夜里被灯照亮（自发光随路灯亮度）
			m.albedo_texture = ProcTex.ads()
			m.emission_enabled = true
			m.emission = Color.BLACK
			m.emission_texture = ProcTex.ads()
			m.emission_energy_multiplier = lamp_energy * 0.6
			m.roughness = 0.6
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"lamp_warm", "lamp_cool":
			m.roughness = 0.4
			m.emission_enabled = true
			m.emission = LAMP_WARM if kind == "lamp_warm" else LAMP_COOL
			m.emission_energy_multiplier = lamp_energy * 4.0
		"concrete", "stone", "grass", "dirt":
			# 照片材质：混凝土（桥墩、护栏、仓库）、石材（店铺外墙）、草坪、泥土
			var tex := {"concrete": "concrete_albedo", "stone": "stone_albedo", "grass": "grass_albedo", "dirt": "dirt_albedo"}[kind] as String
			var sz := {"concrete": 4.0, "stone": 2.5, "grass": 4.0, "dirt": 6.0}[kind] as float
			m.albedo_texture = photo(tex)
			m.uv1_scale = Vector3(1.0 / sz, 1.0 / sz, 1)
			if kind in ["concrete", "stone"]:
				m.normal_enabled = true
				m.normal_texture = photo("concrete_normal" if kind == "concrete" else "stone_normal")
				m.normal_scale = 0.7
			m.roughness = 0.9
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		"skin":
			# 人物：顶点色按 sRGB 解释，与原来用 albedo_color 的颜色一致
			m.vertex_color_is_srgb = true
			m.roughness = 0.7
		"road", "walk":
			# 真实照片材质（assets/textures/photo，来源见 SOURCES.md）：沥青 5 米一张，人行道方砖 4.8 米一张
			m.albedo_texture = photo("asphalt_albedo") if kind == "road" else photo("paving_albedo")
			var sc := 1.0 / 5.0 if kind == "road" else 1.0 / 4.8
			m.uv1_scale = Vector3(sc, sc, 1)
			m.normal_enabled = true
			m.normal_texture = photo("asphalt_normal") if kind == "road" else photo("concrete_normal")
			m.normal_scale = 0.8
			m.roughness = 0.8 if kind == "road" else 0.85
			m.metallic = 0.05
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		"leaf":
			m.albedo_texture = ProcTex.palm_leaf()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.4
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			# 叶片几乎不反光（否则逆光时会反射明亮的天空、整片发白）；逆光时透出一点绿色
			m.roughness = 0.95
			m.metallic_specular = 0.08
			m.backlight_enabled = true
			m.backlight = Color(0.16, 0.24, 0.06)
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
		# 墙面细节层：真实照片的抹灰 / 混凝土质感，按米平铺（UV2），窗玻璃处由遮罩排除
		m.detail_enabled = true
		m.detail_albedo = photo("plaster_detail")
		m.detail_mask = texs[2]
		m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
		m.uv2_scale = Vector3(1.0 / 3.0, 1.0 / 3.0, 1)


## 照片材质（预先加工好的 webp，tools/bake_photo_textures.gd 生成）
static func photo(name: String) -> Texture2D:
	var key := "photo_" + name
	if not _cache.has(key):
		_cache[key] = load("res://assets/textures/photo/%s.webp" % name)
	return _cache[key]


static func set_window_energy(energy: float) -> void:
	window_energy = energy
	for k in ["win_warm", "win_cool"] + FACADES:
		var m: StandardMaterial3D = batch(k)
		m.emission_energy_multiplier = energy


static func set_lamp_energy(energy: float) -> void:
	if absf(energy - lamp_energy) < 0.005 and _cache.has("batch_lamp_warm"):
		return
	lamp_energy = energy
	for k in ["lamp_warm", "lamp_cool"]:
		(batch(k) as StandardMaterial3D).emission_energy_multiplier = energy * 4.0
	(batch("ad") as StandardMaterial3D).emission_energy_multiplier = energy * 0.6
	# 路灯光锥只在「高」「超高」画质显示
	var beam_on := int(SettingsManager.get_v("quality", 1)) >= 2
	(batch("beam") as ShaderMaterial).set_shader_parameter("intensity", energy * energy * 0.07 if beam_on else 0.0)


## 雨天路面变湿：粗糙度降低、带一点金属感，反射霓虹与灯光
static func set_wetness(w: float) -> void:
	wetness = w
	var road: StandardMaterial3D = batch("road")
	road.roughness = lerpf(0.8, 0.12, w)
	road.metallic = lerpf(0.05, 0.45, w)
	var walk: StandardMaterial3D = batch("walk")
	for k in ["concrete", "stone"]:
		var cm: StandardMaterial3D = batch(k)
		cm.roughness = lerpf(0.9, 0.3, w)
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


## 照片地面（世界坐标三平面映射）：城内空地是混凝土，城外远处是泥土
static func photo_ground(id: String, tex: String, size: float, tint: Color) -> StandardMaterial3D:
	var key := "ground_" + id
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = photo(tex)
	m.albedo_color = tint
	m.roughness = 0.95
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(1.0 / size, 1.0 / size, 1.0 / size)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
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
