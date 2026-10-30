class_name HighlandBeacon
extends RefCounted
## 第十九烽「断角烽」的外面和塔下的营地（路线图 5.3b，D12；STORY.md 5.2「山脊上的石砌烽燧塔：塔顶的火盆、塔下的木栅营地（营房、柴棚、粮棚，粮棚快空了）」）。
## 先回答「这里住着谁、缺什么、刚发生过什么」（ART.md 第十节）：住着十来个烽誓团的人和老烽长诺伯特；缺粮、缺柴——柴棚里只剩一小垛，粮棚的架子上只剩两只麻袋；
## 塔顶的火盆是整张图上最亮的光（ART.md「烽燧塔顶的火盆是全图最亮的光；营房只有一盏油灯」），隔着雾在村里也看得见一点暖光。
##   塔：方的石塔，6.4 米见方、11 米高，墙脚一圈宽一点的基石、四角的角石、半腰一道腰线、顶上一圈挑出来的托石和雉堞；
##       东北角塌了一块（「断角」）：那个角的雉堞没了、托石缺了，塔脚下散着掉下来的石头。门朝营地院子，通往塔里（world/beacon_tower.gd）；
##       塔顶：一座石台上架着铁火盆，火烧得正旺（几片按噪声卷动的火苗 shaders/flame.gdshader、火光、火星、烟），一小垛备用的柴，一块木天窗通到塔里（诺伯特的小屋）。
##   木栅：一圈削尖的木桩（多实例，一次画完），两道横木；门开在盘山路进来的那边，两扇门板敞着，门楣上挂着一只断了的号角（「断角」这个名字的来历之一，5.5 诺伯特讲）。
##   营房：矮石屋（Croft），只有一扇窗亮（一盏油灯）；柴棚：敞着的木披棚，柴只剩一小垛、一个劈柴的木墩和斧子；
##   粮棚：架高的木棚（防潮防老鼠），两层架子上只剩两只麻袋，一只空桶倒在地上。
## 同 HighlandVillage：碰撞、门同步建，画面每样一件活交给所在那一块分帧搭。

const TOWER_DOOR := "塔门"
const HATCH_DOWN := "天窗（下到塔里）"
const BARRACKS_TEXT := "营房的门从里面顶着。里面挤着下了岗的人，鼾声一阵一阵的。"
const POST_STEP := 0.42                  # 木桩的间距（米）
const BROKEN := Vector3(1.0, 0.0, -1.0)  # 塌了的那个角（塔的本地坐标：+X、-Z = 东北，朝向转过以后大致还是东北）
const FIRE_Y := 12.2                     # 火在塔脚往上多高
const PARAPET_H := 1.1
const DETAIL_FAR := 110.0                # 营地里的零碎（木栅、门、营房、棚、塌下来的石头）多远以外不画：从村口看整条山谷时绘制调用超了 400（5.3b 实测 425），先砍远处（ART.md 第八节）
const FIRE_FAR := 150.0                  # 火盆、火苗多远以外不画（远处只剩那片光晕）
## 箭窗：[第几面（0 = 门那面，往 +Y 转 90° 一面）, 横着, 高]——外面（这里）和塔里（BeaconTower）同一份；西墙贴着石梯，只在楼上开一道
const SLITS := [[0, -1.2, 2.8], [0, 0.0, 6.2], [1, 0.4, 3.3], [3, 0.0, 6.3], [2, -0.9, 5.6]]

static var _cache := {}


static func clear_cache() -> void:
	_cache.clear()


static func warm() -> void:
	for k in ["stone", "timber", "snow", "bark"]:
		Look.mat(k)
	post_mesh()
	posts()


# ---------------- 摆在哪 ----------------

## 塔的变换：原点在塔脚中心，门朝本地 +Z
static func tower_place() -> Transform3D:
	var c: Vector2 = HighlandLayout.TOWER[0]
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(HighlandLayout.TOWER[1]))), Vector3(c.x, HighlandLayout.tower_base_y() - 0.05, c.y))


## 营地里一处东西的变换（[中心, 朝向, 宽, 纵深]，原点在中心）
static func place_of(spec: Array) -> Transform3D:
	var c: Vector2 = spec[0]
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(spec[1]))), Vector3(c.x, Highland.height_at(c.x, c.y) - 0.05, c.y))


## 木栅门在哪个方向（从营地中心看，单位向量）：最后一段盘山路和木栅那一圈的交点
static func gate_dir() -> Vector2:
	if _cache.has("gate"):
		return _cache.gate
	var c := HighlandLayout.BEACON19
	var n := HighlandLayout.ROAD.size()
	var a: Vector2 = HighlandLayout.ROAD[n - 2]
	var b: Vector2 = HighlandLayout.ROAD[n - 1]
	var hit := b
	for k in 200:
		var p := a.lerp(b, k / 199.0)
		if p.distance_to(c) <= HighlandLayout.PALISADE_R:
			hit = p
			break
	_cache.gate = (hit - c).normalized()
	return _cache.gate


## 木桩：[位置（贴地）, 沿着木栅的切线方向（弧度，绕 Y）, 高的倍数, 歪多少]——门那儿留空
static func posts() -> Array:
	if _cache.has("posts"):
		return _cache.posts
	var out := []
	var c := HighlandLayout.BEACON19
	var r := HighlandLayout.PALISADE_R
	var gate_a := gate_dir().angle()
	var half_gap := (HighlandLayout.GATE_W * 0.5) / r
	var n := int(TAU * r / POST_STEP)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5321
	for k in n:
		var a := TAU * k / n
		if absf(angle_difference(a, gate_a)) < half_gap:
			continue
		var p := c + Vector2.from_angle(a) * (r + rng.randf_range(-0.06, 0.06))
		out.append([Vector3(p.x, Highland.height_at(p.x, p.y) - 0.3, p.y), -a, rng.randf_range(0.88, 1.1), rng.randf_range(-0.04, 0.04)])
	_cache.posts = out
	return out


