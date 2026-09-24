class_name Traffic
extends Node3D
## 空中交通：几十辆悬浮车沿着道路上空的航线循环飞行（纯视觉，不参与碰撞）。
## 数量随天气与画质变化；远处的车不更新（节省 CPU）。

const LANES_Y := [16.0, 24.0, 34.0]
var cars: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 9
	var count: int = [10, 22, 32][clampi(int(SettingsManager.get_v("quality", 1)), 0, 2)]
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(1.8, 0.6, 4.0)
	var tail := BoxMesh.new()
	tail.size = Vector3(1.6, 0.12, 0.08)
	var cols := [Color(0.1, 0.1, 0.14), Color(0.3, 0.05, 0.12), Color(0.05, 0.15, 0.3), Color(0.25, 0.25, 0.28)]
	for i in count:
		var car := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = body_mesh
		mi.material_override = Mats.color(cols[i % cols.size()], 0.3)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		car.add_child(mi)
		var tl := MeshInstance3D.new()
		tl.mesh = tail
		tl.material_override = Mats.glow(Color(1.0, 0.15, 0.3))
		tl.position = Vector3(0, 0, 2.02)
		car.add_child(tl)
		var hl := MeshInstance3D.new()
		hl.mesh = tail
		hl.material_override = Mats.glow(Color(0.8, 0.95, 1.0))
		hl.position = Vector3(0, 0, -2.02)
		car.add_child(hl)
		var under := MeshInstance3D.new()
		var um := BoxMesh.new()
		um.size = Vector3(1.2, 0.05, 3.0)
		under.mesh = um
		under.material_override = Mats.glow(Color(0.2, 0.9, 1.0) if i % 2 == 0 else Color(1.0, 0.2, 0.6))
		under.position = Vector3(0, -0.33, 0)
		car.add_child(under)
		for part in [mi, tl, hl, under]:
			(part as MeshInstance3D).visibility_range_end = 220.0
			(part as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(car)
		var along_x := _rng.randf() < 0.5
		var road: float = CityBuilder.ROADS[_rng.randi() % CityBuilder.ROADS.size()]
		var dir := 1.0 if _rng.randf() < 0.5 else -1.0
		var lane: float = LANES_Y[_rng.randi() % LANES_Y.size()]
		var d := {"node": car, "x": along_x, "road": road + dir * 2.0, "dir": dir, "y": lane, "t": _rng.randf_range(-260, 260), "speed": _rng.randf_range(16, 30)}
		cars.append(d)
		_place(d)


func _place(d: Dictionary) -> void:
	var n: Node3D = d["node"]
	var t: float = d["t"]
	if bool(d["x"]):
		n.position = Vector3(t, float(d["y"]), float(d["road"]))
		n.rotation.y = -PI * 0.5 if float(d["dir"]) > 0 else PI * 0.5
	else:
		n.position = Vector3(float(d["road"]), float(d["y"]), t)
		n.rotation.y = PI if float(d["dir"]) > 0 else 0.0


func _process(delta: float) -> void:
	var dens := WeatherManager.crowd_factor() * 0.5 + 0.5
	for i in cars.size():
		var d: Dictionary = cars[i]
		var n: Node3D = d["node"]
		n.visible = float(i) / cars.size() < dens
		if not n.visible:
			continue
		d["t"] = float(d["t"]) + float(d["dir"]) * float(d["speed"]) * delta
		if absf(float(d["t"])) > 300.0:
			d["t"] = -signf(float(d["t"])) * 300.0
		_place(d)
