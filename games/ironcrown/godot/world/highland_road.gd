class_name HighlandRoad
extends RefCounted
## 盘山路上的东西（路线图 5.3a，D12；STORY.md 5.2「一侧峭壁、一侧缓坡，积雪齐膝（走进去变慢），几处倒伏的松树；半山有一处废弃的羊棚」）。
## 先回答「这里刚发生过什么」（ART.md 第十节）：路没人修了——倒下的树没人锯开拖走，只是被车、人从边上绕过去；
## 半山的羊棚早没人赶羊上来，顶塌了一半，棚里有一堆冷了的灰（烽誓团的人上下山在这儿躲过风）；路边一根根雪杆（深雪里认路用的，杆头涂了沥青）。
## 深雪本身在地形里（HighlandLayout.deep：路边的雪檐、背风的雪窝鼓起来，踩进去变慢）。
##   倒树 = HighlandFlora 的树横过来（树干、枝条同一份网格，枝条换一种没风、发黄的材质），根那头翻起一块带土的根盘，树干上积着一条雪
##   废羊棚 = 干砌石墙（西边后半截塌成一堆石头）、两根还搭着的椽子、东半边几块盖着雪的木板、西半边塌进棚里的木板、门口歪着的破篱笆门、棚里一圈石头围着的冷灰
##   雪杆 = 沿路下坡一侧每隔 24 米一根（多实例）
##   （试过岩坎上贴一道道冰：贴着 1 米的地形网格画长条，近看像浮在岩面上的白纸条，去掉了）
## 同 HighlandVillage：碰撞同步建（Highland._collision），画面每样一件活交给所在那一块分帧搭。

const POLE_EVERY := 24.0
const POLE_H := 2.1
const SHED_WALL_T := 0.55

static var _cache := {}
static var _dead_mat: ShaderMaterial


static func clear_cache() -> void:
	_cache.clear()
	_dead_mat = null


## 载入时备好材质和倒树的网格（分帧的活里只剩搭）
static func warm() -> void:
	for k in ["stone", "timber", "snow", "bark", "peat"]:
		Look.mat(k)
	for k in HighlandFlora.TREE_KINDS:
		fallen_mesh(k)
	pole_mesh()


static func ground(p: Vector2) -> float:
	return Highland.height_at(p.x, p.y)


# ---------------- 倒树 ----------------

## 一棵倒树的摆法：{place 树的变换（本地 +Y 沿树干从根到梢，按树长缩放）, root, tip（贴地的世界坐标）, axis 沿树干的单位向量, r 根部的树干半径}
static func fallen_specs() -> Array:
	if _cache.has("fallen"):
		return _cache.fallen
	var out := []
	for f in HighlandLayout.fallen():
		var length := float(f.len)
		var r0 := (0.022 if int(f.kind) == 0 else 0.026) * length
		var rp: Vector2 = f.root
		var tp: Vector2 = f.tip
		var root := Vector3(rp.x, ground(rp) + r0 * 0.75, rp.y)          # 树干压进雪里一点
		var tip := Vector3(tp.x, ground(tp) + 0.18, tp.y)
		var axis := (tip - root).normalized()
		var side := axis.cross(Vector3.UP).normalized()
		var up := side.cross(axis).normalized()
		var roll := Basis(axis, 0.6 + 0.4 * out.size())                  # 绕树干转一点（几棵的枝条不一个样）
		var basis := (roll * Basis(side, axis, up)).scaled(Vector3(length, length, length))
		out.append({"place": Transform3D(basis, root), "root": root, "tip": tip, "axis": axis,
			"side": side, "up": up, "r": r0, "len": length, "kind": int(f.kind)})
	_cache.fallen = out
	return out


