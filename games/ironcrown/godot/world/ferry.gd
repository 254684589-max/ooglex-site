class_name Ferry
extends RefCounted
## 渡口（路线图 3.6；STORY.md 第三节「渡口：码头、渡船、雾中的河面；渡工、埃德里克与塞拉斯的密会点」）：原创布局。
## 桦林南头的小路下到灰鲸河边：岸上一片踩乱的雪地，西边渡工的小屋，东边拴马的棚子（塞拉斯的马，玛蒂尔达说过「马拴在渡口的棚子里」），
## 一道木码头伸进雾里的河面，码头尽头东边泊着平底渡船。
## 人：码头上是埃德里克少爷和南方人塞拉斯；码头根上「灰手」奥弗带着两个手下堵着路（对话：说服 / 威吓 / 付钱，或者动手——combat/encounter.gd）；渡工躲在小屋门口。
## 奥弗那伙人倒下 / 认输了（GameState.dead / yielded）就按敌人放回去（倒着或跪着、能搜身）；说服走了（旗标 offer_left）就不再出现。
## 3.7：埃德里克拿出借据后三选一（旗标 prologue_edric）——之后埃德里克和塞拉斯都离开渡口（回镇上 / 坐船南下），奥尔本修士提着灯来到岸上（alban_ferry），
## 交出旧书后序章结束；修士在渡口时小教堂里没有他，序章结束（prologue_done）后他回小教堂。refresh() 在对话关上后按旗标把人对上（main 调用）。
## 坐标：原点在码头根的岸边，北 = -Z（回桦林），南 = +Z（河面）。人物仍是占位胶囊，马是占位的方块。

const HALF_X := 16.0
const NORTH := -30.0
const SHORE_Z := 0.0              # 岸边（再往南是水）
const WATER_Y := -0.6
const PIER_X0 := 0.9
const PIER_X1 := 3.3
const PIER_END := 14.0
const DECK_Y := 0.25              # 码头面比岸高一点（走得上去：攀爬 0.3 米以内）
const HUT := Vector3(-7.0, 0, -6.0)            # 渡工小屋正面墙脚中点（正面朝东）
const SHED := Vector3(8.6, 0, -6.2)            # 马棚中心
const BOAT := Vector3(5.6, 0, 10.0)            # 渡船中心
const ENCOUNTER := "ferry_offer"
const EXIT_NAME := "回桦林的路"
## 「灰手」奥弗一伙：[名字, 敌人种类, 敌人编号, 位置, 朝向（弧度）, 对话编号（空 = 只说一句）, 外衣颜色]
const OFFER_GROUP := [
	["「灰手」奥弗", "outlaw_boss", "ferry_offer", Vector3(2.1, DECK_Y, 2.4), PI, "offer", Color("4a4a50")],
	["无旗者", "clubber", "ferry_thug_a", Vector3(-0.6, 0, -1.4), 2.8, "", Color("5a3a2e")],
	["无旗者", "swordsman", "ferry_thug_b", Vector3(4.8, 0, -1.4), -2.8, "", Color("3a3e4a")],
]
const ALBAN_POS := Vector3(-1.4, 0, -4.2)        # 3.7：修士从北边的坡上下来，站在码头根旁边的岸上
const EDRIC_POS := Vector3(2.0, DECK_Y, 11.6)
const SILAS_POS := Vector3(2.6, DECK_Y, 10.2)
const FERRYMAN_POS := Vector3(-6.2, 0, -4.4)
const FERRYMAN_LINES := ["灰手那伙人一来，我就躲到屋门口了……誓剑大人，您可小心点。", "雾不散，船不开。要过河，等天亮吧。", "那个南方人的马拴在棚子里，喂了三天的料钱还没给呢。"]
const FERRYMAN_LINES_CH1 := ["雾散了一半，今天的渡船照常开。", "今天码头上忙，南边的货都堵在河上。", "往南的船都满了——冠城那边的消息一天比一天坏。"]     # 第一章的清晨（4.3）
const THUG_LINES := ["头儿说了算。", "……"]
## 命名出生点（world/areas.gd）：north = 从桦林下来，站在北头、面朝河
const SPAWNS := {
	"north": [Vector3(0, 0, NORTH + 3.5), 180.0],
}
const VIEW_NAMES := ["北头看渡口", "岸上看码头", "码头上看少爷", "马棚", "奥弗面前"]
## 网页 ?area=ferry&view=N 的固定机位：位置、水平朝向（度，0 = 面朝 -Z，正 = 向左转）、俯仰（度）
const VIEWS := [
	[Vector3(0, 0, NORTH + 3.5), 180.0, -3.0],
	[Vector3(1.2, 0, -5.5), 175.0, -5.0],
	[Vector3(2.1, DECK_Y, 7.0), 180.0, -6.0],
	[Vector3(5.0, 0, -9.6), -135.0, -8.0],
	[Vector3(2.1, DECK_Y, 0.7), 180.0, -2.0],      # 4：码头根上、奥弗面前（冒烟测试对话用）
]


