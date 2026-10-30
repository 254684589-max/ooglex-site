class_name HighlandVillage
extends RefCounted
## 羊脊村（路线图 5.2a，D12；STORY.md 5.2；布局数据在 world/highland_layout.gd）：余火高地山谷里的牧羊村。
## 先回答「这里住着谁、缺什么、刚发生过什么」（ART.md 第十节）：住着牧羊人和一个铁匠，厄尔德家在这儿有个驿站给烽燧线征粮；
## 缺粮、缺柴——驿站门口的车是空的、柴垛矮；刚发生过的——前夜又有人长眠走了：雪地上一串光脚的脚印从村里往北去（5.2b 的妮尔就在找她父亲）。
##   矮石屋 6 栋（world/croft.gd）、驿站（House：村里唯一的两层石楼，门通往大堂 world/waystation.gd）、铁匠的披棚（炉火是村里最亮的暖光）、
##   圆的、方的两个干砌石墙羊圈（羊挤在一起）、田间一道道干砌石墙、结冰的溪、村子西北坡上的石圈（九块半埋的立石）、柴垛、草垛、空车、木桶。
## 同 Highland：碰撞、门、路牌同步建（一进场就挡得住、推得开）；画面每样一件活，交给所在那一块分帧搭。

const CROFT_DOOR_TEXT := "门从里面闩着。屋里有人咳了一声，没出来。"
const SIGN_TEXT_VILLAGE := "往第十九烽（断角烽）"
const SIGN_TEXT_BEACON := "往羊脊村"
const WAYSTATION_DOOR := "驿站的门"
const BANNER_FIELD := Color("5e6062")       # 厄尔德家：灰底燃烧的烽燧（WORLD.md 第五节）
const BANNER_CHARGE := Color("c8642a")
## 只说一句的人（5.2b）
const LINES := {
	"shepherd": ["羊比人知道得早。长眠的人从村边走过去那晚，羊挤成一团，一夜没叫。", "妮尔她爹？好人。冻掉了两根指头，照样编得出全村最紧的草绳。屋檐下吊石头的绳子，一半是他编的。",
		"明天洛蒙德家的粮车要从村里过。咱们只配站在路边看着它过去。"],
	"bolted": ["门闩着，是怕自己睡着了往外走。……傻吧？长眠的人，门闩是自己拔开的。", "驿站的罗薇娜小姐是个好人。厄尔德家的人里头，就她肯下山跟我们说话。",
		"昨天夜里又听见有人从门口走过去，光着脚，踩得雪咯吱咯吱的。我没敢开门。"],
}
const FOOTPRINTS := [Vector2(-8.0, 70.0), Vector2(-12.0, 58.0), Vector2(-15.0, 46.0), Vector2(-14.0, 34.0), Vector2(-11.0, 20.0)]   # 光脚的脚印：从村子西北往北去


# ---------------- 碰撞、门、路牌（同步） ----------------

## 所有挡人的东西：[[变换, 尺寸], ...]
static func solids() -> Array:
	var out := []
	for c in HighlandLayout.CROFTS:
		out.append_array(Croft.solids(croft_pos(c), float(c[2]), croft_spec(c)))
	out.append_array(House.solids(waystation_pos(), float(HighlandLayout.WAYSTATION[1]), waystation_spec()))
	out.append_array(_smithy_solids())
	for seg in wall_pieces():
		out.append([Transform3D(Basis(Vector3.UP, float(seg.yaw)), seg.c + Vector3(0, float(seg.h) * 0.5, 0)), Vector3(float(seg.len), float(seg.h), HighlandLayout.WALL_W)])
	for st in ring_stones():
		out.append([Transform3D(Basis(Vector3.UP, float(st.yaw)), (st.pos as Vector3) + Vector3(0, float(st.h) * 0.4, 0)), Vector3(float(st.w) * 0.8, float(st.h) * 0.8, float(st.t) * 0.8)])
	for s in props_decor().solids:
		out.append([Transform3D(Basis.IDENTITY, s[0]), s[1]])
	return out


