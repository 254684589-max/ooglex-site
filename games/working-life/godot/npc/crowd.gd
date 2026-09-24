class_name Crowd
extends Node3D
## 路人（对象池）：固定数量的行人在玩家附近的人行道上来回走动，离得太远就换到玩家附近重新出现。
## 数量随画质、时间（深夜少）和天气（雨天少）变化。每 0.25 秒才检查一次重生，不逐帧扫描。

var points: Array = []
var walkers: Array = []
var _neighbors: Array = []
var _timer := 0.0
var _rng := RandomNumberGenerator.new()


func setup(sidewalk_points: Array) -> void:
	points = sidewalk_points
	_rng.seed = 42
	# 预先计算每个路点的相邻路点（12 米内），行人只在相邻点之间直线行走，不会穿楼
	for i in points.size():
		var nb: Array = []
		for j in points.size():
			if i != j and (points[i] as Vector3).distance_to(points[j]) < 12.5:
				nb.append(j)
		_neighbors.append(nb)
	var n: int = [8, 14, 20][clampi(int(SettingsManager.get_v("quality", 1)), 0, 2)]
	var palette := [Color(0.15, 0.15, 0.2), Color(0.5, 0.1, 0.25), Color(0.1, 0.3, 0.45), Color(0.3, 0.3, 0.3), Color(0.55, 0.45, 0.2), Color(0.1, 0.4, 0.3)]
	for i in n:
		var m := CharacterModel.new()
		m.shirt_color = palette[_rng.randi() % palette.size()]
		m.pants_color = Color(0.12, 0.12, 0.15)
		m.skin_color = Color(0.9, 0.72, 0.58).darkened(_rng.randf() * 0.3)
		m.hair_color = Color(0.08, 0.06, 0.05) if _rng.randf() < 0.8 else Color(0.8, 0.3, 0.6)
		m.accent_color = CityBuilder.NEON_COLORS[i % CityBuilder.NEON_COLORS.size()]
		m.hat = "visor" if i % 4 == 0 else "none"
		m.body_scale = _rng.randf_range(0.92, 1.05)
		m.build_width = [0.94, 1.0, 1.08][_rng.randi() % 3]
		m.sleeves = "long" if _rng.randf() < 0.4 else "short"
		m.draw_distance = 70.0
		m.casts_shadow = false
		add_child(m)
		var w := {"node": m, "anim": AnimationController.new(m), "from": 0, "to": 0, "speed": _rng.randf_range(1.2, 1.9)}
		walkers.append(w)
		_respawn(w, true)


func _respawn(w: Dictionary, anywhere := false) -> void:
	if points.is_empty():
		return
	var p := GameManager.player
	var idx := _rng.randi() % points.size()
	if p != null and not anywhere:
		for tries in 20:
			var cand := _rng.randi() % points.size()
			var d := (points[cand] as Vector3).distance_to(p.global_position)
			if d > 25.0 and d < 60.0:
				idx = cand
				break
	w["from"] = idx
	w["to"] = _pick_next(idx)
	var n: Node3D = w["node"]
	n.global_position = points[idx]


func _pick_next(i: int) -> int:
	var nb: Array = _neighbors[i]
	if nb.is_empty():
		return i
	return int(nb[_rng.randi() % nb.size()])


func _wanted_count() -> int:
	var f := WeatherManager.crowd_factor()
	var h := TimeManager.hour_f()
	if h < 6.0 or h > 23.0:
		f *= 0.3
	return int(round(walkers.size() * f))


func _process(delta: float) -> void:
	var want := _wanted_count()
	_timer += delta
	var check := _timer > 0.25
	if check:
		_timer = 0.0
	var p := GameManager.player
	for i in walkers.size():
		var w: Dictionary = walkers[i]
		var n: Node3D = w["node"]
		n.visible = i < want
		if not n.visible:
			continue
		var target: Vector3 = points[int(w["to"])]
		var to := target - n.global_position
		to.y = 0.0
		var dist := to.length()
		var sp := float(w["speed"])
		if dist < 0.3:
			w["from"] = w["to"]
			w["to"] = _pick_next(int(w["to"]))
		else:
			var dir := to / dist
			n.global_position += dir * sp * delta
			n.rotation.y = lerp_angle(n.rotation.y, atan2(-dir.x, -dir.z), clampf(delta * 6.0, 0.0, 1.0))
		(w["anim"] as AnimationController).update(delta, sp)
		if check and p != null and n.global_position.distance_to(p.global_position) > 80.0:
			_respawn(w)
