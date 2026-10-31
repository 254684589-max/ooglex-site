class_name PlainLayout
extends RefCounted
## 金穗平原连片地图的布局（路线图 6.1a，D10-B、D12；STORY.md 6.2）：只放数据和「这一点有多高」，搭场景在 world/plain.gd。
## 第三张连片地图，地势平缓：麦河（灰鲸河下游的一条支流，宽而慢）从北往南弯过地图中间；西岸是佃农的村子麦渡（渡口在村南），
## 东岸是洛蒙德家的水磨坊和粮仓、再往东一道缓坡上是庄园；南边一道矮丘上是修道院坠星院；东北角是砧山来的路口（塞弗林营地，6.3）。
## 坐标：x 往东、-z 往北（和别的区域一样），y 是高度（米）。整张图 300 × 260 米，地形每 1 米一个采样点（高度场）。
##
## 高度 = 缓缓的起伏（噪声，一两米）+ 庄园那道坡、修道院的矮丘 → 村子、磨坊、庄园、修道院、营地压平 → 路面抹平 → 麦河刻下去（河床平、两岸是斜的泥岸）。
## 地面贴图的分布另外记在每个采样点上（mask）：r 路和踩出来的地（泥雪）、g 田（收割后的麦茬地：着色器在田里画一垄一垄的麦茬露出雪）、b 遮蔽（河岸、凹处暗一点）；
## 陡处（河岸）由着色器按坡度换成泥岸。

const BOUNDS := Rect2(-150, -130, 300, 260)
const STEP := 1.0
const NX := 301                         # -150..150
const NZ := 261                         # -130..130
const CHUNK := 64.0
const WALL_INSET := 5.0
const WALL_H := 40.0

## 麦河：从北边地图外流进来，弯两道，往南流出地图。HALF = 水面半宽，BANK = 两岸斜坡宽，DEPTH = 水面比田低多少
const RIVER := [Vector2(-26.0, -150.0), Vector2(-14.0, -100.0), Vector2(-22.0, -58.0), Vector2(-6.0, -16.0), Vector2(6.0, 24.0),
	Vector2(-4.0, 66.0), Vector2(8.0, 108.0), Vector2(16.0, 150.0)]
const RIVER_HALF := 7.5
const RIVER_BANK := 10.0               # 泥岸缓一点（6 米时像一堵墙，截图）
const RIVER_DEPTH := 2.2
const WATER_Y := -1.9                   # 水面高度（河床 -2.6 附近，冬天水浅）

## 地点（中心、半径、压平到的高度：NAN = 按那儿原来的高度）
const VILLAGE := Vector2(-58.0, 28.0)   # 麦渡（佃农村，6.2）
const VILLAGE_R := 26.0
const DOCK := Vector2(-20.0, 52.0)      # 麦渡的渡口：西岸，村子东南（第三章从这里上岸）
const MILL := Vector2(18.0, -12.0)      # 水磨坊（6.3）：东岸紧贴河，水渠从上游引过来
const MILL_R := 18.0
const GRANARY := Vector2(32.0, -30.0)   # 三座粮仓，磨坊上头
const MANOR := Vector2(76.0, -48.0)     # 洛蒙德庄园（6.3）：东边缓坡上
const MANOR_R := 24.0
const MANOR_RISE := 5.5                 # 庄园那道坡比平原高多少
const ABBEY := Vector2(44.0, 92.0)      # 坠星院（6.2）：南边的矮丘顶上
const ABBEY_R := 18.0
const ABBEY_HILL := 7.0
const ABBEY_HILL_R := 72.0             # 矮丘坡缓（46 米时四边陡、像一块台地，截图）
const CAMP := Vector2(108.0, -100.0)    # 塞弗林营地（6.3）：东北角，砧山来的路口
const CAMP_R := 22.0
const BRIDGE := [Vector2(-24.0, 10.0), Vector2(12.0, 4.0)]   # 木桥（6.2 搭）：村子过河到磨坊