static func interactables(parent: Node3D) -> void:
	for c in HighlandLayout.CROFTS:
		var d := Door.make("门", 0.9, 1.64, true)
		d.locked_text = CROFT_DOOR_TEXT
		d.name = "CroftDoor_" + str(c[0])
		d.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(c[2]))), croft_pos(c)) * Transform3D(Basis.IDENTITY, Vector3(float(c[5]) - 0.45, 0, 0.1))
		parent.add_child(d)
	parent.add_child(waystation_door())
	for sgn in [[HighlandLayout.SIGN_VILLAGE, SIGN_TEXT_VILLAGE, -150.0], [HighlandLayout.SIGN_BEACON, SIGN_TEXT_BEACON, 30.0]]:
		var rs := RoadSign.new()
		rs.text = str(sgn[1])
		var p: Vector3 = sgn[0]
		rs.position = Vector3(p.x, Highland.height_at(p.x, p.z), p.z)
		rs.rotation_degrees.y = float(sgn[2])
		parent.add_child(rs)


## 村里的人（5.2b）：同步放（块没搭好时也得找得到、说得上话，同鹭沼）
static func people(parent: Node3D) -> void:
	for p in HighlandLayout.PEOPLE:
		if str(p[0]) == "nell" and str(GameState.get_flag("ch2_nell", "")) == "left":
			continue                                     # 支线「妮尔的父亲」随她去了（5.5b）：她踩着脚印往北走了
		var pos: Vector2 = p[2]
		var n := Npc.make(str(p[1]), LINES.get(str(p[0]), []), Color(str(p[4])))
		n.name = "Npc_" + str(p[0])
		if str(p[5]) != "":
			n.dialogue_area = "highland"
			n.dialogue_id = str(p[5])
		n.position = Vector3(pos.x, ground(pos), pos.y)
		n.rotation.y = float(p[3])
		parent.add_child(n)


static func waystation_door() -> Door:
	var spec := waystation_spec()
	var d := House.door_node(spec.door)
	d.name = "WaystationDoor"
	d.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(HighlandLayout.WAYSTATION[1]))), waystation_pos()) * Transform3D(Basis.IDENTITY, Vector3(float(spec.door_x) - 0.55, 0, 0.05))
	return d


# ---------------- 摆放 ----------------

static func ground(p: Vector2) -> float:
	return Highland.height_at(p.x, p.y)


static func croft_pos(c: Array) -> Vector3:
	var p: Vector2 = c[1]
	return Vector3(p.x, ground(p) - 0.05, p.y)


static func croft_spec(c: Array) -> Dictionary:
	return {"id": str(c[0]), "w": float(c[3]), "d": float(c[4]), "door_x": float(c[5]), "lit": float(c[6]), "seed": int(c[7])}


static func waystation_pos() -> Vector3:
	var p: Vector2 = HighlandLayout.WAYSTATION[0]
	return Vector3(p.x, ground(p) - 0.05, p.y)


static func waystation_spec() -> Dictionary:
	return {"w": float(HighlandLayout.WAYSTATION[2]), "d": float(HighlandLayout.WAYSTATION[3]), "floors": 1, "stone_upper": true, "roof": "eaves",
		"seed": 21, "lit": 0.85, "door_x": float(HighlandLayout.WAYSTATION[4]), "chimney": true, "solid": false,
		"door": {"name": WAYSTATION_DOOR, "to_area": "waystation", "to_spawn": "front", "verb": "进入", "node": false}}


