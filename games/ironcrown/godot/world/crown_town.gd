class_name CrownTown
extends RefCounted
## 冠城一角的城（路线图 7.6，D12；STORY.md 7.2「一道石桥进桥门，桥门里是贫民区的一条斜街（挤、窄、晾着衣服、排队买面包）；斜街上去是议事厅广场和钟楼；
## 高墙后面的王宫只在远处」）。先回答「这里住着谁、缺什么、刚发生过什么」（ART.md 第十节）：
##   住着谁：贫民区的人——船工、脚夫、洗衣妇、从北边逃荒下来的（斜街两边灰泥木构的窄房子，一栋挤一栋，上层往街上挑）；广场上是各家的人和议事厅的差役；
##   缺什么：面包——面包坊门口从天亮排起长队；柴——好些烟囱不冒烟；
##   刚发生过什么：冬议的告示贴在钟楼底下；议事厅门口刚扫过雪，五家的旗昨夜挂上去了，王座那面旗没有挂。
## 房子沿斜街和三条小巷两边自动摆（houses()，种子固定），每块的房子合成一个网格（同双钥港，HarborTown._merchant），这一块整体按时段亮灯（组 house）。
## 碰撞、门、路牌、告示同步建；画面按所在的块分帧搭（jobs_for）。王宫和岛东头越来越高的城只在地图外面画个影子（palace）。

const BRIDGE_PIERS := [-66.0, -59.0, -52.0, -45.0]  # 石桥的桥墩（x）
const PARAPET_H := 1.0
const TOWER_W := 6.5                                 # 桥门两边的塔：宽、高
const TOWER_H := 14.0
const BELL_W := 5.6                                  # 钟楼：宽、塔身高
const BELL_H := 22.0
const COUNCIL_H := 11.0                              # 议事厅：墙高
const KERB_H := 0.45
const KERB_BLOCK := 1.05
const SIGN_BANK := Vector2(-72.5, -3.6)
const SIGN_BANK_TEXT := "往双钥港（行会的船）"
const SIGN_GATE := Vector2(-34.0, -3.2)
const SIGN_GATE_TEXT := "往议事厅广场 · 桥门"
const JETTY := [Vector2(-66.0, 9.0), Vector2(-57.0, 9.0)]  # 河西岸行会的小码头（往东伸进河里）
const JETTY_W := 2.6
const NOTICE := Vector2(77.0, -14.6)                 # 冬议的告示：钟楼脚下
const NOTICE_TEXT := "钟楼脚下的告示，盖着摄政会议的印：「冬至日辰时，摄政会议于议事厅清账。塞弗林、洛蒙德、瓦伦、厄尔德、卡斯韦尔五家列席；星铁教会大主祭见证。闲人不得入内。」底下有人用炭写了一行：「清的是谁的账？」又有人在旁边添了一行：「面包几个钱？」"
const BAKERY_TEXT := "面包坊的门开着一道缝，一股热气。里面的人隔着门喊：「排队！一人一个，冬至以前都是这个价！」"
const BELL_DOOR_TEXT := "钟楼的门从里面闩着。门上钉着一块牌子：「敲钟的在上面。冬至以前，只敲黄昏那一回。」"
const HOUSE_TEXTS := ["门闩着。里面有孩子在哭，有人在哄。", "门推不开。门缝里一股煮烂了的萝卜味。", "门上钉着一块木板：「房钱冬至交。——钥楼」", "有人隔着门说：「不赊账，也不借火。」", "门开了一道缝，一只眼睛看了你一下，又关上了。"]
const WASH_COLORS := [Color("d8d2c2"), Color("9aa6ae"), Color("8a6a4a"), Color("b8a070"), Color("6e7a6a"), Color("a88070"), Color("cfc8b8")]

static var _houses: Array = []
static var _kerbs: Array = []
static var _wash: Array = []


static func clear_cache() -> void:
	_houses.clear()
	_kerbs.clear()
	_wash.clear()


static func ground(p: Vector2) -> float:
	return CrownCity.height_at(p.x, p.y)


static func xf_of(front: Vector2, yaw: float, y := NAN) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), Vector3(front.x, ground(front) if is_nan(y) else y, front.y))


static func mats() -> Dictionary:
	var m := HarborTown.mats()
	for k in WASH_COLORS.size():
		m["wash%d" % k] = HarborTown._m("wash%d" % k, WASH_COLORS[k], 1.0)
	m["bread"] = HarborTown._m("bread", Color("a8743a"), 0.9)
	return m


static func council_front() -> Vector2:
	return CrownLayout.COUNCIL + Vector2(0, CrownLayout.COUNCIL_D * 0.5)


static func bakery() -> Dictionary:
	return CrownLayout.street_front(CrownLayout.BAKERY)


static func matilda() -> Dictionary:
	return CrownLayout.street_front(CrownLayout.MATILDA)


# ---------------- 房子摆在哪 ----------------

## 沿斜街、小巷自动摆的房子：[{front, yaw, w, d, floors, stone, seed}]（种子固定，每次一样）
static func houses() -> Array:
	if not _houses.is_empty():
		return _houses
	var rng := RandomNumberGenerator.new()
	rng.seed = 7606
	var out := []
	var polys := [CrownLayout.STREET] + CrownLayout.LANES
	for si in polys.size():
		var pts: Array = polys[si]
		var half := CrownLayout.STREET_HALF if si == 0 else CrownLayout.LANE_HALF
		for k in pts.size() - 1:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[k + 1]
			var len := a.distance_to(b)
			var dir := (b - a) / len
			var nrm := Vector2(-dir.y, dir.x)
			var t := 2.0
			while t < len - 2.0:
				var w := rng.randf_range(5.0, 7.4)                              # 贫民区：比双钥港的窄
				for side: float in [-1.0, 1.0]:
					var d := rng.randf_range(6.0, 8.0)
					var front := a + dir * (t + w * 0.5) + nrm * side * (half + 0.9)
					var face := -nrm * side
					var yaw := rad_to_deg(atan2(face.x, face.y))
					var h := {"front": front, "yaw": yaw, "w": w, "d": d, "floors": 2 + int(rng.randf() < 0.6) + int(si == 0 and rng.randf() < 0.3), "stone": false,
						"seed": rng.randi_range(1, 99999)}
					if _fits(h, out):
						out.append(h)
					elif _fits(HarborTown._shrink(h, 5.5), out):
						out.append(HarborTown._shrink(h, 5.5))
					var back := h.duplicate()                                  # 后排：隔一条窄巷背对背再一栋（天际线上一层压一层）
					back.front = front - face * (d + 1.4 + 6.5)
					back.yaw = yaw + 180.0
					back.d = 6.5
					back.floors = 2 + int(rng.randf() < 0.5)
					back.seed = rng.randi_range(1, 99999)
					if _fits(back, out):
						out.append(back)
				t += w + rng.randf_range(0.2, 1.2)
	var x := CrownLayout.WALL_X + 8.0                                     # 街巷背后的空地也挤满（一排排背对背的窄房子，正面朝着斜街那边）
	while x < CrownLayout.BOUNDS.end.x - 8.0:
		var z := -CrownLayout.ISLAND_HALF_Z + 6.0
		while z < CrownLayout.ISLAND_HALF_Z - 6.0:
			var face := Vector2(0, -1) if z > 0.0 else Vector2(0, 1)
			var h := {"front": Vector2(x + rng.randf_range(-1.0, 1.0), z), "yaw": rad_to_deg(atan2(face.x, face.y)) + rng.randf_range(-6.0, 6.0), "w": rng.randf_range(5.5, 7.5),
				"d": rng.randf_range(6.0, 7.5), "floors": 2 + int(rng.randf() < 0.5), "stone": false, "seed": rng.randi_range(1, 99999)}
			if _fits(h, out):
				out.append(h)
			z += 8.5
		x += 7.2
	_houses = out
	return out


