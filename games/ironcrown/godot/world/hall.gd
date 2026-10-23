class_name Hall
extends RefCounted
## 黑鹭堡的大厅（路线图 4.5b；STORY.md 4.5 第 4 步「两位继承人各找你谈」）：原创布局。主楼一楼，18 × 8 米、5 米高的石砌大厅：
##   北墙正中一级台子上是家主的高背椅（空着：家主在病房里昏睡），台子后面挂着白底黑鹭的大旗；台子前一张长桌；西墙一口大壁炉；南墙三扇高窗和出去的门。
##   阿尔里克站在台子东边，塞弗林家的信使跟在他身边；伊薇特在西边壁炉前；序章选「交出」的，埃德里克坐在东南窗边（他要在这里和塞弗林家定亲）。
## 室内的光不跟时段走；窗玻璃按时段换颜色（Inn.glass）。人物仍是占位胶囊（A.2 换装）。
## 坐标：原点在大厅地面中心，北 = -Z；出口门在南墙（z = +4）。

const W := 18.0
const D := 8.0
const H := 5.0
const WALL_T := 0.4
const DOOR_W := 1.6
const EXIT_NAME := "回到庭院"
const WINDOWS := [-5.5, 5.5]                    # 南墙两扇高窗（门在正中）
const DAIS := Rect2(-4.0, -4.0, 8.0, 1.6)        # 北墙正中的台子（高 0.3 米）
const SEAT := Vector3(0, 0.3, -3.5)             # 家主的高背椅
const TABLE := Rect2(-3.5, -1.6, 7.0, 1.1)       # 台子前的长桌
const HEARTH := Rect2(-9.0, -1.4, 0.9, 2.8)      # 西墙的壁炉（凸出墙面）
## 人：[编号, 名字, 位置, 朝向（弧度）, 衣服颜色]
const ALRIC := ["alric", "阿尔里克", Vector3(5.0, 0, -2.6), 2.4, "2e3440"]           # 台子东边，面朝门口
const ENVOY := ["envoy", "塞弗林家的信使", Vector3(6.6, 0, -3.0), 2.2, "6a2a26"]       # 红斗篷（塞弗林家的红）
const IVETTE := ["ivette", "伊薇特", Vector3(-6.8, 0, 0.6), -1.9, "4a3e2c"]          # 壁炉前，面朝东南
const EDRIC := ["edric_hall", "埃德里克", Vector3(6.6, 0, 2.7), PI / 2, "2a3a4e"]      # 东南窗边，只在序章「交出」时
const GUARDS := [["hall_guard", "大厅门口的卫兵", Vector3(-1.6, 0, 3.3), PI, "3e4652"]]
const ENVOY_LINES := ["（他整了整红斗篷的领口，看都没看你）", "摄政大人的耐心，不像北境的冬天这么长。", "粮车就停在南岸，等一句话。"]
const GUARD_LINES := ["两位大人说话的时候，别插嘴。", "家主的椅子空了三天了。谁也不敢坐。", "从早吵到现在，壁炉都快烧没了。"]
const GUARD_LINES_HEIR := ["家主的椅子……今晚过后，总算有人坐了。", "大门关了。另一边的人入夜前会回来。", "别在这儿站着了，去找赫尔曼大人。"]      # 印戒交出去以后（4.8a）
const SPAWNS := {"front": [Vector3(0, 0, 3.0), 0.0]}
const VIEW_NAMES := ["进门看大厅", "台子东边（阿尔里克）", "壁炉前（伊薇特）", "门内对着出口"]
const VIEWS := [
	[Vector3(0, 0, 3.0), 0.0, 2.0],
	[Vector3(4.0, 0, -1.2), -36.0, -4.0],
	[Vector3(-5.0, 0, 1.4), 68.0, -4.0],
	[Vector3(0, 0, 2.6), 180.0, -6.0],
]


