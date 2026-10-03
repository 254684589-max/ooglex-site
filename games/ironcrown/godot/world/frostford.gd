class_name Frostford
extends RefCounted
## 霜渡镇主街（路线图 1.4；STORY.md 第三节「主街」）：原创布局，不照参考截图。
## 一条往北（-Z）的石板街，两侧 11 栋半木结构房屋，左手边有「倒钩鱼」酒馆和一个种着枯树、有口井的小广场，
## 街尽头是领主宅邸。雾夜：深度雾 + 贴地雾带 + 冷月光 + 暖色窗光与 4 盏街灯。
## 房屋、街灯、枯树都是代码搭的几何体 + Poly Haven 写实贴图（assets/SOURCES.md）；人物仍是占位胶囊。
## 1.3 的更夫、锁着的门、木箱上的面包都搬到这里。3.1 起「倒钩鱼」酒馆的门能进去（world/tavern.gd）；
## 3.2 起右手边一条窄巷口有扇木门，通往星铁小教堂与墓园（world/churchyard.gd）。
## 3.5 起街南头（出生点背后）有一道南门，出去是镇外桦林（world/birch.gd），再往南是渡口。

const SPAWN := Vector3(0, 0, 6)
## 命名出生点（3.1，world/areas.gd）：[位置, 水平朝向（度，0 = 面朝 -Z，正 = 向左转）]
## tavern_door：从「倒钩鱼」酒馆出来，站在门外街边、背对酒馆（面朝 +X）
const SPAWNS := {
	"start": [SPAWN, 0.0],
	"tavern_door": [Vector3(-3.1, 0, -7.1), -90.0],
	"chapel_lane": [Vector3(3.3, 0, -27.25), 90.0],     # 从墓园的小路回来：站在小路门外、面朝街心（-X）
	"south_gate": [Vector3(0, 0, 9.9), 0.0],            # 从桦林回来：站在南门里、面朝街道（3.5）
}
const SOUTH_GATE_Z := 11.1        # 南门（3.5）：在南边看不见的围墙前面
const LANE_Z := -27.25           # 右手边第 4、5 栋房子之间的窄巷：通往星铁小教堂墓园的小路门（3.2）
const STREET_HALF := 3.4         # 石板路半宽
const FRONT := 4.5               # 两侧房子正面离街中线的距离
const NORTH_END := -48.0         # 领主宅邸正面
const WATCH_POS := Vector3(2.3, 0, -3.4)
const WATCH_LINES := ["夜里雾大，少往渡口那边走。", "三年没见过春天了……烽燧那边的消息一天比一天坏。", "灯要是灭了，就回屋待着，别在街上晃。"]
const TREE_POS := Vector3(-8.6, 0, -23.5)
const STEWARD_POS := Vector3(0.0, 0, -46.6)       # 领主宅邸门前，面朝街道（+Z）
const HOB_POS := Vector3(-3.7, 0, -10.6)          # 「倒钩鱼」酒馆门口
const WELL_POS := Vector3(-6.4, 0, -25.6)
const DUMMY_POS := Vector3(-2.2, 0, -5.0)         # 更夫岗哨对面的练剑木桩（2.4）
const CRATE_POS := Vector3(-4.9, 0, -22.2)        # 小广场上没人要的破木箱（2.6 搜刮）
const CRATE_ITEMS := ["bandage", "silver_spoon"]
const LAMPS := [Vector3(3.7, 0, -2.0), Vector3(-3.7, 0, -13.0), Vector3(3.7, 0, -24.5), Vector3(-3.7, 0, -37.0)]
const VIEW_NAMES := ["出生点看街道", "小广场看枯树", "领主宅邸前回望"]
## 网页 ?view=N 的固定机位（截图用）：位置、水平朝向（度，0 = 面朝 -Z，正 = 向左转）、俯仰（度）
const VIEWS := [
	[Vector3(0, 0, 6), 0.0, -1.0],
	[Vector3(1.6, 0, -12.5), 32.0, 4.0],
	[Vector3(-0.8, 0, -41.0), 180.0, 1.0],
	[Vector3(2.3, 0, -1.6), 0.0, -8.0],        # 3：更夫面前（冒烟测试对话用，不进基准测试）
	[Vector3(0.0, 0, -44.8), 0.0, -6.0],       # 4：管家面前（冒烟测试接任务用）
	[Vector3(-2.2, 0, -3.5), 0.0, -6.0],       # 5：木桩假人面前（冒烟测试近战用）
	[Vector3(-4.9, 0, -20.6), 0.0, -35.0],     # 6：破木箱前（冒烟测试搜刮用）
]