## 干砌石墙切成一段段（每段 1.4–1.9 米，高矮、朝向稍微错开，像垒出来的）：{c 底面中心, yaw, len, h}
static func wall_pieces() -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5201
	var lines: Array = HighlandLayout.FIELD_WALLS.duplicate()
	var pr: Vector2 = HighlandLayout.PEN_ROUND[0]
	var r := float(HighlandLayout.PEN_ROUND[1])
	var ring := []
	for k in 21:
		var a := TAU * k / 20.0
		ring.append(pr + Vector2(cos(a), sin(a)) * r)
	var cut := []
	for k in ring.size() - 1:
		var mid := ((ring[k] as Vector2) + (ring[k + 1] as Vector2)) * 0.5 - pr
		if absf(angle_difference(mid.angle(), 0.0)) < 0.25:
			continue                                              # 东边留门
		cut.append([ring[k], ring[k + 1]])
	var q: Vector2 = HighlandLayout.PEN_RECT[0]
	var hx := float(HighlandLayout.PEN_RECT[1])
	var hz := float(HighlandLayout.PEN_RECT[2])
	var c0 := q + Vector2(-hx, -hz)
	var c1 := q + Vector2(hx, -hz)
	var c2 := q + Vector2(hx, hz)
	var c3 := q + Vector2(-hx, hz)
	cut.append([c0, c1])
	cut.append([c1, c2])
	cut.append([c2, c3])
	cut.append([c3, c3.lerp(c0, 0.3)])                           # 西边（对着村路）留门
	cut.append([c3.lerp(c0, 0.62), c0])
	for line in lines:
		for i in line.size() - 1:
			cut.append([line[i], line[i + 1]])
	for seg in cut:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var length := a.distance_to(b)
		var n := maxi(1, int(round(length / 1.6)))
		for i in n:
			var p0 := a.lerp(b, float(i) / n)
			var p1 := a.lerp(b, float(i + 1) / n)
			var c := (p0 + p1) * 0.5
			var dir := p1 - p0
			out.append({"c": Vector3(c.x, ground(c) - 0.12, c.y), "yaw": atan2(-dir.y, dir.x) + rng.randf_range(-0.04, 0.04),
				"len": dir.length() + 0.12, "h": HighlandLayout.FIELD_WALL_H * rng.randf_range(0.85, 1.12)})
	return out


## 石圈的九块立石：{pos, yaw, h, w, t, lean}；有一块倒了
static func ring_stones() -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5202
	for k in HighlandLayout.STONES:
		var a := TAU * k / HighlandLayout.STONES + rng.randf_range(-0.08, 0.08)
		var p := HighlandLayout.STONE_RING + Vector2(cos(a), sin(a)) * HighlandLayout.STONE_RING_R
		var fallen := k == 6
		var h := rng.randf_range(1.9, 2.9) if not fallen else 0.75
		out.append({"pos": Vector3(p.x, ground(p) - 0.25, p.y), "yaw": -a + PI * 0.5 + rng.randf_range(-0.2, 0.2), "h": h,
			"w": rng.randf_range(0.7, 1.0) if not fallen else 2.0, "t": rng.randf_range(0.35, 0.55), "lean": rng.randf_range(-0.12, 0.12)})
	return out


## 村里的零碎（柴垛、草垛、空车、木桶、箱子、麻袋）：一份 Decor（碰撞同步建，画面按块）；rect 不空时只要那一块里的
static func props_decor(rect := Rect2()) -> Decor:
	var d := Decor.new()
	var inside := func(p: Vector2) -> bool: return rect.size == Vector2.ZERO or rect.has_point(p)
	for c in HighlandLayout.CROFTS:                      # 每栋房子西山墙边一垛柴（矮：柴不够烧）
		var yaw := deg_to_rad(float(c[2]))
		var right := Vector2(cos(yaw), -sin(yaw))
		var back := -Vector2(sin(yaw), cos(yaw))
		var p: Vector2 = (c[1] as Vector2) - right * (float(c[3]) * 0.5 + 0.75) + back * (float(c[4]) * 0.5)
		if inside.call(p):
			d.woodpile(Vector3(p.x, ground(p), p.y), Vector3(back.x, 0, back.y), 1.6, 0.6)
	var w: Vector2 = HighlandLayout.WAYSTATION[0]
	var items := [
		["cart", w + Vector2(-5.5, -4.2), 0.3, "wood"],              # 驿站门口：空车（只剩几根木头）
		["cart", w + Vector2(-4.6, 4.6), -0.5, "wood"],
		["barrel", w + Vector2(-1.2, 3.6)], ["barrel", w + Vector2(-1.0, 4.4)],
		["crate", w + Vector2(-1.3, -3.4), 0.2], ["sack", w + Vector2(-1.8, -3.9), 0.6], ["sack", w + Vector2(-0.9, -4.3), 1.4],
		["hay", (HighlandLayout.PEN_ROUND[0] as Vector2) + Vector2(8.6, -2.5), 0.3], ["hay", (HighlandLayout.PEN_ROUND[0] as Vector2) + Vector2(8.9, 0.2), 1.2],
		["hay", (HighlandLayout.PEN_RECT[0] as Vector2) + Vector2(-6.4, -2.6), 0.0],
		["barrel", (HighlandLayout.SMITHY[0] as Vector2) + Vector2(-2.3, 1.9)],
	]
	for it in items:
		var p: Vector2 = it[1]
		if not inside.call(p):
			continue
		var pos := Vector3(p.x, ground(p), p.y)
		match str(it[0]):
			"cart":
				d.cart(pos, float(it[2]), str(it[3]))
			"barrel":
				d.barrel(pos)
			"crate":
				d.crate(pos, float(it[2]))
			"sack":
				d.sack(pos, float(it[2]))
			"hay":
				d.hay(pos, float(it[2]))
	return d


