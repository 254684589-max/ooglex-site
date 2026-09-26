class_name DamageCalc
extends RefCounted
## 伤害公式（GDD.md 第 4.2 节），纯函数，可在无头模式下单元测试：
##   技能伤害 = 武器伤害 × 技能系数 × (1 + 主属性/100) × (1 + 伤害加成) × 暴击
##   受到伤害 = 原始伤害 × (1 - 护甲减伤) × (1 - 抗性减伤)
##   护甲减伤 = 护甲 / (护甲 + 40 + 18 × 攻击者等级)，上限 75%
##   抗性减伤 = 抗性 / (抗性 + 5 × 攻击者等级)，上限 70%（「虚」伤害没有抗性）


static func armor_reduction(armor: float, attacker_level: int) -> float:
	var a: Dictionary = Balance.data().armor
	if armor <= 0.0:
		return 0.0
	return minf(armor / (armor + a.base + a.per_level * attacker_level), a.cap)


static func resist_reduction(resist: float, attacker_level: int) -> float:
	var r: Dictionary = Balance.data().resist
	if resist <= 0.0:
		return 0.0
	return minf(resist / (resist + r.per_level * attacker_level), r.cap)


static func roll(attacker: Dictionary, coef: float, dtype: String, target: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	## attacker: level, main_stat, weapon_min, weapon_max, damage_bonus, [crit_chance, crit_bonus]
	## target: armor, resist（字典：伤害类型 → 抗性值）
	var c: Dictionary = Balance.data().crit
	var weapon := rng.randf_range(attacker.weapon_min, attacker.weapon_max)
	var raw: float = weapon * coef * (1.0 + attacker.main_stat / 100.0) * (1.0 + attacker.get("damage_bonus", 0.0))
	var crit: bool = rng.randf() < attacker.get("crit_chance", c.base_chance)
	if crit:
		raw *= 1.0 + attacker.get("crit_bonus", c.base_bonus)
	var lvl: int = attacker.level
	var dealt := raw * (1.0 - armor_reduction(target.get("armor", 0.0), lvl))
	if dtype != "void":
		dealt *= 1.0 - resist_reduction(target.get("resist", {}).get(dtype, 0.0), lvl)
	return { "amount": maxi(1, roundi(dealt)), "crit": crit, "type": dtype, "raw": raw }