## 一根木桩：削尖的圆木 + 两截横木（沿本地 X，木栅上一根根接起来就是两道横木）；两种材质一个网格
static func post_mesh() -> ArrayMesh:
	if _cache.has("post_mesh"):
		return _cache.post_mesh
	var kit := MeshKit.new()
	var h := HighlandLayout.PALISADE_H + 0.3
	kit.cylinder("bark", Vector3.ZERO, Vector3(0, h - 0.4, 0), 0.14, 0.13, 6, 0.8)
	kit.cylinder("bark", Vector3(0, h - 0.4, 0), Vector3(0, h, 0), 0.13, 0.01, 6, 0.9)
	for y in [0.9, 2.3]:
		kit.box("timber", Vector3(0, y, -0.16), Vector3(POST_STEP + 0.04, 0.12, 0.08), Basis.IDENTITY, 0.85, 0.7)
	var mi := kit.build({"bark": Look.mat("bark"), "timber": Look.mat("timber")})
	var m := mi.mesh as ArrayMesh
	mi.free()
	_cache.post_mesh = m
	return m


# ---------------- 碰撞、门（同步） ----------------

static func solids() -> Array:
	var out := []
	var tp := tower_place()
	var w := HighlandLayout.TOWER_W
	var th := HighlandLayout.TOWER_H
	out.append([tp * Transform3D(Basis.IDENTITY, Vector3(0, th * 0.5, 0)), Vector3(w, th, w)])          # 塔身（塔里是另一个区域）
	for wall in parapet_walls():                                                                       # 塔顶的雉堞（塌了的角矮）
		out.append([tp * Transform3D(Basis.IDENTITY, wall[0]), wall[1]])
	out.append([tp * Transform3D(Basis.IDENTITY, Vector3(0, th + 0.45, -0.4)), Vector3(1.6, 0.9, 1.6)])  # 火盆和石台
	var c := HighlandLayout.BEACON19
	var r := HighlandLayout.PALISADE_R
	var gate_a := gate_dir().angle()
	var half_gap := (HighlandLayout.GATE_W * 0.5) / r
	var seg := 2.4 / r
	var a := gate_a + half_gap
	var end := gate_a + TAU - half_gap
	while a < end - 0.001:                                                                             # 木栅：一段段弦
		var b := minf(a + seg, end)
		var p0 := c + Vector2.from_angle(a) * r
		var p1 := c + Vector2.from_angle(b) * r
		var mid := (p0 + p1) * 0.5
		var y := Highland.height_at(mid.x, mid.y)
		var dir := p1 - p0
		out.append([Transform3D(Basis(Vector3.UP, -dir.angle()), Vector3(mid.x, y + 1.4, mid.y)), Vector3(dir.length() + 0.1, 2.8, 0.35)])
		a = b
	out.append_array(Croft.solids(barracks_front(), float(HighlandLayout.BARRACKS[1]), barracks_spec()))
	for sh in [HighlandLayout.WOODSHED, HighlandLayout.GRANARY]:                                        # 两个披棚：后墙和两边
		var pl := place_of(sh)
		var sw := float(sh[2])
		var sd := float(sh[3])
		out.append([pl * Transform3D(Basis.IDENTITY, Vector3(0, 1.0, -sd * 0.5)), Vector3(sw, 2.0, 0.2)])
		for s in [-1.0, 1.0]:
			out.append([pl * Transform3D(Basis.IDENTITY, Vector3(s * sw * 0.5, 1.0, 0)), Vector3(0.2, 2.0, sd)])
	return out


## 雉堞（塔的本地坐标）：[中心, 尺寸]——四边各一道，塌了的那个角两边各缺 1.8 米、只剩矮矮的一截
static func parapet_walls() -> Array:
	var w := HighlandLayout.TOWER_W
	var th := HighlandLayout.TOWER_H
	var t := 0.45
	var hw := w * 0.5
	var out := []
	var gap := 1.8
	# 北（-Z）：西头到东边缺口；东（+X）：北边缺口到南头
	out.append([Vector3(-gap * 0.5, th + PARAPET_H * 0.5, -hw + t * 0.5), Vector3(w - gap, PARAPET_H, t)])
	out.append([Vector3(hw - t * 0.5, th + PARAPET_H * 0.5, gap * 0.5), Vector3(t, PARAPET_H, w - gap)])
	out.append([Vector3(0, th + PARAPET_H * 0.5, hw - t * 0.5), Vector3(w, PARAPET_H, t)])
	out.append([Vector3(-hw + t * 0.5, th + PARAPET_H * 0.5, 0), Vector3(t, PARAPET_H, w)])
	out.append([Vector3(hw - gap * 0.5, th + 0.25, -hw + t * 0.5), Vector3(gap, 0.5, t)])       # 塌了的角：只剩半截
	out.append([Vector3(hw - t * 0.5, th + 0.25, -hw + gap * 0.5), Vector3(t, 0.5, gap)])
	return out


static func barracks_spec() -> Dictionary:
	return {"id": "barracks", "w": float(HighlandLayout.BARRACKS[2]), "d": float(HighlandLayout.BARRACKS[3]), "door_x": -1.6, "lit": 0.34, "seed": 53}


