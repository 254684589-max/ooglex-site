class_name LampPool
extends Node3D
## 路灯光源池：城里有几百盏路灯，但只在离相机最近的几盏下面放真实的点光源（其余靠灯罩自发光和地面光斑），
## 每 0.4 秒重新挑一次。只在路灯亮着时启用；低画质不启用。

const RANGE := 15.0
var points: Array = []
var lights: Array = []
var _timer := 0.0


func setup(lamp_points: Array) -> void:
	points = lamp_points
	var count: int = [0, 6, 10][clampi(int(SettingsManager.get_v("quality", 1)), 0, 2)]
	if GameManager.touch_mode:
		count = mini(count, 4)
	for i in count:
		var o := OmniLight3D.new()
		o.omni_range = RANGE
		o.omni_attenuation = 0.9
		o.shadow_enabled = false
		o.visible = false
		add_child(o)
		lights.append(o)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or lights.is_empty():
		return
	_timer = 0.4
	var on := Mats.lamp_energy > 0.05
	var cam := get_viewport().get_camera_3d()
	if not on or cam == null:
		for o in lights:
			(o as OmniLight3D).visible = false
		return
	var cp := cam.global_position
	# 挑最近的几盏（简单的部分选择：几百个点，每 0.4 秒一次）
	var best: Array = []
	for p in points:
		var d := (p[0] as Vector3).distance_squared_to(cp)
		if best.size() < lights.size():
			best.append([d, p])
			best.sort_custom(func(a, b): return a[0] < b[0])
		elif d < float(best[-1][0]):
			best[-1] = [d, p]
			best.sort_custom(func(a, b): return a[0] < b[0])
	for i in lights.size():
		var o: OmniLight3D = lights[i]
		if i >= best.size() or float(best[i][0]) > 90.0 * 90.0:
			o.visible = false
			continue
		var p: Array = best[i][1]
		o.visible = true
		o.global_position = p[0]
		o.light_color = Mats.LAMP_WARM if bool(p[1]) else Mats.LAMP_COOL
		o.light_energy = 5.0 * Mats.lamp_energy
