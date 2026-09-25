extends Node
## 私家车（自动加载名：VehicleManager）。车型见 data/vehicles.json。
## 负责：买车（全款，现金不够自动从银行卡扣）、转卖、代驾把车送到身边、每月 1 日扣保险停车保养费、
## 下车时按行驶里程结算油费、体面度，以及存档。车在世界里的实体是 PlayerCar（transport/player_car.gd）。

signal cars_changed

## 叫代驾把车开到身边的费用
const VALET_FEE := 80
## 买车后几天内每天早上心情加成
const NEW_CAR_MOOD := 8.0

## 拥有的车：[{uid, model, paint, pos: [x, y, z], yaw, km}]
var owned: Array = []
## 正在驾驶的车 uid（""：步行）
var driving := ""
## 本次驾驶累计里程（米），下车时结算油费
var trip_m := 0.0
## 已扣过月费的月份 key
var paid_month := ""
var _next_uid := 1
## 世界里的车节点：uid → PlayerCar
var _nodes: Dictionary = {}


func _ready() -> void:
	TimeManager.day_changed.connect(_on_day_changed)


func reset() -> void:
	# 还在车里（读档 / 新游戏）：先把人从车里放出来，不结算油费、不改存档数据
	var p := GameManager.player as Player
	if p != null and p.vehicle != null:
		var old := p.vehicle
		old.driver = null
		p.exit_vehicle(old, old.global_position + Vector3(0, 2.0, 0))
	for n in _nodes.values():
		if is_instance_valid(n):
			(n as Node).queue_free()
	_nodes.clear()
	owned.clear()
	driving = ""
	trip_m = 0.0
	paid_month = ""
	_next_uid = 1


func model(id: String) -> Dictionary:
	return DataDB.vehicles.get(id, {})


func has_car() -> bool:
	return not owned.is_empty()


func is_driving() -> bool:
	return driving != ""


func car(uid: String) -> Dictionary:
	for c in owned:
		if String(c["uid"]) == uid:
			return c
	return {}


func node(uid: String) -> PlayerCar:
	var n = _nodes.get(uid)
	return n if is_instance_valid(n) else null


func nodes() -> Array:
	var out: Array = []
	for n in _nodes.values():
		if is_instance_valid(n):
			out.append(n)
	return out


func active_node() -> PlayerCar:
	return node(driving) if driving != "" else null


## 体面度：名下最好的那辆车
func prestige() -> float:
	var best := 0.0
	for c in owned:
		best = maxf(best, float(model(String(c["model"])).get("prestige", 0)))
	return best


## 转卖能拿回的钱（计入净资产）
func resale_value() -> int:
	var total := 0
	for c in owned:
		total += _resale(c)
	return total


func _resale(c: Dictionary) -> int:
	var m := model(String(c["model"]))
	# 每开 1000 公里再折 2%，最低剩三成
	var wear := clampf(1.0 - float(c.get("km", 0.0)) / 1000.0 * 0.02, 0.5, 1.0)
	return int(float(m.get("price", 0)) * float(m.get("resale", 0.6)) * wear)


func monthly_cost() -> int:
	var total := 0
	for c in owned:
		total += int(model(String(c["model"])).get("monthly", 0))
	return total


## 买车：返回提示文字
func buy(model_id: String, paint_idx := 0) -> String:
	var m := model(model_id)
	if m.is_empty():
		return "没有这款车"
	if owned.size() >= 3:
		return "最多同时拥有 3 辆车，先卖掉一辆吧"
	var price := int(m["price"])
	if not EconomyManager.can_afford(price):
		return "钱不够：%s 需要 %s（现金 + 银行卡）" % [String(m["name"]), Fmt.yuan(price)]
	if not EconomyManager.spend(price, "交通", "买车：" + String(m["name"])):
		return "付款失败"
	var paints: Array = m.get("paints", ["#cccccc"])
	var c := {"uid": "car%d" % _next_uid, "model": model_id, "paint": String(paints[clampi(paint_idx, 0, paints.size() - 1)]), "pos": [], "yaw": 0.0, "km": 0.0, "bought_day": TimeManager.day}
	_next_uid += 1
	owned.append(c)
	# 当月已买的车，当月不再扣月费
	paid_month = TimeManager.month_key()
	_spawn(c)
	deliver(String(c["uid"]))
	PlayerManager.change("mood", NEW_CAR_MOOD)
	AudioManager.play_sfx("coin")
	cars_changed.emit()
	Events.money_changed.emit()
	return "提车了！%s 已经停在你附近的路边（地图上的车标）。走过去按 E 上车。" % String(m["name"])


