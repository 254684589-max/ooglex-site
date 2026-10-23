class_name Inn
extends RefCounted
## 「歪桩客栈」里面（路线图 4.4b；STORY.md 第四节「客栈是村里最大的一栋」「客栈：两位继承人各有一帮人在村里招兵，说法截然相反」）：原创布局。
## 芦栈村最大的高脚屋（外面 12 × 9 米，world/marsh_layout.gd 的 HOUSES[0]）的底层大堂：11 × 8 米、3 米高，木板墙、木板顶、露着横梁，梁上挂着晒干的芦苇捆。
##   西北是吧台和酒架（客栈老板）；吧台东头立着一根歪了的老木桩——客栈名字的来历；东边是泥炭火塘，正上方的天花板熏得乌黑、开着烟口（楼上就是外面看到的烟囱）；
##   西边长桌是阿尔里克的人在招兵（桌上摊着名册），火塘边站着伊薇特的老兵，过道上方的横梁吊着一盏油灯；东南窗边一张小方桌（序章选「勒索」时，卡斯韦尔家的收账人吉尔伯特坐在那儿）；
##   北墙一道上楼的木梯（梯脚的栅门锁着，楼上客房不做）；南墙四扇窗（和外面的窗对得上）、正中出去的门。人物仍是占位胶囊（A.2 换装）。
## 室内的光不跟时段走（Daypart：室内永远按原来的样子）；只有窗玻璃按时段换颜色：白天、清晨是窗外发白的雾，黄昏偏橙，夜里是黑的。
## 坐标：原点在大堂地面中心，北 = -Z；出口门在南墙（z = +4）。屋子朝南，所以屋里的北就是外面的北。

const W := 11.0
const D := 8.0
const H := 3.0
const WALL_T := 0.2
const DOOR_X := 0.0               # 出口门中心（外面的 door_x = 0）
const DOOR_W := 1.1
const EXIT_NAME := "回到栈道"
const GATE_TEXT := "栅门上挂着锁。客栈老板头也不抬：「楼上的客人还没起，要住店等天黑再说。」"
const WINDOWS := [-4.9, -3.0, 2.7, 4.6]          # 南墙的窗（和外面一样：House 的窗每隔 1.9 米、避开门）
const WIN_W := 0.75
const WIN_Y := 1.55
const WIN_H := 0.9
## 家具占地（XZ：x、z、宽、高）：碰撞和地图共用
const BAR := Rect2(-4.7, -2.95, 3.6, 0.66)         # 吧台（和酒架之间留 0.7 米：老板站在中间）
const SHELF := Rect2(-4.6, -4.0, 3.2, 0.35)        # 吧台后面的酒架
const STAIRS := Rect2(0.6, -4.0, 4.8, 0.9)         # 北墙上楼的木梯（往东升，连梯下一整块）
const HEARTH := Rect2(2.5, -1.7, 1.6, 1.6)         # 泥炭火塘
const BARRELS := [Vector2(-5.0, -1.7), Vector2(-5.0, -0.95)]
const TABLE_POS := Vector3(-3.2, 0, 0.9)          # 长桌（沿东西方向，两边长凳；阿尔里克的人在这儿招兵）
const SMALL_TABLE_POS := Vector3(4.5, 0, 2.9)     # 东南窗边的小方桌
const POST_POS := Vector3(-0.75, 0, -2.6)         # 吧台东头那根歪桩（往东南歪 7°）
const POST_TILT := 7.0
const HANG_LAMP := Vector3(1.2, 2.3, 0.6)          # 过道上方横梁吊着的油灯
## 人：[编号, 名字, 位置, 朝向（弧度：0 = 面朝北，PI = 面朝南）, 衣服颜色, 对话（"" = 轮流说 lines）]
const KEEPER := ["innkeeper", "客栈老板", Vector3(-2.9, 0, -3.3), PI, "5a4632"]
const ALRIC_MAN := ["alric_sergeant", "阿尔里克的军士", Vector3(-1.55, 0, 0.9), -PI / 2, "3a4652"]     # 长桌东头，面朝过道
const IVETTE_MAN := ["ivette_veteran", "伊薇特的老兵", Vector3(3.3, 0, 0.55), PI / 2, "4e4a36"]          # 站在火塘南边烤手，面朝西边的过道（火光从侧面照着他）
const GILBERT := ["gilbert", "吉尔伯特", Vector3(3.3, 0, 2.9), PI / 2, "2e3a5a"]                     # 站在窗边小方桌旁，面朝大堂（卡斯韦尔家的蓝）
const DRINKER := ["drinker", "喝酒的泥炭工", Vector3(-4.85, 0, 0.9), -PI / 2, "4a4232"]
const OLD_BOATMAN := ["old_boatman", "烤火的老船夫", Vector3(4.55, 0, -2.25), 2.39, "3e4a4a"]          # 火塘东北边的长凳头上，面朝火
const DRINKER_LINES := ["两边的人都请我喝过酒。酒我喝了，名我可没签。", "我兄弟昨天跟着阿尔里克的人走了。说是去吃王都的粮——王都的粮长什么样，谁见过？",
	"泥炭工干一个月也攒不下三枚银币，签个名就先给三枚。你说，换了你，你去不去？"]
