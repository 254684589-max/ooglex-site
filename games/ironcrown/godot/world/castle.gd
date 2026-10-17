class_name Castle
extends RefCounted
## 黑鹭堡的庭院（路线图 4.5a；STORY.md 第四节「黑鹭堡：沼中石岛上的城堡：堡门、庭院、兵营、大厅、账房、家主的病房；背面临水有一道水门」）：原创布局。
## 外景在鹭沼那张图上（world/marsh.gd 的粗模）；进了堡门是这个单独的室外区域 castle（时段照常）。四面 8 米高的石墙围着一个 36 × 40 米的庭院：
##   南墙正中是堡门（出去回到鹭沼的堡门前）；北边是主楼（大厅在一楼），西边是兵营（南头的西墙上开一道侧门），东边北头是家主病房所在的塔楼、南头是账房；
##   西北角的北墙上是水门（铁栅放下着，外面就是水，泥炭船从这里进出）；院子中间一口井，堡守赫尔曼守在井边。
## 4.5a 做了庭院；4.5b 大厅的门推得开（world/hall.gd）；4.5c 病房（world/sickroom.gd，两位继承人都托过你以后）、兵营（world/barracks.gd，伊薇特见过你或你从侧门进来以后）推得开；
## 守水门的老头有了对话（能坐泥炭船回芦栈村）；账房还锁着（钥匙和撬窗在 4.7 的账册支线）。没有引荐信的人从水门（托宾的泥炭船、奥弗的船）或兵营侧门（伊薇特的老兵）进来，
## 站在门里面那头；对话里的 goto 效果把人送到对应的出生点（main._on_dialogue_closed）。
## 坐标：原点在庭院地面中心，北 = -Z；堡门在南墙（z = +20）。

const HW := 18.0                  # 庭院半宽（x）
const HD := 20.0                  # 庭院半深（z）
const WALL_H := 8.0
const WALL_T := 2.5
const GATE_W := 3.2
const GATE_H := 4.2
const EXIT_NAME := "堡门"
const KEEP := [Vector3(0, 0, -10.5), 0.0, {"w": 20.0, "d": 8.5, "floors": 2, "stone_upper": true, "roof": "eaves", "chimney": true, "door_x": 0.0, "seed": 4501, "lit": 0.4,
	"door": {"name": "大厅", "to_area": "hall", "to_spawn": "front", "verb": "进入"}}]       # 4.5b 起推得开
const BARRACKS := [Vector3(-10, 0, 2), 90.0, {"w": 16.0, "d": 7.0, "floors": 1, "roof": "eaves", "door_x": 0.0, "seed": 4502, "lit": 0.3,
	"door": {"name": "兵营", "text": "兵营的门从里面闩着，门口的兵摇了摇头：「小姐没发话，外人不进。」"}}]
const BARRACKS_OPEN := {"name": "兵营", "to_area": "barracks", "to_spawn": "front", "verb": "进入"}      # 4.5c：伊薇特见过你、或者你从侧门进来以后
const TOWER := [Vector3(12, 0, -6), -90.0, {"w": 6.0, "d": 5.5, "floors": 2, "stone_upper": true, "roof": "gable", "door_x": 0.0, "seed": 4503, "lit": 0.5,
	"door": {"name": "病房", "text": "门里传来一个女人的声音：「家主睡着了，谁也别进来。」"}}]
const TOWER_OPEN := {"name": "病房", "to_area": "sickroom", "to_spawn": "front", "verb": "进入"}           # 4.5c：两位继承人都托过你以后
const COUNTING := [Vector3(12, 0, 6), -90.0, {"w": 6.0, "d": 5.5, "floors": 1, "roof": "gable", "door_x": 0.0, "seed": 4504, "lit": 0.2,
	"door": {"name": "账房", "text": "账房的门上了两道锁。钥匙在堡守赫尔曼那儿。"}}]
