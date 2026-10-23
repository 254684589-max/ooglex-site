class_name Counting
extends RefCounted
## 黑鹭堡东边的账房（路线图 4.7a；STORY.md 4.7「皮毛税账册：账房上锁：找赫尔曼要钥匙（声望或口才）、或趁夜里撬窗（被看见就闹大）」）：原创布局。
## 5.4 × 4.8 米、3 米高的石屋：北墙下一张写字台（皮毛税账册摊在上面，一支蜡烛），东墙一排账架，西北角一只铁皮箱，西墙一扇小窗（从外面撬开的就是它）。
## 有钥匙的从庭院的门进来（front）；撬窗的从窗下爬进来（window）。里面的门从里面推得开（出去回到庭院的账房门前）。
## 坐标：原点在屋子地面中心，北 = -Z；门在南墙（z = +2.4），窗在西墙（x = -2.7）。

const W := 5.4
const D := 4.8
const H := 3.0
const WALL_T := 0.5
const DOOR_W := 1.1
const EXIT_NAME := "回到庭院"
const DESK := Rect2(-1.0, -2.3, 2.0, 0.8)          # 北墙下的写字台
const SHELF := Rect2(2.2, -2.2, 0.45, 3.6)         # 东墙的账架
const CHEST := Rect2(-2.55, -2.25, 0.9, 0.55)      # 西北角的铁皮箱
const WINDOW_Z := -0.6                             # 西墙小窗的中心
const LEDGER := Vector3(0.0, 0.8, -1.9)            # 账册（写字台上）
const SPAWNS := {
	"front": [Vector3(0, 0, 1.6), 0.0],
	"window": [Vector3(-2.0, 0, WINDOW_Z), -90.0],    # 从窗下爬进来：面朝东
}
const VIEW_NAMES := ["进门看账房", "写字台前（账册）", "窗下", "门内对着出口"]
const VIEWS := [
	[Vector3(0, 0, 1.6), 0.0, -6.0],
	[Vector3(0, 0, 0.2), 0.0, -22.0],
	[Vector3(-2.0, 0, WINDOW_Z), -90.0, -6.0],
	[Vector3(0, 0, 1.5), 180.0, -6.0],
]


static func build(parent: Node3D, _reduced_motion := false) -> Transform3D:
	var kit := MeshKit.new()
	_room(kit)
	_furniture(kit)
	parent.add_child(kit.build({"stone": Look.mat("castle"), "timber": Look.mat("timber"), "glass": Inn.glass(GameState.daypart),
		"paper": Castle._cloth(Color("d8ccae")), "leather": Castle._cloth(Color("5a3a26")), "iron": Castle._flat(Color("3a3a3e")),
		"wax": Castle._flat(Color("efe4c8"), true)}))
	_decor(parent)
	_colliders(parent)
	_lights(parent)
	var exit := Door.make(EXIT_NAME, DOOR_W, 2.2, false)
	exit.verb = "离开"
	exit.to_area = "castle"
	exit.to_spawn = "counting_door"
	exit.position = Vector3(-DOOR_W * 0.5, 0, D * 0.5 - 0.02)
	parent.add_child(exit)
	if not GameState.has_item("fur_ledger") and not GameState.has_flag("ch1_ledger"):
		var p := Pickup.make("fur_ledger", "皮毛税账册", Color("5a3a26"), Vector3(0.34, 0.07, 0.46))
		p.pickup_id = "counting_fur_ledger"
		p.position = LEDGER
		parent.add_child(p)
	var s: Array = SPAWNS.front
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


static func map_spec() -> Dictionary:
	return {
		"bounds": Rect2(-W * 0.5, -D * 0.5, W, D),
		"shapes": [
			{"k": "furniture", "rect": DESK, "label": "写字台"},
			{"k": "furniture", "rect": SHELF, "label": "账架"},
			{"k": "furniture", "rect": CHEST},
		],
		"exits": [{"at": Vector2(0, D * 0.5), "dir": Vector2(0, 1), "to": "castle", "spawn": "counting_door", "name": EXIT_NAME}],
	}


