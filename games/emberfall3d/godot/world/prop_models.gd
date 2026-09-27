class_name PropModels
extends RefCounted
## 代码搭的道具与房屋细节（2.6 之五）：和角色同一套做法（RigBuilder 拼几何体、明暗画进顶点色），只是不绑骨骼。
## 同一种道具只生成一次网格，所有实例共用；材质每个实例一份（神殿用过要熄灭）。
##   barrel 木桶（鼓肚木板 + 铁箍 + 桶盖）· chest / chest_lid 宝箱（包铁木箱 + 铆钉；盖子单独一个网格，绕后边铰链打开）
##   shrine 神殿石台（台阶底座 + 刻纹石柱 + 托着晶石的石爪）· shrine_crystal 悬浮的晶石（只有发光面）
##   well 水井（石砌井圈 + 木架 + 小顶棚 + 辘轳 + 水桶）· anvil 铁砧（树桩 + 带角的铁砧）
##   waystone 传送石（带符文的方尖石碑）· campfire 篝火（一圈石头 + 交叉的木柴 + 余烬）
##   house(rect, door_dir)：房屋外立面的木构架、门、亮着灯的窗、烟囱、屋脊与封檐板（按房屋大小生成，不缓存）
## 2.6 之六（多实例摆放的，面数要低：多实例网格不会逐个剔除）：
##   tree_pine 暗色针叶树 · tree_dead 被烧焦的枯树 · tree_broad 团簇状的阔叶树（整棵一个面、颜色画在顶点色里，一片林子一次绘制）
##   bone 腿骨 · skull 头骨 · rock 碎石块 · lava_crack 熔岩裂缝（地下城地面装饰）
##   dummy 训练木桩（木桩底座、麻袋塞草的身子、横杆手臂、缝着脸的麻袋头）

const WOOD := Color(0.4, 0.27, 0.15)
const DARK_WOOD := Color(0.24, 0.16, 0.1)
const IRON := Color(0.3, 0.3, 0.33)
const STONE := Color(0.46, 0.44, 0.42)

static var _cache := {}


static func get_model(id: String) -> Dictionary:
	if not _cache.has(id):
		var rb := RigBuilder.new()
		var glow := Color(1, 0.6, 0.2)
		match id:
			"barrel":
				_barrel(rb)
			"chest":
				_chest(rb)
			"chest_lid":
				_chest_lid(rb)
			"shrine":
				_shrine(rb)
			"shrine_crystal":
				_crystal(rb)
				glow = Color(0.45, 0.8, 1.0)
			"well":
				_well(rb)
			"anvil":
				_anvil(rb)
			"waystone":
				_waystone(rb)
				glow = Color(0.35, 0.7, 1.0)
			"campfire":
				_campfire(rb)
				glow = Color(1.0, 0.45, 0.12)
			"tree_pine":
				_tree_pine(rb)
			"tree_dead":
				_tree_dead(rb)
			"tree_broad":
				_tree_broad(rb)
			"bone":
				_bone(rb)
			"skull":
				_skull(rb)
			"rock":
				_rock(rb)
			"lava_crack":
				_lava_crack(rb)
				glow = Color(1.0, 0.45, 0.12)
			"dummy":
				_dummy(rb)
		var m := rb.commit_static()
		m.glow = glow
		_cache[id] = m
	return _cache[id]


static func ids() -> Array:
	return ["barrel", "chest", "chest_lid", "shrine", "shrine_crystal", "well", "anvil", "waystone", "campfire",
		"tree_pine", "tree_dead", "tree_broad", "bone", "skull", "rock", "lava_crack", "dummy"]


## 多实例摆放用的材质（顶点色；树、碎石、白骨）
static func multi_material() -> StandardMaterial3D:
	var m := CharRig.surface_material(RigBuilder.BODY, Color(0, 0, 0), 0.0)
	m.emission_enabled = false
	return m


## 生成一个道具的 MeshInstance3D（材质每个实例一份）
static func instance(id: String) -> MeshInstance3D:
	return _mesh_instance(get_model(id), id)


