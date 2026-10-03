class_name Chapel
extends RefCounted
## 星铁小教堂·内部（路线图 3.2；STORY.md 第三节「破旧礼拜堂」）：原创布局。
## 一间 6 × 10 米、5 米高的石砌中殿：木屋架、两列长椅夹着中间的走道、北端高一级的祭坛台，祭坛后墙挂着「坠星」铁徽（星铁教会的标志，本作原创），
## 两侧墙上的高窄窗透进一点冷月光，西墙一排旧书架（守着教会旧书的奥尔本修士，见 STORY.md 人物表）。
## 光：祭坛两边的烛台（两盏暖色点光源，轻微闪烁）+ 门边一盏油灯。人物仍是占位胶囊。
## 坐标：原点在中殿地面中心，北 = -Z；出口门在南墙（z = +5）。

const W := 6.0
const D := 10.0
const H := 5.0
const WALL_T := 0.3
const DOOR_W := 1.2
const ALTAR_Z := -4.0
const ALBAN_POS := Vector3(1.3, 0, -2.75)        # 祭坛台前、长椅前排的右手边
## 命名出生点（world/areas.gd）：front = 从墓园进门，站在门内、面朝祭坛（-Z）
const SPAWNS := {
	"front": [Vector3(0, 0, 4.1), 0.0],
}
const VIEW_NAMES := ["进门看祭坛", "奥尔本修士面前", "看坠星铁徽", "门内对着出口"]
## 网页 ?area=chapel&view=N 的固定机位：位置、水平朝向（度，0 = 面朝 -Z，正 = 向左转）、俯仰（度）
const VIEWS := [
	[Vector3(0, 0, 4.1), 0.0, 4.0],
	[Vector3(0.0, 0, -2.4), -75.0, -12.0],
	[Vector3(0, 0, -1.0), 0.0, 22.0],
	[Vector3(0, 0, 3.4), 180.0, -8.0],
]


static func build(parent: Node3D, reduced_motion := false) -> Transform3D:
	var kit := MeshKit.new()
	_room(kit)
	_pews(kit)
	_altar(kit)
	_books(kit)
	var mi := kit.build({"stone": Look.mat("stone"), "timber": Look.mat("timber"), "street": Look.mat("street"),
		"moon": _moon_glass(), "iron": _iron_mat(), "ember": _flame_mat(), "cloth": _cloth_mat(), "book": _book_mat()})
	mi.name = "Chapel"
	parent.add_child(mi)
	_colliders(parent)
	_lights(parent, reduced_motion)
	var exit := Door.make("回到墓园", DOOR_W, 2.4, false)
	exit.verb = "离开"
	exit.to_area = "churchyard"
	exit.to_spawn = "chapel_door"
	exit.position = Vector3(-DOOR_W * 0.5, 0, D * 0.5 - 0.02)
	parent.add_child(exit)
	var alban := Npc.make("奥尔本修士", [], Color("3a3a4a"))
	alban.dialogue_area = "chapel"
	alban.dialogue_id = "alban"
	alban.position = ALBAN_POS
	alban.rotation.y = PI                        # 面朝中殿（+Z）
	parent.add_child(alban)
	var s: Array = SPAWNS.front
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


