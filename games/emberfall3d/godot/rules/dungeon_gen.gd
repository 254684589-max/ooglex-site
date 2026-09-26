class_name DungeonGen
extends RefCounted
## 随机地下城的格子布局（移植自 V0.1 的 genDungeon / corridor / finishWalls / bfs，阶段 P2）。
## 只生成「哪格是地面、墙、楼梯」与房间、火把、装饰的位置；3D 几何由 world/dungeon_builder.gd 搭。
## 同一楼层 + 同一种子 → 同一张图（回到去过的楼层时布局不变）。
##
## 返回字典：
##   w, h, floor, theme, t(PackedByteArray 格子类型), deco(PackedByteArray 装饰),
##   rooms[{x, y, w, h, cx, cy}], start(房间下标), boss_room(房间下标或 -1),
##   up(Vector2i), down(Vector2i，首领层为 (-1, -1)：击败首领后才出现), boss_stairs(Vector2i，首领房中心),
##   torches[{cell: Vector2i, face: Vector2i（火把朝向的地面方向）}]

const VOID := 0
const FLOOR := 1
const WALL := 2
const DOWN := 3
const UP := 4

const DECO_BONES := 2
const DECO_RUBBLE := 3
const DECO_LAVA := 4


static func walkable(t: int) -> bool:
	return t == FLOOR or t == DOWN or t == UP


