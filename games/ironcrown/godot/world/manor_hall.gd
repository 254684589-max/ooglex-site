class_name ManorHall
extends RefCounted
## 洛蒙德庄园的大厅（路线图 6.3a；STORY.md 6.2「大厅里炉火很旺，桌上摆满吃的——和对岸是两个世界」）：原创布局。
## 主楼底层，屋里 14 × 9 米、5 米高：石墙、石板地上铺着长毯、木梁顶。
##   北墙一座巨大的石壁炉（火烧得正旺，屋里热得要脱斗篷），炉罩上挂着绿底金麦束的旗；中间一张长桌，桌上摆满了——整只烤的、一摞摞面包、
##   几碗苹果、奶酪、酒壶和杯子，吃剩一半的也没人收；东头一层木台上是女家主的高桌和高背椅（伊莎贝拉站在那儿，6.3d）；
##   西墙一幅挂毯（金色的麦田），墙上四支火把、桌上一排蜡烛；南墙两扇窗、一扇门。
## 室内的光不跟时段走；窗玻璃按时段换颜色（Inn.glass）。坐标：原点在屋里地面中心，北 = -Z；出口门在南墙（z = +4.5），出去站在主楼门外（plain 的出生点 manor_door）。

const W := 14.0
const D := 9.0
const H := 5.0
const WALL_T := 0.4
const DOOR_X := -4.0
const DOOR_W := 1.3
const EXIT_NAME := "回到院子里"
const WINDOWS := [-0.5, 3.8]
const WIN_W := 0.9
const WIN_Y := 2.4
const WIN_H := 1.6
const HEARTH := Rect2(-2.0, -4.5, 4.0, 1.3)
const TABLE := Rect2(-4.6, -0.8, 7.4, 1.4)
const DAIS := Rect2(4.2, -3.6, 2.6, 6.0)
const SPAWNS := {
	"front": [Vector3(DOOR_X, 0, 3.7), 0.0],
}
const VIEW_NAMES := ["进门看大厅", "长桌上的吃的", "壁炉和旗", "东头的高桌"]
const VIEWS := [
	[Vector3(DOOR_X, 0, 3.7), 20.0, -4.0],
	[Vector3(-3.0, 0, 2.0), -25.0, -22.0],
	[Vector3(0.0, 0, 1.6), 0.0, 6.0],
	[Vector3(-1.0, 0, 1.4), -90.0, -2.0],
]


static func build(parent: Node3D, reduced_motion := false) -> Transform3D:
	var kit := MeshKit.new()
	_room(kit)
	_hearth(kit)
	_tables(kit)
	var mi := kit.build({"stone": Look.mat("stone"), "floor": Look.mat("street"), "timber": Look.mat("timber"), "glass": Inn.glass(GameState.daypart),
		"ember": Inn._unshaded(Color("ff7a28")), "soot": Inn._unshaded(Color("0e0b09")), "iron": Inn._iron_mat(), "bread": _food("b08048"), "roast": _food("6a3a1e"),
		"apple": _food("9a3a26"), "cheese": _food("d8b860"), "wine": _food("4a1220"), "pewter": _pewter(), "cloth": _food("9a9282"), "flame": Inn._unshaded(Color("ffb050"))})
	mi.name = "ManorHall"
	parent.add_child(mi)
	_decor(parent, reduced_motion)
	_colliders(parent)
	_lights(parent, reduced_motion)
	people(parent)
	var exit := Door.make(EXIT_NAME, DOOR_W, 2.4, false)
	exit.verb = "离开"
	exit.to_area = "plain"
	exit.to_spawn = "manor_door"
	exit.position = Vector3(DOOR_X - DOOR_W * 0.5, 0, D * 0.5 - 0.02)
	parent.add_child(exit)
	var s: Array = SPAWNS.front
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


## 大厅里的人（6.3d，主线第 3 步）：女家主伊莎贝拉站在东头木台上、高桌和高背椅之间（手边那张没写完的信）；管家塞缪尔捧着账站在门边
const ISABELLA := [Vector3(5.95, 0.3, -0.75), 90.0]
const SAMUEL := [Vector3(-2.6, 0.0, 3.4), 0.0]


static func people(parent: Node3D) -> void:
	for it: Array in [["isabella", "伊莎贝拉·洛蒙德", ISABELLA, "3e5442"], ["samuel", "管家塞缪尔", SAMUEL, "4a4238"]]:
		var n := Npc.make(str(it[1]), [], Color(str(it[3])))
		n.name = "Npc_" + str(it[0])
		n.dialogue_area = "plain"
		n.dialogue_id = str(it[0])
		n.position = (it[2] as Array)[0]
		n.rotation.y = deg_to_rad(float((it[2] as Array)[1]))
		parent.add_child(n)