## 石板地、石墙（南墙留门、东西墙各三扇高窄窗）、木屋架与檩条
static func _room(kit: MeshKit) -> void:
	var hw := W * 0.5
	var hd := D * 0.5
	kit.box("street", Vector3(0, -0.05, 0), Vector3(W, 0.1, D), Basis.IDENTITY, 0.8, 0.8)
	kit.box("stone", Vector3(0, H * 0.5, -hd - WALL_T * 0.5), Vector3(W + WALL_T * 2, H, WALL_T), Basis.IDENTITY, 0.85, 0.55)
	for sx in [-1.0, 1.0]:
		var x: float = sx * (hw + WALL_T * 0.5)
		# 墙分段：窗洞之间的墙垛 + 窗下墙 + 窗上墙（窗在 z = -2.5、0.5、3.0，宽 0.7、窗台 1.8、高 2.0）
		var wins := [-2.5, 0.5, 3.0]
		var edges := [-hd]
		for wz in wins:
			edges.append(wz - 0.35)
			edges.append(wz + 0.35)
		edges.append(hd)
		for i in range(0, edges.size(), 2):
			var a: float = edges[i]
			var b: float = edges[i + 1]
			kit.box("stone", Vector3(x, H * 0.5, (a + b) * 0.5), Vector3(WALL_T, H, b - a), Basis.IDENTITY, 0.85, 0.55)
		for wz in wins:
			kit.box("stone", Vector3(x, 0.9, wz), Vector3(WALL_T, 1.8, 0.7), Basis.IDENTITY, 0.8, 0.55)
			kit.box("stone", Vector3(x, 4.4, wz), Vector3(WALL_T, 1.2, 0.7), Basis.IDENTITY, 0.85, 0.8)
			kit.box("moon", Vector3(x + sx * 0.06, 2.8, wz), Vector3(0.04, 2.0, 0.7))
			kit.box("stone", Vector3(x - sx * 0.12, 1.75, wz), Vector3(0.18, 0.1, 0.8))          # 窗台
	# 南墙：门洞（宽 1.2、高 2.4）
	var zs := hd + WALL_T * 0.5
	var side := (W + WALL_T * 2 - DOOR_W) * 0.5
	for sx in [-1.0, 1.0]:
		kit.box("stone", Vector3(sx * (DOOR_W * 0.5 + side * 0.5), H * 0.5, zs), Vector3(side, H, WALL_T), Basis.IDENTITY, 0.85, 0.55)
	kit.box("stone", Vector3(0, (H + 2.4) * 0.5, zs), Vector3(DOOR_W, H - 2.4, WALL_T), Basis.IDENTITY, 0.85, 0.8)
	# 木屋架：每 2 米一榀（两根斜梁 + 一根拉梁），中间一根脊檩
	for z in [-4.0, -2.0, 0.0, 2.0, 4.0]:
		kit.box("timber", Vector3(0, H - 0.1, z), Vector3(W, 0.22, 0.22), Basis.IDENTITY, 0.6, 0.5)
		for sx in [-1.0, 1.0]:
			kit.box("timber", Vector3(sx * hw * 0.5, H + 0.75, z), Vector3(hw * 1.15, 0.2, 0.2), Basis(Vector3.BACK, deg_to_rad(-27.0) * sx), 0.6, 0.5)
	kit.box("timber", Vector3(0, H + 1.5, 0), Vector3(0.22, 0.22, D), Basis.IDENTITY, 0.6, 0.5)
	for sx in [-1.0, 1.0]:                                                                     # 两面坡的木望板
		kit.box("timber", Vector3(sx * hw * 0.5, H + 0.85, 0), Vector3(hw * 1.2, 0.06, D), Basis(Vector3.BACK, deg_to_rad(-27.0) * sx), 0.45, 0.45)
	kit.box("stone", Vector3(0, H + 0.75, hd + WALL_T * 0.5), Vector3(W, 1.5, WALL_T), Basis.IDENTITY, 0.6, 0.6)   # 山墙（三角形用矩形近似，屋架挡着）
	kit.box("stone", Vector3(0, H + 0.75, -hd - WALL_T * 0.5), Vector3(W, 1.5, WALL_T), Basis.IDENTITY, 0.6, 0.6)


## 两列长椅（中间留 1.2 米走道），每列 5 排
static func _pews(kit: MeshKit) -> void:
	for sx in [-1.0, 1.0]:
		for i in 5:
			var z := 2.6 - i * 1.1
			var c := Vector3(sx * 1.65, 0, z)
			kit.box("timber", c + Vector3(0, 0.45, 0), Vector3(2.1, 0.06, 0.4), Basis.IDENTITY, 0.95, 0.75)
			kit.box("timber", c + Vector3(0, 0.75, 0.2), Vector3(2.1, 0.6, 0.05), Basis.IDENTITY, 0.85, 0.6)
			for lx in [-0.95, 0.95]:
				kit.box("timber", c + Vector3(lx, 0.4, 0.05), Vector3(0.06, 0.8, 0.45), Basis.IDENTITY, 0.8, 0.5)


## 祭坛：高一级的石台、石砌祭台、铺着布，两座三枝烛台；后墙上的「坠星」铁徽
static func _altar(kit: MeshKit) -> void:
	var hd := D * 0.5
	kit.box("stone", Vector3(0, 0.1, (ALTAR_Z - 0.6 - hd) * 0.5), Vector3(W, 0.2, hd + ALTAR_Z + 0.6), Basis.IDENTITY, 0.9, 0.7)   # 祭坛台
	kit.box("stone", Vector3(0, 0.7, ALTAR_Z), Vector3(1.8, 1.0, 0.8), Basis.IDENTITY, 0.85, 0.55)
	kit.box("cloth", Vector3(0, 1.22, ALTAR_Z), Vector3(1.9, 0.04, 0.9))
	kit.box("cloth", Vector3(0, 0.95, ALTAR_Z + 0.44), Vector3(0.7, 0.55, 0.02))
	for sx in [-1.0, 1.0]:
		var b := Vector3(sx * 1.6, 0.2, ALTAR_Z + 0.2)
		kit.cylinder("iron", b, b + Vector3(0, 1.3, 0), 0.04, 0.03, 6, 0.9)
		kit.cylinder("iron", b, b + Vector3(0, 0.06, 0), 0.22, 0.2, 8, 0.8)
		for dx in [-0.18, 0.0, 0.18]:
			var top := b + Vector3(dx, 1.3 + (0.08 if dx == 0.0 else 0.0), 0)
			kit.box("iron", top + Vector3(-dx * 0.5, -0.04, 0), Vector3(absf(dx) + 0.03, 0.03, 0.03))
			kit.cylinder("cloth", top, top + Vector3(0, 0.16, 0), 0.025, 0.025, 6, 1.0)
			kit.box("ember", top + Vector3(0, 0.2, 0), Vector3(0.025, 0.05, 0.025))
	# 坠星：八角铁星 + 斜向下的尾巴，挂在祭坛后墙上（和墓园山墙上那颗一样）
	var c := Vector3(0, 3.1, -hd + 0.03)
	kit.cylinder("iron", c, c + Vector3(0, 0, 0.08), 0.32, 0.32, 8, 1.0)
	for i in 8:
		var a := TAU * i / 8.0
		var r := 0.75 if i % 2 == 0 else 0.5
		kit.box("iron", c + Vector3(cos(a), sin(a), 0) * r * 0.55 + Vector3(0, 0, 0.04), Vector3(r, 0.1, 0.06), Basis(Vector3.BACK, a))
	for i in 3:
		var k := float(i + 1)
		kit.box("iron", c + Vector3(0.38 * k, -0.34 * k, 0.04), Vector3(0.5, 0.11 - i * 0.025, 0.06), Basis(Vector3.BACK, deg_to_rad(-42.0)))