const OLD_BOATMAN_LINES := ["黑鹭堡建在石岛上，三百年没被人打下来过。可三百年也没见过这么冷的冬天。", "我年轻时撑船给老家主送过信。那时候他的腰板比堤道还直。",
	"堤道断的那天夜里，水是从芦苇荡里漫过来的，一点声音都没有。"]
## 命名出生点（world/areas.gd）：front = 刚从栈道进门，背对门站在门内、面朝大堂（-Z）
const SPAWNS := {
	"front": [Vector3(DOOR_X, 0, 3.1), 0.0],
}
const VIEW_NAMES := ["进门看大堂", "吧台前（客栈老板）", "火塘边（伊薇特的老兵）", "门内对着出口", "长桌前（阿尔里克的军士）", "窗边（吉尔伯特）"]
## 网页 ?area=inn&view=N 的固定机位：位置、水平朝向（度，0 = 面朝 -Z，正 = 向左转）、俯仰（度）
const VIEWS := [
	[Vector3(DOOR_X, 0, 3.1), 8.0, -4.0],
	[Vector3(-2.9, 0, -1.55), 0.0, -10.0],
	[Vector3(1.6, 0, 1.6), -58.0, -6.0],
	[Vector3(DOOR_X, 0, 2.4), 180.0, -8.0],      # 3：门内对着出口（冒烟测试出门用）
	[Vector3(-0.2, 0, 1.6), 62.0, -8.0],
	[Vector3(2.0, 0, 2.9), -90.0, -6.0],
]


static func build(parent: Node3D, reduced_motion := false) -> Transform3D:
	var kit := MeshKit.new()
	_room(kit)
	_hearth(kit)
	_bar(kit)
	_tables(kit)
	_stairs(kit)
	_post(kit)
	_reeds(kit)
	var mi := kit.build({"timber": Look.mat("timber"), "stone": Look.mat("stone"), "plaster": Look.mat("plaster"), "peat": Look.mat("peat"),
		"glass": glass(GameState.daypart), "ember": _unshaded(Color("ff7a28")), "bottle": _bottle_mat(), "soot": _unshaded(Color("0e0b09")),
		"reeds": Look.thatch(), "cloth": _cloth_mat(), "iron": _iron_mat()})
	mi.name = "Inn"
	parent.add_child(mi)
	_decor(parent, reduced_motion)
	_colliders(parent)
	_lights(parent, reduced_motion)
	# 出口：回到栈道（站在客栈门前的平台上）
	var exit := Door.make(EXIT_NAME, DOOR_W, 2.1, false)
	exit.verb = "离开"
	exit.to_area = "marsh"
	exit.to_spawn = "inn_door"
	exit.position = Vector3(DOOR_X - DOOR_W * 0.5, 0, D * 0.5 - 0.02)
	parent.add_child(exit)
	# 梯脚的栅门：锁着（楼上客房不做）。门轴在梯脚北边，门板朝南伸出去挡住梯口
	var gate := Door.make("上楼的栅门", 0.9, 1.0, true)
	gate.locked_text = GATE_TEXT
	gate.position = Vector3(STAIRS.position.x - 0.12, 0, STAIRS.position.y)
	gate.rotation.y = -PI / 2                # 本地 +X（门板伸出去的方向）朝南
	parent.add_child(gate)
	for p in [KEEPER, ALRIC_MAN, IVETTE_MAN, DRINKER, OLD_BOATMAN]:
		_person(parent, p)
	if str(GameState.get_flag("prologue_edric")) == "extort":
		_person(parent, GILBERT)             # 只在序章选「勒索」时（STORY 4.4：吉尔伯特在芦栈村等你，想把借据买回去）
	var s: Array = SPAWNS.front
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


