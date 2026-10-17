class_name Barracks
extends RefCounted
## 黑鹭堡西边的兵营（路线图 4.5c；STORY.md 第四节「伊薇特：兵营里的人都服她」）：原创布局。15 × 6.4 米、3.4 米高的长屋：
##   北墙下一排上下铺，屋子中间一张长桌和两条长凳（有人在掷骰子），西墙一排兵器架，东墙一口炉子，南墙两扇小窗和门。
##   伊薇特的军士、三个兵。伊薇特见过你（ivette_met）或者你是从兵营侧门进来的（castle_entry = barracks），庭院里兵营的门才推得开（Castle.barracks_open）。
## 室内的光不跟时段走；窗玻璃按时段换颜色（Inn.glass）。人物仍是占位胶囊（A.2 换装）。
## 坐标：原点在屋子地面中心，北 = -Z；出口门在南墙（z = +3.2）。

const W := 15.0
const D := 6.4
const H := 3.4
const WALL_T := 0.5
const DOOR_W := 1.3
const EXIT_NAME := "回到庭院"
const WINDOWS := [-4.5, 4.5]                       # 南墙两扇小窗（门在正中）
const BUNKS := [-5.6, -3.0, 3.0, 5.6]              # 北墙下的上下铺（中心 x；2.0 长、0.9 深）
const BUNK_Z := -2.75
const TABLE := Rect2(-2.5, -0.5, 5.0, 1.0)         # 长桌（离上下铺留 1.3 米的过道）
const RACK := Rect2(-7.5, -1.4, 0.45, 2.4)         # 西墙的兵器架
const STOVE := Rect2(6.9, -0.9, 0.6, 1.6)          # 东墙的炉子
## 人：[编号, 名字, 位置, 朝向（弧度）, 衣服颜色]；sergeant 有对话（data/dialogue/barracks.json），其余的说写在代码里的话
const SERGEANT := ["sergeant", "伊薇特的军士", Vector3(-3.6, 0, 1.0), -2.13, "4e4a36"]
const SOLDIERS := [
	["dice_soldier", "掷骰子的兵", Vector3(1.0, 0, -1.65), PI, "4e4a36"],
	["rack_soldier", "磨刀的兵", Vector3(-6.4, 0, 1.6), PI / 2, "4a4632"],
	["stove_soldier", "烤火的兵", Vector3(5.6, 0, 1.0), -PI / 2, "524c3a"],
]
const SOLDIER_LINES := {
	"dice_soldier": ["（他把骰子拢进手心，冲你笑了笑）来一把？输了替我站夜岗。", "南边的兵？没见过。我们这些人，冬天守烽燧，夏天剿沼地的贼。", "小姐说，谁要是先拔刀，她就先砍谁——两边都一样。"],
	"rack_soldier": ["（他头也不抬，磨刀石一下一下推着）刀不快，夜里就睡不踏实。", "长枪比剑好使。堤道那么窄，三个人一排就能把路堵死。", "小姐跟我们一块儿吃饭、一块儿站岗。大厅里那位？没在兵营里睡过一晚。"],
	"stove_soldier": ["（他把手伸到炉子跟前搓了搓）泥炭快烧完了。托宾那边再不送来，这个冬天难熬。", "去年秋天招的人，一半是芦栈村的小伙子。家都在村里，谁也不想跟自己家门口打仗。", "家主醒着的时候来过兵营一回，挨个叫得出名字。……不知道他现在还记不记得。"],
}
const SPAWNS := {"front": [Vector3(0, 0, 2.4), 0.0]}
const VIEW_NAMES := ["进门看兵营", "长桌边（军士）", "炉子边", "门内对着出口"]
const VIEWS := [
	[Vector3(0, 0, 2.4), 0.0, -2.0],
	[Vector3(-2.3, 0, 2.2), 47.0, -4.0],
	[Vector3(3.6, 0, 2.0), -60.0, -4.0],
	[Vector3(0, 0, 2.2), 180.0, -6.0],
]