static func build(parent: Node3D, reduced_motion := false) -> Transform3D:
	var kit := MeshKit.new()
	_room(kit)
	_furniture(kit)
	parent.add_child(kit.build({"stone": Look.mat("castle"), "timber": Look.mat("timber"), "street": Look.mat("street"), "glass": Inn.glass(GameState.daypart),
		"cloth": Castle._cloth(Color("d8d2c2")), "heron": Castle._cloth(Color("1a1a1c")), "ember": Castle._flat(Color("ff7a28"), true), "soot": Castle._flat(Color("0e0b09")),
		"iron": Castle._flat(Color("2a2a2e")), "red": Castle._cloth(Color("6a2a26"))}))
	_decor(parent, reduced_motion)
	_colliders(parent)
	_lights(parent, reduced_motion)
	var exit := Door.make(EXIT_NAME, DOOR_W, 2.6, false)
	exit.verb = "离开"
	exit.to_area = "castle"
	exit.to_spawn = "hall_door"
	exit.position = Vector3(-DOOR_W * 0.5, 0, D * 0.5 - 0.02)
	parent.add_child(exit)
	_person(parent, ALRIC, [])
	_person(parent, ENVOY, ENVOY_LINES)
	_person(parent, IVETTE, [])
	if str(GameState.get_flag("prologue_edric")) == "deliver":
		_person(parent, EDRIC, [])
	for g in GUARDS:
		_person(parent, g, GUARD_LINES_HEIR if GameState.has_flag("valen_heir") else GUARD_LINES)
	var s: Array = SPAWNS.front
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


static func _person(parent: Node3D, p: Array, lines: Array) -> void:
	if Chapter1.gone(str(p[0])):
		return                               # 伊薇特拿了印戒：阿尔里克带着信使离堡了（4.8a）
	var n := Npc.make(str(p[1]), lines, Color(str(p[4])))
	n.name = "Npc_" + str(p[0])
	if lines.is_empty():
		n.dialogue_area = "hall"
		n.dialogue_id = str(p[0])
	n.position = p[2]
	n.rotation.y = float(p[3])
	parent.add_child(n)


static func map_spec() -> Dictionary:
	var hw := W * 0.5
	return {
		"bounds": Rect2(-hw, -D * 0.5, W, D),
		"shapes": [
			{"k": "furniture", "rect": DAIS, "label": "家主的座位"},
			{"k": "furniture", "rect": TABLE, "label": "长桌"},
			{"k": "furniture", "rect": HEARTH},
			{"k": "mark", "at": HEARTH.get_center() + Vector2(1.0, 0), "icon": "fire", "label": "壁炉"},
		],
		"exits": [{"at": Vector2(0, D * 0.5), "dir": Vector2(0, 1), "to": "castle", "spawn": "hall_door", "name": EXIT_NAME}],
	}


## 石地面（中间铺一条石板路）、石墙、木梁顶；南墙两扇高窗和门
static func _room(kit: MeshKit) -> void:
	var hw := W * 0.5
	var hd := D * 0.5
	kit.box("stone", Vector3(0, -0.05, 0), Vector3(W, 0.1, D), Basis.IDENTITY, 0.6, 0.6)
	kit.box("street", Vector3(0, 0.005, 1.0), Vector3(2.4, 0.02, 6.0), Basis.IDENTITY, 0.8, 0.8)
	kit.box("timber", Vector3(0, H + 0.05, 0), Vector3(W, 0.1, D), Basis.IDENTITY, 0.4, 0.4, true)
	for x in [-6.0, -2.0, 2.0, 6.0]:
		kit.box("timber", Vector3(x, H - 0.2, 0), Vector3(0.35, 0.4, D), Basis.IDENTITY, 0.5, 0.4)
	kit.box("stone", Vector3(0, H * 0.5, -hd - WALL_T * 0.5), Vector3(W, H, WALL_T), Basis.IDENTITY, 0.85, 0.5)
	for sx: float in [-1.0, 1.0]:
		kit.box("stone", Vector3(sx * (hw + WALL_T * 0.5), H * 0.5, 0), Vector3(WALL_T, H, D), Basis.IDENTITY, 0.85, 0.5)
	var zs := hd + WALL_T * 0.5
	var cuts := [[-DOOR_W * 0.5, DOOR_W * 0.5]]
	for wx: float in WINDOWS:
		cuts.append([wx - 0.6, wx + 0.6])
	cuts.sort_custom(func(a, b): return a[0] < b[0])
	var x0 := -hw
	for c in cuts:
		if float(c[0]) > x0:
			kit.box("stone", Vector3((x0 + float(c[0])) * 0.5, H * 0.5, zs), Vector3(float(c[0]) - x0, H, WALL_T), Basis.IDENTITY, 0.85, 0.5)
		x0 = c[1]
	kit.box("stone", Vector3((x0 + hw) * 0.5, H * 0.5, zs), Vector3(hw - x0, H, WALL_T), Basis.IDENTITY, 0.85, 0.5)
	for wx: float in WINDOWS:
		kit.box("stone", Vector3(wx, 0.75, zs), Vector3(1.2, 1.5, WALL_T), Basis.IDENTITY, 0.8, 0.5)
		kit.box("stone", Vector3(wx, 4.1, zs), Vector3(1.2, 1.8, WALL_T), Basis.IDENTITY, 0.85, 0.6)
		kit.box("glass", Vector3(wx, 2.35, zs + 0.05), Vector3(1.2, 1.7, 0.04))
		kit.box("iron", Vector3(wx, 2.35, zs - 0.05), Vector3(0.05, 1.7, 0.05))
	kit.box("stone", Vector3(0, 3.8, zs), Vector3(DOOR_W, 2.4, WALL_T), Basis.IDENTITY, 0.85, 0.6)
	kit.box("timber", Vector3(0, 2.68, zs - 0.1), Vector3(DOOR_W + 0.4, 0.16, 0.2))