## 窗玻璃：白天、清晨是窗外发白的雾，黄昏偏橙，夜里是黑的（室内的光不跟时段走，只有窗外的颜色告诉你现在几时）
static func glass(daypart: String) -> StandardMaterial3D:
	if daypart == "night":
		return Look.glass_dark()
	var m := _unshaded({"dawn": Color("8a949c"), "day": Color("a6b0b4"), "dusk": Color("b08a66")}.get(daypart, Color("a6b0b4")))
	return m


static func _person(parent: Node3D, p: Array) -> Npc:
	var lines: Array = []
	match str(p[0]):
		"drinker":
			lines = DRINKER_LINES
		"old_boatman":
			lines = OLD_BOATMAN_LINES
	var n := Npc.make(str(p[1]), lines, Color(str(p[4])))
	n.name = "Npc_" + str(p[0])
	if lines.is_empty():
		n.dialogue_area = "reedwharf"
		n.dialogue_id = str(p[0])
	n.position = p[2]
	n.rotation.y = float(p[3])
	parent.add_child(n)
	return n


## 地图（3.11，core/area_map.gd 的格式）：吧台、火塘、桌子、楼梯、酒桶、出口。人都不画；梯脚的栅门锁着，不算出口
static func map_spec() -> Dictionary:
	var hw := W * 0.5
	var shapes := [
		{"k": "furniture", "rect": BAR, "label": "吧台"},
		{"k": "furniture", "rect": SHELF},
		{"k": "furniture", "rect": HEARTH},
		{"k": "mark", "at": HEARTH.get_center(), "icon": "fire", "label": "火塘"},
		{"k": "furniture", "rect": Rect2(TABLE_POS.x - 1.2, TABLE_POS.z - 0.87, 2.4, 1.74), "label": "长桌"},
		{"k": "furniture", "rect": Rect2(SMALL_TABLE_POS.x - 0.5, SMALL_TABLE_POS.z - 0.5, 1.0, 1.0)},
		{"k": "furniture", "rect": STAIRS, "label": "楼梯"},
	]
	for c: Vector2 in BARRELS:
		shapes.append({"k": "furniture", "rect": Rect2(c.x - 0.33, c.y - 0.33, 0.66, 0.66)})
	return {
		"bounds": Rect2(-hw, -D * 0.5, W, D),
		"shapes": shapes,
		"exits": [{"at": Vector2(DOOR_X, D * 0.5), "dir": Vector2(0, 1), "to": "marsh", "spawn": "inn_door", "name": EXIT_NAME}],
	}


