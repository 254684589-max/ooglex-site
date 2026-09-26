class_name HeroProgress
extends RefCounted
## 主角的成长数据（P3）：角色存档字典 sheet（字段同 V0.1 newHero）+ 计算后的属性 S（HeroStats.calc）。
## 规则全部来自 P1 移植的 HeroStats / act1_rules.json；这里只负责持有状态和把属性换成战斗用的数值。
## 开局装备与 V0.1 newGame 相同：普通品质短剑 + 亚麻布衣。

signal leveled(lvl: int)
signal changed

const BASE_APS := 1.15          # 开局短剑的攻速：攻速为它时动作节奏保持阶段 1.4 调好的原样
const BASE_MOVE_M := 5.0        # 3D 里的基础移动速度（米 / 秒），按 V0.1 的移动速度加成等比缩放

var sheet: Dictionary
var S: Dictionary


func _init() -> void:
	sheet = HeroStats.new_hero()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	sheet.eq.weapon = ItemGen.generate(rng, 1, {"rarity": 0, "base": "sword"})
	sheet.eq.body = ItemGen.generate(rng, 1, {"rarity": 0, "base": "cloth"})
	recalc()


func recalc() -> void:
	S = HeroStats.calc(sheet)
	changed.emit()


## 交给 DamageCalc 的攻击方数值：V0.1 的伤害已含力量与伤害加成，所以主属性与伤害加成记 0；V0.1 暴击为双倍伤害
func combat_stats() -> Dictionary:
	return {
		"level": sheet.lvl, "main_stat": 0, "weapon_min": S.dmg[0], "weapon_max": S.dmg[1], "damage_bonus": 0.0,
		"crit_chance": S.crit / 100.0, "crit_bonus": 1.0, "armor": S.arm, "max_hp": S.maxHp, "respawn_s": 3.0,
	}


func attack_speed_scale() -> float:
	return S.aps / BASE_APS


func move_speed() -> float:
	return BASE_MOVE_M * S.ms / Act1Data.rules().hero.stats.base_move_speed


## 击杀：按等级差衰减后加经验，返回升了几级
func add_kill(mon_xp: int, mon_lvl: int) -> int:
	sheet.kills += 1
	var ups := HeroStats.gain_xp(sheet, HeroStats.kill_xp(mon_xp, sheet.lvl, mon_lvl))
	if ups > 0:
		S = HeroStats.calc(sheet)
		leveled.emit(sheet.lvl)
	changed.emit()
	return ups


func allocate(stat: String) -> bool:
	if sheet.pts <= 0 or not stat in ["str", "vit", "mag"]:
		return false
	sheet[stat] += 1
	sheet.pts -= 1
	recalc()
	return true


func xp_fraction() -> float:
	if sheet.lvl >= int(Act1Data.rules().hero.level_cap):
		return 1.0
	return clampf(float(sheet.xp) / HeroStats.xp_need(sheet.lvl), 0.0, 1.0)
