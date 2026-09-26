class_name SaveGame
extends RefCounted
## 存档（P11，移植 V0.1 saveGame / loadGame）：只存角色（同 V0.1：楼层每次进游戏重新生成），外加当前生命法力与音效开关。
## 格式：JSON 文本 { fmt: "ef3d-save", v: 1, savedAt, sheet{…V0.1 角色字段}, hp, mp, snd }。
## 读档时逐项校验：版本号不对、字段缺失或类型不对就当没有存档；未知底材的物品丢掉；缺的字段用新角色的默认值补上。
## 存在哪里：网页版用浏览器 localStorage（键 ooglex.emberfall3d.v1，与 V0.1 的 ooglex.emberfall.v1 分开）；其他平台存 user://。
## 无痕模式等存不了的情况游戏照常进行（返回 false）。

const FORMAT := "ef3d-save"
const VERSION := 1
const WEB_KEY := "ooglex.emberfall3d.v1"
const FILE := "user://emberfall3d_save.json"

static var path_override := ""       # 测试用：换一个存档文件，不碰真存档


static func serialize(sheet: Dictionary, hp: float, mp: float, snd: bool) -> String:
	var sh := sheet.duplicate(true)
	return JSON.stringify({"fmt": FORMAT, "v": VERSION, "savedAt": Time.get_datetime_string_from_system(true) + "Z", "sheet": sh, "hp": hp, "mp": mp, "snd": snd})


static func _num(d: Dictionary, k: String, dv: float, lo: float, hi: float) -> float:
	var v = d.get(k, dv)
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return dv
	return clampf(float(v), lo, hi)


static func _item_ok(it) -> bool:
	return it is Dictionary and it.has("base") and Act1Data.items().bases.has(str(it.base)) and it.has("name") and it.has("rarity")


## 解析并校验存档文本；不合格返回 {}。合格返回 {sheet, hp, mp, snd, savedAt}（sheet 已补齐默认值、整数字段已取整）
static func parse(text: String) -> Dictionary:
	if text.strip_edges() == "":
		return {}
	var j := JSON.new()        # 用 JSON.new().parse：坏存档不往控制台打错误
	if j.parse(text) != OK:
		return {}
	var d = j.data
	if not d is Dictionary or d.get("fmt", "") != FORMAT or int(d.get("v", 0)) != VERSION or not d.get("sheet") is Dictionary:
		return {}
	var h: Dictionary = d.sheet
	if typeof(h.get("lvl")) != TYPE_FLOAT and typeof(h.get("lvl")) != TYPE_INT:
		return {}
	var out := HeroStats.new_hero()
	var cap := float(Act1Data.rules().hero.level_cap)
	out.lvl = int(_num(h, "lvl", 1, 1, cap))
	for k in ["xp", "str", "vit", "mag", "pts", "gold", "kills", "deaths", "maxFloor"]:
		out[k] = int(_num(h, k, out[k], 0, 1e9))
	out.won = bool(h.get("won", false))
	if h.get("pots") is Dictionary:
		for k in ["hp", "mp", "tp"]:
			out.pots[k] = int(_num(h.pots, k, 0, 0, 9999))
	if h.get("q") is Dictionary:
		for k in ["q1", "q2", "q3"]:
			out.q[k] = int(_num(h.q, k, 0, 0, 3))
	out.inv = (h.get("inv", []) as Array).filter(func(it): return _item_ok(it)) if h.get("inv") is Array else []
	out.inv = out.inv.slice(0, int(Act1Data.rules().hero.inventory_cap))
	out.eq = {}
	if h.get("eq") is Dictionary:
		for slot in h.eq:
			if _item_ok(h.eq[slot]):
				out.eq[str(slot)] = h.eq[slot]
	var b = h.get("buff")
	if b is Dictionary and str(b.get("k", "")) in ["might", "guard", "swift", "arcane"]:
		out.buff = {"k": str(b.k), "t": _num(b, "t", 0, 0, float(Act1Data.rules().shrines.duration_s))}
	# JSON 数字读回来是浮点数：物品里的整数字段取整（等级需求、物品等级、词缀值……）
	for it in out.inv + out.eq.values():
		for k in ["id", "rarity", "ilvl", "req", "arm"]:
			if it.has(k):
				it[k] = int(it[k])
		if it.has("dmg"):
			it.dmg = [int(it.dmg[0]), int(it.dmg[1])]
		if it.has("aff") and it.aff is Dictionary:
			for k in it.aff:
				it.aff[k] = int(it.aff[k])
		else:
			it.aff = {}
	return {"sheet": out, "hp": _num(d, "hp", 999, 0, 1e6), "mp": _num(d, "mp", 999, 0, 1e6), "snd": bool(d.get("snd", true)), "savedAt": str(d.get("savedAt", ""))}


## 读档后物品编号接着往下编，避免新物品和存档里的撞号（V0.1 UID = max + 1）
static func bump_item_ids(sheet: Dictionary) -> void:
	var mx := 0
	for it in sheet.inv + sheet.eq.values():
		mx = maxi(mx, int(it.get("id", 0)))
	ItemGen._next_id = maxi(ItemGen._next_id, mx + 1)


# ---------------- 存取 ----------------

static func _web() -> bool:
	return OS.has_feature("web") and path_override == ""


static func read_raw() -> String:
	if _web():
		var ls = JavaScriptBridge.get_interface("localStorage")
		if ls == null:
			return ""
		var v = ls.getItem(WEB_KEY)
		return str(v) if v != null else ""
	var p := path_override if path_override != "" else FILE
	if not FileAccess.file_exists(p):
		return ""
	var f := FileAccess.open(p, FileAccess.READ)
	return f.get_as_text() if f else ""


static func write_raw(text: String) -> bool:
	if _web():
		var ls = JavaScriptBridge.get_interface("localStorage")
		if ls == null:
			return false
		ls.setItem(WEB_KEY, text)
		return str(ls.getItem(WEB_KEY)) == text
	var f := FileAccess.open(path_override if path_override != "" else FILE, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	return true


static func erase() -> void:
	if _web():
		var ls = JavaScriptBridge.get_interface("localStorage")
		if ls != null:
			ls.removeItem(WEB_KEY)
		return
	var p := path_override if path_override != "" else FILE
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)


static func load_saved() -> Dictionary:
	return parse(read_raw())