## 地板、四面木板墙（南墙留门洞和四扇窗）、木板顶与横梁、墙角和墙中间的立柱
static func _room(kit: MeshKit) -> void:
	var hw := W * 0.5
	var hd := D * 0.5
	kit.box("timber", Vector3(0, -0.05, 0), Vector3(W, 0.1, D), Basis.IDENTITY, 0.7, 0.7)
	kit.box("timber", Vector3(0, H + 0.05, 0), Vector3(W, 0.1, D), Basis.IDENTITY, 0.45, 0.45, true)
	for x in [-3.6, -1.2, 1.2, 3.6]:
		kit.box("timber", Vector3(x, H - 0.13, 0), Vector3(0.24, 0.26, D), Basis.IDENTITY, 0.55, 0.45)
	kit.box("timber", Vector3(0, H * 0.5, -hd - WALL_T * 0.5), Vector3(W, H, WALL_T), Basis.IDENTITY, 0.8, 0.6)
	kit.box("timber", Vector3(hw + WALL_T * 0.5, H * 0.5, 0), Vector3(WALL_T, H, D), Basis.IDENTITY, 0.8, 0.6)
	kit.box("timber", Vector3(-hw - WALL_T * 0.5, H * 0.5, 0), Vector3(WALL_T, H, D), Basis.IDENTITY, 0.8, 0.6)
	for z in [-hd + 0.1, hd - 0.1]:
		for x in [-hw + 0.1, hw - 0.1]:
			kit.box("timber", Vector3(x, H * 0.5, z), Vector3(0.2, H, 0.2), Basis.IDENTITY, 0.65, 0.5)
	for x in [-1.9, 1.9]:
		kit.box("timber", Vector3(x, H * 0.5, -hd + 0.07), Vector3(0.18, H, 0.14), Basis.IDENTITY, 0.65, 0.5)
	# 墙脚一圈护板（颜色深一点，看得出墙和地板的分界）
	kit.box("timber", Vector3(0, 0.12, -hd + 0.02), Vector3(W, 0.24, 0.04), Basis.IDENTITY, 0.5, 0.4)
	kit.box("timber", Vector3(hw - 0.02, 0.12, 0), Vector3(0.04, 0.24, D), Basis.IDENTITY, 0.5, 0.4)
	kit.box("timber", Vector3(-hw + 0.02, 0.12, 0), Vector3(0.04, 0.24, D), Basis.IDENTITY, 0.5, 0.4)
	# 南墙：门洞（1.1 × 2.1）与四扇窗分段拼
	var zs := hd + WALL_T * 0.5
	var door_l := DOOR_X - DOOR_W * 0.5
	var door_r := DOOR_X + DOOR_W * 0.5
	var cuts := [[door_l, door_r]]
	for wx: float in WINDOWS:
		cuts.append([wx - WIN_W * 0.5, wx + WIN_W * 0.5])
	cuts.sort_custom(func(a, b): return a[0] < b[0])
	var x0 := -hw
	for c in cuts:
		var a: float = c[0]
		if a > x0:
			kit.box("timber", Vector3((x0 + a) * 0.5, H * 0.5, zs), Vector3(a - x0, H, WALL_T), Basis.IDENTITY, 0.8, 0.6)
		x0 = c[1]
	kit.box("timber", Vector3((x0 + hw) * 0.5, H * 0.5, zs), Vector3(hw - x0, H, WALL_T), Basis.IDENTITY, 0.8, 0.6)
	var sill := WIN_Y - WIN_H * 0.5
	var head := WIN_Y + WIN_H * 0.5
	for wx: float in WINDOWS:
		kit.box("timber", Vector3(wx, sill * 0.5, zs), Vector3(WIN_W, sill, WALL_T), Basis.IDENTITY, 0.75, 0.6)
		kit.box("timber", Vector3(wx, (head + H) * 0.5, zs), Vector3(WIN_W, H - head, WALL_T), Basis.IDENTITY, 0.8, 0.7)
		kit.box("glass", Vector3(wx, WIN_Y, zs + 0.04), Vector3(WIN_W, WIN_H, 0.04))
		kit.box("timber", Vector3(wx, WIN_Y, zs - 0.03), Vector3(0.05, WIN_H, 0.05))           # 窗棂
		kit.box("timber", Vector3(wx, WIN_Y, zs - 0.03), Vector3(WIN_W, 0.05, 0.05))
		kit.box("timber", Vector3(wx, sill - 0.03, zs - 0.08), Vector3(WIN_W + 0.1, 0.06, 0.18))   # 窗台
	kit.box("timber", Vector3(DOOR_X, 2.55, zs), Vector3(DOOR_W, 0.9, WALL_T), Basis.IDENTITY, 0.8, 0.7)
	kit.box("timber", Vector3(DOOR_X, 2.16, zs - 0.06), Vector3(DOOR_W + 0.3, 0.14, 0.12))    # 门楣
	for dx in [door_l - 0.07, door_r + 0.07]:
		kit.box("timber", Vector3(dx, 1.05, zs - 0.06), Vector3(0.14, 2.1, 0.12))


## 东边的泥炭火塘：石砌的方台，台上烧着泥炭块，从天花板吊下一口铁壶；正上方的天花板熏得乌黑、开着烟口（楼上就是外面看到的烟囱）。
## 原来做过一口泥糊的圆烟罩：火光从下面照不到它朝上斜的外面，网页截图里是一团黑影，像顶黑帽子，去掉了
static func _hearth(kit: MeshKit) -> void:
	var c := Vector3(HEARTH.get_center().x, 0, HEARTH.get_center().y)
	kit.box("stone", c + Vector3(0, 0.18, 0), Vector3(HEARTH.size.x, 0.36, HEARTH.size.y), Basis.IDENTITY, 0.85, 0.6)
	kit.box("soot", c + Vector3(0, 0.365, 0), Vector3(1.1, 0.02, 1.1))
	kit.box("ember", c + Vector3(0, 0.39, 0), Vector3(0.62, 0.05, 0.62))
	for i in 6:                                   # 堆着的泥炭块
		var a := TAU * i / 6.0
		kit.box("peat", c + Vector3(cos(a) * 0.38, 0.44, sin(a) * 0.38), Vector3(0.26, 0.12, 0.16), Basis(Vector3.UP, a), 0.6, 0.4)
	kit.box("soot", c + Vector3(0, H - 0.008, 0), Vector3(2.2, 0.02, 2.2))                         # 熏黑的天花板
	kit.box("soot", c + Vector3(0, H - 0.02, 0), Vector3(0.6, 0.02, 0.6))                           # 烟口
	kit.box("timber", c + Vector3(0, H - 0.12, 0), Vector3(0.12, 0.12, 2.0))                        # 吊壶的横木
	kit.cylinder("iron", c + Vector3(0, H - 0.18, 0), c + Vector3(0, 1.18, 0), 0.015, 0.015, 4, 1.0)   # 吊壶的铁链
	kit.cylinder("iron", c + Vector3(0, 0.82, 0), c + Vector3(0, 1.18, 0), 0.2, 0.16, 8, 0.8)       # 铁壶
	# 火塘边一条长凳（老船夫坐的那边）
	kit.box("timber", Vector3(4.75, 0.42, -0.9), Vector3(0.36, 0.06, 1.8), Basis.IDENTITY, 0.9, 0.7)
	for dz in [-0.75, 0.75]:
		kit.box("timber", Vector3(4.75, 0.2, -0.9 + dz), Vector3(0.3, 0.4, 0.08), Basis.IDENTITY, 0.7, 0.5)