## 西墙的旧书架（STORY.md：奥尔本修士守着教会的旧书）
static func _books(kit: MeshKit) -> void:
	var x := -W * 0.5 + 0.25
	var z := -2.5
	kit.box("timber", Vector3(x, 1.1, z + 1.6), Vector3(0.4, 2.2, 1.4), Basis.IDENTITY, 0.8, 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for y in [0.45, 0.95, 1.45, 1.95]:
		var bz := z + 1.0
		while bz < z + 2.2:
			var bw := rng.randf_range(0.05, 0.12)
			var bh := rng.randf_range(0.26, 0.38)
			kit.box("book", Vector3(x + 0.05, y + bh * 0.5, bz + bw * 0.5), Vector3(0.28, bh, bw), Basis(Vector3.RIGHT, rng.randf_range(-0.08, 0.08)), 0.9, 0.7)
			bz += bw + 0.01


static func _colliders(parent: Node3D) -> void:
	var hw := W * 0.5
	var hd := D * 0.5
	_solid(parent, Vector3(0, -0.1, 0), Vector3(W + 1, 0.2, D + 1))
	_solid(parent, Vector3(0, H + 0.1, 0), Vector3(W + 1, 0.2, D + 1))
	_solid(parent, Vector3(0, H * 0.5, -hd - WALL_T * 0.5), Vector3(W + 1, H, WALL_T))
	for sx in [-1.0, 1.0]:
		_solid(parent, Vector3(sx * (hw + WALL_T * 0.5), H * 0.5, 0), Vector3(WALL_T, H, D + 1))
	var side := (W + WALL_T * 2 - DOOR_W) * 0.5
	for sx in [-1.0, 1.0]:
		_solid(parent, Vector3(sx * (DOOR_W * 0.5 + side * 0.5), H * 0.5, hd + WALL_T * 0.5), Vector3(side, H, WALL_T))
	_solid(parent, Vector3(0, H * 0.5, hd + WALL_T + 0.1), Vector3(DOOR_W, H, 0.1))           # 门外：出门靠交互
	for sx in [-1.0, 1.0]:
		_solid(parent, Vector3(sx * 1.65, 0.5, 0.4), Vector3(2.1, 1.0, 5.0))                   # 两列长椅
	_solid(parent, Vector3(0, 0.7, ALTAR_Z), Vector3(1.8, 1.4, 0.8))                           # 祭台（祭坛台高 0.2，能走上去）
	_solid(parent, Vector3(-W * 0.5 + 0.25, 1.1, -0.9), Vector3(0.45, 2.2, 1.4))               # 书架
	for sx in [-1.0, 1.0]:
		_solid(parent, Vector3(sx * 1.6, 0.85, ALTAR_Z + 0.2), Vector3(0.45, 1.3, 0.45))       # 烛台


## 光：祭坛两边的烛火（闪烁）、门边的油灯；一共 3 盏点光源
static func _lights(parent: Node3D, reduced_motion: bool) -> void:
	for sx in [-1.0, 1.0]:
		var l := Tavern.FireLight.new()
		l.light_color = Color("ffb35a")
		l.base = 2.0
		l.omni_range = 7.5
		l.omni_attenuation = 1.1
		l.position = Vector3(sx * 1.6, 1.75, ALTAR_Z + 0.4)
		l.flicker = not reduced_motion
		parent.add_child(l)
	var lamp := OmniLight3D.new()
	lamp.light_color = Look.LAMP_COLOR
	lamp.light_energy = 1.3
	lamp.omni_range = 6.5
	lamp.position = Vector3(1.4, 2.4, D * 0.5 - 0.6)
	parent.add_child(lamp)


## 高窄窗：冷蓝色、自己发一点光（不加点光源），像窗外的月光
static func _moon_glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("3c5a7e")
	return m


static func _iron_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("2e3034")
	m.metallic = 0.55
	m.roughness = 0.45
	m.vertex_color_use_as_albedo = true
	return m


static func _flame_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("ffc070")
	return m


## 祭坛布与蜡烛：旧白色
static func _cloth_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("c8bea8")
	m.roughness = 0.9
	m.vertex_color_use_as_albedo = true
	return m


static func _book_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("5a3a2a")
	m.roughness = 0.85
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
