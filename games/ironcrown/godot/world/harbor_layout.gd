class_name HarborLayout
extends RefCounted
## 双钥港连片地图的布局（路线图 7.1，D10-B、D12；STORY.md 7.2）：只放数据和「这一点有多高」，搭场景在 world/harbor.gd。
## 第四张连片地图：灰鲸河在这里散成几股流进海。河从北边进来、越往南越宽，在地图南边入海；
## 西岸是城（石砌的码头边比水面高三四米，往西北慢慢抬高），两条石砌的潮沟从城里穿过、通到河里（7.2 架木闸和小桥）；
## 城南边是退潮时露出来的大片泥滩，再往南是海；东岸是低低的盐沼，一道沙嘴从东岸往西南伸进海里，尽头一块礁石上是灯塔（7.2）。
## 坐标：x 往东、-z 往北（和别的区域一样），y 是高度（米），0 = 平均潮位附近。整张图 260 × 220 米，地形每 1 米一个采样点（高度场）。
##
## 高度 = 城的台地（码头边 +2.2，往西北抬到 +5）→ 南边码头的石岸陡降到泥滩（-1.3）→ 泥滩外缓缓降成海底（-4）；
## 东岸盐沼（+0.4）、沙嘴（沙脊 +1.4，两边缓缓入水）；河道刻下去（河床 -3.8）；潮沟刻下去（沟底 -1.7，两边几乎是竖的）。
## 地面贴图的分布另外记在每个采样点上（mask）：r 石子路和码头（铺石）、g 沙（沙嘴、海滩）、b 遮蔽（沟底、岸脚暗一点）；
## 泥（泥滩、沟底、河床）和陡岸的卵石按高度、坡度由着色器换（shaders/harbor_ground.gdshader）。
## 潮位按时段（Harbor.TIDE）：白天涨、夜里退——退潮时泥滩和潮沟底露出来能走（泥里走得慢），涨潮时盖在水下（浅水，走得更慢）；
## 河道和泥滩外的深水走不进去（四边的墙以外，沿深水边另有一圈看不见的墙，Harbor._deep_walls）。

const BOUNDS := Rect2(-130, -110, 260, 220)
const STEP := 1.0
const NX := 261                         # -130..130
const NZ := 221                         # -110..110
const CHUNK := 64.0
const WALL_INSET := 5.0
const WALL_H := 40.0

## 灰鲸河：从北边地图外流进来，往南越来越宽，在南边入海。半宽按 z 从 RIVER_HALF_N 渐变到 RIVER_HALF_S
const RIVER := [Vector2(46.0, -130.0), Vector2(41.0, -80.0), Vector2(37.0, -40.0), Vector2(36.0, 0.0), Vector2(40.0, 40.0), Vector2(50.0, 76.0), Vector2(62.0, 130.0)]
const RIVER_HALF_N := 9.0
const RIVER_HALF_S := 22.0
const RIVER_BANK := 3.5                 # 西岸是码头的石岸（陡）；东岸由盐沼缓缓接下去（east_bank）
const RIVER_BED := -3.8