static func build(parent: Node3D, reduced_motion := false) -> Transform3D:
	var kit := MeshKit.new()
	_ground(kit, parent)
	_pier(kit, parent)
	_boat(kit, parent)
	_shed(kit, parent)
	_trees(kit, parent)
	var mi := kit.build({"snow": Look.mat("snow"), "timber": Look.mat("timber"), "stone": Look.mat("stone"), "roof": Look.mat("roof"),
		"water": Look.water(), "horse": _horse_mat(), "mane": _mane_mat(), "hay": _hay_mat(), "ember": _ember_mat(), "rope": _rope_mat(),
		"birch": Look.birch(), "bark": Look.mat("bark")})
	mi.name = "Ferry"
	parent.add_child(mi)
	House.build(parent, HUT, 90.0, {"w": 4.2, "d": 4.0, "floors": 0, "roof": "eaves", "chimney": true, "door_x": 0.0, "seed": 61, "lit": 1.0,
		"door": {"name": "渡工的小屋", "text": "门从里面闩着。渡工就站在门口，用不着进去。"}})
	_bounds(parent)
	_lamps(parent, reduced_motion)
	_fog(parent, reduced_motion)
	Edges.dress(parent, Rect2(-HALF_X, NORTH, HALF_X * 2, SHORE_Z - NORTH), [      # 北头的路口：门柱、地名、栅栏、灯笼，路伸进白桦林（3.10）
		{"at": Vector3(0, 0, NORTH + 0.6), "out": Vector3(0, 0, -1), "half": 1.6, "fence": true, "lantern": true, "frame": "桦林"}],
		[Rect2(-400.0, SHORE_Z, 800.0, 400.0)], 3611)                                # 南边是河：不种树、不铺雪（雪地铺到岸边，和水接上）
	var exit := Door.make(EXIT_NAME, 1.9, 2.0, false)
	exit.verb = "回到"
	exit.to_area = "birch"
	exit.to_spawn = "south"
	exit.position = Vector3(-0.95, 0, NORTH + 0.6)
	parent.add_child(exit)
	var saddlebag := LootContainer.make("ferry_saddlebag", "马鞍袋", ["bread", "strong_spirit"], 8)
	saddlebag.position = SHED + Vector3(-1.2, 0, 1.0)
	parent.add_child(saddlebag)
	_people(parent)
	var s: Array = SPAWNS.north
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


