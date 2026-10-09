class_name AreaMap
extends RefCounted
## 地图的数据（路线图 3.11；所有者 2026-10-09「区域地图 / 总图界面——加上」）。只管数据，不碰界面（ui/map_panel.gd）。
## 每个区域的平面图写在区域脚本自己身上（Frostford.map_spec() 等），用的是搭场景的同一批常量；这里按区域名分派，
## 只读规格、不读场景节点——4.4 鹭沼那种连片地图，远处的块隐藏了、还没搭的时候，地图照样完整。唯一的实时数据是玩家的位置和朝向。
## 「一带」示意图的版面在 data/regions.json（节点位置），连线不写，从各区域规格的出口推出来。
##
## 规格格式（单位米，世界 XZ 坐标，Vector2(x, z)；北 = -Z = 图的上方）：
##   bounds  Rect2              走得到的范围（室外 = Edges 的 "area" 元数据；室内 = 房间）
##   view    Rect2（可选）       整图显示时框住的范围，默认 = bounds（渡口要把码头和渡船框进来）
##   shapes  [{k: 种类, rect: Rect2 | pts: PackedVector2Array | at: Vector2, label?: 字, icon?: 图标, if?: 条件}]
##   exits   [{at: Vector2, dir: 往外走的方向（单位向量）, to: 区域, spawn: 出生点, name: 和门上的名字一字不差, if?: 条件}]
##   zones   [{id, name, pts, if?}]（可选，4.4 鹭沼用：你在「鹭沼 · 芦栈村」）
## 条件 if：{chapter_min, chapter_max, flag, not_flag}，打开地图时现算（第一章才有的路牌、以后按旗标才显示的秘密地点）。
## 地图上不画人、不画东西、不标任务（GDD 7.2：任务标记以后单独做）。
## 读过的 regions.json 缓存在 Engine 的元数据里（static var 存字典退出时报资源没释放，travel.gd 同样的做法）；测试可以换一份。

const REGIONS_PATH := "res://data/regions.json"
const META := "ic_area_map"
const KINDS := ["road", "square", "house", "wall", "water", "pier", "boat", "wood", "graves", "furniture", "mark"]
const ICONS := ["well", "tree", "sign", "fire"]
const IF_KEYS := ["chapter_min", "chapter_max", "flag", "not_flag"]
## 朝向的名字：下标 = posmod(roundi(yaw / 45), 8)；yaw 0 = 面朝 -Z = 北，正 = 向左转（西）
const HEADINGS := ["北", "西北", "西", "西南", "南", "东南", "东", "东北"]
const HERE_SUFFIX := "（你在这里）"
const INDOOR_SUFFIX := "（室内）"
const NEAR := 3.0                                  # 不到这么远就说「就在你旁边」


static func _store() -> Dictionary:
	if not Engine.has_meta(META):
		Engine.set_meta(META, {"regions": null, "overrides": {}})
	return Engine.get_meta(META)


## 区域的地图规格；没有地图的区域（测试场、训练场、军阵试验场）返回 {}
static func spec(area: String) -> Dictionary:
	var ov: Dictionary = _store().overrides
	if ov.has(area):
		return ov[area]
	match area:
		"frostford":
			return Frostford.map_spec()
		"tavern":
			return Tavern.map_spec()
		"churchyard":
			return Churchyard.map_spec()
		"chapel":
			return Chapel.map_spec()
		"birch":
			return Birch.map_spec()
		"ferry":
			return Ferry.map_spec()
	return {}


## 测试用：换掉某个区域的规格（null = 换回区域脚本自己的）
static func override(area: String, s: Variant) -> void:
	var ov: Dictionary = _store().overrides
	if s == null:
		ov.erase(area)
	else:
		ov[area] = s


## 测试用：换一份「一带」数据（null = 回到 data/regions.json）
static func override_regions(d: Variant) -> void:
	_store().regions = d


static func has_map(area: String) -> bool:
	return not spec(area).is_empty()


## 条件过不过（打开地图时现算）
static func passes(entry: Dictionary) -> bool:
	var c: Dictionary = entry.get("if", {})
	if c.has("chapter_min") and GameState.chapter < int(c.chapter_min):
		return false
	if c.has("chapter_max") and GameState.chapter > int(c.chapter_max):
		return false
	if c.has("flag") and not GameState.has_flag(str(c.flag)):
		return false
	if c.has("not_flag") and GameState.has_flag(str(c.not_flag)):
		return false
	return true


static func shapes(area: String) -> Array:
	return spec(area).get("shapes", []).filter(func(s): return passes(s))


static func exits(area: String) -> Array:
	return spec(area).get("exits", []).filter(func(e): return passes(e))


static func bounds(area: String) -> Rect2:
	return spec(area).get("bounds", Rect2())


