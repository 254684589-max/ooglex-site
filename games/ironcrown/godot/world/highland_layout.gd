class_name HighlandLayout
extends RefCounted
## 余火高地连片地图的布局（路线图 5.1a，D10-B、D12；STORY.md 5.2）：只放数据和「这一点有多高」，搭场景在 world/highland.gd。
## 第一张有起伏的地图（鹭沼是平的）：南边山谷底是羊脊村（5.2 盖房子），一条盘山路之字形爬上北边的山脊，
## 山脊上是第十九烽（5.3），往西一座是熄了的第十八烽（5.5a）；山脊背后往下是白寂边缘的冰原（5.8）。
## 坐标：x 往东、-z 往北（和别的区域一样），y 是高度（米）。整张图 320 × 260 米，地形每 1 米一个采样点（高度场）。
##
## 高度 = 大轮廓（往北一路抬升到山脊、东西两边是山肩）+ 噪声（起伏）→ 村子那片压平 → 盘山路切进山坡（路面平、两边过渡），
## 路的上坡一侧在「伏击段」多一道岩坎（STORY.md 5.6「一侧峭壁、一侧缓坡」）。
## 地面贴图的分布另外记在每个采样点上（mask）：路 / 村里踩出来的地（脚印雪）、碎石（噪声斑块）、遮蔽（凹处暗一点）；陡坡露岩由着色器按坡度算。

const BOUNDS := Rect2(-160, -130, 320, 260)
const STEP := 1.0                       # 高度场的采样间距（米）
const NX := 321                         # x 方向采样点数（-160..160）
const NZ := 261                         # z 方向（-130..130）
const CHUNK := 64.0                     # 画面分块（米）
const WALL_INSET := 5.0                 # 看不见的墙离地图边多远（物理层 5「边界」）
const WALL_H := 60.0

const VILLAGE := Vector2(8.0, 88.0)     # 羊脊村中心（5.2 盖房子）：压平的一片
const VILLAGE_R := 34.0
const VILLAGE_Y := 0.6
const BEACON19 := Vector2(22.0, -64.0)  # 第十九烽「断角烽」（5.3）
const BEACON18 := Vector2(-118.0, -74.0) # 第十八烽（5.5a）
const WELL := Vector2(-20.0, -112.0)    # 白寂边缘的石井（5.8）
const PAD_R := 14.0                     # 烽燧脚下压平的一片

## 盘山路（STORY.md 5.2）：从南边进村的路口 → 村子 → 之字形五段爬上山脊 → 第十九烽门前。路面宽 HALF × 2
const ROAD := [Vector2(4.0, 128.0), Vector2(6.0, 104.0), Vector2(10.0, 62.0), Vector2(58.0, 36.0), Vector2(-38.0, 8.0),
	Vector2(48.0, -22.0), Vector2(-6.0, -44.0), Vector2(18.0, -56.0)]
const ROAD_HALF := 2.4
const ROAD_BLEND := 7.0                 # 路边多宽从路面高度过渡回山坡
const AMBUSH_LEG := 4                   # 第几段是伏击段（ROAD[4] → ROAD[5]：上坡一侧是岩坎）
const CLIFF_H := 7.5

## ---------------- 盘山路上（5.3a；STORY.md 5.2「积雪齐膝（走进去变慢），几处倒伏的松树；半山有一处废弃的羊棚」）----------------
## 废羊棚：半山西边那个弯下面一块压平的地。[中心 (x, z), 朝向（度，0 = 门朝 +Z（南）），宽, 纵深]
const SHED := [Vector2(-52.0, 4.0), 90.0, 6.4, 4.6]          # 门朝东，对着路
const SHED_R := 6.0
## 倒伏的松树：按路来摆——[第几段路, 在那段的哪儿 t, 哪一边（"up" 上坡 / "down" 下坡）, 离路边多远（米）, 偏角（度，0 = 垂直离开路、±90 = 顺着路）,
##   长（米）, 树种, 根在哪头（"far" 根在远处、树冠倒到路边 / "near" 根在路边、往外倒）]
## 伏击段下坡那一棵顺着路躺在路肩上：5.6「先断车头」就是把它横过来拦路
const FALLEN := [
	[4, 0.34, "down", 0.9, 82.0, 13.0, 0, "near"],
	[2, 0.55, "up", 0.8, -18.0, 12.0, 0, "far"],
	[5, 0.50, "down", 2.6, 34.0, 10.0, 1, "near"],
	[3, 0.70, "up", 4.5, 64.0, 9.0, 1, "far"],
]
## 深雪（Surface "deep_snow"）：踩出来的路和村里不深；路两边的雪檐、背风的雪窝深；冰原上风把雪刮硬了，浅
const DEEP_BANK := 4.5                  # 路边多宽一条雪檐（米，从路边 + 0.8 起）
const DRIFT_H := 0.4                    # 深雪的地方高出去多少（雪堆）