# ---------------- 画面（分帧的活） ----------------

## 这一块里有哪些活
static func jobs_for(rect: Rect2, reduced_motion: bool) -> Array:
	var out := []
	for c in HighlandLayout.CROFTS:
		if rect.has_point(c[1]):
			out.append(func(root: Node3D): Croft.build(root, croft_pos(c), float(c[2]), croft_spec(c)))
	if rect.has_point(HighlandLayout.WAYSTATION[0]):
		out.append(func(root: Node3D): _waystation(root, reduced_motion))
	if rect.has_point(HighlandLayout.SMITHY[0]):
		out.append(func(root: Node3D): _smithy(root, reduced_motion))
	var walls := wall_pieces().filter(func(s): return rect.has_point(Vector2(s.c.x, s.c.z)))
	if not walls.is_empty():
		out.append(func(root: Node3D): _walls(root, walls))
	if rect.has_point(HighlandLayout.PEN_ROUND[0]) or rect.has_point(HighlandLayout.PEN_RECT[0]):
		out.append(func(root: Node3D): _sheep(root, rect))
	if rect.has_point(HighlandLayout.STONE_RING):
		out.append(func(root: Node3D): _ring(root))
	var half := rect.size * 0.5                     # 零碎按四分之一块各一件活（柴垛是几百根小圆柱，整块一起搭要 35 毫秒）
	for qx in 2:
		for qz in 2:
			var sub := Rect2(rect.position + Vector2(qx * half.x, qz * half.y), half)
			if not props_decor(sub).kit.tools.is_empty():
				out.append(func(root: Node3D): _props(root, sub))
	if rect.has_point(FOOTPRINTS[0]) or rect.has_point(FOOTPRINTS[FOOTPRINTS.size() - 1]) or FOOTPRINTS.any(func(f): return rect.has_point(f)):
		out.append(func(root: Node3D): _footprints(root, rect))
	return out


static func _props(root: Node3D, rect: Rect2) -> void:
	var d := props_decor(rect)
	var mi := d.kit.build(d.mats)                      # 碰撞已经同步建了（solids），这里只要画面
	mi.name = "VillageProps"
	root.add_child(mi)


## 驿站：House（两层石楼）+ 门前的厄尔德家旗、门边的风灯
static func _waystation(root: Node3D, reduced_motion: bool) -> void:
	var yaw := float(HighlandLayout.WAYSTATION[1])
	var pos := waystation_pos()
	House.build(root, pos, yaw, waystation_spec())
	var place := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), pos)
	var d := Decor.new()
	var n := place.basis * Vector3.BACK
	d.banner(place * Vector3(2.2, 4.9, 0.05), n, 1.0, 1.7, BANNER_FIELD, BANNER_CHARGE, "beacon")
	d.sconce(place * Vector3(-1.2, 2.3, 0.04), n, true)
	d.build(root, "WaystationDecor", not reduced_motion)


