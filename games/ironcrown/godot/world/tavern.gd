class_name Tavern
extends RefCounted
## 「倒钩鱼」酒馆内部（路线图 3.1；STORY.md 第三节「酒馆：壁炉、长桌、醉汉」）：原创布局。
## 一间 8 × 7 米、3 米高的大堂：西墙石砌壁炉（炉火照亮半个屋子，轻微闪烁）、北边吧台与酒架、一张长桌和长凳、窗边一张小方桌、
## 东墙一道通到楼上客房的木梯（梯口的栅门锁着，楼上不做）、南墙两扇看得见夜雾的窗和出去的门。
## 老板娘玛蒂尔达在吧台后面（对话给少爷的线索，也卖面包）；一个喝多了的伐木工、一个烤火的货郎。人物仍是占位胶囊（A.2 换装）。
## 坐标：原点在大堂地面中心，北 = -Z；出口门在南墙（z = +3.5）。

const W := 8.0
const D := 7.0
const H := 3.0
const WALL_T := 0.2
const DOOR_X := 1.55              # 出口门中心
const DOOR_W := 1.1
## 命名出生点（world/areas.gd）：front = 刚从主街进门，背对门站在门内、面朝大堂（-Z）
const SPAWNS := {
	"front": [Vector3(DOOR_X, 0, 2.6), 0.0],
}
const FIRE_POS := Vector3(-3.55, 0.35, -0.3)
const MATILDA_POS := Vector3(0.6, 0, -2.85)
const TABLE_POS := Vector3(-1.2, 0, 0.9)          # 长桌（沿东西方向，两边长凳）
const SMALL_TABLE_POS := Vector3(-2.75, 0, 2.75)  # 西南角窗边的小方桌
const WOODCUTTER_POS := Vector3(-2.7, 0, 0.9)     # 长桌西头，背靠炉火
const PEDDLER_POS := Vector3(-2.7, 0, -1.9)
const PEDDLER_LINES := ["这么大的雾，明天的渡船怕是开不了。", "南边来的货一个月比一个月少。听说冠城那边……算了，不说了。", "炉子边上最暖和，你也过来烤烤？"]
const VIEW_NAMES := ["进门看大堂", "吧台前（玛蒂尔达）", "看壁炉", "门内对着出口"]
## 网页 ?area=tavern&view=N 的固定机位：位置、水平朝向（度，0 = 面朝 -Z，正 = 向左转）、俯仰（度）
const VIEWS := [
	[Vector3(DOOR_X, 0, 2.6), 12.0, -4.0],
	[Vector3(0.6, 0, -0.95), 0.0, -12.0],
	[Vector3(0.9, 0, 1.9), 66.0, -6.0],
	[Vector3(DOOR_X, 0, 1.9), 180.0, -8.0],     # 3：门内对着出口（冒烟测试出门用）
]


static func build(parent: Node3D, reduced_motion := false) -> Transform3D:
	var kit := MeshKit.new()
	_room(kit)
	_fireplace(kit)
	_bar(kit)
	_tables(kit)
	_stairs(kit)
	var mi := kit.build({"timber": Look.mat("timber"), "plaster": Look.mat("plaster"), "stone": Look.mat("stone"),
		"glass_dark": Look.glass_dark(), "ember": _ember_mat(), "bottle": _bottle_mat(), "soot": _soot_mat()})
	mi.name = "Tavern"
	parent.add_child(mi)
	_colliders(parent)
	_lights(parent, reduced_motion)
	# 出口：回到主街（站在酒馆门外）
	var exit := Door.make("回到主街", DOOR_W, 2.1, false)
	exit.verb = "离开"
	exit.to_area = "frostford"
	exit.to_spawn = "tavern_door"
	exit.position = Vector3(DOOR_X - DOOR_W * 0.5, 0, D * 0.5 - 0.02)
	parent.add_child(exit)
	# 梯口的栅门：锁着（楼上客房不做）
	var gate := Door.make("上楼的栅门", 0.9, 1.0, true)
	gate.locked_text = "栅门上挂着锁。玛蒂尔达头也不抬：「楼上是客房，今晚住满了。」"
	gate.position = Vector3(W * 0.5 - 0.95, 0, 2.78)
	parent.add_child(gate)
	# 人：老板娘（对话树）、醉醺醺的伐木工（对话树）、烤火的货郎（轮流说一句）
	var matilda := Npc.make("玛蒂尔达", [], Color("6a3a3a"))
	matilda.dialogue_area = "tavern"
	matilda.dialogue_id = "matilda"
	matilda.position = MATILDA_POS
	matilda.rotation.y = PI                  # 面朝大堂（+Z）
	parent.add_child(matilda)
	var woodcutter := Npc.make("伐木工", [], Color("4a4a32"))
	woodcutter.dialogue_area = "tavern"
	woodcutter.dialogue_id = "woodcutter"
	woodcutter.position = WOODCUTTER_POS
	woodcutter.rotation.y = -PI / 2          # 面朝长桌（+X）
	parent.add_child(woodcutter)
	var peddler := Npc.make("货郎", PEDDLER_LINES, Color("3a4a5a"))
	peddler.position = PEDDLER_POS
	peddler.rotation.y = 2.65                # 面朝炉火（西南方向）
	parent.add_child(peddler)
	var s: Array = SPAWNS.front
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