## 西北的吧台（台面 + 立板）与身后的酒架、酒瓶，西墙边两只酒桶
static func _bar(kit: MeshKit) -> void:
	var cx := BAR.get_center().x
	var z := BAR.get_center().y
	kit.box("timber", Vector3(cx, 0.5, z), Vector3(BAR.size.x - 0.2, 1.0, 0.5), Basis.IDENTITY, 0.75, 0.45)
	kit.box("timber", Vector3(cx, 1.04, z + 0.02), Vector3(BAR.size.x, 0.08, BAR.size.y), Basis.IDENTITY, 1.0, 0.8)
	var wall := SHELF.get_center().y
	for y in [1.15, 1.6, 2.05]:
		kit.box("timber", Vector3(SHELF.get_center().x, y, wall), Vector3(SHELF.size.x, 0.05, 0.3))
		for i in 7:
			var bx := SHELF.position.x + 0.3 + i * 0.42 + (0.07 if int(y * 10) % 2 == 0 else 0.0)
			kit.cylinder("bottle", Vector3(bx, y + 0.025, wall), Vector3(bx, y + 0.28, wall), 0.05, 0.035, 6, 0.9)
	for c: Vector2 in BARRELS:
		var b := Vector3(c.x, 0, c.y)
		kit.cylinder("timber", b, b + Vector3(0, 0.9, 0), 0.33, 0.33, 8, 0.85)
		kit.cylinder("timber", b + Vector3(0, 0.9, 0), b + Vector3(0, 0.91, 0), 0.33, 0.01, 8, 0.7)
	for bx in [-3.9, -2.2]:                       # 台面上的木杯
		kit.cylinder("timber", Vector3(bx, 1.08, z + 0.05), Vector3(bx, 1.22, z + 0.05), 0.05, 0.05, 6, 0.9)