## 放得下：四个角、四条边的中点、中间都在岛上（离石岸 4 米以上），不压街、巷、广场、议事厅、钟楼、城墙、两栋认得出的房子、出生点、机位、别的房子
static func _fits(h: Dictionary, others: Array) -> bool:
	var fp := HarborTown.footprint(h)
	var c := HarborTown.house_center(h)
	var probes := Array(fp) + [c]
	for k in 4:
		probes.append((fp[k] + fp[(k + 1) % 4]) * 0.5)
	var council := Rect2(CrownLayout.COUNCIL - Vector2(CrownLayout.COUNCIL_W, CrownLayout.COUNCIL_D) * 0.5, Vector2(CrownLayout.COUNCIL_W, CrownLayout.COUNCIL_D)).grow(3.0)
	for q: Vector2 in probes:
		if CrownLayout.island_d(q) < 4.5 or q.x < CrownLayout.WALL_X + 4.0:
			return false
		if CrownLayout.street_d(q) < CrownLayout.STREET_HALF + 0.4:
			return false
		if CrownLayout.SQUARE.grow(3.0).has_point(q) or council.has_point(q):
			return false
		if q.distance_to(CrownLayout.BELL_TOWER) < BELL_W + 2.0:
			return false
		if not CrownLayout.BOUNDS.grow(-6.0).has_point(q):
			return false
	var r := maxf(float(h.w), float(h.d)) * 0.5
	for sp: Dictionary in [bakery(), matilda()]:
		var sc := House.local_xz(Vector3(sp.front.x, 0, sp.front.y), float(sp.yaw), Vector2(0, -float(sp.d) * 0.5))
		if c.distance_to(sc) < (r + maxf(float(sp.w), float(sp.d)) * 0.5) * 0.95:
			return false
	for keep: Array in [[SIGN_GATE, 2.5], [Vector2(CrownLayout.WALL_X + 3.0, 0.0), 9.0]]:
		if c.distance_to(keep[0]) < float(keep[1]) + r * 0.7:
			return false
	for id in CrownLayout.SPAWN_XZ:
		if c.distance_to(CrownLayout.SPAWN_XZ[id][0]) < r + 2.5:
			return false
	for v: Array in CrownLayout.VIEW_SPEC:
		if c.distance_to(Vector2((v[0] as Vector3).x, (v[0] as Vector3).z)) < r + 2.0:
			return false
	for o: Dictionary in others:
		var oc := HarborTown.house_center(o)
		if c.distance_to(oc) < (r + maxf(float(o.w), float(o.d)) * 0.5) * 0.92:
			return false
	return true


## 斜街上空的晾衣绳：[一头, 另一头, 高]（两边都有房子的地方，每七八米一道）
static func wash_lines() -> Array:
	if not _wash.is_empty():
		return _wash
	var out := []
	var hs := houses()
	var fronts := []
	for h: Dictionary in hs:
		fronts.append(h.front)
	var st: Array = CrownLayout.STREET
	for k in st.size() - 1:
		var a: Vector2 = st[k]
		var b: Vector2 = st[k + 1]
		var len := a.distance_to(b)
		var dir := (b - a) / len
		var nrm := Vector2(-dir.y, dir.x)
		var t := 4.0
		while t < len - 3.0:
			var p := a + dir * t
			var e0 := p + nrm * (CrownLayout.STREET_HALF + 1.0)
			var e1 := p - nrm * (CrownLayout.STREET_HALF + 1.0)
			var near0 := false
			var near1 := false
			for f: Vector2 in fronts:
				near0 = near0 or f.distance_to(e0) < 8.0
				near1 = near1 or f.distance_to(e1) < 8.0
			if near0 and near1:
				out.append([e0, e1, maxf(ground(e0), ground(e1)) + HarborTown.GH + 1.6])
			t += 6.0
	_wash = out
	return out


# ---------------- 碰撞 ----------------

## 石桥桥面：[[起点 x, 终点 x], ...]（每 3 米一段，跟着拱起来）
static func bridge_spans() -> Array:
	var out := []
	var a: Vector2 = CrownLayout.BRIDGE[0]
	var b: Vector2 = CrownLayout.BRIDGE[1]
	var x := a.x
	while x < b.x - 0.01:
		out.append([x, minf(x + 3.0, b.x)])
		x += 3.0
	return out


## 城墙：一段一段 [起点, 终点]（西岸一道，桥门在 z = 0；往北、往南沿岛边拐过去一截）
static func wall_runs() -> Array:
	var out := []
	var g := CrownLayout.GATE_HALF
	var wx := CrownLayout.WALL_X
	var reach := CrownLayout.ISLAND_HALF_Z - 4.0
	out.append([Vector2(wx, -reach), Vector2(wx, -g - TOWER_W)])
	out.append([Vector2(wx, g + TOWER_W), Vector2(wx, reach)])
	for s: float in [-1.0, 1.0]:
		var prev := Vector2(wx, s * reach)
		var x := wx + 6.0
		while x <= -8.0:
			var q := Vector2(x, s * (CrownLayout.island_half(x) - 4.0))
			out.append([prev, q])
			prev = q
			x += 6.0
		out.append([prev, Vector2(prev.x, s * (CrownLayout.island_half(prev.x) - 0.3))])   # 收口：一直砌到石岸边（墙外那一窄条走不进去）
	return out