static func map_spec() -> Dictionary:
	return {
		"bounds": Rect2(-W * 0.5, -D * 0.5, W, D),
		"shapes": [
			{"k": "furniture", "rect": HEARTH},
			{"k": "mark", "at": HEARTH.get_center() + Vector2(0, 0.8), "icon": "fire", "label": "壁炉"},
			{"k": "furniture", "rect": TABLE, "label": "长桌"},
			{"k": "furniture", "rect": DAIS, "label": "高桌"},
		],
		"exits": [{"at": Vector2(DOOR_X, D * 0.5), "dir": Vector2(0, 1), "to": "plain", "spawn": "manor_door", "name": EXIT_NAME}],
	}


static func _room(kit: MeshKit) -> void:
	var hw := W * 0.5
	var hd := D * 0.5
	kit.box("floor", Vector3(0, -0.05, 0), Vector3(W, 0.1, D), Basis.IDENTITY, 0.8, 0.8)
	kit.box("timber", Vector3(0, H + 0.05, 0), Vector3(W, 0.1, D), Basis.IDENTITY, 0.4, 0.4, true)
	for x in [-5.0, -2.5, 0.0, 2.5, 5.0]:
		kit.box("timber", Vector3(x, H - 0.2, 0), Vector3(0.34, 0.4, D), Basis.IDENTITY, 0.55, 0.45)
	kit.box("stone", Vector3(0, H * 0.5, -hd - WALL_T * 0.5), Vector3(W + WALL_T * 2, H, WALL_T), Basis.IDENTITY, 0.8, 0.55)
	kit.box("stone", Vector3(hw + WALL_T * 0.5, H * 0.5, 0), Vector3(WALL_T, H, D), Basis.IDENTITY, 0.8, 0.55)
	kit.box("stone", Vector3(-hw - WALL_T * 0.5, H * 0.5, 0), Vector3(WALL_T, H, D), Basis.IDENTITY, 0.8, 0.55)
	var zs := hd + WALL_T * 0.5
	var cuts := [[DOOR_X - DOOR_W * 0.5, DOOR_X + DOOR_W * 0.5]]
	for wx: float in WINDOWS:
		cuts.append([wx - WIN_W * 0.5, wx + WIN_W * 0.5])
	cuts.sort_custom(func(a, b): return a[0] < b[0])
	var x0 := -hw - WALL_T
	for c in cuts:
		var a: float = c[0]
		if a > x0:
			kit.box("stone", Vector3((x0 + a) * 0.5, H * 0.5, zs), Vector3(a - x0, H, WALL_T), Basis.IDENTITY, 0.8, 0.55)
		x0 = c[1]
	kit.box("stone", Vector3((x0 + hw + WALL_T) * 0.5, H * 0.5, zs), Vector3(hw + WALL_T - x0, H, WALL_T), Basis.IDENTITY, 0.8, 0.55)
	var sill := WIN_Y - WIN_H * 0.5
	var head := WIN_Y + WIN_H * 0.5
	for wx: float in WINDOWS:
		kit.box("stone", Vector3(wx, sill * 0.5, zs), Vector3(WIN_W, sill, WALL_T), Basis.IDENTITY, 0.75, 0.55)
		kit.box("stone", Vector3(wx, (head + H) * 0.5, zs), Vector3(WIN_W, H - head, WALL_T), Basis.IDENTITY, 0.8, 0.65)
		kit.box("glass", Vector3(wx, WIN_Y, zs + 0.08), Vector3(WIN_W, WIN_H, 0.04))
		kit.box("iron", Vector3(wx, WIN_Y, zs - 0.1), Vector3(0.04, WIN_H, 0.04))
		kit.box("iron", Vector3(wx, WIN_Y + 0.2, zs - 0.1), Vector3(WIN_W, 0.04, 0.04))
	kit.box("stone", Vector3(DOOR_X, (2.4 + H) * 0.5, zs), Vector3(DOOR_W, H - 2.4, WALL_T), Basis.IDENTITY, 0.8, 0.7)
	kit.box("timber", Vector3(DOOR_X, 2.48, zs - 0.12), Vector3(DOOR_W + 0.4, 0.18, 0.18))