## 地板、四面墙（南墙留门洞和两扇窗）、天花板与横梁、墙上的木柱与护墙板
static func _room(kit: MeshKit) -> void:
	var hw := W * 0.5
	var hd := D * 0.5
	kit.box("timber", Vector3(0, -0.05, 0), Vector3(W, 0.1, D), Basis.IDENTITY, 0.75, 0.75)
	kit.box("plaster", Vector3(0, H + 0.05, 0), Vector3(W, 0.1, D), Basis.IDENTITY, 0.55, 0.55, true)
	for x in [-2.4, -0.8, 0.8, 2.4]:
		kit.box("timber", Vector3(x, H - 0.12, 0), Vector3(0.22, 0.24, D), Basis.IDENTITY, 0.6, 0.5)
	# 北墙、东墙、西墙：灰泥 + 下半截护墙板 + 木柱
	kit.box("plaster", Vector3(0, H * 0.5, -hd - WALL_T * 0.5), Vector3(W, H, WALL_T), Basis.IDENTITY, 0.85, 0.7)
	kit.box("plaster", Vector3(hw + WALL_T * 0.5, H * 0.5, 0), Vector3(WALL_T, H, D), Basis.IDENTITY, 0.85, 0.7)
	kit.box("plaster", Vector3(-hw - WALL_T * 0.5, H * 0.5, 0), Vector3(WALL_T, H, D), Basis.IDENTITY, 0.85, 0.7)
	kit.box("timber", Vector3(0, 0.45, -hd + 0.02), Vector3(W, 0.9, 0.04), Basis.IDENTITY, 0.8, 0.6)
	kit.box("timber", Vector3(hw - 0.02, 0.45, 0), Vector3(0.04, 0.9, D), Basis.IDENTITY, 0.8, 0.6)
	for z in [-hd + 0.1, hd - 0.1]:
		for x in [-hw + 0.1, hw - 0.1]:
			kit.box("timber", Vector3(x, H * 0.5, z), Vector3(0.2, H, 0.2), Basis.IDENTITY, 0.8, 0.6)
	for x in [-1.6, 1.6]:
		kit.box("timber", Vector3(x, H * 0.5, -hd + 0.06), Vector3(0.18, H, 0.12), Basis.IDENTITY, 0.8, 0.6)
	# 南墙：门洞（DOOR_X 处 1.1 × 2.1）与两扇窗（x = -2.4、-0.4，窗台 1.0 米、高 0.9 米）分段拼
	var zs := hd + WALL_T * 0.5
	var door_l := DOOR_X - DOOR_W * 0.5
	var door_r := DOOR_X + DOOR_W * 0.5
	var segs := [[-hw, -2.95], [-1.85, -0.95], [0.15, door_l], [door_r, hw]]
	for sg in segs:
		var a: float = sg[0]
		var b: float = sg[1]
		kit.box("plaster", Vector3((a + b) * 0.5, H * 0.5, zs), Vector3(b - a, H, WALL_T), Basis.IDENTITY, 0.85, 0.7)
	for wx in [-2.4, -0.4]:
		kit.box("plaster", Vector3(wx, 0.5, zs), Vector3(1.1, 1.0, WALL_T), Basis.IDENTITY, 0.8, 0.7)
		kit.box("plaster", Vector3(wx, 2.45, zs), Vector3(1.1, 1.1, WALL_T), Basis.IDENTITY, 0.85, 0.8)
		kit.box("glass_dark", Vector3(wx, 1.45, zs + 0.04), Vector3(1.1, 0.9, 0.04))
		kit.box("timber", Vector3(wx, 1.45, zs - 0.03), Vector3(0.06, 0.9, 0.06))          # 窗棂
		kit.box("timber", Vector3(wx, 1.45, zs - 0.03), Vector3(1.1, 0.06, 0.06))
		kit.box("timber", Vector3(wx, 0.97, zs - 0.08), Vector3(1.2, 0.06, 0.18))          # 窗台
	kit.box("plaster", Vector3(DOOR_X, 2.55, zs), Vector3(DOOR_W, 0.9, WALL_T), Basis.IDENTITY, 0.85, 0.8)
	kit.box("timber", Vector3(DOOR_X, 2.16, zs - 0.06), Vector3(DOOR_W + 0.3, 0.14, 0.12))    # 门楣
	for dx in [door_l - 0.07, door_r + 0.07]:
		kit.box("timber", Vector3(dx, 1.05, zs - 0.06), Vector3(0.14, 2.1, 0.12))


