class_name CrownLayout
extends RefCounted
## 冠城一角的布局（路线图 7.6，D10-B、D12；STORY.md 7.2「灰鲸河中游的岛城：一道石桥进桥门，桥门里是贫民区的一条斜街（挤、窄、晾着衣服、排队买面包）；
## 斜街上去是议事厅广场和钟楼；高墙后面的王宫只在远处」）：只放数据和「这一点有多高」，搭场景在 world/crown_city.gd。
## 第五张连片地图，只做冠城西头一角：灰鲸河在岛西头分成两股，从地图北边、西边、南边绕过去；西边是河西岸（行会的船在这儿靠岸），
## 一道石桥过西边那股河到桥门；岛上从桥门往东一路上坡，斜街弯弯曲曲爬到议事厅广场（比桥门高九米多）；王宫在东边地图外的高处，只画个影子。
## 坐标：x 往东、-z 往北，y 是高度（米），河面 RIVER_Y。整张图 180 × 160 米，每 1 米一个采样点。

const BOUNDS := Rect2(-90, -80, 180, 160)
const STEP := 1.0
const NX := 181
const NZ := 161
const CHUNK := 64.0
const WALL_INSET := 5.0
const WALL_H := 40.0

const RIVER_Y := -1.0                    # 河面（冠城在中游：没有潮）
const RIVER_BED := -3.6
const DEEP_Y := -2.4
const BANK_Y := 1.4                      # 河西岸、北岸、南岸
const WEST_BANK_X := -62.0               # 河西岸到这儿
const ISLAND_W := -44.0                  # 岛的西岸
const ISLAND_HALF_Z := 57.0              # 岛南北的半宽
const FAR_BANK_Z := 70.0                 # 北岸、南岸从这儿起
const SHORE := 3.0                       # 岛的石岸：几米内陡降到河床
const ISLAND_Y := 2.2                    # 岛西头（桥门）的地面
const SQUARE_Y := 11.6                   # 议事厅广场
const RISE_FROM := -38.0                 # 从这儿开始上坡
const RISE_TO := 34.0                    # 到这儿坡顶（广场西沿）

## 石桥：河西岸 → 桥门（过西边那股河）
const BRIDGE := [Vector2(-70.0, 0.0), Vector2(-40.0, 0.0)]
const BRIDGE_HALF := 2.6
## 城墙：岛西岸一道（桥门在 z = 0），往北、往南沿着岛边拐过去一截
const WALL_X := -40.5
const WALL_T := 2.2
const WALL_TOP := 8.0                    # 墙高（从墙脚的地面算）
const GATE_HALF := 2.4
## 斜街：桥门 → 广场，弯弯曲曲往上爬
const STREET := [Vector2(-37.0, 0.0), Vector2(-22.0, 5.0), Vector2(-8.0, -2.0), Vector2(6.0, 4.0), Vector2(20.0, -3.0), Vector2(34.0, -6.0)]
const STREET_HALF := 2.1
const STREET_BLEND := 1.6
## 斜街两边的小巷
const LANES := [
	[Vector2(-22.0, 5.0), Vector2(-26.0, 24.0), Vector2(-20.0, 42.0)],
	[Vector2(-8.0, -2.0), Vector2(-12.0, -22.0), Vector2(-6.0, -40.0)],
	[Vector2(20.0, -3.0), Vector2(18.0, 18.0), Vector2(26.0, 36.0)],
]
const LANE_HALF := 1.4
## 议事厅广场
const SQUARE := Rect2(34.0, -24.0, 44.0, 30.0)
const COUNCIL := Vector2(56.0, -30.0)    # 议事厅：广场北边，正面朝南（7.8 冬议在里面）
const COUNCIL_W := 24.0
const COUNCIL_D := 14.0
const BELL_TOWER := Vector2(80.0, -18.0) # 钟楼：广场东北角
## 斜街边上两栋认得出来的房子：[第几段, 段上哪儿 (0..1), 哪一边（1 = 南边、-1 = 北边）, 宽, 进深]
const BAKERY := [2, 0.45, 1.0, 8.0, 7.0]        # 面包坊：斜街南边，门口排着队（7.6）
const MATILDA := [3, 0.43, -1.0, 8.0, 8.0]      # 玛蒂尔达新盘下的小酒馆：斜街北边，正面朝着斜街

