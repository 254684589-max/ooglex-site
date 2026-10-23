class_name Sickroom
extends RefCounted
## 黑鹭堡东边塔楼一楼的病房（路线图 4.5c；STORY.md 4.5 第 3 步「见医师玛尔塔；家主昏睡」）：原创布局。5.6 × 5 米、3.2 米高的石屋：
##   北墙下一张木床，家主奥斯瑞克躺着昏睡（床头墙上挂着他没出鞘的长剑）；床边一只矮凳；东墙一扇窄窗，窗下一张小桌（药碗、陶罐、蜡烛）；西南角一只炭盆。
##   医师玛尔塔守在床边。两位继承人都找你谈过以后（heirs_heard，main._heirs_heard 设）庭院里病房的门才推得开。
## 室内的光不跟时段走；窗玻璃按时段换颜色（Inn.glass）。人物仍是占位胶囊（A.2 换装）。
## 坐标：原点在屋子地面中心，北 = -Z；出口门在南墙（z = +2.5）。

const W := 5.6
const D := 5.0
const H := 3.2
const WALL_T := 0.5
const DOOR_W := 1.1
const EXIT_NAME := "回到庭院"
const BED := Rect2(-1.0, -2.5, 1.0, 2.1)          # 北墙下的床（床头靠墙）
const BED_TOP := 0.55                             # 床褥面的高度
const TABLE := Rect2(1.7, -2.3, 0.9, 1.2)         # 东墙窗下的小桌
const WINDOW_Z := -1.7                            # 东墙窄窗的中心
const BRAZIER := Vector3(-2.1, 0, 1.6)            # 西南角的炭盆
## 人：[编号, 名字, 位置, 朝向（弧度）, 衣服颜色]
const MARTA := ["marta", "玛尔塔", Vector3(1.0, 0, -1.2), 2.84, "5a5248"]               # 床边，面朝门口
const OSRIC := ["osric", "奥斯瑞克", Vector3(-0.5, BED_TOP, -0.6), PI, "d0c8b8"]        # 躺在床上，头朝北墙
const OSRIC_LINES := ["（他睡着，呼吸又浅又慢）", "（他的手指在被子上动了一下，又不动了）", "（他嘴里含糊地说了句什么，听不清）"]
const SPAWNS := {"front": [Vector3(0, 0, 1.8), 0.0]}
const VIEW_NAMES := ["进门看病房", "床边（玛尔塔）", "床前（家主）", "门内对着出口"]
const VIEWS := [
	[Vector3(0, 0, 1.8), 0.0, -4.0],
	[Vector3(0.2, 0, 0.6), -24.0, -4.0],
	[Vector3(0.7, 0, -0.4), 50.0, -26.0],
	[Vector3(0, 0, 1.6), 180.0, -6.0],
]


static func build(parent: Node3D, reduced_motion := false) -> Transform3D:
	var kit := MeshKit.new()
	_room(kit)
	_furniture(kit)
	parent.add_child(kit.build({"stone": Look.mat("stone"), "timber": Look.mat("timber"), "glass": Inn.glass(GameState.daypart),
		"linen": Castle._cloth(Color("cfc6b2")), "wool": Castle._cloth(Color("5a4636")), "ember": Castle._flat(Color("ff7a28"), true),
		"iron": Castle._flat(Color("2a2a2e")), "clay": Castle._flat(Color("8a5a3a")), "wax": Castle._flat(Color("efe4c8"), true)}))
	_decor(parent)
	_colliders(parent)
	_lights(parent, reduced_motion)
	var exit := Door.make(EXIT_NAME, DOOR_W, 2.2, false)
	exit.verb = "离开"
	exit.to_area = "castle"
	exit.to_spawn = "sickroom_door"
	exit.position = Vector3(-DOOR_W * 0.5, 0, D * 0.5 - 0.02)
	parent.add_child(exit)
	var marta := Npc.make(str(MARTA[1]), [], Color(str(MARTA[4])))
	marta.name = "Npc_marta"
	marta.dialogue_area = "sickroom"
	marta.dialogue_id = "marta"
	marta.position = MARTA[2]
	marta.rotation.y = float(MARTA[3])
	parent.add_child(marta)
	var osric := Npc.make(str(OSRIC[1]), OSRIC_LINES, Color(str(OSRIC[4])))
	osric.name = "Npc_osric"
	osric.lying = true
	osric.position = OSRIC[2]
	osric.rotation.y = float(OSRIC[3])
	parent.add_child(osric)
	wake(parent)
	var s: Array = SPAWNS.front
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


## 黄昏家主醒了（4.8a：玛尔塔那里选「我就在这儿等他醒」，osric_awake）：能和他说话（data/dialogue/sickroom.json 的 osric）；
## 没醒的时候只能看看（OSRIC_LINES）。区域搭好时、对话关上时（main）各调一次
static func wake(world: Node) -> void:
	var osric := world.find_child("Npc_osric", true, false) as Npc
	if osric == null or not GameState.has_flag("osric_awake") or osric.dialogue_id != "":
		return
	osric.dialogue_area = "sickroom"
	osric.dialogue_id = "osric"
	osric.verb = "交谈"
	if osric.look_model != null:
		osric.look_model.hold("lying", 0.5)    # A.2b：醒着的家主撑着胳膊半坐起来（LayToIdle 起身的那一刻）