## 石地面、石墙、木梁顶；西墙一扇小窗，南墙正中的门
static func _room(kit: MeshKit) -> void:
	var hw := W * 0.5
	var hd := D * 0.5
	kit.box("stone", Vector3(0, -0.05, 0), Vector3(W, 0.1, D), Basis.IDENTITY, 0.6, 0.6)
	kit.box("timber", Vector3(0, H + 0.05, 0), Vector3(W, 0.1, D), Basis.IDENTITY, 0.4, 0.4, true)
	for z in [-1.0, 1.0]:
		kit.box("timber", Vector3(0, H - 0.15, z), Vector3(W, 0.3, 0.3), Basis.IDENTITY, 0.5, 0.4)
	kit.box("stone", Vector3(0, H * 0.5, -hd - WALL_T * 0.5), Vector3(W + WALL_T * 2.0, H, WALL_T), Basis.IDENTITY, 0.85, 0.5)
	kit.box("stone", Vector3(hw + WALL_T * 0.5, H * 0.5, 0), Vector3(WALL_T, H, D), Basis.IDENTITY, 0.85, 0.5)
	var xw := -hw - WALL_T * 0.5         # 西墙：小窗（0.6 宽、0.8 高，窗台 1.1 米）
	kit.box("stone", Vector3(xw, H * 0.5, (-hd + WINDOW_Z - 0.3) * 0.5), Vector3(WALL_T, H, WINDOW_Z - 0.3 + hd), Basis.IDENTITY, 0.85, 0.5)
	kit.box("stone", Vector3(xw, H * 0.5, (WINDOW_Z + 0.3 + hd) * 0.5), Vector3(WALL_T, H, hd - WINDOW_Z - 0.3), Basis.IDENTITY, 0.85, 0.5)
	kit.box("stone", Vector3(xw, 0.55, WINDOW_Z), Vector3(WALL_T, 1.1, 0.6), Basis.IDENTITY, 0.8, 0.5)
	kit.box("stone", Vector3(xw, (1.9 + H) * 0.5, WINDOW_Z), Vector3(WALL_T, H - 1.9, 0.6), Basis.IDENTITY, 0.8, 0.5)
	kit.box("glass", Vector3(xw - 0.05, 1.5, WINDOW_Z), Vector3(0.04, 0.8, 0.6))
	var zs := hd + WALL_T * 0.5
	for sx: float in [-1.0, 1.0]:
		kit.box("stone", Vector3(sx * (DOOR_W * 0.5 + hw + WALL_T) * 0.5, H * 0.5, zs), Vector3(hw + WALL_T - DOOR_W * 0.5, H, WALL_T), Basis.IDENTITY, 0.85, 0.5)
	kit.box("stone", Vector3(0, (2.2 + H) * 0.5, zs), Vector3(DOOR_W, H - 2.2, WALL_T), Basis.IDENTITY, 0.85, 0.6)
	kit.box("timber", Vector3(0, 2.28, zs - 0.1), Vector3(DOOR_W + 0.3, 0.14, 0.2))


