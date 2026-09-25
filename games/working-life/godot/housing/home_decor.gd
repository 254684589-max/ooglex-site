class_name HomeDecor
extends Node3D
## 自己房子里的家具（装修）：按 HousingManager.owned 里每套房的家具，在房间里生成模型与可以使用的交互点
## （躺沙发、看电视、看书、跑步）。每秒检查一次家具有没有变化，变了就重建那套房。
## 摆放位置按房间尺寸计算（房间是楼的后半部分：床在左后角、衣柜在右后角、电脑桌在右前方）。

## 家具位置（房间坐标，w / d 为楼的宽和深）：[x, y, z, 朝向]
static func slot_xf(slot: String, w: float, d: float) -> Array:
	match slot:
		"tv":
			return [-3.2, 0.0, -d * 0.5 + BuildingKit.WALL_T + 0.25, 0.0]
		"sofa":
			return [-3.2, 0.0, -d * 0.5 + 3.8, 0.0]
		"rug":
			return [-3.2, 0.0, -d * 0.5 + 2.2, 0.0]
		"lamp":
			return [-5.2, 0.0, -d * 0.5 + 4.1, 0.0]
		"art":
			return [1.4, 1.75, -d * 0.5 + BuildingKit.WALL_T + 0.03, 0.0]
		"bookshelf":
			return [w * 0.5 - BuildingKit.WALL_T - 0.2, 0.0, -2.9, PI * 0.5]
		"plant":
			return [2.4, 0.0, -0.8, 0.0]
		"treadmill":
			return [-w * 0.5 + 1.1, 0.0, -2.9, 0.0]
		"bedding":
			return [-w * 0.5 + 1.6, 0.0, -d * 0.5 + 1.8, 0.0]
	return [0.0, 0.0, 0.0, 0.0]


var _built: Dictionary = {}
var _timer := 0.0


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	refresh()


## 家具有变化的房子重建，已经不是自己的房子就清掉
func refresh() -> void:
	var want: Dictionary = {}
	for id in HousingManager.owned:
		want[id] = JSON.stringify(HousingManager.furniture_of(id))
	for id in _built.keys():
		if not want.has(id) or String(_built[id]["sig"]) != String(want[id]):
			(_built[id]["node"] as Node).queue_free()
			_built.erase(id)
	for id in want:
		if not _built.has(id):
			var n := _build_home(String(id))
			if n != null:
				_built[id] = {"node": n, "sig": want[id]}


func node_of(home: String) -> Node3D:
	return _built[home]["node"] if _built.has(home) else null


func _build_home(home: String) -> Node3D:
	var loc := String(HousingManager.data(home).get("location", ""))
	var door := GameManager.lookup("door:" + loc) as Node3D
	var ld: Dictionary = DataDB.locations.get(loc, {})
	if door == null or ld.is_empty():
		return null
	var size: Array = ld.get("size", [18, 16])
	var w := float(size[0])
	var d := float(size[1])
	var root := Node3D.new()
	root.name = "Decor_" + home
	add_child(root)
	root.global_transform = door.global_transform
	var mb := MeshBatcher.new()
	mb.chunked = false
	var furn := HousingManager.furniture_of(home)
	for slot in furn:
		var it: Dictionary = DataDB.furniture.get(String(furn[slot]), {})
		if it.is_empty():
			continue
		var t := slot_xf(String(slot), w, d)
		var at := Vector3(float(t[0]), float(t[1]), float(t[2]))
		var rot := Basis(Vector3.UP, float(t[3]))
		_item(mb, root, String(slot), it, at, rot)
		var use := String(it.get("use", ""))
		if use != "":
			_use_point(root, home, loc, use, String(it["id"]), String(slot), at, w, d)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.to_mesh()
	root.add_child(mi)
	return root


func _cols(it: Dictionary) -> Array:
	var out: Array = []
	for h in it.get("colors", ["#888888"]):
		out.append(Mats.hex(String(h), Color(0.5, 0.5, 0.5)))
	while out.size() < 3:
		out.append(out[out.size() - 1])
	return out


