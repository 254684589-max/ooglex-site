class_name HarborTown
extends RefCounted
## 双钥港的城（路线图 7.2，D12；STORY.md 7.2「钥楼街是一排石砌的商行和钱庄，最高的一栋是卡斯韦尔家的钥楼……木栈码头、盐仓、晒鱼架、渡工行会的港口会馆；
## 沙嘴尽头一座灯塔（这个冬天时亮时灭）；城边的债牢」）。先回答「这里住着谁、缺什么、刚发生过什么」（ART.md 第十节）：
##   住着谁：商行和钱庄的人（钥楼街的石头房子，窗子多、亮）、渡工和渔夫（码头、鱼市边上灰泥木构的窄房子）、欠了债的人（西北角的债牢）；
##   缺什么：灯油（灯塔三个月没付油钱，塔顶的火盆只剩一点暗红）、粮（码头上的粮船少，盐仓边上空着一排车）；
##   刚发生过什么：昨夜一条运粮的船在沙嘴外搁浅了，歪在泥滩上；钥楼街贴出了清账的告示——冬至那天，冠城要清账。
## 房子：沿着街两边按规则自动摆（houses()，种子固定）：每 10 米左右一栋，山墙朝街，三层、底层石砌；钥楼街上的是全石砌的（商行），别处上层灰泥木构；
## 同一块里的所有房子合成一个网格（几种材质 = 几次绘制，平原上一栋一个网格时绘制数顶到预算，6.7a），这一块整体按时段亮灯（组 house）。
## 碰撞、门、路牌、告示同步建（一进场就挡得住、看得见）；画面按所在的块分帧搭（jobs_for）。

const GH := 3.0                 # 底层高
const FH := 2.7                 # 上层每层高
const JET := 0.3                # 上层往街挑出
const ROOF_PITCH := 52.0
const EAVE := 0.4
const KEY_W := 16.0             # 钥楼：正面宽、进深（背墙直接立在北潮沟边上）、几层
const KEY_D := 8.0
const KEY_FLOORS := 3
const KEY_GH := 4.0
const KEY_FH := 3.1
const GUILD_W := 15.0
const GUILD_D := 10.0
const PRISON_W := 12.0
const PRISON_D := 10.0
const LIGHT_H := 15.0           # 灯塔高
const LIGHT_R := 3.0
const PIER_W := 3.0
const PIER_OUT := 9.0           # 栈桥伸进河里多远
const PIER_ZS := [-80.0, -62.0, -28.0, -2.0, 26.0]      # 避开两条潮沟的口（-42、12 前后四米）
const BRIDGE_W := 3.6
const KERB_H := 0.45
const KERB_BLOCK := 1.05        # 栏石的碰撞高（比看得见的高：别从码头边、潮沟边一脚跨下去，掉进深水出不来）
const SIGN_QUAY := Vector2(14.0, -15.0)
const SIGN_QUAY_TEXT := "往钥楼街 · 鱼市 · 冠城"
const SIGN_KEY := Vector2(-22.0, -63.6)
const SIGN_KEY_TEXT := "往码头 · 鱼市"
const NOTICE := Vector2(-44.0, -59.2)
const NOTICE_TEXT := "钥楼门口的告示板上钉着一张新的告示，墨还没干透：「冬至日，冠城摄政会议清账。凡持王室担保之借据者，冬至以前到钥楼登记，逾期不录。——卡斯韦尔家」底下有人用炭写了一行小字：「老王欠的，凭什么我们还。」"
const LIGHT_DOOR_TEXT := "灯塔的门从外面挂着锁。门边码着几个空油桶，桶底结着一层冰。"
const HOUSE_TEXTS := ["门闩着。屋里有人在数钱，听见敲门声停了。", "门上贴着一张欠条，被雨泡烂了一半。", "门推不开。里面一股咸鱼味。", "门从里面顶着。有个女人隔着门说：「船钱月底给。」"]
const SHIPS := [[Vector2(46.0, 58.0), 172.0, 18.0], [Vector2(52.0, 86.0), 150.0, 15.0]]   # 停在河口深水里的两条单桅船：位置、船头朝向、长
const WRECK := [Vector2(96.0, 80.0), 62.0, 14.0]                                        # 搁浅在沙嘴东边泥滩上的运粮船
const RACKS := [Vector2(-56.0, 31.0), Vector2(-50.0, 31.0), Vector2(-44.0, 31.0), Vector2(-26.0, 31.0), Vector2(-20.0, 31.0)]   # 晒鱼架（鱼市北边一排）
const SHEDS := [[Vector2(-96.0, 42.0), 0.0], [Vector2(-80.0, 42.5), 0.0], [Vector2(-66.0, 41.0), 0.0]]   # 盐仓：正面朝南、对着石岸（卸盐的船在泥滩外）
const TAVERN_FRONT := Vector2(9.5, -8.0)    # 「咸潮」酒馆（7.3）：码头街西边，正面朝东对着河
const TAVERN_W := 9.0
const TAVERN_D := 8.0
const SHED_W := 12.0
const SHED_D := 6.0

static var _houses: Array = []
static var _kerbs: Array = []
static var _bridges: Array = []
static var _mats := {}


static func clear_cache() -> void:
	_houses.clear()
	_kerbs.clear()
	_bridges.clear()
	_mats.clear()


static func ground(p: Vector2) -> float:
	return Harbor.height_at(p.x, p.y)


static func xf_of(front: Vector2, yaw: float, y := NAN) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), Vector3(front.x, ground(front) if is_nan(y) else y, front.y))


# ---------------- 材质 ----------------