const WELL := Vector3(5.0, 0, 5.0)
const CART := Vector3(-5.5, 0, 12.5)
const PEAT := [Vector2(-16.0, -11.2), Vector2(-16.0, -8.6)]          # 泥炭垛：靠西墙码着（从水门进来往南走，不挡路）
const WATER_GATE_X := -14.0       # 北墙上水门的中心
const SIDE_GATE_Z := 14.0         # 西墙上兵营侧门的中心
const BANNER := Vector3(3.6, 0, -9.0)
const BRAZIERS := [Vector3(-3.0, 0, -9.4), Vector3(3.0, 0, -9.4)]     # 大厅门两边的火盆（夜灯）
## 人：[编号, 名字, 位置, 朝向（弧度）, 衣服颜色]；有对话的编号是 data/dialogue/blackheron.json 里的对话
const HERMAN := ["herman", "赫尔曼", Vector3(3.4, 0, 7.4), PI, "3a3a34"]          # 井边，面朝堡门
const GUARDS := [
	["gate_guard_in", "守门的卫兵", Vector3(2.6, 0, 17.5), 0.0, "3e4652"],
	["barracks_soldier", "兵营门口的兵", Vector3(-8.4, 0, 3.6), -PI / 2, "4e4a36"],
	["water_keeper", "守水门的老头", Vector3(-11.4, 0, -18.4), 2.0, "4a4a42"],      # 托宾、奥弗说的那个「一盏灯、一把锈剑」的老头；4.5c 起有对话（blackheron.json）
]
const GUARD_LINES := {
	"gate_guard_in": ["有事找赫尔曼大人，别在院子里乱走。", "两位继承人的人都住在堡里，各住各的。夜里别往兵营那边去。", "家主的病房谁也不让进——玛尔塔说的，赫尔曼大人点了头。"],
	"barracks_soldier": ["伊薇特小姐在兵营里跟我们一块儿吃饭。阿尔里克大人？他在大厅里。", "这几天兵营不让外人进——小姐点过头的除外。", "听说南边来的信使还在堡里，住的是最好的客房。"],
}
## 命名出生点：gate = 从堡门进来（门里面，面朝庭院）；water_gate = 从水门进来（水门里面，面朝南）；barracks_gate = 从兵营侧门进来（面朝东）
const SPAWNS := {
	"gate": [Vector3(0, 0, 17.5), 0.0],
	"water_gate": [Vector3(WATER_GATE_X, 0, -17.0), 180.0],
	"barracks_gate": [Vector3(-16.2, 0, SIDE_GATE_Z), -90.0],
	"hall_door": [Vector3(0, 0, -9.2), 180.0],                   # 从大厅出来（4.5b）：站在主楼门前、背对门
	"barracks_door": [Vector3(-8.7, 0, 2.0), -90.0],             # 从兵营出来（4.5c）：兵营门前、面朝东
	"sickroom_door": [Vector3(10.7, 0, -6.0), 90.0],             # 从病房出来（4.5c）：塔楼门前、面朝西
}
const VIEW_NAMES := ["进门看庭院", "井边（赫尔曼）", "水门里面", "门内对着堡门"]
const VIEWS := [
	[Vector3(0, 0, 17.5), 0.0, 4.0],
	[Vector3(3.4, 0, 9.6), 0.0, -6.0],
	[Vector3(WATER_GATE_X, 0, -17.0), 180.0, 0.0],
	[Vector3(0, 0, 17.6), 180.0, -2.0],     # 3：门内对着堡门（冒烟测试出门用）
]


static func build(parent: Node3D, reduced_motion := false) -> Transform3D:
	var kit := MeshKit.new()
	_ground(kit)
	_walls(kit)
	_gates(kit)
	_props(kit)
	parent.add_child(kit.build({"street": Look.mat("street"), "stone": Look.mat("stone"), "timber": Look.mat("timber"), "peat": Look.mat("peat"),
		"soot": _flat(Color("0e0b09")), "iron": _flat(Color("2a2a2e")), "water": Look.water(true), "cloth": _cloth(Color("d8d2c2")), "heron": _cloth(Color("1a1a1c")),
		"ember": _flat(Color("ff7a28"), true)}))
	for b in houses():
		var h := House.build(parent, b[0], float(b[1]), b[2])
		h.name = "House_" + str((b[2] as Dictionary).door.name)
	_colliders(parent)
	_doors(parent)
	_lights(parent, reduced_motion)
	_person(parent, HERMAN, [])
	for g in GUARDS:
		_person(parent, g, GUARD_LINES.get(str(g[0]), []))
	var s: Array = SPAWNS.gate
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


static func _person(parent: Node3D, p: Array, lines: Array) -> void:
	var n := Npc.make(str(p[1]), lines, Color(str(p[4])))
	n.name = "Npc_" + str(p[0])
	if lines.is_empty():
		n.dialogue_area = "blackheron"
		n.dialogue_id = str(p[0])
	n.position = p[2]
	n.rotation.y = float(p[3])
	parent.add_child(n)


