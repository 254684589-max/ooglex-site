class_name DayNight
extends Node3D
## 昼夜：太阳 / 月亮方向与颜色、天空颜色、环境光、雾、夜间灯光、城市窗户亮灯。

var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var night_lights: Array = []
var crane_pivot: Node3D

const SKY_TOP_DAY := Color(0.3, 0.52, 0.84)
const SKY_HOR_DAY := Color(0.74, 0.82, 0.9)
const SKY_TOP_DUSK := Color(0.24, 0.28, 0.52)
const SKY_HOR_DUSK := Color(0.96, 0.6, 0.36)
const SKY_TOP_NIGHT := Color(0.02, 0.035, 0.09)
const SKY_HOR_NIGHT := Color(0.08, 0.1, 0.17)

var _lights_on := false


func _ready() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = SKY_TOP_DAY
	sky_mat.sky_horizon_color = SKY_HOR_DAY
	sky_mat.ground_bottom_color = Color(0.3, 0.3, 0.3)
	sky_mat.ground_horizon_color = SKY_HOR_DAY
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.72)
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_density = 0.0022
	env.fog_light_color = SKY_HOR_DAY
	env.fog_sky_affect = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	apply_quality()


func setup(lights: Array, pivot: Node3D) -> void:
	night_lights = lights
	crane_pivot = pivot


func apply_quality() -> void:
	if sun != null:
		sun.shadow_enabled = bool(GameState.settings.get("shadows", true))
	var vp := get_viewport()
	if vp != null:
		vp.msaa_3d = Viewport.MSAA_2X if bool(GameState.settings.get("msaa", true)) else Viewport.MSAA_DISABLED
		if GameState.touch_mode:
			# 手机：界面放大一些方便点按，3D 画面按 75% 分辨率渲染保证帧率
			get_tree().root.content_scale_factor = 1.3
			vp.scaling_3d_scale = 0.75


func _process(delta: float) -> void:
	update_lighting(TimeSystem.minute_of_day())
	if crane_pivot != null and not get_tree().paused:
		crane_pivot.rotation.y += delta * 0.035


func update_lighting(minute: float) -> void:
	var h := minute / 60.0
	var day := TimeSystem.daylight()
	# 太阳：5 点东升，12 点南方高空，19 点西落
	var t := (h - 5.0) / 14.0 * PI
	# 朝霞 / 晚霞的暖色调
	var dusk := 0.0
	if h > 16.5 and h < 20.2:
		dusk = 1.0 - absf(h - 18.6) / 1.7
	elif h > 4.0 and h < 7.0:
		dusk = 1.0 - absf(h - 5.2) / 1.3
	dusk = clampf(dusk, 0.0, 1.0)
	var sun_dir: Vector3
	if day > 0.02:
		sun_dir = Vector3(cos(t), maxf(sin(t), 0.08) * 1.1, 0.45).normalized()
		sun.light_color = Color(1.0, 0.97, 0.9).lerp(Color(1.0, 0.62, 0.35), dusk)
		sun.light_energy = lerpf(0.15, 1.15, day)
	else:
		# 月光
		sun_dir = Vector3(-0.3, 0.8, 0.5).normalized()
		sun.light_color = Color(0.55, 0.65, 0.95)
		sun.light_energy = 0.22
	sun.look_at_from_position(sun_dir * 100.0, Vector3.ZERO, Vector3.UP if absf(sun_dir.y) < 0.99 else Vector3.FORWARD)
	var top := SKY_TOP_NIGHT.lerp(SKY_TOP_DAY, day).lerp(SKY_TOP_DUSK, dusk * 0.6)
	var hor := SKY_HOR_NIGHT.lerp(SKY_HOR_DAY, day).lerp(SKY_HOR_DUSK, dusk * 0.8)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor
	sky_mat.ground_bottom_color = hor.darkened(0.5)
	env.fog_light_color = hor
	env.ambient_light_color = Color(0.3, 0.36, 0.52).lerp(Color(0.62, 0.66, 0.72), day)
	env.ambient_light_energy = lerpf(0.5, 0.55, day)
	var want_lights := day < 0.4
	if want_lights != _lights_on:
		_lights_on = want_lights
		for l in night_lights:
			if is_instance_valid(l):
				l.visible = want_lights
	Mats.set_glow(clampf((0.55 - day) * 4.0, 0.0, 2.2))