## 营房的正面墙脚中点（Croft 的原点）
static func barracks_front() -> Vector3:
	var c: Vector2 = HighlandLayout.BARRACKS[0]
	var yaw := deg_to_rad(float(HighlandLayout.BARRACKS[1]))
	var f := c + Vector2(sin(yaw), cos(yaw)) * float(HighlandLayout.BARRACKS[3]) * 0.5
	return Vector3(f.x, Highland.height_at(f.x, f.y) - 0.05, f.y)


## 营里的人（5.3c）：团长马蒂亚斯在柴棚前数柴，烽长诺伯特在塔顶火盆边（对话 data/dialogue/beacon19.json）；只说一句的兵（LINES）
const LINES := {
	"gate": ["进来吧。天一黑门就合上——合上也没用，它们不走门。", "从羊脊村上来的？路上看见光脚的人没有？……没有就好。", "南边的粮？我站这个门三个月了，只看见上来的人，没看见上来的粮。"],
	"chopper": ["今年是我第十年。守满十年，罪和债一笔勾销，开春就能下山——团长说，开春是哪天，他说了算。", "劈柴得省着劈。斧子砍一下，碎屑也是柴。", "我家在南边，金穗平原那头。有个姑娘等我。等了十年，不知道还等不等。"],
	"sacks": ["两袋。昨天是三袋。你算算还剩几天。", "老鼠都饿跑了。粮棚架那么高，防的是老鼠，防不住人饿。"],
	"door": ["营房里只点一盏灯。油也得省——塔顶的火比我们的眼睛要紧。", "下了岗的都在里面睡。睡得着的就睡，睡不着的……睡不着反倒好。"],
}


static func people(parent: Node3D) -> void:
	var tp := tower_place()
	var wood := place_of(HighlandLayout.WOODSHED)
	var gran := place_of(HighlandLayout.GRANARY)
	var g := gate_dir()
	var tangent := Vector2(-g.y, g.x)
	var c := HighlandLayout.BEACON19
	var gate_in := c + g * (HighlandLayout.PALISADE_R - 1.8) + tangent * 2.6
	var bf := barracks_front()
	var list := [
		["matthias", "马蒂亚斯", wood * Vector3(0.2, 0, 3.0), deg_to_rad(float(HighlandLayout.WOODSHED[1])) + PI, "4a4038", "matthias"],     # 柴棚前，背对着柴棚、面朝院子
		["norbert", "诺伯特", tp * Vector3(-1.25, HighlandLayout.TOWER_H, -0.5), deg_to_rad(float(HighlandLayout.TOWER[1])) - PI * 0.5, "5a5650", "norbert"],   # 塔顶火盆边，面朝火
		["gate", "守门的兵", Vector3(gate_in.x, 0, gate_in.y), atan2(-g.x, -g.y), "3e3a34", ""],      # 门里，面朝门外（rotation.y = θ 时面朝 (-sin θ, -cos θ)）
		["chopper", "劈柴的老兵", wood * Vector3(1.0, 0, 1.15), deg_to_rad(float(HighlandLayout.WOODSHED[1])), "3e3a34", ""],        # 柴棚里的木墩前
		["sacks", "数麻袋的兵", gran * Vector3(0, 0, 2.1), deg_to_rad(float(HighlandLayout.GRANARY[1])), "3e3a34", ""],              # 粮棚前，面朝架子
		["door", "营房门口的兵", Vector3(bf.x + 0.9, 0, bf.z + 1.6), -PI * 0.5, "3e3a34", ""],                                       # 营房门口，面朝院子
	]
	for p in list:
		if str(p[0]) == "sacks" and str(GameState.get_flag("ch2_first_tide", "")) == "lost_one":
			continue                                                  # 第一夜潮水漫进了营地（5.4c）：天亮以后数麻袋的兵不见了
		if str(p[0]) == "chopper" and str(GameState.get_flag("ch2_carsten", "")) == "fled":
			continue                                                  # 支线「第十年」（5.5b）：你帮卡斯滕夜里溜走了
		if str(p[0]) == "chopper" and GameState.has_flag("ch2_first_tide"):
			p = ["chopper", "卡斯滕", p[2], p[3], p[4], "carsten"]    # 第二天：劈柴的老兵报了名字，有话说（5.5b）
		if str(p[0]) == "norbert" and GameState.has_flag("ch2_first_tide"):
			if Chapter2.at_dawn():
				dawn_norbert(parent)                                  # 第二夜过去（5.8）：他又上了塔顶，在火盆边
			continue                                                  # 第二天（5.5a）：诺伯特下了塔顶，在自己的小屋里（BeaconTower）
		var at: Vector3 = p[2]
		var n := Npc.make(str(p[1]), LINES.get(str(p[0]), []), Color(str(p[4])))
		n.name = "Npc_" + str(p[0])
		if str(p[5]) != "":
			n.dialogue_area = "beacon19"
			n.dialogue_id = str(p[5])
		n.position = Vector3(at.x, at.y if str(p[0]) == "norbert" else Highland.height_at(at.x, at.z), at.z)
		n.rotation.y = float(p[3])
		n.far_end = DETAIL_FAR                                       # 从村口看整条山谷时不画（绘制调用，5.3c 实测 417）
		parent.add_child(n)
	if str(GameState.get_flag("ch1_causeway", "")) == "lost" and not GameState.has_flag("ch2_wood_carried"):
		var fw := Pickup.make("firewood", "一捆柴", Color("8a6a44"), Vector3(0.7, 0.28, 0.32))     # 堤道失守的那条线：诺伯特要你扛一捆柴上塔顶（STORY.md 5.4）
		fw.pickup_id = "beacon19_firewood"
		var at := wood * Vector3(-1.0, 0, -float(HighlandLayout.WOODSHED[3]) * 0.5 + 1.0)
		fw.position = Vector3(at.x, Highland.height_at(at.x, at.z) + 0.2, at.z)
		parent.add_child(fw)


