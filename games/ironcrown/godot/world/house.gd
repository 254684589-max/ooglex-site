class_name House
extends RefCounted
## 北境半木结构房屋（ART.md 第六节）：石砌底层 + 木构架灰泥上层（上层向街面挑出一点）+ 陡峭石板瓦屋顶（屋脊积雪）。
## 代码搭几何体 + 写实贴图；整栋房子按材质合并成一个网格。人物、道具以外的建筑都用它搭。
##
## 本地坐标：原点在正面墙脚中点，正面朝 +Z，房子往 -Z 方向纵深 d 米，宽 w 米（x 从 -w/2 到 w/2）。
## spec 字段：
##   w, d          宽、纵深（米）
##   floors        上层层数（1 或 2；领主宅邸 2）
##   roof          "eaves"（屋脊平行街面，檐口朝街）或 "gable"（山墙朝街）
##   seed          随机种子（哪些窗亮着）
##   lit           亮窗比例 0..1
##   door_x        门在正面的位置（本地 x）
##   door          {} = 普通木门（不能交互）；{"name": "...", "text": "..."} = 锁着的门（可交互，提示 text）；
##                 {"name": "...", "to_area": "tavern", "to_spawn": "front", "verb": "进入"} = 通往另一个区域的门（3.1）
##   sign          酒馆招牌上的字（"" = 没有招牌）
##   chimney       是否有烟囱
##   stone_upper   上层也用石砌（领主宅邸）
## 鹭沼的高脚屋（4.4 芦栈村）另有几个选项，不写时和原来一样：
##   base          "stone"（默认，石砌底层）或 "timber"（木板墙底层，没有石基；窗台、门楣也是木头）
##   upper         上层的墙："plaster"（默认，灰泥）或 "timber"（木板）
##   roof_mat      "roof"（默认，石板瓦）或 "thatch"（茅草，Look.thatch()）
##   snow          屋顶积雪（默认 true）
##   stilts        高脚的高度（米，默认 0）：pos 是屋里地板的高度，地板下面立桩子，门前一块小平台、几级台阶下到 pos.y - stilts
##   solid         自己建碰撞（默认 true）；false = 由区域在搭场景时先用 House.solids() 建好（鹭沼：碰撞一次建完，网格分帧搭）

const GROUND_H := 3.0
const FLOOR_H := 2.6
const JETTY := 0.35          # 上层向街面挑出
const PITCH := 48.0
const EAVE := 0.45
const T := 0.14              # 木梁粗细
const PORCH_D := 1.3         # 高脚屋门前平台的进深、宽
const PORCH_W := 2.4
const STAIR_SLOPE := 32.0    # 高脚屋台阶的坡度（度）：碰撞是一块斜板，主角走得上去（地面最陡 46°）
const STAIR_W := 1.4