func sell(uid: String) -> String:
	var c := car(uid)
	if c.is_empty():
		return "没有这辆车"
	if driving == uid:
		return "先下车再卖"
	var money := _resale(c)
	EconomyManager.earn(money, "交通", "卖车：" + String(model(String(c["model"])).get("name", "")), true)
	var n := node(uid)
	if n != null:
		n.queue_free()
	_nodes.erase(uid)
	owned.erase(c)
	cars_changed.emit()
	return "卖掉了，%s 已转入银行卡" % Fmt.yuan(money)


## 代驾：把车开到玩家附近的路边
func valet(uid: String) -> String:
	var c := car(uid)
	if c.is_empty():
		return "没有这辆车"
	if driving == uid:
		return "你就在车里"
	if not EconomyManager.spend(VALET_FEE, "交通", "代驾送车"):
		return "钱不够付代驾费 %s" % Fmt.yuan(VALET_FEE)
	deliver(uid)
	return "代驾把车开到了你附近的路边（%s）" % Fmt.yuan(VALET_FEE)


## 把车放到玩家附近的路边（右侧车道外侧，车头顺着车道方向）
func deliver(uid: String) -> void:
	var p := GameManager.player
	var from := p.global_position if p != null else Vector3.ZERO
	var n0 := node(uid)
	var spot := curb_spot(from, n0.get_rid() if n0 != null else RID())
	var c := car(uid)
	c["pos"] = [spot.origin.x, spot.origin.y, spot.origin.z]
	c["yaw"] = spot.basis.get_euler().y
	var n := node(uid)
	if n == null:
		_spawn(c)
		n = node(uid)
	if n != null:
		n.place(spot.origin, float(c["yaw"]))


## 离某点最近、没有被占用的路边停车位：先找路缘（路边停着的车、灯杆会挡住），不行就停在行车道上
func curb_spot(from: Vector3, exclude := RID()) -> Transform3D:
	var cands: Array = []
	var lim := CityBuilder.LIMIT - 12.0
	for road in CityBuilder.ROADS:
		for along_x in [true, false]:
			for side in [-1.0, 1.0]:
				for lateral in [CityBuilder.ROAD_HALF - 1.3, 1.9]:
					var off: float = float(road) + side * lateral
					var t0 := clampf(from.x if along_x else from.z, -lim, lim)
					for k in range(-6, 7):
						var t := t0 + k * 5.0
						if absf(t) > lim:
							continue
						# 离路口远一点，别停在十字路口中间
						var in_junction := false
						for r2 in CityBuilder.ROADS:
							if absf(t - float(r2)) < CityBuilder.ROAD_HALF + 4.0:
								in_junction = true
						if in_junction:
							continue
						var pos := Vector3(t, 0.02, off) if along_x else Vector3(off, 0.02, t)
						# 右侧通行：车头朝向让这一侧是行驶方向的右边
						var yaw: float
						if along_x:
							yaw = -PI * 0.5 if side > 0 else PI * 0.5
						else:
							yaw = 0.0 if side > 0 else PI
						# 路缘位优先：同样距离时行车道位多算 8 米
						var d := pos.distance_to(Vector3(from.x, 0.02, from.z)) + (8.0 if lateral < 2.0 else 0.0)
						cands.append([d, Transform3D(Basis(Vector3.UP, yaw), pos)])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for c in cands:
		if _spot_free(c[1], exclude):
			return c[1]
	return cands[0][1] if not cands.is_empty() else Transform3D()