static func build(parent: Node3D, reduced_motion := false) -> Transform3D:
	var kit := MeshKit.new()
	_room(kit)
	_furniture(kit)
	parent.add_child(kit.build({"stone": Look.mat("stone"), "timber": Look.mat("timber"), "glass": Inn.glass(GameState.daypart),
		"straw": Castle._cloth(Color("9a8a5a")), "wool": Castle._cloth(Color("4e4436")), "ember": Castle._flat(Color("ff7a28"), true),
		"iron": Castle._flat(Color("5a5a60")), "soot": Castle._flat(Color("0e0b09")), "bone": Castle._flat(Color("e8e0cc"))}))
	_colliders(parent)
	_lights(parent, reduced_motion)
	var exit := Door.make(EXIT_NAME, DOOR_W, 2.3, false)
	exit.verb = "离开"
	exit.to_area = "castle"
	exit.to_spawn = "barracks_door"
	exit.position = Vector3(-DOOR_W * 0.5, 0, D * 0.5 - 0.02)
	parent.add_child(exit)
	_person(parent, SERGEANT, [])
	for s in SOLDIERS:
		_person(parent, s, SOLDIER_LINES[str(s[0])])
	var sp: Array = SPAWNS.front
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(sp[1]))), sp[0])


static func _person(parent: Node3D, p: Array, lines: Array) -> void:
	if Chapter1.gone(str(p[0])):
		return                               # 阿尔里克拿了印戒：伊薇特带着兵营里她的人离堡了（4.8a）
	var n := Npc.make(str(p[1]), lines, Color(str(p[4])))
	n.name = "Npc_" + str(p[0])
	if lines.is_empty():
		n.dialogue_area = "barracks"
		n.dialogue_id = str(p[0])
	n.position = p[2]
	n.rotation.y = float(p[3])
	parent.add_child(n)


static func map_spec() -> Dictionary:
	var shapes := [
		{"k": "furniture", "rect": TABLE, "label": "长桌"},
		{"k": "furniture", "rect": RACK, "label": "兵器架"},
		{"k": "furniture", "rect": STOVE},
		{"k": "mark", "at": STOVE.get_center() + Vector2(-0.8, 0), "icon": "fire", "label": "炉子"},
	]
	for x: float in BUNKS:
		shapes.append({"k": "furniture", "rect": Rect2(x - 1.0, BUNK_Z - 0.45, 2.0, 0.9)})
	return {
		"bounds": Rect2(-W * 0.5, -D * 0.5, W, D),
		"shapes": shapes,
		"exits": [{"at": Vector2(0, D * 0.5), "dir": Vector2(0, 1), "to": "castle", "spawn": "barracks_door", "name": EXIT_NAME}],
	}