## 出生点：[位置 (x, z), 朝向（度；0 = 面朝北，-90 = 面朝东）]
const SPAWN_XZ := {
	"bridge": [Vector2(-76.0, 2.0), -90.0],          # 坐行会的船上来，在河西岸靠岸：面朝东边的石桥和桥门
	"gate": [Vector2(-33.0, 0.5), -90.0],            # 桥门里：面朝斜街
	"square": [Vector2(50.0, -4.0), 0.0],            # 广场：面朝北边的议事厅
	"council_door": [Vector2(56.0, -21.4), 180.0],   # 出了议事厅：门外广场上，面朝南
	"bell_door": [Vector2(75.6, -18.0), 90.0],       # 出了钟楼底下的档案馆（8.1）：钟楼西面门外，背对着门（面朝西、广场）
	"matilda_door": [Vector2(12.0, -0.5), 180.0],    # 出了玛蒂尔达的小酒馆：门外斜街上，背对着门（spawn_points 按 street_front 重算）
}

const VIEW_SPEC := [
	[Vector3(-76.0, 1.7, 2.0), -90.0, 4.0],         # 0 河西岸：石桥、桥门、后面往上爬的城
	[Vector3(-33.0, 1.7, 0.5), -80.0, 6.0],         # 1 桥门里往东：斜街
	[Vector3(4.0, 1.7, 3.0), -70.0, 8.0],           # 2 斜街当中往上：晾着的衣服、面包坊门口的队
	[Vector3(42.0, 1.7, 2.0), -20.0, 4.0],          # 3 广场西南角：议事厅、钟楼
	[Vector3(70.0, 1.7, -2.0), 120.0, -10.0],       # 4 广场东头往西看：整条斜街、桥门、河
	[Vector3(-56.0, 1.7, 0.0), -90.0, 10.0],        # 5 桥上：桥门的两座塔
	[Vector3(70.0, 1.7, -14.0), -75.0, 6.0],        # 6 钟楼门口（8.1）：大主祭、钟楼西面那道门
]
const VIEW_NAMES := ["河西岸", "桥门里", "斜街", "议事厅广场", "广场往西", "桥上", "钟楼门口"]

const PALACE_DIR := Vector2(1.0, -0.15)          # 王宫在东边（远景）


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


static var _noise_big: FastNoiseLite
static var _noise_small: FastNoiseLite


static func _noises() -> void:
	if _noise_big != null:
		return
	_noise_big = FastNoiseLite.new()
	_noise_big.seed = 7601
	_noise_big.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_big.frequency = 0.012
	_noise_small = FastNoiseLite.new()
	_noise_small.seed = 761
	_noise_small.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_small.frequency = 0.08


static func poly_hit(p: Vector2, pts: Array) -> Dictionary:
	return HarborLayout.poly_hit(p, pts)


## 岛的西岸、南北岸（有一点弯）
static func island_west(z: float) -> float:
	return ISLAND_W + 2.0 * sin(z / 17.0) + 1.0 * sin(z / 6.3)


static func island_half(x: float) -> float:
	return ISLAND_HALF_Z + 3.0 * sin(x / 21.0) + 1.0 * sin(x / 7.1)


## 离岛边多远（> 0 在岛上）
static func island_d(p: Vector2) -> float:
	return minf(p.x - island_west(p.y), island_half(p.x) - absf(p.y))


static func on_island(p: Vector2) -> bool:
	return island_d(p) > 0.0


## 岛上的地面：桥门那头低、往东一路上坡到广场
static func island_y(x: float) -> float:
	return ISLAND_Y + (SQUARE_Y - ISLAND_Y) * _smooth(clampf((x - RISE_FROM) / (RISE_TO - RISE_FROM), 0.0, 1.0)) + 1.6 * _smooth(clampf((x - 78.0) / 20.0, 0.0, 1.0))


static func street_d(p: Vector2) -> float:
	var d := float(poly_hit(p, STREET).d)
	for l in LANES:
		d = minf(d, float(poly_hit(p, l).d) + (STREET_HALF - LANE_HALF))
	return d