static func view_rect(area: String) -> Rect2:
	var s := spec(area)
	return s.get("view", s.get("bounds", Rect2()))


## 你在这片地图的哪一块（规格里有 zones 时；4.4 鹭沼用）；"" = 没有分块
static func zone_at(area: String, xz: Vector2) -> String:
	for z in spec(area).get("zones", []):
		if passes(z) and Geometry2D.is_point_in_polygon(xz, z.pts):
			return str(z.name)
	return ""


static func regions() -> Dictionary:
	var st := _store()
	if st.regions == null:
		var d := {}
		var f := FileAccess.open(REGIONS_PATH, FileAccess.READ)
		if f:
			var j := JSON.new()
			if j.parse(f.get_as_text()) == OK and j.data is Dictionary:
				d = j.data.get("regions", {})
		if d.is_empty():
			push_warning("地图「一带」数据读不出来：" + REGIONS_PATH)
		st.regions = d
	return st.regions


## 这个区域属于哪一带（"" = 不属于任何一带，例如测试场）
static func region_of(area: String) -> String:
	var rs := regions()
	for r in rs:
		if rs[r].get("areas", {}).has(area):
			return str(r)
	return ""


static func region_title(region: String) -> String:
	return str(regions().get(region, {}).get("title", region))


static func region_areas(region: String) -> Array:
	return regions().get(region, {}).get("areas", {}).keys()


## 一带里各处怎么连：从成员区域的出口推出来，两头都要在这一带里；[a, b] 不分方向，去重
static func links(region: String) -> Array:
	var members := region_areas(region)
	var out := []
	var seen := {}
	for a in members:
		for e in exits(str(a)):
			var b := str(e.get("to", ""))
			if not b in members or b == str(a):
				continue
			var pair := [str(a), b]
			pair.sort()
			var key := "%s|%s" % pair
			if not seen.has(key):
				seen[key] = true
				out.append(pair)
	return out


## 地图册在这里有哪几页：本地（总有）、一带（这个区域属于某一带时）、北境西部（这一章旅行地图上有地点时，即第一章起）
static func views(area: String, chapter: int) -> Array:
	var v := ["local"]
	if region_of(area) != "":
		v.append("region")
	if not Travel.places(chapter).is_empty():
		v.append("travel")
	return v


## 按 M 时先打开哪一页：室内看「一带」（屋里的平面图没什么好看，看你在镇上哪儿），其余看「本地」
static func default_view(area: String) -> String:
	if Areas.is_indoor(area) and region_of(area) != "":
		return "region"
	return "local"


static func heading_text(yaw_deg: float) -> String:
	return HEADINGS[posmod(roundi(yaw_deg / 45.0), 8)]


## 从 from 看 to 在哪个方向、多远：「南边约 34 米」；太近说「就在你旁边」。
## compass = false（室内）只说远近「离你约 5 米」：室内的平面图按屋子自己的朝向画，和镇上的东南西北对不上
## （审查：酒馆的门在屋里是南墙，在镇上朝东），所以室内不说方向、不画指北
static func bearing_text(from: Vector2, to: Vector2, compass := true) -> String:
	var d := to - from
	if d.length() < NEAR:
		return "就在你旁边"
	if not compass:
		return "离你约 %d 米" % roundi(d.length())
	var yaw := rad_to_deg(atan2(-d.x, -d.y))          # 朝向 yaw 的方向是 (-sin yaw, -cos yaw)
	return "%s边约 %d 米" % [heading_text(yaw), roundi(d.length())]


## 这张图说不说东南西北：室外说；室内的平面图按屋子自己的朝向画，不说（见 bearing_text）
static func has_compass(area: String) -> bool:
	return not Areas.is_indoor(area)


## 区域在「一带」示意图上的名字：当前区域加「（你在这里）」，室内加「（室内）」（两行，按钮窄一点）
static func node_text(area: String, here: String) -> String:
	var t := Areas.display_name(area)
	if area == here:
		return t + "\n" + HERE_SUFFIX
	if Areas.is_indoor(area):
		return t + "\n" + INDOOR_SUFFIX
	return t


## 所有会显示或画出来的字（字体测试用）：规格的标签和出口名（不管条件）、一带的标题和河名、区域名、地图面板上的固定文字
static func texts() -> Array:
	var out: Array = []
	for a in Areas.NAMES:
		out.append(Areas.display_name(a) + HERE_SUFFIX + INDOOR_SUFFIX)
		var s := spec(a)
		for sh in s.get("shapes", []):
			out.append(str(sh.get("label", "")))
		for e in s.get("exits", []):
			out.append(str(e.get("name", "")))
		for z in s.get("zones", []):
			out.append(str(z.get("name", "")))
	var rs := regions()
	for r in rs:
		out.append(str(rs[r].get("title", "")))
		out.append(str(rs[r].get("river", {}).get("label", "")))
	out.append_array(HEADINGS)
	out.append_array(MapPanel.TEXTS)
	out.append_array(MapTabs.LABELS.values())
	out.append(MapTabs.MARK)
	return out


