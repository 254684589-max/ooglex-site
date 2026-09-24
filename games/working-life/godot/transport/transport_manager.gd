extends Node
## 交通（自动加载名：TransportManager）。步行永远可用；公交（找到第一份工作后）、
## 地铁（第三章）、出租车（第四章，手机随时叫车）需要付车费并消耗游戏时间，然后把玩家送到目的地。

const STOP_RADIUS := 7.0


func mode(id: String) -> Dictionary:
	return DataDB.transport.get(id, {})


func unlocked(id: String) -> bool:
	if GameManager.debug_enabled and GameManager.has_flag("debug_all_transport"):
		return true
	return Conditions.check(mode(id).get("unlock", {}))


func bus_down() -> bool:
	return int(GameManager.get_value("bus_down_until", -1)) >= TimeManager.day


func stop_pos(stop: Dictionary) -> Vector3:
	var p: Array = stop.get("pos", [0, 0])
	return Vector3(float(p[0]), 0.1, float(p[1]))


## 玩家附近的站点
func nearest_stop(mode_id: String, pos: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := STOP_RADIUS
	for s in mode(mode_id).get("stops", []):
		var d := Vector2(pos.x, pos.z).distance_to(Vector2(stop_pos(s).x, stop_pos(s).z))
		if d < best_d:
			best_d = d
			best = s
	return best


## 可去的目的地：[{id, name, pos, cost, minutes, available, reason}]
func destinations(mode_id: String, from: Vector3) -> Array:
	var out: Array = []
	var m := mode(mode_id)
	if mode_id == "taxi":
		for loc in DataDB.ids("locations"):
			var p := GameManager.location_front(loc)
			if p == Vector3.INF:
				continue
			out.append(_entry(mode_id, loc, DataDB.location_name(loc), p, from))
	else:
		for s in m.get("stops", []):
			out.append(_entry(mode_id, String(s["id"]), String(s["name"]) + "站", stop_pos(s), from))
	return out


func _entry(mode_id: String, id: String, dname: String, p: Vector3, from: Vector3) -> Dictionary:
	var m := mode(mode_id)
	var dist := Vector2(from.x, from.z).distance_to(Vector2(p.x, p.z))
	var cost := int(m.get("fare", 2))
	if mode_id == "taxi":
		cost += int(dist / 100.0 * float(m.get("per_100m", 2.5)))
		if PlayerManager.owned.has("phone_pro"):
			cost = int(cost * 0.9)
	var minutes := float(m.get("base_minutes", 5)) + dist / 100.0 * float(m.get("minutes_per_100m", 1.5))
	if WeatherManager.is_raining():
		minutes *= 1.2
	return {"id": id, "name": dname, "pos": p, "cost": cost, "minutes": minutes, "dist": dist, "near": dist < 20.0}


## 乘车。返回 {ok, text}
func travel(mode_id: String, dest: Dictionary) -> Dictionary:
	if not unlocked(mode_id):
		return {"ok": false, "text": String(mode(mode_id).get("unlock_text", "尚未开通"))}
	if mode_id == "bus" and bus_down():
		return {"ok": false, "text": "公交今天故障停运，改乘地铁或出租车吧"}
	if bool(dest.get("near", false)):
		return {"ok": false, "text": "就在附近，走过去吧"}
	var cost := int(dest.get("cost", 0))
	if not EconomyManager.spend(cost, "交通", "%s → %s" % [String(mode(mode_id).get("name", "")), String(dest.get("name", ""))]):
		return {"ok": false, "text": "车费不够（%s）" % Fmt.yuan(cost)}
	TimeManager.advance(float(dest.get("minutes", 10)), "travel")
	var p: Vector3 = dest.get("pos", Vector3.ZERO)
	if GameManager.player != null and GameManager.player.has_method("teleport"):
		GameManager.player.teleport(p + Vector3(0, 0.2, 0), GameManager.player.rotation.y)
	AudioManager.play_sfx("travel")
	Events.notify("travel", {"mode": mode_id})
	return {"ok": true, "text": "乘%s到达%s（%s，%d 分钟）" % [String(mode(mode_id).get("name", "")), String(dest.get("name", "")), Fmt.yuan(cost), int(dest.get("minutes", 0))]}
