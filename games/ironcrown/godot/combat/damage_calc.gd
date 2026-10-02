class_name DamageCalc
extends RefCounted
## 伤害公式（GDD.md 6.3），纯规则、不碰场景，便于测试：
##   伤害 = 武器基础伤害 × (1 + 力量 × 0.03 + 技能 × 0.005) × 攻击类型系数（轻 1.0 / 重 1.8） × 失衡倍率（失衡时 2）
##   再减去 护甲 × 0.5，但至少保留 20%；四舍五入，至少 1 点。

const TYPE_MUL := {"light": 1.0, "heavy": 1.8}
const STAGGER_MUL := 2.0
const ARMOR_FACTOR := 0.5
const MIN_SHARE := 0.2


static func compute(base: float, strength: int, skill: int, kind: String, staggered := false, armor := 0.0) -> int:
	var raw := base * (1.0 + strength * 0.03 + skill * 0.005) * float(TYPE_MUL.get(kind, 1.0))
	if staggered:
		raw *= STAGGER_MUL
	var after := maxf(raw - armor * ARMOR_FACTOR, raw * MIN_SHARE)
	return maxi(1, roundi(after))