## 倒树的网格：和站着的树同一份形状，复制一份换枝条的材质（没风、针叶发黄发暗：倒了一冬了）
static func fallen_mesh(kind: int) -> ArrayMesh:
	var key := "fallen_mesh_%d" % kind
	if _cache.has(key):
		return _cache[key]
	var m := HighlandFlora.tree_mesh(kind, 0).duplicate() as ArrayMesh
	m.surface_set_material(0, Look.mat("bark"))
	m.surface_set_material(1, dead_material())
	_cache[key] = m
	return m


static func dead_material() -> ShaderMaterial:
	if _dead_mat == null:
		_dead_mat = HighlandFlora.branch_material().duplicate() as ShaderMaterial
		_dead_mat.set_shader_parameter("wind", 0.0)
		_dead_mat.set_shader_parameter("fallen", true)
		_dead_mat.set_shader_parameter("needle_tint", Color(0.6, 0.6, 0.45))
	return _dead_mat


## 一块里的倒树：树（每种一个多实例）+ 根盘、树干上的雪（一个网格）
static func _fallen(root_node: Node3D, list: Array) -> void:
	var by_kind := {}
	for f in list:
		if not by_kind.has(f.kind):
			by_kind[f.kind] = []
		by_kind[f.kind].append(f)
	for k in by_kind:
		var trees: Array = by_kind[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = fallen_mesh(int(k))
		mm.instance_count = trees.size()
		for i in trees.size():
			mm.set_instance_transform(i, trees[i].place)
			mm.set_instance_custom_data(i, Color(0.4, 0.65, 0.0, 0.0))      # 深浅居中；雪按斑块
		var mi := MultiMeshInstance3D.new()
		mi.name = "FallenTrees%d" % int(k)
		mi.multimesh = mm
		root_node.add_child(mi)
	var kit := MeshKit.new()
	for f in list:
		var r := float(f.r)
		var axis: Vector3 = f.axis
		var up: Vector3 = f.up
		var side: Vector3 = f.side
		var root: Vector3 = f.root
		var length := float(f.len)
		var plate := root - axis * 0.25                                     # 根盘：翻起来的一块土，竖着、对着树干
		var pr := clampf(length * 0.1, 0.9, 1.4)
		kit.cylinder("soil", plate - axis * 0.22, plate + axis * 0.22, pr, pr * 0.85, 9, 0.8)
		kit.box("snow", plate + up * (pr * 0.92), Vector3(0.5, 0.16, pr * 1.3), Basis(axis, up, side), 1.0, 0.9)
		for j in 6:                                                         # 根：从根盘里支棱出来
			var a := TAU * j / 6.0 + 0.3
			var dir := (side * cos(a) + up * sin(a)).normalized()
			var from := plate - axis * 0.2 + dir * pr * 0.6
			kit.cylinder("bark", from, from + dir * pr * 0.7 - axis * 0.35, 0.07, 0.02, 5)
		var ytop := up * r * 0.85                                           # 树干上积的一条雪
		kit.box("snow", root + axis * length * 0.32 + ytop, Vector3(length * 0.58, 0.09, r * 1.3), Basis(axis, up, side), 1.0, 0.95)
	var mi2 := kit.build({"soil": Look.mat("peat"), "bark": Look.mat("bark"), "snow": Look.mat("snow")})
	mi2.name = "FallenRoots"
	root_node.add_child(mi2)


# ---------------- 废羊棚 ----------------

static func shed_place() -> Transform3D:
	var c: Vector2 = HighlandLayout.SHED[0]
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(HighlandLayout.SHED[1]))), Vector3(c.x, ground(c) - 0.05, c.y))


