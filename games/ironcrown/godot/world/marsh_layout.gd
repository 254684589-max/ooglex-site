class_name MarshLayout
extends RefCounted
## 鹭沼连片地图的布局表（路线图 4.4，D10-B）：只有常量和几何换算，搭场景（world/marsh.gd）、地图（map_spec）、测试都读它，一份数据。
## 原创布局。北 = -Z，东 = +X。整张图 256 × 192 米，分成 4 × 3 块 64 米的方格（块：显示 / 隐藏、分帧搭建的单位）：
##   东边是芦栈村：东头一片干岸（路从霜渡镇来），往西是一大片泥滩，高脚屋立在泥滩上，木栈道把它们连起来；北边泥炭场，南边小码头；
##   村子西北角是堤道头，石砌堤道朝西北伸 82 米，中段断口搭着木板，靠堡门一座石拱，尽头是黑鹭堡门前的石台；
##   堤道两边各一溜泥滩、芦苇，再往外是深水（走不进去：边上有看不见的墙，物理层 5「边界」）；西南的鹭沼深处 4.4c 才做（现在是芦苇荡和水）。
## 「地面」（floors）都是有朝向的矩形：{id, k（种类）, c（中心 XZ）, size（本地 x 宽、本地 z 长）, yaw（度，本地 +Z 朝 (sin yaw, cos yaw)）,
##   top（顶面高度，斜的是中心那点的高度）, pitch / tilt（绕本地 x / z 转的角度，斜坡用）}。
## 种类：mud 泥滩（走得慢、不能跑）、land 干地、deck 木栈道、stone 石砌（堤道、石台）、slope 堤道两边的石坡、bridge 断口上的木板。

const CELL := 64.0
const BOUNDS := Rect2(-128, -128, 256, 192)
const COLS := 4
const ROWS := 3
const WATER_Y := -0.4
const MUD_Y := -0.12
const BANK_Y := 0.0
const DECK_Y := 0.12
const CAUSE_Y := 0.5
const STILTS := 0.9                 # 高脚屋地板比栈道高多少
const SHORE := 4.0                  # 走得到的地方外面几米之内的水里长满芦苇（看不见的墙外面总有东西挡着）

## 堤道：从村子西北角的堤道头 CW_START 朝西北（CW_DIR）伸出去；t = 沿堤道的米数，off = 往东北（CW_SIDE）偏几米
const CW_START := Vector2(32, -6)
const CW_DIR := Vector2(-0.70710678, -0.70710678)
const CW_SIDE := Vector2(0.70710678, -0.70710678)
const CW_YAW := 45.0                # 沿堤道的矩形：本地 +Z 朝东南（回村子），本地 +X 朝东北
const CW_LEN := 82.0
const CW_W := 4.0                   # 路面宽（STORY：宽约 4 米、长约 80 米）
const CW_RAMP := 6.0                # 堤道头那段从干地慢慢坡上去
const CW_SLOPE := 25.0              # 两边石坡的坡度：掉进泥里能走回来
const CW_MUD := 6.0                 # 两边泥滩的宽度
const GAP := Vector2(38.0, 44.0)    # 中段断口（t 从 38 到 44）
const BRIDGE_W := 2.4               # 断口上搭的木板宽（窄口：4.9 堤道夜战守这里）
const ARCH_T := 72.0                # 石拱
const ARCH_GAP := 3.0               # 石拱下能走的宽度（另一处窄口）
const APRON_T := Vector2(82.0, 94.0)  # 堡门前的石台
const APRON_W := 16.0
const CASTLE_T := 116.0             # 黑鹭堡的中心（堡墙前面在 t = 94）
const CASTLE_SIZE := Vector2(40, 44)

