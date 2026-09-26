class_name TownGen
extends RefCounted
## 烬原镇的格子布局（P7，移植 V0.1 genTown 的手工布局，参数在 act1_rules.json floors.town）。
## 输出与 DungeonGen 相同格式的字典（w、h、t、deco、up、down、torches……），另加：
##   paths（石板路格子）、trees（树格子）、houses（房屋矩形）、props、npcs、portal_spot、start。
## 树林外圈的疏密用固定种子，每次进镇都一样。

const TREE := 6


static func generate(seed_value: int = 20260926) -> Dictionary:
	var T: Dictionary = Act1Data.rules().floors.town
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var w := int(T.size[0])
	var h := int(T.size[1])
	var t := PackedByteArray()
	t.resize(w * h)
	t.fill(DungeonGen.FLOOR)
	var path := {}
	for p in T.paths:
		for y in range(int(p.y[0]), int(p.y[1]) + 1):
			for x in range(int(p.x[0]), int(p.x[1]) + 1):
				path[Vector2i(x, y)] = true
	# 外围树林：最外 2 格全是树，往里 2 格有 45% 的格子是树（石板路上不长树）
	var trees: Array = []
	for y in h:
		for x in w:
			var e := mini(mini(x, y), mini(w - 1 - x, h - 1 - y))
			if e < int(T.forest_edge) or (e < int(T.forest_fuzzy) and rng.randf() < float(T.forest_chance) and not path.has(Vector2i(x, y))):
				t[y * w + x] = TREE
				trees.append(Vector2i(x, y))
	var M: Dictionary = T.monastery
	for r in M.walls:
		t = _rect(t, w, r, DungeonGen.WALL)
	t = _rect(t, w, M.floor, DungeonGen.FLOOR)
	for p in M.pillars:
		t[int(p[1]) * w + int(p[0])] = DungeonGen.WALL
	# V0.1 的地窖入口是并排两格楼梯；3D 里一组楼梯占 2 × 2 米，只用第一格，第二格当普通地面
	t[int(M.down[0][1]) * w + int(M.down[0][0])] = DungeonGen.DOWN
	var houses: Array = []
	for hs in T.houses:
		t = _rect(t, w, hs.rect, DungeonGen.WALL)
		houses.append({"id": hs.id, "rect": Rect2i(int(hs.rect[0]), int(hs.rect[1]), int(hs.rect[2]) - int(hs.rect[0]) + 1, int(hs.rect[3]) - int(hs.rect[1]) + 1)})
	# 实心道具占住的格子不能走（V0.1 m.solid）
	var solid := {}
	for p in T.props:
		solid[Vector2i(floori(p.x), floori(p.y))] = p.type
	var deco := PackedByteArray()
	deco.resize(w * h)
	var torches: Array = []
	for tc in T.torches:
		torches.append({"cell": Vector2i(floori(tc.x), floori(tc.y)), "face": Vector2i(int(tc.face[0]), int(tc.face[1]))})
	var down := Vector2i(int(M.down[0][0]), int(M.down[0][1]))
	return {
		"w": w, "h": h, "floor": 0, "theme": "town", "t": t, "deco": deco, "rooms": [], "start": -1, "boss_room": -1,
		"up": Vector2i(-1, -1), "down": down, "boss_stairs": Vector2i(-1, -1), "torches": torches, "spawns": [],
		"paths": path.keys(), "trees": trees, "houses": houses, "props": T.props, "solid": solid, "npcs": T.npcs,
		"portal_spot": Vector2(T.portal_spot[0], T.portal_spot[1]), "start_pos": Vector2(T.start[0], T.start[1]),
	}


## 填矩形（PackedByteArray 是值类型：闭包里改不到外面的数组，所以返回改好的数组）
static func _rect(t: PackedByteArray, w: int, r: Array, v: int) -> PackedByteArray:
	for y in range(int(r[1]), int(r[3]) + 1):
		for x in range(int(r[0]), int(r[2]) + 1):
			t[y * w + x] = v
	return t


## V0.1 的格子坐标（可以带小数）→ 3D 世界坐标（1 格 = 2 米，与地下城相同）
static func to_world(x: float, y: float) -> Vector3:
	return Vector3(x * DungeonBuilder.TILE, 0.0, y * DungeonBuilder.TILE)