## 左侧房子：[北端 z, 南端 z（较大）... ] → 用 [z_south, z_north, spec]
const LEFT := [
	[4.0, -3.5, {"floors": 1, "roof": "eaves", "chimney": true, "door_x": -1.6, "seed": 11, "lit": 0.6}],
	[-5.0, -12.0, {"floors": 2, "roof": "gable", "door_x": -1.4, "seed": 12, "lit": 0.9, "sign": "倒钩鱼",
		"door": {"name": "「倒钩鱼」酒馆", "to_area": "tavern", "to_spawn": "front", "verb": "进入"}}],     # 3.1 起能进去
	[-13.5, -20.0, {"floors": 1, "roof": "eaves", "door_x": 0.8, "seed": 13, "lit": 0.4}],
	[-27.0, -34.0, {"floors": 2, "roof": "eaves", "chimney": true, "door_x": 1.6, "seed": 14, "lit": 0.55}],
	[-35.5, -41.5, {"floors": 1, "roof": "gable", "door_x": 0.0, "seed": 15, "lit": 0.5}],
]
const RIGHT := [
	[5.0, -1.0, {"floors": 1, "roof": "gable", "door_x": 0.0, "seed": 21, "lit": 0.5,
		"door": {"name": "民居的门", "text": "门从里面闩上了。"}}],
	[-2.5, -10.5, {"floors": 2, "roof": "eaves", "chimney": true, "door_x": 1.8, "seed": 22, "lit": 0.6}],
	[-12.0, -18.0, {"floors": 1, "roof": "gable", "door_x": 0.0, "seed": 23, "lit": 0.45}],
	[-19.5, -26.5, {"floors": 1, "roof": "eaves", "chimney": true, "door_x": -1.4, "seed": 24, "lit": 0.6}],
	[-28.0, -34.5, {"floors": 2, "roof": "gable", "door_x": 0.0, "seed": 25, "lit": 0.6}],
	[-36.0, -42.0, {"floors": 1, "roof": "eaves", "chimney": true, "door_x": 1.2, "seed": 26, "lit": 0.5}],
]


