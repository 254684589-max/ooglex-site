class_name Waystation
extends RefCounted
## 厄尔德家驿站的大堂（路线图 5.2a；STORY.md 5.2「驿站大堂：火塘、长桌、挂着的烽燧旗」）：原创布局。
## 驿站是羊脊村唯一的两层石楼（外面 11 × 8 米，HighlandLayout.WAYSTATION），底层大堂 10 × 7 米、3.2 米高：粗石墙、石板地、木梁顶。
##   北墙一座大石壁炉（全屋最亮的光），壁炉上方挂着厄尔德家的旗（灰底燃烧的烽燧）；中间一张长桌两条长凳——给上山下山的烽誓团的人吃饭；
##   西边罗薇娜的桌子：摊着账、压着几张盖了印的文书（5.6 的「征粮令」），墙上钉着一张烽燧线的图（一串点，大半画了叉）；
##   东墙一排粮架，架上只剩几只瘪了的麻袋（缺粮）；门边一排挂斗篷的木钉。人（5.2b）：罗薇娜站在桌子前，烽誓团的征粮人坐在长桌边喝汤。
## 室内的光不跟时段走；窗玻璃按时段换颜色（同「歪桩客栈」，Inn.glass）。
## 坐标：原点在大堂地面中心，北 = -Z；出口门在南墙（z = +3.5）。外面的房子朝西（门对着村路），屋里按「门在南墙」摆，map_spec 照屋里的方向画。

const W := 10.0
const D := 7.0
const H := 3.2
const WALL_T := 0.3
const DOOR_X := 0.0
const DOOR_W := 1.1
const EXIT_NAME := "回到村里"
const WINDOWS := [-3.4, 3.2]
const WIN_W := 0.7
const WIN_Y := 1.6
const WIN_H := 0.8
const HEARTH := Rect2(-1.3, -3.5, 2.6, 1.0)          # 北墙的大壁炉（占地）
const TABLE_POS := Vector3(0.4, 0, 0.0)             # 长桌（东西向）
const DESK := Rect2(-4.7, -1.4, 1.2, 2.2)           # 西边罗薇娜的桌子（靠西墙）
const SHELF := Rect2(4.5, -3.0, 0.5, 4.2)           # 东墙的粮架
const BANNER_TOP := Vector3(0.0, 3.0, -2.88)          # 挂在炉罩正面（炉罩前沿在 z = -2.9）
const MAP_POS := Vector3(-4.97, 1.75, 0.0)          # 西墙上钉着的烽燧线图
## 大堂里的人（5.2b）：[编号, 名字, 位置, 朝向（弧度，0 = 面朝北，-PI / 2 = 面朝东）, 衣服颜色]
const ROWENA := ["rowena", "罗薇娜", Vector3(-3.05, 0, 0.2), -PI * 0.5, "5e6062"]        # 西边桌子前，面朝大堂
const REQUISITIONER := ["requisitioner", "烽誓团的征粮人", Vector3(1.3, 0, 0.8), 0.0, "3e3a34"]     # 长桌南边的长凳东头，面朝桌子
## 命名出生点：front = 刚进门，背对门、面朝大堂（-Z）
const SPAWNS := {
	"front": [Vector3(DOOR_X, 0, 2.7), 0.0],
}
const VIEW_NAMES := ["进门看大堂", "壁炉和旗", "罗薇娜的桌子", "门内对着出口", "粮架"]
const VIEWS := [
	[Vector3(DOOR_X, 0, 2.7), 6.0, -6.0],
	[Vector3(0.6, 0, 0.9), 0.0, 6.0],
	[Vector3(-2.6, 0, 0.6), 72.0, -12.0],
	[Vector3(DOOR_X, 0, 2.2), 180.0, -8.0],
	[Vector3(2.4, 0, 0.6), -78.0, -6.0],
]


static func build(parent: Node3D, reduced_motion := false) -> Transform3D:
	var kit := MeshKit.new()
	_room(kit)
	_hearth(kit)
	_furniture(kit)
	var mi := kit.build({"stone": Look.mat("stone"), "floor": Look.mat("street"), "timber": Look.mat("timber"), "glass": Inn.glass(GameState.daypart),
		"ember": Inn._unshaded(Color("ff7a28")), "soot": Inn._unshaded(Color("0e0b09")), "cloth": Inn._cloth_mat(), "iron": Inn._iron_mat(),
		"sack": _sack_mat(), "ink": Inn._unshaded(Color("3a2a1c"))})
	mi.name = "Waystation"
	parent.add_child(mi)
	_decor(parent, reduced_motion)
	_colliders(parent)
	_lights(parent, reduced_motion)
	for p in [ROWENA, REQUISITIONER]:
		var n := Npc.make(str(p[1]), [], Color(str(p[4])))
		n.name = "Npc_" + str(p[0])
		n.dialogue_area = "waystation"
		n.dialogue_id = str(p[0])
		n.position = p[2]
		n.rotation.y = float(p[3])
		parent.add_child(n)
	var exit := Door.make(EXIT_NAME, DOOR_W, 2.1, false)
	exit.verb = "离开"
	exit.to_area = "highland"
	exit.to_spawn = "waystation_door"
	exit.position = Vector3(DOOR_X - DOOR_W * 0.5, 0, D * 0.5 - 0.02)
	parent.add_child(exit)
	var s: Array = SPAWNS.front
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