## 地图（3.11，core/area_map.gd 的格式）：小路、河、码头、渡船、小屋和马棚、北头的路口。人和马鞍袋都不画。
## 码头和渡船伸到岸外，地图框住的范围（view）比走得到的岸上大
static func map_spec() -> Dictionary:
	return {
		"bounds": Rect2(-HALF_X, NORTH, HALF_X * 2, SHORE_Z - NORTH),
		"view": Rect2(-HALF_X, NORTH, HALF_X * 2, PIER_END + 2.0 - NORTH),
		"shapes": [
			{"k": "water", "rect": Rect2(-HALF_X, SHORE_Z, HALF_X * 2, PIER_END + 2.0 - SHORE_Z), "label": "灰鲸河"},
			{"k": "road", "rect": Rect2(-1.6, NORTH + 0.6, 3.2, SHORE_Z - NORTH - 0.6)},
			{"k": "pier", "rect": Rect2(PIER_X0, SHORE_Z - 1.0, PIER_X1 - PIER_X0, PIER_END - SHORE_Z + 1.0), "label": "码头"},
			{"k": "boat", "rect": Rect2(BOAT.x - 1.7, BOAT.z - 3.3, 3.4, 6.6), "label": "渡船"},
			{"k": "house", "pts": House.footprint(HUT, 90.0, 4.2, 4.0)},
			{"k": "house", "rect": Rect2(SHED.x - 1.7, SHED.z - 1.5, 3.4, 3.0)},
		],
		"exits": [
			{"at": Vector2(0, NORTH + 0.6), "dir": Vector2(0, -1), "to": "birch", "spawn": "south", "name": EXIT_NAME},
		],
	}


## 岸上的雪地（到岸边为止，有厚度）、岸边一溜泥和冰、河面（低一截的深色平面，伸进雾里）
static func _ground(kit: MeshKit, parent: Node3D) -> void:
	var len_z := SHORE_Z - NORTH + 4.0
	kit.box("snow", Vector3(0, -0.1, (SHORE_Z + NORTH - 4.0) * 0.5), Vector3(HALF_X * 2 + 6, 0.2, len_z), Basis.IDENTITY, 1.0, 0.9)
	kit.box("snow", Vector3(0, 0.004, -14.0), Vector3(3.2, 0.02, 28.0), Basis.IDENTITY, 0.62, 0.62)                # 从桦林下来的小路
	kit.box("snow", Vector3(1.0, 0.006, -3.0), Vector3(12.0, 0.02, 6.0), Basis(Vector3.UP, 0.05), 0.68, 0.68)       # 码头根被踩乱的一片
	# 岸边的石头、河面：和边界外的雪地一样宽、一样远（3.10：原来只有区域那么宽，雪地铺出去以后两头露出河的边）
	kit.box("stone", Vector3(0, -0.05, SHORE_Z - 0.15), Vector3((HALF_X + Edges.GROUND_MARGIN) * 2, 0.3, 0.5), Basis.IDENTITY, 0.5, 0.3)
	kit.box("water", Vector3(0, WATER_Y, SHORE_Z + Edges.GROUND_MARGIN * 0.5), Vector3((HALF_X + Edges.GROUND_MARGIN) * 2, 0.02, Edges.GROUND_MARGIN))
	_solid(parent, Vector3(0, -0.1, (SHORE_Z + NORTH - 4.0) * 0.5), Vector3(HALF_X * 2 + 6, 0.2, len_z))


