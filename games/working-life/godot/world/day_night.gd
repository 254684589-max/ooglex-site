class_name DayNight
extends Node3D
## 昼夜：太阳 / 月亮方向与颜色、天空、雾、环境光、泛光（Glow）、夜间窗户与路灯。
## 赛博朋克配色：白天是泛黄的雾霾天，黄昏紫红，夜晚深紫蓝，霓虹始终在亮。天气会压暗天空、加浓雾气。

var sun: DirectionalLight3D
var bounce: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var city: CityBuilder
var _night_on := -1
var _sky_timer := 0.0
var _drift := 0.0

## 调色板（写实一点的洛杉矶式黄昏：天顶偏蓝、地平线橙色雾霾；夜里城市光把低空染成紫色）
const SKY_TOP_DAY := Color(0.2, 0.42, 0.76)
const SKY_HOR_DAY := Color(0.74, 0.8, 0.86)
const SKY_TOP_DUSK := Color(0.3, 0.33, 0.6)
const SKY_HOR_DUSK := Color(1.0, 0.66, 0.46)
const SKY_MID_DAY := Color(0.42, 0.6, 0.85)
const SKY_MID_DUSK := Color(0.8, 0.56, 0.7)
const SKY_MID_NIGHT := Color(0.05, 0.05, 0.13)
const SKY_TOP_NIGHT := Color(0.012, 0.016, 0.045)
const SKY_HOR_NIGHT := Color(0.13, 0.08, 0.2)
const SUN_DAY := Color(1.0, 0.95, 0.86)
const SUN_DUSK := Color(1.0, 0.56, 0.28)


func _ready() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://world/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.6)
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.002
	env.fog_light_color = SKY_HOR_DAY
	env.fog_sun_scatter = 0.35
	env.fog_aerial_perspective = 0.45
	env.fog_sky_affect = 0.12
	env.fog_height = 12.0
	env.fog_height_density = 0.004
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.15
	env.adjustment_color_correction = _grade()
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 80.0
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	# 地面反弹补光（模拟全局光照）：一盏从下往上打的暖色弱光，照亮背光面、屋檐下与车身下半部分
	bounce = DirectionalLight3D.new()
	bounce.name = "GroundBounce"
	bounce.shadow_enabled = false
	bounce.light_specular = 0.0
	bounce.rotation = Vector3(deg_to_rad(70.0), 0.0, 0.0)
	add_child(bounce)
	apply_quality()


## 调色（逐通道曲线）：暗部微微偏紫蓝、亮部偏暖，接近电影感的黄昏色调
static func _grade() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(0.0, 0.0, 0.035))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(1.0, 0.985, 0.95))
	g.add_point(0.22, Color(0.2, 0.2, 0.245))
	g.add_point(0.6, Color(0.615, 0.6, 0.585))
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t


func apply_quality() -> void:
	var q := int(SettingsManager.get_v("quality", 1))
	if sun != null:
		sun.shadow_enabled = bool(SettingsManager.get_v("shadows", true)) and q >= 1
		sun.directional_shadow_max_distance = [60.0, 60.0, 110.0, 150.0][clampi(q, 0, 3)]
		# 超高：阴影贴图 4096、四级级联、柔和阴影
		RenderingServer.directional_shadow_atlas_set_size(4096 if q >= 3 else 2048, true)
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q >= 3 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if q >= 3 else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	if bounce != null:
		bounce.visible = q >= 2
	# 让路灯 / 光锥材质在下一帧按新画质刷新
	Mats.lamp_energy = -1.0
	if env != null:
		env.glow_enabled = q >= 1
	var vp := get_viewport()
	if vp != null:
		vp.msaa_3d = Viewport.MSAA_2X if bool(SettingsManager.get_v("msaa", true)) else Viewport.MSAA_DISABLED
		vp.scaling_3d_scale = [0.7, 0.9, 1.0][clampi(q, 0, 2)]
		if GameManager.touch_mode:
			get_tree().root.content_scale_factor = 1.25
			vp.scaling_3d_scale = minf(vp.scaling_3d_scale, 0.75)
		if not OS.has_feature("web"):
			vp.use_occlusion_culling = q >= 1


func _process(delta: float) -> void:
	_sky_timer -= delta
	_drift += delta * 0.004
	update_lighting(TimeManager.minute_of_day())


