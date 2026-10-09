class_name Edges
extends RefCounted
## 区域边缘（路线图 3.10；所有者 2026-10-09 定「A + B」里的 A：区域之间仍用路口连，但边界要做实）。
## 走得到的范围外面不能是空的：2026-10-09 所有者截图里渡口北头「回桦林的路」是空雪地上一块黑门板，
## 逐个区域截图查下来，霜渡镇南门、桦林两头和两侧、渡口三面、墓园墙外都一样：桦林和渡口的雪地只比走得到的地方大三四米，再往外就是天；
## 霜渡镇、墓园的地面本来铺得够远（15–45 米），缺的是墙外的树和出口外的路（墓园 15 米外的地面边夜里也看得见）。
## 这里给户外区域统一收边，全部代码搭、不加外部素材：
##   1. 地面一直铺到雾里（90 米，比白天的雾 85 米还远；只有画面、没有碰撞：人走不过去，看不见尽头）；
##   2. 边界外两圈白桦：近圈 1–14 米密，远圈 18–46 米疏（雾按离镜头的远近算：站在边界上，远圈头几排夜里也还透得出来）；
##      远圈的树只有树干和两根枝，省三角面；树不加碰撞（走不到那里，区域原来的看不见的围墙照旧）；
##   3. 出口留一条路伸进林子和雾里（不种树，路一直铺到地面尽头），出口两边各一段木栅栏，门柱上挂一盏夜里亮的灯笼（灯光是假的：发光的玻璃 + 光晕，
##      不加实时光源，白天跟着时段灭，Daypart.mark_night_light）。门柱、横梁、地名牌：已有的出口不动，新做的出口给 frame（_frame）。
## 种树用网格抖动（每格一棵、在格子里随机偏一点），不用逐棵比距离。
## 树用多实例（MultiMesh）画：近圈两种、远圈一种树的模型各做一份，按位置、转向、高矮摆几百个副本——
## 第一版逐棵拼进合并网格，光收边就要 130–280 毫秒（换区域时网页上会卡半秒多），改多实例以后几毫秒；每块树两次绘制（树干、枝条）。
## 树按 48 米的块分成几个多实例节点（远圈 96 米）：一整圈做成一个节点的话，引擎没法按视野和影子范围裁掉，身后的树、
## 25 米影子范围外的树都照画（中画质近圈的树连影子那一遍约八万个图元）；分块以后整块裁掉。块不能太小：每块每种树两次绘制，
## 24 米的块图元少一到三成，但霜渡镇绘制调用到了 390（预算 400）；48 米的块比没收边时多二三十次（2026-10-09 网页实测，TEST_REPORT）。
## 栅栏和新做的门柱有碰撞（审查发现：渡口北头的栅栏在看不见的墙里面 0.6 米，没有碰撞人能穿过去、站到栅栏外面）；树、地面、路没有。
## 远圈的树不投影子；雾在 24 米以内就吞没时（现在的四个时段都没有这么浓，留给以后的大雪）远圈不画（refresh，按时段和画质）。
## 低画质（触屏默认）近圈只画六成、远圈不画：副本的顺序打乱过，只画前一部分也是均匀稀疏的。

const GROUND_MARGIN := 90.0      # 地面往外铺多远（雾在夜里 36 米、白天 85 米吞没；只有四块，铺远不费）
const NEAR := [1.0, 14.0, 2.9]   # 近圈：离边界几米到几米、格子边长
const FAR := [18.0, 46.0, 7.0]   # 远圈
const CORRIDOR := 1.6            # 出口那条路两边再空出多宽不种树
const ROAD_LEN := GROUND_MARGIN  # 出口外的路伸多远：一直到地面尽头（30 米的话清晨、白天看得见路断在雪地里，审查截图）
const FENCE := 6.0               # 出口两边的栅栏各多长
const NEAR_KINDS := 2            # 近圈有几种树（每种一份模型，相邻的块轮流用）
const CHUNK := 48.0              # 树按多大的块分（米；远圈两倍）：一块一个多实例节点，看不见的块、影子范围外的块整块跳过
const FAR_SEEN := 24.0           # 雾在这么远以外才吞没时才画远圈（远圈从边界外 18 米起；四个时段都画）
const LOW_SHARE := 0.6           # 低画质近圈画几成