## 木码头：桩子插在水里，木板面（有碰撞，能走上去），两边和尽头有看不见的栏杆（掉不下水）；尽头两根系船柱
static func _pier(kit: MeshKit, parent: Node3D) -> void:
	var cx := (PIER_X0 + PIER_X1) * 0.5
	var w := PIER_X1 - PIER_X0
	var z0 := SHORE_Z - 1.0
	kit.box("timber", Vector3(cx, DECK_Y - 0.06, (z0 + PIER_END) * 0.5), Vector3(w, 0.12, PIER_END - z0), Basis.IDENTITY, 1.0, 0.6)
	for i in int(PIER_END - z0) + 1:
		var z := z0 + i
		kit.box("timber", Vector3(cx, DECK_Y + 0.005, z), Vector3(w, 0.01, 0.06), Basis.IDENTITY, 0.5, 0.5)          # 板缝
	for z in range(int(SHORE_Z) + 2, int(PIER_END) + 1, 3):
		for x in [PIER_X0 + 0.1, PIER_X1 - 0.1]:
			kit.cylinder("timber", Vector3(x, WATER_Y - 0.6, z), Vector3(x, DECK_Y + 0.35, z), 0.12, 0.12, 6, 0.7)
	for x in [PIER_X0 + 0.2, PIER_X1 - 0.2]:
		kit.cylinder("timber", Vector3(x, DECK_Y, PIER_END - 0.3), Vector3(x, DECK_Y + 0.7, PIER_END - 0.3), 0.14, 0.12, 7, 0.8)
	_solid(parent, Vector3(cx, DECK_Y - 0.1, (z0 + PIER_END) * 0.5), Vector3(w, 0.2, PIER_END - z0))
	for x in [PIER_X0 - 0.1, PIER_X1 + 0.1]:
		_solid(parent, Vector3(x, 1.2, (SHORE_Z + 0.3 + PIER_END) * 0.5), Vector3(0.2, 2.4, PIER_END - SHORE_Z - 0.3))
	_solid(parent, Vector3(cx, 1.2, PIER_END + 0.1), Vector3(w + 0.4, 2.4, 0.2))


## 平底渡船：泊在码头尽头东边，船舷一圈矮栏，船头一根撑篙；缆绳系在码头的柱子上
static func _boat(kit: MeshKit, parent: Node3D) -> void:
	var b := BOAT
	var deck := WATER_Y + 0.45
	kit.box("timber", Vector3(b.x, deck - 0.2, b.z), Vector3(3.4, 0.4, 6.6), Basis.IDENTITY, 0.9, 0.4)
	for sx in [-1.0, 1.0]:
		kit.box("timber", Vector3(b.x + sx * 1.62, deck + 0.2, b.z), Vector3(0.12, 0.4, 6.6), Basis.IDENTITY, 0.8, 0.6)
	for sz in [-1.0, 1.0]:
		kit.box("timber", Vector3(b.x, deck + 0.2, b.z + sz * 3.24), Vector3(3.4, 0.4, 0.12), Basis.IDENTITY, 0.8, 0.6)
	kit.cylinder("timber", Vector3(b.x + 1.2, deck, b.z + 2.6), Vector3(b.x + 0.4, deck + 4.2, b.z + 3.6), 0.05, 0.04, 5, 0.8)    # 撑篙
	kit.box("timber", Vector3(b.x - 0.6, deck + 0.25, b.z - 1.0), Vector3(1.2, 0.5, 0.8), Basis(Vector3.UP, 0.3), 0.8, 0.5)        # 一只木箱
	kit.cylinder("rope", Vector3(PIER_X1 - 0.2, DECK_Y + 0.6, PIER_END - 0.3), Vector3(b.x - 1.5, deck + 0.3, b.z + 2.8), 0.025, 0.025, 4, 0.8)
	_solid(parent, Vector3(b.x, deck, b.z), Vector3(3.4, 0.8, 6.6))