## 建一栋房子，挂在 parent 下；pos 是正面墙脚中点（世界坐标），yaw 是绕 Y 轴的角度（度）
static func build(parent: Node3D, pos: Vector3, yaw: float, spec: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "House"
	root.position = pos
	root.rotation_degrees.y = yaw
	root.add_to_group("house")
	parent.add_child(root)
	var w: float = spec.get("w", 7.0)
	var d: float = spec.get("d", 7.0)
	var floors: int = spec.get("floors", 1)
	var stone_upper: bool = spec.get("stone_upper", false)
	var rng := RandomNumberGenerator.new()
	rng.seed = spec.get("seed", 1)
	var lit: float = spec.get("lit", 0.55)
	var door_x: float = spec.get("door_x", 0.0)
	var kit := MeshKit.new()
	var top := GROUND_H + floors * FLOOR_H
	var upper := "stone" if stone_upper else str(spec.get("upper", "plaster"))
	var jetty := 0.0 if stone_upper else JETTY
	var windows := {"lit": 0, "dark": 0}
	var timber_base := str(spec.get("base", "stone")) == "timber"
	var trim := "timber" if timber_base else "stone"           # 窗台、门楣、门前台阶
	var roof_key := str(spec.get("roof_mat", "roof"))
	var snow: bool = spec.get("snow", true)
	var stilts := float(spec.get("stilts", 0.0))

	if timber_base:
		# 木板墙底层（4.4 高脚屋）：墙脚压暗；四角立柱、墙脚一道地梁
		kit.box("timber", Vector3(0, GROUND_H * 0.5, -d * 0.5), Vector3(w, GROUND_H, d), Basis.IDENTITY, 1.0, 0.6)
		for cx in [-w * 0.5, w * 0.5]:
			for cz in [0.0, -d]:
				kit.box("timber", Vector3(cx, GROUND_H * 0.5, cz), Vector3(0.22, GROUND_H, 0.22), Basis.IDENTITY, 0.75, 0.55)
		kit.box("timber", Vector3(0, 0.12, -d * 0.5), Vector3(w + 0.14, 0.24, d + 0.14), Basis.IDENTITY, 0.6, 0.45)
	else:
		# 底层石砌：墙脚压暗（顶点色遮蔽）
		kit.box("stone", Vector3(0, GROUND_H * 0.5, -d * 0.5), Vector3(w, GROUND_H, d), Basis.IDENTITY, 1.0, 0.55)
		# 墙脚一圈略宽的石基
		kit.box("stone", Vector3(0, 0.2, -d * 0.5), Vector3(w + 0.16, 0.4, d + 0.16), Basis.IDENTITY, 0.7, 0.45)
	if stilts > 0.0:
		_stilts(kit, w, d, stilts, float(spec.get("door_x", 0.0)))
	# 上层：灰泥（或石砌），向街面挑出 jetty
	for f in floors:
		var y0 := GROUND_H + f * FLOOR_H
		kit.box(upper, Vector3(0, y0 + FLOOR_H * 0.5, -d * 0.5 + jetty * 0.5), Vector3(w, FLOOR_H, d + jetty), Basis.IDENTITY, 0.8, 1.0)
		if not stone_upper:
			_timber_frame(kit, w, d, y0, jetty, rng, lit, windows, trim)
		else:
			_upper_windows_stone(kit, w, y0, rng, lit, windows)
		# 楼层之间一道横梁（挑出处的托梁）
		kit.box("timber", Vector3(0, y0 - 0.06, jetty * 0.5 + 0.02), Vector3(w + 0.12, 0.16, jetty + 0.2), Basis.IDENTITY, 0.6, 0.5)
	# 底层的窗与门
	_ground_floor(kit, w, door_x, rng, lit, windows, spec, trim)
	# 屋顶（山墙三角：有上层时跟上层的墙，只有一层时跟底层的墙）
	var roof: String = spec.get("roof", "eaves")
	var gable_wall := "timber" if timber_base and floors == 0 else upper
	var front := -1.0                                        # 山墙三角的前沿（-1 = 原来的算法）；木底层的高脚屋按有没有上层算
	if timber_base:
		front = jetty if floors > 0 else 0.0
	if roof == "gable":
		_roof_gable(kit, w, d, top, jetty, gable_wall, rng.randf() < lit, windows, roof_key, snow, trim, front)
	else:
		_roof_eaves(kit, w, d, top, jetty, gable_wall, roof_key, snow, front)
	if spec.get("chimney", false):
		var cx := w * 0.28
		var cz := -d * 0.62
		var ch := 4.2 if roof == "eaves" else 3.6
		kit.box("stone", Vector3(cx, top + ch * 0.5, cz), Vector3(0.7, ch, 0.7), Basis.IDENTITY, 1.0, 0.7)
		kit.box("stone", Vector3(cx, top + ch + 0.06, cz), Vector3(0.86, 0.12, 0.86))
	var mats := {"stone": Look.mat("stone"), "plaster": Look.mat("plaster"), "timber": Look.mat("timber"),
		"roof": Look.mat("roof"), "snow": Look.mat("snow"), "glass_lit": Look.glass_lit(), "glass_dark": Look.glass_dark(),
		"halo": Look.halo(Look.WINDOW_COLOR, 0.32)}
	if roof_key == "thatch":
		mats["thatch"] = Look.thatch()
	var mi := kit.build(mats)
	mi.name = "Mesh"
	root.add_child(mi)
	root.set_meta("windows", windows)
	root.set_meta("seed", int(spec.get("seed", 1)))     # 时段（4.2）：清晨按种子挑一部分房子还亮着灯
	root.set_meta("size", Vector2(w, d))                 # 地图（3.11）：测试按它查地图上画的房子和场景对得上
	# 碰撞：整栋房子一个盒子（屋顶、挑出的上层在头顶以上，不用碰撞）；高脚屋另有门前平台和台阶（House.solids）
	if spec.get("solid", true):
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		for b in solids(Vector3.ZERO, 0.0, spec):
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = b[1]
			cs.shape = bs
			cs.transform = b[0]
			body.add_child(cs)
		root.add_child(body)
	# 不放遮挡体：网页导出模板编译时去掉了遮挡剔除，场景里有 OccluderInstance3D 就会报错（1.4 实测，TECH.md 4.6）
	# 门：锁着的门可以交互；普通门只是一块木板
	var dspec: Dictionary = spec.get("door", {})
	if not dspec.is_empty():
		var door := Door.make(dspec.get("name", "门"), 1.1, 2.1, not dspec.has("to_area"))
		door.locked_text = dspec.get("text", "门锁着。")
		door.to_area = str(dspec.get("to_area", ""))
		door.to_spawn = str(dspec.get("to_spawn", ""))
		door.verb = str(dspec.get("verb", "进入"))
		door.position = Vector3(door_x - 0.55, 0, 0.05)
		root.add_child(door)
	var sign_text: String = spec.get("sign", "")
	if sign_text != "":
		_sign(root, door_x + 1.3, sign_text)
	return root


## 房子的碰撞盒：[[变换, 尺寸], ...]，变换是相对 pos、yaw 摆好的（pos = 正面墙脚中点，同 build）。
## 房身一个盒子（高脚屋从桩脚算起）；高脚屋再加门前平台、一块斜板当台阶。区域可以先用它把碰撞建好、网格以后再搭（spec.solid = false）
static func solids(pos: Vector3, yaw: float, spec: Dictionary) -> Array:
	var w: float = spec.get("w", 7.0)
	var d: float = spec.get("d", 7.0)
	var top := GROUND_H + int(spec.get("floors", 1)) * FLOOR_H
	var h := float(spec.get("stilts", 0.0))
	var door_x: float = spec.get("door_x", 0.0)
	var place := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), pos)
	var out := [[place * Transform3D(Basis.IDENTITY, Vector3(0, (top - h) * 0.5, -d * 0.5)), Vector3(w + 0.16, top + h, d + 0.16)]]
	if h > 0.0:
		out.append([place * Transform3D(Basis.IDENTITY, Vector3(door_x, -0.1, PORCH_D * 0.5)), Vector3(PORCH_W, 0.2, PORCH_D)])
		var run := h / tan(deg_to_rad(STAIR_SLOPE))
		var length := sqrt(h * h + run * run)
		var b := Basis(Vector3.RIGHT, deg_to_rad(STAIR_SLOPE))      # 绕 x 转：往 +Z（屋外）走是下坡
		var mid := Vector3(door_x, -h * 0.5, PORCH_D + run * 0.5) - b.y * 0.1
		out.append([place * Transform3D(b, mid), Vector3(STAIR_W, 0.2, length)])
	return out


