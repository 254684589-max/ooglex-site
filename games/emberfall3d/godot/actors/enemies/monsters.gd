class_name Monsters
extends RefCounted
## 怪物数据与生成：读取 res://data/monsters.json，按 behavior 选对应的脚本。

## 用运行时 load 而不是 preload：召唤者脚本反过来要调用 Monsters.spawn，preload 会形成循环依赖。
const BEHAVIORS := {
	"melee": "res://actors/enemies/enemy_melee.gd",
	"charger": "res://actors/enemies/enemy_charger.gd",
	"ranged": "res://actors/enemies/enemy_ranged.gd",
	"summoner": "res://actors/enemies/enemy_summoner.gd",
	"boss_mog": "res://actors/enemies/enemy_boss_mog.gd",        # P9 首领
	"boss_abbot": "res://actors/enemies/enemy_boss_abbot.gd",
}

static var _defs: Dictionary = {}


static func defs() -> Dictionary:
	if _defs.is_empty():
		_defs = JSON.parse_string(FileAccess.open("res://data/monsters.json", FileAccess.READ).get_as_text())
		_defs.erase("_说明")
	return _defs


static func get_def(id: String) -> Dictionary:
	return defs()[id]


## 带 v01 的怪物：生命、伤害、经验、等级按所在楼层从 V0.1 对应怪物换算（P3）
static func scaled_def(id: String, floor_i: int = 1, champ: String = "") -> Dictionary:
	var d: Dictionary = get_def(id).duplicate(true)
	d.floor = floor_i
	d.champ = champ
	if d.has("v01"):
		var m := FloorRules.scale_monster(d.v01, floor_i, champ)
		d.name = m.name
		# 迅捷精英：移动速度 ×1.45（V0.1 spawnMon）；换算成 3D 速度按同样比例放大
		d.speed = float(d.speed) * float(m.spd) / float(Act1Data.monster(d.v01).spd)
		if champ != "":
			var C: Dictionary = Act1Data.rules().monsters.champion
			if champ == "fury":
				# 狂怒精英：攻击间隔 ×0.6
				for k in ["attack", "shot"]:
					if d.has(k):
						for f in ["recover_s", "cooldown_s"]:
							if d[k].has(f):
								d[k][f] = float(d[k][f]) * float(C.fury_cd_mul)
		d.hp = m.hp
		d.boss = m.boss          # P9：首领掉落按 V0.1 dropLoot 的首领分支
		d.level = m.lvl
		d.xp = m.xp
		d.armor = 0
		for k in ["attack", "shot"]:
			if d.has(k):
				d[k].dmg = m.dmg
		if d.has("charge"):
			var mul: float = d.charge.get("dmg_mul", 1.5)
			d.charge.dmg = [maxi(1, roundi(m.dmg[0] * mul)), maxi(1, roundi(m.dmg[1] * mul))]
	return d


static func spawn(id: String, parent: Node, pos: Vector3, player: Node3D, floor_i: int = 1, champ: String = "") -> EnemyBase:
	var d := scaled_def(id, floor_i, champ)
	var e: EnemyBase = load(BEHAVIORS[d.behavior]).new()
	e.setup(d, player)
	e.home = pos
	e.position = pos
	parent.add_child(e)
	e.global_position = pos
	return e
