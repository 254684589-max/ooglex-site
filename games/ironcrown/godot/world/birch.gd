class_name Birch
extends RefCounted
## 镇外桦林（路线图 3.5；STORY.md 第三节「镇外桦林：枯桦、雪地、营火；无旗者强盗营地」「去渡口的近路穿过桦林，遭遇无旗者的哨卡」）：原创布局。
## 一条往南的林间小路（踩实的雪），两边是白桦林；路中间偏南是无旗者的哨卡：路边的营火、横在路上的拒马、营火后面的窝棚和木箱。
## 三个无旗者守着哨卡（两个棍手、一个头目），头目身上有那封盖双钥印的雇佣信（items.json hire_letter）。
## 北头的木门回霜渡镇（主街南门），南头是去渡口的路（渡口在 3.6，现在走不过去，提示说明）。
## 白桦是代码搭的（细长的树干 + 树梢几根枝条，树皮是 Look.birch() 画出来的贴图），整片树林合成一个网格；每棵树一个圆柱碰撞体（敌人寻路会绕开）。
## 坐标：原点在哨卡附近的路中间，北 = -Z（回镇上），南 = +Z（去渡口）。

const HALF_X := 18.0
const NORTH := -36.0
const SOUTH := 36.0
const ROAD_HALF := 1.7
const FIRE_POS := Vector3(-3.6, 0, 2.0)
const CAMP_POS := Vector3(-7.4, 0, 0.6)           # 窝棚（开口朝东，对着营火）
const CHEST_POS := Vector3(-6.2, 0, 3.4)
const CHEST_ITEMS := ["bread", "bandage", "strong_spirit"]
const BARRICADE_Z := 6.0
## 守哨卡的无旗者：[种类, 编号, 巡逻点...]
const ENEMIES := [
	["outlaw_leader", "birch_leader", [Vector3(-2.6, 0, 0.6), Vector3(-2.4, 0, 3.6)]],
	["clubber", "birch_a", [Vector3(0.9, 0, -5.5), Vector3(0.9, 0, 4.4)]],
	["clubber", "birch_b", [Vector3(6.0, 0, -1.5), Vector3(6.5, 0, 7.0)]],
]
## 命名出生点（world/areas.gd）：north = 从霜渡镇南门出来，站在桦林北头、面朝南
const SPAWNS := {
	"north": [Vector3(0, 0, NORTH + 3.2), 180.0],
}
const VIEW_NAMES := ["北头看林间小路", "走近哨卡", "营火边", "南头去渡口的路"]
## 网页 ?area=birch&view=N 的固定机位：位置、水平朝向（度，0 = 面朝 -Z，正 = 向左转）、俯仰（度）
const VIEWS := [
	[Vector3(0, 0, NORTH + 3.2), 180.0, -2.0],
	[Vector3(0.4, 0, -9.0), 180.0, -4.0],
	[Vector3(-0.6, 0, 7.6), 30.0, -10.0],
	[Vector3(0, 0, SOUTH - 3.2), 180.0, -4.0],
]
const TEACH_DESKTOP := "桦林：前面有火光，是无旗者的哨卡。左键 / F 出剑，按住是重击 · 右键 / Q 格挡 · 对方劈下前一瞬间格挡 = 完美格挡 · 跑、出剑、格挡都耗体力 · 蹲下（C）走得悄悄的"
const TEACH_TOUCH := "桦林：前面有火光，是无旗者的哨卡。点「攻」出剑，按住是重击 · 按住「挡」格挡 · 对方劈下前一瞬间格挡 = 完美格挡 · 跑、出剑、格挡都耗体力 · 「蹲」走得悄悄的"


static func build(parent: Node3D, reduced_motion := false) -> Transform3D:
	var kit := MeshKit.new()
	_ground(kit)
	_camp(kit, parent)
	_trees(kit, parent)
	_gates(kit, parent)
	var mi := kit.build({"snow": Look.mat("snow"), "timber": Look.mat("timber"), "bark": Look.mat("bark"), "birch": Look.birch(),
		"stone": Look.mat("stone"), "ember": _ember_mat(), "canvas": _canvas_mat()})
	mi.name = "Birch"
	parent.add_child(mi)
	_solid(parent, Vector3(0, -0.1, 0), Vector3(HALF_X * 2 + 6, 0.2, SOUTH - NORTH + 6))     # 地面（有厚度：导航网格贴着地面）
	_bounds(parent)
	_fire(parent, reduced_motion)
	_fog(parent, reduced_motion)
	var chest := LootContainer.make("birch_chest", "哨卡的木箱", CHEST_ITEMS, 4)
	chest.position = CHEST_POS
	chest.rotation.y = PI / 2
	parent.add_child(chest)
	for row in ENEMIES:
		var route: Array = row[2]
		var e := Enemy.make(row[0], row[1], route)
		e.position = route[0]
		parent.add_child(e)
	var s: Array = SPAWNS.north
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