## 第二夜过去以后（5.8，Chapter2.at_dawn）诺伯特在塔顶火盆边：火亮着站着添柴；火灭了蹲在冷灰边（@norbert_cold）。已经在了就不再放
static func dawn_norbert(parent: Node3D) -> void:
	if not parent.find_children("Npc_norbert*", "", true, false).is_empty():
		return
	var tp := tower_place()
	var at := tp * Vector3(-1.25, HighlandLayout.TOWER_H, -0.5)
	var n := Npc.make("诺伯特", [], Color("5a5650"))
	n.name = "Npc_norbert_cold" if Chapter2.fire_out() else "Npc_norbert"
	n.dialogue_area = "beacon19"
	n.dialogue_id = "norbert"
	n.position = at
	n.rotation.y = deg_to_rad(float(HighlandLayout.TOWER[1])) - PI * 0.5
	n.far_end = DETAIL_FAR
	parent.add_child(n)


## 塔门、塔顶的天窗、营房的门
static func interactables(parent: Node3D) -> void:
	var tp := tower_place()
	var d := Door.make(TOWER_DOOR, 1.1, 2.1, false)
	d.name = "TowerDoor"
	d.verb = "进入"
	d.to_area = "beacon_tower"
	d.to_spawn = "front"
	d.transform = tp * Transform3D(Basis.IDENTITY, Vector3(-0.55, 0, HighlandLayout.TOWER_W * 0.5 + 0.02))
	parent.add_child(d)
	var h := Door.make(HATCH_DOWN, 1.0, 0.25, false)
	h.name = "TowerHatch"
	h.verb = "下去"
	h.panel = false                                                   # 天窗的木板画在塔上；这里只要一个能对准的盒子
	h.to_area = "beacon_tower"
	h.to_spawn = "top"
	h.transform = tp * Transform3D(Basis.IDENTITY, Vector3(1.0, HighlandLayout.TOWER_H, 1.75))
	parent.add_child(h)
	var spec := barracks_spec()
	var bd := Door.make("营房的门", 0.9, 1.64, true)
	bd.name = "BarracksDoor"
	bd.locked_text = BARRACKS_TEXT
	bd.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(HighlandLayout.BARRACKS[1]))), barracks_front()) * Transform3D(Basis.IDENTITY, Vector3(float(spec.door_x) - 0.45, 0, 0.1))
	parent.add_child(bd)


# ---------------- 画面（分帧的活） ----------------

static func jobs_for(rect: Rect2, reduced_motion: bool) -> Array:
	var out := []
	if rect.has_point(HighlandLayout.TOWER[0]):
		out.append(func(root: Node3D): _tower(root))
		out.append(func(root: Node3D): _fire(root, reduced_motion))
	if rect.has_point(HighlandLayout.BARRACKS[0]):
		out.append(func(root: Node3D): far_cut(Croft.build(root, barracks_front(), float(HighlandLayout.BARRACKS[1]), barracks_spec()), DETAIL_FAR))
	if rect.has_point(HighlandLayout.WOODSHED[0]) or rect.has_point(HighlandLayout.GRANARY[0]):
		out.append(func(root: Node3D): _sheds(root, rect))
	var ps := posts().filter(func(p): return rect.has_point(Vector2(p[0].x, p[0].z)))
	if not ps.is_empty():
		out.append(func(root: Node3D): _palisade(root, ps))
	var g := HighlandLayout.BEACON19 + gate_dir() * HighlandLayout.PALISADE_R
	if rect.has_point(g):
		out.append(func(root: Node3D): _gate(root))
	return out


## 把一个节点下面所有画出来的东西设成多远以外不画
static func far_cut(node: Node, dist: float) -> Node:
	if node is GeometryInstance3D and (node as GeometryInstance3D).visibility_range_end == 0.0:
		(node as GeometryInstance3D).visibility_range_end = dist
	for ch in node.get_children():
		far_cut(ch, dist)
	return node