## 村子
const BANK := Rect2(100, 12, 28, 38)          # 东头的干岸（路从这里出图，往霜渡镇）
const ROAD_Z := 30.0
const VILLAGE_MUD := Rect2(30, -2, 72, 54)    # 村子底下的泥滩
const PEAT_YARD := Rect2(54, -6, 38, 14)      # 北边的泥炭场（干地）
const HEAD := Rect2(24, -12, 16, 13)          # 堤道头（干地）
const WALK_W := 2.6                           # 主栈道宽；支路 2 米
## 木栈道：[编号, 起点, 终点, 宽]（都是正南北或正东西）
const WALKS := [
	["main", Vector2(101, 30), Vector2(34, 30), 2.6],
	["to_causeway", Vector2(36, 28.7), Vector2(36, 1), 2.0],
	["to_peat", Vector2(66, 28.7), Vector2(66, 8), 2.0],
	["to_dock", Vector2(50, 31.3), Vector2(50, 52), 2.0],
	["pier", Vector2(50, 52), Vector2(50, 58), 2.6],
]
const DOCK := Rect2(44, 58, 12, 4)            # 码头头上的平台（伸进开阔的水面）
## 高脚屋：[编号, 正面墙脚中点（y = 栈道面，地板再高 STILTS）, 朝向（度）, spec]；北边的朝南（0），南边的朝北（180）
## 北边一排的正面墙脚 z = 30 - 1.3 - House.stair_reach(STILTS) ≈ 25.96，南边 ≈ 34.04：台阶正好落在栈道边上
const HOUSES := [
	["inn", Vector2(74, 25.96), 0.0, {"w": 12.0, "d": 9.0, "floors": 1, "roof": "eaves", "chimney": true, "door_x": 0.0, "seed": 441, "lit": 0.85,
		"sign": "歪桩客栈", "door": {"name": "歪桩客栈", "text": "客栈的门闩着，里面在收拾。（客栈里面还在开发中）"}}],
	["east_n", Vector2(88, 25.96), 0.0, {"w": 7.0, "d": 6.0, "floors": 0, "roof": "eaves", "door_x": -1.5, "seed": 442, "lit": 0.5}],
	["mid_n", Vector2(57, 25.96), 0.0, {"w": 6.0, "d": 5.5, "floors": 0, "roof": "eaves", "door_x": 0.6, "seed": 444, "lit": 0.5}],
	["west_n", Vector2(46, 25.96), 0.0, {"w": 6.5, "d": 6.0, "floors": 0, "roof": "gable", "door_x": 0.8, "seed": 443, "lit": 0.6, "chimney": true}],
	["east_s", Vector2(90, 34.04), 180.0, {"w": 7.0, "d": 6.0, "floors": 1, "roof": "gable", "upper": "timber", "chimney": true, "door_x": 1.2, "seed": 445, "lit": 0.6}],
	["mid_s", Vector2(78, 34.04), 180.0, {"w": 6.0, "d": 5.5, "floors": 0, "roof": "eaves", "door_x": 0.0, "seed": 446, "lit": 0.5}],
	["west_s", Vector2(64, 34.04), 180.0, {"w": 7.5, "d": 6.0, "floors": 0, "roof": "eaves", "chimney": true, "door_x": -1.4, "seed": 447, "lit": 0.6}],
	["corner_s", Vector2(39, 34.04), 180.0, {"w": 5.0, "d": 5.0, "floors": 0, "roof": "gable", "door_x": 0.0, "seed": 449, "lit": 0.4}],
	["ferryman", Vector2(46.26, 44), 90.0, {"w": 4.5, "d": 4.0, "floors": 0, "roof": "eaves", "chimney": true, "door_x": 0.0, "seed": 448, "lit": 0.7,
		"door": {"name": "渡工的小屋", "text": "门锁着。渡工这会儿不在屋里。"}}],
]
## 托宾的小屋：泥炭场东头的干地上（不用高脚），正面朝西
const TOBIN_HUT := [Vector2(87, 1), -90.0, {"w": 4.5, "d": 4.0, "floors": 0, "roof": "eaves", "chimney": true, "door_x": 0.0, "seed": 450, "lit": 0.7,
	"door": {"name": "泥炭工头的小屋", "text": "门锁着。泥炭工头大概在场子里。"}}]
## 泥炭垛：[中心, 朝向（度）]，每垛 2.6 × 1.6 米、1.4 米高（一个碰撞盒；4.9 泥炭工点火拦人会用到）
const PEAT := [[Vector2(57.5, -3.2), 4.0], [Vector2(61.2, -3.0), -3.0], [Vector2(57.8, 1.4), 2.0],
	[Vector2(72.5, -3.3), -5.0], [Vector2(76.2, -3.0), 3.0], [Vector2(79.8, -3.4), -2.0]]