static func map_spec() -> Dictionary:
	var shapes := [
		{"k": "furniture", "rect": HEARTH},
		{"k": "mark", "at": HEARTH.get_center() + Vector2(0, 0.6), "icon": "fire", "label": "壁炉"},
		{"k": "furniture", "rect": Rect2(TABLE_POS.x - 1.6, TABLE_POS.z - 0.9, 3.2, 1.8), "label": "长桌"},
		{"k": "furniture", "rect": DESK, "label": "桌子"},
		{"k": "furniture", "rect": SHELF, "label": "粮架"},
	]
	return {
		"bounds": Rect2(-W * 0.5, -D * 0.5, W, D),
		"shapes": shapes,
		"exits": [{"at": Vector2(DOOR_X, D * 0.5), "dir": Vector2(0, 1), "to": "highland", "spawn": "waystation_door", "name": EXIT_NAME}],
	}


## 石板地、四面粗石墙（南墙留门和两扇窗）、木板顶和四根横梁
static func _room(kit: MeshKit) -> void:
	var hw := W * 0.5
	var hd := D * 0.5
	kit.box("floor", Vector3(0, -0.05, 0), Vector3(W, 0.1, D), Basis.IDENTITY, 0.8, 0.8)
	kit.box("timber", Vector3(0, H + 0.05, 0), Vector3(W, 0.1, D), Basis.IDENTITY, 0.4, 0.4, true)
	for x in [-3.3, -1.1, 1.1, 3.3]:
		kit.box("timber", Vector3(x, H - 0.15, 0), Vector3(0.28, 0.3, D), Basis.IDENTITY, 0.55, 0.45)
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
		kit.box("glass", Vector3(wx, WIN_Y, zs + 0.06), Vector3(WIN_W, WIN_H, 0.04))
		kit.box("timber", Vector3(wx, WIN_Y, zs - 0.08), Vector3(0.05, WIN_H, 0.05))
		kit.box("stone", Vector3(wx, sill - 0.04, zs - 0.12), Vector3(WIN_W + 0.16, 0.08, 0.26))
	kit.box("stone", Vector3(DOOR_X, (2.1 + H) * 0.5, zs), Vector3(DOOR_W, H - 2.1, WALL_T), Basis.IDENTITY, 0.8, 0.7)
	kit.box("timber", Vector3(DOOR_X, 2.17, zs - 0.1), Vector3(DOOR_W + 0.4, 0.16, 0.16))


## 北墙的大石壁炉：炉膛里柴火正旺（自发光 + 点光源），石砌的炉罩一直通到顶，炉台上一口铁锅
static func _hearth(kit: MeshKit) -> void:
	var c := Vector3(HEARTH.get_center().x, 0, HEARTH.get_center().y)
	kit.box("stone", c + Vector3(0, 0.15, 0.1), Vector3(2.6, 0.3, 1.0), Basis.IDENTITY, 0.85, 0.6)             # 炉台
	for s in [-1.0, 1.0]:
		kit.box("stone", c + Vector3(s * 1.05, 0.9, -0.05), Vector3(0.5, 1.5, 0.7), Basis.IDENTITY, 0.85, 0.6)  # 两边的炉墙
	kit.box("stone", c + Vector3(0, 1.85, -0.05), Vector3(2.7, 0.4, 0.8), Basis.IDENTITY, 0.75, 0.6)           # 炉口上的横石
	kit.box("stone", c + Vector3(0, (2.05 + H) * 0.5, -0.2), Vector3(2.2, H - 2.05, 0.6), Basis.IDENTITY, 0.8, 0.7)   # 炉罩
	kit.box("soot", c + Vector3(0, 0.9, -0.38), Vector3(1.6, 1.5, 0.02))                                     # 熏黑的炉膛
	kit.box("ember", c + Vector3(0, 0.33, -0.05), Vector3(1.0, 0.05, 0.45))
	for i in 4:
		var a := -0.5 + i * 0.33
		kit.cylinder("timber", c + Vector3(a - 0.15, 0.36, 0.12), c + Vector3(a + 0.15, 0.42, -0.22), 0.06, 0.06, 5, 0.5)
	kit.cylinder("iron", c + Vector3(0.6, 0.31, 0.25), c + Vector3(0.6, 0.6, 0.25), 0.22, 0.18, 8, 0.8)          # 铁锅