## 所有挡人的东西：[[变换, 尺寸], ...]（桥面、码头是能站上去的）
static func solids() -> Array:
	var out := []
	for h: Dictionary in houses():
		var xf := xf_of(h.front, float(h.yaw))
		out.append([xf * Transform3D(Basis.IDENTITY, Vector3(0, 3.0, -float(h.d) * 0.5)), Vector3(float(h.w) + 0.2, 6.0, float(h.d) + 0.2)])
	for sp: Dictionary in [bakery(), matilda()]:
		var sx := xf_of(sp.front, float(sp.yaw))
		out.append([sx * Transform3D(Basis.IDENTITY, Vector3(0, 3.0, -float(sp.d) * 0.5)), Vector3(float(sp.w) + 0.2, 6.0, float(sp.d) + 0.2)])
	var cx := xf_of(council_front(), 0.0)
	out.append([cx * Transform3D(Basis.IDENTITY, Vector3(0, 5.0, -CrownLayout.COUNCIL_D * 0.5)), Vector3(CrownLayout.COUNCIL_W + 0.2, 10.0, CrownLayout.COUNCIL_D + 0.2)])
	var bt := CrownLayout.BELL_TOWER
	out.append([Transform3D(Basis.IDENTITY, Vector3(bt.x, ground(bt) + 5.0, bt.y)), Vector3(BELL_W + 0.1, 10.0, BELL_W + 0.1)])
	for run: Array in wall_runs():                                       # 城墙
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		var mid := (a + b) * 0.5
		var d := b - a
		out.append([Transform3D(Basis(Vector3.UP, -atan2(d.y, d.x)), Vector3(mid.x, CrownLayout.ISLAND_Y + 3.0, mid.y)), Vector3(d.length() + 0.4, 10.0, CrownLayout.WALL_T)])
	for s: float in [-1.0, 1.0]:                                         # 桥门两边的塔
		var tc := Vector2(CrownLayout.WALL_X, s * (CrownLayout.GATE_HALF + TOWER_W * 0.5))
		out.append([Transform3D(Basis.IDENTITY, Vector3(tc.x, CrownLayout.ISLAND_Y + 4.0, tc.y)), Vector3(TOWER_W, 12.0, TOWER_W)])
	for sp: Array in bridge_spans():                                     # 石桥：桥面、两边石栏
		var x0 := float(sp[0])
		var x1 := float(sp[1])
		var y0 := CrownCity.bridge_y(x0)
		var y1 := CrownCity.bridge_y(x1)
		var bas := Basis(Vector3.BACK, atan2(y1 - y0, x1 - x0))
		var c := Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5 - 0.2, 0.0)
		out.append([Transform3D(bas, c), Vector3(x1 - x0 + 0.1, 0.4, CrownLayout.BRIDGE_HALF * 2.0)])
		for s2: float in [-1.0, 1.0]:
			out.append([Transform3D(bas, c + Vector3(0, 0.2 + PARAPET_H * 0.5 + 0.3, s2 * (CrownLayout.BRIDGE_HALF + 0.15))), Vector3(x1 - x0 + 0.1, PARAPET_H + 0.6, 0.3)])
	var ja: Vector2 = JETTY[0]                                           # 行会的小码头：板面能站，两边、尽头一道栏
	var jb: Vector2 = JETTY[1]
	var jy := ground(ja) + 0.08
	var jm := (ja + jb) * 0.5
	out.append([Transform3D(Basis.IDENTITY, Vector3(jm.x, jy - 0.15, jm.y)), Vector3(ja.distance_to(jb), 0.3, JETTY_W)])
	for s: float in [-1.0, 1.0]:
		out.append([Transform3D(Basis.IDENTITY, Vector3(jm.x + 2.0, jy + 0.55, jm.y + s * (JETTY_W * 0.5 - 0.05))), Vector3(ja.distance_to(jb) - 4.0, 1.1, 0.1)])
	out.append([Transform3D(Basis.IDENTITY, Vector3(jb.x - 0.05, jy + 0.55, jb.y)), Vector3(0.1, 1.1, JETTY_W)])
	for k: Array in kerbs():
		var a: Vector3 = k[0]
		var b: Vector3 = k[1]
		var mid := (a + b) * 0.5
		var d := b - a
		out.append([Transform3D(Basis(Vector3.UP, -atan2(d.z, d.x)), mid + Vector3(0, KERB_BLOCK * 0.5, 0)), Vector3(Vector2(d.x, d.z).length() + 0.05, KERB_BLOCK, 0.4)])
	return out


## 岛南北两边石岸上沿的栏石（城墙拐过去以后接着往东）：每 2 米一段 [起点, 终点]
static func kerbs() -> Array:
	if not _kerbs.is_empty():
		return _kerbs
	var out := []
	for s: float in [-1.0, 1.0]:
		var x := -10.0
		while x < CrownLayout.BOUNDS.end.x - 6.0:
			var a := Vector2(x, s * (CrownLayout.island_half(x) - 1.0))
			var b := Vector2(x + 2.0, s * (CrownLayout.island_half(x + 2.0) - 1.0))
			out.append([Vector3(a.x, ground(a), a.y), Vector3(b.x, ground(b), b.y)])
			x += 2.0
	_kerbs = out
	return out


# ---------------- 门、路牌、告示（同步） ----------------

static func interactables(parent: Node3D) -> void:
	var k := 0
	for h: Dictionary in houses():
		if int(h.seed) % 3 != 0:
			continue
		var d := Door.make("门", 1.0, 2.0, true)
		d.locked_text = HOUSE_TEXTS[k % HOUSE_TEXTS.size()]
		k += 1
		d.name = "CrownDoor_%d" % k
		d.transform = xf_of(h.front, float(h.yaw)) * Transform3D(Basis.IDENTITY, Vector3(-0.5, 0, 0.06))
		parent.add_child(d)
	var m := matilda()
	for spec: Array in [[council_front(), 0.0, "议事厅的门", "council_hall", 2.4, 3.6, "CouncilDoor"], [m.front, float(m.yaw), "玛蒂尔达的小酒馆", "matilda_inn", 1.0, 2.0, "MatildaDoor"]]:
		var d := Door.make(str(spec[2]), float(spec[4]), float(spec[5]), false)
		d.to_area = str(spec[3])
		d.to_spawn = "front"
		d.verb = "进入"
		d.name = str(spec[6])
		d.transform = xf_of(spec[0], float(spec[1])) * Transform3D(Basis.IDENTITY, Vector3(-float(spec[4]) * 0.5, 0, 0.08))
		parent.add_child(d)
	var bk := bakery()
	var bd := Door.make("面包坊的门", 1.0, 2.0, true)
	bd.locked_text = BAKERY_TEXT
	bd.name = "BakeryDoor"
	bd.transform = xf_of(bk.front, float(bk.yaw)) * Transform3D(Basis.IDENTITY, Vector3(-0.5, 0, 0.06))
	parent.add_child(bd)
	var bt := CrownLayout.BELL_TOWER
	var tdoor := Door.make("钟楼的门", 1.2, 2.3, true)
	tdoor.locked_text = BELL_DOOR_TEXT
	tdoor.name = "BellDoor"
	tdoor.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)), Vector3(bt.x, ground(bt), bt.y)) * Transform3D(Basis.IDENTITY, Vector3(-0.6, 0, BELL_W * 0.5 + 0.02))
	parent.add_child(tdoor)
	for s: Array in [[SIGN_BANK, SIGN_BANK_TEXT, 90.0, "BankSign"], [SIGN_GATE, SIGN_GATE_TEXT, -90.0, "GateSign"]]:
		var rs := RoadSign.new()
		rs.text = str(s[1])
		rs.name = str(s[3])
		rs.position = Vector3((s[0] as Vector2).x, ground(s[0]), (s[0] as Vector2).y)
		rs.rotation_degrees.y = float(s[2])
		parent.add_child(rs)
	var e := Examine.make("冬议的告示", "看告示", func(_who: FpController) -> Dictionary:
		var gs := HarborTown._gs()
		if gs:
			gs.set_flag("ch4_council_notice")
		return {"toast": NOTICE_TEXT}, Vector3(1.6, 2.0, 0.6))
	e.name = "CouncilNotice"
	e.position = Vector3(NOTICE.x, ground(NOTICE), NOTICE.y)
	parent.add_child(e)