## 墙一段段：[本地中心（墙脚）, 尺寸]——门在正面（+Z）中间，西边（-X）后半截塌了只剩 0.6 米
static func shed_walls() -> Array:
	var w := float(HighlandLayout.SHED[2])
	var d := float(HighlandLayout.SHED[3])
	var t := SHED_WALL_T
	var door := 1.4
	var side_len := (w - door) * 0.5
	return [
		[Vector3(0, 0, -d * 0.5), Vector3(w, 1.75, t)],                                         # 后墙
		[Vector3(w * 0.5 - t * 0.5, 0, 0), Vector3(t, 1.6, d)],                                 # 东墙
		[Vector3(-w * 0.5 + t * 0.5, 0, d * 0.25), Vector3(t, 1.5, d * 0.5)],                   # 西墙前半截
		[Vector3(-w * 0.5 + t * 0.5, 0, -d * 0.25), Vector3(t, 0.6, d * 0.5)],                  # 西墙后半截：塌了
		[Vector3(-door * 0.5 - side_len * 0.5, 0, d * 0.5), Vector3(side_len, 1.45, t)],        # 正面门两边
		[Vector3(door * 0.5 + side_len * 0.5, 0, d * 0.5), Vector3(side_len, 1.45, t)],
	]


static func _shed(root_node: Node3D) -> void:
	var place := shed_place()
	var w := float(HighlandLayout.SHED[2])
	var d := float(HighlandLayout.SHED[3])
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5311
	for wall in shed_walls():                                   # 干砌石墙：一段墙切成几块，顶上高低不平（垒出来的），顶上积雪
		var c: Vector3 = wall[0]
		var s: Vector3 = wall[1]
		var along := Vector3.RIGHT if s.x > s.z else Vector3.BACK
		var length := maxf(s.x, s.z)
		var n := maxi(1, int(round(length / 1.1)))
		for k in n:
			var seg := length / n
			var off := along * (-length * 0.5 + seg * (k + 0.5))
			var h := s.y + rng.randf_range(-0.12, 0.1)
			var size := Vector3(seg + 0.02, h, s.z) if along == Vector3.RIGHT else Vector3(s.x, h, seg + 0.02)
			kit.box("stone", c + off + Vector3(0, h * 0.5, 0), size, Basis.IDENTITY, 1.0, 0.55)
			var snow := Vector3(size.x - 0.06, 0.1, size.z - 0.08)
			kit.box("snow", c + off + Vector3(0, h + 0.04, 0), snow, Basis.IDENTITY, 1.0, 0.95)
	var back_y := 1.8
	var front_y := 1.5
	for x in [-0.6, 1.3]:                                       # 两根还搭着的椽子（从后墙搭到正面墙）
		kit.cylinder("timber", Vector3(x, back_y, -d * 0.5), Vector3(x, front_y, d * 0.5 + 0.2), 0.08, 0.07, 6, 0.8)
	var pitch := atan2(back_y - front_y, d)
	for k in 4:                                                 # 东半边：几块还盖着的木板，上面压着雪
		var x := 0.6 + k * 0.62
		var b := Basis(Vector3.RIGHT, pitch)
		kit.box("timber", Vector3(x, (back_y + front_y) * 0.5 + 0.1, 0.1), Vector3(0.56, 0.06, d + 0.5), b, 0.85, 0.6)
		kit.box("snow", Vector3(x, (back_y + front_y) * 0.5 + 0.2, 0.1), Vector3(0.6, 0.12, d + 0.4), b, 1.0, 0.95)
	for k in 3:                                                 # 西半边：塌下来的木板，一头还挂在后墙上、一头戳在棚里的雪里
		var x := -2.3 + k * 0.6
		var top := Vector3(x, back_y - 0.1, -d * 0.5 + 0.3)
		var bot := Vector3(x + rng.randf_range(-0.2, 0.2), 0.15, 0.4 + k * 0.3)
		var mid := (top + bot) * 0.5
		var ax := (bot - top).normalized()
		var bs := Basis(Vector3.RIGHT, ax.cross(Vector3.RIGHT).normalized(), ax).orthonormalized()
		kit.box("timber", mid, Vector3(0.5, 0.06, top.distance_to(bot)), bs, 0.8, 0.6)
	kit.box("snow", Vector3(-1.6, 0.25, -0.6), Vector3(2.4, 0.5, 2.6), Basis(Vector3.BACK, 0.12), 1.0, 0.9)   # 从塌了的那角灌进来的雪
	var fire := Vector3(1.2, 0.0, 0.3)                          # 冷了的火堆：一圈石头、几根烧黑的柴、一摊灰
	for k in 7:
		var a := TAU * k / 7.0
		kit.box("stone", fire + Vector3(cos(a) * 0.45, 0.08, sin(a) * 0.45), Vector3(0.2, 0.16, 0.16), Basis(Vector3.UP, a), 0.9, 0.6)
	kit.box("ash", fire + Vector3(0, 0.02, 0), Vector3(0.6, 0.04, 0.6))
	for k in 3:
		var a := k * 1.9
		kit.cylinder("char", fire + Vector3(cos(a) * 0.3, 0.05, sin(a) * 0.3), fire + Vector3(-cos(a) * 0.25, 0.1, -sin(a) * 0.25), 0.04, 0.035, 5)
	var gate := Transform3D(Basis(Vector3.UP, 0.5) * Basis(Vector3.RIGHT, -0.32), Vector3(1.9, 0.0, d * 0.5 + 0.7))   # 破篱笆门：歪靠在门边
	for x in [-0.6, 0.0, 0.6]:
		kit.cylinder("timber", gate * Vector3(x, 0, 0), gate * Vector3(x, 1.0, 0), 0.04, 0.035, 5, 0.8)
	for y in [0.25, 0.55, 0.85]:
		kit.box("timber", gate * Vector3(0, y, 0), Vector3(1.3, 0.05, 0.04), gate.basis, 0.8, 0.7)
	var ash := StandardMaterial3D.new()
	ash.albedo_color = Color("6a6866")
	ash.roughness = 1.0
	var char_m := StandardMaterial3D.new()
	char_m.albedo_color = Color("1c1816")
	char_m.roughness = 0.9
	var mi := kit.build({"stone": Look.mat("stone"), "timber": Look.mat("timber"), "snow": Look.mat("snow"), "ash": ash, "char": char_m})
	mi.name = "Shed"
	mi.transform = place
	root_node.add_child(mi)
	var mm := MultiMesh.new()                                   # 塌下来的石头：散在西墙后半截里外
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = HighlandFlora.rock_mesh(1)
	mm.instance_count = 9
	for k in 9:
		var p := Vector3(-w * 0.5 + rng.randf_range(-1.0, 0.9), 0.0, rng.randf_range(-d * 0.5, 0.0))
		var s := rng.randf_range(0.28, 0.5)
		mm.set_instance_transform(k, place * Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.8, s)), p + Vector3(0, s * 0.18, 0)))
	var rubble := MultiMeshInstance3D.new()
	rubble.name = "ShedRubble"
	rubble.multimesh = mm
	rubble.material_override = Highland.ground_material()
	root_node.add_child(rubble)


