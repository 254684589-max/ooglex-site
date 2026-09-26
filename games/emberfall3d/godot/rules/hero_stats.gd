class_name HeroStats
extends RefCounted
## 角色成长与属性（移植自 V0.1 的 newHero / xpNeed / calcStats / drAgainst / gainXp / killMon / drinkPotion / die）。
## 角色存档是字典（字段与 V0.1 相同，方便以后导入 V0.1 存档）：
##   { v, lvl, xp, str, vit, mag, pts, gold, hp, mp, pots{hp,mp,tp}, inv[], eq{部位: 物品}, maxFloor, q{}, kills, deaths, won, buff{k,t} }
## calc() 返回计算后的属性字典 S（字段名同 V0.1：maxHp、dmg、aps、spell、arm、crit、ms ……）。

const STAT_KEYS := ["str", "vit", "mag", "life", "mana", "dmgp", "spellp", "armp", "ias", "ls", "ms", "regen", "crit", "gf", "mf", "light"]


static func R() -> Dictionary:
	return Act1Data.rules().hero


static func new_hero() -> Dictionary:
	var s: Dictionary = R().start
	return {
		"v": 1, "lvl": int(s.lvl), "xp": 0, "str": int(s.str), "vit": int(s.vit), "mag": int(s.mag), "pts": 0, "gold": int(s.gold),
		"hp": 999, "mp": 999, "pots": {"hp": int(s.pots.hp), "mp": int(s.pots.mp), "tp": int(s.pots.tp)},
		"inv": [], "eq": {}, "maxFloor": 0, "q": {"q1": 0, "q2": 0, "q3": 0}, "kills": 0, "deaths": 0, "won": false, "buff": null,
	}


static func xp_need(lvl: int) -> int:
	return int(floor(R().xp_need.base * pow(lvl, R().xp_need.exp)))


static func active_buff(hero: Dictionary) -> String:
	var b = hero.get("buff")
	if b is Dictionary and b.get("t", 0) > 0:
		return b.k
	return ""


## 按装备、属性点与神殿效果算出全部属性；同时把当前生命 / 法力截到上限（与 V0.1 一致）
static func calc(hero: Dictionary) -> Dictionary:
	var st: Dictionary = R().stats
	var fx: Dictionary = Act1Data.rules().shrines.effects
	var a := {}
	for k in STAT_KEYS:
		a[k] = 0.0
	var arm := 0.0
	var wdmg: Array = st.unarmed.dmg
	var wspd: float = st.unarmed.spd
	for slot in hero.eq:
		var it = hero.eq[slot]
		if it == null:
			continue
		if it.has("arm"):
			arm += it.arm
		if it.has("dmg"):
			wdmg = it.dmg
			wspd = it.spd
		for x in it.aff:
			a[x] = a.get(x, 0.0) + it.aff[x]
	var bf := active_buff(hero)
	var S := {}
	S.str = hero.str + a.str
	S.vit = hero.vit + a.vit
	S.mag = hero.mag + a.mag
	S.maxHp = int(round(st.hp.base + S.vit * st.hp.per_vit + hero.lvl * st.hp.per_lvl + a.life))
	S.maxMp = int(round(st.mp.base + S.mag * st.mp.per_mag + hero.lvl * st.mp.per_lvl + a.mana))
	var mul: float = (1 + S.str / st.str_dmg_div) * (1 + a.dmgp / 100.0) * (fx.might.dmg_mul if bf == "might" else 1.0)
	S.dmg = [maxi(1, int(round(wdmg[0] * mul))), maxi(1, int(round(wdmg[1] * mul)))]
	S.aps = wspd * (1 + a.ias / 100.0) * (fx.swift.aps_mul if bf == "swift" else 1.0)
	S.spell = (1 + S.mag / st.mag_spell_div) * (1 + a.spellp / 100.0) * (fx.arcane.spell_mul if bf == "arcane" else 1.0)
	S.arm = int(round((arm + hero.lvl) * (1 + a.armp / 100.0) * (fx.guard.arm_mul if bf == "guard" else 1.0)))
	S.ls = a.ls
	S.crit = st.base_crit + a.crit
	S.ms = st.base_move_speed * (1 + a.ms / 100.0) * (fx.swift.move_mul if bf == "swift" else 1.0)
	S.regen = st.regen.base + a.regen + hero.lvl * st.regen.per_lvl
	S.mregen = (st.mana_regen.base + S.mag * st.mana_regen.per_mag) * (fx.arcane.mana_regen_mul if bf == "arcane" else 1.0)
	S.gf = a.gf
	S.mf = a.mf
	S.light = st.base_light + a.light
	hero.hp = mini(int(hero.hp), S.maxHp)
	hero.mp = mini(int(hero.mp), S.maxMp)
	return S


## 护甲对某等级敌人的减伤比例
static func damage_reduction(S: Dictionary, attacker_lvl: int) -> float:
	var d: Dictionary = R().armor_dr
	return clampf(S.arm / (S.arm + d.base + attacker_lvl * d.per_mlvl), 0.0, d.cap)


## 击杀经验：玩家比怪物高出太多级时衰减
static func kill_xp(mon_xp: int, hero_lvl: int, mon_lvl: int) -> int:
	var k: Dictionary = R().kill_xp
	var diff := hero_lvl - mon_lvl
	if diff > k.free_gap:
		return int(round(mon_xp * maxf(k.floor, 1 - (diff - k.free_gap) * k.per_level)))
	return mon_xp


## 加经验，返回升了几级；升级时加属性点并回满生命法力（与 V0.1 gainXp 一致）
static func gain_xp(hero: Dictionary, v: int) -> int:
	var cap: int = int(R().level_cap)
	if hero.lvl >= cap:
		return 0
	hero.xp += v
	var ups := 0
	while hero.xp >= xp_need(hero.lvl) and hero.lvl < cap:
		hero.xp -= xp_need(hero.lvl)
		hero.lvl += 1
		hero.pts += int(R().points_per_level)
		ups += 1
		var S := calc(hero)
		hero.hp = S.maxHp
		hero.mp = S.maxMp
	return ups


## 喝药回复量
static func potion_amount(kind: String, S: Dictionary) -> int:
	var p: Dictionary = R().potions[kind]
	return int(round((S.maxHp if kind == "hp" else S.maxMp) * p.of_max + p.flat))


## 死亡时掉落的金币
static func death_gold_loss(gold: int) -> int:
	return int(floor(gold * R().death_gold_loss))


## 在已学会的技能里查（升级解锁）
static func skills_known(lvl: int) -> Array:
	return Act1Data.rules().skills.filter(func(s): return lvl >= s.lvl)
