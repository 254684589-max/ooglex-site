class_name ItemGen
extends RefCounted
## 物品生成与估价（移植自 V0.1 的 rollAff / rollRarity / baseStats / genItem / itemValue / sellValue）。
## 物品是字典：{ id, base, rarity(0 普通 / 1 魔法 / 2 稀有 / 3 传奇), ilvl, name, aff{词缀: 数值}, req, [dmg, spd], [arm] }。
## 随机数一律从传入的 RandomNumberGenerator 取，给定种子即可复现。

const RARITY_NAMES := ["普通", "魔法", "稀有", "传奇"]

static var _next_id := 1


static func _ri(rng: RandomNumberGenerator, a: int, b: int) -> int:
	return rng.randi_range(a, b)


static func _pick(rng: RandomNumberGenerator, arr: Array) -> Variant:
	return arr[rng.randi_range(0, arr.size() - 1)]


## 词缀在给定物品等级下的取值范围 [下限, 上限]（rollAff 的 ri 两端）
static func affix_bounds(id: String, ilvl: int) -> Array:
	var a := Act1Data.affix(id)
	var hi: float = a.base + ilvl * a.per_ilvl
	var lo_v := maxi(1, int(round(hi * 0.5)))
	var hi_v := maxi(1, int(round(hi)))
	if a.has("max"):
		lo_v = mini(lo_v, int(a.max))
		hi_v = mini(hi_v, int(a.max))
	return [lo_v, hi_v]


static func roll_affix(rng: RandomNumberGenerator, id: String, ilvl: int) -> int:
	var a := Act1Data.affix(id)
	var hi: float = a.base + ilvl * a.per_ilvl
	var v := _ri(rng, maxi(1, int(round(hi * 0.5))), maxi(1, int(round(hi))))
	if a.has("max"):
		v = mini(v, int(a.max))
	return v


## 品质：r 为 [0, 1) 的随机数，mul 为掉率倍数（魔法物品掉率等）
static func rarity_from(r: float, mul: float) -> int:
	var t: Dictionary = Act1Data.rules().items.rarity
	if r < t.legendary * mul:
		return 3
	if r < t.rare * mul:
		return 2
	if r < t.magic * minf(mul, t.magic_mul_cap):
		return 1
	return 0


static func roll_rarity(rng: RandomNumberGenerator, mul: float) -> int:
	return rarity_from(rng.randf(), mul)


static func apply_base_stats(it: Dictionary, b: Dictionary, ilvl: int) -> void:
	var g: Dictionary = Act1Data.rules().items.growth
	if b.has("dmg"):
		var m: float = 1 + ilvl * g.weapon_dmg_per_ilvl
		it.dmg = [maxi(1, int(round(b.dmg[0] * m))), maxi(2, int(round(b.dmg[1] * m)))]
		it.spd = b.spd
	if b.has("arm"):
		it.arm = maxi(1, int(round(b.arm * (1 + ilvl * g.armor_per_ilvl))))
	if b.has("implicit"):
		for k in b.implicit:
			it.aff[k] = int(b.implicit[k])


## opt：rarity（指定品质）/ mul（掉率倍数）/ base（指定底材）/ slot（指定部位）
static func generate(rng: RandomNumberGenerator, ilvl: int, opt: Dictionary = {}) -> Dictionary:
	var data := Act1Data.items()
	var ir: Dictionary = Act1Data.rules().items
	var rar: int = opt.rarity if opt.has("rarity") else roll_rarity(rng, opt.get("mul", 1.0))
	if rar == 3:
		var cands: Array = data.uniques.filter(func(u): return Act1Data.base(u.base).lvl <= ilvl + ir.unique_base_lvl_slack)
		if not cands.is_empty():
			var u: Dictionary = _pick(rng, cands)
			var ub := Act1Data.base(u.base)
			var it := {"id": _new_id(), "base": u.base, "rarity": 3, "ilvl": ilvl, "aff": {}, "name": u.name}
			apply_base_stats(it, ub, ilvl)
			var sc: float = 1 + ilvl * ir.growth.unique_affix_per_ilvl
			for k in u.affixes:
				var r: Array = u.affixes[k]
				var v := int(round(_ri(rng, int(r[0]), int(r[1])) * (1.0 if ir.growth.unique_flat_affixes.has(k) else sc)))
				it.aff[k] = int(it.aff.get(k, 0)) + v
			it.req = maxi(1, mini(int(ir.req.unique_cap), maxi(int(ub.lvl), int(floor(ilvl * ir.req.ilvl_mul)))))
			return it
		rar = 2
	var keys: Array = []
	if opt.has("base"):
		keys = [opt.base]
	else:
		for k in data.bases:
			var b0: Dictionary = data.bases[k]
			if b0.lvl <= ilvl + ir.base_lvl_slack and (not opt.has("slot") or b0.slot == opt.slot):
				keys.append(k)
	var bk: String = _pick(rng, keys)
	var b := Act1Data.base(bk)
	if b.get("magic_only", false) and rar == 0:
		rar = 1
	var it := {"id": _new_id(), "base": bk, "rarity": rar, "ilvl": ilvl, "aff": {}, "name": b.name}
	apply_base_stats(it, b, ilvl)
	var n_aff := 0
	if rar == 1:
		n_aff = _ri(rng, int(ir.affix_count.magic[0]), int(ir.affix_count.magic[1]))
	elif rar == 2:
		n_aff = _ri(rng, int(ir.affix_count.rare[0]), int(ir.affix_count.rare[1]))
	var pool: Array = []
	for k in data.affixes:
		var s = data.affixes[k].slots
		if typeof(s) == TYPE_STRING or (s as Array).has(b.slot):
			pool.append(k)
	var added: Array = []
	for i in n_aff:
		if pool.is_empty():
			break
		var k: String = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		it.aff[k] = int(it.aff.get(k, 0)) + roll_affix(rng, k, ilvl)
		added.append(k)
	if rar == 1:
		it.name = Act1Data.affix(added[0]).prefix + b.name
	elif rar == 2:
		it.name = _pick(rng, data.rare_names.first) + _pick(rng, data.rare_names.second)
	it.req = int(b.lvl) if rar == 0 else maxi(int(b.lvl), int(floor(ilvl * ir.req.ilvl_mul)))
	return it


static func value(it: Dictionary) -> int:
	var v: Dictionary = Act1Data.rules().items.value
	var dmg_part := 0.0
	if it.has("dmg"):
		dmg_part = it.dmg[1] * v.per_max_dmg
	return int(round((v.base + it.ilvl * v.per_ilvl) * v.rarity_mul[int(it.rarity)] + it.get("arm", 0) * v.per_arm + dmg_part))


static func sell_value(it: Dictionary) -> int:
	return maxi(1, int(floor(value(it) / Act1Data.rules().items.value.sell_div)))


## 词缀的显示文字，例如「+12% 伤害」
static func affix_text(id: String, v: int) -> String:
	return String(Act1Data.affix(id).text).replace("{v}", str(v))


static func _new_id() -> int:
	_next_id += 1
	return _next_id - 1