static func _m(key: String, c: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		m.vertex_color_use_as_albedo = true
		_mats[key] = m
	return _mats[key]


static func mats() -> Dictionary:
	return {"stone": Look.mat("stone"), "castle": Look.mat("castle"), "plaster": Look.mat("plaster"), "timber": Look.mat("timber"), "roof": Look.mat("roof"),
		"snow": Look.mat("snow"), "glass_lit": Look.glass_lit(), "glass_dark": Look.glass_dark(), "halo": Look.halo(Look.WINDOW_COLOR, 0.32),
		"dark": _m("dark", Color(0.05, 0.045, 0.04), 1.0), "iron": _m("iron", Color("2c2c30"), 0.5, 0.5), "salt": _m("salt", Color("d9d6cf"), 0.95),
		"fish": _m("fish", Color("4a4036"), 0.7), "tar": _m("tar", Color("1e1a16"), 0.8), "sail": _m("sail", Color("8c8270"), 0.95),
		"ember": _ember(), "rope": _m("rope", Color("6e5e44"), 1.0)}


static func _ember() -> StandardMaterial3D:
	if not _mats.has("ember"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("6a2a12")
		m.emission_enabled = true
		m.emission = Color("ff6a2a")
		m.emission_energy_multiplier = 1.2
		_mats["ember"] = m
	return _mats["ember"]


# ---------------- 房子摆在哪 ----------------

## 沿街自动摆的房子：[{front: 正面墙脚中点, yaw, w, d, floors, stone, seed, street}]（种子固定，每次一样）
static func houses() -> Array:
	if not _houses.is_empty():
		return _houses
	var rng := RandomNumberGenerator.new()
	rng.seed = 7202
	var out := []
	for si in HarborLayout.STREETS.size():
		var pts: Array = HarborLayout.STREETS[si]
		for k in pts.size() - 1:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[k + 1]
			var len := a.distance_to(b)
			var dir := (b - a) / len
			var nrm := Vector2(-dir.y, dir.x)
			var t := 5.0
			while t < len - 4.0:
				var w := rng.randf_range(6.5, 9.0)
				for side: float in [-1.0, 1.0]:
					var d := rng.randf_range(7.0, 9.5)
					var p := a + dir * (t + w * 0.5)
					var front := p + nrm * side * (HarborLayout.STREET_HALF + 1.1)
					var face := -nrm * side                                  # 正面朝街
					var yaw := rad_to_deg(atan2(face.x, face.y))
					var h := {"front": front, "yaw": yaw, "w": w, "d": d, "floors": 2 + int(rng.randf() < 0.55), "stone": si == 1,
						"seed": rng.randi_range(1, 99999), "street": si}
					if _fits(h, out):
						out.append(h)
					elif _fits(_shrink(h, 6.0), out):
						out.append(_shrink(h, 6.0))
					var back := h.duplicate()                                  # 后排：隔一条 1.6 米的窄巷，背对背再一栋（城里挤，天际线上一层压一层）
					back.front = front - face * (d + 1.6 + 7.0)
					back.yaw = yaw + 180.0
					back.d = 7.0
					back.floors = 2 + int(rng.randf() < 0.4)
					back.seed = rng.randi_range(1, 99999)
					back.back = true
					if _fits(back, out):
						out.append(back)
				t += w + rng.randf_range(0.6, 2.0)
	_houses = out
	return out


static func _shrink(h: Dictionary, d: float) -> Dictionary:
	var o := h.duplicate()
	o.d = d
	o.w = minf(float(h.w), 7.0)
	return o


static func footprint(h: Dictionary) -> PackedVector2Array:
	return House.footprint(Vector3(h.front.x, 0, h.front.y), float(h.yaw), float(h.w) + JET, float(h.d) + JET)


## 这栋房子放得下：四个角和中间都在城的台地上，离潮沟、河边、南边石岸、街、空地、别的房子都有空
static func _fits(h: Dictionary, others: Array) -> bool:
	var fp := footprint(h)
	var c := House.local_xz(Vector3(h.front.x, 0, h.front.y), float(h.yaw), Vector2(0, -float(h.d) * 0.5))
	var probes := Array(fp) + [c]
	for k in 4:
		probes.append((fp[k] + fp[(k + 1) % 4]) * 0.5)
	for q: Vector2 in probes:
		if not HarborLayout.west_bank(q) or ground(q) < 1.2:
			return false
		if HarborLayout.canal_d(q) < HarborLayout.CANAL_HALF + HarborLayout.CANAL_BANK + 1.4:
			return false
		if HarborLayout.river_edge(q) < HarborLayout.RIVER_BANK + 4.5:
			return false
		if q.y > HarborLayout.quay_z(q.x) - HarborLayout.QUAY_DROP - 2.5:
			return false
		if HarborLayout.street_d(q) < HarborLayout.STREET_HALF + 0.5:
			return false
		if not HarborLayout.BOUNDS.grow(-8.0).has_point(q):
			return false
	var r := maxf(float(h.w), float(h.d)) * 0.5
	for keep: Array in [[TAVERN_FRONT + Vector2(-TAVERN_D * 0.5, 0), 6.5], [HarborLayout.KEY_HOUSE, 12.0], [HarborLayout.GUILD, 10.5], [HarborLayout.PRISON, 11.0], [HarborLayout.FISH, 14.0], [NOTICE, 3.0], [SIGN_KEY, 2.5], [SIGN_QUAY, 2.5]]:
		if c.distance_to(keep[0]) < float(keep[1]) + r * 0.7:
			return false
	for sh: Array in SHEDS:
		if c.distance_to(sh[0]) < 8.0 + r:
			return false
	for id in HarborLayout.SPAWN_XZ:
		if c.distance_to(HarborLayout.SPAWN_XZ[id][0]) < r + 2.5:
			return false
	for v: Array in HarborLayout.VIEW_SPEC:
		if c.distance_to(Vector2((v[0] as Vector3).x, (v[0] as Vector3).z)) < r + 2.0:
			return false
	for o: Dictionary in others:
		var oc := House.local_xz(Vector3(o.front.x, 0, o.front.y), float(o.yaw), Vector2(0, -float(o.d) * 0.5))
		if c.distance_to(oc) < (r + maxf(float(o.w), float(o.d)) * 0.5) * 0.92:
			return false
	return true


static func house_center(h: Dictionary) -> Vector2:
	return House.local_xz(Vector3(h.front.x, 0, h.front.y), float(h.yaw), Vector2(0, -float(h.d) * 0.5))


static func key_front() -> Vector2:
	var cz := HarborLayout.canal_z_at(HarborLayout.KEY_HOUSE.x, 0) - HarborLayout.CANAL_HALF - HarborLayout.CANAL_BANK
	return Vector2(HarborLayout.KEY_HOUSE.x, cz - KEY_D)


static func guild_front() -> Vector2:
	return HarborLayout.GUILD + Vector2(0, GUILD_D * 0.5)


const PRISON_YAW := 12.0         # 正面朝东北一点：对着往城里去的那条街


static func prison_front() -> Vector2:
	return HarborLayout.PRISON + Vector2(PRISON_D * 0.5 * sin(deg_to_rad(PRISON_YAW)), PRISON_D * 0.5 * cos(deg_to_rad(PRISON_YAW)))


## 西岸河边（石岸上沿）的 x
static func river_edge_x(z: float) -> float:
	return HarborLayout.river_x(z) - HarborLayout.river_half(z)


## 栈桥：[岸上那头, 水里那头]（往东伸进河里）
static func piers() -> Array:
	var out := []
	for z: float in PIER_ZS:
		var xe := river_edge_x(z)
		out.append([Vector2(xe - 4.0, z), Vector2(xe + PIER_OUT, z)])
	return out


static func pier_y(p: Array) -> float:
	return ground(p[0]) + 0.08


## 街跨潮沟的地方（桥）：[中心, 沿街方向]
static func bridges() -> Array:
	if not _bridges.is_empty():
		return _bridges
	var out := []
	for st: Array in HarborLayout.STREETS:
		for k in st.size() - 1:
			for cn: Array in HarborLayout.CANALS:
				for j in cn.size() - 1:
					var hit: Variant = Geometry2D.segment_intersects_segment(st[k], st[k + 1], cn[j], cn[j + 1])
					if hit != null:
						out.append([hit as Vector2, ((st[k + 1] as Vector2) - (st[k] as Vector2)).normalized()])
	_bridges = out
	return out


## 潮沟口的木闸：潮沟碰到河边石岸的地方
static func sluices() -> Array:
	var out := []
	for cn: Array in HarborLayout.CANALS:
		var e: Vector2 = cn[cn.size() - 1]
		var a: Vector2 = cn[cn.size() - 2]
		var dir := (e - a).normalized()
		var x := river_edge_x(e.y) - 1.0
		var t := (x - a.x) / dir.x
		out.append([a + dir * t, dir])
	return out


# ---------------- 碰撞 ----------------

## 所有挡人的东西：[[变换, 尺寸], ...]（栈桥、桥面、石阶是能站上去的）
static func solids() -> Array:
	var out := []
	for h: Dictionary in houses():
		var xf := xf_of(h.front, float(h.yaw))
		out.append([xf * Transform3D(Basis.IDENTITY, Vector3(0, 3.0, -float(h.d) * 0.5)), Vector3(float(h.w) + 0.2, 6.0, float(h.d) + 0.2)])
	var kx := xf_of(key_front(), 180.0)
	out.append([kx * Transform3D(Basis.IDENTITY, Vector3(0, 5.0, -KEY_D * 0.5)), Vector3(KEY_W + 0.2, 10.0, KEY_D + 0.2)])
	var gx := xf_of(guild_front(), 0.0)
	out.append([gx * Transform3D(Basis.IDENTITY, Vector3(0, 4.0, -GUILD_D * 0.5)), Vector3(GUILD_W + 0.2, 8.0, GUILD_D + 0.2)])
	var tx := xf_of(TAVERN_FRONT, 90.0)
	out.append([tx * Transform3D(Basis.IDENTITY, Vector3(0, 3.0, -TAVERN_D * 0.5)), Vector3(TAVERN_W + 0.2, 6.0, TAVERN_D + 0.2)])
	var px := xf_of(prison_front(), PRISON_YAW)
	out.append([px * Transform3D(Basis.IDENTITY, Vector3(0, 4.0, -PRISON_D * 0.5)), Vector3(PRISON_W + 0.2, 8.0, PRISON_D + 0.2)])
	var lp := HarborLayout.LIGHTHOUSE
	out.append([Transform3D(Basis.IDENTITY, Vector3(lp.x, ground(lp) + 4.0, lp.y)), Vector3(LIGHT_R * 1.9, 8.0, LIGHT_R * 1.9)])
	for sh: Array in SHEDS:
		var sx := xf_of(sh[0] + Vector2(0, SHED_D * 0.5), float(sh[1]))
		out.append([sx * Transform3D(Basis.IDENTITY, Vector3(0, 1.6, -SHED_D + 0.2)), Vector3(SHED_W, 3.2, 0.4)])           # 背墙
		for s: float in [-1.0, 1.0]:
			out.append([sx * Transform3D(Basis.IDENTITY, Vector3(s * SHED_W * 0.5, 1.6, -SHED_D * 0.5)), Vector3(0.4, 3.2, SHED_D)])
	for p: Array in piers():                                             # 栈桥：桥面能站，两边、尽头一道栏
		var a: Vector2 = p[0]
		var b: Vector2 = p[1]
		var y := pier_y(p)
		var mid := (a + b) * 0.5
		var len := a.distance_to(b)
		out.append([Transform3D(Basis.IDENTITY, Vector3(mid.x, y - 0.15, mid.y)), Vector3(len, 0.3, PIER_W)])
		for s: float in [-1.0, 1.0]:
			out.append([Transform3D(Basis.IDENTITY, Vector3(mid.x + 2.0, y + 0.55, mid.y + s * (PIER_W * 0.5 - 0.05))), Vector3(len - 4.0, 1.1, 0.1)])
		out.append([Transform3D(Basis.IDENTITY, Vector3(b.x - 0.05, y + 0.55, b.y)), Vector3(0.1, 1.1, PIER_W)])
	for br: Array in bridges():                                          # 桥：桥面、两边石栏
		var c: Vector2 = br[0]
		var dir: Vector2 = br[1]
		var yaw := -atan2(dir.y, dir.x)
		var span := (HarborLayout.CANAL_HALF + HarborLayout.CANAL_BANK) * 2.0 + 3.0
		var y := ground(c - dir * span * 0.5)
		var bas := Basis(Vector3.UP, yaw)
		out.append([Transform3D(bas, Vector3(c.x, y - 0.12, c.y)), Vector3(span, 0.3, BRIDGE_W)])
		for s: float in [-1.0, 1.0]:
			out.append([Transform3D(bas, Vector3(c.x, y + 0.5, c.y) + bas * Vector3(0, 0, s * (BRIDGE_W * 0.5 + 0.15))), Vector3(span - 1.0, 1.0, 0.3)])
	for sl: Array in sluices():                                          # 木闸两边的石墩
		var c: Vector2 = sl[0]
		var n := Vector2(-(sl[1] as Vector2).y, (sl[1] as Vector2).x)
		for s: float in [-1.0, 1.0]:
			var q := c + n * s * (HarborLayout.CANAL_HALF + 0.5)
			out.append([Transform3D(Basis.IDENTITY, Vector3(q.x, ground(c + n * s * 6.0) - 1.0, q.y)), Vector3(1.4, 6.0, 1.4)])
	for k: Array in kerbs():
		var a: Vector3 = k[0]
		var b: Vector3 = k[1]
		var mid := (a + b) * 0.5
		var d := b - a
		out.append([Transform3D(Basis(Vector3.UP, -atan2(d.z, d.x)), mid + Vector3(0, KERB_BLOCK * 0.5, 0)), Vector3(Vector2(d.x, d.z).length() + 0.05, KERB_BLOCK, 0.4)])
	for x: Array in props_decor().solids:
		out.append([Transform3D(Basis.IDENTITY, x[0]), x[1]])
	return out


## 栏石（码头边、潮沟边、城南边石岸上沿）：每 2 米一段 [起点, 终点]（地面高度），桥头、栈桥口、石阶口、闸口留空
static func kerbs() -> Array:
	if not _kerbs.is_empty():
		return _kerbs
	var out := []
	var gaps := []
	for br: Array in bridges():                                        # 桥头：栏石离潮沟中线 4.45 米，桥面半宽 1.8——留够
		gaps.append([br[0], 5.8])
	for p: Array in piers():
		gaps.append([Vector2(river_edge_x((p[0] as Vector2).y) - HarborLayout.RIVER_BANK - 0.4, (p[0] as Vector2).y), PIER_W * 0.5 + 0.6])
	for x: float in HarborLayout.STAIRS:
		gaps.append([Vector2(x, HarborLayout.quay_z(x) - HarborLayout.QUAY_DROP - 0.3), HarborLayout.STAIR_HALF + 0.6])
	for sl: Array in sluices():
		gaps.append([sl[0], HarborLayout.CANAL_HALF + 2.5])
	var lines := []
	for cn: Array in HarborLayout.CANALS:                              # 潮沟两边
		for s: float in [-1.0, 1.0]:
			var pts := []
			for j in cn.size() - 1:
				var a: Vector2 = cn[j]
				var b: Vector2 = cn[j + 1]
				var n := Vector2(-(b - a).normalized().y, (b - a).normalized().x)
				var steps := int(ceil(a.distance_to(b) / 2.0))
				for k in steps:
					pts.append(a.lerp(b, float(k) / steps) + n * s * (HarborLayout.CANAL_HALF + HarborLayout.CANAL_BANK + 0.35))
			lines.append(pts)
	var river := []                                                     # 西岸河边
	var z := HarborLayout.BOUNDS.position.y + 8.0
	while z < HarborLayout.quay_z(river_edge_x(z)) - HarborLayout.QUAY_DROP - 1.0:
		river.append(Vector2(river_edge_x(z) - HarborLayout.RIVER_BANK - 0.4, z))
		z += 2.0
	lines.append(river)
	var south := []                                                     # 城南边石岸上沿
	var x := HarborLayout.BOUNDS.position.x + 8.0
	while x < river_edge_x(HarborLayout.QUAY_Z) - HarborLayout.RIVER_BANK - 1.5:
		south.append(Vector2(x, HarborLayout.quay_z(x) - HarborLayout.QUAY_DROP - 0.3))
		x += 2.0
	lines.append(south)
	for ln: Array in lines:
		for k in ln.size() - 1:
			var a: Vector2 = ln[k]
			var b: Vector2 = ln[k + 1]
			var m := (a + b) * 0.5
			var skip := false
			for g: Array in gaps:
				if m.distance_to(g[0]) < float(g[1]):
					skip = true
			if skip or ground(m) < 1.0 or not HarborLayout.west_bank(m) or HarborLayout.river_edge(m) < 0.5:
				continue
			out.append([Vector3(a.x, ground(a), a.y), Vector3(b.x, ground(b), b.y)])
	_kerbs = out
	return out


## 门、路牌、告示（同步）
static func interactables(parent: Node3D) -> void:
	var k := 0
	for h: Dictionary in houses():
		if int(h.seed) % 3 != 0:
			continue
		var d := Door.make("门", 1.0, 2.0, true)
		d.locked_text = HOUSE_TEXTS[k % HOUSE_TEXTS.size()]
		k += 1
		d.name = "HarborDoor_%d" % k
		d.transform = xf_of(h.front, float(h.yaw)) * Transform3D(Basis.IDENTITY, Vector3(-0.5, 0, 0.06))
		parent.add_child(d)
	for spec: Array in [[key_front(), 180.0, "钥楼的门", "key_hall", 1.6, 2.6, "KeyHouseDoor"], [guild_front(), 0.0, "会馆的门", "guild_hall", 1.4, 2.4, "GuildDoor"],
			[prison_front(), PRISON_YAW, "债牢的铁门", "debt_prison", 1.2, 2.1, "PrisonDoor"], [TAVERN_FRONT, 90.0, "「咸潮」酒馆的门", "dock_tavern", 1.2, 2.2, "TavernDoor"]]:
		var d := Door.make(str(spec[2]), float(spec[4]), float(spec[5]), false)       # 7.3：进得去（屋里是另一个区域，HarborRooms）
		d.to_area = str(spec[3])
		d.to_spawn = "front"
		d.verb = "进入"
		d.name = str(spec[6])
		d.transform = xf_of(spec[0], float(spec[1])) * Transform3D(Basis.IDENTITY, Vector3(-float(spec[4]) * 0.5, 0, 0.08))
		parent.add_child(d)
	var lp := HarborLayout.LIGHTHOUSE
	var ld := Door.make("灯塔的门", 1.0, 2.0, true)
	ld.locked_text = LIGHT_DOOR_TEXT
	ld.name = "LighthouseDoor"
	ld.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-30.0)), Vector3(lp.x, ground(lp), lp.y)) * Transform3D(Basis.IDENTITY, Vector3(-0.5, 0, LIGHT_R + 0.02))
	parent.add_child(ld)
	for s: Array in [[SIGN_QUAY, SIGN_QUAY_TEXT, -60.0, "QuaySign"], [SIGN_KEY, SIGN_KEY_TEXT, 90.0, "KeyStreetSign"]]:
		var rs := RoadSign.new()
		rs.text = str(s[1])
		rs.name = str(s[3])
		rs.position = Vector3((s[0] as Vector2).x, ground(s[0]), (s[0] as Vector2).y)
		rs.rotation_degrees.y = float(s[2])
		parent.add_child(rs)
	var e := Examine.make("清账的告示", "看告示", func(_who: FpController) -> Dictionary:
		var gs := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GameState")       # 不直接写 GameState：生成高度场的脚本里没有自动加载（同 Harbor.tide）
		if gs:
			gs.set_flag("ch4_notice_read")
		return {"toast": NOTICE_TEXT}, Vector3(1.6, 2.0, 0.6))
	e.name = "ClearingNotice"
	e.position = Vector3(NOTICE.x, ground(NOTICE), NOTICE.y)
	parent.add_child(e)


