class_name Churchyard
extends RefCounted
## 星铁小教堂与墓园·外景（路线图 3.2；STORY.md 第三节「破旧礼拜堂、墓碑、守墓人小屋；一处藏物的墓穴」）：原创布局。
## 从主街右手边的小路门过来，站在南边的院门内；一条石板路往北通到小教堂（门通往室内，world/chapel.gd），
## 路两边是墓碑；西边是瓦伦家的石砌墓室（铁门要墓园钥匙，里面藏着埃德里克少爷的包袱），东边是守墓人的小屋，守墓人提着灯站在门外。
## 星铁教会供奉「坠星」（WORLD.md 第四节）：小教堂山墙上挂着一颗拖着尾巴的铁星，是本作原创的标志。
## 雾夜与主街相同（室外）；三盏灯：小教堂门口、守墓人的灯笼、墓室门边的长明灯。人物仍是占位胶囊。
## 坐标：原点在墓园中心，北 = -Z；院门在南墙（z = +11）。

const HALF_X := 13.0
const NORTH := -19.0
const SOUTH := 11.0
const CHAPEL_FRONT := -8.0
const CRYPT := Vector3(-9.0, 0, -2.0)          # 墓室中心；正面朝东（+X），正面墙在 x = -7.25
const CRYPT_FRONT_X := -7.25
const HUT := Vector3(8.5, 0, 2.5)              # 守墓人小屋正面墙脚中点；正面朝西（-X）
const GRAVEDIGGER_POS := Vector3(6.6, 0, 3.6)
const GATE_NAME := "霜渡镇主街"                 # 院门（回主街）
const CHAPEL_NAME := "星铁小教堂"               # 小教堂的门（进室内）
const TREES := [[Vector3(-5.2, 0, 6.6), 51, 5.5], [Vector3(10.6, 0, -11.0), 52, 6.5]]     # 两棵枯树：位置、种子、高
## 命名出生点（world/areas.gd）：lane = 从主街的小路进来，站在院门内、面朝北；chapel_door = 从小教堂出来，站在门前、面朝南
const SPAWNS := {
	"lane": [Vector3(0, 0, 9.4), 0.0],
	"chapel_door": [Vector3(0, 0, -6.4), 180.0],
}
const VIEW_NAMES := ["院门看小教堂", "瓦伦家墓室门前", "守墓人面前", "小教堂门前"]
## 网页 ?area=churchyard&view=N 的固定机位：位置、水平朝向（度，0 = 面朝 -Z，正 = 向左转）、俯仰（度）
const VIEWS := [
	[Vector3(0, 0, 9.4), 0.0, 3.0],
	[Vector3(-5.7, 0, -2.0), 90.0, -10.0],
	[Vector3(4.9, 0, 3.6), -90.0, -8.0],
	[Vector3(0, 0, -6.1), 0.0, 4.0],
]
const BUNDLE_ITEMS := ["bread", "bandage", "edric_letter"]