## 给一个户外区域收边。area：走得到的范围（XZ 平面，Rect2(x, z, 宽, 高)）。
## exits：出口 [{"at": 出口的门所在的点 Vector3, "out": 往外的方向 Vector3（水平单位向量）, "half": 路宽的一半,
##         "fence": 两边要不要栅栏, "lantern": 门柱上要不要灯笼, "frame": 地名（不空 = 新做门柱、横梁、小檐和地名牌）}]
## skip：不种树、不铺地的矩形（Rect2，XZ），例如渡口的河面
## 返回地面、路、栅栏、门框合并成的网格（已挂在 parent 下，元数据 exits 记着出口）；树是另外几个多实例节点（组 edge_trees），
## 栅栏和门柱的碰撞是另外一个 StaticBody3D（EdgeSolids）
static func dress(parent: Node3D, area: Rect2, exits: Array, skip: Array, seed_value: int) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var kit := MeshKit.new()
	_ground(kit, area, skip)
	for e in exits:
		_road(kit, e)
	var trees := 0
	var meshes := []
	for k in NEAR_KINDS:
		meshes.append(tree_mesh(k))
	var far_mesh := tree_mesh(-1)
	for band in [NEAR, FAR]:
		var far: bool = band == FAR
		var spots := _ring(area, exits, skip, rng, band)
		var size := CHUNK * (2.0 if far else 1.0)
		var chunks := {}                                       # 按块分：块的格子坐标 → 这块里的树
		for p: Vector3 in spots:
			var c := Vector2i(floori(p.x / size), floori(p.z / size))
			if not chunks.has(c):
				chunks[c] = []
			chunks[c].append(p)
		var keys := chunks.keys()
		keys.sort()                                            # 字典顺序跟插入有关，排一下，同一个种子每次一样
		for c: Vector2i in keys:
			var k := posmod(c.x + c.y, NEAR_KINDS)               # 近圈相邻的块轮流用两种树
			var mesh: Mesh = far_mesh if far else meshes[k]
			_instances(parent, mesh, chunks[c], rng, far, ("EdgeTreesFar_%d_%d" if far else "EdgeTrees_%d_%d") % [c.x, c.y])
		trees += spots.size()
	var solids := StaticBody3D.new()
	solids.name = "EdgeSolids"
	solids.collision_layer = 1
	solids.collision_mask = 0
	for e in exits:
		if str(e.get("frame", "")) != "":
			_frame(parent, kit, solids, e)
		if bool(e.get("fence", false)):
			_fence(kit, solids, e)
		if bool(e.get("lantern", false)):
			_lantern(parent, kit, e)
	var mi := kit.build({"snow": Look.mat("snow"), "birch": Look.birch(), "bark": Look.mat("bark"), "timber": Look.mat("timber"), "roof": Look.mat("roof")})
	mi.name = "Edges"
	mi.set_meta("trees", trees)
	mi.set_meta("exits", exits)
	mi.set_meta("area", area)                     # 走得到的范围（地图 3.11 的测试拿它和区域的地图规格对照）
	parent.add_child(mi)
	if solids.get_child_count() > 0:
		parent.add_child(solids)
	else:
		solids.free()
	return mi


## 栅栏、门柱的碰撞：一个盒子（中心、尺寸、朝向）
static func _solid(solids: StaticBody3D, center: Vector3, size: Vector3, basis: Basis) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(basis, center)
	solids.add_child(cs)


## 新做的出口门框（渡口北头这种原来只有一块门板的）：两根门柱、横梁、小檐、地名牌。门板本身（Door）由区域自己放，宽 1.9 米
static func _frame(parent: Node3D, kit: MeshKit, solids: StaticBody3D, e: Dictionary) -> void:
	var at: Vector3 = e.at
	var out: Vector3 = e.out
	var label := str(e.frame)
	var width := 1.9
	var side := Vector3(-out.z, 0, out.x)                     # 沿着边界的方向
	var basis := Basis(side, Vector3.UP, out)
	var half := width * 0.5 + 0.12
	for s in [-1.0, 1.0]:
		kit.box("timber", at + side * s * half + Vector3(0, 1.25, 0), Vector3(0.22, 2.5, 0.22), basis, 0.85, 0.5)
		_solid(solids, at + side * s * half + Vector3(0, 1.25, 0), Vector3(0.22, 2.5, 0.22), basis)
	kit.box("timber", at + Vector3(0, 2.45, 0), Vector3(width + 0.7, 0.18, 0.22), basis)
	kit.box("roof", at + Vector3(0, 2.66, 0), Vector3(width + 1.0, 0.08, 0.7), basis)
	var l := Blocks.label(parent, label, at + Vector3(0, 2.95, 0) - out * 0.05)
	l.rotation.y = atan2(out.x, out.z) + PI                  # 字朝里（从区域里面读）