# ---------------- 画面（分帧的活） ----------------

static func jobs_for(rect: Rect2) -> Array:
	var out := []
	var hs := []
	for h: Dictionary in houses():
		if rect.has_point(house_center(h)):
			hs.append(h)
	var group := 0
	while group * 8 < hs.size():                                         # 一件活最多 8 栋（一块 14 栋时这件活 90 多毫秒，分帧搭建会卡一下）
		var part := hs.slice(group * 8, group * 8 + 8)
		var tag := group
		out.append(func(root: Node3D): _house_block(root, part, rect, tag))
		group += 1
	if rect.has_point(HarborLayout.KEY_HOUSE):
		out.append(func(root: Node3D): _key_house(root))
	if rect.has_point(HarborLayout.GUILD):
		out.append(func(root: Node3D): _guild(root))
	if rect.has_point(TAVERN_FRONT):
		out.append(func(root: Node3D): _tavern(root))
	if rect.has_point(HarborLayout.PRISON):
		out.append(func(root: Node3D): _prison(root))
	if rect.has_point(HarborLayout.LIGHTHOUSE):
		out.append(func(root: Node3D): _lighthouse(root))
	if _has_works(rect):
		out.append(func(root: Node3D): _works(root, rect))
	if not props_decor(rect).kit.tools.is_empty():
		out.append(func(root: Node3D): _props(root, rect))
	return out