const PEAT_SIZE := Vector3(2.6, 1.4, 1.6)
const PEAT_CUT := Rect2(70, 2, 14, 5)         # 泥炭场里挖开的一片湿地（只是画面，深色）
## 平底船：[中心, 朝向（度）, 在哪儿（水上 / 泥上）]
const PUNTS := [[Vector2(41.3, 60.5), 90.0, "water"], [Vector2(58.7, 60.0), 88.0, "water"], [Vector2(33.5, 41.0), 20.0, "mud"]]
## 晾鱼、晾芦苇的木架：[中心, 朝向]
const RACKS := [[Vector2(96.5, 37.5), 0.0], [Vector2(70.0, 38.5), 90.0], [Vector2(104.5, 19.5), 0.0]]
## 芦苇荡（水里成片的芦苇，地图上也画）：鹭沼深处（4.4c 才走得进去）、堤道两边远处、村子北边
const REED_BEDS := [Rect2(-128, 0, 150, 64), Rect2(-60, -40, 44, 26), Rect2(10, -60, 30, 24), Rect2(60, -50, 40, 30),
	Rect2(104, -20, 24, 28), Rect2(-128, -64, 40, 40), Rect2(4, 4, 22, 46)]
## 不长芦苇的水面：码头前面的开阔水面
const OPEN_WATER := [Rect2(38, 53, 26, 11)]
## 雾带：[位置, 浓度]（贴着水面、泥滩；块按位置分）
const FOG := [
	[Vector3(84, 0.3, 46), 0.55], [Vector3(60, 0.3, 48), 0.6], [Vector3(40, 0.3, 20), 0.55], [Vector3(76, 0.35, 10), 0.5],
	[Vector3(110, 0.3, 4), 0.6], [Vector3(16, 0.0, -18), 0.65], [Vector3(-2, 0.1, -42), 0.7], [Vector3(-14, 0.1, -30), 0.65],
	[Vector3(-30, 0.1, -50), 0.6], [Vector3(-46, 0.1, -60), 0.7], [Vector3(-12, 0.0, -66), 0.6], [Vector3(-60, 0.0, 20), 0.7],
	[Vector3(-20, 0.0, 30), 0.65], [Vector3(-96, 0.0, -30), 0.7],
]
## 出生点（world/areas.gd）：reedwharf = 从霜渡镇来，站在村口、面朝西；castle_gate = 黑鹭堡门前的石台上、面朝堡门
const SPAWNS := {
	"reedwharf": [Vector3(118, BANK_Y, 30), 90.0],
	"castle_gate": [Vector3(-28.81, CAUSE_Y, -66.81), 45.0],
}
const SIGN_VILLAGE := Vector3(114, BANK_Y, 32.4)      # 村口的路牌（出发的地方，TravelPoint）
const SIGN_GATE := Vector3(-32.0, CAUSE_Y, -62.2)     # 堡门前的路牌
const SIGN_CAUSEWAY := Vector3(38.6, BANK_Y, -3.5)    # 堤道头的指路牌（只是牌子）
const EXIT_AT := Vector3(128, BANK_Y, 30)             # 路从这里出图（往霜渡镇；不是门，出发走村口的路牌）
const VIEW_NAMES := ["村口", "客栈前", "小码头", "堤道上看黑鹭堡", "堡门前", "泥滩里"]
## 网页 ?area=marsh&view=N 的固定机位：位置、水平朝向（度，0 = 面朝 -Z，正 = 向左转）、俯仰（度）
const VIEWS := [
	[Vector3(118, BANK_Y, 30), 90.0, -3.0],
	[Vector3(80.5, DECK_Y, 31.0), 40.0, 2.0],
	[Vector3(50, DECK_Y, 60.5), 10.0, -2.0],
	[Vector3(18.6, CAUSE_Y, -19.4), 45.0, 1.0],
	[Vector3(-26.0, CAUSE_Y, -64.0), 45.0, 6.0],
	[Vector3(58.0, MUD_Y, 44.0), 30.0, -4.0],
]


## 堤道上的点：沿堤道 t 米、往东北偏 off 米
static func cw(t: float, off := 0.0) -> Vector2:
	return CW_START + CW_DIR * t + CW_SIDE * off


static func cw3(t: float, off := 0.0, y := CAUSE_Y) -> Vector3:
	var p := cw(t, off)
	return Vector3(p.x, y, p.y)


## 一个轴对齐的矩形地面
static func rect_floor(id: String, k: String, r: Rect2, top: float) -> Dictionary:
	return {"id": id, "k": k, "c": r.get_center(), "size": r.size, "yaw": 0.0, "top": top, "pitch": 0.0, "tilt": 0.0}