static func map_spec() -> Dictionary:
	return {
		"bounds": Rect2(-W * 0.5, -D * 0.5, W, D),
		"shapes": [
			{"k": "furniture", "rect": BED, "label": "家主的床"},
			{"k": "furniture", "rect": TABLE},
			{"k": "mark", "at": Vector2(BRAZIER.x, BRAZIER.z), "icon": "fire", "label": "炭盆"},
		],
		"exits": [{"at": Vector2(0, D * 0.5), "dir": Vector2(0, 1), "to": "castle", "spawn": "sickroom_door", "name": EXIT_NAME}],
	}


## 石地面、石墙、木梁顶；东墙一扇窄窗，南墙正中的门
static func _room(kit: MeshKit) -> void:
	var hw := W * 0.5
	var hd := D * 0.5
	kit.box("stone", Vector3(0, -0.05, 0), Vector3(W, 0.1, D), Basis.IDENTITY, 0.6, 0.6)
	kit.box("timber", Vector3(0, H + 0.05, 0), Vector3(W, 0.1, D), Basis.IDENTITY, 0.4, 0.4, true)
	for z in [-1.2, 1.2]:
		kit.box("timber", Vector3(0, H - 0.15, z), Vector3(W, 0.3, 0.3), Basis.IDENTITY, 0.5, 0.4)
	kit.box("stone", Vector3(0, H * 0.5, -hd - WALL_T * 0.5), Vector3(W + WALL_T * 2.0, H, WALL_T), Basis.IDENTITY, 0.85, 0.5)
	kit.box("stone", Vector3(-hw - WALL_T * 0.5, H * 0.5, 0), Vector3(WALL_T, H, D), Basis.IDENTITY, 0.85, 0.5)
	var xe := hw + WALL_T * 0.5         # 东墙：窄窗（0.6 宽、1.0 高，窗台 1.3 米）
	kit.box("stone", Vector3(xe, H * 0.5, (-hd + WINDOW_Z - 0.3) * 0.5), Vector3(WALL_T, H, WINDOW_Z - 0.3 + hd), Basis.IDENTITY, 0.85, 0.5)
	kit.box("stone", Vector3(xe, H * 0.5, (WINDOW_Z + 0.3 + hd) * 0.5), Vector3(WALL_T, H, hd - WINDOW_Z - 0.3), Basis.IDENTITY, 0.85, 0.5)
	kit.box("stone", Vector3(xe, 0.65, WINDOW_Z), Vector3(WALL_T, 1.3, 0.6), Basis.IDENTITY, 0.8, 0.5)
	kit.box("stone", Vector3(xe, (2.3 + H) * 0.5, WINDOW_Z), Vector3(WALL_T, H - 2.3, 0.6), Basis.IDENTITY, 0.8, 0.5)
	kit.box("glass", Vector3(xe + 0.05, 1.8, WINDOW_Z), Vector3(0.04, 1.0, 0.6))
	var zs := hd + WALL_T * 0.5
	for sx: float in [-1.0, 1.0]:
		kit.box("stone", Vector3(sx * (DOOR_W * 0.5 + hw + WALL_T) * 0.5, H * 0.5, zs), Vector3(hw + WALL_T - DOOR_W * 0.5, H, WALL_T), Basis.IDENTITY, 0.85, 0.5)
	kit.box("stone", Vector3(0, (2.2 + H) * 0.5, zs), Vector3(DOOR_W, H - 2.2, WALL_T), Basis.IDENTITY, 0.85, 0.6)
	kit.box("timber", Vector3(0, 2.28, zs - 0.1), Vector3(DOOR_W + 0.3, 0.14, 0.2))