## 病房的门推不推得开（4.5c）：两位继承人都托过你以后（main._heirs_heard 设 heirs_heard；4.5b 时的存档没有这个旗标，看两个托付的旗标，审查）
static func sickroom_open() -> bool:
	return GameState.has_flag("heirs_heard") or (GameState.has_flag("ledger_asked") and GameState.has_flag("outlaws_asked"))


## 兵营的门推不推得开（4.5c）：伊薇特见过你，或者你是从兵营侧门进来的（side_gate_used；castle_entry 以后坐别人的船进来会被改掉，审查）；
## 4.6：黄昏、夜里伊薇特在兵营（作息），兵营也推得开——不然没见过她的人在大厅找不到她、也进不了兵营，主线卡住
static func barracks_open() -> bool:
	return GameState.has_flag("ivette_met") or GameState.has_flag("side_gate_used") or str(GameState.get_flag("castle_entry")) == "barracks" \
		or Schedule.area_of("ivette") == "barracks"


## 四栋房子（门按现在的进度换成推得开的）
static func houses() -> Array:
	var out := [KEEP]
	for pair in [[BARRACKS, BARRACKS_OPEN, barracks_open()], [TOWER, TOWER_OPEN, sickroom_open()], [COUNTING, {}, false]]:
		var b: Array = pair[0]
		if pair[2]:
			var spec: Dictionary = (b[2] as Dictionary).duplicate()
			spec.door = pair[1]
			out.append([b[0], b[1], spec])
		else:
			out.append(b)
	return out


## 地图（core/area_map.gd 的格式）：庭院、四栋房子、井、水门、出口（病房、兵营推得开以后也算出口）
static func map_spec() -> Dictionary:
	var shapes := [{"k": "road", "rect": Rect2(-HW, -HD, HW * 2.0, HD * 2.0)}]
	for b in [KEEP, BARRACKS, TOWER, COUNTING]:
		var s: Dictionary = b[2]
		shapes.append({"k": "house", "pts": House.footprint(b[0], float(b[1]), float(s.w), float(s.d)), "label": str(s.door.name)})
	shapes.append({"k": "mark", "at": Vector2(WELL.x, WELL.z), "icon": "well", "label": "井"})
	shapes.append({"k": "furniture", "rect": Rect2(WATER_GATE_X - 1.6, -HD - 0.6, 3.2, 0.6), "label": "水门"})
	var exits := [{"at": Vector2(0, HD), "dir": Vector2(0, 1), "to": "marsh", "spawn": "castle_gate", "name": EXIT_NAME},
		{"at": House.door_xz(KEEP[0], float(KEEP[1]), 0.0), "dir": -House.facing(float(KEEP[1])), "to": "hall", "spawn": "front", "name": "大厅"}]
	if barracks_open():
		exits.append({"at": House.door_xz(BARRACKS[0], float(BARRACKS[1]), 0.0), "dir": -House.facing(float(BARRACKS[1])), "to": "barracks", "spawn": "front", "name": "兵营"})
	if sickroom_open():
		exits.append({"at": House.door_xz(TOWER[0], float(TOWER[1]), 0.0), "dir": -House.facing(float(TOWER[1])), "to": "sickroom", "spawn": "front", "name": "病房"})
	return {
		"bounds": Rect2(-HW - 1.0, -HD - 1.0, HW * 2.0 + 2.0, HD * 2.0 + 2.0),
		"shapes": shapes,
		"exits": exits,
	}


## 庭院地面：石板路，四边一圈排水的石沟
static func _ground(kit: MeshKit) -> void:
	kit.box("street", Vector3(0, -0.05, 0), Vector3(HW * 2.0, 0.1, HD * 2.0), Basis.IDENTITY, 0.9, 0.9)
	for z in [-HD + 0.3, HD - 0.3]:
		kit.box("stone", Vector3(0, 0.005, z), Vector3(HW * 2.0, 0.02, 0.5), Basis.IDENTITY, 0.6, 0.6)
	for x in [-HW + 0.3, HW - 0.3]:
		kit.box("stone", Vector3(x, 0.005, 0), Vector3(0.5, 0.02, HD * 2.0), Basis.IDENTITY, 0.6, 0.6)


