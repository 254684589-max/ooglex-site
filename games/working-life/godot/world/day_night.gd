class_name DayNight
extends Node3D
## 昼夜：太阳 / 月亮方向与颜色、天空、雾、环境光、泛光（Glow）、夜间窗户与路灯。
## 赛博朋克配色：白天是泛黄的雾霾天，黄昏紫红，夜晚深紫蓝，霓虹始终在亮。天气会压暗天空、加浓雾气。

var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var city: CityBuilder
var _night_on := -1
var _sky_timer := 0.0
var _drift := 0.0

## 调色板（写实一点的洛杉矶式黄昏：天顶偏蓝、地平线橙色雾霾；夜里城市光把低空染成紫色）
const SKY_TOP_DAY := Color(0.2, 0.42, 0.76)
const SKY_HOR_DAY := Color(0.74, 0.8, 0.86)
const SKY_TOP_DUSK := Color(0.2, 0.3, 0.52)
const SKY_HOR_DUSK := Color(1.0, 0.6, 0.36)
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
	apply_quality()


func apply_quality() -> void:
	var q := int(SettingsManager.get_v("quality", 1))
	if sun != null:
		sun.shadow_enabled = bool(SettingsManager.get_v("shadows", true)) and q >= 1
		sun.directional_shadow_max_distance = 60.0 if q < 2 else 110.0
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
		sun.light_energy = lerpf(0.35, 1.25, day) * (1.0 - gloom * 0.65) * (1.0 - dusk * 0.25)
	else:
		sun_dir = Vector3(-0.3, 0.8, 0.5).normalized()
		sun.light_color = Color(0.55, 0.55, 0.9)
		sun.light_energy = 0.12
	sun.look_at_from_position(sun_dir * 100.0, Vector3.ZERO, Vector3.UP if absf(sun_dir.y) < 0.99 else Vector3.FORWARD)
	var top := SKY_TOP_NIGHT.lerp(SKY_TOP_DAY, day).lerp(SKY_TOP_DUSK, dusk * 0.8)
	var hor := SKY_HOR_NIGHT.lerp(SKY_HOR_DAY, day).lerp(SKY_HOR_DUSK, dusk * 0.9)
	var grey := Color(0.46, 0.5, 0.55).lerp(Color(0.07, 0.06, 0.1), 1.0 - day)
	top = top.lerp(grey.darkened(0.15), gloom)
	hor = hor.lerp(grey.lightened(0.1), gloom * 0.85)
	if _sky_timer <= 0.0:
		# 天空参数每 0.2 秒更新一次（每次更新都会重画反射用的立方体贴图）
		_sky_timer = 0.2
		sky_mat.set_shader_parameter("top_color", top)
		sky_mat.set_shader_parameter("horizon_color", hor)
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
	env.fog_light_color = hor.lerp(Color(0.66, 0.62, 0.64), dusk * 0.45).lerp(Color(0.24, 0.12, 0.3), (1.0 - day) * 0.6)
	env.fog_density = 0.0011 + gloom * 0.0035 + (1.0 - day) * 0.0012
	env.fog_sun_scatter = 0.18 * day * (1.0 - gloom)
	env.ambient_light_color = Color(0.26, 0.24, 0.42).lerp(top.lerp(hor, 0.35).lerp(Color(0.6, 0.64, 0.72), 0.3), day)
	env.ambient_light_energy = lerpf(0.7, 0.75, day)
	env.glow_intensity = lerpf(0.8, 0.45, day)
	env.tonemap_exposure = lerpf(1.1, 1.0, day)
	Mats.set_window_energy(clampf((0.75 - day) * 2.0, 0.05, 1.0))
	var night := 1 if day < 0.45 else 0
	if night != _night_on and city != null:
		_night_on = night
		city.set_night(night == 1)