## 夯土地面、石墙、木梁顶；南墙两扇小窗和门
static func _room(kit: MeshKit) -> void:
	var hw := W * 0.5
	var hd := D * 0.5
	kit.box("stone", Vector3(0, -0.05, 0), Vector3(W, 0.1, D), Basis.IDENTITY, 0.5, 0.5)
	kit.box("timber", Vector3(0, H + 0.05, 0), Vector3(W, 0.1, D), Basis.IDENTITY, 0.4, 0.4, true)
	for x in [-5.0, -1.7, 1.7, 5.0]:
		kit.box("timber", Vector3(x, H - 0.15, 0), Vector3(0.3, 0.3, D), Basis.IDENTITY, 0.5, 0.4)
	kit.box("stone", Vector3(0, H * 0.5, -hd - WALL_T * 0.5), Vector3(W + WALL_T * 2.0, H, WALL_T), Basis.IDENTITY, 0.85, 0.5)
	for sx: float in [-1.0, 1.0]:
		kit.box("stone", Vector3(sx * (hw + WALL_T * 0.5), H * 0.5, 0), Vector3(WALL_T, H, D), Basis.IDENTITY, 0.85, 0.5)
	var zs := hd + WALL_T * 0.5
	var cuts := [[-DOOR_W * 0.5, DOOR_W * 0.5]]
	for wx: float in WINDOWS:
		cuts.append([wx - 0.45, wx + 0.45])
	cuts.sort_custom(func(a, b): return a[0] < b[0])
	var x0 := -hw - WALL_T
	for c in cuts:
		kit.box("stone", Vector3((x0 + float(c[0])) * 0.5, H * 0.5, zs), Vector3(float(c[0]) - x0, H, WALL_T), Basis.IDENTITY, 0.85, 0.5)
		x0 = c[1]
	kit.box("stone", Vector3((x0 + hw + WALL_T) * 0.5, H * 0.5, zs), Vector3(hw + WALL_T - x0, H, WALL_T), Basis.IDENTITY, 0.85, 0.5)
	for wx: float in WINDOWS:
		kit.box("stone", Vector3(wx, 0.6, zs), Vector3(0.9, 1.2, WALL_T), Basis.IDENTITY, 0.8, 0.5)
		kit.box("stone", Vector3(wx, (2.1 + H) * 0.5, zs), Vector3(0.9, H - 2.1, WALL_T), Basis.IDENTITY, 0.85, 0.6)
		kit.box("glass", Vector3(wx, 1.65, zs + 0.05), Vector3(0.9, 0.9, 0.04))
	kit.box("stone", Vector3(0, (2.3 + H) * 0.5, zs), Vector3(DOOR_W, H - 2.3, WALL_T), Basis.IDENTITY, 0.85, 0.6)
	kit.box("timber", Vector3(0, 2.38, zs - 0.1), Vector3(DOOR_W + 0.3, 0.14, 0.2))