## 雪地（比区域大一圈）+ 往南的林间小路（踩实的雪，颜色暗一点）+ 路边被踩乱的雪
static func _ground(kit: MeshKit) -> void:
	kit.box("snow", Vector3(0, -0.01, 0), Vector3(HALF_X * 2 + 6, 0.02, SOUTH - NORTH + 6), Basis.IDENTITY, 1.0, 1.0)
	kit.box("snow", Vector3(0, 0.005, 0), Vector3(ROAD_HALF * 2, 0.02, SOUTH - NORTH), Basis.IDENTITY, 0.62, 0.62)
	for z in range(int(NORTH) + 2, int(SOUTH) - 1, 4):
		var w := 0.5 + absf(sin(z * 1.7)) * 0.6
		for sx in [-1.0, 1.0]:
			kit.box("snow", Vector3(sx * (ROAD_HALF + w * 0.5), 0.008, z + 1.0), Vector3(w, 0.02, 3.6), Basis.IDENTITY, 0.8, 0.8)
	# 营火边踩出来的一片
	kit.box("snow", FIRE_POS + Vector3(-0.8, 0.007, 0.0), Vector3(6.0, 0.02, 5.4), Basis(Vector3.UP, 0.2), 0.7, 0.7)


## 哨卡：营火（一圈石头、交叉的柴、火）、两截当凳子的原木、营火后的窝棚、横在路上的拒马
static func _camp(kit: MeshKit, parent: Node3D) -> void:
	for i in 9:
		var a := TAU * i / 9.0
		kit.box("stone", FIRE_POS + Vector3(cos(a) * 0.55, 0.1, sin(a) * 0.55), Vector3(0.24, 0.2, 0.2), Basis(Vector3.UP, -a), 0.9, 0.6)
	for i in 4:
		var a := PI * i / 4.0
		var d := Vector3(cos(a), 0, sin(a)) * 0.38
		kit.cylinder("bark", FIRE_POS - d + Vector3(0, 0.05, 0), FIRE_POS + d + Vector3(0, 0.22, 0), 0.05, 0.05, 5, 0.6)
	kit.box("ember", FIRE_POS + Vector3(0, 0.22, 0), Vector3(0.36, 0.28, 0.36), Basis(Vector3.UP, 0.4))
	kit.box("ember", FIRE_POS + Vector3(0.05, 0.42, -0.03), Vector3(0.18, 0.26, 0.18), Basis(Vector3.UP, 1.1))
	_solid(parent, FIRE_POS + Vector3(0, 0.2, 0), Vector3(1.2, 0.4, 1.2))
	for lg in [[FIRE_POS + Vector3(1.4, 0.22, -0.6), 0.3], [FIRE_POS + Vector3(-0.2, 0.22, 1.5), 1.4]]:
		var c: Vector3 = lg[0]
		var b := Basis(Vector3.UP, float(lg[1]))
		kit.cylinder("bark", c - b.x * 0.8, c + b.x * 0.8, 0.22, 0.2, 7, 0.8)
		_solid(parent, c, Vector3(1.6, 0.44, 0.44) if absf(b.x.x) > 0.7 else Vector3(0.44, 0.44, 1.6))
	# 窝棚：两根立柱 + 横梁，斜搭的木板顶，帆布挡着背风的一面
	var cp := CAMP_POS
	for dz in [-1.3, 1.3]:
		kit.box("timber", cp + Vector3(0.9, 0.9, dz), Vector3(0.14, 1.8, 0.14), Basis.IDENTITY, 0.8, 0.5)
	kit.box("timber", cp + Vector3(0.9, 1.82, 0), Vector3(0.16, 0.14, 2.9))
	kit.box("timber", cp + Vector3(0.0, 1.0, 0), Vector3(2.1, 0.08, 2.9), Basis(Vector3.BACK, deg_to_rad(-38.0)), 0.9, 0.6)
	kit.box("canvas", cp + Vector3(-0.75, 0.55, 0), Vector3(0.06, 1.1, 2.8), Basis.IDENTITY, 0.8, 0.5)
	kit.box("canvas", cp + Vector3(0.1, 0.12, 0.1), Vector3(1.3, 0.12, 2.0), Basis.IDENTITY, 0.7, 0.6)      # 铺在地上的毯子
	_solid(parent, cp + Vector3(0.05, 0.9, 0), Vector3(1.9, 1.8, 2.9))
	# 拒马：三副交叉的木桩，横在路上（人从两边的林子绕过去）
	for i in 3:
		var x := -1.2 + i * 1.2
		for s in [-1.0, 1.0]:
			kit.cylinder("bark", Vector3(x - 0.5, 0.0, BARRICADE_Z + s * 0.45), Vector3(x + 0.5, 1.15, BARRICADE_Z - s * 0.45), 0.07, 0.05, 5, 0.75)
	kit.cylinder("bark", Vector3(-1.9, 0.6, BARRICADE_Z), Vector3(1.9, 0.6, BARRICADE_Z), 0.09, 0.09, 6, 0.8)
	_solid(parent, Vector3(0, 0.6, BARRICADE_Z), Vector3(3.8, 1.2, 1.0))