## 马棚：四根柱子、斜顶，里面一匹占位的马（方块搭的身子、脖子、头、腿）、一堆干草和一只料槽
static func _shed(kit: MeshKit, parent: Node3D) -> void:
	var c := SHED
	for dx in [-1.6, 1.6]:
		for dz in [-1.4, 1.4]:
			kit.box("timber", c + Vector3(dx, 1.15 + (0.25 if dz < 0 else 0.0), dz), Vector3(0.14, 2.3 + (0.5 if dz < 0 else 0.0), 0.14), Basis.IDENTITY, 0.85, 0.5)
	kit.box("roof", c + Vector3(0, 2.6, 0), Vector3(3.8, 0.08, 3.4), Basis(Vector3.RIGHT, deg_to_rad(8.0)), 0.9, 0.6)
	kit.box("timber", c + Vector3(0, 0.5, -1.4), Vector3(3.2, 1.0, 0.08), Basis.IDENTITY, 0.8, 0.5)       # 后面一道矮挡板
	# 马：面朝西（-X），侧对着岸
	var h := c + Vector3(0.2, 0, 0.1)
	kit.box("horse", h + Vector3(0, 1.25, 0), Vector3(1.6, 0.65, 0.55), Basis.IDENTITY, 1.0, 0.7)                      # 身子
	kit.box("horse", h + Vector3(-0.95, 1.65, 0), Vector3(0.35, 0.75, 0.32), Basis(Vector3.BACK, deg_to_rad(-30.0)), 1.0, 0.8)   # 脖子
	kit.box("horse", h + Vector3(-1.25, 1.95, 0), Vector3(0.55, 0.26, 0.26), Basis(Vector3.BACK, deg_to_rad(-20.0)), 1.0, 0.8)   # 头
	for lx in [-0.6, 0.6]:
		for lz in [-0.18, 0.18]:
			kit.box("horse", h + Vector3(lx, 0.47, lz), Vector3(0.14, 0.94, 0.14), Basis.IDENTITY, 0.8, 0.5)
	kit.box("mane", h + Vector3(0.88, 1.15, 0), Vector3(0.1, 0.55, 0.12), Basis(Vector3.BACK, deg_to_rad(20.0)), 0.6, 0.5)      # 尾巴
	kit.box("mane", h + Vector3(-0.86, 1.82, 0), Vector3(0.12, 0.62, 0.1), Basis(Vector3.BACK, deg_to_rad(-30.0)), 0.8, 0.7)     # 鬃毛
	kit.box("hay", c + Vector3(1.2, 0.3, -0.9), Vector3(1.0, 0.6, 0.7), Basis(Vector3.UP, 0.2), 1.0, 0.6)
	kit.box("timber", c + Vector3(-1.2, 0.45, -1.0), Vector3(0.9, 0.35, 0.4), Basis.IDENTITY, 0.8, 0.5)                     # 料槽
	_solid(parent, c + Vector3(0, 1.2, 0), Vector3(3.4, 2.4, 3.0))