## 四面石墙（南墙留堡门、西墙留侧门、北墙留水门的拱洞），墙头一圈雉堞；四角是方塔
static func _walls(kit: MeshKit) -> void:
	var t := WALL_T
	var gw := GATE_W * 0.5 + 0.4
	for sx: float in [-1.0, 1.0]:      # 南墙两段
		var a := gw
		kit.box("stone", Vector3(sx * (a + HW + t) * 0.5, WALL_H * 0.5, HD + t * 0.5), Vector3(HW + t - a, WALL_H, t), Basis.IDENTITY, 0.85, 0.45)    # 门洞两边（审查：原来两段在门洞上重叠）
	kit.box("stone", Vector3(0, (GATE_H + 0.5 + WALL_H) * 0.5, HD + t * 0.5), Vector3(gw * 2.0, WALL_H - GATE_H - 0.5, t), Basis.IDENTITY, 0.85, 0.6)
	# 北墙：水门那里留一个 3.2 米宽、3.2 米高的拱洞（隔着铁栅看得见外面的水和泥炭船；碰撞还是整面墙）
	var w0 := WATER_GATE_X - 1.6
	var w1 := WATER_GATE_X + 1.6
	kit.box("stone", Vector3((-HW - t + w0) * 0.5, WALL_H * 0.5, -HD - t * 0.5), Vector3(w0 + HW + t, WALL_H, t), Basis.IDENTITY, 0.85, 0.45)
	kit.box("stone", Vector3((w1 + HW + t) * 0.5, WALL_H * 0.5, -HD - t * 0.5), Vector3(HW + t - w1, WALL_H, t), Basis.IDENTITY, 0.85, 0.45)
	kit.box("stone", Vector3(WATER_GATE_X, (3.2 + WALL_H) * 0.5, -HD - t * 0.5), Vector3(3.2, WALL_H - 3.2, t), Basis.IDENTITY, 0.85, 0.6)
	for sx: float in [-1.0, 1.0]:
		kit.box("stone", Vector3(sx * (HW + t * 0.5), WALL_H * 0.5, 0), Vector3(t, WALL_H, HD * 2.0), Basis.IDENTITY, 0.85, 0.45)
	# 雉堞：墙头内沿每 1.6 米一个垛口
	var k := -HW
	while k < HW:
		for z: float in [-HD - t + 0.25, HD + t - 0.25]:
			kit.box("stone", Vector3(k + 0.4, WALL_H + 0.45, z), Vector3(0.8, 0.9, 0.5), Basis.IDENTITY, 0.9, 0.7)
		k += 1.6
	k = -HD
	while k < HD:
		for x: float in [-HW - t + 0.25, HW + t - 0.25]:
			kit.box("stone", Vector3(x, WALL_H + 0.45, k + 0.4), Vector3(0.5, 0.9, 0.8), Basis.IDENTITY, 0.9, 0.7)
		k += 1.6
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			kit.box("stone", Vector3(sx * (HW + t * 0.5), WALL_H * 0.75, sz * (HD + t * 0.5)), Vector3(5.0, WALL_H * 1.5, 5.0), Basis.IDENTITY, 0.85, 0.45)


## 堡门的拱、北墙的水门（黑洞洞的拱 + 放下的铁栅 + 外面停着的泥炭船船头）、西墙的侧门拱
static func _gates(kit: MeshKit) -> void:
	kit.box("stone", Vector3(0, GATE_H + 0.3, HD - 0.05), Vector3(GATE_W + 0.8, 0.4, 0.3), Basis.IDENTITY, 0.9, 0.7)      # 门楣（在门板上面，不压着门）
	var wx := WATER_GATE_X
	kit.box("stone", Vector3(wx, -0.25, -HD - WALL_T * 0.5), Vector3(3.2, 0.5, WALL_T), Basis.IDENTITY, 0.6, 0.4)          # 拱洞底下的石阶（往下就是水）
	kit.box("stone", Vector3(wx, 3.35, -HD + 0.1), Vector3(3.8, 0.4, 0.3), Basis.IDENTITY, 0.9, 0.7)
	for sx: float in [-1.0, 1.0]:
		kit.box("stone", Vector3(wx + sx * 1.75, 1.6, -HD + 0.1), Vector3(0.3, 3.2, 0.3), Basis.IDENTITY, 0.85, 0.6)
	for i in 7:                                    # 铁栅：竖条、横条
		kit.box("iron", Vector3(wx - 1.35 + i * 0.45, 1.5, -HD + 0.18), Vector3(0.06, 3.0, 0.06))
	for y: float in [0.4, 1.2, 2.0, 2.8]:
		kit.box("iron", Vector3(wx, y, -HD + 0.18), Vector3(3.0, 0.06, 0.06))
	kit.box("water", Vector3(wx, -0.45, -HD - WALL_T - 3.0), Vector3(8.0, 0.02, 6.0))           # 栅外的水
	kit.box("timber", Vector3(wx + 0.5, -0.3, -HD - WALL_T - 1.4), Vector3(1.3, 0.3, 2.4), Basis(Vector3.UP, 0.2), 0.8, 0.5)    # 拴在栅外的泥炭船
	kit.box("peat", Vector3(wx + 0.5, -0.05, -HD - WALL_T - 1.4), Vector3(1.0, 0.25, 1.8), Basis(Vector3.UP, 0.2), 0.8, 0.5)
	var sz := SIDE_GATE_Z
	kit.box("soot", Vector3(-HW + 0.02, 1.2, sz), Vector3(0.04, 2.4, 1.6))
	kit.box("stone", Vector3(-HW + 0.1, 2.55, sz), Vector3(0.3, 0.3, 2.0), Basis.IDENTITY, 0.9, 0.7)


