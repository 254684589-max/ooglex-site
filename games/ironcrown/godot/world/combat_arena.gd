class_name CombatArena
extends RefCounted
## 训练场（路线图 2.5）：网页 ?test=2 打开。一块围起来的空地，三个无旗者（两个棍手、一个剑手）在巡逻，四支火把。
## 出生点旁边就有火把：站在火光里，20 米外的敌人也看得见你（暗处只有 8 米）。
## 敌人是正式战斗的试验品：序章里他们出现在渡口（STORY.md），不在霜渡镇街上。

const SPAWN := Vector3(0, 0, 10)
const HALF := 15.0
const TORCHES := [Vector3(-4, 0, 8), Vector3(4, 0, 8), Vector3(-7, 0, -8), Vector3(7, 0, -8)]
const TORCH_RADIUS := 6.0
## [种类, 编号, 巡逻点...]
const ENEMIES := [
	["clubber", "a", [Vector3(-6, 0, -4), Vector3(6, 0, -4)]],
	["clubber", "b", [Vector3(9, 0, -10), Vector3(9, 0, -1)]],
	["swordsman", "s", [Vector3(-2, 0, -11), Vector3(2, 0, -11)]],
]
const CRATES := [Vector3(-8, 0.4, 2), Vector3(5, 0.4, 3), Vector3(-3, 0.4, -7)]


static func build(parent: Node3D) -> Transform3D:
	var ground := Blocks.mat(Color("3e3a34"))
	var wall := Blocks.mat(Color("5a5650"))
	Blocks.box(parent, Vector3(HALF * 2 + 2, 0.2, HALF * 2 + 2), Vector3(0, -0.1, -1), ground)
	for w in [[Vector3(HALF * 2 + 2, 3, 0.4), Vector3(0, 1.5, HALF - 1 + 1)], [Vector3(HALF * 2 + 2, 3, 0.4), Vector3(0, 1.5, -HALF - 1 - 1)],
			[Vector3(0.4, 3, HALF * 2 + 2), Vector3(HALF + 1, 1.5, -1)], [Vector3(0.4, 3, HALF * 2 + 2), Vector3(-HALF - 1, 1.5, -1)]]:
		Blocks.box(parent, w[0], w[1], wall)
	for c in CRATES:
		Blocks.box(parent, Vector3(0.8, 0.8, 0.8), c, Look.mat("timber"))
	for p in TORCHES:
		_torch(parent, p)
	Blocks.label(parent, "训练场 · 三个无旗者", Vector3(0, 3.6, -HALF - 1.6))     # 北墙上方，不挡出生点的视线
	var director := CombatDirector.new()
	director.name = "CombatDirector"
	parent.add_child(director)
	for row in ENEMIES:
		var route: Array = row[2]
		var e := Enemy.make(row[0], row[1], route)
		e.position = route[0]
		parent.add_child(e)
	return Transform3D(Basis.IDENTITY, SPAWN)


## 火把：木杆 + 发光的火头 + 一盏点光源；组 light_source（敌人据此判断你是否站在亮处）
static func _torch(parent: Node3D, p: Vector3) -> void:
	var root := Node3D.new()
	root.position = p
	root.add_to_group("light_source")
	root.set_meta("radius", TORCH_RADIUS)
	parent.add_child(root)
	var kit := MeshKit.new()
	kit.cylinder("timber", Vector3.ZERO, Vector3(0, 1.9, 0), 0.05, 0.04, 6)
	kit.box("glass_lit", Vector3(0, 2.0, 0), Vector3(0.14, 0.2, 0.14), Basis.IDENTITY, 1.0, 1.0, true)
	root.add_child(kit.build({"timber": Look.mat("timber"), "glass_lit": Look.glass_lit()}))
	var l := OmniLight3D.new()
	l.light_color = Look.LAMP_COLOR
	l.light_energy = 1.8
	l.omni_range = 9.0
	l.position = Vector3(0, 2.1, 0)
	root.add_child(l)
