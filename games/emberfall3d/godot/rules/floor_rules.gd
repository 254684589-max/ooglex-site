class_name FloorRules
extends RefCounted
## 楼层、怪物成长、掉落与商店（移植自 V0.1 的 themeFor / floorName / isBossFloor / poolFor / spawnMon / dropLoot / useProp / refreshShops）。
## 这里只算「数值与掉什么」，不负责生成地图和摆放实体（那是 P2 / P5 / P10）。


static func F() -> Dictionary:
	return Act1Data.rules().floors


static func theme_for(floor_i: int) -> String:
	if floor_i <= 0:
		return "town"
	var th: Dictionary = F().themes
	for k in th:
		if floor_i >= th[k].floors[0] and floor_i <= th[k].floors[1]:
			return k
	return "abyss"


static func floor_name(floor_i: int) -> String:
	if floor_i <= 0:
		return F().town_name
	return "%s · 第 %d 层" % [F().themes[theme_for(floor_i)].name, floor_i]


static func is_boss_floor(floor_i: int) -> bool:
	var last: int = int(F().boss_floors[-1])
	if F().boss_floors.has(float(floor_i)):
		return true
	return floor_i > last and floor_i % int(F().abyss_boss_every) == 0


## 本层首领：第 3 层莫格、第 6 层摩登；深渊首领层在两者中随机
static func boss_for(rng: RandomNumberGenerator, floor_i: int) -> String:
	var fixed: Dictionary = F().bosses
	if fixed.has(str(floor_i)):
		return fixed[str(floor_i)]
	var keys := fixed.values()
	return keys[rng.randi_range(0, keys.size() - 1)]


static func monster_pool(floor_i: int) -> Array:
	var pools: Dictionary = Act1Data.monsters().pools
	return pools[str(clampi(floor_i, 1, 7))]


## 按楼层与精英特性算出一只怪的数值（V0.1 spawnMon 的数值部分）
static func scale_monster(key: String, floor_i: int, champ: String = "") -> Dictionary:
	var d := Act1Data.monster(key)
	var m: Dictionary = Act1Data.rules().monsters
	var boss: bool = d.get("boss", false)
	var f := maxi(1, floor_i)
	var k := f - 1
	var hp_m: float = (1 + m.hp_growth.boss_per_floor * k) if boss else (1 + m.hp_growth.per_floor * k + m.hp_growth.per_floor_sq * k * k)
	var dm_m: float = 1 + m.dmg_growth_per_floor * k
	var hp: float = d.hp * hp_m
	var spd: float = d.spd
	var c: Dictionary = m.champion
	if champ != "":
		hp *= c.hp_mul
		if champ == "fast":
			spd *= c.fast_speed_mul
	var cm: float = c.dmg_mul if champ != "" else 1.0
	var prefix: String = Act1Data.monsters().champions[champ].prefix if champ != "" else ""
	return {
		"key": key, "name": prefix + d.name, "champ": champ, "boss": boss,
		"hp": int(round(hp)), "spd": spd,
		"dmg": [maxi(1, int(round(d.dmg[0] * dm_m * cm))), maxi(1, int(round(d.dmg[1] * dm_m * cm)))],
		"xp": int(round(d.xp * (1 + m.xp_growth_per_floor * k) * (c.xp_mul if champ != "" else 1.0))),
		"lvl": f * int(m.lvl.per_floor) + (int(m.lvl.boss_bonus) if boss else 0),
	}


static func _ri(rng: RandomNumberGenerator, r: Array) -> int:
	return rng.randi_range(int(r[0]), int(r[1]))