## 台子、家主的高背椅、大旗、长桌和长凳、壁炉、两盏吊着的铁烛台
static func _furniture(kit: MeshKit) -> void:
	kit.box("stone", Vector3(DAIS.get_center().x, 0.15, DAIS.get_center().y), Vector3(DAIS.size.x, 0.3, DAIS.size.y), Basis.IDENTITY, 0.8, 0.5)
	var s := SEAT
	kit.box("timber", s + Vector3(0, 0.25, 0), Vector3(1.0, 0.5, 0.8), Basis.IDENTITY, 0.9, 0.6)
	kit.box("timber", s + Vector3(0, 1.3, -0.35), Vector3(1.0, 2.1, 0.12), Basis.IDENTITY, 0.9, 0.7)
	kit.box("red", s + Vector3(0, 0.52, 0), Vector3(0.9, 0.06, 0.7))
	var t := TABLE
	kit.box("timber", Vector3(t.get_center().x, 0.78, t.get_center().y), Vector3(t.size.x, 0.08, t.size.y), Basis.IDENTITY, 1.0, 0.8)
	for lx: float in [-3.0, 0.0, 3.0]:
		kit.box("timber", Vector3(lx, 0.38, t.get_center().y), Vector3(0.12, 0.76, 0.8), Basis.IDENTITY, 0.8, 0.5)
	kit.box("timber", Vector3(t.get_center().x, 0.45, t.end.y + 0.35), Vector3(t.size.x - 0.4, 0.06, 0.32), Basis.IDENTITY, 0.9, 0.7)
	for i in 5:
		kit.cylinder("timber", Vector3(-2.8 + i * 1.4, 0.82, t.get_center().y), Vector3(-2.8 + i * 1.4, 0.95, t.get_center().y), 0.05, 0.05, 6, 0.9)
	var h := HEARTH
	kit.box("stone", Vector3(h.get_center().x, 1.6, h.get_center().y), Vector3(h.size.x, 3.2, h.size.y + 0.6), Basis.IDENTITY, 0.85, 0.6)
	kit.box("soot", Vector3(h.end.x + 0.01, 0.75, h.get_center().y), Vector3(0.02, 1.3, 1.8))
	kit.box("ember", Vector3(h.end.x - 0.2, 0.12, h.get_center().y), Vector3(0.4, 0.08, 1.2))
	kit.box("stone", Vector3(h.end.x + 0.3, 0.05, h.get_center().y), Vector3(0.6, 0.1, 2.6), Basis.IDENTITY, 0.8, 0.6)
	for cx: float in [-4.0, 4.0]:
		var c := Vector3(cx, 3.2, 0.4)
		kit.cylinder("iron", c + Vector3(0, 0.4, 0), Vector3(cx, H - 0.4, 0.4), 0.015, 0.015, 4, 1.0)
		kit.cylinder("iron", c, c + Vector3(0, 0.06, 0), 0.6, 0.6, 10, 0.8)
		for k in 6:
			var a := TAU * k / 6.0
			kit.box("ember", c + Vector3(cos(a) * 0.55, 0.14, sin(a) * 0.55), Vector3(0.04, 0.12, 0.04))