static func tile(m: Dictionary, x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= m.w or y >= m.h:
		return VOID
	return m.t[y * m.w + x]


static func generate(floor_i: int, seed_value: int) -> Dictionary:
	var G: Dictionary = Act1Data.rules().floors.generator
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var w := int(G.size[0])
	var h := int(G.size[1])
	var t := PackedByteArray()
	t.resize(w * h)
	var m := {"w": w, "h": h, "floor": floor_i, "theme": FloorRules.theme_for(floor_i), "t": t, "rooms": [], "boss_room": -1,
		"up": Vector2i(-1, -1), "down": Vector2i(-1, -1), "boss_stairs": Vector2i(-1, -1), "torches": []}
	var rooms: Array = m.rooms
	var margin := int(G.room_margin)
	var gap := int(G.room_gap)

	var try_room := func(rw: int, rh: int) -> int:
		for k in int(G.room_tries):
			var x := rng.randi_range(margin, w - rw - margin - 1)
			var y := rng.randi_range(margin, h - rh - margin - 1)
			var ok := true
			for r in rooms:
				if not (x > r.x + r.w + gap or x + rw + gap < r.x or y > r.y + r.h + gap or y + rh + gap < r.y):
					ok = false
					break
			if ok:
				rooms.append({"x": x, "y": y, "w": rw, "h": rh, "cx": x + (rw >> 1), "cy": y + (rh >> 1)})
				return rooms.size() - 1
		return -1

	if FloorRules.is_boss_floor(floor_i):
		m.boss_room = try_room.call(int(G.boss_room[0]), int(G.boss_room[1]))
	var n := int(G.rooms_base) + mini(int(G.rooms_extra_max), floor_i >> 1)
	var k := 0
	while k < n * 4 and rooms.size() < n:
		try_room.call(rng.randi_range(int(G.room_size[0]), int(G.room_size[1])), rng.randi_range(int(G.room_size[0]), int(G.room_size[1])))
		k += 1
	for r in rooms:
		for y in range(r.y, r.y + r.h):
			for x in range(r.x, r.x + r.w):
				t[y * w + x] = FLOOR
	# 注意：PackedByteArray 是值类型。下面走廊与补墙直接改 m.t，改完要重新取回本地变量
	m.t = t

	# 走廊：每次把「离已连通房间最近」的房间连上（曼哈顿距离），保证全部连通；再随机加几条环路
	var conn: Array = [0]
	var rest: Array = range(1, rooms.size())
	while not rest.is_empty():
		var bi := 0
		var bc := 0
		var bd := 1 << 30
		for i in rest.size():
			var ri: Dictionary = rooms[rest[i]]
			for c in conn:
				var rc: Dictionary = rooms[c]
				var d := absi(ri.cx - rc.cx) + absi(ri.cy - rc.cy)
				if d < bd:
					bd = d
					bi = i
					bc = c
		var r_i: int = rest.pop_at(bi)
		_corridor(m, rng, rooms[r_i], rooms[bc], int(G.corridor_width))
		conn.append(r_i)
	for e in int(G.extra_corridors):
		var a := rng.randi_range(0, rooms.size() - 1)
		var b := rng.randi_range(0, rooms.size() - 1)
		if a != b and a != m.boss_room and b != m.boss_room:
			_corridor(m, rng, rooms[a], rooms[b], int(G.corridor_width))
	_finish_walls(m)
	t = m.t

	# 起点：首领层取离首领房最远的房间
	var start := 0
	if m.boss_room >= 0:
		var br: Dictionary = rooms[m.boss_room]
		var far := -1
		for i in rooms.size():
			if i == m.boss_room:
				continue
			var d := absi(rooms[i].cx - br.cx) + absi(rooms[i].cy - br.cy)
			if d > far:
				far = d
				start = i
		m.boss_stairs = Vector2i(br.cx, br.cy)
	m.start = start
	var sr: Dictionary = rooms[start]
	m.up = Vector2i(sr.cx, sr.cy)
	t[sr.cy * w + sr.cx] = UP
	m.t = t
	var dist := bfs(m, m.up)
	m.dist = dist
	if m.boss_room < 0:
		var best := start
		var far := -1
		for i in rooms.size():
			if i == start:
				continue
			var d: int = dist[rooms[i].cy * w + rooms[i].cx]
			if d > far:
				far = d
				best = i
		var dr: Dictionary = rooms[best]
		m.down = Vector2i(dr.cx, dr.cy)
		t[dr.cy * w + dr.cx] = DOWN

	# 装饰：白骨、碎石；熔渊与深渊加熔岩裂缝
	var D: Dictionary = G.deco
	var lava: bool = Act1Data.rules().floors.themes[m.theme].get("lava", false)
	var deco := PackedByteArray()
	deco.resize(w * h)
	for i in w * h:
		if t[i] == FLOOR:
			var r := rng.randf()
			if r < D.bones_below:
				deco[i] = DECO_BONES
			elif r < D.rubble_below:
				deco[i] = DECO_RUBBLE
			elif lava and r < D.lava_below:
				deco[i] = DECO_LAVA
	m.deco = deco

	# 火把：挂在「朝南或朝东有地面」的墙上，彼此至少隔 6 格（V0.1 的两个朝向 = 屏幕上看得见的墙面）
	var T: Dictionary = G.torch
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if t[y * w + x] != WALL or rng.randf() > T.chance:
				continue
			var face := Vector2i.ZERO
			if walkable(t[(y + 1) * w + x]):
				face = Vector2i(0, 1)
			elif walkable(t[y * w + x + 1]):
				face = Vector2i(1, 0)
			if face == Vector2i.ZERO:
				continue
			var near := false
			for tc in m.torches:
				if absi(tc.cell.x - x) + absi(tc.cell.y - y) < int(T.min_spacing):
					near = true
					break
			if not near:
				m.torches.append({"cell": Vector2i(x, y), "face": face})
	m.t = t
	m.spawns = _room_packs(m, rng)
	m.boss_key = ""
	if m.boss_room >= 0:
		m.spawns.append_array(_boss_pack(m, rng))
	# 木桶、宝箱、神殿（P10）用单独的随机数：不改变 P2–P9 已有的布局与刷怪
	var prng := RandomNumberGenerator.new()
	prng.seed = seed_value ^ 0x9e3779
	m.props = _room_props(m, prng)
	return m


## 房间里的道具（P10，V0.1 genDungeon「房间内容」）：起点房与首领房以外，每个房间 0–3 个木桶、20% 一个宝箱；
## 整层 75% 有一座神殿，出现在某个房间的概率每间 30%（先到先得）。不放在楼梯与怪物的格子上。
## 返回 [{type: "barrel" / "chest" / "shrine", cell, room}]
static func _room_props(m: Dictionary, rng: RandomNumberGenerator) -> Array:
	var P: Dictionary = Act1Data.rules().floors.props
	var used := {}
	for sp in m.spawns:
		used[sp.cell] = true
	var out: Array = []
	var shrine := rng.randf() < float(P.shrine_floor_chance)
	for ri in m.rooms.size():
		if ri == m.start or ri == m.boss_room:
			continue
		var r: Dictionary = m.rooms[ri]
		var spot := func() -> Vector2i:
			for k in 30:
				var c := Vector2i(rng.randi_range(r.x + 1, r.x + r.w - 2), rng.randi_range(r.y + 1, r.y + r.h - 2))
				if m.t[c.y * m.w + c.x] == FLOOR and not used.has(c):
					used[c] = true
					return c
			return Vector2i(-1, -1)
		for i in rng.randi_range(int(P.barrels_per_room[0]), int(P.barrels_per_room[1])):
			var c: Vector2i = spot.call()
			if c.x >= 0:
				out.append({"type": "barrel", "cell": c, "room": ri})
		if rng.randf() < float(P.chest_chance):
			var c: Vector2i = spot.call()
			if c.x >= 0:
				out.append({"type": "chest", "cell": c, "room": ri})
		if shrine and rng.randf() < float(P.shrine_room_chance):
			var c: Vector2i = spot.call()
			if c.x >= 0:
				out.append({"type": "shrine", "cell": c, "room": ri})
				shrine = false
	return out


## 首领房（P9，V0.1 genDungeon）：房间正中是首领（第 3 层莫格、第 6 层摩登、深渊首领层随机一个并改名「深渊化身」），
## 另有 4 只护卫：莫格带腐尸、摩登带骸骨战士，深渊层从本层怪物池里挑。首领条目带 boss = true。
static func _boss_pack(m: Dictionary, rng: RandomNumberGenerator) -> Array:
	var bk := FloorRules.boss_for(rng, m.floor)
	m.boss_key = bk
	var r: Dictionary = m.rooms[m.boss_room]
	var boss := {"key": bk, "cell": Vector2i(r.cx, r.cy), "champ": "", "room": m.boss_room, "boss": true}
	var abyss: bool = int(m.floor) > int(Act1Data.rules().floors.boss_floors[-1])
	if abyss:
		boss.name = Act1Data.rules().floors.abyss_boss_names[bk]
	var out: Array = [boss]
	var pool := FloorRules.monster_pool(m.floor)
	var used := {boss.cell: true}
	for i in 4:
		for tries in 30:
			var c := Vector2i(rng.randi_range(r.x + 1, r.x + r.w - 2), rng.randi_range(r.y + 1, r.y + r.h - 2))
			if m.t[c.y * m.w + c.x] == FLOOR and not used.has(c):
				used[c] = true
				var g: String = pool[rng.randi_range(0, pool.size() - 1)] if abyss else Act1Data.rules().floors.boss_guards[bk]
				out.append({"key": g, "cell": c, "champ": "", "room": m.boss_room})
				break
	return out


## 房间里的怪物群（V0.1 genDungeon「房间内容」）：起点房与首领房不刷；每个房间 72% 有一群，
## 其中 12% 是精英群（同一种精英特性，2–3 只），否则 2–4 只（第 3 层以下 +1），30% 的群混合几种怪。
## 返回 [{key, cell, champ, room}]；key 是 V0.1 的怪物键名。首领与护卫见 _boss_pack（P9）。
static func _room_packs(m: Dictionary, rng: RandomNumberGenerator) -> Array:
	var P: Dictionary = Act1Data.rules().monsters.pack
	var C: Dictionary = Act1Data.rules().monsters.champion
	var champs: Array = Act1Data.monsters().champions.keys()
	var pool := FloorRules.monster_pool(m.floor)
	var out: Array = []
	for ri in m.rooms.size():
		if ri == m.start or ri == m.boss_room:
			continue
		if rng.randf() >= float(P.chance):
			continue
		var champ: String = champs[rng.randi_range(0, champs.size() - 1)] if rng.randf() < float(C.chance) else ""
		var mixed := rng.randf() < float(P.mixed_chance)
		var k0: String = pool[rng.randi_range(0, pool.size() - 1)]
		var cnt := rng.randi_range(int(P.champion_size[0]), int(P.champion_size[1])) if champ != "" else rng.randi_range(int(P.size[0]), int(P.size[1])) + (1 if m.floor > int(P.deep_bonus_after_floor) else 0)
		var r: Dictionary = m.rooms[ri]
		var used := {}
		for i in cnt:
			for tries in 30:
				var c := Vector2i(rng.randi_range(r.x + 1, r.x + r.w - 2), rng.randi_range(r.y + 1, r.y + r.h - 2))
				if m.t[c.y * m.w + c.x] == FLOOR and not used.has(c):
					used[c] = true
					out.append({"key": pool[rng.randi_range(0, pool.size() - 1)] if mixed else k0, "cell": c, "champ": champ, "room": ri})
					break
	return out


static func _corridor(m: Dictionary, rng: RandomNumberGenerator, a: Dictionary, b: Dictionary, width: int) -> void:
	var x: int = a.cx
	var y: int = a.cy
	var tx: int = b.cx
	var ty: int = b.cy
	var t: PackedByteArray = m.t
	var cells: Array[Vector2i] = []
	if rng.randf() < 0.5:
		while x != tx:
			cells.append(Vector2i(x, y))
			x += signi(tx - x)
		while y != ty:
			cells.append(Vector2i(x, y))
			y += signi(ty - y)
	else:
		while y != ty:
			cells.append(Vector2i(x, y))
			y += signi(ty - y)
		while x != tx:
			cells.append(Vector2i(x, y))
			x += signi(tx - x)
	cells.append(Vector2i(x, y))
	for c in cells:
		for dy in width:
			for dx in width:
				var X := c.x + dx
				var Y := c.y + dy
				if X > 0 and Y > 0 and X < m.w - 1 and Y < m.h - 1:
					t[Y * m.w + X] = FLOOR
	m.t = t


## 紧挨地面（含斜角）的空格变成墙
static func _finish_walls(m: Dictionary) -> void:
	var w: int = m.w
	var h: int = m.h
	var t: PackedByteArray = m.t
	var add: Array = []
	for y in h:
		for x in w:
			if t[y * w + x] != VOID:
				continue
			var nb := false
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var X: int = x + dx
					var Y: int = y + dy
					if X >= 0 and Y >= 0 and X < w and Y < h and walkable(t[Y * w + X]):
						nb = true
						break
				if nb:
					break
			if nb:
				add.append(y * w + x)
	for i in add:
		t[i] = WALL
	m.t = t


## 四方向步数距离（走不到为 -1）
static func bfs(m: Dictionary, from: Vector2i) -> PackedInt32Array:
	var w: int = m.w
	var d := PackedInt32Array()
	d.resize(w * m.h)
	d.fill(-1)
	var q := PackedInt32Array([from.y * w + from.x])
	d[q[0]] = 0
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var x := i % w
		var y := i / w
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var X: int = x + o.x
			var Y: int = y + o.y
			if not walkable(tile(m, X, Y)):
				continue
			var j := Y * w + X
			if d[j] >= 0:
				continue
			d[j] = d[i] + 1
			q.append(j)
	return d


## 离 (x, y) 最近的空地面格（不站在楼梯上），V0.1 nearFree
static func near_free(m: Dictionary, at: Vector2i, avoid_stairs := true) -> Vector2i:
	for rad in range(1, 6):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				var X := at.x + dx
				var Y := at.y + dy
				var tt := tile(m, X, Y)
				if not walkable(tt):
					continue
				if avoid_stairs and (tt == DOWN or tt == UP):
					continue
				return Vector2i(X, Y)
	return at