## 西墙壁炉：石砌炉膛 + 炉台 + 一直通到天花板的烟囱壁；炉膛里两根木柴和发光的炭火
static func _fireplace(kit: MeshKit) -> void:
	var x := -W * 0.5
	var z := FIRE_POS.z
	kit.box("stone", Vector3(x + 0.35, H * 0.5, z), Vector3(0.7, H, 2.2), Basis.IDENTITY, 0.85, 0.7)      # 烟囱壁（凸出墙面）
	kit.box("soot", Vector3(x + 0.71, 0.55, z), Vector3(0.04, 1.0, 1.2))                                   # 炉膛口（熏黑的内壁）
	kit.box("stone", Vector3(x + 0.85, 1.12, z), Vector3(0.36, 0.16, 2.3), Basis.IDENTITY, 0.9, 0.8)      # 炉台
	for dz in [-0.75, 0.75]:
		kit.box("stone", Vector3(x + 0.85, 0.52, z + dz), Vector3(0.3, 1.04, 0.3), Basis.IDENTITY, 0.85, 0.6)
	kit.box("stone", Vector3(x + 1.0, 0.04, z), Vector3(0.6, 0.08, 2.0), Basis.IDENTITY, 0.8, 0.7)        # 炉前石台
	for i in 2:
		var a := Vector3(x + 0.85, 0.16 + i * 0.1, z - 0.4)
		kit.cylinder("timber", a, a + Vector3(0, 0, 0.8), 0.07, 0.07, 6, 0.5)
	kit.box("ember", Vector3(x + 0.88, 0.12, z), Vector3(0.3, 0.06, 0.7))
	# 炉台上的小物件：两个陶罐
	for dz in [-0.6, 0.5]:
		kit.cylinder("timber", Vector3(x + 0.85, 1.2, z + dz), Vector3(x + 0.85, 1.42, z + dz), 0.08, 0.06, 6, 0.8)


## 北边吧台（台面 + 立板）与身后的酒架、酒瓶、两只酒桶
static func _bar(kit: MeshKit) -> void:
	var z := -2.15
	kit.box("timber", Vector3(0.5, 0.5, z), Vector3(3.4, 1.0, 0.5), Basis.IDENTITY, 0.8, 0.5)
	kit.box("timber", Vector3(0.5, 1.04, z + 0.02), Vector3(3.6, 0.08, 0.66), Basis.IDENTITY, 1.0, 0.8)
	var wall := -D * 0.5 + 0.18
	for y in [1.15, 1.6, 2.05]:
		kit.box("timber", Vector3(0.5, y, wall), Vector3(3.0, 0.05, 0.3))
		for i in 7:
			var bx := -0.75 + i * 0.4 + (0.07 if int(y * 10) % 2 == 0 else 0.0)
			kit.cylinder("bottle", Vector3(bx, y + 0.025, wall), Vector3(bx, y + 0.3, wall), 0.05, 0.035, 6, 0.9)
	for c in [Vector3(-1.75, 0, -2.95), Vector3(2.85, 0, -2.95)]:
		kit.cylinder("timber", c, c + Vector3(0, 0.95, 0), 0.36, 0.36, 8, 0.85)
		kit.cylinder("timber", c + Vector3(0, 0.95, 0), c + Vector3(0, 0.96, 0), 0.36, 0.01, 8, 0.7)
	# 台面上的两只木杯
	for bx in [-0.4, 1.3]:
		kit.cylinder("timber", Vector3(bx, 1.08, z + 0.05), Vector3(bx, 1.22, z + 0.05), 0.05, 0.05, 6, 0.9)