## 路（村路、田埂上的大车道）：[点...]，路面半宽 ROAD_HALF
const ROADS := [
	[Vector2(-20.0, 52.0), Vector2(-40.0, 40.0), Vector2(-58.0, 28.0)],                                # 渡口 → 麦渡
	[Vector2(-58.0, 28.0), Vector2(-40.0, 14.0), Vector2(-24.0, 10.0)],                                # 麦渡 → 桥西头
	[Vector2(12.0, 4.0), Vector2(18.0, -6.0)],                                                          # 桥东头 → 磨坊
	[Vector2(18.0, -6.0), Vector2(32.0, -26.0), Vector2(54.0, -40.0), Vector2(76.0, -48.0)],          # 磨坊 → 粮仓 → 庄园
	[Vector2(76.0, -48.0), Vector2(92.0, -74.0), Vector2(108.0, -100.0), Vector2(132.0, -130.0)],     # 庄园 → 塞弗林营地 → 往砧山
	[Vector2(12.0, 4.0), Vector2(26.0, 40.0), Vector2(38.0, 72.0), Vector2(44.0, 92.0)],              # 桥东头 → 坠星院
	[Vector2(-58.0, 28.0), Vector2(-70.0, -10.0), Vector2(-84.0, -60.0), Vector2(-96.0, -130.0)],     # 麦渡 → 往北（出地图）
]
const ROAD_HALF := 2.0
const ROAD_BLEND := 4.0

## 出生点：[位置 (x, z), 朝向（度）]
const SPAWN_XZ := {
	"dock": [Vector2(-22.0, 46.0), 20.0],          # 渡口上岸：面朝北边的村子和远处的磨坊
	"village": [Vector2(-50.0, 22.0), 60.0],
	"mill": [Vector2(26.0, -4.0), -30.0],
	"manor": [Vector2(66.0, -38.0), 200.0],
	"abbey": [Vector2(40.0, 80.0), 170.0],
}

## ?view=N 的固定机位：[位置（x, 离地高度, z）, 水平朝向, 俯仰]——截图、冒烟用
const VIEW_SPEC := [
	[Vector3(-22.0, 1.7, 48.0), 18.0, 1.0],         # 0 渡口上岸：河、对岸的田、远处的磨坊和庄园那道坡
	[Vector3(-30.0, 1.7, 6.0), -70.0, 0.0],         # 1 桥西头往东看：麦河、磨坊那片
	[Vector3(4.0, 1.7, -50.0), 200.0, -2.0],        # 2 东岸河边往南：弯过去的河、两岸的麦茬地
	[Vector3(84.0, 1.7, -42.0), 108.0, -6.0],       # 3 庄园坡上往西看整片平原
	[Vector3(46.0, 1.7, 84.0), 175.0, -5.0],        # 4 坠星院的丘顶往北：平原、河、远处的砧山
	[Vector3(-90.0, 1.7, -40.0), 60.0, 0.0],        # 5 西北的田里往东北：砧山的黑影
	[Vector3(-56.0, 1.7, 40.0), 20.0, 0.0],         # 6 麦渡村南往北
]
const VIEW_NAMES := ["渡口", "桥西头", "东岸河边", "庄园坡上", "坠星院丘顶", "西北的田", "麦渡村南"]

const ANVIL_DIR := Vector2(0.62, -0.78)         # 砧山在东北（远景，Plain._far）


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


static var _noise_big: FastNoiseLite
static var _noise_small: FastNoiseLite
static var _noise_field: FastNoiseLite


static func _noises() -> void:
	if _noise_big != null:
		return
	_noise_big = FastNoiseLite.new()                # 缓缓的起伏：上百米一个包
	_noise_big.seed = 3061
	_noise_big.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_big.frequency = 0.006
	_noise_big.fractal_octaves = 2
	_noise_small = FastNoiseLite.new()              # 小起伏：田里的垄、雪堆
	_noise_small.seed = 361
	_noise_small.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_small.frequency = 0.06
	_noise_small.fractal_octaves = 2
	_noise_field = FastNoiseLite.new()              # 田块边上的雪厚薄
	_noise_field.seed = 6101
	_noise_field.frequency = 0.03
	_noise_field.fractal_octaves = 2


## 自然地面（还没压平、切路、刻河）：缓缓的起伏 + 庄园那道坡 + 修道院的矮丘；往东北（砧山那边）慢慢抬一点
static func natural(x: float, z: float) -> float:
	_noises()
	var y := 1.6 * _noise_big.get_noise_2d(x, z) + 0.18 * _noise_small.get_noise_2d(x, z)
	y += clampf((x - z) / 260.0, -0.4, 1.0) * 1.2
	var dm := Vector2(x, z).distance_to(MANOR + Vector2(10.0, -6.0))
	y += MANOR_RISE * _smooth(clampf(1.0 - (dm - 14.0) / 70.0, 0.0, 1.0))
	var da := Vector2(x, z).distance_to(ABBEY)
	var hk := clampf(1.0 - da / ABBEY_HILL_R, 0.0, 1.0)
	y += ABBEY_HILL * hk * hk * (3.0 - 2.0 * hk) * (0.6 + 0.4 * hk)       # 顶上圆、坡脚拖得长
	return y


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