# ---------------- 画面（分帧的活） ----------------

static func jobs_for(rect: Rect2) -> Array:
	var out := []
	var hs := []
	for h: Dictionary in houses():
		if rect.has_point(HarborTown.house_center(h)):
			hs.append(h)
	var group := 0
	while group * 8 < hs.size():                                         # 一件活最多 8 栋（同双钥港）
		var part := hs.slice(group * 8, group * 8 + 8)
		var tag := group
		out.append(func(root: Node3D): _house_block(root, part, rect, tag))
		group += 1
	if rect.has_point(bakery().front):
		out.append(func(root: Node3D): _bakery(root))
	if rect.has_point(matilda().front):
		out.append(func(root: Node3D): _matilda(root))
	if rect.has_point(CrownLayout.COUNCIL):
		out.append(func(root: Node3D): _council(root))
	if rect.has_point(CrownLayout.BELL_TOWER):
		out.append(func(root: Node3D): _bell_tower(root))
	if rect.has_point(Vector2(CrownLayout.WALL_X, 0.0)):
		out.append(func(root: Node3D): _wall(root))
	if rect.has_point(Vector2(-55.0, 0.0)):
		out.append(func(root: Node3D): _bridge(root))
	var lines := []
	for wl: Array in wash_lines():
		if rect.has_point(((wl[0] as Vector2) + (wl[1] as Vector2)) * 0.5):
			lines.append(wl)
	if not lines.is_empty():
		out.append(func(root: Node3D): _washing(root, lines, rect))
	var ks := []
	for kb: Array in kerbs():
		if rect.has_point(Vector2((kb[0] as Vector3).x, (kb[0] as Vector3).z)):
			ks.append(kb)
	if not ks.is_empty():
		out.append(func(root: Node3D): _kerb_mesh(root, ks, rect))
	return out


## 一块里的房子合成一个网格（组 house：按时段整块亮灯 / 灭灯）；房子底下一圈石头墙基（斜街是坡，靠下那头露出一截）
static func _house_block(root: Node3D, hs: Array, rect: Rect2, tag := 0) -> void:
	var node := Node3D.new()
	node.name = "CrownHouses_%d_%d_%d" % [int(rect.position.x), int(rect.position.y), tag]
	node.add_to_group("house")
	node.set_meta("seed", int(rect.position.x * 7 + rect.position.y * 13) + tag * 31)
	root.add_child(node)
	var kit := MeshKit.new()
	for h: Dictionary in hs:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(h.seed)
		_house(kit, h, rng, 0.45)
	var mi := kit.build(mats())
	mi.name = "Mesh"
	node.add_child(mi)
	var smoke := RandomNumberGenerator.new()
	smoke.seed = int(rect.position.x * 3 + rect.position.y) + tag
	for h: Dictionary in hs:
		if smoke.randf() < 0.18:                                         # 缺柴：冒烟的烟囱少
			var top := HarborTown.GH + int(h.floors) * HarborTown.FH + float(h.w) * 0.5 * tan(deg_to_rad(HarborTown.ROOF_PITCH)) * 0.6
			var cp := xf_of(h.front, float(h.yaw)) * Vector3(float(h.w) * 0.25, top + 1.4, -float(h.d) * 0.7)
			Atmos.smoke(node, cp)


static func _house(kit: MeshKit, h: Dictionary, rng: RandomNumberGenerator, lit: float) -> void:
	var xf := xf_of(h.front, float(h.yaw))
	var lo := INF
	for q: Vector2 in HarborTown.footprint(h):
		lo = minf(lo, ground(q))
	var drop := xf.origin.y - lo
	if drop > 0.05:
		kit.box("stone", xf * Vector3(0, -drop * 0.5 - 0.1, -float(h.d) * 0.5), Vector3(float(h.w) + 0.1, drop + 0.4, float(h.d) + 0.1), xf.basis, 0.6, 0.4)
	HarborTown._merchant(kit, xf, float(h.w), float(h.d), int(h.floors), bool(h.stone), rng, lit)


## 面包坊：斜街南边一栋两层，门口一块画着圆面包的木牌，烟囱一直冒烟（全斜街最暖的一栋）
static func _bakery(root: Node3D) -> void:
	var node := Node3D.new()
	node.name = "Bakery"
	node.add_to_group("house")
	node.set_meta("seed", 97)
	root.add_child(node)
	var sp := bakery()
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7607
	var h := {"front": sp.front, "yaw": sp.yaw, "w": sp.w, "d": sp.d, "floors": 1, "stone": false}
	_house(kit, h, rng, 0.9)
	var xf := xf_of(sp.front, float(sp.yaw))
	var at := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x, y, z)
	var sg: Vector3 = at.call(-1.8, 2.8, 0.6)                          # 招牌：铁杆上吊一块木板，板上一个圆面包
	kit.box("iron", sg + xf.basis * Vector3(0, 0.3, -0.3), Vector3(0.05, 0.05, 1.0), xf.basis)
	kit.box("timber", sg, Vector3(0.8, 0.55, 0.06), xf.basis * Basis(Vector3.UP, PI * 0.5), 1.0, 0.8)
	kit.cylinder("bread", sg + xf.basis * Vector3(0.04, 0, 0), sg + xf.basis * Vector3(0.07, 0, 0), 0.18, 0.18, 8)
	kit.box("stone", at.call(float(sp.w) * 0.3, HarborTown.GH + HarborTown.FH + 3.4, -float(sp.d) * 0.6), Vector3(0.9, 3.0, 0.9), xf.basis, 1.0, 0.6)    # 炉子的大烟囱
	var mi := kit.build(mats())
	mi.name = "Mesh"
	node.add_child(mi)
	Atmos.smoke(node, at.call(float(sp.w) * 0.3, HarborTown.GH + HarborTown.FH + 5.2, -float(sp.d) * 0.6))
	var dec := Decor.new()
	dec.sack(at.call(2.4, 0.0, 0.9), 0.4)
	dec.sack(at.call(2.9, 0.0, 1.0), 1.7)
	dec.woodpile(at.call(-3.0, 0.0, 0.7), xf.basis * Vector3.RIGHT, 1.2, 0.7)
	dec.build(node, "BakeryDecor")


