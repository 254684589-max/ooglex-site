class_name StreetTraffic
extends Node3D
## 地面交通：汽车沿道路右侧车道行驶，跟车保持车距，玩家或玩家的车挡在前面会减速停车（纯视觉，不参与物理碰撞；
## 玩家开的车与车流的碰撞由 PlayerCar 按距离处理）。
## 车的几何体与路边停车共用 BuildingKit.car_geometry；每种车漆一个网格，所有车共享。

const LANE_OFF := 2.1
const EDGE := CityBuilder.LIMIT + 6.0
const GAP := 9.0
var cars: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 31
	var count: int = [6, 16, 26][clampi(int(SettingsManager.get_v("quality", 1)), 0, 2)]
	if GameManager.touch_mode:
		count = mini(count, 12)
	var paints := [Color(0.85, 0.85, 0.86), Color(0.07, 0.07, 0.08), Color(0.42, 0.44, 0.48), Color(0.6, 0.05, 0.08), Color(0.08, 0.18, 0.42), Color(0.95, 0.75, 0.1)]
	var meshes: Array = []
	for pc in paints:
		var mb := MeshBatcher.new()
		mb.chunked = false
		BuildingKit.car_geometry(mb, Vector3.ZERO, Basis.IDENTITY, pc)
		meshes.append(mb.to_mesh())
	for i in count:
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[i % meshes.size()]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 200.0
		add_child(mi)
		var along_x := _rng.randf() < 0.5
		var road: float = CityBuilder.ROADS[_rng.randi() % CityBuilder.ROADS.size()]
		var dir := 1.0 if _rng.randf() < 0.5 else -1.0
		var sp := _rng.randf_range(9.0, 14.0)
		var d := {"node": mi, "x": along_x, "road": road, "dir": dir, "t": _rng.randf_range(-EDGE, EDGE), "speed": sp, "cruise": sp}
		cars.append(d)
		_place(d)


## 车道横向位置：右侧通行
func _lane_pos(d: Dictionary) -> float:
	var dir: float = d["dir"]
	if bool(d["x"]):
		return float(d["road"]) + LANE_OFF * dir
	return float(d["road"]) - LANE_OFF * dir


func _place(d: Dictionary) -> void:
	var n: Node3D = d["node"]
	var t: float = d["t"]
	var lane := _lane_pos(d)
	var dir: float = d["dir"]
	if bool(d["x"]):
		n.position = Vector3(t, 0, lane)
		n.rotation.y = -PI * 0.5 * dir
	else:
		n.position = Vector3(lane, 0, t)
		n.rotation.y = 0.0 if dir < 0 else PI


func _process(delta: float) -> void:
	var dens := WeatherManager.crowd_factor() * 0.4 + 0.6
	# 障碍：玩家本人 + 玩家的私家车（停在路边或正在开）
	var obstacles: Array = []
	if GameManager.player != null:
		obstacles.append(GameManager.player.global_position)
	for car in VehicleManager.nodes():
		obstacles.append((car as Node3D).global_position)
	for i in cars.size():
		var d: Dictionary = cars[i]
		var n: Node3D = d["node"]
		n.visible = float(i) / cars.size() < dens
		if not n.visible:
			continue
		var dir: float = d["dir"]
		var t: float = d["t"]
		var want: float = d["cruise"]
		# 前方最近的同车道车辆
		var ahead := 999.0
		for j in cars.size():
			if j == i:
				continue
			var o: Dictionary = cars[j]
			if bool(o["x"]) != bool(d["x"]) or float(o["road"]) != float(d["road"]) or float(o["dir"]) != dir or not (o["node"] as Node3D).visible:
				continue
			var gap := (float(o["t"]) - t) * dir
			if gap > 0.0 and gap < ahead:
				ahead = gap
		# 玩家或玩家的车在车道上：刹车
		for op in obstacles:
			var pp: Vector3 = op
			var lateral := absf((pp.z if bool(d["x"]) else pp.x) - _lane_pos(d))
			if lateral < 2.2:
				var pgap := ((pp.x if bool(d["x"]) else pp.z) - t) * dir
				if pgap > 0.0 and pgap < ahead + 3.0:
					ahead = minf(ahead, pgap + 2.5)
		if ahead < GAP:
			want = 0.0
		elif ahead < GAP * 2.5:
			want = want * (ahead - GAP) / (GAP * 1.5)
		var sp: float = d["speed"]
		sp = move_toward(sp, want, (18.0 if want < sp else 4.0) * delta)
		d["speed"] = sp
		t += dir * sp * delta
		if absf(t) > EDGE:
			t = -signf(t) * EDGE
		d["t"] = t
		_place(d)