## 长桌与长凳（桌上摊着招兵的名册、插着一面白底的小旗）；窗边的小方桌与两张凳子
static func _tables(kit: MeshKit) -> void:
	var c := TABLE_POS
	kit.box("timber", c + Vector3(0, 0.76, 0), Vector3(2.4, 0.08, 0.9), Basis.IDENTITY, 1.0, 0.8)
	for lx in [-1.0, 1.0]:
		kit.box("timber", c + Vector3(lx, 0.36, 0), Vector3(0.1, 0.72, 0.7), Basis.IDENTITY, 0.8, 0.5)
	for bz in [-0.72, 0.72]:
		kit.box("timber", c + Vector3(0, 0.44, bz), Vector3(2.2, 0.06, 0.3), Basis.IDENTITY, 0.9, 0.7)
		for lx in [-0.9, 0.9]:
			kit.box("timber", c + Vector3(lx, 0.21, bz), Vector3(0.08, 0.42, 0.24), Basis.IDENTITY, 0.8, 0.5)
	kit.box("cloth", c + Vector3(0.75, 0.81, 0.05), Vector3(0.5, 0.02, 0.36))                   # 名册（摊开的两页）
	kit.box("timber", c + Vector3(0.75, 0.805, 0.05), Vector3(0.04, 0.03, 0.36))
	kit.cylinder("timber", c + Vector3(1.05, 0.8, -0.2), c + Vector3(1.05, 0.88, -0.2), 0.04, 0.035, 6, 0.6)   # 墨水壶
	kit.cylinder("timber", c + Vector3(1.1, 0.8, -0.36), c + Vector3(1.1, 1.75, -0.36), 0.02, 0.02, 4, 0.8)   # 小旗的杆（东头，军士身边）
	kit.box("cloth", c + Vector3(1.1, 1.55, -0.14), Vector3(0.02, 0.32, 0.44))
	for i in 3:
		var mx := -0.6 + i * 0.55
		kit.cylinder("timber", c + Vector3(mx, 0.8, -0.18 + 0.2 * (i % 2)), c + Vector3(mx, 0.92, -0.18 + 0.2 * (i % 2)), 0.045, 0.045, 6, 0.9)
	kit.box("ember", c + Vector3(-0.35, 0.86, 0.15), Vector3(0.05, 0.12, 0.05))         # 桌上的蜡烛（光源另外放）
	var s := SMALL_TABLE_POS
	kit.box("timber", s + Vector3(0, 0.74, 0), Vector3(0.9, 0.06, 0.9), Basis.IDENTITY, 1.0, 0.8)
	kit.box("timber", s + Vector3(0, 0.36, 0), Vector3(0.12, 0.72, 0.12), Basis.IDENTITY, 0.8, 0.5)
	for d in [Vector3(-0.68, 0, 0), Vector3(0, 0, -0.68)]:
		kit.box("timber", s + d + Vector3(0, 0.44, 0), Vector3(0.34, 0.06, 0.34), Basis.IDENTITY, 0.9, 0.7)
		kit.box("timber", s + d + Vector3(0, 0.21, 0), Vector3(0.08, 0.42, 0.08), Basis.IDENTITY, 0.8, 0.5)
	kit.cylinder("bottle", s + Vector3(0.15, 0.77, 0.1), s + Vector3(0.15, 1.02, 0.1), 0.045, 0.03, 6, 0.9)   # 一瓶南方的酒、一只杯子
	kit.cylinder("timber", s + Vector3(-0.15, 0.77, -0.05), s + Vector3(-0.15, 0.88, -0.05), 0.04, 0.04, 6, 0.9)


## 北墙上楼的木梯：往东升，14 级（每级高 0.2 米）一直通进天花板上的梯口（黑的，楼上不做）；梯脚有栅门
static func _stairs(kit: MeshKit) -> void:
	var z := STAIRS.get_center().y
	var run := STAIRS.size.x / 14.0
	for i in 14:
		var top := 0.2 * (i + 1)
		var x := STAIRS.position.x + run * (i + 0.5)
		kit.box("timber", Vector3(x, top - 0.1, z), Vector3(run, 0.2, STAIRS.size.y), Basis.IDENTITY, 0.9, 0.6)
		kit.box("timber", Vector3(x, (top - 0.2) * 0.5, z), Vector3(run - 0.02, maxf(top - 0.2, 0.01), STAIRS.size.y - 0.02), Basis.IDENTITY, 0.55, 0.45)
	kit.box("soot", Vector3(STAIRS.end.x - 1.1, H - 0.01, z), Vector3(2.2, 0.02, STAIRS.size.y + 0.1))     # 天花板上的梯口
	# 扶手：沿梯子南沿，从梯脚斜到快碰着天花板的地方（再往上就进梯口了）
	var slope := 0.2 / run
	var zr := STAIRS.end.y - 0.04
	var r0 := Vector3(STAIRS.position.x + 0.1, 1.05, zr)
	var r1 := Vector3(4.0, 1.05 + (4.0 - r0.x) * slope, zr)
	kit.cylinder("timber", r0, r1, 0.03, 0.03, 6, 0.8)
	for x: float in [0.9, 2.2, 3.5]:              # 栏杆柱：从台阶面立到扶手
		var step_top := 0.2 * (floorf((x - STAIRS.position.x) / run) + 1.0)
		var rail := r0.y + (x - r0.x) * slope
		kit.box("timber", Vector3(x, (step_top + rail) * 0.5, zr), Vector3(0.05, rail - step_top, 0.05))


## 吧台东头那根歪桩：从地板一直顶到横梁，往东南歪 7°，桩脚箍着两道铁箍
static func _post(kit: MeshKit) -> void:
	var tilt := Basis(Vector3(1, 0, -1).normalized(), deg_to_rad(POST_TILT))
	var top := POST_POS + tilt * Vector3(0, H, 0)
	kit.cylinder("timber", POST_POS, top, 0.17, 0.15, 8, 0.75)
	for y in [0.35, 0.6]:
		var p := POST_POS + tilt * Vector3(0, y, 0)
		kit.cylinder("iron", p, p + tilt * Vector3(0, 0.05, 0), 0.18, 0.18, 8, 0.8)