## 井（石圈 + 两根柱子撑着的小顶、辘轳）、拉麦子的板车、泥炭垛、大厅门前的旗杆（白底黑鹭）、火盆
static func _props(kit: MeshKit) -> void:
	kit.cylinder("stone", WELL, WELL + Vector3(0, 0.8, 0), 0.9, 0.9, 10, 0.75)
	kit.cylinder("soot", WELL + Vector3(0, 0.78, 0), WELL + Vector3(0, 0.8, 0), 0.7, 0.7, 10, 1.0)
	for sx: float in [-1.0, 1.0]:
		kit.box("timber", WELL + Vector3(sx * 0.85, 1.3, 0), Vector3(0.12, 2.6, 0.12), Basis.IDENTITY, 0.8, 0.6)
	kit.cylinder("timber", WELL + Vector3(-0.85, 1.9, 0), WELL + Vector3(0.85, 1.9, 0), 0.08, 0.08, 6, 0.8)
	kit.box("timber", WELL + Vector3(0, 2.7, 0), Vector3(2.2, 0.1, 1.4), Basis(Vector3.RIGHT, 0.15), 0.9, 0.6)
	var c := CART
	kit.box("timber", c + Vector3(0, 0.75, 0), Vector3(1.6, 0.12, 2.8), Basis.IDENTITY, 0.9, 0.6)
	for sx: float in [-1.0, 1.0]:
		kit.box("timber", c + Vector3(sx * 0.8, 1.0, 0), Vector3(0.08, 0.4, 2.8), Basis.IDENTITY, 0.8, 0.6)
		kit.cylinder("timber", c + Vector3(sx * 0.9, 0.5, 0.6), c + Vector3(sx * 0.98, 0.5, 0.6), 0.5, 0.5, 10, 0.7)
	kit.box("timber", c + Vector3(0, 0.55, -2.1), Vector3(0.1, 0.1, 1.6), Basis(Vector3.RIGHT, -0.25), 0.8, 0.6)
	for k in 3:                                    # 车上几袋麦子（浅色麻袋；原来装的是泥炭，网页截图里整辆车是一团黑）
		kit.box("cloth", c + Vector3(-0.3 + 0.3 * (k % 2), 1.05, -0.7 + k * 0.7), Vector3(0.7, 0.45, 0.6), Basis(Vector3.UP, k * 0.3), 0.95, 0.7)
	for p: Vector2 in PEAT:
		for layer in 3:
			kit.box("peat", Vector3(p.x, 0.25 + layer * 0.48, p.y), Vector3(2.4 - layer * 0.2, 0.46, 1.5 - layer * 0.15), Basis(Vector3.UP, layer * 0.05), 0.95 - layer * 0.05, 0.6)
	var b := BANNER
	kit.cylinder("timber", b, b + Vector3(0, 6.0, 0), 0.08, 0.06, 6, 0.8)
	kit.box("cloth", b + Vector3(0.75, 4.9, 0), Vector3(1.4, 2.0, 0.03))
	kit.box("heron", b + Vector3(0.75, 4.95, -0.02), Vector3(0.3, 0.9, 0.02), Basis(Vector3.BACK, 0.3))     # 黑鹭（剪影）
	kit.box("heron", b + Vector3(0.6, 5.5, -0.02), Vector3(0.45, 0.12, 0.02), Basis(Vector3.BACK, -0.4))
	for f: Vector3 in BRAZIERS:
		kit.cylinder("iron", f, f + Vector3(0, 0.9, 0), 0.08, 0.08, 5, 0.8)
		kit.cylinder("iron", f + Vector3(0, 0.9, 0), f + Vector3(0, 1.2, 0), 0.25, 0.35, 8, 0.8)
		kit.box("ember", f + Vector3(0, 1.18, 0), Vector3(0.4, 0.06, 0.4))