## 铁匠的披棚：三面矮石墙、一面敞着朝路，单坡木板顶压着雪；石砌的炉子里炭火通红（村里最亮的暖光）、铁砧、淬火的桶
static func _smithy(root: Node3D, reduced_motion: bool) -> void:
	var p: Vector2 = HighlandLayout.SMITHY[0]
	var yaw := deg_to_rad(float(HighlandLayout.SMITHY[1]))
	var place := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, ground(p) - 0.05, p.y))
	var kit := MeshKit.new()
	var w := 4.2
	var dd := 3.2
	kit.box("stone", Vector3(0, 0.6, -dd), Vector3(w, 1.2, 0.5), Basis.IDENTITY, 1.0, 0.5)              # 后墙
	for s in [-1.0, 1.0]:
		kit.box("stone", Vector3(s * w * 0.5, 0.6, -dd * 0.5), Vector3(0.5, 1.2, dd), Basis.IDENTITY, 1.0, 0.5)
		kit.cylinder("timber", Vector3(s * (w * 0.5 - 0.1), 0.0, 0.0), Vector3(s * (w * 0.5 - 0.1), 2.3, 0.0), 0.1, 0.09, 6)
	var roof_b := Basis(Vector3.RIGHT, deg_to_rad(-14.0))
	kit.box("timber", Vector3(0, 2.75, -dd * 0.5), Vector3(w + 0.6, 0.1, dd + 0.9), roof_b, 0.9, 0.6)
	kit.box("snow", Vector3(0, 2.86, -dd * 0.5), Vector3(w + 0.5, 0.1, dd + 0.6), roof_b, 1.0, 0.9)
	kit.box("stone", Vector3(-0.9, 0.5, -dd + 0.7), Vector3(1.3, 1.0, 1.0), Basis.IDENTITY, 0.9, 0.5)      # 炉子
	kit.box("stone", Vector3(-0.9, 1.6, -dd + 0.45), Vector3(0.7, 1.2, 0.5), Basis.IDENTITY, 0.8, 0.6)     # 炉子上的烟道
	kit.box("ember", Vector3(-0.9, 1.02, -dd + 0.75), Vector3(0.8, 0.06, 0.6))                            # 炭火
	kit.box("iron", Vector3(0.9, 0.62, -1.1), Vector3(0.6, 0.18, 0.24))                                   # 铁砧
	kit.box("timber", Vector3(0.9, 0.27, -1.1), Vector3(0.4, 0.54, 0.4), Basis.IDENTITY, 0.9, 0.6)
	var mi := kit.build({"stone": Look.mat("stone"), "timber": Look.mat("timber"), "snow": Look.mat("snow"), "ember": Inn._unshaded(Color("ff6a1e")), "iron": Inn._iron_mat()})
	mi.name = "Smithy"
	mi.transform = place
	root.add_child(mi)
	var fire := Tavern.FireLight.new()
	fire.name = "Forge"
	fire.light_color = Color("ff7a32")
	fire.base = 2.4
	fire.omni_range = 7.0
	fire.flicker = not reduced_motion
	fire.position = place * Vector3(-0.9, 1.4, -dd + 1.2)
	fire.add_to_group("light_source")
	fire.set_meta("radius", 4.0)
	root.add_child(fire)
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.4, 0.9)
	var hm := Look.halo(Color("ff7a32"), 0.5).duplicate() as StandardMaterial3D
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = hm
	halo.mesh = q
	halo.position = place * Vector3(-0.9, 1.15, -dd + 0.9)
	root.add_child(halo)


static func _smithy_solids() -> Array:
	var p: Vector2 = HighlandLayout.SMITHY[0]
	var place := Transform3D(Basis(Vector3.UP, deg_to_rad(float(HighlandLayout.SMITHY[1]))), Vector3(p.x, ground(p) - 0.05, p.y))
	var out := [[place * Transform3D(Basis.IDENTITY, Vector3(0, 0.8, -3.2)), Vector3(4.2, 1.6, 0.5)]]
	for s in [-1.0, 1.0]:
		out.append([place * Transform3D(Basis.IDENTITY, Vector3(s * 2.1, 0.8, -1.6)), Vector3(0.5, 1.6, 3.2)])
	out.append([place * Transform3D(Basis.IDENTITY, Vector3(-0.9, 0.9, -2.5)), Vector3(1.3, 1.8, 1.0)])
	out.append([place * Transform3D(Basis.IDENTITY, Vector3(0.9, 0.4, -1.1)), Vector3(0.6, 0.8, 0.4)])
	return out


## 干砌石墙：每段一块石头盒子（石墙贴图）+ 顶上一层雪
static func _walls(root: Node3D, pieces: Array) -> void:
	var kit := MeshKit.new()
	for s in pieces:
		var b := Basis(Vector3.UP, float(s.yaw))
		var h := float(s.h)
		kit.box("stone", (s.c as Vector3) + Vector3(0, h * 0.5, 0), Vector3(float(s.len), h, HighlandLayout.WALL_W), b, 1.0, 0.5)
		kit.box("snow", (s.c as Vector3) + Vector3(0, h + 0.05, 0), Vector3(float(s.len) - 0.05, 0.12, HighlandLayout.WALL_W * 0.85), b, 1.0, 0.95)
	var mi := kit.build({"stone": Look.mat("stone"), "snow": Look.mat("snow")})
	mi.name = "DryWalls"
	root.add_child(mi)


