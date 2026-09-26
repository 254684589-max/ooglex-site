class_name Monsters
extends RefCounted
## 怪物数据与生成：读取 res://data/monsters.json，按 behavior 选对应的脚本。

## 用运行时 load 而不是 preload：召唤者脚本反过来要调用 Monsters.spawn，preload 会形成循环依赖。
const BEHAVIORS := {
	"melee": "res://actors/enemies/enemy_melee.gd",
	"charger": "res://actors/enemies/enemy_charger.gd",
	"ranged": "res://actors/enemies/enemy_ranged.gd",
	"summoner": "res://actors/enemies/enemy_summoner.gd",
}

static var _defs: Dictionary = {}


static func defs() -> Dictionary:
	if _defs.is_empty():
		_defs = JSON.parse_string(FileAccess.open("res://data/monsters.json", FileAccess.READ).get_as_text())
		_defs.erase("_说明")
	return _defs


static func get_def(id: String) -> Dictionary:
	return defs()[id]


static func spawn(id: String, parent: Node, pos: Vector3, player: Node3D) -> EnemyBase:
	var d := get_def(id)
	var e: EnemyBase = load(BEHAVIORS[d.behavior]).new()
	e.setup(d, player)
	e.home = pos
	e.position = pos
	parent.add_child(e)
	e.global_position = pos
	return e