## 高脚屋台阶的落脚点（本地 z）：门前平台进深 + 台阶的水平长度；区域按它把房子摆在栈道边上
static func stair_reach(stilts: float) -> float:
	return PORCH_D + stilts / tan(deg_to_rad(STAIR_SLOPE))


## 地图用（3.11）：本地坐标（x, z）→ 世界 XZ。本地 +Z 是正面朝向；绕 Y 转 yaw 度
static func local_xz(pos: Vector3, yaw: float, p: Vector2) -> Vector2:
	var r := deg_to_rad(yaw)
	return Vector2(pos.x + p.x * cos(r) + p.y * sin(r), pos.z - p.x * sin(r) + p.y * cos(r))


## 正面朝向（世界 XZ 的单位向量）
static func facing(yaw: float) -> Vector2:
	var r := deg_to_rad(yaw)
	return Vector2(sin(r), cos(r))


## 房子占地的四个角（世界 XZ，顺时针或逆时针都行）：正面墙脚在 pos，往背后纵深 d
static func footprint(pos: Vector3, yaw: float, w: float, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for c in [Vector2(-w * 0.5, 0), Vector2(w * 0.5, 0), Vector2(w * 0.5, -d), Vector2(-w * 0.5, -d)]:
		out.append(local_xz(pos, yaw, c))
	return out


## 门的中心（世界 XZ）：门宽 1.1，门轴在 door_x - 0.55
static func door_xz(pos: Vector3, yaw: float, door_x: float) -> Vector2:
	return local_xz(pos, yaw, Vector2(door_x, 0.05))


## 一扇窗：玻璃（亮 / 暗）+ 木窗框 + 窗台；亮窗外加一片光晕，暗窗有一半关着百叶
static func _window(kit: MeshKit, c: Vector3, ww: float, wh: float, on: bool, closed: bool, windows: Dictionary, sill := "stone") -> void:
	var z := c.z
	var g := "glass_lit" if on else "glass_dark"
	kit.quad(g, [c + Vector3(-ww / 2, wh / 2, 0.005), c + Vector3(ww / 2, wh / 2, 0.005), c + Vector3(ww / 2, -wh / 2, 0.005), c + Vector3(-ww / 2, -wh / 2, 0.005)], Vector3.BACK)
	var f := 0.08
	kit.box("timber", c + Vector3(0, wh / 2 + f / 2, 0.03), Vector3(ww + 2 * f, f, 0.08), Basis.IDENTITY, 0.85, 0.85)
	kit.box("timber", c + Vector3(0, -wh / 2 - f / 2, 0.03), Vector3(ww + 2 * f, f, 0.08), Basis.IDENTITY, 0.85, 0.85)
	kit.box("timber", c + Vector3(-ww / 2 - f / 2, 0, 0.03), Vector3(f, wh, 0.08), Basis.IDENTITY, 0.85, 0.85)
	kit.box("timber", c + Vector3(ww / 2 + f / 2, 0, 0.03), Vector3(f, wh, 0.08), Basis.IDENTITY, 0.85, 0.85)
	kit.box("timber", c + Vector3(0, 0, 0.03), Vector3(0.04, wh, 0.05), Basis.IDENTITY, 0.8, 0.8)   # 竖窗棂
	kit.box(sill, c + Vector3(0, -wh / 2 - f - 0.05, 0.08), Vector3(ww + 0.3, 0.1, 0.22), Basis.IDENTITY, 0.9, 0.7)
	if on:
		var hw := ww * 1.6
		var hh := wh * 1.5
		# 光晕的图（径向渐变）要铺满整个面片：UV 给 0..1。原来按米投影，一张 2.4 × 2.7 米的光晕里图重复了好几遍，
		# 窗外是一格一格的光斑（4.4 芦栈村深色木板墙上一眼就看出来；霜渡镇的灰泥墙上淡一些，一直都有）
		kit.quad("halo", [c + Vector3(-hw, hh, 0.07), c + Vector3(hw, hh, 0.07), c + Vector3(hw, -hh, 0.07), c + Vector3(-hw, -hh, 0.07)], Vector3.BACK,
			[1.0, 1.0, 1.0, 1.0], [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		windows.lit += 1
	else:
		windows.dark += 1
		if closed:   # 两扇关着的百叶
			kit.box("timber", c + Vector3(-ww / 4, 0, 0.06), Vector3(ww / 2 - 0.01, wh, 0.04), Basis.IDENTITY, 0.75, 0.7)
			kit.box("timber", c + Vector3(ww / 4, 0, 0.06), Vector3(ww / 2 - 0.01, wh, 0.04), Basis.IDENTITY, 0.75, 0.7)


static func _ground_floor(kit: MeshKit, w: float, door_x: float, rng: RandomNumberGenerator, lit: float, windows: Dictionary, spec: Dictionary, trim := "stone") -> void:
	# 门洞：木门框 + 门楣石；门板另外放（可交互的 Door 或一块木板）
	var dw := 1.1
	var dh := 2.1
	kit.box("timber", Vector3(door_x - dw / 2 - 0.07, dh / 2, 0.04), Vector3(0.14, dh, 0.12), Basis.IDENTITY, 0.8, 0.6)
	kit.box("timber", Vector3(door_x + dw / 2 + 0.07, dh / 2, 0.04), Vector3(0.14, dh, 0.12), Basis.IDENTITY, 0.8, 0.6)
	kit.box(trim, Vector3(door_x, dh + 0.12, 0.06), Vector3(dw + 0.5, 0.24, 0.16), Basis.IDENTITY, 0.9, 0.8)
	if float(spec.get("stilts", 0.0)) <= 0.0:
		kit.box(trim, Vector3(door_x, 0.06, 0.3), Vector3(dw + 0.4, 0.12, 0.6), Basis.IDENTITY, 0.8, 0.6)   # 门前台阶（高脚屋是平台和台阶，_stilts）
	if (spec.get("door", {}) as Dictionary).is_empty():
		kit.box("timber", Vector3(door_x, dh / 2, 0.02), Vector3(dw, dh, 0.06), Basis.IDENTITY, 0.8, 0.6)
	# 窗：避开门，间隔 1.9 米
	var x := -w / 2 + 1.1
	while x <= w / 2 - 1.0:
		if absf(x - door_x) > 1.3:
			var on := rng.randf() < lit
			_window(kit, Vector3(x, 1.55, 0.0), 0.75, 0.9, on, rng.randf() < 0.5, windows, trim)
		x += 1.9


## 上层正面的木构架：底梁、顶梁、立柱，两端的斜撑；立柱之间开窗。两个侧面也有角柱和梁。
static func _timber_frame(kit: MeshKit, w: float, d: float, y0: float, jetty: float, rng: RandomNumberGenerator, lit: float, windows: Dictionary, trim := "stone") -> void:
	var zf := jetty + 0.025
	var n := maxi(2, roundi(w / 1.5))
	kit.box("timber", Vector3(0, y0 + T / 2, zf), Vector3(w + 0.06, T + 0.04, 0.1), Basis.IDENTITY, 0.8, 0.7)
	kit.box("timber", Vector3(0, y0 + FLOOR_H - T / 2, zf), Vector3(w + 0.06, T + 0.04, 0.1), Basis.IDENTITY, 0.6, 0.6)
	var bay := w / n
	for i in n + 1:
		var px := -w / 2 + i * bay
		kit.box("timber", Vector3(clampf(px, -w / 2 + T / 2, w / 2 - T / 2), y0 + FLOOR_H / 2, zf), Vector3(T, FLOOR_H, 0.1), Basis.IDENTITY, 0.7, 0.85)
	for i in n:
		var cx := -w / 2 + (i + 0.5) * bay
		if (i == 0 or i == n - 1) and n >= 3:
			# 斜撑：从柱脚斜到柱顶
			var ang := atan2(FLOOR_H - 2 * T, bay)
			var len := sqrt(pow(bay, 2) + pow(FLOOR_H - 2 * T, 2))
			var sgn := 1.0 if i == 0 else -1.0
			kit.box("timber", Vector3(cx, y0 + FLOOR_H / 2, zf), Vector3(len, T * 0.9, 0.09), Basis(Vector3.BACK, ang * sgn), 0.75, 0.75)
		else:
			var on := rng.randf() < lit
			_window(kit, Vector3(cx, y0 + 1.35, jetty), minf(0.7, bay - 0.5), 0.9, on, rng.randf() < 0.4, windows, trim)
			kit.box("timber", Vector3(cx, y0 + 0.62, zf), Vector3(bay - T, T * 0.8, 0.09), Basis.IDENTITY, 0.75, 0.75)   # 窗下横档
	# 两个侧面：角柱 + 中柱 + 底梁 / 顶梁
	for s in [-1.0, 1.0]:
		var xf: float = s * (w / 2 + 0.025)
		for zc in [jetty - T / 2, -d / 2, -d + T / 2]:
			kit.box("timber", Vector3(xf, y0 + FLOOR_H / 2, zc), Vector3(0.1, FLOOR_H, T), Basis.IDENTITY, 0.7, 0.85)
		for yy in [y0 + T / 2, y0 + FLOOR_H - T / 2]:
			kit.box("timber", Vector3(xf, yy, (jetty - d) / 2), Vector3(0.1, T, d + jetty), Basis.IDENTITY, 0.7, 0.7)


## 石砌上层（领主宅邸）的窗：均匀排开
static func _upper_windows_stone(kit: MeshKit, w: float, y0: float, rng: RandomNumberGenerator, lit: float, windows: Dictionary) -> void:
	var x := -w / 2 + 1.2
	while x <= w / 2 - 1.1:
		_window(kit, Vector3(x, y0 + 1.4, 0.0), 0.8, 1.2, rng.randf() < lit, rng.randf() < 0.3, windows)
		x += 2.0


## 屋脊平行街面：前后两片斜面 + 两侧山墙三角 + 积雪
static func _roof_eaves(kit: MeshKit, w: float, d: float, top: float, jetty: float, wall: String, roof_key := "roof", snow := true, front := -1.0) -> void:
	var t := tan(deg_to_rad(PITCH))
	var zr := (jetty - d) * 0.5
	var half := (jetty + d) * 0.5
	var s := half + EAVE
	var length := s / cos(deg_to_rad(PITCH))
	var rise_wall := half * t
	for side in [1.0, -1.0]:
		var b := Basis(Vector3.RIGHT, deg_to_rad(PITCH) * side)
		var center := Vector3(0, top + rise_wall - s * 0.5 * t + 0.08, zr + side * s * 0.5)
		kit.box(roof_key, center, Vector3(w + 0.6, 0.16, length), b, 1.0, 0.6, true)
		if snow:
			# 积雪：靠屋脊的四成
			var up := b * Vector3.UP
			var snow_c := Vector3(0, top + rise_wall - s * 0.18 * t + 0.08, zr + side * s * 0.18) + up * 0.1
			kit.box("snow", snow_c, Vector3(w + 0.62, 0.06, length * 0.36), b)
	for sx in [-1.0, 1.0]:
		var x: float = sx * w / 2
		var fz := front if front >= 0.0 else (jetty if wall == "plaster" else 0.0)
		kit.tri(wall, Vector3(x, top, fz), Vector3(x, top, -d), Vector3(x, top + rise_wall, zr), Vector3(sx, 0, 0), 0.85)
	if snow:
		kit.box("snow", Vector3(0, top + rise_wall + 0.2, zr), Vector3(w + 0.62, 0.12, 0.36))   # 屋脊上的雪
	else:
		kit.box(roof_key, Vector3(0, top + rise_wall + 0.16, zr), Vector3(w + 0.62, 0.16, 0.42), Basis.IDENTITY, 0.8, 0.7)   # 屋脊压一道


## 山墙朝街：左右两片斜面 + 前后山墙三角（正面山墙有木构架和一扇阁楼窗）
static func _roof_gable(kit: MeshKit, w: float, d: float, top: float, jetty: float, wall: String, attic_lit: bool, windows: Dictionary, roof_key := "roof", snow := true, trim := "stone", front := -1.0) -> void:
	var t := tan(deg_to_rad(PITCH))
	var half := w * 0.5
	var s := half + 0.35
	var length := s / cos(deg_to_rad(PITCH))
	var rise_wall := half * t
	var depth := d + jetty + 0.7
	var zc := (jetty - d) * 0.5
	for side in [1.0, -1.0]:
		# side = 1：右片（+X 一侧，往 +X 下斜）
		var b := Basis(Vector3.BACK, -deg_to_rad(PITCH) * side)
		var center := Vector3(side * s * 0.5, top + rise_wall - s * 0.5 * t + 0.08, zc)
		kit.box(roof_key, center, Vector3(length, 0.16, depth), b, 1.0, 0.6, true)
		if snow:
			var up := b * Vector3.UP
			kit.box("snow", Vector3(side * s * 0.18, top + rise_wall - s * 0.18 * t + 0.08, zc) + up * 0.1, Vector3(length * 0.36, 0.06, depth + 0.02), b)
	var zf := front if front >= 0.0 else jetty
	kit.tri(wall, Vector3(-half, top, zf), Vector3(half, top, zf), Vector3(0, top + rise_wall, zf), Vector3.BACK, 0.85)
	kit.tri(wall, Vector3(-half, top, -d), Vector3(half, top, -d), Vector3(0, top + rise_wall, -d), Vector3.FORWARD, 0.85)
	if snow:
		kit.box("snow", Vector3(0, top + rise_wall + 0.2, zc), Vector3(0.36, 0.12, depth + 0.02))
	else:
		kit.box(roof_key, Vector3(0, top + rise_wall + 0.16, zc), Vector3(0.42, 0.16, depth + 0.02), Basis.IDENTITY, 0.8, 0.7)
	if wall == "plaster":
		# 山墙上的木构架：中柱 + 一道横梁 + 一扇小阁楼窗
		kit.box("timber", Vector3(0, top + rise_wall * 0.5, zf + 0.025), Vector3(T, rise_wall, 0.1), Basis.IDENTITY, 0.7, 0.8)
		kit.box("timber", Vector3(0, top + rise_wall * 0.35, zf + 0.025), Vector3(w * 0.62, T, 0.1), Basis.IDENTITY, 0.7, 0.7)
		_window(kit, Vector3(-w * 0.17, top + rise_wall * 0.18 + 0.05, zf), 0.5, 0.6, attic_lit, false, windows, trim)


## 高脚（4.4）：地板下一道地梁、一排排桩子插进泥里；门前一块小平台（两根桩），台阶一级级下到 -h（碰撞是 solids() 里的斜板）
static func _stilts(kit: MeshKit, w: float, d: float, h: float, door_x: float) -> void:
	kit.box("timber", Vector3(0, -0.12, -d * 0.5), Vector3(w + 0.1, 0.24, d + 0.1), Basis.IDENTITY, 0.55, 0.4)
	var nx := maxi(2, ceili(w / 2.4) + 1)
	var nz := maxi(2, ceili(d / 2.4) + 1)
	for i in nx:
		for j in nz:
			var x := -w * 0.5 + 0.2 + (w - 0.4) * i / (nx - 1)
			var z := -0.2 - (d - 0.4) * j / (nz - 1)
			kit.cylinder("timber", Vector3(x, -h - 0.5, z), Vector3(x, -0.2, z), 0.13, 0.11, 6, 0.6)
	# 门前平台：木板面 + 两根桩
	kit.box("timber", Vector3(door_x, -0.08, PORCH_D * 0.5), Vector3(PORCH_W, 0.16, PORCH_D), Basis.IDENTITY, 0.9, 0.5)
	for sx in [-1.0, 1.0]:
		kit.cylinder("timber", Vector3(door_x + sx * (PORCH_W * 0.5 - 0.15), -h - 0.5, PORCH_D - 0.15), Vector3(door_x + sx * (PORCH_W * 0.5 - 0.15), 0.9, PORCH_D - 0.15), 0.08, 0.07, 5, 0.7)
	# 台阶：每级约 0.18 米高；两边各一根斜梁
	var run := h / tan(deg_to_rad(STAIR_SLOPE))
	var n := maxi(2, ceili(h / 0.2))
	for k in n:
		var y := -h * (k + 1) / n
		var z := PORCH_D + run * (k + 0.5) / n
		kit.box("timber", Vector3(door_x, y + 0.03, z), Vector3(STAIR_W, 0.06, run / n + 0.04), Basis.IDENTITY, 0.85, 0.6)
	var b := Basis(Vector3.RIGHT, deg_to_rad(STAIR_SLOPE))
	for sx in [-1.0, 1.0]:
		kit.box("timber", Vector3(door_x + sx * (STAIR_W * 0.5 + 0.05), -h * 0.5 - 0.08, PORCH_D + run * 0.5), Vector3(0.1, 0.18, sqrt(h * h + run * run)), b, 0.7, 0.5)


## 酒馆招牌：从墙上伸出的木臂，下面吊一块木牌，牌子两面写字
static func _sign(root: Node3D, x: float, text: String) -> void:
	var kit := MeshKit.new()
	kit.box("timber", Vector3(x, 2.95, 0.6), Vector3(0.08, 0.08, 1.2))
	kit.box("timber", Vector3(x, 2.7, 0.05), Vector3(0.08, 0.6, 0.08))
	kit.box("timber", Vector3(x, 2.5, 0.9), Vector3(0.05, 0.55, 0.9), Basis.IDENTITY, 0.8, 0.8, true)
	for dz in [0.62, 1.18]:
		kit.box("timber", Vector3(x, 2.83, dz), Vector3(0.02, 0.18, 0.02))   # 吊绳（占位）
	var mi := kit.build({"timber": Look.mat("timber")})
	root.add_child(mi)
	for s in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = text
		l.font = load(Blocks.FONT_PATH)
		l.font_size = 40
		l.pixel_size = 0.004
		l.modulate = Color("e8c88a")
		l.outline_size = 6
		l.double_sided = false
		l.position = Vector3(x + s * 0.03, 2.5, 0.9)
		l.rotation_degrees.y = 90.0 * s
		root.add_child(l)