## 上下铺（草褥、毯子）、长桌和长凳（骰子、木碗）、兵器架（长枪、盾）、炉子
static func _furniture(kit: MeshKit) -> void:
	for x: float in BUNKS:
		for c in [Vector2(x - 0.95, BUNK_Z - 0.4), Vector2(x + 0.95, BUNK_Z - 0.4), Vector2(x - 0.95, BUNK_Z + 0.4), Vector2(x + 0.95, BUNK_Z + 0.4)]:
			kit.box("timber", Vector3(c.x, 0.9, c.y), Vector3(0.1, 1.8, 0.1))
		for y: float in [0.35, 1.35]:
			kit.box("timber", Vector3(x, y, BUNK_Z), Vector3(2.0, 0.08, 0.9), Basis.IDENTITY, 0.9, 0.7)
			kit.box("straw", Vector3(x, y + 0.1, BUNK_Z), Vector3(1.9, 0.12, 0.82))
			kit.box("wool", Vector3(x + 0.3, y + 0.18, BUNK_Z), Vector3(1.1, 0.05, 0.84))
	var t := TABLE
	kit.box("timber", Vector3(t.get_center().x, 0.76, t.get_center().y), Vector3(t.size.x, 0.08, t.size.y), Basis.IDENTITY, 1.0, 0.8)
	for lx: float in [-2.2, 0.0, 2.2]:
		kit.box("timber", Vector3(lx, 0.36, t.get_center().y), Vector3(0.12, 0.72, 0.8), Basis.IDENTITY, 0.8, 0.5)
	for bz: float in [t.position.y - 0.35, t.end.y + 0.35]:
		kit.box("timber", Vector3(t.get_center().x, 0.44, bz), Vector3(t.size.x - 0.4, 0.06, 0.3), Basis.IDENTITY, 0.9, 0.7)
		for lx: float in [-2.0, 2.0]:
			kit.box("timber", Vector3(lx, 0.2, bz), Vector3(0.08, 0.4, 0.24))
	for d in [Vector3(0.8, 0.83, -0.45), Vector3(0.95, 0.83, -0.38)]:
		kit.box("bone", d, Vector3(0.06, 0.06, 0.06))
	for bx: float in [-1.6, -0.6, 1.8]:
		kit.cylinder("timber", Vector3(bx, 0.8, -0.2), Vector3(bx, 0.88, -0.2), 0.1, 0.08, 8, 0.8)
	var r := RACK
	kit.box("timber", Vector3(r.get_center().x, 1.0, r.get_center().y), Vector3(0.1, 0.08, r.size.y))
	kit.box("timber", Vector3(r.get_center().x, 0.15, r.get_center().y), Vector3(r.size.x, 0.08, r.size.y))
	for i in 6:
		var z := r.position.y + 0.2 + i * 0.4
		kit.cylinder("timber", Vector3(r.get_center().x, 0.15, z), Vector3(r.get_center().x - 0.05, 2.9, z), 0.025, 0.02, 5, 0.9)
		kit.box("iron", Vector3(r.get_center().x - 0.05, 3.0, z), Vector3(0.03, 0.22, 0.06))
	kit.cylinder("timber", Vector3(-W * 0.5 + 0.06, 1.4, 1.6), Vector3(-W * 0.5 + 0.12, 1.4, 1.6), 0.38, 0.38, 10, 0.8)     # 墙上挂的圆盾
	kit.cylinder("iron", Vector3(-W * 0.5 + 0.12, 1.4, 1.6), Vector3(-W * 0.5 + 0.16, 1.4, 1.6), 0.08, 0.08, 8, 0.9)
	var s := STOVE
	kit.box("stone", Vector3(s.get_center().x, 0.6, s.get_center().y), Vector3(s.size.x, 1.2, s.size.y), Basis.IDENTITY, 0.85, 0.6)
	kit.box("soot", Vector3(s.position.x - 0.01, 0.5, s.get_center().y), Vector3(0.02, 0.5, 0.8))
	kit.box("ember", Vector3(s.position.x + 0.15, 0.32, s.get_center().y), Vector3(0.3, 0.06, 0.7))
	kit.box("stone", Vector3(s.get_center().x + 0.1, (1.2 + H) * 0.5, s.get_center().y), Vector3(0.4, H - 1.2, 0.5), Basis.IDENTITY, 0.8, 0.6)


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
	for x: float in BUNKS:
		Castle._solid(parent, Vector3(x, 0.9, BUNK_Z), Vector3(2.0, 1.8, 0.9))
	Castle._solid(parent, Vector3(TABLE.get_center().x, 0.45, TABLE.get_center().y), Vector3(TABLE.size.x, 0.9, TABLE.size.y + 1.0))    # 桌子连两条长凳
	Castle._solid(parent, Vector3(RACK.get_center().x, 1.5, RACK.get_center().y), Vector3(RACK.size.x, 3.0, RACK.size.y))
	Castle._solid(parent, Vector3(STOVE.get_center().x, 0.6, STOVE.get_center().y), Vector3(STOVE.size.x, 1.2, STOVE.size.y))


## 光：炉火（闪烁）、长桌上方一盏油灯。一共 2 盏点光源
static func _lights(parent: Node3D, reduced_motion: bool) -> void:
	var fire := Tavern.FireLight.new()
	fire.name = "Stove"
	fire.light_color = Color("ff8a3a")
	fire.base = 2.0
	fire.omni_range = 7.0
	fire.position = Vector3(STOVE.position.x - 0.5, 0.8, STOVE.get_center().y)
	fire.flicker = not reduced_motion
	fire.add_to_group("light_source")
	fire.set_meta("radius", 3.0)
	parent.add_child(fire)
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.light_color = Color("ffb060")
	lamp.light_energy = 1.6
	lamp.omni_range = 9.0
	lamp.position = Vector3(-1.0, 2.6, -0.3)
	parent.add_child(lamp)