## 一块里的房子合成一个网格（组 house：按时段整块亮灯 / 灭灯，Daypart.set_windows 找子节点 Mesh）
static func _house_block(root: Node3D, hs: Array, rect: Rect2, tag := 0) -> void:
	var node := Node3D.new()
	node.name = "Houses_%d_%d_%d" % [int(rect.position.x), int(rect.position.y), tag]
	node.add_to_group("house")
	node.set_meta("seed", int(rect.position.x * 7 + rect.position.y * 13) + tag * 31)
	root.add_child(node)
	var kit := MeshKit.new()
	for h: Dictionary in hs:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(h.seed)
		_merchant(kit, xf_of(h.front, float(h.yaw)), float(h.w), float(h.d), int(h.floors), bool(h.stone), rng)
	var mi := kit.build(mats())
	mi.name = "Mesh"
	node.add_child(mi)
	var smoke := RandomNumberGenerator.new()
	smoke.seed = int(rect.position.x * 3 + rect.position.y) + tag
	for h: Dictionary in hs:
		if smoke.randf() < 0.3:
			var top := GH + int(h.floors) * FH + float(h.w) * 0.5 * tan(deg_to_rad(ROOF_PITCH)) * 0.6
			var cp := xf_of(h.front, float(h.yaw)) * Vector3(float(h.w) * 0.25, top + 1.4, -float(h.d) * 0.7)
			Atmos.smoke(node, cp)


## 港口的窄房子：底层石砌，上层灰泥木构（钥楼街上的商行全石砌），山墙朝街、陡的石板瓦顶，屋脊积着一点雪，正面每层一排窗
static func _merchant(kit: MeshKit, xf: Transform3D, w: float, d: float, floors: int, stone: bool, rng: RandomNumberGenerator, lit := 0.5) -> void:
	var b := xf.basis
	var at := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x, y, z)
	var jet := 0.0 if stone else JET
	var upper := "stone" if stone else "plaster"
	kit.box("stone", at.call(0, GH * 0.5, -d * 0.5), Vector3(w, GH, d), b, 1.0, 0.55)
	kit.box("stone", at.call(0, 0.2, -d * 0.5), Vector3(w + 0.16, 0.4, d + 0.16), b, 0.7, 0.45)
	var top := GH + floors * FH
	for f in floors:
		var y0 := GH + f * FH
		kit.box(upper, at.call(0, y0 + FH * 0.5, -d * 0.5 + jet * 0.5), Vector3(w, FH, d + jet), b, 0.85, 1.0)
		kit.box("timber", at.call(0, y0 - 0.06, jet * 0.5 + 0.02), Vector3(w + 0.1, 0.16, jet + 0.18), b, 0.6, 0.5)
		if not stone:                                                    # 木构架：正面三根立柱、上下两道横梁、两头斜撑
			for px: float in [-w * 0.5 + 0.08, 0.0, w * 0.5 - 0.08]:
				kit.box("timber", at.call(px, y0 + FH * 0.5, jet + 0.03), Vector3(0.16, FH, 0.06), b, 0.7, 0.6)
			kit.box("timber", at.call(0, y0 + FH - 0.08, jet + 0.03), Vector3(w, 0.14, 0.06), b, 0.7, 0.6)
			for s: float in [-1.0, 1.0]:
				kit.box("timber", at.call(s * (w * 0.5 - 0.55), y0 + FH * 0.35, jet + 0.035), Vector3(0.12, 1.5, 0.05), b * Basis(Vector3.BACK, s * 0.62), 0.7, 0.6)
		var n := maxi(1, int((w - 1.2) / 1.9))                           # 正面一排窗
		for i in n:
			var x := -w * 0.5 + (i + 0.5) * w / n
			_window(kit, at.call(x, y0 + FH * 0.55, jet + 0.04), b, rng.randf() < lit, 0.72, 1.15)
		_window(kit, at.call(0, y0 + FH * 0.55, -d - 0.04), b * Basis(Vector3.UP, PI), rng.randf() < lit * 0.6, 0.7, 1.1)    # 背面一扇
	kit.box("dark", at.call(-0.0, 1.05, 0.04), Vector3(1.0, 2.1, 0.06), b)                                     # 门洞（门板是同步放的 Door，或者就是一块黑）
	kit.box("stone", at.call(0, 2.2, 0.08), Vector3(1.4, 0.18, 0.12), b, 0.8, 0.8)                          # 门楣
	for s: float in [-1.0, 1.0]:                                                                               # 底层两边两扇小窗，带木板窗扇
		var wx := s * (w * 0.5 - 1.1)
		if absf(wx) > 1.3:
			_window(kit, at.call(wx, 1.6, 0.05), b, rng.randf() < lit, 0.8, 0.8)
			kit.box("timber", at.call(wx + s * 0.62, 1.6, 0.1), Vector3(0.4, 0.86, 0.05), b, 0.7, 0.6)
	# 山墙朝街的屋顶：屋脊顺着进深，两片瓦坡、前后两个山墙三角
	var hw := w * 0.5 + EAVE
	var rise := (w * 0.5) * tan(deg_to_rad(ROOF_PITCH + rng.randf_range(-4.0, 4.0)))
	var slope := sqrt(hw * hw + rise * rise * (hw / (w * 0.5)) * (hw / (w * 0.5)))
	var zf := jet + 0.45
	var zb := -d - 0.4
	var depth := zf - zb
	for s: float in [-1.0, 1.0]:
		var ang := atan2(rise, w * 0.5)
		var sb := b * Basis(Vector3.BACK, -s * ang)
		var mid: Vector3 = at.call(s * hw * 0.5, top + rise * 0.5 - 0.12 * cos(ang) - (hw - w * 0.5) * tan(ang) * 0.5, (zf + zb) * 0.5)
		kit.box("roof", mid, Vector3(slope, 0.14, depth), sb, 1.0, 0.75)
		kit.box("snow", mid + (sb * Vector3.UP) * 0.09 + (sb * Vector3.RIGHT) * (-s) * slope * 0.22, Vector3(slope * 0.5, 0.06, depth - 0.1), sb, 1.0, 1.0)
	for zz: float in [jet + 0.01, -d - 0.01]:
		var nz := (b * Vector3.BACK) * (1.0 if zz > 0.0 else -1.0)
		kit.tri(upper, at.call(-w * 0.5, top, zz), at.call(w * 0.5, top, zz), at.call(0, top + rise, zz), nz, 0.9)
	if rng.randf() < 0.6:
		var cx := w * 0.25
		kit.box("stone", at.call(cx, top + rise * 0.6 + 0.7, -d * 0.7), Vector3(0.6, 2.2, 0.6), b, 1.0, 0.7)