## 长桌和两条长凳、西边罗薇娜的桌子和椅子（桌上的账和文书）、东墙的粮架（瘪了的麻袋）、门边挂斗篷的木钉
static func _furniture(kit: MeshKit) -> void:
	var c := TABLE_POS
	kit.box("timber", c + Vector3(0, 0.76, 0), Vector3(3.2, 0.1, 0.95), Basis.IDENTITY, 1.0, 0.8)
	for lx in [-1.35, 1.35]:
		kit.box("timber", c + Vector3(lx, 0.36, 0), Vector3(0.12, 0.72, 0.75), Basis.IDENTITY, 0.8, 0.5)
	for bz in [-0.78, 0.78]:
		kit.box("timber", c + Vector3(0, 0.44, bz), Vector3(3.0, 0.07, 0.32), Basis.IDENTITY, 0.9, 0.7)
		for lx in [-1.2, 1.2]:
			kit.box("timber", c + Vector3(lx, 0.21, bz), Vector3(0.09, 0.42, 0.26), Basis.IDENTITY, 0.8, 0.5)
	for i in 4:                                       # 桌上几只木碗、一只水罐
		var mx := -1.1 + i * 0.6
		kit.cylinder("timber", c + Vector3(mx, 0.81, 0.18 * (1 - 2 * (i % 2))), c + Vector3(mx, 0.88, 0.18 * (1 - 2 * (i % 2))), 0.09, 0.07, 7, 0.85)
	kit.cylinder("iron", c + Vector3(0.3, 0.81, -0.05), c + Vector3(0.3, 1.08, -0.05), 0.09, 0.07, 7, 0.8)
	var d := Vector3(DESK.get_center().x, 0, DESK.get_center().y)
	kit.box("timber", d + Vector3(0, 0.78, 0), Vector3(DESK.size.x, 0.08, DESK.size.y), Basis.IDENTITY, 1.0, 0.8)
	for dx in [-0.48, 0.48]:
		for dz in [-0.95, 0.95]:
			kit.box("timber", d + Vector3(dx, 0.38, dz), Vector3(0.08, 0.76, 0.08), Basis.IDENTITY, 0.8, 0.5)
	kit.box("cloth", d + Vector3(0.05, 0.83, -0.3), Vector3(0.5, 0.02, 0.38), Basis(Vector3.UP, 0.1))         # 摊开的账
	for i in 3:                                       # 几张文书，最上面那张盖着红印（征粮令，5.2b）
		kit.box("cloth", d + Vector3(0.1 + i * 0.03, 0.825 + i * 0.004, 0.45 - i * 0.04), Vector3(0.34, 0.004, 0.24), Basis(Vector3.UP, -0.2 + i * 0.15))
	kit.box("ember", d + Vector3(0.18, 0.84, 0.42), Vector3(0.06, 0.004, 0.06))                                # 红印
	kit.cylinder("ink", d + Vector3(-0.3, 0.82, 0.6), d + Vector3(-0.3, 0.9, 0.6), 0.04, 0.035, 6, 0.6)          # 墨水壶
	kit.box("timber", d + Vector3(0.95, 0.45, 0.0), Vector3(0.45, 0.06, 0.45), Basis.IDENTITY, 0.9, 0.7)       # 椅子
	kit.box("timber", d + Vector3(1.15, 0.85, 0.0), Vector3(0.06, 0.8, 0.45), Basis.IDENTITY, 0.85, 0.6)
	# 西墙上钉着的烽燧线图：一张羊皮纸，一串点连成一线，大半打了叉
	kit.box("cloth", MAP_POS, Vector3(0.02, 0.7, 1.1))
	for i in 9:
		var mz := -0.42 + i * 0.105
		var my := 0.1 * sin(i * 0.9)
		var out := i not in [2, 5, 7]
		kit.box("ink", MAP_POS + Vector3(0.015, my, mz), Vector3(0.01, 0.045, 0.045))
		if out:
			kit.box("ink", MAP_POS + Vector3(0.016, my, mz), Vector3(0.01, 0.09, 0.012), Basis(Vector3.RIGHT, 0.785))
			kit.box("ink", MAP_POS + Vector3(0.016, my, mz), Vector3(0.01, 0.09, 0.012), Basis(Vector3.RIGHT, -0.785))
	# 粮架：三层，只剩几只瘪麻袋
	var sx := SHELF.get_center().x
	for y in [0.45, 1.15, 1.85]:
		kit.box("timber", Vector3(sx, y, SHELF.get_center().y), Vector3(SHELF.size.x, 0.05, SHELF.size.y), Basis.IDENTITY, 0.9, 0.7)
	for z in [SHELF.position.y + 0.05, SHELF.end.y - 0.05]:
		kit.box("timber", Vector3(sx, 1.0, z), Vector3(SHELF.size.x, 2.0, 0.08), Basis.IDENTITY, 0.8, 0.5)
	for p in [Vector3(sx, 0.55, -2.4), Vector3(sx, 0.55, -1.8), Vector3(sx, 1.25, 0.6)]:
		kit.box("sack", p, Vector3(0.38, 0.16, 0.45), Basis(Vector3.UP, 0.3), 1.0, 0.7)
	# 门边挂斗篷的木钉、一件灰斗篷
	for i in 4:
		kit.box("timber", Vector3(-2.2 + i * 0.35, 1.85, D * 0.5 - 0.05), Vector3(0.05, 0.05, 0.14))
	kit.box("sack", Vector3(-2.2, 1.35, D * 0.5 - 0.1), Vector3(0.5, 0.95, 0.06), Basis.IDENTITY, 0.8, 0.5)