## 北墙的大壁炉：炉膛宽 2.6 米、柴火堆得高、炉罩一直通到顶
static func _hearth(kit: MeshKit) -> void:
	var c := Vector3(HEARTH.get_center().x, 0, HEARTH.get_center().y)
	kit.box("stone", c + Vector3(0, 0.15, 0.15), Vector3(4.0, 0.3, 1.3), Basis.IDENTITY, 0.85, 0.6)
	for s in [-1.0, 1.0]:
		kit.box("stone", c + Vector3(s * 1.65, 1.1, -0.05), Vector3(0.7, 1.9, 0.9), Basis.IDENTITY, 0.85, 0.6)
	kit.box("stone", c + Vector3(0, 2.3, -0.05), Vector3(4.2, 0.5, 1.0), Basis.IDENTITY, 0.75, 0.6)
	kit.box("stone", c + Vector3(0, (2.55 + H) * 0.5, -0.25), Vector3(3.4, H - 2.55, 0.7), Basis.IDENTITY, 0.8, 0.7)
	kit.box("soot", c + Vector3(0, 1.1, -0.48), Vector3(2.6, 1.9, 0.02))
	kit.box("ember", c + Vector3(0, 0.34, -0.05), Vector3(1.8, 0.06, 0.6))
	for i in 7:
		var a := -0.9 + i * 0.3
		kit.cylinder("timber", c + Vector3(a - 0.2, 0.38, 0.2), c + Vector3(a + 0.2, 0.5 + (i % 2) * 0.12, -0.3), 0.08, 0.08, 5, 0.5)
	kit.cylinder("iron", c + Vector3(-1.2, 0.3, 0.55), c + Vector3(-1.2, 1.3, 0.55), 0.03, 0.03, 4)                    # 火钳架
	for i in 6:                                                                                                          # 火舌（自发光，泛光里一团暖光）
		var fx := -0.75 + i * 0.3
		var fh := 0.45 + 0.35 * absf(sin(i * 1.7))
		kit.box("flame", c + Vector3(fx, 0.55 + fh * 0.5, -0.1 + 0.08 * (i % 2)), Vector3(0.12, fh, 0.03), Basis(Vector3.BACK, (i - 2.5) * 0.08))