## 玛蒂尔达新盘下的小酒馆：斜街北边一栋窄窄的三层，门口挂一盏灯、一块新刷的牌子（还是霜渡镇那条倒钩鱼）
static func _matilda(root: Node3D) -> void:
	var node := Node3D.new()
	node.name = "MatildaInn"
	node.add_to_group("house")
	node.set_meta("seed", 98)
	root.add_child(node)
	var sp := matilda()
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7608
	var h := {"front": sp.front, "yaw": sp.yaw, "w": sp.w, "d": sp.d, "floors": 2, "stone": false}
	_house(kit, h, rng, 0.85)
	var xf := xf_of(sp.front, float(sp.yaw))
	var at := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x, y, z)
	var sg: Vector3 = at.call(1.7, 2.8, 0.6)
	kit.box("iron", sg + xf.basis * Vector3(0, 0.3, -0.3), Vector3(0.05, 0.05, 1.0), xf.basis)
	kit.box("timber", sg, Vector3(0.9, 0.5, 0.06), xf.basis * Basis(Vector3.UP, PI * 0.5), 1.0, 0.8)
	kit.box("fish", sg + xf.basis * Vector3(0.04, 0.02, 0), Vector3(0.55, 0.12, 0.01), xf.basis * Basis(Vector3.UP, PI * 0.5))     # 一条鱼
	kit.box("iron", sg + xf.basis * Vector3(0.045, -0.06, 0.24), Vector3(0.012, 0.16, 0.03), xf.basis * Basis(Vector3.UP, PI * 0.5))   # 鱼嘴上的倒钩
	var mi := kit.build(mats())
	mi.name = "Mesh"
	node.add_child(mi)
	var dec := Decor.new()
	dec.sconce(at.call(-0.9, 2.2, 0.06), xf.basis * Vector3.BACK, true)
	dec.barrel(at.call(-2.4, 0.0, 0.8))
	dec.build(node, "MatildaDecor")


## 议事厅：广场北边一栋高高的石头大厅，正面朝南：五扇尖顶高窗、当中一道大拱门，门上五家的旗（王室那面旗杆空着），陡的石板瓦顶、屋脊当中一座小钟亭
static func _council(root: Node3D) -> void:
	var node := Node3D.new()
	node.name = "CouncilHall"
	node.add_to_group("house")
	node.set_meta("seed", 99)
	root.add_child(node)
	var kit := MeshKit.new()
	var xf := xf_of(council_front(), 0.0)
	var b := xf.basis
	var at := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x, y, z)
	var w := CrownLayout.COUNCIL_W
	var d := CrownLayout.COUNCIL_D
	var top := COUNCIL_H
	kit.box("castle", at.call(0, top * 0.5 - 0.5, -d * 0.5), Vector3(w, top + 1.0, d), b, 1.0, 0.8)
	kit.box("castle", at.call(0, 0.3, -d * 0.5), Vector3(w + 0.4, 0.6, d + 0.4), b, 0.7, 0.4)
	kit.box("castle", at.call(0, top - 0.1, 0.1), Vector3(w + 0.3, 0.3, 0.4), b, 0.85, 0.7)              # 檐口
	for i in 6:                                                          # 扶壁
		var x := -w * 0.5 + i * w / 5.0
		kit.box("castle", at.call(x, top * 0.4, 0.45), Vector3(0.9, top * 0.8, 0.9), b, 0.9, 0.5)
		kit.box("castle", at.call(x, top * 0.8 + 0.5, 0.25), Vector3(0.7, 1.4, 0.5), b * Basis(Vector3.RIGHT, -0.35), 0.9, 0.7)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7609
	for i in 5:                                                          # 五扇尖顶高窗（当中那扇在大门上面）
		var x := -w * 0.5 + (i + 0.5) * w / 5.0
		var y := 6.6 if i == 2 else 5.4
		var hh := 3.2 if i == 2 else 4.6
		HarborTown._window(kit, at.call(x, y, 0.06), b, rng.randf() < 0.5, 1.3, hh)
		for s: float in [-1.0, 1.0]:
			kit.box("castle", at.call(x + s * 0.36, y + hh * 0.5 + 0.35, 0.08), Vector3(0.9, 0.16, 0.12), b * Basis(Vector3.BACK, -s * 0.75), 0.9, 0.8)
	kit.box("dark", at.call(0, 1.8, 0.05), Vector3(2.4, 3.6, 0.06), b)                                       # 大拱门
	kit.box("castle", at.call(0, 3.9, 0.2), Vector3(3.6, 0.6, 0.4), b, 0.9, 0.8)
	for s: float in [-1.0, 1.0]:
		kit.box("castle", at.call(s * 1.55, 1.9, 0.18), Vector3(0.7, 3.8, 0.36), b, 0.9, 0.7)
	for k in 3:                                                          # 门前三级石阶（矮，走得上去）
		kit.box("castle", at.call(0, 0.05 + k * 0.05, 1.6 - k * 0.45), Vector3(6.0 - k * 0.8, 0.1 + k * 0.1, 0.5), b, 0.8, 0.6)
	# 屋顶：屋脊东西走向，两片陡坡、东西两个山墙三角
	var rise := 7.0
	for s: float in [-1.0, 1.0]:
		var ang := atan2(rise, d * 0.5 + 0.6)
		var sb := b * Basis(Vector3.RIGHT, s * ang)
		var slope := sqrt(pow(d * 0.5 + 0.6, 2) + rise * rise)
		var mid: Vector3 = at.call(0, top + rise * 0.5, -d * 0.5 + s * (d * 0.25 + 0.3))
		kit.box("roof", mid, Vector3(w + 1.0, 0.18, slope), sb, 1.0, 0.75)
		kit.box("snow", mid + (sb * Vector3.UP) * 0.11 + (sb * Vector3.BACK) * (-s) * slope * 0.22, Vector3(w + 0.8, 0.06, slope * 0.5), sb, 1.0, 1.0)
	for s: float in [-1.0, 1.0]:
		kit.tri("castle", at.call(s * w * 0.5, top, 0.0), at.call(s * w * 0.5, top, -d), at.call(s * w * 0.5, top + rise, -d * 0.5), (b * Vector3.RIGHT) * s, 0.9)
	var lan: Vector3 = at.call(0, top + rise, -d * 0.5)                  # 屋脊当中的小钟亭、尖顶
	kit.box("castle", lan + Vector3(0, 1.0, 0), Vector3(2.0, 2.0, 2.0), b, 0.9, 0.7)
	kit.box("dark", lan + Vector3(0, 1.2, 0), Vector3(2.04, 1.0, 0.8), b)
	kit.cylinder("roof", lan + Vector3(0, 2.0, 0), lan + Vector3(0, 5.0, 0), 1.5, 0.05, 4, 0.8)
	var mi := kit.build(mats())
	mi.name = "Mesh"
	node.add_child(mi)
	var dec := Decor.new()                                               # 门上五家的旗：塞弗林、洛蒙德、瓦伦、厄尔德、卡斯韦尔（王室那根旗杆空着）
	var flags := [[Color("7a2420"), Color("2a2a2e"), "anvil", Color("c8a040")], [Color("3c5a2c"), Color("d8b850"), "wheat", Color("b89a4a")],
		[Color("1e2228"), Color("cfcac0"), "heron", Color("8a8a8a")], [Color("4a3424"), Color("e08a3a"), "beacon", Color("8a6a3a")], [Color("26407a"), Color("d8c890"), "keys", Color("b89a4a")]]
	var xs := [-7.2, -2.4, 2.4, 7.2, 12.0]                               # 挂在扶壁上（不挡窗）：四家在当中，卡斯韦尔家在东头那根扶壁上；大门顶上王室那根旗杆空着
	for i in 5:
		var f: Array = flags[i]
		dec.banner(at.call(float(xs[i]), top - 1.2, 0.95), b * Vector3.BACK, 1.3, 3.0, f[0], f[1], str(f[2]), f[3])
	for s: float in [-1.0, 1.0]:
		dec.sconce(at.call(s * 2.2, 2.8, 0.12), b * Vector3.BACK, true)
	dec.build(node, "CouncilDecor")
	var pole := MeshKit.new()                                            # 王室的旗杆：空着
	pole.cylinder("iron", at.call(0, top + 0.2, 0.3), at.call(0, top + 4.2, 0.3), 0.06, 0.05, 6)
	var pm := pole.build(mats())
	pm.name = "EmptyPole"
	node.add_child(pm)