static func build(parent: Node3D, reduced_motion := false) -> Transform3D:
	var kit := MeshKit.new()
	_ground(parent, kit)
	_walls(parent, kit)
	_graves(parent, kit)
	_crypt(parent, kit)
	_emblem(kit)
	var mi := kit.build({"snow": Look.mat("snow"), "street": Look.mat("street"), "stone": Look.mat("stone"), "timber": Look.mat("timber"),
		"iron": _iron_mat(), "glass_lit": Look.glass_lit(), "halo": Look.halo(Look.LAMP_COLOR, 0.5)})
	mi.name = "Churchyard"
	parent.add_child(mi)
	# 小教堂：石砌、山墙朝院子，门通往室内
	House.build(parent, Vector3(0, 0, CHAPEL_FRONT), 0.0, {"w": 7.0, "d": 9.0, "floors": 1, "stone_upper": true, "roof": "gable",
		"door_x": 0.0, "seed": 41, "lit": 0.8,
		"door": {"name": CHAPEL_NAME, "to_area": "chapel", "to_spawn": "front", "verb": "进入"}})
	# 守墓人小屋：一层、窗里亮着
	House.build(parent, HUT, -90.0, {"w": 4.0, "d": 4.0, "floors": 0, "roof": "eaves", "chimney": true, "door_x": 0.0, "seed": 42, "lit": 1.0,
		"door": {"name": "守墓人的小屋", "text": "门从里面闩上了。守墓人就站在门外，用不着进去。"}})
	for t in TREES:
		BareTree.build(parent, t[0], t[1], t[2])
	Edges.dress(parent, Rect2(-HALF_X, NORTH, HALF_X * 2, SOUTH - NORTH), [         # 墙外是林子，院门外的小路伸回镇上（3.10）
		{"at": Vector3(0, 0, SOUTH), "out": Vector3(0, 0, 1), "half": 1.1}], [], 3612)
	# 院门：回到主街（站在小路门外）
	var gate := Door.make(GATE_NAME, 1.4, 1.9, false)
	gate.verb = "回到"
	gate.to_area = "frostford"
	gate.to_spawn = "chapel_lane"
	gate.position = Vector3(-0.7, 0, SOUTH)
	parent.add_child(gate)
	# 瓦伦家墓室的铁门：要墓园钥匙
	var crypt_door := Door.make("瓦伦家墓室的铁门", 1.0, 2.0, true)
	crypt_door.key_item = "crypt_key"
	crypt_door.locked_text = "铁门锁着。门楣上刻着「瓦伦」，锁眼边上有几道新划痕。"
	crypt_door.position = Vector3(CRYPT_FRONT_X, 0, CRYPT.z + 0.5)
	crypt_door.rotation.y = PI / 2                  # 门板沿 -Z 方向伸出
	parent.add_child(crypt_door)
	Blocks.label(parent, "瓦伦家", Vector3(CRYPT_FRONT_X + 0.1, 2.35, CRYPT.z), 28, 0.006)
	var bundle := LootContainer.make("valen_crypt_bundle", "少爷的包袱", BUNDLE_ITEMS, 6)
	bundle.size = Vector3(0.6, 0.32, 0.45)
	bundle.position = CRYPT + Vector3(0.75, 0, -0.6)
	bundle.rotation.y = 0.3
	parent.add_child(bundle)
	# 守墓人
	var gd := Npc.make("守墓人", [], Color("4a4038"))
	gd.dialogue_area = "churchyard"
	gd.dialogue_id = "gravedigger"
	gd.position = GRAVEDIGGER_POS
	gd.rotation.y = PI / 2                          # 面朝西边的石板路
	parent.add_child(gd)
	_lights(parent, reduced_motion)
	_fog(parent, reduced_motion)
	var s: Array = SPAWNS.lane
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


## 地图（3.11，core/area_map.gd 的格式）：围墙、石板路、小教堂、守墓人小屋、墓室、两片墓地、出口。
## 钥匙、包袱、守墓人都不画；墓室的铁门锁着，不算出口
static func map_spec() -> Dictionary:
	var shapes := [
		{"k": "graves", "rect": Rect2(-HALF_X + 0.8, -6.8, HALF_X - 4.0, 15.6), "label": "墓地"},
		{"k": "graves", "rect": Rect2(3.2, -6.8, HALF_X - 4.0, 15.6)},
		{"k": "road", "rect": Rect2(-1.2, CHAPEL_FRONT, 2.4, SOUTH - CHAPEL_FRONT)},
		{"k": "road", "rect": Rect2(CRYPT_FRONT_X - 1.2, CRYPT.z - 0.8, -CRYPT_FRONT_X + 1.2, 1.6)},
		{"k": "road", "rect": Rect2(1.2, HUT.z - 0.7, HUT.x - 1.2, 1.4)},
		{"k": "wall", "rect": Rect2(-HALF_X - 0.25, NORTH - 0.25, HALF_X * 2 + 0.5, 0.5)},
		{"k": "wall", "rect": Rect2(-HALF_X - 0.25, NORTH, 0.5, SOUTH - NORTH)},
		{"k": "wall", "rect": Rect2(HALF_X - 0.25, NORTH, 0.5, SOUTH - NORTH)},
		{"k": "wall", "rect": Rect2(-HALF_X, SOUTH - 0.25, HALF_X - 0.8, 0.5)},
		{"k": "wall", "rect": Rect2(0.8, SOUTH - 0.25, HALF_X - 0.8, 0.5)},
		{"k": "house", "pts": House.footprint(Vector3(0, 0, CHAPEL_FRONT), 0.0, 7.0, 9.0), "label": CHAPEL_NAME},
		{"k": "house", "pts": House.footprint(HUT, -90.0, 4.0, 4.0)},
		{"k": "house", "rect": Rect2(CRYPT_FRONT_X - 3.5, CRYPT.z - 1.5, 3.5, 3.0), "label": "瓦伦家"},
	]
	for t in TREES:
		var p: Vector3 = t[0]
		shapes.append({"k": "mark", "at": Vector2(p.x, p.z), "icon": "tree"})
	var exits := [
		{"at": Vector2(0, SOUTH), "dir": Vector2(0, 1), "to": "frostford", "spawn": "chapel_lane", "name": GATE_NAME},
		{"at": House.door_xz(Vector3(0, 0, CHAPEL_FRONT), 0.0, 0.0), "dir": -House.facing(0.0), "to": "chapel", "spawn": "front", "name": CHAPEL_NAME},
	]
	return {"bounds": Rect2(-HALF_X, NORTH, HALF_X * 2, SOUTH - NORTH), "shapes": shapes, "exits": exits}