## 城：码头边的台地高度、往西北抬高多少
const TOWN_Y := 2.2
const TOWN_RISE := 2.8
## 城南边的石岸（码头边，往南陡降到泥滩）：QUAY_Z + 一点起伏；泥滩到 FLATS_END_Z 为止，再往南是海
const QUAY_Z := 48.0
const QUAY_DROP := 2.5                  # 石岸从台地降到泥滩用几米
const FLATS_Y := -1.3
const FLATS_END_Z := 84.0
const SEA_Y := -4.0
## 东岸的盐沼
const MARSH_Y := 0.4
## 沙嘴：从东岸往西南伸进海里，尽头是灯塔那块礁石
const SPIT := [Vector2(102.0, -4.0), Vector2(92.0, 30.0), Vector2(80.0, 62.0), Vector2(66.0, 90.0)]
const SPIT_HALF := 10.0
const SPIT_Y := 1.4
const LIGHTHOUSE := Vector2(63.0, 95.0)
const LIGHTHOUSE_R := 7.0
const LIGHTHOUSE_Y := 2.6
## 潮沟：从城里通到河里的两条石砌水道（7.2 架木闸、小桥）。半宽、沟底、岸宽（几乎竖着）
const CANALS := [
	[Vector2(-94.0, -46.0), Vector2(-52.0, -49.0), Vector2(-12.0, -45.0), Vector2(30.0, -42.0)],     # 北潮沟：钥楼背后（金库之夜从这儿摸过去，7.5）
	[Vector2(-76.0, 6.0), Vector2(-34.0, 10.0), Vector2(4.0, 13.0), Vector2(30.0, 12.0)],             # 南潮沟：穿过鱼市
]
const CANAL_HALF := 3.2
const CANAL_BED := -1.7
const CANAL_BANK := 0.9
## 深水：比这个低的地方走不进去（河道、泥滩外的海）
const DEEP_Y := -2.6
## 城南边石岸下到泥滩的石阶（7.2）：x、宽；石岸那一段的地形改成一道直的斜坡（不然石阶底下是 60° 的陡坎，人站不住）
const STAIRS := [-28.0, -88.0]
const STAIR_HALF := 1.4
const STAIR_UP := 3.5           # 斜坡从石岸上沿往北多远开始
const STAIR_DOWN := 2.0         # 到石岸脚往南多远

## 地点（7.2 起放房子）：中心
const KEY_HOUSE := Vector2(-34.0, -55.0)        # 钥楼：钥楼街和北潮沟中间，正面朝北对着街、背后的墙直接立在潮沟边上（水门，7.5）
const GUILD := Vector2(-4.0, 27.0)              # 渡工行会的港口会馆：南潮沟南边、鱼市东头，正面朝南（7.2：原来 (10, 30) 压在码头街上）
const PRISON := Vector2(-106.0, -88.0)          # 债牢：城的西北角
const QUAY := Vector2(18.0, -10.0)              # 木栈码头（第四章从这儿上岸）
const FISH := Vector2(-40.0, 38.0)              # 鱼市、晒鱼架、盐仓：城南边靠泥滩
const PADS := [[KEY_HOUSE, 10.0, 5.0], [GUILD, 9.0, 5.0], [PRISON, 9.0, 6.0]]

## 街（铺石的路）：[点...]，路面半宽 STREET_HALF
const STREETS := [
	[Vector2(22.0, -100.0), Vector2(16.0, -60.0), Vector2(13.0, -20.0), Vector2(13.0, 20.0), Vector2(12.0, 44.0)],      # 码头街：沿河一整条
	[Vector2(-100.0, -60.0), Vector2(-60.0, -62.0), Vector2(-34.0, -62.0), Vector2(0.0, -58.0), Vector2(16.0, -58.0)],   # 钥楼街：北潮沟北边
	[Vector2(-60.0, -62.0), Vector2(-62.0, -20.0), Vector2(-58.0, 0.0), Vector2(-50.0, 30.0), Vector2(-40.0, 40.0)],     # 城中斜着往南下到鱼市的街
	[Vector2(-58.0, -10.0), Vector2(-20.0, -14.0), Vector2(13.0, -16.0)],                                               # 城中往码头的横街
	[Vector2(-40.0, 38.0), Vector2(-10.0, 38.0), Vector2(12.0, 44.0)],                                                  # 鱼市沿着石岸
	[Vector2(-100.0, -60.0), Vector2(-106.0, -88.0)],                                                                   # 往债牢
	[Vector2(-112.0, -36.0), Vector2(-90.0, -32.0), Vector2(-62.0, -34.0)],                                             # 西边的小巷（7.2）
	[Vector2(-28.0, -38.0), Vector2(-26.0, -10.0), Vector2(-22.0, 22.0), Vector2(-20.0, 38.0)],                       # 城中南北的小巷：跨南潮沟（7.2）
	[Vector2(-96.0, -10.0), Vector2(-92.0, 14.0), Vector2(-86.0, 36.0)],                                                # 西南的小巷：跨南潮沟西头附近、下到盐仓（7.2）
]
const STREET_HALF := 2.4
const STREET_BLEND := 2.0