## 生成一件家具的几何体（局部坐标：at 为摆放点，rot 为朝向）
func _item(mb: MeshBatcher, root: Node3D, slot: String, it: Dictionary, at: Vector3, rot: Basis) -> void:
	var c: Array = _cols(it)
	var tier := int(it.get("tier", 1))
	var P := func(v: Vector3) -> Vector3: return at + rot * v
	match slot:
		"tv":
			mb.box("solid", P.call(Vector3(0, 0.25, 0)), Vector3(2.2, 0.5, 0.45), c[1], rot)
			var sw: float = [0.8, 1.25, 1.9][tier - 1]
			var sh := sw * 0.58
			mb.box("metal", P.call(Vector3(0, 0.62 + sh * 0.5, 0.02)), Vector3(sw + 0.05, sh + 0.05, 0.05), c[0], rot)
			mb.box("neon", P.call(Vector3(0, 0.62 + sh * 0.5, 0.05)), Vector3(sw - 0.02, sh - 0.02, 0.01), Color(0.1, 0.16, 0.26), rot)
			if tier >= 2:
				mb.box("metal", P.call(Vector3(0.7, 0.54, 0.05)), Vector3(0.3, 0.07, 0.25), Color(0.92, 0.92, 0.9), rot)
			if tier >= 3:
				for sx in [-1.35, 1.35]:
					mb.box("solid", P.call(Vector3(sx, 0.55, 0.0)), Vector3(0.3, 1.1, 0.3), c[0], rot)
		"sofa":
			var l: float = [1.6, 2.2, 2.8][tier - 1]
			# 沙发朝向电视（-Z），靠背在 +Z 一侧
			mb.box("prop", P.call(Vector3(0, 0.22, 0)), Vector3(l, 0.44, 0.88), c[0], rot)
			mb.box("prop", P.call(Vector3(0, 0.62, 0.34)), Vector3(l, 0.46, 0.2), c[0], rot)
			for sx in [-1.0, 1.0]:
				mb.box("prop", P.call(Vector3(sx * (l * 0.5 - 0.1), 0.52, 0)), Vector3(0.2, 0.34, 0.88), c[0].darkened(0.1), rot)
			var n := int(l / 0.75)
			for k in n:
				var x := -l * 0.5 + 0.25 + (l - 0.5) * (k + 0.5) / n
				mb.box("prop", P.call(Vector3(x, 0.5, -0.05)), Vector3((l - 0.5) / n - 0.04, 0.12, 0.7), c[0].lightened(0.06), rot)
			if tier >= 2:
				mb.box("solid", P.call(Vector3(0, 0.2, -1.15)), Vector3(1.1, 0.4, 0.55), c[1], rot)
				for sx in [-1.0, 1.0]:
					mb.box("prop", P.call(Vector3(sx * (l * 0.5 - 0.45), 0.72, 0.18)), Vector3(0.42, 0.36, 0.14), c[1], rot)
		"rug":
			var rw: float = [2.4, 2.9, 3.4][tier - 1]
			var rd: float = [1.6, 1.9, 2.3][tier - 1]
			# 地板面在 0.03，地毯贴在上面
			mb.box("prop", P.call(Vector3(0, 0.038, 0)), Vector3(rw, 0.012, rd), c[0], rot)
			mb.box("prop", P.call(Vector3(0, 0.046, 0)), Vector3(rw - 0.3, 0.006, rd - 0.3), c[0].lightened(0.15), rot)
		"lamp":
			mb.cylinder("metal", P.call(Vector3(0, 0.02, 0)), 0.18, 0.04, c[0], 12)
			if tier == 2:
				mb.cylinder("metal", P.call(Vector3(0, 0.85, 0)), 0.02, 1.7, c[0], 6)
				mb.beam("metal", P.call(Vector3(0, 1.7, 0)), P.call(Vector3(0.9, 1.9, 0)), 0.03, c[0])
				mb.cylinder("neon", P.call(Vector3(0.9, 1.72, 0)), 0.22, 0.3, c[1], 12, Basis.IDENTITY, 0.08)
			else:
				mb.cylinder("metal", P.call(Vector3(0, 0.75, 0)), 0.02, 1.5, c[0], 6)
				mb.cylinder("neon", P.call(Vector3(0, 1.55, 0)), 0.2 if tier == 1 else 0.28, 0.32, c[1], 12, Basis.IDENTITY, 0.14 if tier == 1 else 0.2)
				if tier == 3:
					mb.cylinder("neon", P.call(Vector3(0, 1.2, 0)), 0.14, 0.12, c[1], 12)
			if int(SettingsManager.get_v("quality", 1)) >= 1:
				var l3 := OmniLight3D.new()
				l3.light_color = Color(1.0, 0.85, 0.65)
				l3.light_energy = 0.5 + tier * 0.2
				l3.omni_range = 4.5
				l3.position = P.call(Vector3(0.9 if tier == 2 else 0.0, 1.5, 0))
				root.add_child(l3)
		"art":
			var aw: float = [0.6, 1.0, 1.6][tier - 1]
			var ah: float = [0.8, 0.8, 1.1][tier - 1]
			mb.box("solid", P.call(Vector3(0, 0, 0)), Vector3(aw + 0.08, ah + 0.08, 0.04), c[0], rot)
			mb.box("prop", P.call(Vector3(-aw * 0.25, 0, 0.025)), Vector3(aw * 0.5, ah, 0.01), c[1], rot)
			mb.box("prop", P.call(Vector3(aw * 0.25, 0, 0.025)), Vector3(aw * 0.5, ah, 0.01), c[2], rot)
			mb.box("prop", P.call(Vector3(0, -ah * 0.2, 0.03)), Vector3(aw * 0.7, ah * 0.2, 0.01), c[1].lerp(c[2], 0.5).lightened(0.2), rot)
		"bookshelf":
			var bh: float = [1.2, 2.0, 2.4][tier - 1]
			var bw: float = [1.0, 1.8, 2.4][tier - 1]
			var wood: Color = c[0]
			# 背板、两侧、隔板（书架朝 -X，宽度沿 Z）
			mb.box("solid", P.call(Vector3(0, bh * 0.5, 0.16)), Vector3(bw, bh, 0.04), wood.darkened(0.15), rot)
			for sx in [-1.0, 1.0]:
				mb.box("solid", P.call(Vector3(sx * bw * 0.5, bh * 0.5, 0)), Vector3(0.04, bh, 0.36), wood, rot)
			var shelves := int(bh / 0.4)
			var rng := RandomNumberGenerator.new()
			rng.seed = tier * 17
			for k in shelves + 1:
				var y := 0.02 + k * (bh - 0.04) / shelves
				mb.box("solid", P.call(Vector3(0, y, 0)), Vector3(bw, 0.03, 0.36), wood, rot)
				if k < shelves:
					var x := -bw * 0.5 + 0.06
					while x < bw * 0.5 - 0.12:
						var t := rng.randf_range(0.03, 0.07)
						var h := rng.randf_range(0.22, 0.32)
						var bc := Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.6), rng.randf_range(0.35, 0.8))
						mb.box("prop", P.call(Vector3(x + t * 0.5, y + 0.015 + h * 0.5, 0.02)), Vector3(t, h, 0.24), bc, rot)
						x += t + 0.005
						if rng.randf() < 0.08:
							x += 0.15
		"plant":
			var ph: float = [0.5, 1.4, 2.1][tier - 1]
			mb.cylinder("solid", P.call(Vector3(0, 0.2, 0)), 0.2, 0.4, c[0], 12, Basis.IDENTITY, 0.24)
			mb.cylinder("solid", P.call(Vector3(0, 0.39, 0)), 0.19, 0.02, Color(0.22, 0.16, 0.12), 12)
			var rng := RandomNumberGenerator.new()
			rng.seed = 31 + tier
			if tier > 1:
				mb.cylinder("solid", P.call(Vector3(0, 0.4 + ph * 0.35, 0)), 0.03, ph * 0.7, Color(0.35, 0.25, 0.18), 6)
			# 叶子：一片片压扁的小方块，朝外倾斜；龟背竹叶大，发财树叶细而多
			var count: int = [22, 36, 120][tier - 1]
			var leaf: Vector3 = [Vector3(0.16, 0.012, 0.11), Vector3(0.24, 0.014, 0.18), Vector3(0.2, 0.01, 0.07)][tier - 1]
			for k in count:
				var a := rng.randf() * TAU
				var r: float
				var y: float
				if tier == 1:
					r = rng.randf_range(0.08, 0.26)
					y = 0.42 + rng.randf_range(0.0, 0.2) - r * 0.4
				else:
					var hh := rng.randf_range(0.45, 1.0)
					r = rng.randf_range(0.05, 0.45 if tier == 2 else 0.6) * (1.2 - hh * 0.5)
					y = 0.4 + ph * hh
				var lb := Basis.from_euler(Vector3(rng.randf_range(-0.6, 0.2), a, rng.randf_range(-0.4, 0.4)))
				var lc: Color = c[1].lightened(rng.randf_range(-0.15, 0.15))
				mb.box("prop", P.call(Vector3(cos(a) * r, y, sin(a) * r)), leaf * rng.randf_range(0.8, 1.25), lc, rot * lb)
		"treadmill":
			mb.box("metal", P.call(Vector3(0, 0.1, 0)), Vector3(0.8, 0.2, 1.8), c[0], rot)
			mb.box("metal", P.call(Vector3(0, 0.21, 0.05)), Vector3(0.55, 0.02, 1.5), Color(0.06, 0.06, 0.07), rot)
			for sx in [-0.36, 0.36]:
				mb.box("metal", P.call(Vector3(sx, 0.7, -0.75)), Vector3(0.05, 1.1, 0.06), c[1], rot)
			mb.box("metal", P.call(Vector3(0, 1.25, -0.8)), Vector3(0.75, 0.12, 0.25), c[0], rot)
			mb.box("neon", P.call(Vector3(0, 1.3, -0.72)), Vector3(0.3, 0.06, 0.02), c[1] if tier >= 2 else Color(0.3, 0.9, 1.0), rot)
			if tier == 3:
				mb.box("neon", P.call(Vector3(0, 1.1, -1.25)), Vector3(0.7, 1.7, 0.03), c[1] * 0.35, rot)
		"bedding":
			mb.box("prop", P.call(Vector3(0, 0.84, 0.45)), Vector3(1.96, 0.12, 1.85), c[0], rot)
			for sx in [-0.45, 0.45]:
				mb.box("prop", P.call(Vector3(sx, 0.92, -0.95)), Vector3(0.7, 0.16, 0.45), c[1], rot)
			if int(it.get("tier", 1)) >= 3:
				mb.box("prop", P.call(Vector3(0, 0.91, 1.05)), Vector3(2.0, 0.04, 0.55), c[1], rot)


## 可以使用的家具：加一个交互点
func _use_point(root: Node3D, home: String, loc: String, use: String, item: String, slot: String, at: Vector3, w: float, d: float) -> void:
	var spot := at
	var key := "interact"
	var label := ""
	match use:
		"rest":
			spot = at + Vector3(0, 0, -0.6)
			label = "躺沙发休息"
		"tv":
			# 看电视在沙发前面按 F（和躺沙发的 E 不冲突）
			var sofa := slot_xf("sofa", w, d)
			spot = Vector3(float(sofa[0]), 0.0, float(sofa[2]) - 0.6)
			key = "pickup"
			label = "看电视"
		"read":
			spot = at + Vector3(-1.0, 0, 0)
			label = "看书"
		"run":
			spot = at + Vector3(0, 0, 1.3)
			label = "在家跑步"
	var sp := ServicePoint.new()
	root.add_child(sp)
	sp.setup("decor_" + use, label, loc, {"home": home, "item": item, "reach": 2.2, "always_open": true}, key)
	sp.position = spot
	GameManager.register("point:%s:%s" % [loc, "decor_" + use], sp)