static func _ground(kit: MeshKit, area: Rect2, skip: Array) -> void:
	var g := area.grow(GROUND_MARGIN)
	# 四条：北、南、西、东（中间是区域自己的地面，不重铺）；比区域地面低 2 厘米，接缝看不出来
	var strips := [
		Rect2(g.position.x, g.position.y, g.size.x, area.position.y - g.position.y),
		Rect2(g.position.x, area.end.y, g.size.x, g.end.y - area.end.y),
		Rect2(g.position.x, area.position.y, area.position.x - g.position.x, area.size.y),
		Rect2(area.end.x, area.position.y, g.end.x - area.end.x, area.size.y),
	]
	for r in strips:
		for part in _minus(r, skip):
			var c: Vector2 = part.get_center()
			kit.box("snow", Vector3(c.x, -0.03, c.y), Vector3(part.size.x, 0.02, part.size.y), Basis.IDENTITY, 1.0, 1.0)


## 矩形减去不铺的地方（只处理整条切掉的情况：跳过区域和它重叠的部分按 skip 的边裁掉）
static func _minus(r: Rect2, skip: Array) -> Array:
	var parts := [r]
	for s: Rect2 in skip:
		var next := []
		for p: Rect2 in parts:
			if not p.intersects(s):
				next.append(p)
				continue
			# 只裁南北方向（渡口的河在南边整条横过去）
			if s.position.y > p.position.y:
				next.append(Rect2(p.position.x, p.position.y, p.size.x, s.position.y - p.position.y))
			if s.end.y < p.end.y:
				next.append(Rect2(p.position.x, s.end.y, p.size.x, p.end.y - s.end.y))
		parts = next
	return parts.filter(func(p: Rect2): return p.size.x > 0.1 and p.size.y > 0.1)


static func _road(kit: MeshKit, e: Dictionary) -> void:
	var at: Vector3 = e.at
	var out: Vector3 = e.out
	var half := float(e.get("half", 1.6))
	var c: Vector3 = at + out * (ROAD_LEN * 0.5)
	var basis := Basis(Vector3(-out.z, 0, out.x), Vector3.UP, out)
	kit.box("snow", Vector3(c.x, -0.005, c.z), Vector3(half * 2.0, 0.02, ROAD_LEN), basis, 0.62, 0.62)


## 一种树的模型（k = 0、1：近圈的两种；-1：远圈的简化树）。每次现做（三棵树约 1 毫秒）；不放静态缓存——
## 静态变量里存网格，退出时引擎报资源没释放（dialogue_runner.gd 说过同样的坑）
static func tree_mesh(k: int) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + k
	var kit := MeshKit.new()
	if k < 0:
		_far_tree(kit, Vector3.ZERO, rng)
	else:
		Birch.add_tree(kit, null, Vector3.ZERO, rng)
	var mi := kit.build({"birch": Look.birch(), "bark": Look.mat("bark")})
	var mesh := mi.mesh
	mi.free()                                              # 只要网格，临时的节点放掉
	return mesh