## 沿堤道的一条：t0..t1、中线偏 off、宽 width
static func strip(id: String, k: String, t0: float, t1: float, off: float, width: float, top: float, pitch := 0.0, tilt := 0.0) -> Dictionary:
	return {"id": id, "k": k, "c": cw((t0 + t1) * 0.5, off), "size": Vector2(width, t1 - t0), "yaw": CW_YAW, "top": top, "pitch": pitch, "tilt": tilt}


## 所有地面（顺序就是建碰撞的顺序）。每次现算（三十来块，很快）；不放静态缓存
static func floors() -> Array:
	var out := []
	out.append(rect_floor("bank", "land", BANK, BANK_Y))
	out.append(rect_floor("village_mud", "mud", VILLAGE_MUD, MUD_Y))
	out.append(rect_floor("peat_yard", "land", PEAT_YARD, BANK_Y))
	out.append(rect_floor("head", "land", HEAD, BANK_Y))
	for w in WALKS:
		out.append(rect_floor("walk_" + str(w[0]), "deck", walk_rect(w), DECK_Y))
	out.append(rect_floor("dock", "deck", DOCK, DECK_Y))
	# 堤道：头上一段缓坡，然后两截路面（中间断口），两边石坡、泥滩；断口上搭木板；尽头石台
	var rise := rad_to_deg(atan2(CAUSE_Y - BANK_Y, CW_RAMP))
	out.append(strip("cw_ramp", "stone", 0.0, CW_RAMP, 0.0, CW_W, (CAUSE_Y + BANK_Y) * 0.5, rise))
	out.append(strip("cw_a", "stone", CW_RAMP, GAP.x, 0.0, CW_W, CAUSE_Y))
	out.append(strip("cw_b", "stone", GAP.y, APRON_T.x, 0.0, CW_W, CAUSE_Y))
	out.append(strip("bridge", "bridge", GAP.x - 0.4, GAP.y + 0.4, 0.0, BRIDGE_W, CAUSE_Y))
	var sw := slope_width()
	for seg in [["a", CW_RAMP, GAP.x - 1.0], ["b", GAP.y + 1.0, APRON_T.x]]:
		for side in [1.0, -1.0]:
			var tag := "%s_%s" % [seg[0], "ne" if side > 0.0 else "sw"]
			out.append(strip("slope_" + tag, "slope", seg[1], seg[2], side * (CW_W * 0.5 + sw * 0.5), sw, (CAUSE_Y + MUD_Y) * 0.5, 0.0, -side * CW_SLOPE))
			out.append(strip("cwmud_" + tag, "mud", seg[1], seg[2], side * (CW_W * 0.5 + sw + CW_MUD * 0.5), CW_MUD, MUD_Y))
	out.append(strip("apron", "stone", APRON_T.x, APRON_T.y, 0.0, APRON_W, CAUSE_Y))
	return out


## 两边石坡的水平宽度：从路面（CAUSE_Y）坡到泥滩（MUD_Y）
static func slope_width() -> float:
	return (CAUSE_Y - MUD_Y) / tan(deg_to_rad(CW_SLOPE))


## 一段木栈道的矩形
static func walk_rect(w: Array) -> Rect2:
	var a: Vector2 = w[1]
	var b: Vector2 = w[2]
	var half := float(w[3]) * 0.5
	var r := Rect2(a, Vector2.ZERO).expand(b)
	return r.grow_individual(half if r.size.x < 0.01 else 0.0, half if r.size.y < 0.01 else 0.0, half if r.size.x < 0.01 else 0.0, half if r.size.y < 0.01 else 0.0)


## 世界 XZ → 这块地面的本地坐标（x 宽、z 长）
static func local_of(f: Dictionary, p: Vector2) -> Vector2:
	var r := deg_to_rad(float(f.yaw))
	var d: Vector2 = p - f.c
	return Vector2(d.x * cos(r) - d.y * sin(r), d.x * sin(r) + d.y * cos(r))


static func world_of(f: Dictionary, l: Vector2) -> Vector2:
	var r := deg_to_rad(float(f.yaw))
	return f.c + Vector2(cos(r), -sin(r)) * l.x + Vector2(sin(r), cos(r)) * l.y


static func contains(f: Dictionary, p: Vector2, grow := 0.0) -> bool:
	var l := local_of(f, p)
	var h: Vector2 = f.size * 0.5
	return absf(l.x) <= h.x + grow and absf(l.y) <= h.y + grow