# ---------------- 雪杆 ----------------

## 雪杆的位置：出了村以后每段路下坡一侧，每隔 POLE_EVERY 米一根（离路边 0.55 米）：[位置（贴地）, 歪的方向（弧度）, 歪多少]
static func poles() -> Array:
	if _cache.has("poles"):
		return _cache.poles
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5312
	for i in HighlandLayout.ROAD.size() - 1:
		var a: Vector2 = HighlandLayout.ROAD[i]
		var b: Vector2 = HighlandLayout.ROAD[i + 1]
		var dir := (b - a).normalized()
		var out_n := Vector2(-dir.y, dir.x) * -HighlandLayout._uphill_side(i)       # 下坡那一边
		var n := int(a.distance_to(b) / POLE_EVERY)
		for k in range(1, n + 1):
			var p := a.lerp(b, float(k) / (n + 1)) + out_n * (HighlandLayout.ROAD_HALF + 0.55)
			if p.distance_to(HighlandLayout.VILLAGE) < HighlandLayout.VILLAGE_R + 6.0:
				continue
			if HighlandLayout.road_hit(p).d < HighlandLayout.ROAD_HALF + 0.3:     # 弯道里侧碰到别的一段路
				continue
			out.append([Vector3(p.x, ground(p) - 0.2, p.y), rng.randf() * TAU, rng.randf_range(0.0, 0.07)])
	_cache.poles = out
	return out


