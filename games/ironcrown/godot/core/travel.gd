class_name Travel
extends RefCounted
## 旅行地图的规则（路线图 4.2；STORY.md 4.2「旅行地图：点一下就走，本章路上没有随机遭遇」）。只管数据和能不能走，不碰界面（ui/travel_map.gd）。
## 数据在 data/travel.json：地点（名字、区域与出生点、第几章起出现、地图上的位置）和路线（从哪到哪、路上怎么走、到了是什么时段）。
## area 为空的地点 = 还没做好：地图上照样画出来、写明「还没做好」，不能去。
## 只有站在出发的地方（霜渡镇宅邸门口的路牌，组 travel_point）才能出发；别处按 M 打开只能看。
## 读过的数据缓存在 Engine 的元数据里（static var 存字典在退出时会报资源没释放，dialogue_runner.gd 同样的做法）；测试可以换一份。

const PATH := "res://data/travel.json"
const META := "ic_travel"
const ICONS := ["town", "village", "castle"]
const DEPART_RADIUS := 6.0        # 离出发点（路牌）多近按 M 打开地图也能出发（第一章开场站在宅邸门口，离路牌 4.7 米）


static func data() -> Dictionary:
	if Engine.has_meta(META):
		return Engine.get_meta(META)
	var d := {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f:
		var j := JSON.new()
		if j.parse(f.get_as_text()) == OK and j.data is Dictionary:
			d = j.data
	if d.is_empty():
		push_warning("旅行地图数据读不出来：" + PATH)
	Engine.set_meta(META, d)
	return d


## 测试用：换一份数据（null = 回到 data/travel.json）
static func override(d: Variant) -> void:
	if d == null:
		Engine.remove_meta(META)
	else:
		Engine.set_meta(META, d)


static func place(id: String) -> Dictionary:
	return data().get("places", {}).get(id, {})


static func name_of(id: String) -> String:
	return str(place(id).get("name", id))


## 这一章地图上有哪些地点（按数据里的顺序）
static func places(chapter: int) -> Array:
	var out := []
	var ps: Dictionary = data().get("places", {})
	for id in ps:
		if int(ps[id].get("chapter", 1)) <= chapter:
			out.append(str(id))
	return out


## 这个区域是地图上的哪个地点（"" = 不是地图上的地点，例如酒馆里）
static func place_of_area(area: String) -> String:
	var ps: Dictionary = data().get("places", {})
	for id in ps:
		if str(ps[id].get("area", "")) == area and area != "":
			return str(id)
	return ""


## 这个地点做好了没有（区域登记过）
static func built(id: String) -> bool:
	var a := str(place(id).get("area", ""))
	return a != "" and Areas.known(a)


static func route(from: String, to: String) -> Dictionary:
	for r in data().get("routes", []):
		if str(r.get("from", "")) == from and str(r.get("to", "")) == to:
			return r
	return {}


## 从 from 去 to 中间要经过哪儿（只看一站）："" = 没有
static func via(from: String, to: String) -> String:
	for r in data().get("routes", []):
		var mid := str(r.get("to", ""))
		if str(r.get("from", "")) == from and not route(mid, to).is_empty():
			return mid
	return ""


## 现在能不能从 from 去 to：{ok, why（不能走的原因，给玩家看）, route}。
## at_departure：是不是站在出发的地方（路牌旁边）；不是的话只能看
static func check(chapter: int, from: String, to: String, at_departure: bool) -> Dictionary:
	var why := ""
	var r := route(from, to)
	if not to in places(chapter):
		why = "这一章去不了那里。"
	elif to == from:
		why = "你就在这里。"
	elif not built(to):
		why = str(place(to).get("pending", "%s还没做好。" % name_of(to)))
	elif from == "":
		why = "要先回到地图上的地方才能出发。"
	elif r.is_empty():
		var mid := via(from, to)
		why = ("从这里去不了，先到%s。" % name_of(mid)) if mid != "" else "从这里没有路过去。"
	elif not at_departure:
		why = "走到%s那里才能出发。" % str(place(from).get("depart_at", "出发的地方"))
	return {"ok": why == "", "why": why, "route": r}


## 检查数据（测试用）：地点的区域、出生点、位置、图标；路线两头的地点、到达时段
static func validate() -> Array:
	var errors := []
	var ps: Dictionary = data().get("places", {})
	if ps.is_empty():
		errors.append("没有地点")
	for id in ps:
		var p: Dictionary = ps[id]
		if str(p.get("name", "")) == "":
			errors.append("%s：没有名字" % id)
		var a := str(p.get("area", ""))
		if a != "":
			if not Areas.known(a):
				errors.append("%s：区域 %s 没登记（world/areas.gd）" % [id, a])
			elif Areas.spawn(a, str(p.get("spawn", ""))) == null:
				errors.append("%s：区域 %s 没有出生点 %s" % [id, a, p.get("spawn", "")])
		elif str(p.get("pending", "")) == "":
			errors.append("%s：还没做好的地点要写 pending（给玩家看的说明）" % id)
		var pos: Array = p.get("pos", [])
		if pos.size() != 2 or float(pos[0]) < 0.05 or float(pos[0]) > 0.95 or float(pos[1]) < 0.05 or float(pos[1]) > 0.95:
			errors.append("%s：地图位置要在 0.05..0.95 以内" % id)
		if not str(p.get("icon", "")) in ICONS:
			errors.append("%s：图标 %s 不认识" % [id, p.get("icon", "")])
	for r in data().get("routes", []):
		for k in ["from", "to"]:
			if not ps.has(str(r.get(k, ""))):
				errors.append("路线 %s → %s：地点 %s 不认识" % [r.get("from", ""), r.get("to", ""), r.get(k, "")])
		var dp := str(r.get("daypart", ""))
		if dp != "" and not Daypart.valid(dp):
			errors.append("路线 %s → %s：时段 %s 不认识" % [r.get("from", ""), r.get("to", ""), dp])
		if str(r.get("text", "")) == "":
			errors.append("路线 %s → %s：没写路上怎么走" % [r.get("from", ""), r.get("to", "")])
	return errors