## 钟楼：广场东北角一座方石塔，顶上一层开着拱洞的钟室、四坡尖顶；钟室里一口铁钟（黄昏敲一回，第四章章末停在这口钟里）
static func _bell_tower(root: Node3D) -> void:
	var node := Node3D.new()
	node.name = "BellTower"
	root.add_child(node)
	var bt := CrownLayout.BELL_TOWER
	var base := Vector3(bt.x, ground(bt) - 0.3, bt.y)
	var kit := MeshKit.new()
	var w := BELL_W
	kit.box("castle", base + Vector3(0, BELL_H * 0.5, 0), Vector3(w, BELL_H, w), Basis.IDENTITY, 1.0, 0.8)
	kit.box("castle", base + Vector3(0, 0.4, 0), Vector3(w + 0.5, 0.8, w + 0.5), Basis.IDENTITY, 0.7, 0.4)
	for y: float in [7.0, 14.0, BELL_H]:                                # 每一截一道石檐
		kit.box("castle", base + Vector3(0, y, 0), Vector3(w + 0.4, 0.3, w + 0.4), Basis.IDENTITY, 0.85, 0.7)
	for k in 4:                                                          # 塔身上的窄窗
		var a := k * PI * 0.5
		var n := Vector3(sin(a), 0, cos(a))
		for y: float in [9.5, 16.5]:
			kit.box("dark", base + Vector3(0, y, 0) + n * (w * 0.5 + 0.02), Vector3(0.4, 1.4, 0.05), Basis(Vector3.UP, a))
	var bh := 4.4                                                        # 钟室：四角四根石柱、顶上一圈
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			kit.box("castle", base + Vector3(sx * (w * 0.5 - 0.5), BELL_H + bh * 0.5, sz * (w * 0.5 - 0.5)), Vector3(1.0, bh, 1.0), Basis.IDENTITY, 0.9, 0.7)
	kit.box("castle", base + Vector3(0, BELL_H + bh + 0.3, 0), Vector3(w + 0.3, 0.6, w + 0.3), Basis.IDENTITY, 0.85, 0.7)
	kit.box("castle", base + Vector3(0, BELL_H + 0.2, 0), Vector3(w, 0.4, w), Basis.IDENTITY, 0.8, 0.6)
	kit.cylinder("iron", base + Vector3(0, BELL_H + bh - 0.4, 0), base + Vector3(0, BELL_H + 1.4, 0), 0.25, 0.95, 10, 0.8)   # 钟
	kit.box("timber", base + Vector3(0, BELL_H + bh - 0.3, 0), Vector3(w - 1.0, 0.3, 0.3), Basis.IDENTITY, 0.8, 0.6)
	kit.cylinder("roof", base + Vector3(0, BELL_H + bh + 0.6, 0), base + Vector3(0, BELL_H + bh + 7.0, 0), w * 0.78, 0.05, 4, 0.8)   # 四坡尖顶
	kit.box("dark", base + Vector3(-w * 0.5 - 0.02, 1.45, 0), Vector3(0.05, 2.3, 1.2), Basis.IDENTITY)               # 西面的门洞（门板是同步放的 Door）
	var mi := kit.build(mats())
	mi.name = "BellTowerMesh"
	node.add_child(mi)


## 城墙和桥门：灰方石的高墙从河里直接砌上来，墙顶一排垛口；桥门两边两座方塔，门洞上一道拱、一道放下一半的铁闸
static func _wall(root: Node3D) -> void:
	var node := Node3D.new()
	node.name = "CityWall"
	root.add_child(node)
	var kit := MeshKit.new()
	var top := CrownLayout.ISLAND_Y + CrownLayout.WALL_TOP
	var foot := CrownLayout.RIVER_BED
	for run: Array in wall_runs():
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		var mid := (a + b) * 0.5
		var dv := b - a
		var bas := Basis(Vector3.UP, -atan2(dv.y, dv.x))
		var len := dv.length() + 0.6
		kit.box("castle", Vector3(mid.x, (foot + top) * 0.5, mid.y), Vector3(len, top - foot, CrownLayout.WALL_T), bas, 1.0, 0.75)
		var n := int(len / 1.6)
		for k in n:                                                      # 垛口
			if k % 2 == 1:
				continue
			var t := -len * 0.5 + (k + 0.5) * len / n
			kit.box("castle", Vector3(mid.x, top + 0.55, mid.y) + bas * Vector3(t, 0, 0), Vector3(len / n, 1.1, CrownLayout.WALL_T * 0.9), bas, 0.9, 0.8)
		kit.box("snow", Vector3(mid.x, top + 0.04, mid.y), Vector3(len, 0.08, CrownLayout.WALL_T * 0.7), bas)
	var g := CrownLayout.GATE_HALF
	var wx := CrownLayout.WALL_X
	for s: float in [-1.0, 1.0]:                                         # 两座塔
		var tc := Vector3(wx, 0, s * (g + TOWER_W * 0.5))
		var ty := CrownLayout.ISLAND_Y + TOWER_H
		kit.box("castle", Vector3(tc.x, (foot + ty) * 0.5, tc.z), Vector3(TOWER_W, ty - foot, TOWER_W), Basis.IDENTITY, 1.0, 0.75)
		kit.box("castle", Vector3(tc.x, ty - 0.2, tc.z), Vector3(TOWER_W + 0.5, 0.4, TOWER_W + 0.5), Basis.IDENTITY, 0.85, 0.7)
		for k in 4:
			var a := k * PI * 0.5
			for m in 3:
				var off := (m - 1) * TOWER_W * 0.33
				var p := Vector3(tc.x, ty + 0.55, tc.z) + Vector3(cos(a), 0, sin(a)) * (TOWER_W * 0.5) + Vector3(-sin(a), 0, cos(a)) * off
				kit.box("castle", p, Vector3(0.9, 1.1, 0.9), Basis(Vector3.UP, a), 0.9, 0.8)
			for y: float in [CrownLayout.ISLAND_Y + 5.5, CrownLayout.ISLAND_Y + 10.0]:
				kit.box("dark", Vector3(tc.x, y, tc.z) + Vector3(cos(a), 0, sin(a)) * (TOWER_W * 0.5 + 0.02), Vector3(0.35, 1.2, 0.05), Basis(Vector3.UP, -a + PI * 0.5))
		kit.box("snow", Vector3(tc.x, ty + 0.03, tc.z), Vector3(TOWER_W - 0.4, 0.06, TOWER_W - 0.4))
	var gy := CrownLayout.ISLAND_Y                                       # 门洞上面那一截墙、拱、铁闸
	kit.box("castle", Vector3(wx, (gy + 5.4 + top) * 0.5, 0), Vector3(CrownLayout.WALL_T + 0.6, top - gy - 5.4, g * 2.0 + 0.2), Basis.IDENTITY, 0.9, 0.6)
	kit.box("castle", Vector3(wx, gy + 5.2, 0), Vector3(CrownLayout.WALL_T + 0.8, 0.5, g * 2.0 + 0.6), Basis.IDENTITY, 0.85, 0.8)
	for k in 9:
		kit.box("iron", Vector3(wx - 0.4, gy + 4.4, -g + 0.25 + k * (g * 2.0 - 0.5) / 8.0), Vector3(0.08, 1.6, 0.08))
	kit.box("iron", Vector3(wx - 0.4, gy + 3.65, 0), Vector3(0.1, 0.1, g * 2.0))
	kit.box("castle", Vector3(wx, (foot + gy - 0.2) * 0.5, 0), Vector3(CrownLayout.WALL_T + 0.4, gy - 0.2 - foot, g * 2.0), Basis.IDENTITY, 0.6, 0.35)   # 门洞底下（桥头）
	var mi := kit.build(mats())
	mi.name = "WallMesh"
	node.add_child(mi)
	var dec := Decor.new()
	for s: float in [-1.0, 1.0]:
		dec.sconce(Vector3(wx - CrownLayout.WALL_T * 0.5 - 0.05, gy + 3.0, s * (g + 0.5)), Vector3(-1, 0, 0), s > 0.0)
	dec.build(node, "GateDecor")