static func _window(kit: MeshKit, c: Vector3, b: Basis, on: bool, w: float, h: float) -> void:
	kit.box("glass_lit" if on else "glass_dark", c, Vector3(w, h, 0.03), b)
	kit.box("timber", c + b * Vector3(0, -h * 0.5 - 0.05, 0.03), Vector3(w + 0.16, 0.08, 0.1), b, 0.8, 0.6)
	kit.box("timber", c + b * Vector3(0, 0, 0.025), Vector3(0.05, h, 0.03), b, 0.8, 0.8)
	if on:
		kit.box("halo", c + b * Vector3(0, 0, 0.12), Vector3(w * 1.8, h * 1.6, 0.01), b)


## 钥楼：钥楼街上最高的一栋，全石砌（黑鹭堡那种灰方石），底层高、窗上装着铁栏，正面两面蓝底双钥交叉的旗；背墙直接立在北潮沟边上，墙脚一道带铁栅的水门
static func _key_house(root: Node3D) -> void:
	var node := Node3D.new()
	node.name = "KeyHouse"
	node.add_to_group("house")
	node.set_meta("seed", 77)
	root.add_child(node)
	var kit := MeshKit.new()
	var xf := xf_of(key_front(), 180.0)
	var b := xf.basis
	var at := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x, y, z)
	var w := KEY_W
	var d := KEY_D
	var top := KEY_GH + KEY_FLOORS * KEY_FH
	kit.box("castle", at.call(0, top * 0.5, -d * 0.5), Vector3(w, top, d), b, 1.0, 0.5)
	kit.box("castle", at.call(0, 0.3, -d * 0.5), Vector3(w + 0.3, 0.6, d + 0.3), b, 0.7, 0.4)
	for f in KEY_FLOORS + 1:                                             # 每层一道石檐
		var y := KEY_GH + f * KEY_FH
		kit.box("castle", at.call(0, y - 0.05, 0.08), Vector3(w + 0.2, 0.2, 0.3), b, 0.85, 0.7)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7203
	for f in KEY_FLOORS:                                                 # 上面三层：一排高窗，大多亮着（钱庄的人夜里还在算账）
		var y0 := KEY_GH + f * KEY_FH
		for i in 6:
			var x := -w * 0.5 + (i + 0.5) * w / 6.0
			_window(kit, at.call(x, y0 + KEY_FH * 0.55, 0.06), b, rng.randf() < 0.75, 0.8, 1.6)
	for i in 4:                                                          # 底层：四扇小窗，铁栏
		var x := -w * 0.5 + (i + 0.5) * w / 4.0
		if absf(x) < 2.0:
			continue
		_window(kit, at.call(x, 2.2, 0.06), b, false, 0.9, 1.0)
		for k in 4:
			kit.box("iron", at.call(x - 0.33 + k * 0.22, 2.2, 0.1), Vector3(0.05, 1.1, 0.05), b)
	kit.box("dark", at.call(0, 1.4, 0.05), Vector3(1.8, 2.8, 0.06), b)
	kit.box("castle", at.call(0, 3.0, 0.15), Vector3(2.6, 0.4, 0.3), b, 0.9, 0.8)
	for s: float in [-1.0, 1.0]:
		kit.box("castle", at.call(s * 1.15, 1.5, 0.12), Vector3(0.4, 3.0, 0.24), b, 0.9, 0.7)
	# 屋顶：顺着正面的四坡顶（比别的房子高一截），屋脊上一排雪
	var rise := 4.2
	for s: float in [-1.0, 1.0]:
		var ang := atan2(rise, d * 0.5 + 0.5)
		var sb := b * Basis(Vector3.RIGHT, s * ang)
		var slope := sqrt(pow(d * 0.5 + 0.5, 2) + rise * rise)
		var mid: Vector3 = at.call(0, top + rise * 0.5, -d * 0.5 + s * (d * 0.25 + 0.25))
		kit.box("roof", mid, Vector3(w + 0.8, 0.16, slope), sb, 1.0, 0.75)
		kit.box("snow", mid + (sb * Vector3.UP) * 0.1 + (sb * Vector3.BACK) * (-s) * slope * 0.22, Vector3(w + 0.6, 0.06, slope * 0.5), sb, 1.0, 1.0)
	for s: float in [-1.0, 1.0]:
		var nx := (b * Vector3.RIGHT) * s
		kit.tri("castle", at.call(s * w * 0.5, top, 0.0), at.call(s * w * 0.5, top, -d), at.call(s * w * 0.5, top + rise, -d * 0.5), nx, 0.9)
	# 背面：潮沟边的水门（拱一点的黑洞、一道铁栅，底在潮沟底）
	var canal_y := HarborLayout.CANAL_BED
	var gate_c: Vector3 = at.call(3.0, 0.0, -d - 0.02)
	var base_y := xf.origin.y
	kit.box("dark", Vector3(gate_c.x, (canal_y + base_y + 0.4) * 0.5, gate_c.z), Vector3(2.4, base_y + 0.4 - canal_y, 0.06), b)
	for k in 7:
		var gx: Vector3 = at.call(3.0 - 1.05 + k * 0.35, 0.0, -d - 0.08)
		kit.box("iron", Vector3(gx.x, (canal_y + base_y + 0.3) * 0.5, gx.z), Vector3(0.06, base_y + 0.3 - canal_y, 0.06), b)
	kit.box("castle", Vector3(gate_c.x, base_y + 0.6, gate_c.z) + (b * Vector3.BACK) * -0.1, Vector3(3.0, 0.4, 0.3), b)
	kit.box("castle", Vector3(xf.origin.x, (canal_y + base_y) * 0.5, xf.origin.z) + (b * Vector3.BACK) * (-d) + (b * Vector3.BACK) * -0.05, Vector3(w, base_y - canal_y, 0.1), b, 0.8, 0.4)   # 背墙一直砌到沟底
	var mi := kit.build(mats())
	mi.name = "Mesh"
	node.add_child(mi)
	var dec := Decor.new()
	for s: float in [-1.0, 1.0]:
		dec.banner(at.call(s * 4.2, KEY_GH + 2.6, 0.12), b * Vector3.BACK, 1.3, 2.6, Color("26407a"), Color("d8c890"), "keys", Color("b89a4a"))
		dec.sconce(at.call(s * 1.7, 2.6, 0.12), b * Vector3.BACK, s > 0.0)
	dec.build(node, "KeyHouseDecor")


## 渡工行会的港口会馆：一层半的长屋，底层石砌、上层灰泥木构，正面朝南对着鱼市，门上一面灰底桨与绳结的旗
static func _guild(root: Node3D) -> void:
	var node := Node3D.new()
	node.name = "GuildHall"
	node.add_to_group("house")
	node.set_meta("seed", 91)
	root.add_child(node)
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7204
	var xf := xf_of(guild_front(), 0.0)
	_merchant(kit, xf, GUILD_W, GUILD_D, 2, false, rng, 0.8)
	var mi := kit.build(mats())
	mi.name = "Mesh"
	node.add_child(mi)
	var dec := Decor.new()
	var at := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x, y, z)
	dec.banner(at.call(0, GH + 2.2, JET + 0.1), xf.basis * Vector3.BACK, 1.4, 2.2, Color("5a5e62"), Color("d8d2c0"), "oar", Color("8a6a3a"))
	for k in 3:
		dec.barrel(at.call(-5.0 + k * 0.7, 0.0, 1.2))
	dec.crate(at.call(4.5, 0.0, 1.4), 0.4)
	dec.build(node, "GuildDecor")


