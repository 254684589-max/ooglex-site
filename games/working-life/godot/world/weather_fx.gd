class_name WeatherFX
extends Node3D
## 天气画面与声音：雨丝粒子（跟随镜头）、路面变湿反光、雨声环境音。

var rain: CPUParticles3D
var target: Node3D
var _wet := 0.0


func _ready() -> void:
	rain = CPUParticles3D.new()
	rain.name = "Rain"
	rain.amount = 900
	rain.lifetime = 0.9
	rain.preprocess = 1.0
	rain.local_coords = false
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(22, 1, 22)
	rain.direction = Vector3(0.1, -1, 0.05)
	rain.spread = 3.0
	rain.gravity = Vector3(0, -30, 0)
	rain.initial_velocity_min = 22.0
	rain.initial_velocity_max = 28.0
	var qm := QuadMesh.new()
	qm.size = Vector2(0.025, 0.7)
	rain.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.7, 0.8, 1.0, 0.35)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	rain.material_override = m
	rain.emitting = false
	add_child(rain)
	WeatherManager.weather_changed.connect(_on_weather)
	_on_weather(WeatherManager.weather)


func _on_weather(w: String) -> void:
	var on := w == "rain"
	rain.emitting = on
	AudioManager.set_ambience(1, "rain" if on else "")


func _process(delta: float) -> void:
	if target != null and is_instance_valid(target):
		rain.global_position = target.global_position + Vector3(0, 14, 0)
	var want := 1.0 if WeatherManager.weather == "rain" else 0.0
	if absf(want - _wet) > 0.001:
		_wet = move_toward(_wet, want, delta * (0.2 if want > _wet else 0.05))
		Mats.set_wetness(_wet)