static func build(parent: Node3D, reduced_motion := false) -> Transform3D:
	_ground(parent)
	for row in LEFT:
		var w: float = row[0] - row[1]
		var spec: Dictionary = row[2].duplicate()
		spec["w"] = w
		spec["d"] = 7.0
		House.build(parent, Vector3(-FRONT, 0, (row[0] + row[1]) * 0.5), 90.0, spec)
	for row in RIGHT:
		var w: float = row[0] - row[1]
		var spec: Dictionary = row[2].duplicate()
		spec["w"] = w
		spec["d"] = 7.0
		House.build(parent, Vector3(FRONT, 0, (row[0] + row[1]) * 0.5), -90.0, spec)
	# 街尽头：领主宅邸（两层石砌）+ 两侧矮石墙
	House.build(parent, Vector3(0, 0, NORTH_END), 0.0, {"w": 14.0, "d": 9.0, "floors": 2, "stone_upper": true, "roof": "eaves",
		"chimney": true, "door_x": 0.0, "seed": 31, "lit": 0.3,
		"door": {"name": "领主宅邸的大门", "text": "宅邸的大门闩着，门缝里透出一点灯光。"}})
	var walls := MeshKit.new()
	for sx in [-1.0, 1.0]:
		walls.box("stone", Vector3(sx * 11.0, 1.1, NORTH_END - 0.5), Vector3(8.0, 2.2, 0.6), Basis.IDENTITY, 0.9, 0.5)
		walls.box("snow", Vector3(sx * 11.0, 2.24, NORTH_END - 0.5), Vector3(8.1, 0.08, 0.7))
	_props(parent, walls)
	parent.add_child(walls.build({"stone": Look.mat("stone"), "snow": Look.mat("snow"), "timber": Look.mat("timber")}))
	for sx in [-1.0, 1.0]:
		_solid(parent, Vector3(sx * 11.0, 1.1, NORTH_END - 0.5), Vector3(8.0, 2.2, 0.6))
	BareTree.build(parent, TREE_POS, 5, 6.0)
	for i in LAMPS.size():
		var lamp := StreetLamp.new()
		var p: Vector3 = LAMPS[i]
		lamp.position = p
		lamp.rotation_degrees.y = 90.0 if p.x > 0 else -90.0    # 横臂伸向街心
		lamp.flicker = not reduced_motion
		parent.add_child(lamp)
	_fog(parent, reduced_motion)
	_bounds(parent)
	# 1.3 的交互物：更夫、木箱上的面包（锁着的门在房子里）
	var watch := Npc.make("更夫", WATCH_LINES, Color("3e4a3a"))
	watch.dialogue_area = "frostford"           # 2.1 起用对话树（data/dialogue/frostford.json）
	watch.dialogue_id = "watchman"
	watch.position = WATCH_POS
	watch.rotation.y = PI
	parent.add_child(watch)
	# 2.3：领主宅邸门口的管家（交代主线）、酒馆门口的醉汉老霍布（支线）
	var steward := Npc.make("管家", [], Color("2e2a3a"))
	steward.dialogue_area = "frostford"
	steward.dialogue_id = "steward"
	steward.position = STEWARD_POS
	steward.rotation.y = PI
	parent.add_child(steward)
	var hob := Npc.make("老霍布", [], Color("5a4a3a"))
	hob.dialogue_area = "frostford"
	hob.dialogue_id = "hob"
	hob.position = HOB_POS
	hob.rotation.y = -PI / 2
	parent.add_child(hob)
	var bread := Pickup.make("bread", "面包", Color("c8a060"))
	bread.pickup_id = "frostford_bread"
	bread.position = Vector3(-3.95, 0.62, 1.2)
	parent.add_child(bread)
	var crate := LootContainer.make("frostford_crate", "破木箱", CRATE_ITEMS, 3)
	crate.position = CRATE_POS
	crate.rotation.y = 0.2
	parent.add_child(crate)
	_lane_gate(parent)
	_south_gate(parent)
	var dummy := TrainingDummy.new()
	dummy.position = DUMMY_POS
	dummy.rotation.y = 0.3
	parent.add_child(dummy)
	return Transform3D(Basis.IDENTITY, SPAWN)