## 一种树的多实例：每个位置随机转个方向、高矮差一点
static func _instances(parent: Node3D, mesh: Mesh, spots: Array, rng: RandomNumberGenerator, far: bool, node_name: String) -> void:
	if spots.is_empty():
		return
	spots = spots.duplicate()
	for i in range(spots.size() - 1, 0, -1):                 # 打乱顺序（固定种子）：只画前一部分时也是均匀的
		var j := rng.randi_range(0, i)
		var t: Vector3 = spots[i]
		spots[i] = spots[j]
		spots[j] = t
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for i in spots.size():
		var sc := rng.randf_range(0.85, 1.2)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.15), sc))
		mm.set_instance_transform(i, Transform3D(b, spots[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.add_to_group("edge_trees")
	mmi.set_meta("far", far)
	mmi.set_meta("spots", PackedVector3Array(spots))         # 树的位置另记一份：无界面跑测试时引擎读不回多实例的变换（全是原点）
	if far:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


## 按画质和雾的远近决定画多少树：low = 低画质；fog_end = 当前时段的雾在几米外吞没（室内、测试场给 0）
static func refresh(tree: SceneTree, low: bool, fog_end: float) -> void:
	for n in tree.get_nodes_in_group("edge_trees"):
		var mmi := n as MultiMeshInstance3D
		var far := bool(mmi.get_meta("far", false))
		if far:
			mmi.visible = not low and fog_end > FAR_SEEN
		else:
			mmi.multimesh.visible_instance_count = int(mmi.multimesh.instance_count * LOW_SHARE) if low else -1


## 一圈树的位置：在 area 外 band[0]–band[1] 米的环里，每 band[2] 米一格，格子里偏一点种一棵；避开出口的路和 skip
static func _ring(area: Rect2, exits: Array, skip: Array, rng: RandomNumberGenerator, band: Array) -> Array:
	var inner := area.grow(float(band[0]))
	var outer := area.grow(float(band[1]))
	var step := float(band[2])
	var out := []
	var x := outer.position.x
	while x < outer.end.x:
		var z := outer.position.y
		while z < outer.end.y:
			var p := Vector3(x + rng.randf_range(0.15, 0.85) * step, 0, z + rng.randf_range(0.15, 0.85) * step)
			z += step
			var p2 := Vector2(p.x, p.z)
			if inner.has_point(p2) or not outer.has_point(p2):
				continue
			if skip.any(func(s: Rect2): return s.grow(1.0).has_point(p2)):
				continue
			if _in_corridor(p, exits):
				continue
			out.append(p)
		x += step
	return out


## 点在不在某个出口那条路（加两边留空）上
static func _in_corridor(p: Vector3, exits: Array) -> bool:
	for e in exits:
		var at: Vector3 = e.at
		var out: Vector3 = e.out
		var d := p - at
		var along := d.dot(out)
		var across := absf(d.dot(Vector3(-out.z, 0, out.x)))
		if along > -2.0 and along < ROAD_LEN + 20.0 and across < float(e.get("half", 1.6)) + CORRIDOR:
			return true
	return false


## 远处的树：只有树干和两根枝（雾里看个轮廓，省三角面）
static func _far_tree(kit: MeshKit, p: Vector3, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(7.0, 11.0)
	var top := p + Vector3(rng.randf_range(-0.3, 0.3), h, rng.randf_range(-0.3, 0.3))
	var r := rng.randf_range(0.14, 0.22)
	kit.cylinder("birch", p + Vector3(0, -0.1, 0), top, r, r * 0.3, 5, 1.0)
	for k in 2:
		var at := p + (top - p) * rng.randf_range(0.6, 0.85)
		var ang := rng.randf() * TAU
		kit.cylinder("bark", at, at + Vector3(cos(ang), rng.randf_range(0.7, 1.1), sin(ang)).normalized() * rng.randf_range(1.4, 2.4), r * 0.3, 0.02, 3, 0.7)


## 出口两边的木栅栏：每 2 米一根桩、两道横杆，沿着边界往两边各 FENCE 米；每边一个碰撞盒（人穿不过去）
static func _fence(kit: MeshKit, solids: StaticBody3D, e: Dictionary) -> void:
	var at: Vector3 = e.at
	var out: Vector3 = e.out
	var side := Vector3(-out.z, 0, out.x)
	var basis := Basis(side, Vector3.UP, out)
	var start := 1.35                                         # 从门柱外侧开始
	for s in [-1.0, 1.0]:
		var d := start
		while d <= start + FENCE + 0.01:
			kit.box("timber", at + side * s * d + Vector3(0, 0.6, 0), Vector3(0.12, 1.2, 0.12), basis, 0.85, 0.5)
			d += 2.0
		var mid: Vector3 = at + side * s * (start + FENCE * 0.5)
		for y in [0.45, 0.95]:
			kit.box("timber", mid + Vector3(0, y, 0), Vector3(FENCE, 0.08, 0.06), basis)
		_solid(solids, mid + Vector3(0, 0.6, 0), Vector3(FENCE + 0.12, 1.2, 0.15), basis)


## 门柱上的灯笼：木框 + 发光的玻璃 + 光晕（不是实时光源）；夜灯，白天灭
static func _lantern(parent: Node3D, kit: MeshKit, e: Dictionary) -> void:
	var at: Vector3 = e.at
	var out: Vector3 = e.out
	var side := Vector3(-out.z, 0, out.x)
	var p := at + side * 1.05 + Vector3(0, 1.95, 0) - out * 0.3     # 挂在一根门柱里侧
	kit.box("timber", p + Vector3(0, 0.17, 0), Vector3(0.26, 0.05, 0.26))
	var lamp := Node3D.new()
	lamp.name = "GateLantern"
	lamp.position = p
	var glass := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, 0.26, 0.18)
	bm.material = Look.glass_lit()
	glass.mesh = bm
	lamp.add_child(glass)
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.1, 1.1)
	var hm := Look.halo(Look.LAMP_COLOR, 0.5).duplicate() as StandardMaterial3D
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = hm
	halo.mesh = q
	lamp.add_child(halo)
	Daypart.mark_night_light(lamp)
	parent.add_child(lamp)