## 石桥：五个桥墩从河底起来，桥面跟着拱一点，两边齐腰的石栏
static func _bridge(root: Node3D) -> void:
	var node := Node3D.new()
	node.name = "StoneBridge"
	root.add_child(node)
	var kit := MeshKit.new()
	var hw := CrownLayout.BRIDGE_HALF
	for sp: Array in bridge_spans():
		var x0 := float(sp[0])
		var x1 := float(sp[1])
		var y0 := CrownCity.bridge_y(x0)
		var y1 := CrownCity.bridge_y(x1)
		var bas := Basis(Vector3.BACK, atan2(y1 - y0, x1 - x0))
		var c := Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0.0)
		kit.box("stone", c + Vector3(0, -0.35, 0), Vector3(x1 - x0 + 0.12, 0.7, hw * 2.0), bas, 0.9, 0.6)
		kit.box("castle", c + Vector3(0, -1.0, 0), Vector3(x1 - x0 + 0.12, 0.7, hw * 2.0 + 0.3), bas, 0.6, 0.4)
		for s: float in [-1.0, 1.0]:
			kit.box("castle", c + Vector3(0, PARAPET_H * 0.5, s * (hw + 0.15)), Vector3(x1 - x0 + 0.12, PARAPET_H, 0.3), bas, 0.9, 0.7)
			kit.box("snow", c + Vector3(0, PARAPET_H + 0.03, s * (hw + 0.15)), Vector3(x1 - x0 + 0.1, 0.05, 0.26), bas)
	for px: float in BRIDGE_PIERS:                                       # 桥墩：上游那头一个尖的分水
		var y := CrownCity.bridge_y(px) - 1.3
		var foot := CrownLayout.RIVER_BED - 0.5
		kit.box("castle", Vector3(px, (foot + y) * 0.5, 0), Vector3(2.4, y - foot, hw * 2.0 + 0.6), Basis.IDENTITY, 0.7, 0.3)
		kit.box("castle", Vector3(px, (foot + y) * 0.5 - 0.3, -hw - 0.9), Vector3(1.7, y - foot - 0.6, 1.7), Basis(Vector3.UP, PI * 0.25), 0.7, 0.3)
		kit.box("castle", Vector3(px, (foot + y) * 0.5 - 0.3, hw + 0.9), Vector3(1.7, y - foot - 0.6, 1.7), Basis(Vector3.UP, PI * 0.25), 0.7, 0.3)
	var ja: Vector2 = JETTY[0]                                           # 行会的小码头、靠着的一条船
	var jb: Vector2 = JETTY[1]
	var jy := ground(ja) + 0.08
	var jm := (ja + jb) * 0.5
	var jl := ja.distance_to(jb)
	kit.box("timber", Vector3(jm.x, jy - 0.08, jm.y), Vector3(jl, 0.16, JETTY_W), Basis.IDENTITY, 0.8, 0.6)
	var x := ja.x + 1.0
	while x < jb.x:
		for s: float in [-1.0, 1.0]:
			kit.cylinder("timber", Vector3(x, CrownLayout.RIVER_BED, jm.y + s * (JETTY_W * 0.5 - 0.1)), Vector3(x, jy + 0.9, jm.y + s * (JETTY_W * 0.5 - 0.1)), 0.13, 0.12, 6)
		x += 2.2
	for s: float in [-1.0, 1.0]:
		kit.box("timber", Vector3(jm.x + 2.0, jy + 0.85, jm.y + s * (JETTY_W * 0.5 - 0.1)), Vector3(jl - 4.0, 0.1, 0.1), Basis.IDENTITY, 0.8, 0.6)
	HarborTown._hull(kit, Vector3(jm.x + 1.0, CrownLayout.RIVER_Y - 0.25, jm.y + JETTY_W * 0.5 + 2.2), Basis(Vector3.UP, PI * 0.5), 12.0)
	var mi := kit.build(mats())
	mi.name = "BridgeMesh"
	node.add_child(mi)
	var dec := Decor.new()
	for k in 3:
		dec.crate(Vector3(ja.x - 1.5 - k * 0.8, ground(Vector2(ja.x - 1.5 - k * 0.8, ja.y + 1.2)), ja.y + 1.2), k * 0.6)
	dec.barrel(Vector3(ja.x - 2.0, ground(Vector2(ja.x - 2.0, ja.y - 1.0)), ja.y - 1.0))
	dec.build(node, "JettyDecor")


## 晾衣绳：一根绳子微微往下垂，上面挂着几件洗过的衣服、床单（不受风，冬天冻硬了）
static func _washing(root: Node3D, lines: Array, rect: Rect2) -> void:
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(rect.position.x * 11 + rect.position.y * 5) + 76
	for wl: Array in lines:
		var a: Vector2 = wl[0]
		var b: Vector2 = wl[1]
		var y := float(wl[2])
		var mid := Vector3((a.x + b.x) * 0.5, y - 0.35, (a.y + b.y) * 0.5)
		var pa := Vector3(a.x, y, a.y)
		var pb := Vector3(b.x, y, b.y)
		kit.cylinder("rope", pa, mid, 0.02, 0.02, 3)
		kit.cylinder("rope", mid, pb, 0.02, 0.02, 3)
		var dir := (b - a).normalized()
		var bas := Basis(Vector3.UP, -atan2(dir.y, dir.x))
		var n := rng.randi_range(2, 4)
		for k in n:
			var t := (k + 0.5) / n + rng.randf_range(-0.08, 0.08)
			var sag := 0.35 * (1.0 - absf(t - 0.5) * 2.0)
			var p := pa.lerp(pb, t) - Vector3(0, sag, 0)
			var cw := rng.randf_range(0.5, 1.3)
			var ch := rng.randf_range(0.5, 1.2)
			kit.box("wash%d" % rng.randi_range(0, WASH_COLORS.size() - 1), p - Vector3(0, ch * 0.5, 0), Vector3(cw, ch, 0.03), bas * Basis(Vector3.UP, rng.randf_range(-0.08, 0.08)), 1.0, 0.8)
	var mi := kit.build(mats())
	mi.name = "Washing_%d_%d" % [int(rect.position.x), int(rect.position.y)]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