## 雪地（带碰撞）、往北的石板路、通往墓室与小屋的两条岔路
static func _ground(parent: Node3D, kit: MeshKit) -> void:
	kit.box("snow", Vector3(0, -0.1, -4), Vector3(60, 0.2, 60), Basis.IDENTITY, 1.0, 1.0)
	kit.box("street", Vector3(0, 0.0, (SOUTH + CHAPEL_FRONT) * 0.5), Vector3(2.4, 0.02, SOUTH - CHAPEL_FRONT), Basis.IDENTITY, 0.9, 0.9)
	kit.box("street", Vector3((CRYPT_FRONT_X - 1.2) * 0.5, 0.0, CRYPT.z), Vector3(-CRYPT_FRONT_X + 1.2, 0.02, 1.6), Basis.IDENTITY, 0.85, 0.85)
	kit.box("street", Vector3((HUT.x + 1.2) * 0.5, 0.0, HUT.z), Vector3(HUT.x - 1.2, 0.02, 1.4), Basis.IDENTITY, 0.85, 0.85)
	_solid(parent, Vector3(0, -0.1, -4), Vector3(60, 0.2, 60))


## 一圈 1.2 米高的矮石墙（墙头有雪），南墙中间是院门；院门两边两根石柱
static func _walls(parent: Node3D, kit: MeshKit) -> void:
	var h := 1.2
	var t := 0.5
	var segs := [
		[Vector3(0, h * 0.5, NORTH), Vector3(HALF_X * 2 + t, h, t)],
		[Vector3(-HALF_X, h * 0.5, (NORTH + SOUTH) * 0.5), Vector3(t, h, SOUTH - NORTH)],
		[Vector3(HALF_X, h * 0.5, (NORTH + SOUTH) * 0.5), Vector3(t, h, SOUTH - NORTH)],
		[Vector3((-HALF_X - 0.8) * 0.5, h * 0.5, SOUTH), Vector3(HALF_X - 0.8, h, t)],
		[Vector3((HALF_X + 0.8) * 0.5, h * 0.5, SOUTH), Vector3(HALF_X - 0.8, h, t)],
	]
	for sg in segs:
		kit.box("stone", sg[0], sg[1], Basis.IDENTITY, 0.9, 0.5)
		kit.box("snow", sg[0] + Vector3(0, h * 0.5 + 0.04, 0), Vector3(sg[1].x + 0.06, 0.08, sg[1].z + 0.06))
		_solid(parent, sg[0] + Vector3(0, 0.6, 0), sg[1] + Vector3(0, 1.2, 0))      # 碰撞比墙高，翻不过去
	for sx in [-1.0, 1.0]:
		kit.box("stone", Vector3(sx * 0.95, 1.0, SOUTH), Vector3(0.4, 2.0, 0.6), Basis.IDENTITY, 0.9, 0.5)
		kit.box("snow", Vector3(sx * 0.95, 2.04, SOUTH), Vector3(0.46, 0.08, 0.66))
		_solid(parent, Vector3(sx * 0.95, 1.0, SOUTH), Vector3(0.4, 2.0, 0.6))


