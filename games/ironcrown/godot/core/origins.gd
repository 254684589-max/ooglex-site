class_name Origins
extends RefCounted
## 出身三选一（路线图 O.1；WORLD.md 第七节「出身背景三选一（影响开局属性与部分对话选项）」）。数据在 data/origins.json。
## 选了就设旗标 origin = 编号（跟着存档走；对话里 {"flag": "origin", "eq": 编号}），再加上这个出身开局的技能、属性、声望（只加一次）。

const PATH := "res://data/origins.json"
const ATTR_NAMES := {"strength": "力量", "agility": "敏捷", "constitution": "体魄", "wits": "机敏"}

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY:
				_data = d
	return _data


static func ids() -> Array:
	return data().get("order", [])


static func spec(id: String) -> Dictionary:
	return data().get("origins", {}).get(id, {})


static func name_of(id: String) -> String:
	return str(spec(id).get("name", ""))


## 现在的出身（"" = 还没选）
static func current() -> String:
	return str(GameState.get_flag("origin", "")) if GameState.has_flag("origin") else ""


## 开局多了什么（一行字：「剑术 +5 · 威吓 +2 · 力量 +1」）
static func bonus_text(id: String) -> String:
	var s := spec(id)
	var parts := []
	for k in s.get("skills", {}):
		parts.append("%s +%d" % [GameState.SKILL_NAMES.get(k, k), int(s.skills[k])])
	for k in s.get("attrs", {}):
		parts.append("%s +%d" % [ATTR_NAMES.get(k, k), int(s.attrs[k])])
	for k in s.get("rep", {}):
		var v := int(s.rep[k])
		parts.append("%s %s%d" % [str(GameState.progression().get("factions", {}).get(k, {}).get("name", k)), "+" if v > 0 else "−", absi(v)])
	return " · ".join(parts)


## 选定：设旗标、加开局的技能 / 属性 / 声望。已经选过的不再加（返回 false）
static func apply(id: String) -> bool:
	if current() != "" or spec(id).is_empty():
		return false
	var s := spec(id)
	GameState.set_flag("origin", id)
	for k in s.get("skills", {}):
		GameState.skills[k] = mini(int(GameState.skills.get(k, 0)) + int(s.skills[k]), GameState.SKILL_MAX)
	for k in s.get("attrs", {}):
		GameState.set(k, int(GameState.get(k)) + int(s.attrs[k]))
	for k in s.get("rep", {}):
		GameState.change_rep(k, int(s.rep[k]))
	print("IC_ORIGIN id=%s" % id)
	return true