static func _kerb_mesh(root: Node3D, ks: Array, rect: Rect2) -> void:
	var kit := MeshKit.new()
	for k: Array in ks:
		var a: Vector3 = k[0]
		var b: Vector3 = k[1]
		var mid := (a + b) * 0.5
		var d := b - a
		var bas := Basis(Vector3.UP, -atan2(d.z, d.x))
		kit.box("stone", mid + Vector3(0, KERB_H * 0.5 - 0.1, 0), Vector3(Vector2(d.x, d.z).length() + 0.05, KERB_H + 0.2, 0.45), bas, 0.8, 0.6)
		kit.box("snow", mid + Vector3(0, KERB_H + 0.12, 0), Vector3(Vector2(d.x, d.z).length(), 0.05, 0.36), bas)
	var mi := kit.build(mats())
	mi.name = "Kerbs_%d_%d" % [int(rect.position.x), int(rect.position.y)]
	root.add_child(mi)


# ---------------- 地图外面的影子 ----------------

## 岛东头越来越高的城、高墙后面的王宫（地图外，只画个影子：一个网格、不投影；雾里只看得见轮廓）
static func palace(parent: Node3D) -> void:
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7610
	for k in 70:                                                         # 城：一层压一层的屋顶
		var p := Vector2(rng.randf_range(96.0, 220.0), rng.randf_range(-48.0, 48.0))
		var y := CrownCity.far_height(p.x, p.y)
		var w := rng.randf_range(6.0, 11.0)
		var d := rng.randf_range(6.0, 10.0)
		var hh := rng.randf_range(6.0, 11.0)
		var bas := Basis(Vector3.UP, rng.randf_range(-0.2, 0.2) + (PI * 0.5 if rng.randf() < 0.5 else 0.0))
		kit.box("plaster", Vector3(p.x, y + hh * 0.5 - 1.0, p.y), Vector3(w, hh + 2.0, d), bas, 1.0, 0.6)
		var rise := w * 0.5 * 1.1
		for s: float in [-1.0, 1.0]:
			var sb := bas * Basis(Vector3.BACK, -s * atan2(rise, w * 0.5))
			kit.box("roof", Vector3(p.x, y + hh + rise * 0.5, p.y) + bas * Vector3(s * w * 0.25, 0, 0), Vector3(sqrt(w * w * 0.25 + rise * rise) + 0.3, 0.2, d + 0.4), sb, 1.0, 0.75)
	var pc := Vector2(250.0, -30.0)                                      # 王宫：一道高墙、四角圆塔、当中一座方的主楼
	var py := CrownCity.far_height(pc.x, pc.y)
	var r := 34.0
	for k in 4:
		var a := k * PI * 0.5
		var c := pc + Vector2(cos(a), sin(a)) * r
		kit.box("castle", Vector3(c.x, py + 7.0, c.y), Vector3(r * 2.0 if k % 2 == 1 else 3.0, 16.0, 3.0 if k % 2 == 1 else r * 2.0), Basis.IDENTITY, 1.0, 0.5)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var tc := Vector3(pc.x + sx * r, py - 1.0, pc.y + sz * r)
			kit.cylinder("castle", tc, tc + Vector3(0, 24.0, 0), 5.0, 4.4, 10, 0.9)
			kit.cylinder("roof", tc + Vector3(0, 24.0, 0), tc + Vector3(0, 32.0, 0), 5.4, 0.1, 10, 0.8)
	kit.box("castle", Vector3(pc.x, py + 16.0, pc.y), Vector3(26.0, 34.0, 22.0), Basis.IDENTITY, 1.0, 0.5)
	for s: float in [-1.0, 1.0]:
		kit.box("roof", Vector3(pc.x, py + 37.0, pc.y + s * 5.8), Vector3(27.0, 0.4, 13.6), Basis(Vector3.RIGHT, s * 0.75), 1.0, 0.75)
	var keep := Vector3(pc.x + 8.0, py + 33.0, pc.y - 4.0)
	kit.box("castle", keep + Vector3(0, 8.0, 0), Vector3(8.0, 16.0, 8.0), Basis.IDENTITY, 1.0, 0.6)
	kit.cylinder("roof", keep + Vector3(0, 16.0, 0), keep + Vector3(0, 26.0, 0), 6.0, 0.1, 4, 0.8)
	var mi := kit.build(mats())
	mi.name = "FarCity"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 50.0
	parent.add_child(mi)


## 地图册「本地」页上的房子
static func map_shapes() -> Array:
	var out := []
	for h: Dictionary in houses():
		out.append({"k": "house", "pts": HarborTown.footprint(h)})
	var bk := bakery()
	out.append({"k": "house", "pts": House.footprint(Vector3(bk.front.x, 0, bk.front.y), float(bk.yaw), float(bk.w), float(bk.d)), "label": "面包坊"})
	var m := matilda()
	out.append({"k": "house", "pts": House.footprint(Vector3(m.front.x, 0, m.front.y), float(m.yaw), float(m.w), float(m.d)), "label": "玛蒂尔达的小酒馆"})
	var cf := council_front()
	out.append({"k": "house", "pts": House.footprint(Vector3(cf.x, 0, cf.y), 0.0, CrownLayout.COUNCIL_W, CrownLayout.COUNCIL_D), "label": "议事厅"})
	var bt := CrownLayout.BELL_TOWER
	out.append({"k": "house", "pts": CrownCity._rect(Rect2(bt - Vector2(BELL_W, BELL_W) * 0.5, Vector2(BELL_W, BELL_W))), "label": "钟楼"})
	for run: Array in wall_runs():
		out.append({"k": "house", "pts": CrownCity._strip(run[0], run[1], CrownLayout.WALL_T * 0.5)})
	for s: float in [-1.0, 1.0]:
		var tc := Vector2(CrownLayout.WALL_X, s * (CrownLayout.GATE_HALF + TOWER_W * 0.5))
		out.append({"k": "house", "pts": CrownCity._rect(Rect2(tc - Vector2(TOWER_W, TOWER_W) * 0.5, Vector2(TOWER_W, TOWER_W))), "label": "桥门" if s > 0.0 else ""})
	out.append({"k": "road", "pts": CrownCity._strip(JETTY[0], JETTY[1], JETTY_W * 0.5)})
	return out