## 到麦河中线多远（米）
static func river_d(p: Vector2) -> float:
	_noises()
	return float(poly_hit(p, RIVER).d) + 1.2 * _noise_small.get_noise_2d(p.x * 0.5, p.y * 0.5)   # 岸线不是一条直线


## 到最近的路多远
static func road_d(p: Vector2) -> float:
	var d := INF
	for r in ROADS:
		d = minf(d, float(poly_hit(p, r).d))
	return d


## 压平的地方：[中心, 半径, 过渡宽]
static func pads() -> Array:
	return [[VILLAGE, VILLAGE_R, 14.0], [MILL, 12.0, 8.0], [MANOR, MANOR_R, 14.0], [CAMP, CAMP_R, 12.0], [DOCK, 8.0, 6.0]]   # 修道院不压：丘顶本来就圆（压平了四边一圈陡坎，截图）


## 最终高度（地形网格、碰撞、出生点都用它；Plain 一次算好整张高度场）
static func height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var y := natural(x, z)
	for pad in pads():
		var c: Vector2 = pad[0]
		var d := p.distance_to(c)
		var outer := float(pad[1]) + float(pad[2])
		if d < outer:
			var py := natural(c.x, c.y) + 0.15
			var k := _smooth(clampf((outer - d) / float(pad[2]), 0.0, 1.0))
			y = lerpf(y, py + 0.08 * _noise_small.get_noise_2d(x * 2.0, z * 2.0), k)
	var rd := road_d(p)
	if rd < ROAD_HALF + ROAD_BLEND:                                  # 路面：抹平小起伏（大车道顺着地势走）
		var smooth_y := natural(x, z) - 0.18 * _noise_small.get_noise_2d(x, z)
		var k := 1.0 if rd <= ROAD_HALF else _smooth(1.0 - (rd - ROAD_HALF) / ROAD_BLEND)
		y = lerpf(y, smooth_y - 0.05, k * 0.8)
	var dr := river_d(p)                                             # 麦河：刻下去，河床平、两岸是斜的泥岸
	if dr < RIVER_HALF + RIVER_BANK:
		var bed := WATER_Y - 0.7
		var k := 1.0 if dr <= RIVER_HALF else 1.0 - _smooth((dr - RIVER_HALF) / RIVER_BANK)
		y = lerpf(y, bed, k)
	return y


## 地面贴图的分布（0..1）：x = 路和踩出来的地，y = 田（收割后的麦茬地，着色器画一垄一垄），z = 遮蔽
static func masks(x: float, z: float) -> Vector3:
	var p := Vector2(x, z)
	var rd := road_d(p)
	var track := _smooth(clampf((ROAD_HALF + 1.4 - rd) / 1.6, 0.0, 1.0))
	var dv := p.distance_to(VILLAGE)
	if dv < VILLAGE_R:                                               # 村里踩出来的泥雪（一块一块，不是整片）
		_noises()
		track = maxf(track, clampf(0.45 + 0.6 * _noise_field.get_noise_2d(x * 2.0, z * 2.0), 0.0, 1.0) * _smooth(clampf((VILLAGE_R - dv) / 8.0, 0.0, 1.0)))
	for c in [MILL, GRANARY, DOCK, CAMP]:
		var dc := p.distance_to(c)
		if dc < 12.0:
			track = maxf(track, _smooth(clampf((12.0 - dc) / 6.0, 0.0, 1.0)) * 0.85)
	var field := 1.0                                                 # 田：除了村子、庄园、修道院、营地、路、河边
	for pad in pads() + [[ABBEY, ABBEY_R, 12.0]]:
		var d := p.distance_to(pad[0])
		field = minf(field, _smooth(clampf((d - float(pad[1])) / 10.0, 0.0, 1.0)))
	field = minf(field, _smooth(clampf((river_d(p) - RIVER_HALF - RIVER_BANK - 3.0) / 6.0, 0.0, 1.0)))
	field = minf(field, _smooth(clampf((rd - ROAD_HALF - 1.0) / 2.0, 0.0, 1.0)))
	field *= 1.0 - track
	var occl := 1.0
	var dr := river_d(p)
	if dr < RIVER_HALF + RIVER_BANK + 1.0:
		occl = lerpf(0.78, 1.0, _smooth(clampf((dr - RIVER_HALF) / (RIVER_BANK + 1.0), 0.0, 1.0)))
	return Vector3(track, field, occl)


static func surface_at(_pos: Vector3) -> String:
	return "snow"


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