## 墓碑：路两边几排石碑（有的歪了），碑前一道雪堆；避开墓室、小屋和岔路
static func _graves(parent: Node3D, kit: MeshKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for side in [-1.0, 1.0]:
		var z := 8.4
		while z > -6.5:
			var x := 3.2
			while x < 12.0:
				var p := Vector3(side * (x + rng.randf_range(-0.25, 0.25)), 0, z + rng.randf_range(-0.3, 0.3))
				var skip := false
				if side < 0 and p.x < -6.2 and p.z > -4.4 and p.z < 0.4:
					skip = true            # 墓室
				if side < 0 and p.z > -3.0 and p.z < -1.0:
					skip = true            # 去墓室的岔路
				if side > 0 and p.x > 5.6 and p.z > -0.5 and p.z < 6.0:
					skip = true            # 守墓人小屋与守墓人
				if side > 0 and p.z > 1.6 and p.z < 3.4:
					skip = true            # 去小屋的岔路
				if Vector2(p.x, p.z).distance_to(Vector2(-5.2, 6.6)) < 1.2:
					skip = true            # 枯树
				if not skip and rng.randf() < 0.85:
					_gravestone(parent, kit, p, rng)
				x += 1.9
			z -= 2.3


static func _gravestone(parent: Node3D, kit: MeshKit, p: Vector3, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(0.6, 1.0)
	var w := rng.randf_range(0.45, 0.62)
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(rng.randf_range(-7.0, 7.0))) * Basis(Vector3.FORWARD, deg_to_rad(rng.randf_range(-5.0, 5.0)))
	kit.box("stone", p + Vector3(0, h * 0.5, 0), Vector3(w, h, 0.14), tilt, 0.95, 0.55)
	kit.box("snow", p + Vector3(0, h + 0.03, 0), Vector3(w + 0.04, 0.06, 0.18), tilt)
	kit.box("snow", p + Vector3(0, 0.06, 0.75), Vector3(0.7, 0.14, 1.2))                      # 坟前的雪堆
	if rng.randf() < 0.3:                                                                      # 有的碑上嵌一颗小铁星
		kit.box("iron", p + Vector3(0, h * 0.7, 0.08), Vector3(0.12, 0.12, 0.02), Basis(Vector3.BACK, PI / 4))
	_solid(parent, p + Vector3(0, h * 0.5, 0), Vector3(w, h, 0.2))


## 瓦伦家墓室：石砌小屋（正面朝东、门洞 1 × 2 米），石板人字顶；里面一口石棺，包袱放在门边
static func _crypt(parent: Node3D, kit: MeshKit) -> void:
	var c := CRYPT
	var dx := 3.5         # 进深（x）
	var wz := 3.0         # 宽（z）
	var h := 2.6
	var t := 0.3
	var back_x := CRYPT_FRONT_X - dx
	var parts := [
		[Vector3(back_x + t * 0.5, h * 0.5, c.z), Vector3(t, h, wz)],                                        # 后墙
		[Vector3(c.x, h * 0.5, c.z - wz * 0.5 + t * 0.5), Vector3(dx, h, t)],                                # 南侧墙
		[Vector3(c.x, h * 0.5, c.z + wz * 0.5 - t * 0.5), Vector3(dx, h, t)],                                # 北侧墙
		[Vector3(CRYPT_FRONT_X - t * 0.5, h * 0.5, c.z - 0.5 - (wz * 0.5 - 0.5) * 0.5), Vector3(t, h, wz * 0.5 - 0.5)],   # 正面墙（门的两侧）
		[Vector3(CRYPT_FRONT_X - t * 0.5, h * 0.5, c.z + 0.5 + (wz * 0.5 - 0.5) * 0.5), Vector3(t, h, wz * 0.5 - 0.5)],
		[Vector3(CRYPT_FRONT_X - t * 0.5, 2.3, c.z), Vector3(t, 0.6, 1.0)],                                   # 门楣
	]
	for pt in parts:
		kit.box("stone", pt[0], pt[1], Basis.IDENTITY, 0.9, 0.55)
		_solid(parent, pt[0], pt[1])
	kit.box("stone", Vector3(c.x, h + 0.05, c.z), Vector3(dx + 0.2, 0.1, wz + 0.2))                         # 顶板
	_solid(parent, Vector3(c.x, h + 0.05, c.z), Vector3(dx, 0.1, wz))
	for sz in [-1.0, 1.0]:                                                                                   # 人字顶的两片坡
		kit.box("stone", Vector3(c.x, h + 0.45, c.z + sz * 0.8), Vector3(dx + 0.4, 0.12, 1.9), Basis(Vector3.RIGHT, deg_to_rad(28.0) * -sz), 0.8, 0.6)
		kit.box("snow", Vector3(c.x, h + 0.53, c.z + sz * 0.8), Vector3(dx + 0.42, 0.06, 1.7), Basis(Vector3.RIGHT, deg_to_rad(28.0) * -sz))
	kit.box("stone", Vector3(back_x + 0.75, 0.45, c.z), Vector3(0.9, 0.9, 2.0), Basis.IDENTITY, 0.85, 0.5)     # 石棺
	kit.box("stone", Vector3(back_x + 0.75, 0.95, c.z), Vector3(1.0, 0.1, 2.1))
	_solid(parent, Vector3(back_x + 0.75, 0.5, c.z), Vector3(0.9, 1.0, 2.0))
	kit.box("stone", Vector3(CRYPT_FRONT_X + 0.3, 0.06, c.z), Vector3(0.6, 0.12, 1.4), Basis.IDENTITY, 0.8, 0.6)   # 门前台阶


## 小教堂山墙上的「坠星」：一颗八角铁星，拖着一条斜向下的尾巴（星铁教会的标志，本作原创）
static func _emblem(kit: MeshKit) -> void:
	var c := Vector3(0, 6.7, CHAPEL_FRONT + 0.12)
	kit.cylinder("iron", c, c + Vector3(0, 0, 0.06), 0.2, 0.2, 8, 1.0)
	for i in 8:
		var a := TAU * i / 8.0
		var r := 0.42 if i % 2 == 0 else 0.3
		kit.box("iron", c + Vector3(cos(a), sin(a), 0) * r * 0.55 + Vector3(0, 0, 0.03), Vector3(r, 0.06, 0.04), Basis(Vector3.BACK, a))
	for i in 3:
		var k := float(i + 1)
		kit.box("iron", c + Vector3(0.22 * k, -0.2 * k, 0.03), Vector3(0.3, 0.07 - i * 0.015, 0.04), Basis(Vector3.BACK, deg_to_rad(-42.0)))


## 三盏灯：小教堂门口的壁灯、守墓人的灯笼、瓦伦家墓室门边的长明灯（后两盏挂在立杆上）；都是暖色、会轻微闪烁
static func _lights(parent: Node3D, reduced_motion: bool) -> void:
	for spec in [[Vector3(1.25, 2.55, CHAPEL_FRONT + 0.3), 1.6, 8.0], [GRAVEDIGGER_POS + Vector3(0.9, 1.9, 0.8), 1.4, 7.0],
			[Vector3(CRYPT_FRONT_X + 0.9, 1.5, CRYPT.z + 1.3), 0.9, 5.0]]:
		var kit := MeshKit.new()
		var p: Vector3 = spec[0]
		kit.box("glass_lit", p, Vector3(0.2, 0.28, 0.2), Basis.IDENTITY, 1.0, 1.0, true)
		kit.box("timber", p + Vector3(0, 0.17, 0), Vector3(0.26, 0.05, 0.26))
		if p.z > CHAPEL_FRONT + 1.0:       # 守墓人的灯：立杆
			kit.box("timber", Vector3(p.x, p.y * 0.5, p.z), Vector3(0.1, p.y + 0.3, 0.1), Basis.IDENTITY, 0.8, 0.5)
		parent.add_child(kit.build({"glass_lit": Look.glass_lit(), "timber": Look.mat("timber")}))
		var halo := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.2, 1.2)
		var hm := Look.halo(Look.LAMP_COLOR, 0.55).duplicate() as StandardMaterial3D
		hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		q.material = hm
		halo.mesh = q
		halo.position = p
		parent.add_child(halo)
		var l := Tavern.FireLight.new()
		l.light_color = Look.LAMP_COLOR
		l.base = float(spec[1])
		l.omni_range = float(spec[2])
		l.omni_attenuation = 1.2
		l.position = p + Vector3(0, -0.15, 0.1)
		l.flicker = not reduced_motion
		l.add_to_group("light_source")
		l.set_meta("radius", 5.0)
		Daypart.mark_night_light(l, halo)         # 白天灭掉（4.2）
		parent.add_child(l)


## 贴地雾带：墓碑之间几片（低画质时由 main 隐藏一半）
static func _fog(parent: Node3D, reduced_motion: bool) -> void:
	var root := Node3D.new()
	root.name = "FogBands"
	parent.add_child(root)
	var i := 0
	for z in [8.0, 2.0, -4.0, -10.0]:
		for x in [-7.0, 0.0, 7.0]:
			var mi := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(8.0, 7.0)
			mi.mesh = pm
			mi.material_override = Look.fog_material(0.55, reduced_motion)
			mi.position = Vector3(x, 0.35 + (i % 2) * 0.25, z)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.set_meta("fog_index", i)
			mi.add_to_group("fog_band")
			root.add_child(mi)
			i += 1


static func _iron_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("2e3034")
	m.metallic = 0.5
	m.roughness = 0.5
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