## 白桦林：随机撒在路两边（固定种子，避开路、哨卡和两头的门），每棵一个碰撞体；还有几截倒在雪里的枯木
static func _trees(kit: MeshKit, parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3505
	var placed: Array = []
	var tries := 0
	while placed.size() < 96 and tries < 4000:
		tries += 1
		var p := Vector3(rng.randf_range(-HALF_X + 1.0, HALF_X - 1.0), 0, rng.randf_range(NORTH + 4.0, SOUTH - 4.0))
		if absf(p.x) < ROAD_HALF + 1.2 or (absf(p.x) < 3.2 and (p.z < NORTH + 5.0 or p.z > SOUTH - 5.0)):
			continue
		if Vector2(p.x - FIRE_POS.x, p.z - FIRE_POS.z).length() < 4.6 or Vector2(p.x - CAMP_POS.x, p.z - CAMP_POS.z).length() < 3.0:
			continue
		if Vector2(p.x - 6.2, p.z - 2.8).length() < 2.6:          # 东边那个棍手的巡逻路线
			continue
		var ok := true
		for q in placed:
			if Vector2(p.x - q.x, p.z - q.z).length() < 2.0:
				ok = false
				break
		if not ok:
			continue
		placed.append(p)
		var h := rng.randf_range(7.0, 10.5)
		var r := rng.randf_range(0.12, 0.2)
		var lean := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		var top := p + Vector3(0, h, 0) + lean
		kit.cylinder("birch", p + Vector3(0, -0.1, 0), p + (top - p) * 0.55, r, r * 0.75, 7, 1.0)
		kit.cylinder("birch", p + (top - p) * 0.55, top, r * 0.75, r * 0.25, 6, 1.0)
		for k in rng.randi_range(4, 6):                        # 树梢的枝条：往上斜着长，细而黑
			var at := p + (top - p) * rng.randf_range(0.55, 0.92)
			var ang := rng.randf() * TAU
			var dir := Vector3(cos(ang), rng.randf_range(0.6, 1.2), sin(ang)).normalized()
			var l := rng.randf_range(1.2, 2.6)
			var mid := at + dir * l * 0.6
			kit.cylinder("bark", at, mid, r * 0.3, r * 0.18, 4, 0.7)
			kit.cylinder("bark", mid, mid + (dir + Vector3(rng.randf_range(-0.4, 0.4), 0.3, rng.randf_range(-0.4, 0.4))).normalized() * l * 0.5, r * 0.18, 0.01, 4, 0.7)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = p + Vector3(0, 1.5, 0)
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = r + 0.05
		cyl.height = 3.0
		cs.shape = cyl
		body.add_child(cs)
		parent.add_child(body)
	# 倒在雪里的枯木（路东边两截、西边一截）
	for spec in [[Vector3(8.5, 0.2, -14.0), 0.5, 4.0], [Vector3(11.0, 0.2, 15.0), 2.2, 3.2], [Vector3(-10.5, 0.2, -20.0), 1.1, 3.6]]:
		var c: Vector3 = spec[0]
		var d := Vector3(cos(float(spec[1])), 0, sin(float(spec[1]))) * float(spec[2]) * 0.5
		kit.cylinder("birch", c - d, c + d, 0.2, 0.16, 7, 0.75)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = c
		body.rotation.y = -float(spec[1])
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(float(spec[2]), 0.4, 0.4)
		cs.shape = bs
		body.add_child(cs)
		parent.add_child(body)


## 两头的门：北头回霜渡镇（主街南门的外面）；南头是去渡口的路，渡口还没开放（3.6），走不过去，提示说明
static func _gates(kit: MeshKit, parent: Node3D) -> void:
	for spec in [[NORTH + 0.6, "回霜渡镇的木门", false], [SOUTH - 0.6, "去渡口的路", true]]:
		var z: float = spec[0]
		for sx in [-1.0, 1.0]:
			kit.box("timber", Vector3(sx * 1.05, 1.2, z), Vector3(0.2, 2.4, 0.2), Basis.IDENTITY, 0.85, 0.5)
		kit.box("timber", Vector3(0, 2.36, z), Vector3(2.5, 0.16, 0.2))
		var gate := Door.make(str(spec[1]), 1.9, 2.0, bool(spec[2]))
		gate.position = Vector3(-0.95, 0, z)
		if spec[2]:
			gate.locked_text = "雾越来越浓，再往前就是渡口了。（渡口在后续版本开放）"
		else:
			gate.verb = "回到"
			gate.to_area = "frostford"
			gate.to_spawn = "south_gate"
		parent.add_child(gate)
	Blocks.label(parent, "霜渡镇", Vector3(0, 2.75, NORTH + 0.6))
	Blocks.label(parent, "渡口", Vector3(0, 2.75, SOUTH - 0.6))
	# 门柱上各挂一盏风灯：门在月光的背面，不点灯就是一块黑板
	for p in [Vector3(1.25, 1.9, NORTH + 0.85), Vector3(1.25, 1.9, SOUTH - 0.85)]:
		kit.box("ember", p, Vector3(0.18, 0.24, 0.18))
		kit.box("timber", p + Vector3(0, 0.15, 0), Vector3(0.24, 0.05, 0.24))
		var l := Tavern.FireLight.new()
		l.light_color = Look.LAMP_COLOR
		l.base = 1.2
		l.omni_range = 6.0
		l.omni_attenuation = 1.2
		l.position = p + Vector3(0, 0, (1.0 if p.z < 0 else -1.0) * 0.5)
		parent.add_child(l)


## 看不见的围墙：走不出这片林子（两头靠门）
static func _bounds(parent: Node3D) -> void:
	var len_z := SOUTH - NORTH
	for w in [[Vector3(HALF_X * 2, 6, 0.4), Vector3(0, 3, NORTH - 0.2)], [Vector3(HALF_X * 2, 6, 0.4), Vector3(0, 3, SOUTH + 0.2)],
			[Vector3(0.4, 6, len_z), Vector3(HALF_X + 0.2, 3, 0)], [Vector3(0.4, 6, len_z), Vector3(-HALF_X - 0.2, 3, 0)]]:
		_solid(parent, w[1], w[0])


## 营火的光：暖色、闪烁，组 light_source（站在火光里，远处的人也看得见你）
static func _fire(parent: Node3D, reduced_motion: bool) -> void:
	var l := Tavern.FireLight.new()
	l.light_color = Color("ff8a3a")
	l.base = 2.6
	l.omni_range = 11.0
	l.omni_attenuation = 1.1
	l.position = FIRE_POS + Vector3(0, 0.9, 0)
	l.flicker = not reduced_motion
	l.add_to_group("light_source")
	l.set_meta("radius", 7.0)
	parent.add_child(l)
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.4, 2.4)
	var hm := Look.halo(Look.LAMP_COLOR, 0.6).duplicate() as StandardMaterial3D
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = hm
	halo.mesh = q
	halo.position = FIRE_POS + Vector3(0, 0.55, 0)
	parent.add_child(halo)


## 贴地雾带：沿着小路一串（低画质时由 main 隐藏一半）
static func _fog(parent: Node3D, reduced_motion: bool) -> void:
	var root := Node3D.new()
	root.name = "FogBands"
	parent.add_child(root)
	var i := 0
	for z in range(int(NORTH) + 4, int(SOUTH), 7):
		for x in [-8.0, 0.0, 8.0]:
			var mi := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(9.0, 7.5)
			mi.mesh = pm
			mi.material_override = Look.fog_material(0.6, reduced_motion)
			mi.position = Vector3(x, 0.35 + (i % 2) * 0.3, float(z))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.set_meta("fog_index", i)
			mi.add_to_group("fog_band")
			root.add_child(mi)
			i += 1


static func _ember_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("ff9a40")
	return m


static func _canvas_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("5a5040")
	m.roughness = 0.95
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