## 去墓园的小路门（3.2）：两栋房子之间 1.5 米的窄巷口，两根木柱 + 横梁 + 小檐，一扇木门；门柱上挂着写「星铁小教堂」的木牌
static func _lane_gate(parent: Node3D) -> void:
	var kit := MeshKit.new()
	var x := FRONT + 0.05
	for dz in [-0.72, 0.72]:
		kit.box("timber", Vector3(x, 1.2, LANE_Z + dz), Vector3(0.16, 2.4, 0.16), Basis.IDENTITY, 0.85, 0.5)
	kit.box("timber", Vector3(x, 2.36, LANE_Z), Vector3(0.18, 0.16, 1.6))
	kit.box("roof", Vector3(x - 0.1, 2.55, LANE_Z), Vector3(0.7, 0.08, 1.9), Basis(Vector3.BACK, deg_to_rad(18.0)))
	kit.box("timber", Vector3(x - 0.25, 1.85, LANE_Z - 0.95), Vector3(0.04, 0.3, 0.7))           # 木牌
	parent.add_child(kit.build({"timber": Look.mat("timber"), "roof": Look.mat("roof")}))
	var gate := Door.make("通往星铁小教堂的小路", 1.1, 2.0, false)
	gate.verb = "前往"
	gate.to_area = "churchyard"
	gate.to_spawn = "lane"
	gate.position = Vector3(x, 0, LANE_Z - 0.55)
	gate.rotation.y = -PI / 2                     # 门板沿 +Z 方向伸出，正面朝街
	parent.add_child(gate)
	Blocks.label(parent, "星铁小教堂", Vector3(x - 0.3, 1.85, LANE_Z - 0.95), 30, 0.006)


## 南门（3.5）：街南头两根木柱 + 横梁，一扇对开宽的木门，出去是镇外桦林；横梁上写着「南门」
static func _south_gate(parent: Node3D) -> void:
	var kit := MeshKit.new()
	var z := SOUTH_GATE_Z
	for sx in [-1.0, 1.0]:
		kit.box("timber", Vector3(sx * 1.05, 1.3, z), Vector3(0.22, 2.6, 0.22), Basis.IDENTITY, 0.85, 0.5)
	kit.box("timber", Vector3(0, 2.55, z), Vector3(2.7, 0.18, 0.22))
	kit.box("roof", Vector3(0, 2.75, z), Vector3(3.0, 0.08, 0.7))
	parent.add_child(kit.build({"timber": Look.mat("timber"), "roof": Look.mat("roof")}))
	var gate := Door.make("南门（往桦林、渡口）", 1.9, 2.2, false)
	gate.verb = "前往"
	gate.to_area = "birch"
	gate.to_spawn = "north"
	gate.position = Vector3(-0.95, 0, z)
	parent.add_child(gate)
	Blocks.label(parent, "南门", Vector3(0, 3.05, z - 0.05), 30, 0.006)


## 地面：大片雪泥地（带碰撞）+ 石板路 + 两侧路缘石
static func _ground(parent: Node3D) -> void:
	var kit := MeshKit.new()
	kit.box("snow", Vector3(0, -0.1, -20), Vector3(120, 0.2, 120), Basis.IDENTITY, 1.0, 1.0)
	var length := 12.0 - NORTH_END
	var zc := (12.0 + NORTH_END) * 0.5
	kit.box("street", Vector3(0, 0.0, zc), Vector3(STREET_HALF * 2.0, 0.02, length), Basis.IDENTITY, 0.95, 0.95)
	for sx in [-1.0, 1.0]:
		kit.box("stone", Vector3(sx * (STREET_HALF + 0.12), 0.04, zc), Vector3(0.24, 0.1, length), Basis.IDENTITY, 0.8, 0.6)
	# 小广场：铺一块不规则的石板地
	kit.box("street", Vector3(-6.0, 0.0, -23.5), Vector3(5.2, 0.02, 6.2), Basis.IDENTITY, 0.85, 0.85)
	var mi := kit.build({"snow": Look.mat("snow"), "street": Look.mat("street"), "stone": Look.mat("stone")})
	mi.name = "Ground"
	parent.add_child(mi)
	_solid(parent, Vector3(0, -0.1, -20), Vector3(120, 0.2, 120))