## 点到这块地面的水平距离（在里面 = 0）
static func distance(f: Dictionary, p: Vector2) -> float:
	var l := local_of(f, p)
	var h: Vector2 = f.size * 0.5
	return Vector2(maxf(absf(l.x) - h.x, 0.0), maxf(absf(l.y) - h.y, 0.0)).length()


static func corners(f: Dictionary) -> PackedVector2Array:
	var h: Vector2 = f.size * 0.5
	var out := PackedVector2Array()
	for c in [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]:
		out.append(world_of(f, c))
	return out


static func aabb(f: Dictionary) -> Rect2:
	var pts := corners(f)
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


## 碰撞盒 / 网格盒的朝向：绕 Y 转 yaw，再绕本地 x 抬 pitch（正 = -Z 那头高）、绕本地 z 侧倾 tilt（正 = -X 那头低）
static func basis_of(f: Dictionary) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(float(f.yaw))) * Basis(Vector3.RIGHT, deg_to_rad(float(f.get("pitch", 0.0)))) * Basis(Vector3.BACK, deg_to_rad(float(f.get("tilt", 0.0))))


## 地面盒子：[变换, 尺寸]，顶面中心在 (c, top)，往下 thick 米
static func box_of(f: Dictionary, thick: float) -> Array:
	var b := basis_of(f)
	var c: Vector2 = f.c
	var center := Vector3(c.x, float(f.top), c.y) - b.y * (thick * 0.5)
	var size := Vector3(f.size.x / cos(deg_to_rad(float(f.get("tilt", 0.0)))), thick, f.size.y / cos(deg_to_rad(float(f.get("pitch", 0.0)))))
	return [Transform3D(b, center), size]


## 点在哪一块（方格坐标）；图外的点夹到边上那块
static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((p.x - BOUNDS.position.x) / CELL), 0, COLS - 1), clampi(floori((p.y - BOUNDS.position.y) / CELL), 0, ROWS - 1))


static func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(BOUNDS.position + Vector2(c) * CELL, Vector2(CELL, CELL))


static func cell_id(c: Vector2i) -> String:
	return "%d_%d" % [c.x, c.y]


## 高脚屋的世界坐标位置（y = 地板）
static func house_pos(h: Array) -> Vector3:
	var p: Vector2 = h[1]
	return Vector3(p.x, DECK_Y + STILTS, p.y)


static func house_spec(h: Array) -> Dictionary:
	var s: Dictionary = (h[3] as Dictionary).duplicate()
	s.merge({"base": "timber", "roof_mat": "thatch", "snow": false, "stilts": STILTS, "solid": false})
	return s


static func tobin_spec() -> Dictionary:
	var s: Dictionary = (TOBIN_HUT[2] as Dictionary).duplicate()
	s.merge({"base": "timber", "roof_mat": "thatch", "snow": false, "solid": false})
	return s


## 黑鹭堡的摆放：中心在堤道延长线上 t = CASTLE_T，正面朝东南（对着堤道）
static func castle_xform() -> Transform3D:
	var c := cw(CASTLE_T)
	return Transform3D(Basis(Vector3.UP, deg_to_rad(CW_YAW)), Vector3(c.x, 0, c.y))


## 地图上的分块（core/area_map.gd zones）：先查窄的；place = 旅行地图上的哪个地点（Travel.place_of_area 按它分）
static func zones() -> Array:
	# 黑鹭堡外从 t = 76 起：堡门前的路牌（t ≈ 85）6 米以内都算黑鹭堡（站在那里能出发，审查）；堤道从堤道头的缓坡起（不留不属于哪块的角）
	var gate := PackedVector2Array([cw(APRON_T.x - 6.0, -12), cw(APRON_T.x - 6.0, 12), cw(CASTLE_T + 26.0, 30), cw(CASTLE_T + 26.0, -30)])
	var causeway := PackedVector2Array([cw(4.0, -14), cw(4.0, 14), cw(APRON_T.x - 6.0, 14), cw(APRON_T.x - 6.0, -14)])
	var village := PackedVector2Array([Vector2(20, -14), Vector2(128, -14), Vector2(128, 64), Vector2(20, 64)])
	return [
		{"id": "gate", "name": "黑鹭堡外", "place": "blackheron", "pts": gate},
		{"id": "causeway", "name": "堤道", "place": "", "pts": causeway},
		{"id": "village", "name": "芦栈村", "place": "reedwharf", "pts": village},
	]
