class_name Fog
extends RefCounted
## 视野（P8，移植 V0.1 computeVis）：以主角为圆心、半径 光照 + 2 格，逐格做视线检测（墙、树、虚空挡视线），
## 看得见的格子记入 vis（本帧可见）与 seen（到过、自动地图上显示）。与可见地面相邻的墙也算看见（避免墙体缺口）。
## P8 只用它画小地图与自动地图；地牢里的战争迷雾与光照范围在 P10。镇上全部可见（V0.1 genTown seen.fill(1)）。


static func opaque(m: Dictionary, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= m.w or y >= m.h:
		return true
	var t: int = m.t[y * m.w + x]
	return t == DungeonGen.WALL or t == DungeonGen.VOID or t == TownGen.TREE


## p = 主角所在的格子坐标（带小数，1 格 = DungeonBuilder.TILE 米）；R = 半径（格）。
## vis 先清零再重算；seen 只增不减。PackedByteArray 是值类型，所以返回 [vis, seen]。
static func compute(m: Dictionary, vis: PackedByteArray, seen: PackedByteArray, p: Vector2, R: int) -> Array:
	vis.fill(0)
	var x0 := floori(p.x)
	var y0 := floori(p.y)
	for y in range(y0 - R, y0 + R + 1):
		for x in range(x0 - R, x0 + R + 1):
			if x < 0 or y < 0 or x >= m.w or y >= m.h:
				continue
			var dx := x + 0.5 - p.x
			var dy := y + 0.5 - p.y
			var d := sqrt(dx * dx + dy * dy)
			if d > R:
				continue
			var n := ceili(d * 3.0)
			var ok := true
			for s in range(1, n):
				var cx := floori(p.x + dx * s / n)
				var cy := floori(p.y + dy * s / n)
				if cx == x and cy == y:
					break
				if opaque(m, cx, cy):
					ok = false
					break
			if ok:
				vis[y * m.w + x] = 1
				seen[y * m.w + x] = 1
	for y in range(maxi(1, y0 - R), mini(m.h - 2, y0 + R) + 1):
		for x in range(maxi(1, x0 - R), mini(m.w - 2, x0 + R) + 1):
			var i: int = y * m.w + x
			if m.t[i] != DungeonGen.WALL or vis[i]:
				continue
			for oy in [-1, 0, 1]:
				for ox in [-1, 0, 1]:
					var j: int = (y + oy) * m.w + x + ox
					if vis[j] and DungeonGen.walkable(m.t[j]):
						vis[i] = 1
						seen[i] = 1
	return [vis, seen]