func update_lighting(minute: float) -> void:
	var h := minute / 60.0
	var day := TimeManager.daylight()
	var t := (h - 5.0) / 14.0 * PI
	var dusk := 0.0
	if h > 16.5 and h < 20.4:
		dusk = 1.0 - absf(h - 18.6) / 1.9
	elif h > 4.2 and h < 7.2:
		dusk = 1.0 - absf(h - 5.8) / 1.4
	dusk = clampf(dusk, 0.0, 1.0)
	var weather := WeatherManager.weather
	var gloom := 0.0
	if weather == "rain":
		gloom = 0.7
	elif weather == "cloudy":
		gloom = 0.3
	var sun_dir: Vector3
	var sun_col := SUN_DAY.lerp(SUN_DUSK, dusk)
	if day > 0.02:
		sun_dir = Vector3(cos(t), maxf(sin(t), 0.06) * 1.1, 0.45).normalized()
		sun.light_color = sun_col
		# 黄昏太阳贴近地平线、被雾霾削弱：楼的受光面只剩一层暖色，背光面偏蓝紫（接近剪影）
		sun.light_energy = lerpf(0.35, 1.25, day) * (1.0 - gloom * 0.65) * (1.0 - dusk * 0.5)
	else:
		sun_dir = Vector3(-0.3, 0.8, 0.5).normalized()
		sun.light_color = Color(0.55, 0.55, 0.9)
		sun.light_energy = 0.12
	sun.look_at_from_position(sun_dir * 100.0, Vector3.ZERO, Vector3.UP if absf(sun_dir.y) < 0.99 else Vector3.FORWARD)
	var top := SKY_TOP_NIGHT.lerp(SKY_TOP_DAY, day).lerp(SKY_TOP_DUSK, dusk * 0.8)
	var hor := SKY_HOR_NIGHT.lerp(SKY_HOR_DAY, day).lerp(SKY_HOR_DUSK, dusk * 0.9)
	var mid := SKY_MID_NIGHT.lerp(SKY_MID_DAY, day).lerp(SKY_MID_DUSK, dusk * 0.85)
	var grey := Color(0.46, 0.5, 0.55).lerp(Color(0.07, 0.06, 0.1), 1.0 - day)
	top = top.lerp(grey.darkened(0.15), gloom)
	hor = hor.lerp(grey.lightened(0.1), gloom * 0.85)
	mid = mid.lerp(grey, gloom)
	if _sky_timer <= 0.0:
		# 天空参数每 0.2 秒更新一次（每次更新都会重画反射用的立方体贴图）
		_sky_timer = 0.2
		sky_mat.set_shader_parameter("top_color", top)
		sky_mat.set_shader_parameter("horizon_color", hor)
		sky_mat.set_shader_parameter("mid_color", mid)
		sky_mat.set_shader_parameter("ground_color", hor.darkened(0.55))
		sky_mat.set_shader_parameter("sun_color", sun_col * (1.0 - gloom * 0.7))
		sky_mat.set_shader_parameter("sun_dir", sun_dir if day > 0.02 else Vector3(0, -1, 0))
		sky_mat.set_shader_parameter("sun_visible", clampf(day * 3.0, 0.0, 1.0) * (1.0 - gloom))
		sky_mat.set_shader_parameter("haze", lerpf(0.5, 1.3, dusk) * clampf(day * 2.0, 0.0, 1.0))
		sky_mat.set_shader_parameter("cloud_cover", 0.38 + gloom * 0.55)
		var cc := Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.7, 0.55), dusk).lerp(Color(0.16, 0.11, 0.2), 1.0 - day)
		sky_mat.set_shader_parameter("cloud_color", cc.lerp(grey.lightened(0.2), gloom))
		sky_mat.set_shader_parameter("cloud_shadow", Color(0.55, 0.6, 0.7).lerp(Color(0.45, 0.3, 0.42), dusk).lerp(Color(0.05, 0.04, 0.08), 1.0 - day).lerp(grey.darkened(0.2), gloom))
		sky_mat.set_shader_parameter("stars", clampf(1.0 - day * 3.0, 0.0, 1.0) * (1.0 - gloom))
		sky_mat.set_shader_parameter("drift", _drift)
	# 雾色取地平线与中空的混合：黄昏是桃粉到淡紫，远处的楼和山被染成天空色（空气透视）
	# 背光一侧的雾比天空暗：黄昏时整体压暗一些，楼才会呈现偏蓝紫的剪影而不是被雾「漂白」
	env.fog_light_color = hor.lerp(mid, 0.45).darkened(dusk * 0.35).lerp(Color(0.2, 0.12, 0.28), (1.0 - day) * 0.6)
	env.fog_aerial_perspective = 0.45 - dusk * 0.25
	env.fog_density = 0.0011 + gloom * 0.0035 + dusk * 0.0009 + (1.0 - day) * 0.0012
	env.fog_height_density = 0.004 + dusk * 0.01
	env.fog_sun_scatter = 0.18 * day * (1.0 - gloom)
	env.ambient_light_color = Color(0.26, 0.24, 0.42).lerp(top.lerp(hor, 0.35).lerp(Color(0.6, 0.64, 0.72), 0.3), day).lerp(Color(0.42, 0.42, 0.66), dusk * 0.6)
	env.ambient_light_energy = lerpf(0.7, 0.75, day) * (1.0 - dusk * 0.5)
	env.glow_intensity = lerpf(0.8, 0.45, day)
	if bounce != null:
		# 反弹光颜色取太阳色与地面色的混合，强度随太阳高度
		bounce.light_color = sun_col.lerp(Color(0.7, 0.62, 0.55), 0.5)
		bounce.light_energy = 0.22 * day * (1.0 - gloom * 0.6)
	env.tonemap_exposure = lerpf(1.1, 1.0, day)
	# 黄昏开始陆续开灯：窗户与路灯在太阳落山前就亮起来（参考真实城市的蓝调时刻）
	Mats.set_window_energy(clampf((0.9 - day) * 1.6, 0.05, 1.0))
	var lamps := clampf((0.85 - day) / 0.4, 0.0, 1.0) * (1.0 if day < 0.99 else 0.0)
	if gloom > 0.5 and day < 0.99:
		lamps = maxf(lamps, 0.6)
	Mats.set_lamp_energy(lamps)
	var night := 1 if lamps > 0.3 else 0
	if night != _night_on and city != null:
		_night_on = night
		city.set_night(night == 1)