## 街上的小东西：井、木箱、木桶（合并进 kit）
static func _props(parent: Node3D, kit: MeshKit) -> void:
	# 井：一圈石栏 + 两根立柱 + 横梁 + 小屋顶
	for i in 8:
		var a := TAU * i / 8.0
		var c := WELL_POS + Vector3(cos(a), 0, sin(a)) * 0.75
		kit.box("stone", c + Vector3(0, 0.4, 0), Vector3(0.5, 0.8, 0.28), Basis(Vector3.UP, -a + PI / 2), 0.9, 0.55)
	kit.box("snow", WELL_POS + Vector3(0, 0.84, 0), Vector3(1.7, 0.04, 1.7))
	for sx in [-1.0, 1.0]:
		kit.box("timber", WELL_POS + Vector3(sx * 0.85, 1.1, 0), Vector3(0.12, 2.2, 0.12))
	kit.box("timber", WELL_POS + Vector3(0, 2.1, 0), Vector3(1.9, 0.1, 0.1))
	for sz in [-1.0, 1.0]:
		kit.box("timber", WELL_POS + Vector3(0, 2.35, sz * 0.4), Vector3(2.0, 0.06, 0.9), Basis(Vector3.RIGHT, deg_to_rad(30) * sz))
	_solid(parent, WELL_POS + Vector3(0, 0.5, 0), Vector3(1.9, 1.0, 1.9))
	# 木箱（面包放在第一个上）与木桶（八棱柱占位）
	for c in [Vector3(-3.95, 0.3, 1.2), Vector3(-4.0, 0.25, -12.8), Vector3(4.0, 0.3, -19.0), Vector3(-6.0, 0.3, -21.2)]:
		kit.box("timber", c, Vector3(0.6, 0.6, 0.6), Basis(Vector3.UP, c.z * 0.37), 1.0, 0.6)
		_solid(parent, c, Vector3(0.6, 0.6, 0.6))
	for c in [Vector3(-4.0, 0, -13.6), Vector3(3.95, 0, -11.3), Vector3(-6.8, 0, -21.0)]:
		kit.cylinder("timber", c, c + Vector3(0, 0.85, 0), 0.3, 0.3, 8, 0.9)
		kit.cylinder("timber", c + Vector3(0, 0.85, 0), c + Vector3(0, 0.86, 0), 0.3, 0.01, 8, 0.8)
		_solid(parent, c + Vector3(0, 0.43, 0), Vector3(0.6, 0.86, 0.6))


## 贴地雾带：沿街两层，低画质时由 main 隐藏一半
static func _fog(parent: Node3D, reduced_motion: bool) -> void:
	var root := Node3D.new()
	root.name = "FogBands"
	parent.add_child(root)
	var i := 0
	for z in range(10, -50, -8):
		for layer in [[0.35, 0.7, Vector2(8.6, 9.0)], [1.1, 0.4, Vector2(8.0, 7.0)]]:
			var mi := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = layer[2]
			mi.mesh = pm
			mi.material_override = Look.fog_material(layer[1], reduced_motion)
			mi.position = Vector3(0, layer[0], float(z) - (2.0 if layer[0] > 1.0 else 0.0))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.set_meta("fog_index", i)
			mi.add_to_group("fog_band")
			root.add_child(mi)
			i += 1
	# 小广场上一片
	var sq := MeshInstance3D.new()
	var spm := PlaneMesh.new()
	spm.size = Vector2(6.0, 7.0)
	sq.mesh = spm
	sq.material_override = Look.fog_material(0.65, reduced_motion)
	sq.position = Vector3(-6.0, 0.4, -23.5)
	sq.set_meta("fog_index", i)
	sq.add_to_group("fog_band")
	root.add_child(sq)


## 看不见的围墙：走不出这片区域（房子背后留了一圈雪地）
static func _bounds(parent: Node3D) -> void:
	for w in [[Vector3(32, 6, 0.4), Vector3(0, 3, 11.5)], [Vector3(32, 6, 0.4), Vector3(0, 3, -59)],
			[Vector3(0.4, 6, 72), Vector3(15.5, 3, -24)], [Vector3(0.4, 6, 72), Vector3(-15.5, 3, -24)]]:
		_solid(parent, w[1], w[0])


static func _solid(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	parent.add_child(body)