## 一根雪杆：木杆 + 杆头一截涂了沥青的黑头（两种材质，一个网格；多实例画）
static func pole_mesh() -> ArrayMesh:
	if _cache.has("pole_mesh"):
		return _cache.pole_mesh
	var kit := MeshKit.new()
	kit.cylinder("timber", Vector3.ZERO, Vector3(0, POLE_H - 0.35, 0), 0.04, 0.034, 6, 0.85)
	kit.cylinder("tar", Vector3(0, POLE_H - 0.35, 0), Vector3(0, POLE_H, 0), 0.036, 0.03, 6)
	var tar := StandardMaterial3D.new()
	tar.albedo_color = Color("16120f")
	tar.roughness = 0.45
	var mi := kit.build({"timber": Look.mat("timber"), "tar": tar})
	var m := mi.mesh as ArrayMesh
	mi.free()                                                   # 只要网格（多实例用）：节点不放进场景，自己释放
	_cache.pole_mesh = m
	return m


static func _poles(root_node: Node3D, list: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = pole_mesh()
	mm.instance_count = list.size()
	for i in list.size():
		var pl: Array = list[i]
		var lean := Basis(Vector3(cos(float(pl[1])), 0, sin(float(pl[1]))), float(pl[2]))
		mm.set_instance_transform(i, Transform3D(lean, pl[0]))
	var mi := MultiMeshInstance3D.new()
	mi.name = "SnowPoles"
	mi.multimesh = mm
	mi.visibility_range_end = 140.0
	root_node.add_child(mi)


# ---------------- 碰撞、分帧 ----------------

## 挡人的东西：[[变换, 尺寸], ...]——倒树的树干、根盘，羊棚的墙
static func solids() -> Array:
	var out := []
	for f in fallen_specs():
		var axis: Vector3 = f.axis
		var up: Vector3 = f.up
		var side: Vector3 = f.side
		var b := Basis(axis, up, side)
		var length := float(f.len)
		var r := float(f.r)
		out.append([Transform3D(b, (f.root as Vector3) + axis * length * 0.33), Vector3(length * 0.62, r * 2.0, r * 2.0)])
		var pr := clampf(length * 0.1, 0.9, 1.4)
		out.append([Transform3D(b, (f.root as Vector3) - axis * 0.25), Vector3(0.45, pr * 1.7, pr * 1.7)])
	var place := shed_place()
	for wall in shed_walls():
		var s: Vector3 = wall[1]
		out.append([place * Transform3D(Basis.IDENTITY, (wall[0] as Vector3) + Vector3(0, s.y * 0.5, 0)), s])
	return out


## 这一块里有哪些活
static func jobs_for(rect: Rect2) -> Array:
	var out := []
	var trees := fallen_specs().filter(func(f): return rect.has_point(Vector2(f.root.x, f.root.z)))
	if not trees.is_empty():
		out.append(func(root: Node3D): _fallen(root, trees))
	if rect.has_point(HighlandLayout.SHED[0]):
		out.append(func(root: Node3D): _shed(root))
	var ps := poles().filter(func(pl): return rect.has_point(Vector2(pl[0].x, pl[0].z)))
	if not ps.is_empty():
		out.append(func(root: Node3D): _poles(root, ps))
	return out


## 树、石头不长在这些东西上（HighlandFlora.near_village_works 调）
static func blocks(p: Vector2, margin: float) -> bool:
	if p.distance_to(HighlandLayout.SHED[0]) < HighlandLayout.SHED_R + 2.0 + margin:
		return true
	for f in HighlandLayout.fallen():
		if HighlandLayout._seg_d(p, f.root, f.tip) < 1.6 + margin:
			return true
	return false
