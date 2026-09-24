class_name PostFX
extends Node
## 「超高」画质的后期效果（网页兼容渲染器里模拟电脑版的高画质）：
##   环境光遮蔽（乘法全屏层）+ 光柱与雨天路面反射（加法全屏层）。
## 两个全屏四边形挂在当前相机下；相机切换时自动跟过去。画质低于「超高」时隐藏。

var ao_quad: MeshInstance3D
var light_quad: MeshInstance3D
var ao_mat: ShaderMaterial
var light_mat: ShaderMaterial
var day_night: DayNight


func _ready() -> void:
	ao_mat = ShaderMaterial.new()
	ao_mat.shader = load("res://world/shaders/postfx_ao.gdshader")
	ao_mat.render_priority = 126
	light_mat = ShaderMaterial.new()
	light_mat.shader = load("res://world/shaders/postfx_light.gdshader")
	light_mat.render_priority = 127
	ao_quad = _quad(ao_mat, "PostAO")
	light_quad = _quad(light_mat, "PostLight")


func _quad(mat: ShaderMaterial, n: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mi.mesh = q
	mi.material_override = mat
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 0, -1)
	return mi


static func enabled() -> bool:
	return int(SettingsManager.get_v("quality", 1)) >= 3


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var on := enabled() and cam != null
	for q in [ao_quad, light_quad]:
		var mi: MeshInstance3D = q
		if on and mi.get_parent() != cam:
			if mi.get_parent() != null:
				mi.get_parent().remove_child(mi)
			cam.add_child(mi)
		mi.visible = on
	if not on:
		return
	# 光柱：太阳在屏幕上的位置；太阳在身后或在地平线下时关闭
	var shafts := 0.0
	if day_night != null and day_night.sun != null:
		var sun_dir := -day_night.sun.global_transform.basis.z
		var far_pt := cam.global_position - sun_dir * 1000.0
		var fwd := -cam.global_transform.basis.z
		var facing := fwd.dot(-sun_dir)
		if facing > 0.1 and not cam.is_position_behind(far_pt):
			var sp := cam.unproject_position(far_pt)
			var vs := get_viewport().get_visible_rect().size
			light_mat.set_shader_parameter("sun_uv", Vector2(sp.x / vs.x, 1.0 - sp.y / vs.y))
			var day := TimeManager.daylight()
			var low := clampf(1.0 - (-sun_dir).y * 2.5, 0.0, 1.0)
			shafts = clampf(facing, 0.0, 1.0) * low * day * (1.0 - (0.7 if WeatherManager.weather == "rain" else 0.0)) * 1.6
			light_mat.set_shader_parameter("sun_color", day_night.sun.light_color)
	light_mat.set_shader_parameter("shafts", shafts)
	light_mat.set_shader_parameter("wet", Mats.wetness * 0.9)
	var night := 1.0 - TimeManager.daylight()
	ao_mat.set_shader_parameter("strength", lerpf(0.75, 0.5, night))