## 出生点：[位置 (x, z), 朝向（度；0 = 面朝北，-90 = 面朝东）]
const SPAWN_XZ := {
	"quay": [Vector2(16.0, -8.0), -100.0],          # 木栈码头上岸（从河上坐船下来）：面朝河、对岸的盐沼和沙嘴
	"keyhouse": [Vector2(-34.0, -64.0), 180.0],     # 钥楼街：面朝钥楼（往南）
	"fishmarket": [Vector2(-34.0, 32.0), 160.0],    # 鱼市：面朝南边的泥滩和海
	"guild": [Vector2(-4.0, 37.0), 0.0],           # 会馆门口：面朝会馆（往北）
	"keyhouse_door": [Vector2(-34.0, -60.9), 0.0],     # 出了钥楼：门外钥楼街上，面朝北（7.3；钥楼正面在 z = -59.3，HarborTown.key_front）
	"guild_door": [Vector2(-4.0, 33.6), 180.0],        # 出了会馆：门外，面朝南（鱼市）
	"prison_door": [Vector2(-104.6, -81.6), -168.0],   # 出了债牢：门外，面朝东南（往城里去的街）
	"tavern_door": [Vector2(11.1, -8.0), -90.0],       # 出了「咸潮」酒馆：门外码头街上，面朝东（河）
	"keyhouse_gate": [Vector2(-61.0, -41.6), 180.0],   # 金库之夜出来（7.5）：顺着北潮沟摸回西边那座桥，从桥头爬上来，站在桥南头
	"lighthouse": [Vector2(66.4, 92.4), 128.0],        # 坐摆渡的船到灯塔（7.7）：沙嘴尽头外那块礁石，面朝灯塔
}

## ?view=N 的固定机位：[位置（x, 离地高度, z）, 水平朝向, 俯仰]——截图、冒烟用
const VIEW_SPEC := [
	[Vector3(16.0, 1.7, -8.0), -100.0, 0.0],        # 0 码头上岸：灰鲸河、对岸的盐沼、远处的沙嘴
	[Vector3(-10.0, 1.7, 39.0), 170.0, -4.0],       # 1 鱼市石岸上往南：泥滩、海、东南边的沙嘴和灯塔那块礁石
	[Vector3(-30.0, 1.7, -52.0), -80.0, -6.0],      # 2 钥楼背后、北潮沟边往东：潮沟一直通到河
	[Vector3(84.0, 1.7, 52.0), 150.0, -2.0],        # 3 沙嘴上往西南：沙嘴尽头的礁石、海
	[Vector3(-100.0, 1.7, -96.0), -135.0, -3.0],     # 4 债牢那边（西北角高处）往东南看整座城（7.2：原来 -45 朝东北、对着地图边）
	[Vector3(14.0, 1.7, 40.0), -170.0, -3.0],       # 5 码头南头往南：河口、两边的泥滩
	[Vector3(-60.0, 1.7, 0.0), -80.0, -6.0],        # 6 南潮沟西头往东
	[Vector3(-54.0, 1.7, -62.0), -92.0, 6.0],       # 7 钥楼街西头往东：两边的石头商行、钥楼和门口的告示（7.2）
	[Vector3(-48.0, 1.7, 37.0), 20.0, 2.0],         # 8 鱼市：晒鱼架、往北的小巷（7.2）
	[Vector3(67.6, 1.7, 91.0), 125.0, 12.0],        # 9 灯塔礁石上（7.7）：灯塔、塔门口的老蒂博
]
const VIEW_NAMES := ["码头上岸", "鱼市石岸", "北潮沟", "沙嘴上", "城西北角", "河口", "南潮沟", "钥楼街", "鱼市", "灯塔礁石"]

const SEA_DIR := Vector2(0.25, 1.0)              # 海在南边（远景，Harbor.far_height）


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