## 横梁上挂着晒干的芦苇捆（鹭沼人家家都这么挂，生火、补屋顶用）；过道上方那根横梁上吊着一盏油灯
static func _reeds(kit: MeshKit) -> void:
	var l := HANG_LAMP
	kit.cylinder("iron", Vector3(l.x, H - 0.26, l.z), l + Vector3(0, 0.12, 0), 0.012, 0.012, 4, 1.0)
	kit.box("iron", l + Vector3(0, 0.1, 0), Vector3(0.24, 0.04, 0.24))
	kit.box("ember", l + Vector3(0, -0.06, 0), Vector3(0.14, 0.24, 0.14))
	kit.box("iron", l + Vector3(0, -0.2, 0), Vector3(0.22, 0.04, 0.22))
	for d in [Vector2(-0.1, -0.1), Vector2(0.1, -0.1), Vector2(-0.1, 0.1), Vector2(0.1, 0.1)]:
		kit.box("iron", l + Vector3(d.x, -0.05, d.y), Vector3(0.02, 0.28, 0.02))
	var spots := [Vector3(-3.6, 0, -1.4), Vector3(-3.6, 0, 2.6), Vector3(-1.2, 0, 2.2), Vector3(1.2, 0, 1.8), Vector3(3.6, 0, 2.4), Vector3(-1.2, 0, -0.6)]
	for i in spots.size():
		var p: Vector3 = spots[i]
		var len := 0.75 + 0.15 * (i % 3)
		kit.cylinder("reeds", Vector3(p.x, H - 0.26, p.z), Vector3(p.x, H - 0.26 - len, p.z), 0.07, 0.11, 6, 0.8)
		kit.cylinder("timber", Vector3(p.x, H - 0.26 - 0.12, p.z), Vector3(p.x, H - 0.26 - 0.17, p.z), 0.085, 0.085, 6, 0.5)   # 捆绳


## 陈设（2026-10-23 美化，Decor）：西南角板条箱和麻袋、两张桌上的蜡烛、西墙一支火把（带光）、东墙一张渔网似的挂毯
static func _decor(parent: Node3D, reduced_motion := false) -> void:
	var d := Decor.new()
	d.crate(Vector3(-5.0, 0, 3.4), 0.3, 0.55)
	d.sack(Vector3(-4.4, 0, 3.5), 0.2)
	d.sack(Vector3(-5.05, 0, 2.75), -0.4)
	d.candles(TABLE_POS + Vector3(-0.5, 0.8, 0), 2)
	d.candles(SMALL_TABLE_POS + Vector3(0, 0.77, 0), 1, false)
	d.sconce(Vector3(-W * 0.5, 1.9, 1.6), Vector3.RIGHT, true)
	d.tapestry(Vector3(W * 0.5, 1.8, 1.4), Vector3.LEFT, 1.4, 1.2, Color("5a5040"), [Color("3a3a32"), Color("7a6a4a")])
	d.build(parent, "Decor", not reduced_motion)