## 羊：几只挤在羊圈里（代码搭：一团羊毛、黑脸、四条细腿；三只里一只卧着）。这一块里的羊合成一个网格（羊毛、黑脸各一面）：
## 原来每只羊六个网格，村口绘制调用多出四十多次（5.2a 实测，预算 400）
static func _sheep(root: Node3D, rect: Rect2) -> void:
	var wool := SurfaceTool.new()
	wool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark := SurfaceTool.new()
	dark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := SphereMesh.new()
	body.radius = 0.36
	body.height = 0.62
	body.radial_segments = 10
	body.rings = 6
	var head := BoxMesh.new()
	head.size = Vector3(0.17, 0.2, 0.3)
	var leg := CylinderMesh.new()
	leg.top_radius = 0.035
	leg.bottom_radius = 0.03
	leg.height = 0.5
	leg.radial_segments = 5
	var rng := RandomNumberGenerator.new()
	rng.seed = 5203
	var count := 0
	for i in HighlandLayout.SHEEP.size():
		var sp: Vector3 = HighlandLayout.SHEEP[i]
		var yaw := rng.randf() * TAU
		if not rect.has_point(Vector2(sp.x, sp.z)):
			continue
		count += 1
		var lying := i % 3 == 2
		var lift := 0.15 if lying else 0.55
		var place := Transform3D(Basis(Vector3.UP, yaw), Vector3(sp.x, ground(Vector2(sp.x, sp.z)), sp.z))
		wool.append_from(body, 0, place * Transform3D(Basis().scaled(Vector3(0.9, 0.85, 1.45)), Vector3(0, lift + 0.2, 0)))
		dark.append_from(head, 0, place * Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0, lift + 0.36, 0.56)))
		if not lying:
			for lx in [-0.15, 0.15]:
				for lz in [-0.3, 0.3]:
					dark.append_from(leg, 0, place * Transform3D(Basis.IDENTITY, Vector3(lx, 0.25, lz)))
	if count == 0:
		return
	var mesh := ArrayMesh.new()
	wool.commit(mesh)
	dark.commit(mesh)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color("bcb4a4")
	wm.roughness = 1.0
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color("2a2624")
	dm.roughness = 0.9
	mesh.surface_set_material(0, wm)
	mesh.surface_set_material(1, dm)
	var mi := MeshInstance3D.new()
	mi.name = "Sheep"
	mi.mesh = mesh
	mi.set_meta("count", count)
	root.add_child(mi)


## 石圈：九块立石（地形着色器：侧面灰岩、顶上积雪），有一块倒在雪里
static func _ring(root: Node3D) -> void:
	var stones := ring_stones()
	var mm := MultiMesh.new()                         # 九块一次画完
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = HighlandFlora.rock_mesh(2)
	mm.instance_count = stones.size()
	for i in stones.size():
		var st: Dictionary = stones[i]
		var b := Basis(Vector3.UP, float(st.yaw)) * Basis(Vector3.BACK, float(st.lean))
		mm.set_instance_transform(i, Transform3D(b.scaled(Vector3(float(st.w), float(st.h), float(st.t))), (st.pos as Vector3) + Vector3(0, float(st.h) * 0.45, 0)))
	var mi := MultiMeshInstance3D.new()
	mi.name = "RingStones"
	mi.multimesh = mm
	mi.material_override = Highland.ground_material()
	root.add_child(mi)