## 「咸潮」酒馆（7.3）：码头街西边一栋矮胖的两层，底层石砌、上层灰泥木构，门口挂一块木牌子（一条鱼、一道浪）、两盏灯
static func _tavern(root: Node3D) -> void:
	var node := Node3D.new()
	node.name = "Tavern"
	node.add_to_group("house")
	node.set_meta("seed", 93)
	root.add_child(node)
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7302
	var xf := xf_of(TAVERN_FRONT, 90.0)
	_merchant(kit, xf, TAVERN_W, TAVERN_D, 1, false, rng, 0.9)
	var at := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x, y, z)
	var sp: Vector3 = at.call(1.6, 2.9, 0.6)                           # 招牌：伸出来的铁杆上吊一块木板
	kit.box("iron", sp + xf.basis * Vector3(0, 0.3, -0.3), Vector3(0.05, 0.05, 1.0), xf.basis)
	kit.box("timber", sp, Vector3(0.9, 0.55, 0.06), xf.basis * Basis(Vector3.UP, PI * 0.5), 1.0, 0.8)
	kit.box("dark", sp + xf.basis * Vector3(0.04, 0.05, 0), Vector3(0.5, 0.14, 0.01), xf.basis * Basis(Vector3.UP, PI * 0.5))
	var mi := kit.build(mats())
	mi.name = "Mesh"
	node.add_child(mi)
	var dec := Decor.new()
	for s: float in [-1.0, 1.0]:
		dec.sconce(at.call(s * 1.2, 2.2, 0.06), xf.basis * Vector3.BACK, s > 0.0)
	dec.barrel(at.call(-2.6, 0.0, 1.0))
	dec.barrel(at.call(-3.2, 0.0, 1.2))
	dec.build(node, "TavernDecor")


## 债牢：城西北角一栋矮胖的石头房子，窗子小、带铁栏，门是铁的；屋前一道矮院墙
static func _prison(root: Node3D) -> void:
	var node := Node3D.new()
	node.name = "Prison"
	root.add_child(node)
	var kit := MeshKit.new()
	var xf := xf_of(prison_front(), PRISON_YAW)
	var b := xf.basis
	var at := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x, y, z)
	var w := PRISON_W
	var d := PRISON_D
	var top := 6.6
	kit.box("castle", at.call(0, top * 0.5, -d * 0.5), Vector3(w, top, d), b, 1.0, 0.45)
	for i in 5:
		var x := -w * 0.5 + (i + 0.5) * w / 5.0
		if absf(x) < 1.2:
			continue
		for y: float in [2.4, 5.0]:
			kit.box("dark", at.call(x, y, 0.04), Vector3(0.5, 0.6, 0.04), b)
			for k in 3:
				kit.box("iron", at.call(x - 0.17 + k * 0.17, y, 0.08), Vector3(0.04, 0.66, 0.04), b)
	kit.box("iron", at.call(0, 1.05, 0.05), Vector3(1.2, 2.1, 0.06), b)
	for s: float in [-1.0, 1.0]:                                         # 平顶上一圈矮墙
		kit.box("castle", at.call(s * w * 0.5, top + 0.4, -d * 0.5), Vector3(0.4, 0.8, d), b, 0.9, 0.8)
		kit.box("castle", at.call(0, top + 0.4, -d * 0.5 + s * d * 0.5), Vector3(w, 0.8, 0.4), b, 0.9, 0.8)
	kit.box("snow", at.call(0, top + 0.03, -d * 0.5), Vector3(w - 0.4, 0.06, d - 0.4), b)
	var mi := kit.build(mats())
	mi.name = "PrisonMesh"
	node.add_child(mi)


## 灯塔：沙嘴尽头礁石上的石塔，往上收，塔顶一圈铁栏和火盆——这个冬天没油，只剩一点暗红的炭（夜里一盏很弱的灯，组 night_light）
static func _lighthouse(root: Node3D) -> void:
	var node := Node3D.new()
	node.name = "Lighthouse"
	root.add_child(node)
	var lp := HarborLayout.LIGHTHOUSE
	var base := Vector3(lp.x, ground(lp) - 0.3, lp.y)
	var kit := MeshKit.new()
	kit.cylinder("castle", base, base + Vector3(0, LIGHT_H, 0), LIGHT_R, LIGHT_R * 0.68, 12, 1.0)
	kit.cylinder("castle", base + Vector3(0, LIGHT_H, 0), base + Vector3(0, LIGHT_H + 0.5, 0), LIGHT_R * 0.85, LIGHT_R * 0.85, 12, 0.9)
	for k in 10:                                                         # 塔顶一圈铁栏
		var a := TAU * k / 10.0
		var p := base + Vector3(cos(a) * LIGHT_R * 0.8, LIGHT_H + 0.5, sin(a) * LIGHT_R * 0.8)
		kit.cylinder("iron", p, p + Vector3(0, 1.0, 0), 0.04, 0.04, 4)
	kit.cylinder("iron", base + Vector3(0, LIGHT_H + 0.5, 0), base + Vector3(0, LIGHT_H + 1.3, 0), 0.25, 0.9, 8, 0.8)   # 火盆
	kit.cylinder("ember", base + Vector3(0, LIGHT_H + 1.2, 0), base + Vector3(0, LIGHT_H + 1.35, 0), 0.75, 0.6, 8)
	for k in 3:                                                          # 塔身三个小窗
		var y := 4.0 + k * 3.6
		var a := deg_to_rad(-30.0 + k * 50.0)
		var r := lerpf(LIGHT_R, LIGHT_R * 0.68, y / LIGHT_H) + 0.02
		kit.box("dark", base + Vector3(sin(a) * r, y, cos(a) * r), Vector3(0.4, 0.8, 0.05), Basis(Vector3.UP, a))
	var mi := kit.build(mats())
	mi.name = "LighthouseMesh"
	node.add_child(mi)
	var l := Tavern.FireLight.new()
	l.name = "LighthouseEmber"
	l.light_color = Color("ff7a3a")
	l.base = 0.9
	l.omni_range = 9.0
	l.position = base + Vector3(0, LIGHT_H + 1.8, 0)
	l.add_to_group("night_light")
	node.add_child(l)


## 这一块里有没有码头和水边的东西（便宜地查：不真的搭）
static func _has_works(rect: Rect2) -> bool:
	for p: Array in piers():
		if rect.has_point(((p[0] as Vector2) + (p[1] as Vector2)) * 0.5):
			return true
	for sl: Array in sluices():
		if rect.has_point(sl[0]):
			return true
	for br: Array in bridges():
		if rect.has_point(br[0]):
			return true
	for x: float in HarborLayout.STAIRS:
		if rect.has_point(Vector2(x, HarborLayout.stair_span(x).x + 1.0)):
			return true
	for r: Vector2 in RACKS:
		if rect.has_point(r):
			return true
	for sh: Array in SHEDS:
		if rect.has_point(sh[0]):
			return true
	if rect.has_point(WRECK[0]):
		return true
	for k: Array in kerbs():
		var m: Vector3 = ((k[0] as Vector3) + (k[1] as Vector3)) * 0.5
		if rect.has_point(Vector2(m.x, m.z)):
			return true
	return false


