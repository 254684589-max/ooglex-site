class_name TownBuilder
extends RefCounted
## 把 TownGen 的布局搭成 3D 烬原镇（P7）。地面、墙（修道院废墟与房屋）、导航、楼梯、墙上火把复用 DungeonBuilder；
## 这里再加：整片泥土地面、石板路、外圈树林（带碰撞）、房顶、篝火、水井、铁砧、传送石、野花、三位 NPC。
## 地面、墙、房顶用写实贴图（2.6 之二 / 之四）；水井、铁砧、传送石、篝火与房屋细节是代码搭的模型（PropModels，2.6 之五）；树林也是（2.6 之六）。

## 树林分块（格）与三种树的比例：针叶树 < x ≤ 阔叶树 < y ≤ 枯树
const TREE_BLOCK := 12
const TREE_MIX := Vector2(0.5, 0.8)
const PROP_SIZES := {"fire": Vector3(1.4, 0.6, 1.4), "well": Vector3(1.8, 1.0, 1.8), "wp": Vector3(1.0, 1.8, 1.0), "anvil": Vector3(1.1, 0.9, 0.7)}


static func build(parent: Node3D, m: Dictionary, opt: Dictionary = {}) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var ground_mat := Look.ground_material()
	var obstacles: Array = []
	for p in m.props:
		obstacles.append({"pos": TownGen.to_world(p.x, p.y), "size": PROP_SIZES.get(p.type, Vector3.ONE)})
	var o := opt.duplicate()
	o.floor_material = ground_mat
	# 2.6 之四：修道院废墟用粗石墙（主题 town 的墙），房屋的墙用灰泥石墙
	var house_rects: Array = m.houses.map(func(hs): return hs.rect)
	o.wall_kind = func(c: Vector2i) -> String:
		for r in house_rects:
			if (r as Rect2i).has_point(c):
				return "house"
		return ""
	o.wall_materials = {"house": func() -> Material: return Look.surface_material("wall_house", Color(1, 1, 1), Color(1.05, 0.98, 0.9))}
	o.obstacles = obstacles
	var info := DungeonBuilder.build(parent, m, o)
	var region: Node3D = info.region
	var rng := RandomNumberGenerator.new()
	rng.seed = 36

	# 整片泥土地（树下也有地面，不露黑底）
	var gp := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(m.w * DungeonBuilder.TILE + 20.0, m.h * DungeonBuilder.TILE + 20.0)
	gp.mesh = plane
	gp.material_override = ground_mat
	gp.position = Vector3(m.w * DungeonBuilder.TILE / 2.0, -0.03, m.h * DungeonBuilder.TILE / 2.0)
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.name = "Ground"
	region.add_child(gp)

	# 石板路：合并成一个网格
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in m.paths:
		DungeonBuilder._quad(st, DungeonBuilder.cell_center(c) + Vector3(0, 0.012, 0), Vector3.UP, Vector3.FORWARD, DungeonBuilder.TILE / 2, DungeonBuilder.TILE / 2)
	var pmi := MeshInstance3D.new()
	pmi.mesh = st.commit()
	pmi.material_override = Look.floor_material(Color(0.95, 1.0, 1.05))
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pmi.name = "Paths"
	region.add_child(pmi)

	# 树林（2.6 之六）：针叶树、阔叶树、枯树三种代码搭的模型，按 12×12 格分块、每块每种一个多实例网格
	# （多实例网格不会逐棵剔除：分块后镜头外的整块不画；树都不投影——P7 实测低分段 + 投影时一个镜头 35 万图元）。每格一个碰撞盒
	var trees: Array = m.trees
	var groups := {}        # [块 x, 块 y, 种类] → 变换列表
	var tbody := StaticBody3D.new()
	tbody.name = "Trees"
	tbody.collision_layer = Layers.WORLD
	tbody.collision_mask = 0
	region.add_child(tbody)
	for i in trees.size():
		var c: Vector2i = trees[i]
		var p := DungeonBuilder.cell_center(c) + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
		var s := rng.randf_range(0.8, 1.35)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
		var r := rng.randf()
		var kind := "tree_pine" if r < TREE_MIX.x else ("tree_broad" if r < TREE_MIX.y else "tree_dead")
		var key := [c.x / TREE_BLOCK, c.y / TREE_BLOCK, kind]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(Transform3D(b, p))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(DungeonBuilder.TILE, 3.0, DungeonBuilder.TILE)
		cs.shape = bs
		cs.position = DungeonBuilder.cell_center(c) + Vector3(0, 1.5, 0)
		tbody.add_child(cs)
	var tree_mat := PropModels.multi_material()
	for key in groups:
		var xs: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = PropModels.get_model(key[2]).mesh
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = tree_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "Trees_%s_%d_%d" % [String(key[2]).trim_prefix("tree_"), key[0], key[1]]
		region.add_child(mi)

	# 房顶
	for hs in m.houses:
		var r: Rect2i = hs.rect
		var roof := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(r.size.x * DungeonBuilder.TILE + 0.8, 2.2, r.size.y * DungeonBuilder.TILE + 0.8)
		roof.mesh = pm
		# 灰色石板瓦（缺贴图时退回原来的暗红色）
		var rm := Look.surface_material("roof")
		if Look.photo_set("roof").is_empty():
			rm = StandardMaterial3D.new()
			rm.albedo_color = Color(0.36, 0.14, 0.1)
			rm.roughness = 1.0
		roof.material_override = rm
		roof.position = Vector3((r.position.x + r.size.x / 2.0) * DungeonBuilder.TILE, DungeonBuilder.WALL_H + 1.1, (r.position.y + r.size.y / 2.0) * DungeonBuilder.TILE)
		roof.name = "Roof_" + String(hs.id)
		region.add_child(roof)
		# 2.6 之五：木构架、门（开在离石板路最近的那一面）、亮灯的窗、烟囱、屋脊与封檐板
		var det := PropModels.house(r, door_dir(r, m.paths), hash(String(hs.id)) & 7)
		det.name = "House_" + String(hs.id)
		region.add_child(det)

	# 道具（传送石、水井可以点：InteractSpot，P8）
	var torches: Array = info.torches.duplicate()
	var use_spots: Array = []
	for p in m.props:
		var pos := TownGen.to_world(p.x, p.y)
		if p.type in ["wp", "well"]:
			var sp := InteractSpot.make(p.type, "传送石" if p.type == "wp" else "")
			parent.add_child(sp)
			sp.position = pos
			use_spots.append(sp)
		match p.type:
			"fire":
				var cf := PropModels.instance("campfire")          # 2.6 之五：一圈石头 + 交叉的木柴 + 余烬
				cf.position = pos
				region.add_child(cf)
				var fire := Torch.new()
				fire.mounted = false                                  # 篝火只要火苗与火光，不要墙上的托架
				parent.add_child(fire)
				fire.position = pos + Vector3(0, 0.55, 0)
				fire.scale = Vector3.ONE * 2.2
				fire.energy = 2.6
				fire.light.omni_range = 11.0
				torches.append(fire)
			"well", "wp", "anvil":
				# 2.6 之五：石砌水井（木架、顶棚、辘轳、水桶）、带符文的方尖传送石、树桩上的铁砧
				var pm := PropModels.instance({"well": "well", "wp": "waystone", "anvil": "anvil"}[p.type])
				pm.position = pos
				if p.type == "anvil":
					pm.rotation.y = 0.5
				region.add_child(pm)

	# 野花（V0.1 deco 5 / 6）
	var fl := MultiMesh.new()
	fl.transform_format = MultiMesh.TRANSFORM_3D
	fl.use_colors = true
	var fb2 := BoxMesh.new()
	fb2.size = Vector3(0.12, 0.1, 0.12)
	fl.mesh = fb2
	var spots: Array = []
	for i in int(Act1Data.rules().floors.town.flower_count):
		var c := Vector2i(rng.randi_range(3, m.w - 4), rng.randi_range(3, m.h - 4))
		if m.t[c.y * m.w + c.x] == DungeonGen.FLOOR and not m.paths.has(c) and not m.solid.has(c):
			spots.append(c)
	fl.instance_count = spots.size()
	for i in spots.size():
		fl.set_instance_transform(i, Transform3D(Basis.IDENTITY, DungeonBuilder.cell_center(spots[i]) + Vector3(rng.randf_range(-0.8, 0.8), 0.06, rng.randf_range(-0.8, 0.8))))
		fl.set_instance_color(i, [Color(0.9, 0.8, 0.3), Color(0.8, 0.4, 0.5), Color(0.85, 0.85, 0.9)][i % 3])
	var flm := StandardMaterial3D.new()
	flm.vertex_color_use_as_albedo = true
	var fmi := MultiMeshInstance3D.new()
	fmi.multimesh = fl
	fmi.material_override = flm
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fmi.name = "Flowers"
	region.add_child(fmi)

	# 人物
	var npcs: Array = []
	for d in m.npcs:
		var n := Npc.make(d)
		parent.add_child(n)
		n.position = TownGen.to_world(d.x, d.y)
		n.face_v01(float(d.face))
		npcs.append(n)

	info.torches = torches
	info.npcs = npcs
	info.spots = use_spots
	info.build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	return info


## 房门开在哪一面：四面各取门口外一格，离最近的石板路格子最近的那一面（曼哈顿距离）
static func door_dir(r: Rect2i, paths: Array) -> Vector2i:
	var best := Vector2i(0, 1)
	var best_d := 1 << 30
	var ctr := r.position + r.size / 2
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var out := Vector2i(ctr.x, ctr.y)
		if d.x != 0:
			out.x = (r.end.x if d.x > 0 else r.position.x - 1)
		else:
			out.y = (r.end.y if d.y > 0 else r.position.y - 1)
		for p in paths:
			var dd: int = absi((p as Vector2i).x - out.x) + absi((p as Vector2i).y - out.y)
			if dd < best_d:
				best_d = dd
				best = d
	return best