static var _noise_big: FastNoiseLite
static var _noise_small: FastNoiseLite


static func _noises() -> void:
	if _noise_big != null:
		return
	_noise_big = FastNoiseLite.new()
	_noise_big.seed = 7101
	_noise_big.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_big.frequency = 0.008
	_noise_big.fractal_octaves = 2
	_noise_small = FastNoiseLite.new()
	_noise_small.seed = 711
	_noise_small.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_small.frequency = 0.07
	_noise_small.fractal_octaves = 2


## 点到折线的最近距离、在哪一段、段上哪儿
static func poly_hit(p: Vector2, pts: Array) -> Dictionary:
	var best := {"d": INF, "i": -1, "t": 0.0}
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best.d:
			best = {"d": d, "i": i, "t": t}
	return best


## 河在这一段有多宽（半宽）
static func river_half(z: float) -> float:
	return lerpf(RIVER_HALF_N, RIVER_HALF_S, clampf((z - BOUNDS.position.y) / BOUNDS.size.y, 0.0, 1.0))


## 河中线的 x（按 z 插值；河基本南北走向）
static func river_x(z: float) -> float:
	for i in RIVER.size() - 1:
		var a: Vector2 = RIVER[i]
		var b: Vector2 = RIVER[i + 1]
		if z >= a.y and z <= b.y:
			return lerpf(a.x, b.x, (z - a.y) / (b.y - a.y))
	return (RIVER[0] as Vector2).x if z < (RIVER[0] as Vector2).y else (RIVER[RIVER.size() - 1] as Vector2).x


## 到河中线多远（横着量；> 0 东边，< 0 西边），减去这一段的半宽 = 离水边多远（< 0 在河里）
static func river_edge(p: Vector2) -> float:
	_noises()
	return absf(p.x - river_x(p.y)) - river_half(p.y) + 0.8 * _noise_small.get_noise_2d(p.x * 0.4, p.y * 0.4)


## 城南边石岸的 z（再往南是泥滩）
static func quay_z(x: float) -> float:
	return QUAY_Z + 3.0 * sin(x / 19.0) + 1.5 * sin(x / 7.3)


static func flats_end_z(x: float) -> float:
	return FLATS_END_Z + 6.0 * sin(x / 31.0 + 0.7)


## 第 idx 条潮沟中线在 x 处的 z（潮沟大体东西走向）
static func canal_z_at(x: float, idx: int) -> float:
	var cn: Array = CANALS[idx]
	for i in cn.size() - 1:
		var a: Vector2 = cn[i]
		var b: Vector2 = cn[i + 1]
		if x >= a.x and x <= b.x:
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return (cn[0] as Vector2).y if x < (cn[0] as Vector2).x else (cn[cn.size() - 1] as Vector2).y


## 石阶的斜坡：[上头 z, 下头 z]
static func stair_span(x: float) -> Vector2:
	return Vector2(quay_z(x) - QUAY_DROP - STAIR_UP, quay_z(x) + STAIR_DOWN)


static func canal_d(p: Vector2) -> float:
	var d := INF
	for c in CANALS:
		d = minf(d, float(poly_hit(p, c).d))
	return d


static func street_d(p: Vector2) -> float:
	var d := INF
	for r in STREETS:
		d = minf(d, float(poly_hit(p, r).d))
	return d


static func spit_d(p: Vector2) -> float:
	return float(poly_hit(p, SPIT).d)


## 西岸（城）还是东岸（盐沼、沙嘴）
static func west_bank(p: Vector2) -> bool:
	return p.x < river_x(p.y)