## 码头和水边的活：栈桥（木桩站在河里）、木闸、桥、栏石、石阶、晒鱼架、盐仓、船、搁浅的粮船
static func _works_kit(rect: Rect2) -> MeshKit:
	var kit := MeshKit.new()
	var inside := func(p: Vector2) -> bool: return rect.has_point(p)
	for p: Array in piers():
		var a: Vector2 = p[0]
		var b: Vector2 = p[1]
		if not inside.call((a + b) * 0.5):
			continue
		var y := pier_y(p)
		var mid := (a + b) * 0.5
		var len := a.distance_to(b)
		kit.box("timber", Vector3(mid.x, y - 0.1, mid.y), Vector3(len, 0.2, PIER_W), Basis.IDENTITY, 1.0, 0.7)
		var x := a.x + 3.5
		while x < b.x:                                                   # 木桩：一对一对站到河床
			for s: float in [-1.0, 1.0]:
				var px := Vector3(x, y - 0.2, mid.y + s * (PIER_W * 0.5 - 0.15))
				kit.cylinder("tar", Vector3(px.x, HarborLayout.RIVER_BED - 0.5, px.z), px + Vector3(0, 1.3, 0), 0.16, 0.14, 6)
			x += 2.4
		for s: float in [-1.0, 1.0]:
			kit.box("timber", Vector3(mid.x + 2.0, y + 0.95, mid.y + s * (PIER_W * 0.5 - 0.15)), Vector3(len - 4.0, 0.1, 0.1), Basis.IDENTITY, 0.8, 0.8)
		kit.cylinder("tar", Vector3(b.x - 0.4, y, b.y + 1.0), Vector3(b.x - 0.4, y + 0.6, b.y + 1.0), 0.16, 0.18, 6)      # 拴船桩
	for sl: Array in sluices():
		var c: Vector2 = sl[0]
		if not inside.call(c):
			continue
		var dir: Vector2 = sl[1]
		var n := Vector2(-dir.y, dir.x)
		var yaw := -atan2(n.y, n.x)
		var top := ground(c + n * 6.0) + 0.3
		for s: float in [-1.0, 1.0]:
			var q := c + n * s * (HarborLayout.CANAL_HALF + 0.5)
			kit.box("castle", Vector3(q.x, (HarborLayout.CANAL_BED + top) * 0.5, q.y), Vector3(1.4, top - HarborLayout.CANAL_BED, 1.4), Basis.IDENTITY, 0.9, 0.5)
		kit.box("timber", Vector3(c.x, top + 1.2, c.y), Vector3(HarborLayout.CANAL_HALF * 2.0 + 2.4, 0.3, 0.4), Basis(Vector3.UP, yaw), 0.8, 0.7)      # 闸上的横梁（闸板吊起来了：涨潮时船进得来）
		kit.box("timber", Vector3(c.x, top + 0.35, c.y), Vector3(HarborLayout.CANAL_HALF * 2.0, 1.2, 0.18), Basis(Vector3.UP, yaw), 0.7, 0.55)
		for s: float in [-1.0, 1.0]:
			var q := c + n * s * (HarborLayout.CANAL_HALF + 0.5)
			kit.box("timber", Vector3(q.x, top + 0.9, q.y), Vector3(0.24, 1.8, 0.24), Basis.IDENTITY, 0.8, 0.7)
	for br: Array in bridges():
		var c: Vector2 = br[0]
		if not inside.call(c):
			continue
		var dir: Vector2 = br[1]
		var bas := Basis(Vector3.UP, -atan2(dir.y, dir.x))
		var span := (HarborLayout.CANAL_HALF + HarborLayout.CANAL_BANK) * 2.0 + 3.0
		var y := ground(c - dir * span * 0.5)
		var cc := Vector3(c.x, y, c.y)
		kit.box("stone", cc + Vector3(0, -0.25, 0), Vector3(span, 0.5, BRIDGE_W), bas, 1.0, 0.6)
		kit.box("stone", cc + Vector3(0, -1.2, 0), Vector3(span - 2.0, 1.4, BRIDGE_W - 0.2), bas, 0.6, 0.4)                       # 桥身（拱下面是黑的潮沟）
		for s: float in [-1.0, 1.0]:
			kit.box("stone", cc + bas * Vector3(0, 0.45, s * (BRIDGE_W * 0.5 + 0.15)), Vector3(span - 0.6, 0.9, 0.3), bas, 1.0, 0.7)
			kit.box("snow", cc + bas * Vector3(0, 0.92, s * (BRIDGE_W * 0.5 + 0.15)), Vector3(span - 0.8, 0.05, 0.28), bas)
	for k: Array in kerbs():
		var a: Vector3 = k[0]
		var bq: Vector3 = k[1]
		var m := (a + bq) * 0.5
		if not inside.call(Vector2(m.x, m.z)):
			continue
		var d := bq - a
		var bas := Basis(Vector3.UP, -atan2(d.z, d.x))
		kit.box("stone", m + Vector3(0, KERB_H * 0.5, 0), Vector3(Vector2(d.x, d.z).length() + 0.04, KERB_H, 0.42), bas, 0.95, 0.6)
	for x: float in HarborLayout.STAIRS:
		var sp := HarborLayout.stair_span(x)
		var top := Vector2(x, sp.x + 1.0)
		if not inside.call(top):
			continue
		var n := 14
		for k in n:                                                      # 一级一级的石阶（压在地形的斜坡上，碰撞就是地形）
			var t := (k + 0.5) / n
			var p := Vector2(x, lerpf(sp.x + 1.0, sp.y, t))
			kit.box("stone", Vector3(p.x, ground(p) - 0.12, p.y), Vector3(HarborLayout.STAIR_HALF * 2.0, 0.3, (sp.y - sp.x - 1.0) / n + 0.06), Basis.IDENTITY, 0.9, 0.5)
		for s: float in [-1.0, 1.0]:                                    # 两边一道矮石墙
			var a := Vector2(x + s * (HarborLayout.STAIR_HALF + 0.2), sp.x + 1.5)
			var b := Vector2(x + s * (HarborLayout.STAIR_HALF + 0.2), sp.y - 0.5)
			var ya := ground(Vector2(x, a.y)) + 0.4
			var yb := ground(Vector2(x, b.y)) + 0.4
			var mid := Vector3(a.x, (ya + yb) * 0.5, (a.y + b.y) * 0.5)
			var dl := Vector3(0, yb - ya, b.y - a.y)
			kit.box("stone", mid, Vector3(0.35, 0.9, dl.length()), Basis(Vector3.RIGHT, -atan2(dl.y, dl.z)), 0.9, 0.6)
	for r: Vector2 in RACKS:                                             # 晒鱼架：两头木架、三道横杆，杆上挂着一排排剖开的鱼
		if not inside.call(r):
			continue
		var y := ground(r)
		for s: float in [-1.0, 1.0]:
			for t: float in [-0.35, 0.35]:
				kit.cylinder("timber", Vector3(r.x + s * 2.0, y, r.y + t), Vector3(r.x + s * 2.0, y + 2.1, r.y), 0.06, 0.05, 5)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(r.x * 31.0 + r.y)
		for k in 3:
			var yy := y + 1.1 + k * 0.45
			kit.cylinder("timber", Vector3(r.x - 2.1, yy, r.y), Vector3(r.x + 2.1, yy, r.y), 0.035, 0.035, 4)
			var fx := -1.8
			while fx < 1.8:
				if rng.randf() < 0.75:
					kit.box("fish", Vector3(r.x + fx, yy - 0.22, r.y), Vector3(0.12, 0.42, 0.03), Basis(Vector3.UP, rng.randf_range(-0.4, 0.4)), 1.0, 0.7)
				fx += 0.22
	for sh: Array in SHEDS:                                              # 盐仓：木板墙、单坡顶，正面敞着，里头堆着白的盐
		var c: Vector2 = sh[0]
		if not inside.call(c):
			continue
		var xf := xf_of(c + Vector2(0, SHED_D * 0.5), float(sh[1]))
		var bb := xf.basis
		var at := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x, y, z)
		kit.box("timber", at.call(0, 1.6, -SHED_D + 0.1), Vector3(SHED_W, 3.2, 0.2), bb, 0.9, 0.5)
		for s: float in [-1.0, 1.0]:
			kit.box("timber", at.call(s * SHED_W * 0.5, 1.6, -SHED_D * 0.5), Vector3(0.2, 3.2, SHED_D), bb, 0.9, 0.5)
		for px: float in [-SHED_W * 0.5 + 0.2, -SHED_W / 6.0, SHED_W / 6.0, SHED_W * 0.5 - 0.2]:
			kit.box("timber", at.call(px, 1.3, -0.1), Vector3(0.2, 2.6, 0.2), bb, 0.8, 0.6)
		var ang := atan2(3.4 - 2.6, SHED_D)
		var rb := bb * Basis(Vector3.RIGHT, ang)
		kit.box("roof", at.call(0, 3.05, -SHED_D * 0.5), Vector3(SHED_W + 0.6, 0.12, SHED_D + 0.6), rb, 1.0, 0.75)
		kit.box("snow", at.call(0, 3.14, -SHED_D * 0.5), Vector3(SHED_W + 0.4, 0.05, SHED_D * 0.7), rb)
		for k in 3:
			var hx := -SHED_W * 0.33 + k * SHED_W * 0.33
			var hc: Vector3 = at.call(hx, 0.0, -SHED_D * 0.55)
			kit.cylinder("salt", hc, hc + Vector3(0, 1.3 + k * 0.2, 0), 1.5, 0.05, 9, 1.0)
	var wp: Vector2 = WRECK[0]                                           # 搁浅的粮船：歪在泥滩上，船帮破了一块，桅杆断了半截
	if inside.call(wp):
		var y := ground(wp) + 0.2
		var hb := Basis(Vector3.UP, deg_to_rad(float(WRECK[1]))) * Basis(Vector3.BACK, 0.32)
		_hull(kit, Vector3(wp.x, y, wp.y), hb, float(WRECK[2]), true)
	return kit