## 检查数据（测试用）：种类、图标、条件、图形在框住的范围以内、出口通往的区域和出生点、一带的节点
static func validate() -> Array:
	var errors := []
	for a in Areas.NAMES:
		var s := spec(a)
		if s.is_empty():
			continue
		var b: Rect2 = s.get("bounds", Rect2())
		if b.size.x <= 0.0 or b.size.y <= 0.0:
			errors.append("%s：没有 bounds" % a)
		var v: Rect2 = s.get("view", b)
		for sh in s.get("shapes", []):
			var k := str(sh.get("k", ""))
			if not k in KINDS:
				errors.append("%s：图形种类 %s 不认识" % [a, k])
			if sh.has("icon") and not str(sh.icon) in ICONS:
				errors.append("%s：图标 %s 不认识" % [a, sh.icon])
			errors.append_array(_check_if(a, sh))
			if str(sh.get("label", "")).contains("　"):
				errors.append("%s：标签里有全角空格" % a)
			var box := shape_rect(sh)
			if k == "mark" and not sh.has("at"):
				errors.append("%s：地标要有 at（一个点）" % a)
			elif k != "mark" and not sh.has("rect") and (sh.get("pts", PackedVector2Array()) as PackedVector2Array).size() < 3:
				errors.append("%s：%s 要有 rect 或者至少三个点的 pts" % [a, k])
			elif k != "water" and not v.grow(2.0).encloses(box):
				errors.append("%s：%s「%s」超出了地图范围" % [a, k, sh.get("label", "")])
		if not v.grow(0.01).encloses(b):
			errors.append("%s：view 没框住 bounds" % a)
		for z in s.get("zones", []):
			if str(z.get("name", "")) == "" or (z.get("pts", PackedVector2Array()) as PackedVector2Array).size() < 3:
				errors.append("%s：分块要有名字和至少三个点" % a)
			errors.append_array(_check_if(a, z))
		for e in s.get("exits", []):
			var to := str(e.get("to", ""))
			if not Areas.known(to):
				errors.append("%s：出口通往的区域 %s 没登记" % [a, to])
			elif Areas.spawn(to, str(e.get("spawn", ""))) == null:
				errors.append("%s：出口通往 %s 的出生点 %s 不存在" % [a, to, e.get("spawn", "")])
			if str(e.get("name", "")) == "":
				errors.append("%s：出口没写名字" % a)
			var dir: Vector2 = e.get("dir", Vector2.ZERO)
			if absf(dir.length() - 1.0) > 0.01:
				errors.append("%s：出口「%s」的方向不是单位向量" % [a, e.get("name", "")])
			if not v.grow(2.0).has_point(e.get("at", Vector2(INF, INF))):
				errors.append("%s：出口「%s」不在地图范围里" % [a, e.get("name", "")])
			errors.append_array(_check_if(a, e))
	var rs := regions()
	if rs.is_empty():
		errors.append("没有「一带」数据")
	for r in rs:
		var members: Dictionary = rs[r].get("areas", {})
		for a in members:
			var m: Dictionary = members[a]
			if not Areas.known(str(a)):
				errors.append("一带 %s：区域 %s 没登记" % [r, a])
			var pos: Array = m.get("pos", [])
			if pos.size() != 2 or float(pos[0]) < 0.05 or float(pos[0]) > 0.95 or float(pos[1]) < 0.05 or float(pos[1]) > 0.95:
				errors.append("一带 %s：%s 的位置要在 0.05..0.95 以内" % [r, a])
			if m.has("host"):
				var h := str(m.host)
				if not members.has(h) or Areas.is_indoor(h):
					errors.append("一带 %s：%s 的 host %s 要是这一带里的室外区域" % [r, a, h])
	return errors


static func _check_if(area: String, entry: Dictionary) -> Array:
	var errors := []
	for key in entry.get("if", {}):
		if not str(key) in IF_KEYS:
			errors.append("%s：条件 %s 不认识" % [area, key])
	return errors


## 一个图形占的矩形（XZ）：rect 本身、多边形的外接矩形；点（at）是零大小的矩形
static func shape_rect(sh: Dictionary) -> Rect2:
	if sh.has("rect"):
		return sh.rect
	if sh.has("pts"):
		var pts: PackedVector2Array = sh.pts
		if pts.is_empty():
			return Rect2()
		var r := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			r = r.expand(p)
		return r
	if sh.has("at"):
		return Rect2(sh.at, Vector2.ZERO)
	return Rect2()