## 怪物掉落（V0.1 dropLoot）。source：{ boss: bool, champ: String }；mf / gf 为角色的魔法物品掉率 / 金币掉落加成（百分比）。
## 返回掉落列表，每项为 {gold: n} / {pot: "hp"|"mp"|"tp"} / {item: 物品字典}。
static func roll_loot(rng: RandomNumberGenerator, floor_i: int, source: Dictionary, mf: float = 0, gf: float = 0) -> Array:
	var L: Dictionary = Act1Data.rules().loot
	var f := maxi(1, floor_i)
	var mfm := 1 + mf / 100.0
	var gfm := 1 + gf / 100.0
	var boss: bool = source.get("boss", false)
	var champ: bool = source.get("champ", "") != ""
	var ilvl := f * int(L.ilvl.per_floor) + (int(L.ilvl.boss_bonus) if boss else (int(L.ilvl.champion_bonus) if champ else 0))
	var out: Array = []
	if boss:
		var b: Dictionary = L.boss
		out.append({"gold": maxi(1, int(round(rng.randi_range(f * int(b.gold[0]), f * int(b.gold[1])) * gfm)))})
		out.append({"item": ItemGen.generate(rng, ilvl, {"rarity": 3 if rng.randf() < b.first_legendary_chance else 2})})
		out.append({"item": ItemGen.generate(rng, ilvl, {"rarity": 2})})
		for i in 2:
			out.append({"item": ItemGen.generate(rng, ilvl, {"mul": mfm * b.magic_find_mul})})
		out.append({"pot": "hp"})
		return out
	var n: Dictionary = L.normal
	if rng.randf() < n.gold_chance:
		out.append({"gold": maxi(1, int(round(rng.randi_range(f * int(n.gold[0]), f * int(n.gold[1])) * gfm * (L.champion.gold_mul if champ else 1.0))))})
	if rng.randf() < n.potion_chance:
		out.append({"pot": "hp" if rng.randf() < n.potion_hp_share else "mp"})
	if rng.randf() < n.scroll_chance:
		out.append({"pot": "tp"})
	var count := 0
	if champ:
		count = 2 if rng.randf() < L.champion.items_two_chance else 1
	elif rng.randf() < n.item_chance:
		count = 1
	for i in count:
		out.append({"item": ItemGen.generate(rng, ilvl, {"mul": mfm * (L.champion.mf_mul if champ else 1.0)})})
	return out


## 宝箱（V0.1 useProp 的 chest 分支）
static func roll_chest(rng: RandomNumberGenerator, floor_i: int, mf: float = 0, gf: float = 0) -> Array:
	var c: Dictionary = Act1Data.rules().loot.chest
	var f := maxi(1, floor_i)
	var out: Array = [{"gold": maxi(1, int(round(rng.randi_range(f * int(c.gold[0]), f * int(c.gold[1])) * (1 + gf / 100.0))))}]
	for i in _ri(rng, c.items):
		out.append({"item": ItemGen.generate(rng, f * 2 + int(c.ilvl_bonus), {"mul": (1 + mf / 100.0) * c.mf_mul})})
	if rng.randf() < c.potion_chance:
		out.append({"pot": ["hp", "hp", "mp"][rng.randi_range(0, 2)]})
	return out


## 木桶：返回 {gold} / {pot} / {item} / {imps: n}（窜出火坑小鬼）或空
static func roll_barrel(rng: RandomNumberGenerator, floor_i: int) -> Dictionary:
	var b: Dictionary = Act1Data.rules().loot.barrel
	var f := maxi(1, floor_i)
	var r := rng.randf()
	if r < b.gold_below:
		return {"gold": rng.randi_range(f * int(b.gold[0]), f * int(b.gold[1]))}
	if r < b.potion_below:
		return {"pot": "hp"}
	if r < b.item_below:
		return {"item": ItemGen.generate(rng, f * 2)}
	if r < b.imps_below:
		return {"imps": _ri(rng, b.imps)}
	return {}


## 商店进货（V0.1 refreshShops）：{ smith: [物品 ×8，不含戒指护符], alchemist: [戒指或护符 ×2] }
static func refresh_shop(rng: RandomNumberGenerator, hero_lvl: int) -> Dictionary:
	var s: Dictionary = Act1Data.rules().shop
	var il := maxi(int(s.ilvl.min), hero_lvl + int(s.ilvl.over_hero_lvl))
	var smith: Array = []
	while smith.size() < int(s.smith.count):
		var rar := 2 if rng.randf() < s.smith.rare_chance else (1 if rng.randf() < s.smith.magic_chance else 0)
		var it := ItemGen.generate(rng, il, {"rarity": rar})
		if not Act1Data.base(it.base).get("magic_only", false):
			smith.append(it)
	var alch: Array = []
	for i in int(s.alchemist.count):
		var bases: Array = s.alchemist.bases
		alch.append(ItemGen.generate(rng, il, {"rarity": 2 if rng.randf() < s.alchemist.rare_chance else 1, "base": bases[rng.randi_range(0, bases.size() - 1)]}))
	return {"smith": smith, "alchemist": alch}
