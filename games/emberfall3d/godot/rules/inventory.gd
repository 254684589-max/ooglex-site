class_name Inventory
extends RefCounted
## 背包与装备规则（P6，移植自 V0.1 equip / unequip / drop / itemHtml / delta）。纯函数，界面在 ui/inv_panel.gd。
## sheet 是角色存档字典（inv：物品数组，eq：部位 → 物品）。


static func slot_of(it: Dictionary) -> String:
	return Act1Data.base(it.base).slot


static func slot_name(slot: String) -> String:
	for s in Act1Data.items().slots:
		if s.id == slot:
			return s.name
	return slot


static func can_equip(sheet: Dictionary, it: Dictionary) -> bool:
	return int(sheet.lvl) >= int(it.req)


## 穿上背包第 idx 件：原来那件放回同一个格子（V0.1 equip）。等级不够返回 false。
static func equip(sheet: Dictionary, idx: int) -> bool:
	if idx < 0 or idx >= sheet.inv.size():
		return false
	var it: Dictionary = sheet.inv[idx]
	if not can_equip(sheet, it):
		return false
	var slot := slot_of(it)
	var old = sheet.eq.get(slot)
	sheet.inv.remove_at(idx)
	sheet.eq[slot] = it
	if old != null:
		sheet.inv.insert(idx, old)
	return true


## 卸下某部位：背包满了卸不下（V0.1 unequip）。
static func unequip(sheet: Dictionary, slot: String) -> bool:
	if not sheet.eq.has(slot) or sheet.eq[slot] == null:
		return false
	if sheet.inv.size() >= int(Act1Data.rules().hero.inventory_cap):
		return false
	sheet.inv.append(sheet.eq[slot])
	sheet.eq.erase(slot)
	return true


## 从背包里拿出第 idx 件（丢在地上用），返回物品；没有返回空字典。
static func take(sheet: Dictionary, idx: int) -> Dictionary:
	if idx < 0 or idx >= sheet.inv.size():
		return {}
	var it: Dictionary = sheet.inv[idx]
	sheet.inv.remove_at(idx)
	return it


## 物品说明的各行：[文字, 类型]，类型 name / base / stat / affix / req / req_bad（V0.1 itemHtml）
static func item_lines(it: Dictionary, hero_lvl: int) -> Array:
	var b := Act1Data.base(it.base)
	var out: Array = [[it.name, "name"], ["%s · %s · 物品等级 %d" % [ItemGen.RARITY_NAMES[int(it.rarity)], b.name, int(it.ilvl)], "base"]]
	if it.has("dmg"):
		out.append(["伤害：%d - %d · 攻速 %.2f" % [it.dmg[0], it.dmg[1], it.spd], "stat"])
	if it.get("arm", 0) > 0:
		out.append(["护甲：%d" % it.arm, "stat"])
	for k in it.aff:
		out.append([ItemGen.affix_text(k, int(it.aff[k])), "affix"])
	out.append(["需要等级：%d" % int(it.req), "req_bad" if hero_lvl < int(it.req) else "req"])
	return out


## 与已装备的同部位物品比较（V0.1 delta）：[[说明, 差值]]，差值 > 0 表示更好
static func compare(it: Dictionary, cmp) -> Array:
	var d: Array = []
	if cmp == null or cmp == it:
		return d
	if it.has("dmg") and cmp.has("dmg"):
		var a: float = (it.dmg[0] + it.dmg[1]) * float(it.spd)
		var c: float = (cmp.dmg[0] + cmp.dmg[1]) * float(cmp.spd)
		d.append(["武器每秒伤害", snappedf((a - c) / 2.0, 0.1)])
	if int(it.get("arm", 0)) != int(cmp.get("arm", 0)):
		d.append(["护甲", float(int(it.get("arm", 0)) - int(cmp.get("arm", 0)))])
	var keys := {}
	for k in it.aff:
		keys[k] = true
	for k in cmp.aff:
		keys[k] = true
	for k in keys:
		var v := float(int(it.aff.get(k, 0)) - int(cmp.aff.get(k, 0)))
		if v != 0.0:
			d.append([affix_label(k), v])
	return d


## 比较用的词缀名：去掉数值占位与加号；百分比词缀把「%」移到名字后面（V0.1 原样会显示成「% 暴击几率」）
static func affix_label(k: String) -> String:
	var t := String(Act1Data.affix(k).text).replace("{v}", "").replace("+", "").strip_edges()
	while t.contains("  "):
		t = t.replace("  ", " ")
	if t.begins_with("%"):
		t = t.substr(1).strip_edges() + "（%）"
	return t