## ---------------- 羊脊村（5.2a；STORY.md 5.2「干砌石墙的矮石屋、草皮屋顶压着石头、羊圈、结冰的溪、一圈半埋在雪里的古老立石」）----------------
## 矮石屋（world/croft.gd）：[编号, 正面墙脚中点 (x, z), 朝向（度，0 = 正面朝 +Z（南），90 = 朝东，-90 = 朝西）, 宽, 纵深, 门在正面的位置, 亮窗比例, 种子]
## 村里的路南北穿过村子（ROAD[1] → ROAD[2]），房子正面都朝着路
const CROFTS := [
	["croft_n", Vector2(-0.5, 96.0), 90.0, 7.0, 5.0, 0.8, 0.7, 11],
	["croft_w", Vector2(1.0, 78.0), 95.0, 8.0, 5.5, -1.0, 0.6, 12],
	["croft_sw", Vector2(-12.0, 69.0), 60.0, 7.0, 5.0, 0.0, 0.5, 13],
	["croft_ne", Vector2(16.5, 100.0), -90.0, 7.0, 5.0, 0.6, 0.6, 14],
	["croft_se", Vector2(23.0, 66.5), -112.0, 7.5, 5.0, 0.0, 0.4, 15],
	["croft_nw", Vector2(-16.0, 94.0), 80.0, 6.5, 4.5, 0.0, 0.5, 16],
]
## 厄尔德家的驿站：村里唯一的两层石楼（House，石砌上层、石板瓦），门通往大堂（world/waystation.gd）
const WAYSTATION := [Vector2(17.5, 84.0), -90.0, 11.0, 8.0, 0.0]          # 正面墙脚中点、朝向、宽、纵深、门的位置
const SMITHY := [Vector2(19.5, 74.5), -90.0]                               # 铁匠的披棚（三面矮墙、一面敞着朝路，炉火是暖光）
## 羊圈：干砌石墙。圆的 [中心, 半径, 门的方向（度）]、方的 [中心, 半宽, 半深, 门在哪边]
const PEN_ROUND := [Vector2(-21.0, 82.0), 6.5, 80.0]
const PEN_RECT := [Vector2(32.0, 92.0), 5.0, 3.5]
const SHEEP := [Vector3(-22.5, 0, 80.0), Vector3(-19.8, 0, 83.5), Vector3(-23.6, 0, 84.2), Vector3(-18.5, 0, 79.6), Vector3(-21.4, 0, 86.2),
	Vector3(30.6, 0, 91.2), Vector3(33.4, 0, 93.0), Vector3(31.9, 0, 89.9)]
