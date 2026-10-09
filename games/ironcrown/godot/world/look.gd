class_name Look
extends RefCounted
## 画面风格（ART.md、TECH.md 4.6）：写实贴图材质、窗光 / 光晕等特殊材质、雾带噪声、画质分档。
## 写实贴图用 MeshKit 按面生成的 UV（1 单位 = 1 米），不用三向投影（每张贴图采样三次，太费；1.4 实测）。
## 贴图缺文件时退回纯色材质，并打出警告（不会崩）。

## 贴图：编号（Poly Haven，见 assets/SOURCES.md）、每隔多少米平铺一次、染色
const PHOTO := {
	"street": {"id": "cobblestone_floor_03", "meters": 2.4, "tint": Color(0.82, 0.86, 0.92), "fallback": Color("5e6670")},
	"stone": {"id": "stone_wall", "meters": 2.2, "tint": Color(0.6, 0.62, 0.68), "fallback": Color("5a5c62")},
	"plaster": {"id": "plastered_wall_02", "meters": 2.4, "tint": Color(0.62, 0.62, 0.64), "fallback": Color("8a8884")},
	"timber": {"id": "weathered_planks", "meters": 1.6, "tint": Color(0.62, 0.55, 0.5), "fallback": Color("3a2a20")},
	"roof": {"id": "roof_slates_02", "meters": 2.5, "tint": Color(0.75, 0.78, 0.85), "fallback": Color("3c4048")},
	"snow": {"id": "snow_03", "meters": 3.0, "tint": Color(0.86, 0.9, 0.96), "fallback": Color("c9d3dc")},
	"bark": {"id": "bark_brown_02", "meters": 1.2, "tint": Color(0.55, 0.52, 0.5), "fallback": Color("3a3430")},
}
const TIERS := ["low", "medium", "high"]
const WINDOW_COLOR := Color("ffc873")
const LAMP_COLOR := Color("ff9a3c")
const FOG_COLOR := Color("1c2a3a")

static var photo_dir := "res://assets/textures/%s/%s_%s_1k.jpg"   # 测试会临时改成不存在的路径，验证退回纯色
static var _mats := {}
static var _noise: ImageTexture
static var _halo: GradientTexture2D


static func clear_cache() -> void:
	_mats.clear()


## 带写实贴图的材质（同一种只建一次，所有房子共用）
static func mat(kind: String) -> StandardMaterial3D:
	if _mats.has(kind):
		return _mats[kind]
	var cfg: Dictionary = PHOTO[kind]
	var m := StandardMaterial3D.new()
	m.roughness = 1.0
	m.metallic = 0.0
	m.vertex_color_use_as_albedo = true      # 顶点色当作遮蔽（墙脚、屋檐下更暗）
	var tex := {}
	for pair in [["albedo", "diff"], ["normal", "nor_gl"], ["arm", "arm"]]:
		var path := photo_dir % [cfg.id, cfg.id, pair[1]]
		var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
		if t == null:
			push_warning("写实贴图缺文件，退回纯色：" + path)
			tex = {}
			break
		tex[pair[0]] = t
	if tex.is_empty():
		m.albedo_color = cfg.fallback
		m.set_meta("photo", false)
	else:
		m.albedo_texture = tex.albedo
		m.albedo_color = cfg.tint
		m.normal_enabled = true
		m.normal_texture = tex.normal
		m.roughness_texture = tex.arm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.ao_enabled = true
		m.ao_texture = tex.arm
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.ao_light_affect = 0.25
		var s := 1.0 / float(cfg.meters)
		m.uv1_scale = Vector3(s, s, 1.0)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.set_meta("photo", true)
	if kind == "street":
		m.roughness = 0.7                    # 湿石板：乘在 ARM 的粗糙度上，更光一点，月光和灯光在路面上反光
	_mats[kind] = m
	return m