## 床（床架、褥子、羊毛被、枕头）、床头墙上的长剑、矮凳、窗下小桌（药碗、陶罐、蜡烛）、炭盆
static func _furniture(kit: MeshKit) -> void:
	var b := BED
	var bc := Vector3(b.get_center().x, 0, b.get_center().y)
	kit.box("timber", bc + Vector3(0, 0.25, 0), Vector3(b.size.x, 0.12, b.size.y), Basis.IDENTITY, 0.9, 0.7)
	for c in [Vector2(b.position.x + 0.06, b.position.y + 0.06), Vector2(b.end.x - 0.06, b.position.y + 0.06), Vector2(b.position.x + 0.06, b.end.y - 0.06), Vector2(b.end.x - 0.06, b.end.y - 0.06)]:
		kit.box("timber", Vector3(c.x, 0.2, c.y), Vector3(0.1, 0.4, 0.1))
	kit.box("timber", Vector3(bc.x, 0.6, b.position.y + 0.05), Vector3(b.size.x, 1.0, 0.1), Basis.IDENTITY, 0.9, 0.7)
	kit.box("linen", bc + Vector3(0, 0.4, 0), Vector3(b.size.x - 0.08, 0.18, b.size.y - 0.08))
	kit.box("wool", Vector3(bc.x, 0.53, b.end.y - 0.75), Vector3(b.size.x - 0.02, 0.06, 1.3))
	kit.box("linen", Vector3(bc.x, 0.55, b.position.y + 0.3), Vector3(0.6, 0.12, 0.35))
	kit.box("timber", Vector3(bc.x, 1.75, -D * 0.5 + 0.06), Vector3(0.16, 1.1, 0.05), Basis(Vector3.BACK, 0.6))       # 剑鞘
	kit.box("iron", Vector3(bc.x - 0.33, 2.2, -D * 0.5 + 0.08), Vector3(0.36, 0.05, 0.05), Basis(Vector3.BACK, 0.6))   # 护手
	kit.cylinder("timber", Vector3(0.3, 0, -1.7), Vector3(0.3, 0.42, -1.7), 0.18, 0.16, 8, 0.8)         # 矮凳
	var t := TABLE
	kit.box("timber", Vector3(t.get_center().x, 0.74, t.get_center().y), Vector3(t.size.x, 0.06, t.size.y), Basis.IDENTITY, 0.9, 0.7)
	for c in [Vector2(t.position.x + 0.06, t.position.y + 0.06), Vector2(t.end.x - 0.06, t.position.y + 0.06), Vector2(t.position.x + 0.06, t.end.y - 0.06), Vector2(t.end.x - 0.06, t.end.y - 0.06)]:
		kit.box("timber", Vector3(c.x, 0.36, c.y), Vector3(0.07, 0.72, 0.07))
	kit.cylinder("clay", Vector3(1.95, 0.77, -2.0), Vector3(1.95, 0.85, -2.0), 0.12, 0.09, 10, 0.8)       # 药碗
	kit.cylinder("clay", Vector3(2.3, 0.77, -1.5), Vector3(2.3, 1.05, -1.5), 0.09, 0.07, 10, 0.8)         # 陶罐
	kit.cylinder("wax", Vector3(2.0, 0.77, -1.3), Vector3(2.0, 0.92, -1.3), 0.025, 0.025, 6, 1.0)          # 蜡烛
	var br := BRAZIER
	kit.cylinder("iron", br, br + Vector3(0, 0.5, 0), 0.08, 0.08, 6, 0.6)
	kit.cylinder("iron", br + Vector3(0, 0.5, 0), br + Vector3(0, 0.62, 0), 0.24, 0.3, 10, 0.8)
	kit.cylinder("ember", br + Vector3(0, 0.6, 0), br + Vector3(0, 0.64, 0), 0.24, 0.24, 10, 1.0)


## 陈设（2026-10-23 美化，Decor）：西墙一幅挂毯、床边一块小地毯、床尾的箱子、窗下桌上一簇蜡烛、门边墙上的火把
static func _decor(parent: Node3D) -> void:
	var d := Decor.new()
	var hw := W * 0.5
	d.tapestry(Vector3(-hw, 1.9, -0.6), Vector3.RIGHT, 1.6, 1.8, Color("2e3a4a"), [Color("b89a4a"), Color("6a2a26"), Color("d8d2c2")])
	d.rug(Rect2(0.15, -2.2, 1.1, 1.6), 0.0, Color("4a2e24"), Color("8a6a3a"))
	d.chest(Vector3(-0.5, 0, -0.1), 0.0, Vector3(0.8, 0.42, 0.45))
	d.candles(Vector3(2.25, 0.77, -2.0), 2, false)
	d.sconce(Vector3(1.4, 1.8, D * 0.5), Vector3.FORWARD)
	d.build(parent)


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
	Castle._solid(parent, Vector3(0, H * 0.5, zs + 0.2), Vector3(DOOR_W, H, 0.1))         # 门外：出不去（出门靠交互）
	Castle._solid(parent, Vector3(BED.get_center().x, 0.25, BED.get_center().y), Vector3(BED.size.x, 0.5, BED.size.y))       # 床：上不去（人躺在上面）
	Castle._solid(parent, Vector3(TABLE.get_center().x, 0.4, TABLE.get_center().y), Vector3(TABLE.size.x, 0.8, TABLE.size.y))
	Castle._solid(parent, BRAZIER + Vector3(0, 0.35, 0), Vector3(0.6, 0.7, 0.6))


## 光：炭盆（闪烁）、桌上的蜡烛。一共 2 盏点光源
static func _lights(parent: Node3D, reduced_motion: bool) -> void:
	var fire := Tavern.FireLight.new()
	fire.name = "Brazier"
	fire.light_color = Color("ff8a3a")
	fire.base = 1.6
	fire.omni_range = 5.0
	fire.position = BRAZIER + Vector3(0, 0.9, 0)
	fire.flicker = not reduced_motion
	fire.add_to_group("light_source")
	fire.set_meta("radius", 2.5)
	parent.add_child(fire)
	var candle := OmniLight3D.new()
	candle.name = "Candle"
	candle.light_color = Color("ffc070")
	candle.light_energy = 1.2
	candle.omni_range = 4.5
	candle.position = Vector3(2.0, 1.1, -1.3)
	parent.add_child(candle)