## 光脚的脚印：前夜长眠走了的那个人，从村子西北一直往北（ART.md 第十节「痕迹」）。一串小凹印（深一点的雪色小椭圆），左右交替
static func _footprints(root: Node3D, rect: Rect2) -> void:
	var kit := MeshKit.new()
	for i in FOOTPRINTS.size() - 1:
		var a: Vector2 = FOOTPRINTS[i]
		var b: Vector2 = FOOTPRINTS[i + 1]
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		var n := int(a.distance_to(b) / 0.7)
		for k in n:
			var p := a.lerp(b, float(k) / n) + side * (0.13 if k % 2 == 0 else -0.13)
			if not rect.has_point(p):
				continue
			var y := ground(p) + 0.02
			var yaw := atan2(-dir.y, dir.x)
			kit.box("print", Vector3(p.x, y, p.y), Vector3(0.24, 0.01, 0.1), Basis(Vector3.UP, yaw), 1.0, 1.0)
	if kit.tools.is_empty():
		return
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("8f9aab")
	m.roughness = 0.9
	m.vertex_color_use_as_albedo = true
	var mi := kit.build({"print": m})
	mi.name = "Footprints"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## 结冰的溪：顺着溪床铺一条冰面（同步，一个网格），冰上落着一层薄雪
static func stream_ice(parent: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := []
	for i in HighlandLayout.STREAM.size() - 1:
		var a: Vector2 = HighlandLayout.STREAM[i]
		var b: Vector2 = HighlandLayout.STREAM[i + 1]
		var n := maxi(1, int(a.distance_to(b) / 2.0))
		for k in n:
			pts.append(a.lerp(b, float(k) / n))
	pts.append(HighlandLayout.STREAM[HighlandLayout.STREAM.size() - 1])
	var half := HighlandLayout.STREAM_HALF + 0.45
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in pts.size():
		var p: Vector2 = pts[i]
		var dir: Vector2 = ((pts[mini(i + 1, pts.size() - 1)] as Vector2) - (pts[maxi(i - 1, 0)] as Vector2)).normalized()
		var side := Vector2(-dir.y, dir.x)
		var y := Highland.height_at(p.x, p.y) + 0.25
		var l := Vector3(p.x + side.x * half, y, p.y + side.y * half)
		var r := Vector3(p.x - side.x * half, y, p.y - side.y * half)
		if i > 0:
			for v in [prev_l, prev_r, r, prev_l, r, l]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2((v as Vector3).x, (v as Vector3).z) * 0.25)
				st.add_vertex(v)
		prev_l = l
		prev_r = r
	var mi := MeshInstance3D.new()
	mi.name = "StreamIce"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	var t: Texture2D = Highland._tex(Highland.TEX_DIR % ["snow_02", "diff"])
	if t != null:
		m.albedo_texture = t
	m.albedo_color = Color(0.62, 0.71, 0.8)
	m.roughness = 0.16
	m.metallic_specular = 0.7
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## 石圈上的刻字（5.5a；STORY.md 5.8 支线「石圈」）：倒下的那块立石朝天的一面刻着一圈字，被风磨得快平了。
## 看一眼记下线索 `stones_seal`（`ch2_stones` = copied）；身上有奥尔本修士的旧书（序章），残卷上有一模一样的字（= matched）。诺伯特第二天多说一句。
static func stone_words(parent: Node3D) -> void:
	var fallen: Dictionary = ring_stones()[6]                  # 倒下的那块（ring_stones 里的第 7 块）
	var at := Vector2(fallen.pos.x, fallen.pos.z)
	var e := Examine.make("倒下的立石", "看刻字", func(_who: FpController) -> Dictionary: return read_stones(), Vector3(2.6, 1.0, 1.6))
	e.name = "StoneWords"
	e.position = Vector3(at.x, Highland.height_at(at.x, at.y), at.y)
	parent.add_child(e)


static func read_stones() -> Dictionary:
	var had := str(GameState.get_flag("ch2_stones", ""))
	var book := GameState.has_item("old_book")
	var text := "立石上刻着一圈字，被风雪磨得快平了，不是现在的写法——像是星铁教会还没立起来以前的字。你用手指一个一个摸过去，只认出几个：「……于冬井……誓……断……」"
	if book:
		text = "立石上刻着一圈字，被风雪磨得快平了。你想起奥尔本修士那本烧焦的旧书，翻开夹着的半页残卷——上面有一模一样的一行：「封于冬井，誓不可断。」"
	var val := "matched" if book else "copied"
	if had != "matched":
		GameState.set_flag("ch2_stones", val)
		GameState.add_clue("stones_seal")
	return {"kind": "examine", "name": "石圈", "toast": text}