## 岸上北半边的白桦（和桦林同一种树，world/birch.gd），避开小路、小屋、马棚和码头根
static func _trees(kit: MeshKit, parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3606
	var placed: Array = []
	var tries := 0
	while placed.size() < 26 and tries < 2000:
		tries += 1
		var p := Vector3(rng.randf_range(-HALF_X + 1.0, HALF_X - 1.0), 0, rng.randf_range(NORTH + 3.0, -12.0))
		if absf(p.x) < 3.0 or Vector2(p.x - HUT.x + 2.0, p.z - HUT.z).length() < 4.5 or Vector2(p.x - SHED.x, p.z - SHED.z).length() < 4.0:
			continue
		var ok := true
		for q in placed:
			if Vector2(p.x - q.x, p.z - q.z).length() < 2.6:
				ok = false
				break
		if ok:
			placed.append(p)
			Birch.add_tree(kit, parent, p, rng)


## 看不见的围墙：东西两边和北头（北头留路口，靠门回桦林）；岸边一道（码头上另有栏杆）
static func _bounds(parent: Node3D) -> void:
	var len_z := SHORE_Z - NORTH
	_solid(parent, Vector3(HALF_X + 0.2, 3, (SHORE_Z + NORTH) * 0.5), Vector3(0.4, 6, len_z))
	_solid(parent, Vector3(-HALF_X - 0.2, 3, (SHORE_Z + NORTH) * 0.5), Vector3(0.4, 6, len_z))
	_solid(parent, Vector3(0, 3, NORTH - 0.2), Vector3(HALF_X * 2, 6, 0.4))
	var left := (-HALF_X + PIER_X0 - 0.2) * 0.5
	var right := (HALF_X + PIER_X1 + 0.2) * 0.5
	_solid(parent, Vector3(left, 3, SHORE_Z + 0.25), Vector3(PIER_X0 - 0.2 + HALF_X, 6, 0.3))
	_solid(parent, Vector3(right, 3, SHORE_Z + 0.25), Vector3(HALF_X - PIER_X1 - 0.2, 6, 0.3))


## 风灯：码头根一盏、码头尽头一盏、渡工小屋门口一盏、马棚一盏；码头的两盏在组 light_source（站在灯下谁都看得见你）
static func _lamps(parent: Node3D, reduced_motion: bool) -> void:
	var kit := MeshKit.new()
	for spec in [[Vector3(PIER_X1 + 0.15, 1.7, SHORE_Z + 0.4), true], [Vector3(PIER_X0 - 0.05, 1.7, PIER_END - 0.6), true],
			[HUT + Vector3(0.6, 1.9, 1.3), false], [SHED + Vector3(-1.7, 2.0, 1.5), false]]:
		var p: Vector3 = spec[0]
		kit.box("ember", p, Vector3(0.18, 0.26, 0.18))
		kit.box("timber", p + Vector3(0, 0.16, 0), Vector3(0.24, 0.05, 0.24))
		kit.box("timber", Vector3(p.x, (p.y + (DECK_Y if p.z > SHORE_Z else 0.0)) * 0.5, p.z), Vector3(0.1, p.y, 0.1), Basis.IDENTITY, 0.8, 0.5)
		var halo := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.3, 1.3)
		var hm := Look.halo(Look.LAMP_COLOR, 0.55).duplicate() as StandardMaterial3D
		hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		q.material = hm
		halo.mesh = q
		halo.position = p
		parent.add_child(halo)
		var l := Tavern.FireLight.new()
		l.light_color = Look.LAMP_COLOR
		l.base = 1.5
		l.omni_range = 8.0
		l.omni_attenuation = 1.15
		l.position = p + Vector3(0, -0.1, 0)
		l.flicker = not reduced_motion
		if spec[1]:
			l.add_to_group("light_source")
			l.set_meta("radius", 5.0)
		Daypart.mark_night_light(l, halo)         # 白天灭掉（4.2）
		parent.add_child(l)
	parent.add_child(kit.build({"ember": _ember_mat(), "timber": Look.mat("timber")}))


