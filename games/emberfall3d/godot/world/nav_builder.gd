class_name NavBuilder
extends RefCounted
## 导航网格（TECH.md 第 4.1 节）：
## - make_region()：建一个导航区域，关卡的墙体 / 地面作为它的子节点，运行时烘焙；
## - bake()：同步烘焙（网页导出没有线程），返回耗时毫秒；
## - bench_dungeon()：用 V0.1 同款「房间 + 走廊」随机生成一整层地下城的几何体，只烘焙不显示，
##   实测一层地下城的运行时烘焙耗时（TECH.md 第九节风险：「网页运行时烘焙导航网格太慢」）。

const PARSE_MASK := 1 | 4      # 世界层 + 地面层


static func make_navmesh(cell_size := 0.25) -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.cell_size = cell_size
	# 半径必须是 cell_size 的整数倍、高度类参数必须是 cell_height 的整数倍，否则烘焙时引擎会取整并报警告（1.3 网页实测）。
	# 半径按格子向上取整：0.25 米格子 → 0.5 米（主角碰撞半径 0.35 米，路径离墙留一点余量）。
	nm.cell_height = 0.25
	nm.agent_radius = ceilf(0.4 / cell_size - 0.001) * cell_size
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = PARSE_MASK
	return nm


static func make_region() -> NavigationRegion3D:
	var r := NavigationRegion3D.new()
	r.navigation_mesh = make_navmesh()
	return r


static func bake(region: NavigationRegion3D) -> float:
	var t0 := Time.get_ticks_usec()
	region.bake_navigation_mesh(false)
	return (Time.get_ticks_usec() - t0) / 1000.0


static func bench_dungeon(seed_value: int = 7, cell_size: float = 0.25) -> Dictionary:
	## 58×58 格、每格 2 米（116 米见方），与 V0.1 地下城同规模。
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var w := 58
	var h := 58
	var tile := 2.0
	var grid := PackedByteArray()
	grid.resize(w * h)
	var rooms: Array = []
	for k in 600:
		if rooms.size() >= 14:
			break
		var rw := rng.randi_range(5, 10)
		var rh := rng.randi_range(5, 10)
		var rx := rng.randi_range(2, w - rw - 3)
		var ry := rng.randi_range(2, h - rh - 3)
		var ok := true
		for r in rooms:
			if rx < r.x + r.z + 2 and rx + rw + 2 > r.x and ry < r.y + r.w + 2 and ry + rh + 2 > r.y:
				ok = false
				break
		if ok:
			rooms.append(Vector4i(rx, ry, rw, rh))
	for r in rooms:
		for y in range(r.y, r.y + r.w):
			for x in range(r.x, r.x + r.z):
				grid[y * w + x] = 1
	for i in range(1, rooms.size()):
		var a: Vector4i = rooms[i - 1]
		var b: Vector4i = rooms[i]
		var x := a.x + a.z / 2
		var y := a.y + a.w / 2
		var tx := b.x + b.z / 2
		var ty := b.y + b.w / 2
		while x != tx:
			grid[y * w + x] = 1
			grid[(y + 1) * w + x] = 1
			x += signi(tx - x)
		while y != ty:
			grid[y * w + x] = 1
			grid[y * w + x + 1] = 1
			y += signi(ty - y)
	var geo := NavigationMeshSourceGeometryData3D.new()
	var floor_tiles := 0
	var wall_tiles := 0
	for y in h:
		for x in w:
			var i := y * w + x
			var x0 := x * tile
			var z0 := y * tile
			if grid[i] == 1:
				floor_tiles += 1
				geo.add_faces(PackedVector3Array([
					Vector3(x0, 0, z0), Vector3(x0 + tile, 0, z0), Vector3(x0 + tile, 0, z0 + tile),
					Vector3(x0, 0, z0), Vector3(x0 + tile, 0, z0 + tile), Vector3(x0, 0, z0 + tile)]), Transform3D.IDENTITY)
			elif _near_floor(grid, w, h, x, y):
				wall_tiles += 1
				_add_box(geo, Vector3(x0, 0, z0), Vector3(tile, 3.2, tile))
	var nm := make_navmesh(cell_size)
	var t0 := Time.get_ticks_usec()
	NavigationServer3D.bake_from_source_geometry_data(nm, geo, Callable())
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	return {"ms": ms, "polygons": nm.get_polygon_count(), "floor_tiles": floor_tiles, "wall_tiles": wall_tiles, "rooms": rooms.size(), "cell_size": cell_size}


static func _near_floor(grid: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var nx: int = x + dx
			var ny: int = y + dy
			if nx >= 0 and ny >= 0 and nx < w and ny < h and grid[ny * w + nx] == 1:
				return true
	return false


static func _add_box(geo: NavigationMeshSourceGeometryData3D, o: Vector3, s: Vector3) -> void:
	var b := BoxMesh.new()
	b.size = s
	geo.add_mesh(b, Transform3D(Basis.IDENTITY, o + s * 0.5))