## 陈设（2026-10-23 美化，Decor）：台子后面白底黑鹭的大旗、两边墙上各一面小旗和挂毯、北墙两面盾、
## 门口到长桌的红地毯、东墙兵器架、墙上的火把、长桌上的烛台和酒杯
static func _decor(parent: Node3D, reduced_motion := false) -> void:
	var d := Decor.new()
	var hd := D * 0.5
	var hw := W * 0.5
	var white := Color("d8d2c2")
	var black := Color("1a1a1c")
	d.banner(Vector3(0, 4.6, -hd), Vector3.BACK, 2.4, 3.4, white, black, "heron")
	for s: float in [-1.0, 1.0]:
		d.shield(Vector3(s * 3.0, 3.1, -hd), Vector3.BACK, 0.42, white, black)
		d.sconce(Vector3(s * 6.2, 2.4, -hd), Vector3.BACK, true)
		d.sconce(Vector3(s * 3.0, 2.4, hd), Vector3.FORWARD)
	d.banner(Vector3(hw, 4.4, 2.2), Vector3.LEFT, 1.2, 2.4, black, white, "heron")
	d.tapestry(Vector3(hw, 2.7, -1.8), Vector3.LEFT, 2.2, 2.4, Color("4a2e24"), [Color("8a6a3a"), Color("2e3a4a"), Color("6a2a26")])
	d.banner(Vector3(-hw, 4.4, 2.6), Vector3.RIGHT, 1.2, 2.4, black, white, "heron")
	d.shield(Vector3(-hw, 3.0, -2.9), Vector3.RIGHT, 0.4, Color("6a2a26"), white)
	d.rack(Vector3(hw - 0.15, 0, 0.6), Vector3.LEFT, 1.4)
	d.rug(Rect2(-0.9, -0.3, 1.8, 4.1), 0.02, Color("6a2a26"), Color("b89a4a"))
	for x: float in [-2.1, 0.7, 2.6]:
		d.candles(Vector3(x, 0.82, TABLE.get_center().y), 3)
	d.chest(Vector3(-7.6, 0, 3.2), PI * 0.5)
	d.build(parent, "Decor", not reduced_motion)


static func _colliders(parent: Node3D) -> void:
	var hw := W * 0.5
	var hd := D * 0.5
	Castle._solid(parent, Vector3(0, -0.1, 0), Vector3(W + 1, 0.2, D + 1))
	Castle._solid(parent, Vector3(0, H + 0.1, 0), Vector3(W + 1, 0.2, D + 1))
	Castle._solid(parent, Vector3(0, H * 0.5, -hd - WALL_T * 0.5), Vector3(W + 1, H, WALL_T))
	for sx: float in [-1.0, 1.0]:
		Castle._solid(parent, Vector3(sx * (hw + WALL_T * 0.5), H * 0.5, 0), Vector3(WALL_T, H, D + 1))
	var zs := hd + WALL_T * 0.5
	for sx: float in [-1.0, 1.0]:
		Castle._solid(parent, Vector3(sx * (DOOR_W * 0.5 + hw) * 0.5, H * 0.5, zs), Vector3(hw - DOOR_W * 0.5, H, WALL_T))
	Castle._solid(parent, Vector3(0, H * 0.5, zs + 0.25), Vector3(DOOR_W, H, 0.1))         # 门外：出不去（出门靠交互）
	Castle._solid(parent, Vector3(DAIS.get_center().x, 0.6, DAIS.get_center().y), Vector3(DAIS.size.x, 1.2, DAIS.size.y))    # 台子：上不去（家主的位置）
	Castle._solid(parent, Vector3(TABLE.get_center().x, 0.45, TABLE.get_center().y + 0.2), Vector3(TABLE.size.x, 0.9, TABLE.size.y + 0.8))
	Castle._solid(parent, Vector3(HEARTH.get_center().x + 0.2, 0.8, HEARTH.get_center().y), Vector3(HEARTH.size.x + 0.4, 1.6, HEARTH.size.y + 0.6))


## 光：壁炉（闪烁）、两盏吊着的铁烛台（一盏光）。一共 3 盏点光源
static func _lights(parent: Node3D, reduced_motion: bool) -> void:
	var fire := Tavern.FireLight.new()
	fire.name = "Fire"
	fire.light_color = Color("ff8a3a")
	fire.base = 3.0
	fire.omni_range = 9.0
	fire.position = Vector3(HEARTH.end.x + 0.6, 1.0, HEARTH.get_center().y)
	fire.flicker = not reduced_motion
	fire.add_to_group("light_source")
	fire.set_meta("radius", 4.0)
	parent.add_child(fire)
	for cx: float in [-4.0, 4.0]:
		var l := OmniLight3D.new()
		l.name = "Chandelier_W" if cx < 0.0 else "Chandelier_E"
		l.light_color = Color("ffb060")
		l.light_energy = 2.2
		l.omni_range = 8.0
		l.position = Vector3(cx, 3.0, 0.4)
		parent.add_child(l)
