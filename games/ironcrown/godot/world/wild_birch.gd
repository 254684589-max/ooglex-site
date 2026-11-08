class_name WildBirch
extends RefCounted
## 序章那几片林中空地（霜渡镇、桦林、渡口）外面的无尽荒野（2026-11-08 所有者「玩家可自由无尽探索」）：
## 原来四边是看不见的围墙、墙外一圈走不到的白桦（Edges，3.10）。现在墙去掉，外面边走边生成一片白桦林（WildStreamer）：
##   地面贴着区域边上是平的（和区域的雪地接得上，出口的路也平），往外慢慢有一点起伏；
##   白桦按噪声一片密一片疏，树干挡人；出口那条路两边空出来；
##   渡口：岸线（z > water_z）以南是河，荒野里那边是深水，边上同样立墙（WildStreamer.deep_y）。
## Edges.dress 在 wild = true 时不铺那块只有画面的大雪地、不种墙外那两圈树（荒野自己有地、有树）；出口的路照铺，荒野在路两边压平。

const RADIUS := 2
const TREE_STEP := 4.2


static func height(x: float, z: float, core: Rect2, water_z: float, exits: Array = []) -> float:
	var dx := maxf(maxf(core.position.x - x, x - core.end.x), 0.0)
	var dz := maxf(maxf(core.position.y - z, z - core.end.y), 0.0)
	var out := sqrt(dx * dx + dz * dz)
	if out <= 0.0:
		return -0.15                                  # 空地里面：压在空地自己的雪地底下（整块照搭，WildStreamer.carve_core = false）
	var k := clampf((out - 8.0) / 30.0, 0.0, 1.0)
	var y := -0.04 + k * k * (3.0 - 2.0 * k) * (0.9 * sin(x / 23.0 + 0.7) * sin(z / 19.0) + 0.45 * sin(x / 7.3 + z / 9.1) + 0.6 * sin(x / 61.0 - z / 47.0))
	if not exits.is_empty() and Edges._in_corridor(Vector3(x, 0, z), exits):
		y = -0.04                                     # 出口那条路（Edges 铺的，一直伸进雾里）两边是平的：一条穿过林子的小路
	if z > water_z:                                   # 渡口：岸线以南是河
		y = lerpf(y, -3.0, clampf((z - water_z) / 2.0, 0.0, 1.0))
	return y


static func attach(parent: Node3D, core: Rect2, exits: Array, water_z := INF) -> WildStreamer:
	var hf := func(x: float, z: float) -> float: return WildBirch.height(x, z, core, water_z, exits)
	var w := WildStreamer.make(core, hf, Look.mat("snow"), RADIUS)
	w.carve_core = false
	w.color_fn = func(_x: float, _z: float, slope: float) -> Color:   # Look.mat 的雪地拿顶点色当明暗（MeshKit 的 shade）：白的，陡一点暗一点
		var v := 1.0 - clampf(slope * 1.5, 0.0, 0.25)
		return Color(v, v, v)
	w.surface = "snow"
	w.ground_fn = func(x: float, z: float) -> float: return 0.0 if core.has_point(Vector2(x, z)) else WildBirch.height(x, z, core, water_z, exits)
	if water_z < INF:
		w.deep_y = -1.2
		w.deep_wall_top = 1.2
	var meshes := [Edges.tree_mesh(0), Edges.tree_mesh(1)]
	w.scatter_fn = func(root: Node3D, body: StaticBody3D, r: Rect2, seed: int) -> void: WildBirch.scatter(root, body, r, seed, hf, exits, meshes, water_z, core)
	parent.add_child(w)
	return w


static func scatter(root: Node3D, body: StaticBody3D, r: Rect2, seed: int, hf: Callable, exits: Array, meshes: Array, water_z: float, core := Rect2()) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var noise := FastNoiseLite.new()
	noise.seed = 311
	noise.frequency = 0.03
	var c := r.get_center()
	var origin := Vector3(c.x, 0, c.y)
	var per := [[], []]
	var x := r.position.x + 1.0
	while x < r.end.x:
		var z := r.position.y + 1.0
		while z < r.end.y:
			var p := Vector3(x + rng.randf_range(-1.6, 1.6), 0, z + rng.randf_range(-1.6, 1.6))
			var dens := clampf(noise.get_noise_2d(p.x, p.z) * 0.9 + 0.45, 0.08, 0.75)
			if rng.randf() < dens and p.z < water_z - 1.5 and not core.grow(2.0).has_point(Vector2(p.x, p.z)) and not Edges._in_corridor(p, exits):
				p.y = float(hf.call(p.x, p.z))
				per[rng.randi() % 2].append([p, rng.randf() * TAU, rng.randf_range(0.85, 1.2)])
			z += TREE_STEP
		x += TREE_STEP
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.2
	trunk.height = 3.0
	for k in 2:
		var list: Array = per[k]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[k]
		mm.instance_count = list.size()
		for i in list.size():
			var t: Array = list[i]
			var s := float(t[2])
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(t[1])).scaled(Vector3(s, s, s)), (t[0] as Vector3) - origin))
			var tc := CollisionShape3D.new()
			tc.shape = trunk
			tc.position = (t[0] as Vector3) - origin + Vector3(0, 1.5, 0)
			body.add_child(tc)
		var mi := MultiMeshInstance3D.new()
		mi.name = "WildBirches%d" % k
		var spots := PackedVector3Array()             # 无界面时读不回多实例的变换：另记一份位置（测试查出口的路上有没有树）
		for t: Array in list:
			spots.append(t[0])
		mi.set_meta("spots", spots)
		mi.multimesh = mm
		mi.visibility_range_end = 140.0
		root.add_child(mi)
