class_name BattleArena
extends RefCounted
## 军阵试验场（路线图 B.1，D8；网页 ?test=3）：一片围起来的雪地，白带（你这边）对黑带，每边默认 10 人（?test=3&n=30 每边最多 30 人，共 60）。
## 开局 3 秒后开打（main）；你站在白带后面，可以冲上去帮忙，也可以上身后的观战台看。黑带的人也会来打你，白带的人你砍不到。
## 兵是占位胶囊：罩袍按阵营上色，胸前一道白 / 黑布带（正式外观在 B.6）。
## B.4 兵种搭配（每 10 人，kind_for）：前排两头剑盾兵、中间两个长枪兵、剑兵 2、持棍民兵 2，后排一个弓手和队长。
## B.2：白带前排的 6 个人（n 大时是 6 成，最多 12 个）是你的小队，头顶有 ◆，听 1 / 2 / 3（触屏「令」）的命令；默认冲锋。
## B.3：每边最后一个人是队长（背上插小旗，倒下时全队士气大掉）；黑带开打 12 秒后有 4 个援军从北头进场（每边 3 人以上时）——不帮忙的话白带多半要输。

const HALF_X := 22.0
const NORTH := -24.0
const SOUTH := 20.0
const SPAWN := Vector3(0, 0, 12)
const PER_SIDE := 10
const SQUAD_MAX := 12              # 小队最多几个人（GDD 6.4：6–12 人）
const WAVE_SIZE := 4               # 黑带援军人数（B.3）
const WAVE_DELAY := 12.0           # 开打后多少秒到（满血 10 对 10 一般 13–19 秒分出胜负，20 秒时援军常常赶不上）
const WAVE_Z := NORTH + 2.5        # 援军从北头进场
const WAVE_KINDS := ["shield", "soldier", "archer", "levy"]
const MAX_PER_SIDE := 30
const WHITE_Z := 6.0               # 白带第一排
const BLACK_Z := -10.0             # 黑带第一排
const GAP := 1.6                   # 队列里人与人的间距
const ROW := 8                     # 每排几个人
const STAND_TOP := 1.5             # 观战台台面高度
const TORCHES := [Vector3(-12, 0, 8), Vector3(12, 0, 8), Vector3(-12, 0, -12), Vector3(12, 0, -12)]
const SIDES := {
	"white": {"name": "白带", "coat": "5e6e80", "band": "ece6d8"},
	"black": {"name": "黑带", "coat": "8a4636", "band": "161616"},      # 罩袍偏红：深色罩袍上黑布带看不清（B.1 截图）
}
const VIEW_NAMES := ["白带身后", "观战台上", "两军之间"]
## 固定机位（截图、冒烟测试用）：[位置, 水平朝向（度）, 俯仰（度）]
const VIEWS := [
	[SPAWN, 0.0, -4.0],
	[Vector3(0, STAND_TOP, 18.0), 0.0, -14.0],
	[Vector3(-7.0, 0, -2.0), -60.0, -6.0],
]