## 船身：几块往两头收的木板（船底、两舷、船头船尾翘起），一根桅杆；broken = 搁浅的那条（舷上一个黑洞、桅杆断了）
static func _hull(kit: MeshKit, c: Vector3, b: Basis, length: float, broken := false) -> void:
	var beam := length * 0.3
	var at := func(x: float, y: float, z: float) -> Vector3: return c + b * Vector3(x, y, z)
	kit.box("tar", at.call(0, 0.35, 0), Vector3(beam * 0.55, 0.7, length * 0.8), b, 0.8, 0.5)
	for s: float in [-1.0, 1.0]:
		kit.box("timber", at.call(s * beam * 0.38, 1.05, 0), Vector3(0.14, 1.5, length * 0.82), b * Basis(Vector3.BACK, s * 0.22), 0.9, 0.55)
		for e: float in [-1.0, 1.0]:                                     # 船头、船尾往中间收
			kit.box("timber", at.call(s * beam * 0.2, 1.2, e * length * 0.44), Vector3(0.14, 1.6, length * 0.16), b * Basis(Vector3.UP, s * e * 0.55), 0.9, 0.55)
	kit.box("timber", at.call(0, 1.6, length * 0.47), Vector3(beam * 0.4, 1.8, 0.2), b, 0.9, 0.6)
	kit.box("timber", at.call(0, 1.8, -length * 0.45), Vector3(beam * 0.6, 1.4, 1.2), b, 0.9, 0.6)              # 船尾的小舱
	if broken:
		kit.box("dark", at.call(beam * 0.46, 0.9, length * 0.1), Vector3(0.05, 0.8, 2.2), b * Basis(Vector3.BACK, 0.22))
		kit.cylinder("timber", at.call(0, 0.7, 0), at.call(0, 4.5, 0), 0.18, 0.14, 6)
		for k in 4:
			kit.box("sail", at.call(0.0, 0.9, -1.5 + k * 0.6), Vector3(0.6, 0.4, 0.45), b * Basis(Vector3.UP, k * 0.7), 1.0, 0.8)   # 船上没卸完的几袋粮
	else:
		kit.cylinder("timber", at.call(0, 0.7, length * 0.05), at.call(0, length * 0.8, length * 0.05), 0.2, 0.13, 6)
		kit.cylinder("timber", at.call(-beam * 0.9, length * 0.62, length * 0.05), at.call(beam * 0.9, length * 0.62, length * 0.05), 0.08, 0.08, 5)
		kit.box("sail", at.call(0, length * 0.6, length * 0.05), Vector3(beam * 1.7, 0.4, 0.4), b, 1.0, 0.85)    # 卷起来捆在横桁上的帆
		kit.cylinder("rope", at.call(0, length * 0.78, length * 0.05), at.call(0, 1.4, length * 0.46), 0.025, 0.025, 3)
		kit.cylinder("rope", at.call(0, length * 0.78, length * 0.05), at.call(0, 1.6, -length * 0.44), 0.025, 0.025, 3)


static func _works(root: Node3D, rect: Rect2) -> void:
	var kit := _works_kit(rect)
	var mi := kit.build(mats())
	mi.name = "HarborWorks_%d_%d" % [int(rect.position.x), int(rect.position.y)]
	root.add_child(mi)


## 停在河口的两条船：跟着潮位上下（组 tide_float，Harbor.set_tide 挪）。同步搭（船在深水里、离岸远，一共两个网格）
static func ships(parent: Node3D) -> void:
	for k in SHIPS.size():
		var s: Array = SHIPS[k]
		var kit := MeshKit.new()
		_hull(kit, Vector3.ZERO, Basis(Vector3.UP, deg_to_rad(float(s[1]))), float(s[2]))
		var mi := kit.build(mats())
		mi.name = "Ship%d" % k
		mi.position = Vector3((s[0] as Vector2).x, Harbor.tide() - 0.55, (s[0] as Vector2).y)
		mi.add_to_group("tide_float")
		mi.set_meta("float_off", -0.55)
		parent.add_child(mi)


## 码头上、鱼市里、会馆门口的零碎：木桶、板条箱、麻袋、空车、渔篓（Decor，碰撞同步）
static func props_decor(rect := Rect2()) -> Decor:
	var d := Decor.new()
	var inside := func(p: Vector2) -> bool: return rect.size == Vector2.ZERO or rect.has_point(p)
	var items := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7205
	for p: Array in piers():                                             # 每座栈桥头上一堆货
		var a: Vector2 = p[0]
		for k in 4:
			var q := a + Vector2(-2.2 - rng.randf_range(0.0, 1.5), rng.randf_range(-2.5, 2.5) + (3.2 if k < 2 else -3.2))
			items.append(["barrel" if k % 2 == 0 else "crate", q, rng.randf_range(0.0, PI)])
	items.append_array([["cart", Vector2(-74.0, 33.0), 0.2, "none"], ["cart", Vector2(-88.0, 33.5), -0.3, "none"],     # 盐仓前空着两辆车（粮船没来）
		["creel", Vector2(-38.0, 34.5), 0.3], ["creel", Vector2(-37.0, 35.2), 1.1], ["creel", Vector2(-31.0, 34.8), 2.0],
		["sack", Vector2(-60.0, 38.0), 0.5], ["sack", Vector2(-59.4, 38.6), 1.9],
		["barrel", Vector2(-46.0, -60.5), 0.0], ["crate", Vector2(-20.0, -60.6), 0.6]])
	for it: Array in items:
		var p: Vector2 = it[1]
		if not inside.call(p) or HarborLayout.street_d(p) < HarborLayout.STREET_HALF - 0.6 and str(it[0]) != "cart":
			continue
		if ground(p) < 1.0 or HarborLayout.river_edge(p) < HarborLayout.RIVER_BANK + 0.8:
			continue
		var pos := Vector3(p.x, ground(p), p.y)
		match str(it[0]):
			"cart":
				d.cart(pos, float(it[2]), str(it[3]))
			"barrel":
				d.barrel(pos)
			"crate":
				d.crate(pos, float(it[2]))
			"sack":
				d.sack(pos, float(it[2]))
			"creel":
				d.creel(pos, float(it[2]))
	return d


static func _props(root: Node3D, rect: Rect2) -> void:
	var d := props_decor(rect)
	var mi := d.kit.build(d.mats)
	mi.name = "HarborProps_%d_%d" % [int(rect.position.x), int(rect.position.y)]
	root.add_child(mi)


## 地图册「本地」页上的房子
static func map_shapes() -> Array:
	var out := []
	for h: Dictionary in houses():
		out.append({"k": "house", "pts": footprint(h)})
	out.append({"k": "house", "pts": House.footprint(Vector3(key_front().x, 0, key_front().y), 180.0, KEY_W, KEY_D), "label": "钥楼"})
	out.append({"k": "house", "pts": House.footprint(Vector3(guild_front().x, 0, guild_front().y), 0.0, GUILD_W, GUILD_D), "label": "渡工行会会馆"})
	out.append({"k": "house", "pts": House.footprint(Vector3(TAVERN_FRONT.x, 0, TAVERN_FRONT.y), 90.0, TAVERN_W, TAVERN_D), "label": "「咸潮」酒馆"})
	out.append({"k": "house", "pts": House.footprint(Vector3(prison_front().x, 0, prison_front().y), PRISON_YAW, PRISON_W, PRISON_D), "label": "债牢"})
	for sh: Array in SHEDS:
		out.append({"k": "house", "pts": House.footprint(Vector3((sh[0] as Vector2).x, 0, (sh[0] as Vector2).y + SHED_D * 0.5), float(sh[1]), SHED_W, SHED_D)})
	for p: Array in piers():
		out.append({"k": "road", "pts": Harbor._strip(p[0], p[1], PIER_W * 0.5)})
	return out