## 自然地面（还没刻河、刻潮沟）
static func natural(x: float, z: float) -> float:
	_noises()
	var p := Vector2(x, z)
	var y: float
	if west_bank(p):
		var nw := clampf((-(x + 20.0) - (z + 10.0)) / 160.0, 0.0, 1.0)          # 往西北抬高
		y = TOWN_Y + TOWN_RISE * _smooth(nw) + 0.25 * _noise_big.get_noise_2d(x, z) + 0.05 * _noise_small.get_noise_2d(x, z)
		var qz := quay_z(x)
		if z > qz - QUAY_DROP:                                                  # 石岸往南陡降到泥滩
			var k := _smooth(clampf((z - (qz - QUAY_DROP)) / QUAY_DROP, 0.0, 1.0))
			var fl := FLATS_Y + 0.25 * _noise_big.get_noise_2d(x * 2.0, z * 2.0) + 0.06 * _noise_small.get_noise_2d(x, z)
			var fe := flats_end_z(x)
			if z > fe:                                                          # 泥滩外缓缓降成海底
				fl = lerpf(fl, SEA_Y, _smooth(clampf((z - fe) / 14.0, 0.0, 1.0)))
			y = lerpf(y, fl, k)
	else:
		y = MARSH_Y + 0.3 * _noise_big.get_noise_2d(x, z) + 0.08 * _noise_small.get_noise_2d(x * 1.5, z * 1.5)
		if z > 20.0:                                                            # 东岸往南也成了泥滩、再成海
			var fl := FLATS_Y + 0.25 * _noise_big.get_noise_2d(x * 2.0, z * 2.0)
			if z > flats_end_z(x) - 10.0:
				fl = lerpf(fl, SEA_Y, _smooth(clampf((z - flats_end_z(x) + 10.0) / 14.0, 0.0, 1.0)))
			y = lerpf(y, fl, _smooth(clampf((z - 20.0) / 16.0, 0.0, 1.0)))
	var sd := spit_d(p)                                                         # 沙嘴：一道沙脊
	if sd < SPIT_HALF * 2.2:
		var k := _smooth(clampf(1.0 - sd / (SPIT_HALF * 2.2), 0.0, 1.0))
		y = maxf(y, lerpf(FLATS_Y - 0.4, SPIT_Y + 0.3 * _noise_big.get_noise_2d(x * 3.0, z * 3.0), k))
	if west_bank(p):                                                           # 石阶：石岸那一段改成直的斜坡
		for sx: float in STAIRS:
			var dx := absf(x - sx)
			if dx < STAIR_HALF + 0.8:
				var sp := stair_span(sx)
				if z > sp.x and z < sp.y + 1.0:
					var top := TOWN_Y + 0.25 * _noise_big.get_noise_2d(sx, sp.x)
					var t := clampf((z - sp.x) / (sp.y - sp.x), 0.0, 1.0)
					var ramp := lerpf(top, FLATS_Y, t)
					var k := _smooth(clampf((STAIR_HALF + 0.8 - dx) / 0.8, 0.0, 1.0))
					y = lerpf(y, ramp, k) if z < sp.y else y
	var ld := p.distance_to(LIGHTHOUSE)                                         # 灯塔那块礁石
	if ld < LIGHTHOUSE_R + 8.0:
		var k := _smooth(clampf((LIGHTHOUSE_R + 8.0 - ld) / 8.0, 0.0, 1.0))
		y = maxf(y, lerpf(FLATS_Y, LIGHTHOUSE_Y + 0.2 * _noise_small.get_noise_2d(x * 3.0, z * 3.0), k))
	return y