## 贴地雾带：岸上一层，河面上两层更浓的（低画质时由 main 隐藏一半）
static func _fog(parent: Node3D, reduced_motion: bool) -> void:
	var root := Node3D.new()
	root.name = "FogBands"
	parent.add_child(root)
	var i := 0
	var spots: Array = []
	for z in [-24.0, -16.0, -8.0]:
		for x in [-8.0, 0.0, 8.0]:
			spots.append([Vector3(x, 0.35 + (i % 2) * 0.25, z), 0.55])
			i += 1
	for z in [4.0, 12.0, 20.0]:
		for x in [-10.0, -2.0, 6.0, 14.0]:
			spots.append([Vector3(x, WATER_Y + 0.5 + (i % 2) * 0.3, z), 0.75])
			i += 1
	for k in spots.size():
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(9.0, 8.0)
		mi.mesh = pm
		mi.material_override = Look.fog_material(float(spots[k][1]), reduced_motion)
		mi.position = spots[k][0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("fog_index", k)
		mi.add_to_group("fog_band")
		root.add_child(mi)


## 人：奥弗一伙（没解决时是 NPC，倒下 / 认输的按敌人放回去，说服走了就不放）、埃德里克、塞拉斯、渡工
static func _people(parent: Node3D) -> void:
	for m in OFFER_GROUP:
		var id := str(m[2])
		if GameState.dead.has(id) or GameState.yielded.has(id):
			var e := Enemy.make(str(m[1]), id)
			e.display_override = str(m[0])
			e.position = m[3]
			parent.add_child(e)                         # 自己按存档摆成倒下 / 跪着的样子，留搜刮点
			continue
		if GameState.has_flag("offer_left"):
			continue
		var n := Npc.make(str(m[0]), THUG_LINES, m[6])
		if str(m[5]) != "":
			n.dialogue_area = "ferry"
			n.dialogue_id = str(m[5])
		n.position = m[3]
		n.rotation.y = float(m[4])
		n.set_meta("enemy_kind", str(m[1]))
		n.set_meta("enemy_id", id)
		n.add_to_group(Encounter.group_name(ENCOUNTER))
		parent.add_child(n)
	_pair(parent)
	_alban(parent)
	var fm := Npc.make("渡工", FERRYMAN_LINES_CH1 if GameState.chapter >= 1 else FERRYMAN_LINES, Color("4a5a4a"))
	fm.position = FERRYMAN_POS
	fm.rotation.y = -PI / 2                             # 面朝东（码头）
	parent.add_child(fm)


## 埃德里克与塞拉斯：做出抉择以前在码头上（之后都走了）
static func _pair(parent: Node3D) -> void:
	if GameState.has_flag("prologue_edric"):
		return
	for spec in [["埃德里克", "edric", EDRIC_POS, Color("2e3a4e")], ["塞拉斯", "silas", SILAS_POS, Color("3a2e44")]]:
		var p := Npc.make(str(spec[0]), [], spec[3])
		p.dialogue_area = "ferry"
		p.dialogue_id = str(spec[1])
		p.position = spec[2]
		parent.add_child(p)                             # 脸朝北（岸上）


## 奥尔本修士：抉择之后提着灯来到岸上，序章结束后回小教堂
static func _alban(parent: Node3D) -> void:
	if not GameState.has_flag("prologue_edric") or GameState.has_flag("prologue_done"):
		return
	var a := Npc.make("奥尔本修士", [], Color("3a3a4a"))
	a.dialogue_area = "ferry"
	a.dialogue_id = "alban_ferry"
	a.position = ALBAN_POS
	a.rotation.y = PI * 0.85                            # 面朝码头（东南）
	var lantern := MeshInstance3D.new()                 # 手里的风灯：一小块亮的灯罩 + 一盏不投影的暖光
	var bm := BoxMesh.new()
	bm.size = Vector3(0.14, 0.2, 0.14)
	bm.material = _ember_mat()
	lantern.mesh = bm
	lantern.position = Vector3(0.38, 0.85, -0.1)
	a.add_child(lantern)
	var l := OmniLight3D.new()
	l.light_color = Look.LAMP_COLOR
	l.light_energy = 0.9
	l.omni_range = 4.0
	l.position = lantern.position
	a.add_child(l)
	parent.add_child(a)


## 对话关上后按旗标把人对上（3.7）：抉择后埃德里克和塞拉斯离开、修士来了。返回发生了什么（"left" / "arrived" / ""）给 main 提示
static func refresh(parent: Node3D) -> String:
	var what := ""
	if GameState.has_flag("prologue_edric"):
		for n in parent.find_children("*", "", true, false):
			if n is Npc and (n as Npc).dialogue_id in ["edric", "silas"]:
				n.queue_free()
				what = "left"
		var has_alban := false
		for n in parent.find_children("*", "", true, false):
			if n is Npc and (n as Npc).dialogue_id == "alban_ferry" and not n.is_queued_for_deletion():
				has_alban = true
		if not has_alban and not GameState.has_flag("prologue_done"):
			_alban(parent)
			what = "arrived"
	return what


static func _horse_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("8a7e72")                  # 灰马：夜里看得出轮廓
	m.roughness = 0.85
	m.vertex_color_use_as_albedo = true
	return m


static func _mane_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("2e2824")
	m.roughness = 1.0
	m.vertex_color_use_as_albedo = true
	return m


static func _hay_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("8a7440")
	m.roughness = 1.0
	m.vertex_color_use_as_albedo = true
	return m


static func _rope_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("6a5a40")
	m.roughness = 1.0
	m.vertex_color_use_as_albedo = true
	return m


static func _ember_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("ffb060")
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