## 写字台（墨水瓶、一摞账、蜡烛）、方凳、账架（一格格的账簿）、铁皮箱
static func _furniture(kit: MeshKit) -> void:
	var d := DESK
	kit.box("timber", Vector3(d.get_center().x, 0.74, d.get_center().y), Vector3(d.size.x, 0.06, d.size.y), Basis.IDENTITY, 0.9, 0.7)
	for c in [Vector2(d.position.x + 0.06, d.position.y + 0.06), Vector2(d.end.x - 0.06, d.position.y + 0.06), Vector2(d.position.x + 0.06, d.end.y - 0.06), Vector2(d.end.x - 0.06, d.end.y - 0.06)]:
		kit.box("timber", Vector3(c.x, 0.36, c.y), Vector3(0.07, 0.72, 0.07))
	kit.box("leather", Vector3(-0.7, 0.85, -2.05), Vector3(0.3, 0.16, 0.4))             # 一摞旧账
	kit.box("paper", Vector3(0.55, 0.78, -1.85), Vector3(0.3, 0.01, 0.22), Basis(Vector3.UP, 0.3))
	kit.cylinder("iron", Vector3(0.75, 0.77, -2.1), Vector3(0.75, 0.84, -2.1), 0.04, 0.03, 6, 0.8)        # 墨水瓶
	kit.cylinder("wax", Vector3(-0.4, 0.77, -2.15), Vector3(-0.4, 0.95, -2.15), 0.025, 0.025, 6, 1.0)     # 蜡烛
	kit.box("timber", Vector3(0.75, 0.5, -1.2), Vector3(0.4, 0.05, 0.36))               # 方凳（推到写字台东头，不挡写字台上的账册，截图发现）
	for c in [Vector2(0.58, -1.35), Vector2(0.92, -1.35), Vector2(0.58, -1.05), Vector2(0.92, -1.05)]:
		kit.box("timber", Vector3(c.x, 0.25, c.y), Vector3(0.05, 0.5, 0.05))
	var s := SHELF
	for y: float in [0.05, 0.6, 1.15, 1.7, 2.25]:
		kit.box("timber", Vector3(s.get_center().x, y, s.get_center().y), Vector3(s.size.x, 0.05, s.size.y), Basis.IDENTITY, 0.9, 0.7)
	for i in 4:
		for j in 7:
			var z := s.position.y + 0.3 + j * 0.48
			var hh := 0.32 + 0.08 * float((i + j) % 3)
			kit.box("leather" if (i + j) % 2 == 0 else "paper", Vector3(s.get_center().x, 0.1 + i * 0.55 + hh * 0.5, z), Vector3(0.32, hh, 0.36))
	kit.box("timber", Vector3(s.get_center().x + 0.2, 1.2, s.get_center().y), Vector3(0.05, 2.4, s.size.y))
	var c := CHEST
	kit.box("timber", Vector3(c.get_center().x, 0.28, c.get_center().y), Vector3(c.size.x, 0.56, c.size.y), Basis.IDENTITY, 0.9, 0.6)
	for x: float in [c.position.x + 0.12, c.end.x - 0.12]:
		kit.box("iron", Vector3(x, 0.28, c.get_center().y), Vector3(0.05, 0.58, c.size.y + 0.02))


## 陈设（2026-10-23 美化，Decor）：写字台上方一面黑鹭小旗、桌上几摞钱币和一簇蜡烛、门边的木桶和麻袋、地上一块旧地毯
static func _decor(parent: Node3D) -> void:
	var d := Decor.new()
	d.banner(Vector3(0, 2.75, -D * 0.5), Vector3.BACK, 0.8, 1.3, Color("d8d2c2"), Color("1a1a1c"), "heron")
	d.candles(Vector3(0.55, 0.77, -2.05), 2, true)
	d.rug(Rect2(-1.0, -1.2, 2.0, 1.6), 0.0, Color("3a2e2a"), Color("6a5a3a"))
	d.barrel(Vector3(-2.2, 0, 1.9), 0.7, 0.26)
	d.sack(Vector3(-1.6, 0, 2.0), 0.6)
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
	Castle._solid(parent, Vector3(DESK.get_center().x, 0.4, DESK.get_center().y), Vector3(DESK.size.x, 0.8, DESK.size.y))
	Castle._solid(parent, Vector3(SHELF.get_center().x, 1.2, SHELF.get_center().y), Vector3(SHELF.size.x, 2.4, SHELF.size.y))
	Castle._solid(parent, Vector3(CHEST.get_center().x, 0.3, CHEST.get_center().y), Vector3(CHEST.size.x, 0.6, CHEST.size.y))


## 光：写字台上的蜡烛、窗口透进来的一点光。一共 2 盏点光源
static func _lights(parent: Node3D) -> void:
	var candle := OmniLight3D.new()
	candle.name = "Candle"
	candle.light_color = Color("ffc070")
	candle.light_energy = 1.3
	candle.omni_range = 5.0
	candle.position = Vector3(-0.4, 1.2, -1.9)
	parent.add_child(candle)
	var win := OmniLight3D.new()
	win.name = "WindowGlow"
	win.light_color = Color("9aa6b4")
	win.light_energy = 0.6
	win.omni_range = 3.5
	win.position = Vector3(-2.2, 1.6, WINDOW_Z)
	parent.add_child(win)