static func _decor(parent: Node3D, reduced_motion := false) -> void:
	var d := Decor.new()
	d.banner(BANNER_TOP, Vector3.BACK, 1.3, 1.0, HighlandVillage.BANNER_FIELD, HighlandVillage.BANNER_CHARGE, "beacon")
	d.candles(Vector3(DESK.get_center().x + 0.2, 0.82, DESK.get_center().y - 0.75), 2)
	d.candles(TABLE_POS + Vector3(-0.6, 0.81, -0.1), 1, false)
	d.sconce(Vector3(-W * 0.5 + 0.02, 2.0, -2.2), Vector3.RIGHT, true)
	d.woodpile(Vector3(-2.2, 0, -3.15), Vector3.RIGHT, 1.2, 0.7, false)
	d.barrel(Vector3(4.4, 0, 2.6))
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
	var door_l := DOOR_X - DOOR_W * 0.5
	var door_r := DOOR_X + DOOR_W * 0.5
	Inn._solid(parent, Vector3((-hw + door_l) * 0.5, H * 0.5, zs), Vector3(door_l + hw, H, WALL_T))
	Inn._solid(parent, Vector3((door_r + hw) * 0.5, H * 0.5, zs), Vector3(hw - door_r, H, WALL_T))
	Inn._solid(parent, Vector3(DOOR_X, H * 0.5, zs + 0.15), Vector3(DOOR_W, H, 0.1))
	Inn._solid(parent, Vector3(HEARTH.get_center().x, 1.0, HEARTH.get_center().y), Vector3(HEARTH.size.x + 0.1, 2.0, HEARTH.size.y + 0.2))
	Inn._solid(parent, TABLE_POS + Vector3(0, 0.4, 0), Vector3(3.2, 0.8, 1.9))
	Inn._solid(parent, Vector3(DESK.get_center().x + 0.2, 0.45, DESK.get_center().y), Vector3(DESK.size.x + 0.4, 0.9, DESK.size.y))
	Inn._solid(parent, Vector3(SHELF.get_center().x, 1.0, SHELF.get_center().y), Vector3(SHELF.size.x, 2.0, SHELF.size.y))


## 光：壁炉（暖橙、闪烁，全屋最亮）、长桌上方一盏油灯、西墙的火把（Decor 的 sconce 自带一盏小光）
static func _lights(parent: Node3D, reduced_motion: bool) -> void:
	var fire := Tavern.FireLight.new()
	fire.name = "Fire"
	fire.light_color = Color("ff8a3a")
	fire.base = 3.6
	fire.omni_range = 10.0
	fire.omni_attenuation = 1.1
	fire.position = Vector3(HEARTH.get_center().x, 0.9, HEARTH.get_center().y + 0.9)
	fire.flicker = not reduced_motion
	fire.add_to_group("light_source")
	fire.set_meta("radius", 4.5)
	parent.add_child(fire)
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.8, 1.0)
	var hm := Look.halo(Color("ff8a3a"), 0.45).duplicate() as StandardMaterial3D
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = hm
	halo.mesh = q
	halo.position = Vector3(HEARTH.get_center().x, 0.6, HEARTH.get_center().y + 0.4)
	parent.add_child(halo)
	var lamp := OmniLight3D.new()
	lamp.name = "TableLamp"
	lamp.light_color = Look.LAMP_COLOR
	lamp.light_energy = 1.6
	lamp.omni_range = 7.0
	lamp.position = TABLE_POS + Vector3(0, 2.4, 0)
	parent.add_child(lamp)


static func _sack_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("8a7a5a")
	m.roughness = 1.0
	m.vertex_color_use_as_albedo = true
	return m