## 长桌与长凳；窗边的小方桌与两张凳子。中间留出从门口到壁炉的过道
static func _tables(kit: MeshKit) -> void:
	var c := TABLE_POS
	kit.box("timber", c + Vector3(0, 0.76, 0), Vector3(2.4, 0.08, 0.9), Basis.IDENTITY, 1.0, 0.8)
	for lx in [-1.0, 1.0]:
		kit.box("timber", c + Vector3(lx, 0.36, 0), Vector3(0.1, 0.72, 0.7), Basis.IDENTITY, 0.8, 0.5)
	for bz in [-0.72, 0.72]:
		kit.box("timber", c + Vector3(0, 0.44, bz), Vector3(2.2, 0.06, 0.3), Basis.IDENTITY, 0.9, 0.7)
		for lx in [-0.9, 0.9]:
			kit.box("timber", c + Vector3(lx, 0.21, bz), Vector3(0.08, 0.42, 0.24), Basis.IDENTITY, 0.8, 0.5)
	for i in 3:
		var mx := -0.75 + i * 0.7
		kit.cylinder("timber", c + Vector3(mx, 0.8, 0.12 - 0.2 * (i % 2)), c + Vector3(mx, 0.92, 0.12 - 0.2 * (i % 2)), 0.045, 0.045, 6, 0.9)
	kit.box("ember", c + Vector3(0.1, 0.86, 0.0), Vector3(0.05, 0.12, 0.05))           # 桌上的蜡烛（光源另外放）
	var s := SMALL_TABLE_POS
	kit.box("timber", s + Vector3(0, 0.74, 0), Vector3(0.9, 0.06, 0.9), Basis.IDENTITY, 1.0, 0.8)
	kit.box("timber", s + Vector3(0, 0.36, 0), Vector3(0.12, 0.72, 0.12), Basis.IDENTITY, 0.8, 0.5)
	for d in [Vector3(0.7, 0, 0), Vector3(0, 0, -0.7)]:
		kit.box("timber", s + d + Vector3(0, 0.44, 0), Vector3(0.36, 0.06, 0.36), Basis.IDENTITY, 0.9, 0.7)
		kit.box("timber", s + d + Vector3(0, 0.21, 0), Vector3(0.08, 0.42, 0.08), Basis.IDENTITY, 0.8, 0.5)