## 最终高度（地形网格、碰撞、出生点都用它；Harbor 一次算好整张高度场）
static func height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var y := natural(x, z)
	for pad in PADS:                                                            # 钥楼、会馆、债牢底下压平
		var c: Vector2 = pad[0]
		var d := p.distance_to(c)
		var outer := float(pad[1]) + float(pad[2])
		if d < outer:
			y = lerpf(y, natural(c.x, c.y), _smooth(clampf((outer - d) / float(pad[2]), 0.0, 1.0)))
	var sd := street_d(p)                                                       # 街面：抹平小起伏
	if sd < STREET_HALF + STREET_BLEND and y > 1.0:
		var k := 1.0 if sd <= STREET_HALF else _smooth(1.0 - (sd - STREET_HALF) / STREET_BLEND)
		y = lerpf(y, y - 0.05 * _noise_small.get_noise_2d(x, z) - 0.04, k * 0.8)
	var cd := canal_d(p)                                                        # 潮沟：两边几乎是竖的石岸、沟底平
	if cd < CANAL_HALF + CANAL_BANK:
		var k := 1.0 if cd <= CANAL_HALF else 1.0 - _smooth((cd - CANAL_HALF) / CANAL_BANK)
		y = lerpf(y, CANAL_BED + 0.08 * _noise_small.get_noise_2d(x * 2.0, z * 2.0), k)
	var re := river_edge(p)                                                     # 灰鲸河：西岸陡（码头的石岸）、东岸缓
	var bank := RIVER_BANK if west_bank(p) else 12.0
	if re < bank:
		var k := 1.0 if re <= 0.0 else 1.0 - _smooth(re / bank)
		k *= _smooth(clampf((p.distance_to(LIGHTHOUSE) - LIGHTHOUSE_R) / 2.5, 0.0, 1.0))   # 灯塔那块礁石露在河口外（7.7：原先被河道刻没了）
		y = lerpf(y, RIVER_BED + 0.3 * _noise_small.get_noise_2d(x * 0.5, z * 0.5), k) if y > RIVER_BED else y
	return y


## 地面贴图的分布（0..1）：x = 铺石（街、码头边），y = 沙（沙嘴、海滩），z = 遮蔽
static func masks(x: float, z: float) -> Vector3:
	var p := Vector2(x, z)
	var y := height(x, z)
	var sd := street_d(p)
	var paved := _smooth(clampf((STREET_HALF + 0.6 - sd) / 1.2, 0.0, 1.0))
	if west_bank(p):                                                           # 码头边一条铺石（沿河、沿南边石岸、沿潮沟）
		var re := river_edge(p)
		paved = maxf(paved, _smooth(clampf((RIVER_BANK + 4.0 - re) / 2.0, 0.0, 1.0)) * float(y > 1.0))
		var qe := quay_z(x) - QUAY_DROP                                         # 南边石岸的上沿：往北 4 米一条铺石
		paved = maxf(paved, _smooth(clampf((z - (qe - 4.0)) / 1.5, 0.0, 1.0)) * float(z < qe + 0.3) * float(y > 1.0))
		paved = maxf(paved, _smooth(clampf((CANAL_HALF + CANAL_BANK + 3.0 - canal_d(p)) / 1.5, 0.0, 1.0)) * float(y > 1.0))
	var sand := 0.0
	var spd := spit_d(p)
	if spd < SPIT_HALF * 2.4:
		sand = _smooth(clampf((SPIT_HALF * 2.4 - spd) / (SPIT_HALF * 1.2), 0.0, 1.0))
	if not west_bank(p) and y < 0.9 and z > 10.0:
		sand = maxf(sand, 0.35)
	sand *= 1.0 - paved
	var occl := 1.0
	var cd := canal_d(p)
	if cd < CANAL_HALF + CANAL_BANK + 0.5:
		occl = 0.72
	elif y < FLATS_Y + 0.6 and west_bank(p) and z < quay_z(x) + 4.0:
		occl = 0.82                                                             # 石岸脚下
	return Vector3(paved, sand, occl)


## 脚下是什么（Surface 的 surface_at）：泥滩、沟底露出来是泥；水下是浅水
static func surface_at(pos: Vector3) -> String:
	if pos.y < Harbor.tide() - 0.05:
		return "shallows"
	if pos.y < 0.3 and masks(pos.x, pos.z).y < 0.5:
		return "mud"
	return ""


static func spawn_points() -> Dictionary:
	var out := {}
	for id in SPAWN_XZ:
		var s: Array = SPAWN_XZ[id]
		var p: Vector2 = s[0]
		out[id] = [Vector3(p.x, height(p.x, p.y) + 0.05, p.y), s[1]]
	return out


static func views() -> Array:
	var out := []
	for v: Array in VIEW_SPEC:
		var p: Vector3 = v[0]
		out.append([Vector3(p.x, height(p.x, p.z) + p.y, p.z), v[1], v[2]])
	return out