## 长桌（桌布、整只烤的、一摞摞面包、几碗苹果、奶酪、酒壶和杯子）、两条长凳；东头木台上的高桌和高背椅
static func _tables(kit: MeshKit) -> void:
	var t := TABLE
	var c := Vector3(t.get_center().x, 0, t.get_center().y)
	kit.box("timber", c + Vector3(0, 0.78, 0), Vector3(t.size.x, 0.1, t.size.y), Basis.IDENTITY, 1.0, 0.8)
	kit.box("cloth", c + Vector3(0, 0.84, 0), Vector3(t.size.x - 0.4, 0.02, t.size.y + 0.1), Basis.IDENTITY, 1.0, 0.9)
	for lx in [-3.2, 0.0, 3.2]:
		kit.box("timber", c + Vector3(lx, 0.38, 0), Vector3(0.14, 0.76, 1.1), Basis.IDENTITY, 0.8, 0.5)
	for bz in [-1.05, 1.05]:
		kit.box("timber", c + Vector3(0, 0.45, bz), Vector3(t.size.x - 0.3, 0.07, 0.34), Basis.IDENTITY, 0.9, 0.7)
		for lx in [-3.2, 0.0, 3.2]:
			kit.box("timber", c + Vector3(lx, 0.22, bz), Vector3(0.1, 0.44, 0.28), Basis.IDENTITY, 0.8, 0.5)
	var top := 0.86
	kit.cylinder("pewter", c + Vector3(-0.6, top, 0), c + Vector3(-0.6, top + 0.03, 0), 0.55, 0.55, 12)                   # 大盘子上整只烤的
	kit.cylinder("roast", c + Vector3(-1.05, top + 0.2, 0), c + Vector3(-0.15, top + 0.2, 0), 0.2, 0.17, 10, 0.9)
	kit.cylinder("roast", c + Vector3(-1.0, top + 0.15, 0.12), c + Vector3(-1.25, top + 0.06, 0.28), 0.05, 0.03, 5)
	for k in 3:                                                                                                          # 面包一摞摞
		for j in 3:
			kit.cylinder("bread", c + Vector3(1.3 + k * 0.38, top + j * 0.11, -0.25 + (k % 2) * 0.1), c + Vector3(1.3 + k * 0.38, top + 0.1 + j * 0.11, -0.25 + (k % 2) * 0.1), 0.15, 0.12, 9, 0.95)
	for bx in [-2.6, 2.6]:                                                                                               # 两碗苹果
		kit.cylinder("timber", c + Vector3(bx, top, 0.2), c + Vector3(bx, top + 0.12, 0.2), 0.16, 0.24, 10, 0.8)
		for k in 5:
			var a := TAU * k / 5.0
			kit.cylinder("apple", c + Vector3(bx + cos(a) * 0.1, top + 0.13, 0.2 + sin(a) * 0.1), c + Vector3(bx + cos(a) * 0.1, top + 0.21, 0.2 + sin(a) * 0.1), 0.05, 0.045, 7, 0.9)
	kit.cylinder("cheese", c + Vector3(0.6, top, 0.3), c + Vector3(0.6, top + 0.14, 0.3), 0.22, 0.22, 10, 0.9)
	for k in 6:                                                                                                          # 酒壶和杯子
		var x := -3.2 + k * 1.25
		kit.cylinder("pewter", c + Vector3(x, top, -0.45), c + Vector3(x, top + 0.14, -0.45), 0.045, 0.04, 7)
		kit.cylinder("wine", c + Vector3(x, top + 0.13, -0.45), c + Vector3(x, top + 0.135, -0.45), 0.04, 0.04, 7)
	for x in [-1.8, 2.0]:
		kit.cylinder("pewter", c + Vector3(x, top, 0.45), c + Vector3(x, top + 0.32, 0.45), 0.09, 0.06, 8)
	var d := Vector3(DAIS.get_center().x, 0, DAIS.get_center().y)                                                       # 东头的木台、高桌、高背椅
	kit.box("timber", d + Vector3(0, 0.15, 0), Vector3(DAIS.size.x, 0.3, DAIS.size.y), Basis.IDENTITY, 0.85, 0.6)
	kit.box("timber", d + Vector3(-0.3, 1.08, 0), Vector3(0.9, 0.08, 3.2), Basis.IDENTITY, 1.0, 0.8)
	kit.box("cloth", d + Vector3(-0.3, 1.13, 0), Vector3(1.0, 0.02, 3.0), Basis.IDENTITY, 1.0, 0.9)
	for lz in [-1.4, 1.4]:
		kit.box("timber", d + Vector3(-0.3, 0.7, lz), Vector3(0.7, 0.8, 0.12), Basis.IDENTITY, 0.8, 0.5)
	kit.box("timber", d + Vector3(0.6, 0.78, 0), Vector3(0.6, 0.08, 0.7), Basis.IDENTITY, 0.9, 0.7)                        # 高背椅
	kit.box("timber", d + Vector3(0.9, 1.6, 0), Vector3(0.1, 1.7, 0.75), Basis.IDENTITY, 0.85, 0.6)
	kit.cylinder("pewter", d + Vector3(-0.3, 1.14, -0.4), d + Vector3(-0.3, 1.32, -0.4), 0.05, 0.04, 7)
	kit.box("cloth", d + Vector3(-0.35, 1.145, 0.5), Vector3(0.4, 0.01, 0.3), Basis(Vector3.UP, 0.2))                      # 高桌上一张没写完的信


static func _decor(parent: Node3D, reduced_motion := false) -> void:
	var d := Decor.new()
	d.banner(Vector3(HEARTH.get_center().x, H - 0.3, HEARTH.get_center().y + 0.62), Vector3.BACK, 1.6, 2.0, PlainManor.FIELD, PlainManor.CHARGE, "wheat")
	d.banner(Vector3(W * 0.5 - 0.02, H - 0.4, 0.0), Vector3.LEFT, 1.3, 2.2, PlainManor.FIELD, PlainManor.CHARGE, "wheat")
	d.tapestry(Vector3(-W * 0.5 + 0.03, 2.6, 0.0), Vector3.RIGHT, 3.2, 2.0, Color("6a5a2a"), [Color("c8a440"), Color("a08030"), Color("2e5a32")])
	d.rug(Rect2(-5.0, -1.9, 9.6, 3.6), 0.005, Color("5a2a22"), Color("c8a440"))
	for x in [-3.6, -1.2, 1.2]:
		d.candles(Vector3(x + TABLE.get_center().x * 0.0, 0.86, TABLE.get_center().y + 0.05), 3)
	d.candle_stand(Vector3(DAIS.position.x + 0.2, 0.3, DAIS.position.y + 0.4))
	d.candle_stand(Vector3(DAIS.position.x + 0.2, 0.3, DAIS.end.y - 0.4))
	for p in [[Vector3(-W * 0.5 + 0.02, 2.4, -2.6), Vector3.RIGHT], [Vector3(-W * 0.5 + 0.02, 2.4, 2.6), Vector3.RIGHT], [Vector3(W * 0.5 - 0.02, 2.4, -3.4), Vector3.LEFT], [Vector3(0.0, 2.4, -D * 0.5 + 0.02), Vector3.BACK]]:
		d.sconce(p[0], p[1], false)
	d.chest(Vector3(-5.8, 0, -3.6), 0.0, Vector3(1.1, 0.6, 0.6))
	d.barrel(Vector3(-6.2, 0, 3.6))
	d.barrel(Vector3(-5.5, 0, 3.8))
	d.build(parent, "Decor", not reduced_motion)