static func build(parent: Node3D, per_side := PER_SIDE) -> Transform3D:
	var ground := Look.mat("snow")
	var wall := Blocks.mat(Color("4a4844"))
	Blocks.box(parent, Vector3(HALF_X * 2 + 2, 0.2, SOUTH - NORTH + 2), Vector3(0, -0.1, (SOUTH + NORTH) * 0.5), ground)
	var cz := (SOUTH + NORTH) * 0.5
	var lz := SOUTH - NORTH + 2
	for w in [[Vector3(HALF_X * 2 + 2, 2.4, 0.4), Vector3(0, 1.2, SOUTH + 1)], [Vector3(HALF_X * 2 + 2, 2.4, 0.4), Vector3(0, 1.2, NORTH - 1)],
			[Vector3(0.4, 2.4, lz), Vector3(HALF_X + 1, 1.2, cz)], [Vector3(0.4, 2.4, lz), Vector3(-HALF_X - 1, 1.2, cz)]]:
		Blocks.box(parent, w[0], w[1], wall)
	_stand(parent)
	for p in TORCHES:
		CombatArena._torch(parent, p)
	Blocks.label(parent, "军阵试验场 · 白带（你这边）对 黑带", Vector3(0, 3.4, NORTH - 0.6))
	var director := CombatDirector.new()
	director.name = "CombatDirector"
	parent.add_child(director)
	var battle := Battle.new()
	battle.name = "Battle"
	battle.player_side = "white"
	for id in SIDES:
		battle.add_side(id, SIDES[id].name)
	parent.add_child(battle)
	var n := clampi(per_side, 1, MAX_PER_SIDE)
	for id in ["white", "black"]:
		for i in n:
			var kind := kind_for(i, n)
			var c: Dictionary = SIDES[id]
			var s := Soldier.create(kind, "%s%02d" % [id, i], id, Color(c.coat), Color(c.band))
			s.display_override = "%s · %s" % [c.name, Enemy.types()[kind].name]
			s.position = slot(id, i, n)
			s.rotation.y = 0.0 if id == "white" else PI      # 白带面朝北（-Z），黑带面朝南
			if id == "white" and i < squad_size(n):
				battle.add_to_squad(s)
			battle.enlist(s, parent)
	if n >= 3:                                                               # 黑带的援军（B.3）
		var wave: Array = []
		for i in WAVE_SIZE:
			var kind: String = WAVE_KINDS[i % WAVE_KINDS.size()]
			var c: Dictionary = SIDES.black
			var s := Soldier.create(kind, "blackw%d" % i, "black", Color(c.coat), Color(c.band))
			s.display_override = "%s · %s（援军）" % [c.name, Enemy.types()[kind].name]
			s.position = Vector3((i - (WAVE_SIZE - 1) * 0.5) * GAP, 0, WAVE_Z)
			s.rotation.y = PI
			wave.append(s)
		battle.add_wave("black", wave, parent, WAVE_DELAY)
	return Transform3D(Basis.IDENTITY, SPAWN)


## 第 i 个兵是什么兵（B.4）：每 10 人里 0、7 剑盾兵，3、4 长枪兵，2、5 民兵，8 弓手，其余剑兵；每边最后一个是队长（B.3）
static func kind_for(i: int, n: int) -> String:
	if i == n - 1 and n >= 3:
		return "captain"
	match i % 10:
		0, 7:
			return "shield"
		3, 4:
			return "spear"
		2, 5:
			return "levy"
		8:
			return "archer"
	return "soldier"


## 小队人数：每边人数的六成，1–12 人（10 人时 6 个）
static func squad_size(per_side: int) -> int:
	return clampi(per_side * 6 / 10, 1, SQUAD_MAX)


## 第 i 个兵在队列里的位置：每排 ROW 人，左右居中；白带往南排、黑带往北排
static func slot(side: String, i: int, n: int) -> Vector3:
	var cols := mini(n, ROW)
	var row := i / ROW
	var col := i % ROW
	var in_row := mini(cols, n - row * ROW)
	var x := (col - (in_row - 1) * 0.5) * GAP
	var z := WHITE_Z + row * GAP if side == "white" else BLACK_Z - row * GAP
	return Vector3(x, 0, z)


## 观战台：白带身后一座木台子（16.5–19.5 米），前面五级台阶，每级 0.25 米（主角最多跨 0.3 米，正好 0.3 米时会卡住）
static func _stand(parent: Node3D) -> void:
	var wood := Look.mat("timber")
	Blocks.box(parent, Vector3(6, STAND_TOP, 3), Vector3(0, STAND_TOP * 0.5, 18.0), wood)
	var steps := int(round(STAND_TOP / 0.25)) - 1
	for i in range(1, steps + 1):
		var h := 0.25 * i
		Blocks.box(parent, Vector3(3, h, 0.5), Vector3(0, h * 0.5, 16.5 - (steps + 1 - i) * 0.5 + 0.25), wood)