static func _colliders(parent: Node3D) -> void:
	var hw := W * 0.5
	var hd := D * 0.5
	_solid(parent, Vector3(0, -0.1, 0), Vector3(W + 1, 0.2, D + 1))                       # 地板
	_solid(parent, Vector3(0, H + 0.1, 0), Vector3(W + 1, 0.2, D + 1))                     # 天花板
	_solid(parent, Vector3(0, H * 0.5, -hd - WALL_T * 0.5), Vector3(W + 1, H, WALL_T))
	_solid(parent, Vector3(hw + WALL_T * 0.5, H * 0.5, 0), Vector3(WALL_T, H, D + 1))
	_solid(parent, Vector3(-hw - WALL_T * 0.5, H * 0.5, 0), Vector3(WALL_T, H, D + 1))
	var zs := hd + WALL_T * 0.5
	var door_l := DOOR_X - DOOR_W * 0.5
	var door_r := DOOR_X + DOOR_W * 0.5
	_solid(parent, Vector3((-hw + door_l) * 0.5, H * 0.5, zs), Vector3(door_l + hw, H, WALL_T))
	_solid(parent, Vector3((door_r + hw) * 0.5, H * 0.5, zs), Vector3(hw - door_r, H, WALL_T))
	_solid(parent, Vector3(DOOR_X, H * 0.5, zs + 0.15), Vector3(DOOR_W, H, 0.1))            # 门外：出不去（出门靠交互）
	_solid(parent, Vector3(BAR.get_center().x, 0.55, BAR.get_center().y), Vector3(BAR.size.x, 1.1, BAR.size.y))
	_solid(parent, Vector3(SHELF.get_center().x, 1.2, SHELF.get_center().y), Vector3(SHELF.size.x, 2.4, SHELF.size.y))
	for c: Vector2 in BARRELS:
		_solid(parent, Vector3(c.x, 0.45, c.y), Vector3(0.66, 0.9, 0.66))
	_solid(parent, TABLE_POS + Vector3(0, 0.4, 0), Vector3(2.4, 0.8, 1.74))              # 长桌连长凳
	_solid(parent, SMALL_TABLE_POS + Vector3(-0.17, 0.4, -0.17), Vector3(1.24, 0.8, 1.24))   # 小方桌连凳子
	_solid(parent, Vector3(HEARTH.get_center().x, 1.0, HEARTH.get_center().y), Vector3(HEARTH.size.x + 0.2, 2.0, HEARTH.size.y + 0.2))   # 火塘：人走不进火里（2 米高：从旁边长凳上也跳不上去，审查）
	_solid(parent, Vector3(4.75, 0.25, -0.9), Vector3(0.4, 0.5, 1.8))                     # 火塘边的长凳
	# 楼梯：栅门锁着，上不去；整段楼梯连同梯下的空间当一块实心挡住
	_solid(parent, Vector3(STAIRS.get_center().x, H * 0.5, STAIRS.get_center().y), Vector3(STAIRS.size.x, H, STAIRS.size.y))
	var tilt := Basis(Vector3(1, 0, -1).normalized(), deg_to_rad(POST_TILT))
	var body := StaticBody3D.new()                # 歪桩：斜着的圆柱
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = Transform3D(tilt, POST_POS + tilt * Vector3(0, H * 0.5, 0))
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.18
	cyl.height = H
	cs.shape = cyl
	body.add_child(cs)
	parent.add_child(body)


## 光：泥炭火塘（暖橙、闪烁）、吧台上方的油灯、过道上方吊着的油灯（照着两拨招兵的人的脸：只有火塘一盏时，背着火站的人是一团黑影）。
## 室内一共 3 盏点光源（和酒馆一样，手机上不超）；长桌上的蜡烛只发光、不照亮
static func _lights(parent: Node3D, reduced_motion: bool) -> void:
	var fire := Tavern.FireLight.new()
	fire.name = "Fire"
	fire.light_color = Color("ff8a3a")
	fire.base = 3.2
	fire.omni_range = 9.0
	fire.omni_attenuation = 1.1
	fire.position = Vector3(HEARTH.get_center().x, 0.9, HEARTH.get_center().y)
	fire.flicker = not reduced_motion
	fire.add_to_group("light_source")
	fire.set_meta("radius", 4.0)
	parent.add_child(fire)
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.3, 0.8)
	var hm := Look.halo(Color("ff8a3a"), 0.45).duplicate() as StandardMaterial3D
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = hm
	halo.mesh = q
	halo.position = Vector3(HEARTH.get_center().x, 0.6, HEARTH.get_center().y)
	parent.add_child(halo)
	var lamp := OmniLight3D.new()
	lamp.name = "BarLamp"
	lamp.light_color = Look.LAMP_COLOR
	lamp.light_energy = 2.0
	lamp.omni_range = 7.0
	lamp.position = Vector3(-2.9, 2.4, -2.0)
	parent.add_child(lamp)
	var hang := OmniLight3D.new()
	hang.name = "HangingLamp"
	hang.light_color = Look.LAMP_COLOR
	hang.light_energy = 1.5
	hang.omni_range = 6.5
	hang.position = HANG_LAMP + Vector3(0, -0.15, 0)
	parent.add_child(hang)


static func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


static func _bottle_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("3a3a26")
	m.roughness = 0.2
	m.metallic = 0.2
	m.vertex_color_use_as_albedo = true
	return m


## 名册的纸、白底小旗（瓦伦家的白）
static func _cloth_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("d8d0bc")
	m.roughness = 0.9
	m.vertex_color_use_as_albedo = true
	return m


static func _iron_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("2a2a2e")
	m.metallic = 0.6
	m.roughness = 0.5
	m.vertex_color_use_as_albedo = true
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
