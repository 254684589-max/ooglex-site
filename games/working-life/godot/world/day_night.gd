class_name DayNight
extends Node3D
## 昼夜：太阳 / 月亮方向与颜色、天空、雾、环境光、泛光（Glow）、夜间窗户与路灯。
## 赛博朋克配色：白天是泛黄的雾霾天，黄昏紫红，夜晚深紫蓝，霓虹始终在亮。天气会压暗天空、加浓雾气。

var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var city: CityBuilder
var _night_on := -1

const SKY_TOP_DAY := Color(0.2, 0.36, 0.5)
const SKY_HOR_DAY := Color(0.5, 0.58, 0.64)
const SKY_TOP_DUSK := Color(0.28, 0.12, 0.38)
const SKY_HOR_DUSK := Color(1.0, 0.38, 0.45)
const SKY_TOP_NIGHT := Color(0.03, 0.02, 0.08)
const SKY_HOR_NIGHT := Color(0.16, 0.06, 0.22)


func _ready() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = SKY_TOP_DAY
	sky_mat.sky_horizon_color = SKY_HOR_DAY
	sky_mat.ground_bottom_color = Color(0.05, 0.05, 0.07)
	sky_mat.ground_horizon_color = SKY_HOR_DAY
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.6)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_density = 0.004
	env.fog_light_color = SKY_HOR_DAY
	env.fog_sky_affect = 0.35
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
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


func _process(_delta: float) -> void:
	update_lighting(TimeManager.minute_of_day())


func update_lighting(minute: float) -> void:
	var h := minute / 60.0
	var day := TimeManager.daylight()
	var t := (h - 5.0) / 14.0 * PI
	var dusk := 0.0
	if h > 16.5 and h < 20.4:
		dusk = 1.0 - absf(h - 18.6) / 1.8
	elif h > 4.2 and h < 7.2:
		dusk = 1.0 - absf(h - 5.6) / 1.4
	dusk = clampf(dusk, 0.0, 1.0)
	var weather := WeatherManager.weather
	var gloom := 0.0
	if weather == "rain":
		gloom = 0.55
	elif weather == "cloudy":
		gloom = 0.3
	var sun_dir: Vector3
	if day > 0.02:
		sun_dir = Vector3(cos(t), maxf(sin(t), 0.1) * 1.1, 0.45).normalized()
		sun.light_color = Color(0.92, 0.95, 1.0).lerp(Color(1.0, 0.45, 0.5), dusk)
		sun.light_energy = lerpf(0.15, 0.95, day) * (1.0 - gloom * 0.6)
	else:
		sun_dir = Vector3(-0.3, 0.8, 0.5).normalized()
		sun.light_color = Color(0.5, 0.45, 0.95)
		sun.light_energy = 0.18
	sun.look_at_from_position(sun_dir * 100.0, Vector3.ZERO, Vector3.UP if absf(sun_dir.y) < 0.99 else Vector3.FORWARD)
	var top := SKY_TOP_NIGHT.lerp(SKY_TOP_DAY, day).lerp(SKY_TOP_DUSK, dusk * 0.7)
	var hor := SKY_HOR_NIGHT.lerp(SKY_HOR_DAY, day).lerp(SKY_HOR_DUSK, dusk * 0.8)
	var grey := Color(0.3, 0.32, 0.36).lerp(Color(0.08, 0.07, 0.12), 1.0 - day)
	top = top.lerp(grey, gloom)
	hor = hor.lerp(grey.lightened(0.1), gloom)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor
	sky_mat.ground_bottom_color = hor.darkened(0.6)
	env.fog_light_color = hor.lerp(Color(0.35, 0.15, 0.45), 1.0 - day)
	env.fog_density = 0.0022 + gloom * 0.0035 + (1.0 - day) * 0.0022
	env.ambient_light_color = Color(0.32, 0.25, 0.5).lerp(Color(0.5, 0.56, 0.66), day)
	env.ambient_light_energy = lerpf(0.75, 0.6, day)
	env.glow_intensity = lerpf(1.2, 0.6, day)
	Mats.set_window_energy(clampf((0.75 - day) * 3.0, 0.15, 2.0))
	var night := 1 if day < 0.45 else 0
	if night != _night_on and city != null:
		_night_on = night
		city.set_night(night == 1)