## 塔身：基石、墙、角石、腰线、托石、雉堞（塌了一角）、门洞、箭窗、塔顶的石板地和天窗、积雪；塔脚下塌下来的石头
static func _tower(root: Node3D) -> void:
	var kit := MeshKit.new()
	var w := HighlandLayout.TOWER_W
	var th := HighlandLayout.TOWER_H
	var hw := w * 0.5
	kit.box("stone", Vector3(0, 0.5, 0), Vector3(w + 0.5, 1.0, w + 0.5), Basis.IDENTITY, 0.75, 0.45)      # 基石
	kit.box("stone", Vector3(0, th * 0.5, 0), Vector3(w, th, w), Basis.IDENTITY, 1.0, 0.6)
	for sx in [-1.0, 1.0]:                                                                                # 角石：每隔一层错开（长短交替）
		for sz in [-1.0, 1.0]:
			if Vector3(sx, 0, sz) == BROKEN:
				continue
			var y := 1.2
			var k := 0
			while y < th - 0.6:
				var long := 0.95 if k % 2 == 0 else 0.6
				kit.box("quoin", Vector3(sx * (hw - long * 0.5 + 0.06), y + 0.22, sz * (hw - 0.3 + 0.06)), Vector3(long, 0.44, 0.6), Basis.IDENTITY, 1.0, 0.8)
				kit.box("quoin", Vector3(sx * (hw - 0.3 + 0.06), y + 0.22, sz * (hw - (1.55 - long) * 0.5 + 0.06)), Vector3(0.6, 0.44, 1.55 - long), Basis.IDENTITY, 1.0, 0.8)
				y += 0.48
				k += 1
	kit.box("quoin", Vector3(0, 4.3, 0), Vector3(w + 0.16, 0.22, w + 0.16), Basis.IDENTITY, 0.9, 0.7)       # 腰线
	for side in 4:                                                                                         # 托石（一排挑出来的石头）+ 上面一圈挑檐
		var rot := Basis(Vector3.UP, side * PI * 0.5)
		for k in 7:
			var at := rot * Vector3(-hw + 0.45 + k * (w - 0.9) / 6.0, th - 0.55, hw + 0.15)
			if at.x > hw - 1.9 and at.z < -hw + 1.9:
				continue                                                                                   # 塌了的那个角：托石也掉了
			kit.box("quoin", at, Vector3(0.3, 0.5, 0.3), rot, 0.9, 0.6)
	kit.box("stone", Vector3(0, th - 0.15, 0), Vector3(w + 0.5, 0.3, w + 0.5), Basis.IDENTITY, 0.85, 0.6)
	for wall in parapet_walls():                                                                           # 雉堞：矮墙 + 一个个垛子
		var c: Vector3 = wall[0]
		var s: Vector3 = wall[1]
		if s.y < 0.6:
			kit.box("stone", c + Vector3(0, -0.05, 0), s + Vector3(0, -0.1, 0), Basis.IDENTITY, 0.85, 0.6)        # 塌了的半截：顶上不平
			kit.box("snow", c + Vector3(0, s.y * 0.5 - 0.06, 0), Vector3(s.x * 0.9, 0.08, s.z * 0.9), Basis.IDENTITY, 1.0, 0.95)
			continue
		var low := 0.6
		kit.box("stone", Vector3(c.x, th + low * 0.5, c.z), Vector3(s.x, low, s.z), Basis.IDENTITY, 0.9, 0.6)
		var along := Vector3.RIGHT if s.x > s.z else Vector3.BACK
		var length := maxf(s.x, s.z)
		var n := int(length / 1.2)
		for k in n:
			var off := along * (-length * 0.5 + (k + 0.5) * length / n)
			var msize := Vector3(0.62, PARAPET_H - low, s.z) if along == Vector3.RIGHT else Vector3(s.x, PARAPET_H - low, 0.62)
			kit.box("stone", Vector3(c.x, th + low, c.z) + off + Vector3(0, msize.y * 0.5, 0), msize, Basis.IDENTITY, 1.0, 0.85)
			kit.box("snow", Vector3(c.x, th + PARAPET_H + 0.04, c.z) + off, msize * Vector3(0.95, 0, 0.95) + Vector3(0, 0.08, 0), Basis.IDENTITY, 1.0, 0.95)
	kit.box("slab", Vector3(0, th + 0.02, 0), Vector3(w - 0.9, 0.04, w - 0.9), Basis.IDENTITY, 0.9, 0.9)    # 塔顶的石板（火盆边上雪化了）
	for k in 4:                                                                                            # 雉堞脚下一圈积雪
		var rot := Basis(Vector3.UP, k * PI * 0.5)
		kit.box("snow", rot * Vector3(0, th + 0.08, hw - 0.7), Vector3(w - 1.5, 0.12, 0.45), rot, 1.0, 0.95)
	kit.box("timber", Vector3(1.5, th + 0.06, 1.75), Vector3(1.0, 0.06, 0.9), Basis.IDENTITY, 0.8, 0.7)     # 天窗的木板
	kit.box("iron", Vector3(1.5, th + 0.1, 1.45), Vector3(0.5, 0.03, 0.04))
	kit.box("timber", Vector3(-1.7, th + 0.2, 1.4), Vector3(1.4, 0.36, 0.7), Basis(Vector3.UP, 0.3), 0.8, 0.6)   # 备用的一小垛柴
	# 门洞：深色的门道 + 门楣石
	kit.box("dark", Vector3(0, 1.1, hw + 0.005), Vector3(1.3, 2.2, 0.02))
	kit.box("quoin", Vector3(0, 2.35, hw + 0.08), Vector3(1.7, 0.3, 0.2), Basis.IDENTITY, 0.95, 0.8)
	for sx in [-1.0, 1.0]:
		kit.box("quoin", Vector3(sx * 0.78, 1.15, hw + 0.06), Vector3(0.26, 2.3, 0.16), Basis.IDENTITY, 0.9, 0.7)
	for slit in SLITS:                                                                                     # 箭窗：窄窄一条黑
		var b := Basis(Vector3.UP, int(slit[0]) * PI * 0.5)
		kit.box("dark", b * Vector3(float(slit[1]), float(slit[2]), hw + 0.005), Vector3(0.16, 0.9, 0.02), b)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("0c0a09")
	dark.roughness = 1.0
	var slab := Highland.ground_material()
	var mi := kit.build({"stone": Look.mat("stone"), "quoin": _quoin_mat(), "snow": Look.mat("snow"), "timber": Look.mat("timber"), "dark": dark,
		"iron": Inn._iron_mat(), "slab": Look.mat("street")})
	mi.name = "BeaconTower"
	mi.transform = tower_place()
	root.add_child(mi)
	var mm := MultiMesh.new()                                                                              # 塌下来的石头：散在东北角塔脚下
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = HighlandFlora.rock_mesh(3)
	mm.instance_count = 10
	var rng := RandomNumberGenerator.new()
	rng.seed = 5322
	var tp := tower_place()
	for k in 10:
		var lp := Vector3(hw + rng.randf_range(0.3, 2.6), 0.0, -hw - rng.randf_range(0.3, 2.6))
		if k < 4:
			lp = Vector3(hw + rng.randf_range(0.2, 1.0), 0.0, -hw + rng.randf_range(-0.2, 1.5))
		var wp := tp * lp
		var s := rng.randf_range(0.35, 0.7)
		mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.75, s)), Vector3(wp.x, Highland.height_at(wp.x, wp.z) + s * 0.15, wp.z)))
	var rubble := MultiMeshInstance3D.new()
	rubble.name = "TowerRubble"
	rubble.multimesh = mm
	rubble.material_override = slab
	rubble.visibility_range_end = DETAIL_FAR
	root.add_child(rubble)