## 田间的干砌石墙（一段段折线）
const FIELD_WALLS := [
	[Vector2(-6.0, 113.0), Vector2(-18.0, 116.0), Vector2(-31.0, 115.0)],
	[Vector2(13.0, 111.0), Vector2(26.0, 116.0), Vector2(41.0, 121.0)],
	[Vector2(40.0, 60.0), Vector2(52.0, 56.0), Vector2(66.0, 50.0)],
	[Vector2(38.0, 98.0), Vector2(46.0, 84.0), Vector2(47.0, 70.0)],
]
const FIELD_WALL_H := 1.0
const WALL_W := 0.7
## 结冰的溪：从西北的山坡下来，绕过村子西边，往南出山谷。溪床往下刻 0.9 米，冰面在溪床上 0.25 米
const STREAM := [Vector2(-74.0, 6.0), Vector2(-46.0, 36.0), Vector2(-34.0, 64.0), Vector2(-35.0, 92.0), Vector2(-27.0, 116.0), Vector2(-23.0, 140.0)]
const STREAM_HALF := 2.0
const STREAM_BANK := 3.0
const STREAM_DEPTH := 0.9
## 石圈：村子西北的坡上，九块半埋的立石（5.5a 石上的字）
const STONE_RING := Vector2(-20.0, 48.0)
const STONE_RING_R := 6.0
const STONES := 9
## 村里的人（5.2b）：[编号, 名字, 位置 (x, z), 朝向（弧度，0 = 面朝北，PI / 2 = 面朝西）, 衣服颜色, 对话编号（"" = 只说一句，台词在 HighlandVillage.LINES）]
const PEOPLE := [
	["nell", "妮尔", Vector2(-14.5, 54.0), 0.3, "6a6458", "nell"],                     # 石圈边，守着那串往北去的脚印
	["smith", "铁匠", Vector2(19.7, 75.4), PI * 0.5, "3a2e24", "smith"],                # 披棚里铁砧边，面朝村路
	["shepherd", "老牧羊人", Vector2(-13.2, 82.6), PI * 0.5, "5a5246", ""],             # 圆羊圈的门口
	["bolted", "闩着门的女人", Vector2(15.0, 100.6), PI * 0.5, "6a6256", ""],           # 东北那栋矮石屋门口
]
## 路牌（出发的地方）：村北路边（往第十九烽）、第十九烽门前（往羊脊村）
const SIGN_VILLAGE := Vector3(13.2, 0, 60.0)
const SIGN_BEACON := Vector3(10.5, 0, -50.5)