static func _colliders(parent: Node3D) -> void:
	var hw := W * 0.5
	var hd := D * 0.5
	Inn._solid(parent, Vector3(0, -0.1, 0), Vector3(W + 1, 0.2, D + 1))
	Inn._solid(parent, Vector3(0, H + 0.1, 0), Vector3(W + 1, 0.2, D + 1))
	Inn._solid(parent, Vector3(0, H * 0.5, -hd - WALL_T * 0.5), Vector3(W + 1, H, WALL_T))
	Inn._solid(parent, Vector3(hw + WALL_T * 0.5, H * 0.5, 0), Vector3(WALL_T, H, D + 1))
	Inn._solid(parent, Vector3(-hw - WALL_T * 0.5, H * 0.5, 0), Vector3(WALL_T, H, D + 1))
	var zs := hd + WALL_T * 0.5
	var dl := DOOR_X - DOOR_W * 0.5
	var dr := DOOR_X + DOOR_W * 0.5
	Inn._solid(parent, Vector3((-hw + dl) * 0.5, H * 0.5, zs), Vector3(dl + hw, H, WALL_T))
	Inn._solid(parent, Vector3((dr + hw) * 0.5, H * 0.5, zs), Vector3(hw - dr, H, WALL_T))
	Inn._solid(parent, Vector3(DOOR_X, H * 0.5, zs + 0.15), Vector3(DOOR_W, H, 0.1))
	Inn._solid(parent, Vector3(HEARTH.get_center().x, 1.2, HEARTH.get_center().y), Vector3(HEARTH.size.x + 0.2, 2.4, HEARTH.size.y + 0.2))
	Inn._solid(parent, Vector3(TABLE.get_center().x, 0.45, TABLE.get_center().y), Vector3(TABLE.size.x, 0.9, TABLE.size.y + 2.4))
	Inn._solid(parent, Vector3(DAIS.get_center().x + 0.2, 0.6, DAIS.get_center().y), Vector3(DAIS.size.x - 0.4, 1.2, 3.4))


## 光：壁炉（大、暖、闪烁）、长桌上方两盏吊灯、东头高桌一盏
static func _lights(parent: Node3D, reduced_motion: bool) -> void:
	var fire := Tavern.FireLight.new()
	fire.name = "Fire"
	fire.light_color = Color("ff8a3a")
	fire.base = 4.8
	fire.omni_range = 13.0
	fire.omni_attenuation = 1.0
	fire.position = Vector3(HEARTH.get_center().x, 1.1, HEARTH.get_center().y + 1.2)
	fire.flicker = not reduced_motion
	fire.add_to_group("light_source")
	fire.set_meta("radius", 6.0)
	parent.add_child(fire)
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.8, 1.4)
	var hm := Look.halo(Color("ff8a3a"), 0.5).duplicate() as StandardMaterial3D
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = hm
	halo.mesh = q
	halo.position = Vector3(HEARTH.get_center().x, 0.8, HEARTH.get_center().y + 0.5)
	parent.add_child(halo)
	for x in [-3.0, 1.0]:
		var lamp := OmniLight3D.new()
		lamp.light_color = Look.LAMP_COLOR
		lamp.light_energy = 1.8
		lamp.omni_range = 8.0
		lamp.position = Vector3(x, 3.4, TABLE.get_center().y)
		parent.add_child(lamp)
	var high := OmniLight3D.new()
	high.light_color = Look.LAMP_COLOR
	high.light_energy = 1.4
	high.omni_range = 6.0
	high.position = Vector3(DAIS.get_center().x, 2.6, DAIS.get_center().y)
	parent.add_child(high)


static func _food(hex: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = 0.85
	m.vertex_color_use_as_albedo = true
	return m


static func _pewter() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("8a8a86")
	m.metallic = 0.6
	m.roughness = 0.45
	return m