static func _quoin_mat() -> StandardMaterial3D:
	if not _cache.has("quoin_mat"):
		var m := (Look.mat("stone") as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.albedo_color = m.albedo_color.lightened(0.12)                   # 角石、腰线、托石：琢过的石头，颜色浅一点
		_cache.quoin_mat = m
	return _cache.quoin_mat


## 塔顶的火盆：石台、铁篮（一圈铁条、两道箍）、烧得正旺的柴（自发光的火苗）、火光（全图最亮）、远处也看得见的光晕、火星、烟
static func _fire(root: Node3D, reduced_motion: bool) -> void:
	var tp := tower_place()
	var th := HighlandLayout.TOWER_H
	var c := Vector3(0, th, -0.4)
	var kit := MeshKit.new()
	kit.box("stone", c + Vector3(0, 0.2, 0), Vector3(1.6, 0.4, 1.6), Basis.IDENTITY, 0.85, 0.6)
	for k in 12:                                                                                           # 铁条
		var a := TAU * k / 12.0
		var lo := c + Vector3(cos(a) * 0.5, 0.4, sin(a) * 0.5)
		var hi := c + Vector3(cos(a) * 0.85, 1.25, sin(a) * 0.85)
		kit.cylinder("iron", lo, hi, 0.035, 0.03, 4)
	for ring in [[0.62, 0.7], [0.85, 1.22]]:                                                               # 两道箍
		var r := float(ring[0])
		var y := float(ring[1])
		for k in 16:
			var a0 := TAU * k / 16.0
			var a1 := TAU * (k + 1) / 16.0
			kit.cylinder("iron", c + Vector3(cos(a0) * r, y, sin(a0) * r), c + Vector3(cos(a1) * r, y, sin(a1) * r), 0.03, 0.03, 4)
	var mi := kit.build({"stone": Look.mat("stone"), "iron": Inn._iron_mat()})
	mi.name = "BeaconBrazier"
	mi.visibility_range_end = FIRE_FAR
	mi.transform = tp
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var lit_root := Node3D.new()                                                                           # 火（5.8：天亮时粮没上山，火熄了——整组藏起来，换上冷灰 BeaconAsh）
	lit_root.name = "BeaconFlames"
	root.add_child(lit_root)
	var ash_root := Node3D.new()
	ash_root.name = "BeaconAsh"
	root.add_child(ash_root)
	for cold in [false, true]:
		var ek := MeshKit.new()
		ek.box("ember", c + Vector3(0, 0.62, 0), Vector3(1.0, 0.14 if not cold else 0.1, 1.0))           # 炭 / 冷灰
		var rng := RandomNumberGenerator.new()
		rng.seed = 5323
		for k in (7 if not cold else 4):                                                                   # 烧着的柴 / 烧剩的几截黑柴头
			var a := rng.randf() * TAU
			ek.cylinder("char", c + Vector3(cos(a) * 0.45, 0.65, sin(a) * 0.45), c + Vector3(-cos(a) * 0.3, 1.0 if not cold else 0.75, -sin(a) * 0.3), 0.07, 0.06, 5)
		var ember := StandardMaterial3D.new()
		if cold:
			ember.albedo_color = Color("6e6a66")                                                           # 灰白的冷灰（压暗一点：天光下不发白）
			ember.roughness = 1.0
		else:
			ember.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ember.albedo_color = Color("ff5a1e")
		var char_m := StandardMaterial3D.new()
		char_m.albedo_color = Color("1a1412")
		char_m.roughness = 0.9
		var em := ek.build({"ember": ember, "char": char_m})
		em.name = "BeaconCinders" if cold else "BeaconEmbers"
		em.visibility_range_end = FIRE_FAR
		em.transform = tp
		em.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(ash_root if cold else lit_root).add_child(em)
	root = lit_root
	var flame_sh := load("res://shaders/flame.gdshader") as Shader                                         # 火苗：几片绕 Y 轴对着镜头、按噪声往上卷的火（shaders/flame.gdshader）
	for k in 4:
		var q0 := QuadMesh.new()
		var fw: float = [1.5, 1.1, 1.0, 0.8][k]
		var fh: float = [2.3, 2.0, 1.6, 1.4][k]
		q0.size = Vector2(fw, fh)
		var fm := ShaderMaterial.new()
		fm.shader = flame_sh
		fm.set_shader_parameter("noise_tex", Look.noise_texture())
		fm.set_shader_parameter("phase", 0.23 * k + 0.1)
		fm.set_shader_parameter("speed", 0.0 if reduced_motion else 1.0)
		fm.set_shader_parameter("strength", 1.3 if k == 0 else 1.0)
		q0.material = fm
		var fl := MeshInstance3D.new()
		fl.name = "Flame%d" % k
		fl.mesh = q0
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fl.visibility_range_end = FIRE_FAR
		var off: Vector3 = [Vector3.ZERO, Vector3(0.25, 0, 0.1), Vector3(-0.22, 0, -0.12), Vector3(0.05, 0, 0.28)][k]
		fl.position = tp * (c + off + Vector3(0, 0.6 + fh * 0.5, 0))
		root.add_child(fl)
	var at := tp * (c + Vector3(0, 1.5, 0))
	var fire := Tavern.FireLight.new()
	fire.name = "BeaconFire"
	fire.light_color = Color("ff8a3a")
	fire.base = 7.0
	fire.omni_range = 30.0
	fire.omni_attenuation = 1.3
	fire.flicker = not reduced_motion
	fire.position = at
	fire.add_to_group("light_source")
	fire.set_meta("radius", 2.6)
	root.add_child(fire)
	var halo := MeshInstance3D.new()                                                                       # 近处：火上的一团光
	var q := QuadMesh.new()
	q.size = Vector2(3.2, 3.6)
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.albedo_texture = Look.halo_texture()
	hm.albedo_color = Color(1.0, 0.6, 0.25, 0.9)
	hm.disable_fog = true
	q.material = hm
	halo.mesh = q
	halo.position = at + Vector3(0, 0.3, 0)
	halo.visibility_range_end = FIRE_FAR
	root.add_child(halo)
	var glow := MeshInstance3D.new()                                                                       # 远处：隔着雾也看得见的一点暖光（不受雾影响，同远处那串烽燧）
	var g := QuadMesh.new()
	g.size = Vector2(40.0, 40.0)
	var gm := hm.duplicate() as StandardMaterial3D
	gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	gm.albedo_color = Color(1.0, 0.55, 0.22, 0.6)
	gm.disable_fog = true
	gm.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA       # 近处淡掉（站在塔顶时不是满屏的光）
	gm.distance_fade_min_distance = 8.0
	gm.distance_fade_max_distance = 22.0
	g.material = gm
	glow.mesh = g
	glow.name = "BeaconFireGlow"
	glow.position = at
	root.add_child(glow)
	if not reduced_motion:
		root.add_child(_sparks(at))
		Atmos.smoke(root, at + Vector3(0, 1.0, 0))
	apply_fire(root.get_parent())


## 第十九烽的火亮不亮（5.8：天亮时 Chapter2.fire_out() 就熄了；搭好以后、天亮那一刻 main 都调一次）
static func apply_fire(root: Node) -> void:
	var out := Chapter2.fire_out()
	for n in root.find_children("BeaconFlames", "Node3D", true, false):
		(n as Node3D).visible = not out
	for n in root.find_children("BeaconAsh", "Node3D", true, false):
		(n as Node3D).visible = out


## 火星：一小撮往上飘、被风吹歪的亮点
static func _sparks(at: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "BeaconSparks"
	p.visibility_range_end = 80.0
	p.position = at
	p.amount = 24
	p.lifetime = 1.6
	p.preprocess = 1.6
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = Atmos._soft_dot()
	m.albedo_color = Color("ffb04a")
	q.material = m
	p.mesh = q
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5
	p.direction = Vector3(0, 1, 0)
	p.spread = 25.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Atmos.HIGHLAND_WIND * 0.8 + Vector3(0, 0.4, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	p.local_coords = false
	return p


## 木栅：多实例的木桩
static func _palisade(root: Node3D, list: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = post_mesh()
	mm.instance_count = list.size()
	for i in list.size():
		var p: Array = list[i]
		var b := Basis(Vector3.UP, float(p[1]) - PI * 0.5) * Basis(Vector3.RIGHT, float(p[3]))
		mm.set_instance_transform(i, Transform3D(b.scaled(Vector3(1.0, float(p[2]), 1.0)), p[0]))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Palisade"
	mi.multimesh = mm
	mi.visibility_range_end = DETAIL_FAR
	root.add_child(mi)


## 木栅门：两根粗门柱、门楣（挂着一只断了的号角）、两扇往里敞着的门板
static func _gate(root: Node3D) -> void:
	var c := HighlandLayout.BEACON19
	var g := gate_dir()
	var r := HighlandLayout.PALISADE_R
	var mid := c + g * r
	var y := Highland.height_at(mid.x, mid.y)
	var tangent := Vector2(-g.y, g.x)
	var place := Transform3D(Basis(Vector3.UP, -tangent.angle()), Vector3(mid.x, y, mid.y))   # 本地 X 沿木栅、-Z 朝营地里
	var hw := HighlandLayout.GATE_W * 0.5
	var kit := MeshKit.new()
	for s in [-1.0, 1.0]:
		kit.cylinder("bark", Vector3(s * (hw + 0.1), -0.4, 0), Vector3(s * (hw + 0.1), 3.7, 0), 0.22, 0.2, 7, 0.8)
		var leaf := Basis(Vector3.UP, s * 1.2)                                                   # 门板往里敞着
		var hinge := Vector3(s * hw, 0, 0)
		for k in 6:
			var lx: float = -s * (0.18 + k * 0.33)
			kit.box("timber", hinge + leaf * Vector3(lx, 1.35, -0.05), Vector3(0.3, 2.6, 0.1), leaf, 0.85, 0.6)
		for yy in [0.5, 2.2]:
			kit.box("timber", hinge + leaf * Vector3(-s * hw * 0.5, yy, -0.14), Vector3(hw, 0.14, 0.06), leaf, 0.8, 0.6)
	kit.box("timber", Vector3(0, 3.55, 0), Vector3(HighlandLayout.GATE_W + 0.8, 0.26, 0.3), Basis.IDENTITY, 0.85, 0.6)     # 门楣
	kit.box("snow", Vector3(0, 3.72, 0), Vector3(HighlandLayout.GATE_W + 0.7, 0.1, 0.28), Basis.IDENTITY, 1.0, 0.95)
	kit.cylinder("horn", Vector3(-0.3, 3.2, 0.2), Vector3(0.25, 3.05, 0.22), 0.09, 0.05, 7)                               # 断了的号角：挂在门楣上，尖那头没了
	kit.cylinder("horn", Vector3(-0.3, 3.2, 0.2), Vector3(-0.42, 3.22, 0.2), 0.1, 0.11, 7)
	kit.cylinder("iron", Vector3(-0.15, 3.42, 0.18), Vector3(-0.15, 3.2, 0.2), 0.012, 0.012, 3)
	var horn := StandardMaterial3D.new()
	horn.albedo_color = Color("c9b48a")
	horn.roughness = 0.6
	var mi := kit.build({"bark": Look.mat("bark"), "timber": Look.mat("timber"), "snow": Look.mat("snow"), "horn": horn, "iron": Inn._iron_mat()})
	mi.name = "PalisadeGate"
	mi.visibility_range_end = DETAIL_FAR
	mi.transform = place
	root.add_child(mi)


## 柴棚、粮棚：木披棚（四根柱、后墙和两边是木板、单坡顶压着雪）。柴棚里一小垛柴、劈柴的木墩和斧子；粮棚架高，两层架子上两只麻袋、一只空桶倒着
static func _sheds(root: Node3D, rect: Rect2) -> void:
	var d := Decor.new()
	for sh in [HighlandLayout.WOODSHED, HighlandLayout.GRANARY]:
		if not rect.has_point(sh[0]):
			continue
		var granary: bool = sh == HighlandLayout.GRANARY
		var pl := place_of(sh)
		var kit := MeshKit.new()
		var sw := float(sh[2])
		var sd := float(sh[3])
		var floor_y := 0.45 if granary else 0.0
		var front_h := 2.5
		var back_h := 1.9
		for x in [-sw * 0.5, sw * 0.5]:
			for z in [-sd * 0.5, sd * 0.5]:
				var h := front_h if z > 0.0 else back_h
				kit.cylinder("bark", Vector3(x, -0.2, z), Vector3(x, h, z), 0.09, 0.08, 6, 0.8)
		var pitch := atan2(front_h - back_h, sd)
		var roof_b := Basis(Vector3.RIGHT, -pitch)
		kit.box("timber", Vector3(0, (front_h + back_h) * 0.5 + 0.06, 0), Vector3(sw + 0.5, 0.07, sd + 0.6), roof_b, 0.85, 0.6)
		kit.box("snow", Vector3(0, (front_h + back_h) * 0.5 + 0.16, 0), Vector3(sw + 0.4, 0.13, sd + 0.5), roof_b, 1.0, 0.95)
		kit.box("timber", Vector3(0, back_h * 0.5, -sd * 0.5 - 0.04), Vector3(sw, back_h, 0.06), Basis.IDENTITY, 0.8, 0.5)
		for s in [-1.0, 1.0]:
			kit.box("timber", Vector3(s * (sw * 0.5 + 0.04), 0.95, 0), Vector3(0.06, 1.9, sd), Basis.IDENTITY, 0.8, 0.5)
		if granary:
			kit.box("timber", Vector3(0, floor_y, 0), Vector3(sw, 0.08, sd), Basis.IDENTITY, 0.85, 0.6)
			for y in [1.15, 1.75]:
				kit.box("timber", Vector3(0, y, -sd * 0.5 + 0.35), Vector3(sw - 0.3, 0.05, 0.6), Basis.IDENTITY, 0.9, 0.7)
		var mi := kit.build({"bark": Look.mat("bark"), "timber": Look.mat("timber"), "snow": Look.mat("snow")})
		mi.name = "Granary" if granary else "Woodshed"
		mi.visibility_range_end = DETAIL_FAR
		mi.transform = pl
		root.add_child(mi)
		if granary:
			d.sack(pl * Vector3(-0.9, 1.2, -sd * 0.5 + 0.35), 0.3)
			d.sack(pl * Vector3(0.6, 1.8, -sd * 0.5 + 0.35), 1.1)
			var tipped := pl * Vector3(1.0, floor_y + 0.3, 0.4)
			d.kit.cylinder(d._wood(), tipped + pl.basis * Vector3(-0.4, 0, 0), tipped + pl.basis * Vector3(0.4, 0, 0), 0.3, 0.3, 10, 0.8)
		else:
			d.woodpile(pl * Vector3(-1.0, 0, -sd * 0.5 + 0.45), pl.basis * Vector3.RIGHT, 1.1, 0.45, false)
			var blk := pl * Vector3(1.0, 0, 0.3)
			d.kit.cylinder(d._wood(), blk, blk + Vector3(0, 0.5, 0), 0.3, 0.28, 8, 0.8)
			d.kit.cylinder(d._wood(), blk + Vector3(0.05, 0.5, 0), blk + Vector3(0.25, 1.15, 0.05), 0.025, 0.025, 5, 0.7)
			d.kit.box(d._solid(Color("4a4a50"), 0.4, 0.6), blk + Vector3(0.05, 0.53, 0), Vector3(0.18, 0.1, 0.03), Basis(Vector3.FORWARD, 0.3))
	d.build(root, "ShedProps", false).visibility_range_end = DETAIL_FAR


## 树、石头不长在营地里（HighlandFlora.near_village_works 调）
static func blocks(p: Vector2, margin: float) -> bool:
	return p.distance_to(HighlandLayout.BEACON19) < HighlandLayout.PALISADE_R + 2.0 + margin