static func _mesh_instance(m: Dictionary, nm: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m.mesh
	mi.name = nm
	var surfaces: Array = m.surfaces
	for s in surfaces.size():
		mi.set_surface_override_material(s, CharRig.surface_material(surfaces[s], m.glow, 0.15))
	return mi


# ---------------- 地下城道具 ----------------

static func _barrel(rb: RigBuilder) -> void:
	# 鼓肚的木板桶身：一圈竖木板（相邻木板颜色略有不同）
	var n := 12
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var col := WOOD.lerp(DARK_WOOD, 0.15 + 0.25 * RigBuilder._hash(i * 7 + 3))
		var ys := [0.02, 0.2, 0.45, 0.7, 0.88]
		var rs := [0.3, 0.35, 0.38, 0.35, 0.3]
		for k in ys.size() - 1:
			var p00 := Vector3(cos(a0) * rs[k], ys[k], sin(a0) * rs[k])
			var p01 := Vector3(cos(a1) * rs[k], ys[k], sin(a1) * rs[k])
			var p10 := Vector3(cos(a0) * rs[k + 1], ys[k + 1], sin(a0) * rs[k + 1])
			var p11 := Vector3(cos(a1) * rs[k + 1], ys[k + 1], sin(a1) * rs[k + 1])
			var nm := Vector3(cos((a0 + a1) / 2.0), 0, sin((a0 + a1) / 2.0))
			_quad(rb, p00, p01, p11, p10, nm, col)
	for y in [0.12, 0.34, 0.56, 0.78]:
		var r := 0.3 + 0.08 * sin(PI * (y - 0.02) / 0.86) + 0.012
		rb.tube([Vector3(0, y - 0.025, 0), Vector3(0, y + 0.025, 0)], [Vector2(r, r), Vector2(r, r)], [0, 0], IRON, RigBuilder.METAL, 14, false)
	rb.ellipsoid(Vector3(0, 0.87, 0), Vector3(0.29, 0.02, 0.29), 0, DARK_WOOD, RigBuilder.BODY, Basis.IDENTITY, 2, 12)
	rb.block(Vector3(0, 0.885, 0), Vector3(0.5, 0.02, 0.05), 0, DARK_WOOD.darkened(0.2))


static func _quad(rb: RigBuilder, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nm: Vector3, col: Color) -> void:
	var i0 := rb._vert(RigBuilder.BODY, a, nm, col, 0)
	var i1 := rb._vert(RigBuilder.BODY, b, nm, col, 0)
	var i2 := rb._vert(RigBuilder.BODY, c, nm, col, 0)
	var i3 := rb._vert(RigBuilder.BODY, d, nm, col, 0)
	rb._tri(RigBuilder.BODY, i0, i1, i2)
	rb._tri(RigBuilder.BODY, i0, i2, i3)


static func _chest(rb: RigBuilder) -> void:
	# 箱身：木板 + 竖向铁箍 + 包角 + 四只脚
	rb.block(Vector3(0, 0.27, 0), Vector3(0.88, 0.46, 0.53), 0, WOOD)
	for z in [-0.12, 0.12]:
		rb.block(Vector3(0, 0.27, z * 2.25), Vector3(0.9, 0.012, 0.012), 0, DARK_WOOD)          # 木板缝
	for x in [-0.28, 0.28]:
		rb.block(Vector3(x, 0.27, 0), Vector3(0.07, 0.48, 0.56), 0, IRON, RigBuilder.METAL)
		for z in [-0.28, 0.28]:
			rb.ellipsoid(Vector3(x, 0.4, z), Vector3(0.018, 0.018, 0.018), 0, IRON.lightened(0.2), RigBuilder.METAL, Basis.IDENTITY, 2, 5)
	for x in [-0.44, 0.44]:
		for z in [-0.265, 0.265]:
			rb.block(Vector3(x, 0.27, z), Vector3(0.07, 0.5, 0.07), 0, IRON.darkened(0.1), RigBuilder.METAL)
			rb.block(Vector3(x * 0.9, 0.02, z * 0.9), Vector3(0.09, 0.05, 0.09), 0, DARK_WOOD)


static func _chest_lid(rb: RigBuilder) -> void:
	# 盖子（坐标以后边的铰链为原点）：拱起的木盖 + 铁箍 + 金色锁扣
	var c := Vector3(0, 0.0, 0.275)
	rb.block(c + Vector3(0, 0.07, 0), Vector3(0.9, 0.14, 0.55), 0, WOOD, RigBuilder.BODY, Basis.IDENTITY, Vector2(1.0, 0.8))
	rb.block(c + Vector3(0, 0.155, 0), Vector3(0.88, 0.05, 0.36), 0, WOOD.lightened(0.05), RigBuilder.BODY, Basis.IDENTITY, Vector2(1.0, 0.7))
	for x in [-0.28, 0.28]:
		rb.block(c + Vector3(x, 0.09, 0), Vector3(0.07, 0.17, 0.57), 0, IRON, RigBuilder.METAL, Basis.IDENTITY, Vector2(1.0, 0.75))
	rb.block(c + Vector3(0, 0.02, 0.29), Vector3(0.14, 0.14, 0.04), 0, Color(0.78, 0.6, 0.26), RigBuilder.METAL)
	rb.ellipsoid(c + Vector3(0, 0.0, 0.315), Vector3(0.025, 0.035, 0.01), 0, Color(0.1, 0.08, 0.05), RigBuilder.BODY, Basis.IDENTITY, 2, 5)


static func _shrine(rb: RigBuilder) -> void:
	# 三层八角台阶 + 刻纹石柱 + 顶上的石碗，四只石爪托着上面悬浮的晶石
	var tiers := [[0.0, 0.14, 0.66], [0.14, 0.26, 0.54], [0.26, 0.36, 0.42]]
	for t in tiers:
		rb.tube([Vector3(0, t[0], 0), Vector3(0, t[1], 0)], [Vector2(t[2], t[2]), Vector2(t[2] - 0.03, t[2] - 0.03)], [0, 0], STONE.darkened(0.08 * tiers.find(t)), RigBuilder.BODY, 8, true)
	rb.tube([Vector3(0, 0.36, 0), Vector3(0, 0.6, 0), Vector3(0, 0.95, 0), Vector3(0, 1.08, 0)], [Vector2(0.22, 0.22), Vector2(0.18, 0.18), Vector2(0.2, 0.2), Vector2(0.3, 0.3)], [0, 0, 0, 0], STONE, RigBuilder.BODY, 8, true)
	for y in [0.52, 0.8]:
		rb.tube([Vector3(0, y - 0.02, 0), Vector3(0, y + 0.02, 0)], [Vector2(0.205, 0.205), Vector2(0.205, 0.205)], [0, 0], STONE.darkened(0.3), RigBuilder.BODY, 8, false)
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		var d := Vector3(cos(a), 0, sin(a))
		rb.tube([d * 0.24 + Vector3(0, 1.05, 0), d * 0.28 + Vector3(0, 1.2, 0), d * 0.2 + Vector3(0, 1.3, 0)], [Vector2(0.045, 0.045), Vector2(0.035, 0.035), Vector2(0.0, 0.0)], [0, 0, 0], STONE.lightened(0.05), RigBuilder.BODY, 5, true)


static func _crystal(rb: RigBuilder) -> void:
	# 两头尖的晶石（坐标以晶石中心为原点）
	rb.spike(Vector3(0, 0, 0), Vector3(0, 0.26, 0), 0.14, 0, Color(0.45, 0.8, 1.0), RigBuilder.GLOW, 6)
	rb.spike(Vector3(0, 0, 0), Vector3(0, -0.2, 0), 0.14, 0, Color(0.45, 0.8, 1.0), RigBuilder.GLOW, 6)


# ---------------- 镇上的道具 ----------------

static func _well(rb: RigBuilder) -> void:
	# 石砌井圈：外圈、内壁、井口压顶石、黑色水面
	rb.tube([Vector3(0, 0, 0), Vector3(0, 0.82, 0)], [Vector2(0.9, 0.9), Vector2(0.86, 0.86)], [0, 0], STONE, RigBuilder.BODY, 14, false)
	rb.tube([Vector3(0, 0.82, 0), Vector3(0, 0.3, 0)], [Vector2(0.68, 0.68), Vector2(0.68, 0.68)], [0, 0], STONE.darkened(0.4), RigBuilder.BODY, 14, false)
	rb.tube([Vector3(0, 0.8, 0), Vector3(0, 0.92, 0)], [Vector2(0.92, 0.92), Vector2(0.9, 0.9)], [0, 0], STONE.lightened(0.08), RigBuilder.BODY, 14, false)
	rb.ellipsoid(Vector3(0, 0.9, 0), Vector3(0.9, 0.02, 0.9), 0, STONE.lightened(0.05), RigBuilder.BODY, Basis.IDENTITY, 2, 14)
	rb.ellipsoid(Vector3(0, 0.6, 0), Vector3(0.68, 0.01, 0.68), 0, Color(0.04, 0.07, 0.1), RigBuilder.BODY, Basis.IDENTITY, 2, 14)
	for k in 10:
		var a := TAU * k / 10.0 + 0.2
		rb.block(Vector3(cos(a) * 0.9, 0.2 + 0.35 * (k % 2), sin(a) * 0.9), Vector3(0.3, 0.16, 0.06), 0, STONE.darkened(0.1 + 0.1 * (k % 3)), RigBuilder.BODY, Basis(Vector3.UP, -a + PI / 2))
	# 木架、顶棚、辘轳、绳子和水桶
	for x in [-0.78, 0.78]:
		rb.block(Vector3(x, 1.5, 0), Vector3(0.12, 1.3, 0.12), 0, DARK_WOOD)
	rb.tube([Vector3(-0.9, 1.72, 0), Vector3(0.9, 1.72, 0)], [Vector2(0.06, 0.06), Vector2(0.06, 0.06)], [0, 0], WOOD, RigBuilder.BODY, 8, true)
	rb.block(Vector3(1.0, 1.62, 0), Vector3(0.05, 0.25, 0.05), 0, DARK_WOOD)
	for sx in [1.0, -1.0]:
		rb.block(Vector3(0, 2.3, sx * 0.34), Vector3(1.9, 0.05, 0.78), 0, DARK_WOOD.lightened(0.05), RigBuilder.BODY, Basis(Vector3.RIGHT, sx * 0.62))
	rb.block(Vector3(0, 2.52, 0), Vector3(1.95, 0.08, 0.08), 0, DARK_WOOD)
	rb.limb(Vector3(0.1, 1.7, 0), Vector3(0.1, 1.15, 0), 0.01, 0.01, 0, Color(0.6, 0.52, 0.38), -1, RigBuilder.BODY, 4)
	rb.tube([Vector3(0.1, 0.95, 0), Vector3(0.1, 1.15, 0)], [Vector2(0.11, 0.11), Vector2(0.13, 0.13)], [0, 0], WOOD, RigBuilder.BODY, 8, true)
	rb.tube([Vector3(0.1, 1.02, 0), Vector3(0.1, 1.05, 0)], [Vector2(0.125, 0.125), Vector2(0.125, 0.125)], [0, 0], IRON, RigBuilder.METAL, 8, false)


static func _anvil(rb: RigBuilder) -> void:
	# 树桩 + 铁砧（底座、细腰、砧面、一头尖角、另一头方尾）
	rb.tube([Vector3(0, 0, 0), Vector3(0, 0.5, 0)], [Vector2(0.3, 0.3), Vector2(0.26, 0.26)], [0, 0], DARK_WOOD, RigBuilder.BODY, 10, false)
	rb.ellipsoid(Vector3(0, 0.5, 0), Vector3(0.26, 0.015, 0.26), 0, WOOD.lightened(0.15), RigBuilder.BODY, Basis.IDENTITY, 2, 10)
	var iron := Color(0.26, 0.26, 0.29)
	rb.block(Vector3(0, 0.58, 0), Vector3(0.44, 0.16, 0.3), 0, iron, RigBuilder.METAL, Basis.IDENTITY, Vector2(0.7, 0.7))
	rb.block(Vector3(0, 0.72, 0), Vector3(0.24, 0.14, 0.18), 0, iron, RigBuilder.METAL)
	rb.block(Vector3(0, 0.84, 0), Vector3(0.62, 0.12, 0.26), 0, iron.lightened(0.1), RigBuilder.METAL, Basis.IDENTITY, Vector2(1.05, 1.0))
	rb.spike(Vector3(0.3, 0.84, 0), Vector3(0.62, 0.86, 0), 0.07, 0, iron.lightened(0.1), RigBuilder.METAL, 6)
	rb.block(Vector3(-0.36, 0.84, 0), Vector3(0.12, 0.1, 0.2), 0, iron, RigBuilder.METAL)
	# 旁边斜靠着的铁锤
	rb.limb(Vector3(0.28, 0.02, 0.26), Vector3(0.22, 0.5, 0.2), 0.02, 0.02, 0, WOOD, -1, RigBuilder.BODY, 5)
	rb.block(Vector3(0.28, 0.06, 0.26), Vector3(0.14, 0.08, 0.08), 0, iron, RigBuilder.METAL)


static func _waystone(rb: RigBuilder) -> void:
	# 方尖石碑：底座、上窄下宽的碑身、尖顶；正反两面刻着发蓝光的符文
	rb.block(Vector3(0, 0.12, 0), Vector3(1.0, 0.24, 0.72), 0, STONE.darkened(0.15))
	rb.block(Vector3(0, 0.3, 0), Vector3(0.84, 0.14, 0.58), 0, STONE.darkened(0.08))
	rb.block(Vector3(0, 1.2, 0), Vector3(0.66, 1.66, 0.44), 0, STONE, RigBuilder.BODY, Basis.IDENTITY, Vector2(0.72, 0.72))
	rb.spike(Vector3(0, 2.02, 0), Vector3(0, 2.4, 0), 0.26, 0, STONE.lightened(0.05), RigBuilder.BODY, 4)
	var rune := Color(0.35, 0.7, 1.0)
	for sz in [1.0, -1.0]:
		for k in 5:
			var y := 0.62 + k * 0.26
			var w := 0.3 - k * 0.03
			var z: float = sz * (0.222 - (y - 0.37) * 0.034)
			rb.block(Vector3(0, y, z), Vector3(w * 0.25, 0.14, 0.02), 0, rune, RigBuilder.GLOW)
			rb.block(Vector3(-w * 0.3, y + 0.05, z), Vector3(w * 0.25, 0.03, 0.02), 0, rune, RigBuilder.GLOW)
			rb.block(Vector3(w * 0.3, y - 0.05, z), Vector3(w * 0.25, 0.03, 0.02), 0, rune, RigBuilder.GLOW)


static func _campfire(rb: RigBuilder) -> void:
	# 一圈石头、交叉搭起的木柴、中间发光的余烬（火苗和火光由 Torch 负责）
	for k in 9:
		var a := TAU * k / 9.0
		var r := 0.62 + 0.04 * sin(k * 2.3)
		rb.ellipsoid(Vector3(cos(a) * r, 0.08, sin(a) * r), Vector3(0.16, 0.1 + 0.03 * (k % 2), 0.13), 0, STONE.darkened(0.1 * (k % 3)), RigBuilder.BODY, Basis(Vector3.UP, a), 3, 6)
	for k in 5:
		var a := TAU * k / 5.0
		var d := Vector3(cos(a), 0, sin(a))
		rb.limb(d * 0.5 + Vector3(0, 0.05, 0), Vector3(0, 0.55, 0) - d * 0.05, 0.06, 0.045, 0, DARK_WOOD.darkened(0.2 * (k % 2)), -1, RigBuilder.BODY, 6)
	rb.ellipsoid(Vector3(0, 0.07, 0), Vector3(0.36, 0.06, 0.36), 0, Color(1.0, 0.45, 0.12), RigBuilder.GLOW, Basis.IDENTITY, 2, 10)


# ---------------- 房屋外立面 ----------------

## rect：房屋占的格子（整块是墙）；door_dir：门开在哪一面（格子方向，例如 (0, 1) 是南面）。
## 返回 MeshInstance3D（世界坐标）：木构架（墙角立柱、每约 1.6 米一根立柱、地梁 / 腰梁 / 檐梁、斜撑）、门、亮着灯的窗与打开的百叶、
## 屋脊梁、山墙封檐板、石砌烟囱。
static func house(rect: Rect2i, door_dir: Vector2i, seed_v: int) -> MeshInstance3D:
	var rb := RigBuilder.new()
	var T := DungeonBuilder.TILE
	var H := DungeonBuilder.WALL_H
	var x0 := rect.position.x * T
	var x1 := rect.end.x * T
	var z0 := rect.position.y * T
	var z1 := rect.end.y * T
	var beam := DARK_WOOD
	var faces := [[Vector2i(0, 1), Vector3(x0, 0, z1), Vector3(1, 0, 0), x1 - x0], [Vector2i(0, -1), Vector3(x1, 0, z0), Vector3(-1, 0, 0), x1 - x0],
		[Vector2i(1, 0), Vector3(x1, 0, z1), Vector3(0, 0, -1), z1 - z0], [Vector2i(-1, 0), Vector3(x0, 0, z0), Vector3(0, 0, 1), z1 - z0]]
	for f in faces:
		var dir: Vector2i = f[0]
		var nrm := Vector3(dir.x, 0, dir.y)
		var start: Vector3 = f[1] + nrm * 0.07
		var along: Vector3 = f[2]
		var L: float = f[3]
		var basis := Basis(Vector3.UP, atan2(nrm.x, nrm.z))
		var has_door := dir == door_dir
		var door_w := 1.2
		var mid := L / 2.0
		# 立柱：两端 + 中间每约 1.6 米一根；门两侧各一根（门框）
		var n := maxi(2, roundi(L / 1.6))
		var posts: Array = []
		for i in n + 1:
			var s := lerpf(0.1, L - 0.1, float(i) / n)
			if has_door and absf(s - mid) < door_w / 2.0 + 0.15:
				continue
			posts.append(s)
		if has_door:
			posts.append(mid - door_w / 2.0 - 0.08)
			posts.append(mid + door_w / 2.0 + 0.08)
		posts.sort()
		for s in posts:
			rb.block(start + along * s + Vector3(0, H / 2.0 + 0.2, 0), Vector3(0.16, H - 0.4, 0.1), 0, beam, RigBuilder.BODY, basis)
		for y in [0.5, H - 0.22]:
			rb.block(start + along * mid + Vector3(0, y, 0), Vector3(L - 0.1, 0.14, 0.1), 0, beam, RigBuilder.BODY, basis)
		# 腰梁（门的位置断开）
		if has_door:
			var l1 := mid - door_w / 2.0 - 0.16
			rb.block(start + along * (l1 / 2.0 + 0.05) + Vector3(0, 1.9, 0), Vector3(l1, 0.12, 0.1), 0, beam, RigBuilder.BODY, basis)
			rb.block(start + along * (L - l1 / 2.0 - 0.05) + Vector3(0, 1.9, 0), Vector3(l1, 0.12, 0.1), 0, beam, RigBuilder.BODY, basis)
		else:
			rb.block(start + along * mid + Vector3(0, 1.9, 0), Vector3(L - 0.1, 0.12, 0.1), 0, beam, RigBuilder.BODY, basis)
		# 斜撑：下半截每隔一格加一根
		for i in posts.size() - 1:
			var a: float = posts[i]
			var b: float = posts[i + 1]
			if (i + seed_v) % 2 == 1 or b - a < 0.6 or (has_door and a < mid and b > mid):
				continue
			var ctr := start + along * ((a + b) / 2.0) + Vector3(0, 1.2, 0)
			var dx := b - a - 0.16
			var ang := atan2(1.3, dx)
			rb.block(ctr, Vector3(sqrt(dx * dx + 1.3 * 1.3), 0.11, 0.08), 0, beam.lightened(0.04), RigBuilder.BODY, basis * Basis(Vector3.FORWARD, ang if i % 2 == 0 else -ang))
		# 窗：上半截每个够宽的格间一扇（门那一面只在门两边各一扇）
		var win_spots: Array = []
		for i in posts.size() - 1:
			var a2: float = posts[i]
			var b2: float = posts[i + 1]
			if b2 - a2 >= 1.0 and not (has_door and a2 < mid and b2 > mid) and (win_spots.size() < 2):
				win_spots.append((a2 + b2) / 2.0)
		for s in win_spots:
			var wc: Vector3 = start + along * s + Vector3(0, 2.45, 0)
			rb.block(wc, Vector3(0.64, 0.56, 0.02), 0, Color(1.0, 0.66, 0.3), RigBuilder.GLOW, basis)                 # 亮着灯的窗
			rb.block(wc + nrm * 0.02, Vector3(0.05, 0.56, 0.03), 0, beam, RigBuilder.BODY, basis)                       # 窗棂
			rb.block(wc + nrm * 0.02, Vector3(0.64, 0.05, 0.03), 0, beam, RigBuilder.BODY, basis)
			rb.block(wc + Vector3(0, -0.33, 0) + nrm * 0.03, Vector3(0.78, 0.07, 0.1), 0, beam, RigBuilder.BODY, basis)  # 窗台
			for sd in [-1.0, 1.0]:
				rb.block(wc + along * (sd * 0.5) + nrm * 0.12, Vector3(0.34, 0.6, 0.03), 0, WOOD.darkened(0.1), RigBuilder.BODY, basis * Basis(Vector3.UP, sd * 1.1))   # 打开的百叶
		# 门：门框、三块竖木板、铁合页、门环、门前的台阶石
		if has_door:
			var dc := start + along * mid
			rb.block(dc + Vector3(0, 1.08, 0), Vector3(door_w, 2.08, 0.04), 0, WOOD.darkened(0.05), RigBuilder.BODY, basis)
			for k in 3:
				rb.block(dc + along * ((k - 1) * 0.4) + Vector3(0, 1.08, 0) + nrm * 0.025, Vector3(0.012, 2.04, 0.02), 0, beam, RigBuilder.BODY, basis)
			rb.block(dc + Vector3(0, 2.2, 0) + nrm * 0.02, Vector3(door_w + 0.3, 0.16, 0.12), 0, beam, RigBuilder.BODY, basis)
			for y in [0.45, 1.7]:
				rb.block(dc + along * (-0.25) + Vector3(0, y, 0) + nrm * 0.04, Vector3(0.6, 0.07, 0.02), 0, IRON, RigBuilder.METAL, basis)
			rb.tube([dc + along * 0.35 + Vector3(0, 1.05, 0) + nrm * 0.05, dc + along * 0.35 + Vector3(0, 0.97, 0) + nrm * 0.06], [Vector2(0.05, 0.05), Vector2(0.05, 0.05)], [0, 0], IRON, RigBuilder.METAL, 8, false)
			rb.block(dc + Vector3(0, 0.05, 0) + nrm * 0.35, Vector3(door_w + 0.3, 0.1, 0.6), 0, STONE.darkened(0.1), RigBuilder.BODY, basis)
	# 屋顶：屋脊梁、两头山墙的封檐板、烟囱（房顶是 TownBuilder 的棱柱，屋脊沿 z 方向、比墙每边宽 0.4 米、高 2.2 米）
	var cx := (x0 + x1) / 2.0
	var cz := (z0 + z1) / 2.0
	var half := (x1 - x0) / 2.0 + 0.4
	var rise := 2.2
	rb.block(Vector3(cx, H + rise + 0.03, cz), Vector3(0.18, 0.14, z1 - z0 + 1.0), 0, beam)
	var slope := sqrt(half * half + rise * rise)
	var ang2 := atan2(rise, half)
	for zz in [z0 - 0.42, z1 + 0.42]:
		for sx in [1.0, -1.0]:
			rb.block(Vector3(cx + sx * half / 2.0, H + rise / 2.0, zz), Vector3(slope + 0.1, 0.12, 0.06), 0, beam, RigBuilder.BODY, Basis(Vector3.FORWARD, sx * ang2))   # 右边一块向右下斜、左边一块向左下斜
	var chx := cx + half * 0.45
	var chz := z0 + (z1 - z0) * 0.3
	var roof_y := H + rise * (1.0 - 0.45)
	rb.block(Vector3(chx, roof_y + 0.6, chz), Vector3(0.6, 1.8, 0.6), 0, STONE.darkened(0.1))
	rb.block(Vector3(chx, roof_y + 1.52, chz), Vector3(0.72, 0.12, 0.72), 0, STONE.darkened(0.25))
	var m := rb.commit_static()
	m.glow = Color(1.0, 0.66, 0.3)
	var mi := _mesh_instance(m, "HouseDetail")
	mi.set_meta("tris", m.tris)
	return mi


# ---------------- 2.6 之六：树林与地面装饰 ----------------

static func _tree_pine(rb: RigBuilder) -> void:
	# 暗色针叶树：细树干 + 三层上小下大的锥形枝叶（颜色越往上越浅，像落了一层灰）
	rb.tube([Vector3(0, 0, 0), Vector3(0, 1.4, 0)], [Vector2(0.2, 0.2), Vector2(0.13, 0.13)], [0, 0], Color(0.24, 0.17, 0.11), RigBuilder.BODY, 5, false)
	var tiers := [[0.8, 1.4, 1.7], [1.8, 1.1, 1.5], [2.8, 0.75, 1.5]]
	for i in tiers.size():
		var t: Array = tiers[i]
		var col := Color(0.11, 0.18, 0.14).lerp(Color(0.24, 0.28, 0.24), i * 0.35)
		rb.spike(Vector3(0, t[0], 0), Vector3(0.03 * i, t[0] + t[2], 0), t[1], 0, col, RigBuilder.BODY, 7)


static func _tree_dead(rb: RigBuilder) -> void:
	# 被烧焦的枯树：弯曲的树干，几根向上斜伸的枯枝（每根再分一个小杈）
	var bark := Color(0.2, 0.16, 0.13)
	rb.tube([Vector3(0, 0, 0), Vector3(0.05, 1.2, 0.02), Vector3(-0.08, 2.4, 0.06), Vector3(0.02, 3.4, 0.0)], [Vector2(0.24, 0.24), Vector2(0.17, 0.17), Vector2(0.12, 0.12), Vector2(0.0, 0.0)], [0, 0, 0, 0], bark, RigBuilder.BODY, 5, true)
	var branches := [[1.5, 0.3, 1.1, 0.6], [2.1, 2.5, 1.0, 0.8], [2.6, 4.4, 0.8, 0.6], [1.1, 5.2, 0.9, 0.3]]
	for b in branches:
		var a: float = b[1]
		var d := Vector3(cos(a), 0, sin(a))
		var p0 := Vector3(0, b[0], 0)
		var p1: Vector3 = p0 + d * b[2] + Vector3(0, b[3], 0)
		rb.spike(p0, p1, 0.07, 0, bark.lightened(0.05), RigBuilder.BODY, 4)
		rb.spike(p0.lerp(p1, 0.5), p1 + d.rotated(Vector3.UP, 0.7) * 0.4 + Vector3(0, 0.5, 0), 0.035, 0, bark, RigBuilder.BODY, 3)


static func _tree_broad(rb: RigBuilder) -> void:
	# 阔叶树：短粗树干 + 四团枝叶（暗橄榄绿里夹一团锈红，像被余烬烤过的秋叶）
	rb.tube([Vector3(0, 0, 0), Vector3(0, 1.8, 0)], [Vector2(0.26, 0.26), Vector2(0.17, 0.17)], [0, 0], Color(0.26, 0.18, 0.12), RigBuilder.BODY, 6, false)
	var clumps := [[Vector3(0, 2.6, 0), 1.2, Color(0.18, 0.23, 0.13)], [Vector3(0.7, 2.2, 0.3), 0.85, Color(0.2, 0.25, 0.13)],
		[Vector3(-0.6, 2.3, -0.4), 0.9, Color(0.33, 0.2, 0.1)], [Vector3(0.1, 3.3, -0.2), 0.8, Color(0.22, 0.27, 0.15)]]
	for c in clumps:
		var r: float = c[1]
		rb.ellipsoid(c[0], Vector3(r, r * 0.8, r), 0, c[2], RigBuilder.BODY, Basis(Vector3.UP, r * 3.0), 4, 7)


static func _bone(rb: RigBuilder) -> void:
	# 腿骨：中间细、两头各鼓出两个关节头
	var col := Color(0.78, 0.74, 0.64)
	rb.tube([Vector3(-0.24, 0, 0), Vector3(0.24, 0, 0)], [Vector2(0.03, 0.03), Vector2(0.03, 0.03)], [0, 0], col, RigBuilder.BODY, 4, false)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			rb.ellipsoid(Vector3(sx * 0.26, 0, sz * 0.025), Vector3(0.04, 0.035, 0.045), 0, col.lightened(0.05), RigBuilder.BODY, Basis.IDENTITY, 2, 4)


static func _skull(rb: RigBuilder) -> void:
	# 头骨：颅顶、脸、黑眼窝（侧躺在地上时也认得出来）
	var col := Color(0.82, 0.78, 0.68)
	rb.ellipsoid(Vector3(0, 0.1, 0), Vector3(0.1, 0.095, 0.12), 0, col, RigBuilder.BODY, Basis.IDENTITY, 3, 6)
	rb.block(Vector3(0, 0.05, 0.08), Vector3(0.1, 0.06, 0.08), 0, col.darkened(0.1))
	for sx in [1.0, -1.0]:
		rb.ellipsoid(Vector3(0.04 * sx, 0.1, 0.1), Vector3(0.025, 0.022, 0.015), 0, Color(0.08, 0.06, 0.05), RigBuilder.BODY, Basis.IDENTITY, 2, 4)


static func _rock(rb: RigBuilder) -> void:
	# 碎石：两块压扁的石头叠在一起，棱角分明（面数低：一层几百块）
	var col := Color(0.46, 0.43, 0.4)
	rb.ellipsoid(Vector3(0, 0.05, 0), Vector3(0.15, 0.08, 0.12), 0, col, RigBuilder.BODY, Basis(Vector3.UP, 0.4), 3, 5)
	rb.ellipsoid(Vector3(0.08, 0.1, 0.03), Vector3(0.08, 0.06, 0.07), 0, col.lightened(0.08), RigBuilder.BODY, Basis(Vector3.UP, 1.3), 2, 4)


static func _lava_crack(rb: RigBuilder) -> void:
	# 熔岩裂缝：贴在地面上的折线（主缝 4 段 + 岔缝 2 段）；每段是暗红的宽边上叠一条亮橙的缝芯。只有发光面（不受光照影响）
	var main := [Vector3(-0.6, 0, -0.05), Vector3(-0.3, 0, 0.08), Vector3(-0.02, 0, -0.04), Vector3(0.28, 0, 0.06), Vector3(0.6, 0, -0.02)]
	var fork := [Vector3(-0.02, 0, -0.04), Vector3(0.1, 0, -0.2), Vector3(0.3, 0, -0.28)]
	for line in [[main, 0.13], [fork, 0.08]]:
		var pts: Array = line[0]
		for i in pts.size() - 1:
			var w: float = float(line[1]) * (1.0 - 0.15 * i)
			_flat_seg(rb, pts[i], pts[i + 1], w, Color(0.55, 0.12, 0.03), 0.0)
			_flat_seg(rb, pts[i], pts[i + 1], w * 0.4, Color(1.0, 0.62, 0.2), 0.008)


## 贴地的一段扁条（发光面）：a → b，宽 w，离地 y
static func _flat_seg(rb: RigBuilder, a: Vector3, b: Vector3, w: float, col: Color, y: float) -> void:
	var d := (b - a).normalized()
	var side := Vector3(-d.z, 0, d.x) * (w / 2.0)
	var ext := d * (w * 0.3)      # 两头各伸出一点，相邻两段接得上
	var up := Vector3(0, y, 0)
	var ids: Array = []
	for p in [a - ext - side, a - ext + side, b + ext + side, b + ext - side]:
		ids.append(rb._vert(RigBuilder.GLOW, (p as Vector3) + up, Vector3.UP, col, 0))
	rb._tri(RigBuilder.GLOW, ids[0], ids[1], ids[2])
	rb._tri(RigBuilder.GLOW, ids[0], ids[2], ids[3])


static func _dummy(rb: RigBuilder) -> void:
	# 训练木桩：圆木底座、立柱、麻袋塞草的身子（捆着绳子）、横杆手臂（两头露出稻草）、缝着脸的麻袋头
	var wood := Color(0.42, 0.29, 0.17)
	var burlap := Color(0.62, 0.5, 0.33)
	var straw := Color(0.8, 0.68, 0.36)
	var rope := Color(0.5, 0.42, 0.28)
	rb.tube([Vector3(0, 0, 0), Vector3(0, 0.14, 0)], [Vector2(0.5, 0.5), Vector2(0.47, 0.47)], [0, 0], Color(0.34, 0.24, 0.15), RigBuilder.BODY, 10, false)
	rb.ellipsoid(Vector3(0, 0.14, 0), Vector3(0.47, 0.012, 0.47), 0, Color(0.56, 0.42, 0.26), RigBuilder.BODY, Basis.IDENTITY, 2, 10)      # 锯开的圆木截面
	rb.tube([Vector3(0, 0.1, 0), Vector3(0, 1.95, 0)], [Vector2(0.08, 0.08), Vector2(0.07, 0.07)], [0, 0], wood, RigBuilder.BODY, 6, false)
	rb.tube([Vector3(0, 0.7, 0), Vector3(0, 0.95, 0.01), Vector3(0, 1.3, 0.02), Vector3(0, 1.55, 0.0)], [Vector2(0.26, 0.2), Vector2(0.32, 0.26), Vector2(0.33, 0.26), Vector2(0.2, 0.16)], [0, 0, 0, 0], burlap, RigBuilder.BODY, 10, true, Vector3.BACK)
	for y in [0.88, 1.38]:
		rb.tube([Vector3(0, y - 0.02, 0), Vector3(0, y + 0.02, 0)], [Vector2(0.33, 0.265), Vector2(0.33, 0.265)], [0, 0], rope, RigBuilder.BODY, 10, false, Vector3.BACK)
	for k in 5:
		rb.spike(Vector3(-0.05 + k * 0.025, 0.72, 0.1), Vector3(-0.08 + k * 0.04, 0.55, 0.14), 0.02, 0, straw, RigBuilder.BODY, 3)
	rb.tube([Vector3(-0.72, 1.32, 0), Vector3(0.72, 1.32, 0)], [Vector2(0.055, 0.055), Vector2(0.055, 0.055)], [0, 0], wood, RigBuilder.BODY, 6, true)
	for sx in [1.0, -1.0]:
		for k in 4:
			var a := TAU * k / 4.0
			rb.spike(Vector3(sx * 0.7, 1.32, 0), Vector3(sx * 0.9, 1.32 + sin(a) * 0.08, cos(a) * 0.08), 0.025, 0, straw, RigBuilder.BODY, 3)
	rb.ellipsoid(Vector3(0, 1.8, 0.01), Vector3(0.2, 0.22, 0.19), 0, burlap.lightened(0.05), RigBuilder.BODY, Basis.IDENTITY, 5, 9)
	rb.tube([Vector3(0, 1.6, 0), Vector3(0, 1.64, 0)], [Vector2(0.12, 0.12), Vector2(0.12, 0.12)], [0, 0], rope, RigBuilder.BODY, 8, false)
	for sx in [1.0, -1.0]:
		rb.block(Vector3(0.07 * sx, 1.84, 0.185), Vector3(0.07, 0.014, 0.01), 0, Color(0.15, 0.1, 0.07), RigBuilder.BODY, Basis(Vector3.FORWARD, 0.8))
		rb.block(Vector3(0.07 * sx, 1.84, 0.185), Vector3(0.07, 0.014, 0.01), 0, Color(0.15, 0.1, 0.07), RigBuilder.BODY, Basis(Vector3.FORWARD, -0.8))
	rb.block(Vector3(0, 1.73, 0.19), Vector3(0.12, 0.012, 0.01), 0, Color(0.15, 0.1, 0.07))
	for k in 4:
		rb.block(Vector3(-0.045 + k * 0.03, 1.73, 0.192), Vector3(0.006, 0.03, 0.01), 0, Color(0.15, 0.1, 0.07))