## 亮着的窗户：不受光照、颜色偏暖，开泛光时会晕开
static func glass_lit() -> StandardMaterial3D:
	if not _mats.has("glass_lit"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color("d99a48")       # 比 WINDOW_COLOR 暗一档：不受光照的面直接输出颜色，太亮会过曝成白色
		_mats["glass_lit"] = m
	return _mats["glass_lit"]


## 没亮的窗户：深色、偏光滑，能反一点光
static func glass_dark() -> StandardMaterial3D:
	if not _mats.has("glass_dark"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("141c26")
		m.roughness = 0.25
		m.metallic = 0.3
		_mats["glass_dark"] = m
	return _mats["glass_dark"]


## 看不见的材质（4.2）：合并网格里的一个表面没法单独隐藏，白天把窗外的光晕表面换成它
static func hidden() -> StandardMaterial3D:
	if not _mats.has("hidden"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0, 0, 0, 0)
		_mats["hidden"] = m
	return _mats["hidden"]


## 光晕面片：加法混合的径向渐变，不受雾影响（否则雾色会被叠亮）
static func halo(color: Color, strength := 0.55) -> StandardMaterial3D:
	var key := "halo_%s_%.2f" % [color.to_html(), strength]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = false
		m.disable_fog = true
		# 不受雾影响就要自己随距离淡出：12 米内完整、30 米外消失（否则远处浓雾里会剩一片亮点阵）
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		m.distance_fade_min_distance = 30.0
		m.distance_fade_max_distance = 12.0
		m.albedo_texture = halo_texture()
		m.albedo_color = Color(color.r, color.g, color.b, strength)
		_mats[key] = m
	return _mats[key]


static func halo_texture() -> GradientTexture2D:
	if _halo == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.35))
		_halo = GradientTexture2D.new()
		_halo.gradient = g
		_halo.fill = GradientTexture2D.FILL_RADIAL
		_halo.fill_from = Vector2(0.5, 0.5)
		_halo.fill_to = Vector2(1.0, 0.5)
		_halo.width = 64
		_halo.height = 64
	return _halo


## 白桦树皮（3.5）：没有现成的白桦贴图，用代码画一张——灰白底子、横向的深色皮孔和几块深色斑（主线程同步生成，固定种子）
static func birch() -> StandardMaterial3D:
	if not _mats.has("birch"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 35
		var img := Image.create(64, 128, false, Image.FORMAT_RGB8)
		img.fill(Color(0.82, 0.81, 0.78))
		for i in 900:                                         # 底子上一点点明暗起伏
			var x := rng.randi_range(0, 63)
			var y := rng.randi_range(0, 127)
			var v := rng.randf_range(0.72, 0.9)
			img.set_pixel(x, y, Color(v, v * 0.99, v * 0.95))
		for i in 60:                                          # 横向的皮孔：短而扁的深色横纹
			var x0 := rng.randi_range(0, 63)
			var y0 := rng.randi_range(0, 127)
			var dash := rng.randi_range(4, 14)
			var dark := rng.randf_range(0.12, 0.3)
			for k in dash:
				img.set_pixel((x0 + k) % 64, y0, Color(dark, dark, dark * 0.95))
				if k % 3 != 0:
					img.set_pixel((x0 + k) % 64, (y0 + 1) % 128, Color(dark + 0.1, dark + 0.1, dark + 0.08))
		for i in 6:                                           # 几块深色斑（树皮剥落、枝条脱落的疤）
			var cx := rng.randi_range(0, 63)
			var cy := rng.randi_range(0, 127)
			for k in 40:
				var px := (cx + rng.randi_range(-4, 4)) % 64
				var py := clampi(cy + rng.randi_range(-3, 3), 0, 127)
				img.set_pixel(px if px >= 0 else px + 64, py, Color(0.16, 0.15, 0.14))
		img.generate_mipmaps()
		var m := StandardMaterial3D.new()
		m.albedo_texture = ImageTexture.create_from_image(img)
		m.roughness = 0.9
		m.vertex_color_use_as_albedo = true
		m.uv1_scale = Vector3(2.0, 0.5, 1.0)                  # 一圈约半米、竖着两米一个循环
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_mats["birch"] = m
	return _mats["birch"]


## 雾带用的无缝噪声（主线程同步生成：网页无线程版不能依赖 NoiseTexture2D 的后台生成）
static func noise_texture() -> ImageTexture:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.seed = 7
		n.frequency = 0.012
		n.fractal_octaves = 4
		var img := n.get_seamless_image(256, 256)
		img.generate_mipmaps()
		_noise = ImageTexture.create_from_image(img)
	return _noise


static func fog_material(density: float, reduced_motion := false) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/fog_plane.gdshader")
	sm.set_shader_parameter("noise_tex", noise_texture())
	sm.set_shader_parameter("density", density)
	sm.set_shader_parameter("color", Color(0.45, 0.55, 0.66))
	sm.set_shader_parameter("drift", Vector2.ZERO if reduced_motion else Vector2(0.012, 0.004))
	return sm


## 各向异性过滤（斜看地面更清楚）：低画质关掉，省采样
static func set_anisotropic(on: bool) -> void:
	for k in PHOTO:
		mat(k).texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC if on else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## 画质默认值：触屏设备低档，其余中档（TECH.md 第五节）
static func default_tier() -> String:
	return "low" if DisplayServer.is_touchscreen_available() else "medium"