static func _colliders(parent: Node3D) -> void:
	var t := WALL_T
	var gw := GATE_W * 0.5 + 0.4
	_solid(parent, Vector3(0, -0.1, 0), Vector3(HW * 2.0 + 2.0 * t, 0.2, HD * 2.0 + 2.0 * t))
	for sx: float in [-1.0, 1.0]:
		_solid(parent, Vector3(sx * (gw + HW + t) * 0.5, WALL_H * 0.5, HD + t * 0.5), Vector3(HW + t - gw, WALL_H, t))
		_solid(parent, Vector3(sx * (HW + t * 0.5), WALL_H * 0.5, 0), Vector3(t, WALL_H, HD * 2.0 + t * 2.0))
	_solid(parent, Vector3(0, WALL_H * 0.5, -HD - t * 0.5), Vector3(HW * 2.0 + t * 2.0, WALL_H, t))
	_solid(parent, Vector3(0, WALL_H * 0.5, HD + t * 0.5), Vector3(gw * 2.0, WALL_H, t * 0.6))     # 门洞后面：出不去（出门靠交互）
	for sx: float in [-1.0, 1.0]:                  # 四角的方塔伸进院子 1.25 米（审查：原来没有碰撞，走得进石头里）
		for sz: float in [-1.0, 1.0]:
			_solid(parent, Vector3(sx * (HW + t * 0.5), WALL_H * 0.75, sz * (HD + t * 0.5)), Vector3(5.0, WALL_H * 1.5, 5.0))
	_solid(parent, WELL + Vector3(0, 0.6, 0), Vector3(2.0, 1.2, 2.0))
	_solid(parent, CART + Vector3(0, 0.7, -0.3), Vector3(2.0, 1.4, 3.6))
	for p: Vector2 in PEAT:
		_solid(parent, Vector3(p.x, 0.75, p.y), Vector3(2.4, 1.5, 1.5))
	_solid(parent, BANNER + Vector3(0, 1.5, 0), Vector3(0.3, 3.0, 0.3))
	for f: Vector3 in BRAZIERS:
		_solid(parent, f + Vector3(0, 0.6, 0), Vector3(0.7, 1.2, 0.7))


## 门：出去的堡门（通往鹭沼的堡门前）、水门（铁栅放下着）、兵营侧门（从里面闩着）
static func _doors(parent: Node3D) -> void:
	var exit := Door.make(EXIT_NAME, GATE_W, GATE_H, false)
	exit.verb = "出去"
	exit.to_area = "marsh"
	exit.to_spawn = "castle_gate"
	exit.position = Vector3(-GATE_W * 0.5, 0, HD - 0.02)
	parent.add_child(exit)
	var wg := Door.make("水门", 3.0, 3.0, true)
	wg.panel = false                              # 看得见铁栅（审查：原来是一块木门板挡在铁栅前面）
	wg.locked_text = "水门的铁栅放下着，外面就是水。泥炭船从这里进出。"
	wg.position = Vector3(WATER_GATE_X - 1.5, 0, -HD + 0.1)
	parent.add_child(wg)
	var sg := Door.make("兵营侧门", 1.4, 2.3, true)
	sg.locked_text = "侧门从里面闩上了。"
	sg.position = Vector3(-HW + 0.06, 0, SIDE_GATE_Z - 0.7)
	sg.rotation.y = -PI / 2
	parent.add_child(sg)


## 夜灯：大厅门两边的火盆（白天不点）
static func _lights(parent: Node3D, reduced_motion: bool) -> void:
	for f: Vector3 in BRAZIERS:
		var l := Tavern.FireLight.new()
		l.light_color = Color("ff8a3a")
		l.base = 1.6
		l.omni_range = 9.0
		l.position = f + Vector3(0, 1.5, 0)
		l.flicker = not reduced_motion
		l.add_to_group("light_source")
		l.set_meta("radius", 5.0)
		Daypart.mark_night_light(l)
		parent.add_child(l)


static func _flat(c: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	m.vertex_color_use_as_albedo = true
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func _cloth(c: Color) -> StandardMaterial3D:
	var m := _flat(c)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


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