## 一点离溪中线多远
static func stream_d(p: Vector2) -> float:
	var best := INF
	for i in STREAM.size() - 1:
		var a: Vector2 = STREAM[i]
		var b: Vector2 = STREAM[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## 村里踩出来的小路：每栋房子、驿站、铁匠棚、羊圈门口到村路（线段：[a, b]）
static func village_paths() -> Array:
	var out := []
	for c in CROFTS:
		var door := croft_door(c)
		out.append([door, _road_foot(door)])
	var w: Vector2 = WAYSTATION[0]
	out.append([w + Vector2(-1.0, 0), _road_foot(w)])
	var sm: Vector2 = SMITHY[0]
	out.append([sm + Vector2(-1.5, 0), _road_foot(sm)])
	var pr: Vector2 = PEN_ROUND[0]
	out.append([pr + Vector2.from_angle(deg_to_rad(-float(PEN_ROUND[2]) + 90.0)) * 0.0 + Vector2(float(PEN_ROUND[1]), 0), _road_foot(pr)])
	var pq: Vector2 = PEN_RECT[0]
	out.append([pq + Vector2(-float(PEN_RECT[1]), 0), _road_foot(pq)])
	return out


## 矮石屋的门口（门外 0.6 米）
static func croft_door(c: Array) -> Vector2:
	var pos: Vector2 = c[1]
	var yaw := deg_to_rad(float(c[2]))
	var fwd := Vector2(sin(yaw), cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	return pos + right * float(c[5]) + fwd * 0.6


static func _road_foot(p: Vector2) -> Vector2:
	var r := road_hit(p)
	var a: Vector2 = ROAD[r.i]
	var b: Vector2 = ROAD[r.i + 1]
	return a + (b - a) * float(r.t)


static func _seg_d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## 命名出生点：[位置（y 由地形算）, 水平朝向（度）]
const SPAWN_XZ := {
	"village": [Vector2(6.0, 112.0), 0.0],          # 进村的路口，面朝北（村子、身后是来路）
	"road": [Vector2(-30.0, 10.0), -60.0],          # 盘山路第三个弯
	"beacon": [Vector2(14.0, -52.0), -20.0],        # 第十九烽门前
	"plain": [Vector2(-10.0, -96.0), 180.0],        # 山脊背后，面朝北的冰原
	"waystation_door": [Vector2(15.4, 84.6), 90.0], # 驿站门外（从大堂出来），面朝西（村路）
	"shed": [Vector2(-42.0, 9.0), 70.0],            # 废羊棚下面的路上（5.3a），面朝羊棚
}
## ?view=N 的固定机位：[位置（x, 离地高度, z）, 水平朝向, 俯仰]——截图、冒烟用
const VIEW_SPEC := [
	[Vector3(6.0, 1.7, 116.0), 8.0, 2.0],           # 0 进村的路口往北看：山谷、村子那片平地、远处山坡上的路
	[Vector3(60.0, 1.7, 40.0), 140.0, -6.0],        # 1 盘山路第一个弯往下看：山谷、村子
	[Vector3(-25.0, 1.7, 3.5), -70.0, 0.0],         # 2 伏击段（沿着路往东北走）：左手边是岩坎、右手边是缓坡
	[Vector3(50.0, 1.7, -19.0), 192.0, -10.0],      # 3 半山腰的弯道上往南回看整条山谷
	[Vector3(-6.0, 1.7, -88.0), 0.0, -3.0],         # 4 山脊背后往北看冰原（白寂边缘）
	[Vector3(34.0, 1.7, -66.0), -100.0, 1.0],       # 5 第十九烽边上顺着山脊往东看：远处那串烽燧塔（5.1b）
	[Vector3(5.0, 1.7, 88.5), -82.0, 2.0],          # 6 村路上看驿站（5.2a）
	[Vector3(-6.0, 1.7, 90.0), 112.0, -6.0],        # 7 村西：圆羊圈、远处结冰的溪
	[Vector3(-19.0, 1.7, 62.0), 12.0, 0.0],         # 8 石圈
	[Vector3(9.5, 1.7, 70.5), -62.0, -4.0],         # 9 铁匠棚
	[Vector3(12.0, 1.7, 52.0), 172.0, -6.0],        # 10 村北路牌往回看整个村子
	[Vector3(-39.0, 1.7, 7.5), 75.0, -8.0],         # 11 西边那个弯上往下看废羊棚（5.3a）：门朝着路，西南角塌了
	[Vector3(-29.0, 1.7, 9.5), -72.0, -6.0],        # 12 伏击段起头：右手路肩上躺着的那棵倒树、路边的雪檐、左手的岩坎
	[Vector3(24.4, 1.7, 54.2), -52.0, -5.0],        # 13 第一段路：树冠倒到路边的那棵、下坡一侧的雪杆
]
const VIEW_NAMES := ["进村的路口", "盘山路的弯", "伏击段", "半山回看", "白寂边缘", "山脊往东", "驿站", "羊圈和溪", "石圈", "铁匠棚", "村北回看",
	"废羊棚", "路肩上的倒树", "第一段路"]


## 大轮廓（不含噪声）：南边谷底 0 米 → 往北抬升 → 山脊（z 约 -68，最高约 46 米，西高东低）→ 山脊背后落到冰原（约 30 米）；东西两边是山肩
static func base(x: float, z: float) -> float:
	var crest := crest_z(x)
	var top := 40.0 - x * 0.04 + 3.0 * sin(x / 23.0)           # 山脊高度：西边高一点
	var y: float
	if z > crest:
		var t := clampf((z - crest) / (66.0 - crest), 0.0, 1.0)  # 0 = 山脊，1 = 谷底（z = 66）
		y = top * (1.0 - _smooth(t)) - 1.5 * t
	else:
		var t := clampf((crest - z) / 26.0, 0.0, 1.0)            # 山脊往北 26 米落到冰原
		y = lerpf(top, 29.0, _smooth(t))
	var ax := absf(x)
	y += 34.0 * _smooth(clampf((ax - 95.0) / 75.0, 0.0, 1.0)) * (0.6 + 0.4 * clampf((z + 30.0) / 120.0, 0.0, 1.0))  # 东西山肩（南边谷里更明显）
	return y


## 山脊线在 x 处的 z（往东西两边一直延下去：远处那串烽燧塔也站在这条线上，5.1b）
static func crest_z(x: float) -> float:
	return -68.0 + 7.0 * sin(x / 37.0) + 3.0 * sin(x / 13.0 + 1.3)


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


static var _noise_big: FastNoiseLite
static var _noise_small: FastNoiseLite
static var _noise_paint: FastNoiseLite
static var _noise_drift: FastNoiseLite


static func _noises() -> void:
	if _noise_big != null:
		return
	_noise_big = FastNoiseLite.new()                  # 大起伏：几十米一个包
	_noise_big.seed = 2046
	_noise_big.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_big.frequency = 0.012
	_noise_big.fractal_octaves = 3
	_noise_small = FastNoiseLite.new()                # 小起伏：几米的坑洼、雪堆
	_noise_small.seed = 646
	_noise_small.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_small.frequency = 0.07
	_noise_small.fractal_octaves = 2
	_noise_paint = FastNoiseLite.new()                # 贴图分布的斑块（碎石、村里踩出来的地）
	_noise_paint.seed = 11
	_noise_paint.frequency = 0.035
	_noise_paint.fractal_octaves = 3
	_noise_drift = FastNoiseLite.new()                # 背风的雪窝（5.3a 深雪）
	_noise_drift.seed = 5303
	_noise_drift.frequency = 0.028
	_noise_drift.fractal_octaves = 2


## 起伏（米）：噪声（固定种子，每次载入都一样）；冰原上换成风吹出来的长条雪浪（顺着西北风）
static func bumps(x: float, z: float) -> float:
	_noises()
	var n := 4.2 * _noise_big.get_noise_2d(x, z) + 0.55 * _noise_small.get_noise_2d(x, z)
	if z < -80.0:
		var k := clampf((-80.0 - z) / 14.0, 0.0, 1.0)
		var along := x * 0.6 + z * 0.8
		var dune := 0.5 * sin(along * 0.19 + 2.0 * _noise_big.get_noise_2d(x * 0.5, z * 0.5)) + 0.25 * _noise_small.get_noise_2d(x * 0.4, z * 1.6)
		n = lerpf(n, n * 0.3 + dune, k)
	return n


## 自然地面（还没压村子、切路）
static func natural(x: float, z: float) -> float:
	return base(x, z) + bumps(x, z)


## 路面中线在这一段 t（0..1）处的高度：两头的路口高度之间线性——路是顺着坡一路往上的，不跟着小起伏
static func road_y_at(i: int, t: float) -> float:
	return lerpf(_road_node_y(i), _road_node_y(i + 1), t)


## 路口的高度：出了村以后，「山坡在这儿多高」和「从村口到烽燧一路匀速爬上去」各取一半——
## 只按山坡，S 形的坡把爬升挤在中间几段（最陡 19%，粮车上不去）；只按匀速，西边的弯要垫高 6 米。现在每段 10%–16%，弯道处垫起两三米（像垒出来的路基）
static func _road_node_y(i: int) -> float:
	var p: Vector2 = ROAD[i]
	if p.distance_to(VILLAGE) < VILLAGE_R:
		return VILLAGE_Y
	var first := 0
	while (ROAD[first] as Vector2).distance_to(VILLAGE) >= VILLAGE_R or (ROAD[first + 1] as Vector2).distance_to(VILLAGE) < VILLAGE_R:
		first += 1                                           # 村里最后一个路口
	var last := ROAD.size() - 1
	var top_y := base((ROAD[last] as Vector2).x, (ROAD[last] as Vector2).y) + 0.3
	if i == last:
		return top_y
	var total := 0.0
	var upto := 0.0
	for k in range(first, last):
		var seg := (ROAD[k] as Vector2).distance_to(ROAD[k + 1])
		total += seg
		if k < i:
			upto += seg
	var even := lerpf(VILLAGE_Y, top_y, upto / total)
	return (even + base(p.x, p.y) + 0.3) * 0.5


## 一点离盘山路有多远、最近的是哪一段、在那一段的哪儿、在路的哪一边（+1 = 走路方向的左手边）
static func road_hit(p: Vector2) -> Dictionary:
	var best := {"d": INF, "i": -1, "t": 0.0, "side": 0.0}
	for i in ROAD.size() - 1:
		var a: Vector2 = ROAD[i]
		var b: Vector2 = ROAD[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_to(q)
		if d < best.d:
			best = {"d": d, "i": i, "t": t, "side": signf(ab.cross(p - a))}
	return best


## 最终高度（地形网格、碰撞、出生点都用它；Highland 一次算好整张高度场）
static func height(x: float, z: float) -> float:
	var y := natural(x, z)
	var p := Vector2(x, z)
	var dv := p.distance_to(VILLAGE)                               # 村子：压平，边上 12 米过渡
	if dv < VILLAGE_R + 12.0:
		var k := _smooth(clampf((VILLAGE_R + 12.0 - dv) / 12.0, 0.0, 1.0))
		y = lerpf(y, VILLAGE_Y + 0.25 * bumps(x * 0.5, z * 0.5), k)
	for c in [BEACON19, BEACON18]:                                 # 烽燧脚下：压平一小片
		var dc := p.distance_to(c)
		if dc < PAD_R + 6.0:
			var cy := base(c.x, c.y) + 1.0
			y = lerpf(y, cy, _smooth(clampf((PAD_R + 6.0 - dc) / 6.0, 0.0, 1.0)))
	var r := road_hit(p)
	if r.d < ROAD_HALF + ROAD_BLEND:
		var ry := road_y_at(r.i, r.t) + 0.08 * bumps(x * 3.0, z * 3.0)
		var k := 1.0 if r.d <= ROAD_HALF else _smooth(1.0 - (r.d - ROAD_HALF) / ROAD_BLEND)
		y = lerpf(y, ry, k)
	var dsh := p.distance_to(SHED[0])                             # 废羊棚：压平一小片（5.3a）
	if dsh < SHED_R + 10.0:                                         # 过渡 10 米：坡上切出来的坎不陡（5 米时背后露出一大片岩石）
		var sy := natural((SHED[0] as Vector2).x, (SHED[0] as Vector2).y)
		y = lerpf(y, sy, _smooth(clampf((SHED_R + 10.0 - dsh) / 10.0, 0.0, 1.0)))
	y += _cliff(p)
	y += DRIFT_H * deep(x, z) * (0.75 + 0.5 * _noise_small.get_noise_2d(x * 0.7, z * 0.7))   # 深雪的地方鼓起来一点（雪堆、路边的雪檐）
	var ds := stream_d(p)                                           # 溪：往下刻一道沟（溪床平、两岸斜）
	if ds < STREAM_HALF + STREAM_BANK:
		var k := 1.0 if ds <= STREAM_HALF else 1.0 - _smooth((ds - STREAM_HALF) / STREAM_BANK)
		y -= STREAM_DEPTH * k
	return y


## 伏击段（ROAD[AMBUSH_LEG] → 下一点）上坡一侧的岩坎：贴着路边 3 米内陡起来，再往外 30 米慢慢落回山坡（不是一堵墙、也不是一块平台）；两头收掉
static func _cliff(p: Vector2) -> float:
	var a: Vector2 = ROAD[AMBUSH_LEG]
	var b: Vector2 = ROAD[AMBUSH_LEG + 1]
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	if t <= 0.06 or t >= 0.94:
		return 0.0
	if signf(ab.cross(p - a)) != _uphill_side(AMBUSH_LEG):
		return 0.0
	var d := p.distance_to(a + ab * t) - ROAD_HALF - 0.5
	if d <= 0.0 or d > 32.0:
		return 0.0
	_noises()
	var along := _smooth(clampf(minf(t - 0.06, 0.94 - t) / 0.16, 0.0, 1.0))
	var rise := _smooth(clampf((d + 1.3 * _noise_small.get_noise_2d(p.x * 1.3, p.y * 1.3)) / 4.5, 0.0, 1.0))   # 岩坎的脚不是一条直线
	var fall := 1.0 - _smooth(clampf((d - 4.0) / 28.0, 0.0, 1.0))
	return CLIFF_H * rise * fall * along * (0.8 + 0.35 * _noise_small.get_noise_2d(p.x * 2.0, p.y * 2.0))


## 这一段路哪一边是上坡（北边高）：路往前走时北边在左手 = +1
static func _uphill_side(i: int) -> float:
	var ab: Vector2 = ROAD[i + 1] - ROAD[i]
	return signf(ab.cross(Vector2(0, -1)))


## 地面贴图的分布（0..1）：track = 路和村里踩出来的地（脚印雪）；scree = 碎石斑块（山坡上、雪薄的地方）
static func masks(x: float, z: float) -> Vector2:
	var p := Vector2(x, z)
	var track := 0.0
	var r := road_hit(p)
	if r.d < ROAD_HALF + 1.6:
		track = _smooth(clampf((ROAD_HALF + 1.6 - r.d) / 1.8, 0.0, 1.0))
	var dv := p.distance_to(VILLAGE)
	if dv < VILLAGE_R + 8.0:                                       # 村里（5.2a）：每栋房子、驿站、羊圈门口到村路踩出来的小路，驿站门前一片
		for seg in village_paths():
			var d := _seg_d(p, seg[0], seg[1])
			if d < 1.6:
				track = maxf(track, _smooth(clampf((1.6 - d) / 1.0, 0.0, 1.0)))
		var w: Vector2 = WAYSTATION[0]
		var dw := p.distance_to(w + Vector2(-4.5, 0))
		if dw < 6.0:
			track = maxf(track, _smooth(clampf((6.0 - dw) / 3.0, 0.0, 1.0)))
	for c in [BEACON19, BEACON18]:
		var dc := p.distance_to(c)
		if dc < PAD_R:
			track = maxf(track, _smooth(clampf((PAD_R - dc) / 6.0, 0.0, 1.0)) * 0.8)
	_noises()
	var s := 0.5 + 0.5 * _noise_paint.get_noise_2d(x, z)
	var scree := clampf((s - 0.6) * 4.0, 0.0, 1.0) * clampf((z - (-80.0)) / 20.0, 0.0, 1.0)   # 冰原上没有碎石
	scree *= 1.0 - deep(x, z)                                    # 深雪盖住了碎石
	var dsh := p.distance_to(SHED[0])                             # 废羊棚门前踩出来的一片（以前赶羊进出）
	if dsh < SHED_R:
		track = maxf(track, _smooth(clampf((SHED_R - dsh) / 3.0, 0.0, 1.0)) * 0.6)
	return Vector2(track, scree)


## 深雪（0..1；> 0.5 算 Surface「deep_snow」）：路面、村里、烽燧脚下、废羊棚、岩坎上不深；路两边各一条雪檐；别处按噪声一片一片（背风的雪窝）；冰原上浅
static func deep(x: float, z: float) -> float:
	var p := Vector2(x, z)
	if p.distance_to(VILLAGE) < VILLAGE_R + 4.0 or p.distance_to(SHED[0]) < SHED_R:
		return 0.0
	for c in [BEACON19, BEACON18]:
		if p.distance_to(c) < PAD_R + 2.0:
			return 0.0
	var r := road_hit(p)
	var off: float = r.d - ROAD_HALF - 0.8                             # 踩出来的路面再往外 0.8 米还是硬的
	if off <= 0.0:
		return 0.0
	_noises()
	var k := _smooth(clampf((_noise_drift.get_noise_2d(x, z) + 0.12) / 0.3, 0.0, 1.0))
	if off < DEEP_BANK + 2.0:                                    # 路边的雪檐（扫路、车过、风都往路边堆）
		k = maxf(k, 1.0 - _smooth(clampf((off - DEEP_BANK) / 2.0, 0.0, 1.0)))
	k *= _smooth(clampf(off / 1.2, 0.0, 1.0))
	if z < -80.0:
		k *= lerpf(1.0, 0.3, clampf((-80.0 - z) / 10.0, 0.0, 1.0))
	if int(r.i) == AMBUSH_LEG and float(r.side) == _uphill_side(AMBUSH_LEG) and off < 10.0:
		k = 0.0                                                  # 岩坎脚下、坎上没有深雪（按岩坎高度一点点收：1 米的网格上是一排锯齿）
	return clampf(k, 0.0, 1.0)


## 脚下是哪种地面（Surface；高地的地面是一整块高度图，按位置查：Highland._collision 把它挂在碰撞体的元数据 surface_at 上）
static func surface_at(pos: Vector3) -> String:
	return "deep_snow" if deep(pos.x, pos.z) > 0.5 else "snow"


## 倒伏的松树：[{root 根部（世界坐标，贴地）, tip 树梢, kind, len}]
static func fallen() -> Array:
	var out := []
	for f in FALLEN:
		var i := int(f[0])
		var a: Vector2 = ROAD[i]
		var b: Vector2 = ROAD[i + 1]
		var dir := (b - a).normalized()
		var left := Vector2(-dir.y, dir.x)                       # road_hit 的 side = +1 那一边（dir.cross(left) > 0）
		var up := _uphill_side(i)
		var side := up if str(f[2]) == "up" else -up
		var out_n := left * side
		var edge := a.lerp(b, float(f[1])) + out_n * (ROAD_HALF + float(f[3]))
		var d := out_n.rotated(deg_to_rad(float(f[4])))
		var far := edge + d * float(f[5])
		var root := far if str(f[7]) == "far" else edge
		var tip := edge if str(f[7]) == "far" else far
		out.append({"root": root, "tip": tip, "kind": int(f[6]), "len": float(f[5])})
	return out


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