## 东墙上楼的木梯：14 级台阶（每级高 0.2 米），一直通进天花板上的梯口（黑的，楼上不做）；梯口在梯脚的栅门后面
static func _stairs(kit: MeshKit) -> void:
	var x := W * 0.5 - 0.5
	for i in 14:
		var top := 0.2 * (i + 1)
		var z := 2.4 - i * 0.36
		kit.box("timber", Vector3(x, top - 0.1, z), Vector3(0.9, 0.2, 0.36), Basis.IDENTITY, 0.9, 0.6)
		kit.box("timber", Vector3(x, (top - 0.2) * 0.5, z), Vector3(0.9, maxf(top - 0.2, 0.01), 0.34), Basis.IDENTITY, 0.6, 0.5)
	kit.box("soot", Vector3(x, H - 0.01, -1.6), Vector3(1.0, 0.02, 2.2))                   # 天花板上的梯口
	kit.box("timber", Vector3(x - 0.48, 1.55, 0.2), Vector3(0.06, 0.06, 5.2), Basis(Vector3.RIGHT, deg_to_rad(-29)))   # 扶手
	for i in 4:                                   # 栏杆柱：从台阶面立到扶手
		var z := 2.3 - i * 1.25
		var step_top := 0.2 * (floorf((2.4 - z) / 0.36 + 0.5) + 1.0)
		var rail := 1.55 + (0.2 - z) * 0.556
		kit.box("timber", Vector3(x - 0.48, (step_top + rail) * 0.5, z), Vector3(0.05, rail - step_top, 0.05))


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
	_solid(parent, Vector3(-hw + 0.35, H * 0.5, FIRE_POS.z), Vector3(0.7, H, 2.2))
	_solid(parent, Vector3(-hw + 0.95, 0.55, FIRE_POS.z), Vector3(0.5, 1.1, 2.3))          # 炉台挡住，人走不进火里
	_solid(parent, Vector3(0.5, 0.55, -2.15), Vector3(3.6, 1.1, 0.66))                      # 吧台
	_solid(parent, Vector3(0.5, 1.2, -hd + 0.2), Vector3(3.0, 2.4, 0.4))                    # 酒架
	for c in [Vector3(-1.75, 0.48, -2.95), Vector3(2.85, 0.48, -2.95)]:
		_solid(parent, c, Vector3(0.72, 0.96, 0.72))
	_solid(parent, TABLE_POS + Vector3(0, 0.4, 0), Vector3(2.4, 0.8, 1.74))              # 长桌连长凳
	_solid(parent, SMALL_TABLE_POS + Vector3(0.15, 0.4, -0.15), Vector3(1.3, 0.8, 1.3))  # 小方桌连凳子
	# 楼梯：栅门锁着，上不去；整段楼梯连同梯下的空间当一块实心挡住
	_solid(parent, Vector3(W * 0.5 - 0.5, H * 0.5, -0.1), Vector3(1.0, H, 5.2))


## 光：炉火（暖橙、闪烁）、吧台上方的油灯、长桌上的蜡烛。室内一共 3 盏点光源
static func _lights(parent: Node3D, reduced_motion: bool) -> void:
	var fire := FireLight.new()
	fire.name = "Fire"
	fire.light_color = Color("ff8a3a")
	fire.base = 3.0
	fire.omni_range = 7.5
	fire.omni_attenuation = 1.1
	fire.position = Vector3(-W * 0.5 + 1.1, 0.7, FIRE_POS.z)
	fire.flicker = not reduced_motion
	fire.add_to_group("light_source")
	fire.set_meta("radius", 4.0)
	parent.add_child(fire)
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.4, 1.0)
	var hm := Look.halo(Color("ff8a3a"), 0.5).duplicate() as StandardMaterial3D
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = hm
	halo.mesh = q
	halo.position = Vector3(-W * 0.5 + 0.9, 0.35, FIRE_POS.z)
	parent.add_child(halo)
	var lamp := OmniLight3D.new()
	lamp.name = "BarLamp"
	lamp.light_color = Look.LAMP_COLOR
	lamp.light_energy = 1.7
	lamp.omni_range = 6.0
	lamp.position = Vector3(0.5, 2.4, -1.2)
	parent.add_child(lamp)
	var candle := OmniLight3D.new()
	candle.name = "Candle"
	candle.light_color = Color("ffb060")
	candle.light_energy = 0.9
	candle.omni_range = 3.6
	candle.position = TABLE_POS + Vector3(0.1, 1.15, 0.0)
	parent.add_child(candle)


static func _ember_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("ff7a28")
	return m


static func _bottle_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("2c4a32")
	m.roughness = 0.2
	m.metallic = 0.2
	m.vertex_color_use_as_albedo = true
	return m


static func _soot_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("0e0b09")
	m.roughness = 1.0
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


## 炉火：两个频率叠加的轻微闪烁；减少动态效果时不闪
class FireLight extends OmniLight3D:
	var base := 2.0
	var flicker := true
	var t := 0.0

	func _ready() -> void:
		light_energy = base

	func _process(delta: float) -> void:
		if not flicker:
			light_energy = base
			return
		t += delta
		light_energy = base * (1.0 + sin(t * 9.1) * 0.06 + sin(t * 23.7 + 1.3) * 0.04)