func _spot_free(xf: Transform3D, exclude := RID()) -> bool:
	var world := _world() as Node3D
	if world == null or not world.is_inside_tree():
		return true
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.3, 1.2, 5.0)
	q.shape = box
	q.transform = Transform3D(xf.basis, xf.origin + Vector3(0, 0.95, 0))
	q.collision_mask = 1 | 4 | 32
	if exclude.is_valid():
		q.exclude = [exclude]
	return world.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _spawn(c: Dictionary) -> void:
	var world := _world()
	if world == null:
		return
	var n := PlayerCar.new()
	n.setup(c)
	world.add_child(n)
	_nodes[String(c["uid"])] = n
	var pos: Array = c.get("pos", [])
	if pos.size() == 3:
		n.place(Vector3(float(pos[0]), float(pos[1]), float(pos[2])), float(c.get("yaw", 0.0)))


func _world() -> Node:
	if GameManager.main != null and is_instance_valid(GameManager.main):
		return GameManager.main
	return null


## 上车 / 下车（由 PlayerCar 调用）
func on_enter(uid: String) -> void:
	driving = uid
	trip_m = 0.0
	cars_changed.emit()


func on_exit(uid: String) -> void:
	var c := car(uid)
	var n := node(uid)
	if n != null and not c.is_empty():
		var p := n.global_position
		c["pos"] = [p.x, p.y, p.z]
		c["yaw"] = n.rotation.y
	driving = ""
	settle_fuel(uid)
	cars_changed.emit()


## 结算这趟的油费
func settle_fuel(uid: String) -> int:
	var c := car(uid)
	if c.is_empty() or trip_m < 1.0:
		trip_m = 0.0
		return 0
	var km := trip_m / 1000.0
	c["km"] = float(c.get("km", 0.0)) + km
	var fee := int(ceil(km * float(model(String(c["model"])).get("fuel_per_km", 1.0))))
	trip_m = 0.0
	if fee > 0:
		EconomyManager.charge(fee, "交通", "油费 %.1f 公里" % km)
		Events.say("这一趟开了 %.1f 公里，油费 %s" % [km, Fmt.yuan(fee)], "info")
	return fee


func add_distance(m: float) -> void:
	trip_m += m


func _on_day_changed(_day: int) -> void:
	if owned.is_empty():
		return
	for c in owned:
		if TimeManager.day - int(c.get("bought_day", -99)) <= 3:
			PlayerManager.change("mood", 2.0)
	var mk := TimeManager.month_key()
	if TimeManager.day_of_month() == 1 and paid_month != mk:
		paid_month = mk
		var fee := monthly_cost()
		if fee > 0:
			EconomyManager.charge(fee, "交通", "车辆保险 / 停车 / 保养")
			Events.say("本月用车费用（保险、停车、保养）%s 已扣除" % Fmt.yuan(fee), "info")


## 世界重建后（读档、新游戏）按数据生成车辆
func respawn_all() -> void:
	for n in _nodes.values():
		if is_instance_valid(n):
			(n as Node).queue_free()
	_nodes.clear()
	for c in owned:
		if (c.get("pos", []) as Array).size() != 3:
			continue
		_spawn(c)


func to_dict() -> Dictionary:
	# 正在开车时存档：记下车的当前位置
	if driving != "":
		var n := node(driving)
		var c := car(driving)
		if n != null and not c.is_empty():
			c["pos"] = [n.global_position.x, n.global_position.y, n.global_position.z]
			c["yaw"] = n.rotation.y
	return {"owned": owned.duplicate(true), "driving": driving, "paid_month": paid_month, "next_uid": _next_uid}


func from_dict(d: Dictionary) -> void:
	reset()
	for c in d.get("owned", []):
		if typeof(c) == TYPE_DICTIONARY and not model(String(c.get("model", ""))).is_empty():
			owned.append(c)
	paid_month = String(d.get("paid_month", ""))
	_next_uid = int(d.get("next_uid", owned.size() + 1))
	respawn_all()
	var was := String(d.get("driving", ""))
	cars_changed.emit()
	if was != "" and node(was) != null and GameManager.player != null:
		# 读档时如果在开车，就回到车里
		node(was).call_deferred("enter", GameManager.player)