static func natural(x: float, z: float) -> float:
	_noises()
	var p := Vector2(x, z)
	var bank_k := 0.0                                                        # 河西岸、北岸、南岸
	bank_k = maxf(bank_k, _smooth(clampf((WEST_BANK_X - x) / 6.0, 0.0, 1.0)))
	bank_k = maxf(bank_k, _smooth(clampf((absf(z) - FAR_BANK_Z) / 6.0, 0.0, 1.0)))
	var water := RIVER_BED + 0.4 * _noise_big.get_noise_2d(x, z)
	var bank := BANK_Y + 0.3 * _noise_big.get_noise_2d(x, z) + 0.06 * _noise_small.get_noise_2d(x, z)
	var y := lerpf(water, bank, bank_k)
	var d := island_d(p)
	if d > -SHORE:                                                           # 岛：石岸几米内陡降到河床
		var iy := island_y(x) + 0.25 * _noise_big.get_noise_2d(x * 1.5, z * 1.5) + 0.05 * _noise_small.get_noise_2d(x, z)
		var k := _smooth(clampf((d + SHORE) / SHORE, 0.0, 1.0))
		y = lerpf(y, iy, k)
	return y


## 最终高度
static func height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var y := natural(x, z)
	if on_island(p):
		var sq := SQUARE.grow(6.0)                                           # 广场压平
		if sq.has_point(p):
			var k := _smooth(clampf(minf(minf(p.x - sq.position.x, sq.end.x - p.x), minf(p.y - sq.position.y, sq.end.y - p.y)) / 6.0, 0.0, 1.0))
			y = lerpf(y, SQUARE_Y, k)
		var sd := street_d(p)                                                # 街面：抹平
		if sd < STREET_HALF + STREET_BLEND:
			var k := 1.0 if sd <= STREET_HALF else _smooth(1.0 - (sd - STREET_HALF) / STREET_BLEND)
			y = lerpf(y, island_y(x) - 0.04, k * 0.85)
	return y


## r 铺石（街、广场、桥门那一片），g 不用，b 遮蔽
static func masks(x: float, z: float) -> Vector3:
	var p := Vector2(x, z)
	var paved := 0.0
	if on_island(p):
		paved = _smooth(clampf((STREET_HALF + 0.5 - street_d(p)) / 1.0, 0.0, 1.0))
		if SQUARE.has_point(p):
			paved = 1.0
		if p.distance_to(Vector2(-36.0, 0.0)) < 6.0:
			paved = 1.0
	var occl := 1.0
	if island_d(p) < 0.5 and island_d(p) > -SHORE:
		occl = 0.8
	return Vector3(paved, 0.0, occl)


static func surface_at(pos: Vector3) -> String:
	if pos.y < RIVER_Y - 0.05:
		return "shallows"
	return ""


## 斜街边上一栋房子的正面：{front: 正面墙脚中点, yaw（房子的朝向，同 HarborTown.xf_of）, face: 正面朝哪（单位向量）, w, d}
static func street_front(spec: Array) -> Dictionary:
	var a: Vector2 = STREET[int(spec[0])]
	var b: Vector2 = STREET[int(spec[0]) + 1]
	var dir := (b - a).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	var side := float(spec[2])
	var front := a.lerp(b, float(spec[1])) + nrm * side * (STREET_HALF + 1.0)
	var face := -nrm * side
	return {"front": front, "yaw": rad_to_deg(atan2(face.x, face.y)), "face": face, "w": float(spec[3]), "d": float(spec[4])}


static func spawn_points() -> Dictionary:
	var out := {}
	for id in SPAWN_XZ:
		var s: Array = SPAWN_XZ[id]
		var p: Vector2 = s[0]
		var yaw := float(s[1])
		if id == "matilda_door":                                           # 出了门站在门外一米多，背对着门
			var m := street_front(MATILDA)
			p = (m.front as Vector2) + (m.face as Vector2) * 1.5
			yaw = rad_to_deg(atan2(-(m.face as Vector2).x, -(m.face as Vector2).y))
		out[id] = [Vector3(p.x, height(p.x, p.y) + 0.05, p.y), yaw]
	return out


static func views() -> Array:
	var out := []
	for v: Array in VIEW_SPEC:
		var p: Vector3 = v[0]
		var y := height(p.x, p.z)
		if p.x > (BRIDGE[0] as Vector2).x + 2.0 and p.x < (BRIDGE[1] as Vector2).x and absf(p.z) < BRIDGE_HALF:
			y = maxf(y, CrownCity.bridge_y(p.x))                                      # 桥上
		out.append([Vector3(p.x, y + p.y, p.z), v[1], v[2]])
	return out
