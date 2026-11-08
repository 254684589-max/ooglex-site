class_name WildFinds
extends RefCounted
## 荒野里的小发现（2026-11-08 所有者选「加荒野内容」）：无尽荒野（WildStreamer）里每一块有一定机会放一处——
##   ruin   塌了半边的烽燧（石头堆成的半截塔）       cairn  一堆垒起来的石头、顶上一块磨平了字的木牌
##   frozen 冻死在雪里的旅人（蜷着的斗篷、包袱）       camp   一圈熏黑的石头、冷灰、两根坐人的木头
##   hut    猎人的窝棚（斜搭的木板、挂着兽皮）         cart   翻在雪里、断了车轴的大车
## 每处一个「看看 / 翻找」的交互：一句原创的描写（按区域换几句）；有的能拿到一点东西（只拿一次，旗标 wild_<区域>_<块>，跟着存档走）。
## 位置、种类按块的种子定：同一块回来还是同一处。离手工地图 MIN_OUT 米以内不放（地图边上不突兀）。

const CHANCE := 0.22
const MIN_OUT := 30.0
const KINDS := {
	"highland": ["ruin", "ruin", "cairn", "frozen", "frozen", "camp", "hut"],
	"plain": ["cart", "cart", "camp", "cairn", "hut", "frozen"],
	"harbor": ["cairn", "camp", "frozen", "cart"],
	"forest": ["hut", "camp", "cairn", "frozen"],
}
const NAMES := {"ruin": "塌了的烽燧", "cairn": "石堆", "frozen": "冻僵的旅人", "camp": "冷了的火堆", "hut": "猎人的窝棚", "cart": "翻倒的大车"}
const TEXT := {
	"ruin": ["一座塌了半边的烽燧，石缝里还有烟熏的黑印。没人记得它是第几烽，火是哪一年灭的。", "半截石塔，顶上的火盆早被人撬走了。墙根下压着一块刻了字的石头：「守到开春」。"],
	"cairn": ["一堆垒起来的石头，顶上插着一块木牌，字被风磨平了。也许是界石，也许是坟。", "路人一块一块垒起来的石堆。最上面放着一枚生了锈的铜扣，像是谁留下的记号。"],
	"frozen": ["一个人蜷在雪里，斗篷裹得紧紧的，早就冻硬了。眼睛是闭着的——不知道是冻死的，还是睡过去的。", "雪埋了半个身子。他朝着北边倒下，手还往前伸着。"],
	"camp": ["一圈熏黑的石头，灰是冷的。旁边两根坐人的木头，雪上的脚印早被风抹平了。", "有人在这儿过过夜：灰里埋着几块没烧完的柴，石头上搁着一只裂了的陶碗。"],
	"hut": ["猎人斜搭的窝棚，门口挂着一张冻硬的兽皮。里面没人，地上铺着干草。", "一个只够一个人蜷着的窝棚。墙上用炭划了几道——十几天，或者十几个人。"],
	"cart": ["一辆翻在雪里的大车，车轴断了。麻袋早被人扛走了，车板底下还压着一点什么。", "空车。车辕上系着半截缰绳，马不知道去哪儿了。"],
}
## 拿得到的东西：[物品, 数量] 或 ["silver", 数量]；空 = 什么都没有
const LOOT := {
	"ruin": [["firewood", 1]], "cairn": [["silver", 4]], "frozen": [["silver", 9], ["bread", 1]],
	"camp": [["firewood", 2]], "hut": [["firewood", 1], ["bandage", 1]], "cart": [["bread", 2]],
}


static func place(root: Node3D, body: StaticBody3D, r: Rect2, seed: int, hf: Callable, region: String, area: String, core: Rect2) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7 + 13
	if rng.randf() > CHANCE:
		return {}
	var p := Vector2(rng.randf_range(r.position.x + 8, r.end.x - 8), rng.randf_range(r.position.y + 8, r.end.y - 8))
	if core.grow(MIN_OUT).has_point(p) or r.size.x < 20.0 or r.size.y < 20.0:
		return {}
	var kinds: Array = KINDS.get(region, KINDS.forest)
	var kind: String = kinds[rng.randi() % kinds.size()]
	var y := float(hf.call(p.x, p.y))
	var c := r.get_center()
	var at := Vector3(p.x - c.x, y, p.y - c.y)
	var yaw := rng.randf() * TAU
	var b := Basis(Vector3.UP, yaw)
	var kit := MeshKit.new()
	_build(kit, kind, at, b, rng, body)
	var mi := kit.build({"stone": Look.mat("stone"), "timber": Look.mat("timber"), "bark": Look.mat("bark"), "cloth": _flat(Color("4a3e34")), "ash": _flat(Color("2a2624")), "hide": _flat(Color("7a6248")), "snow": Look.mat("snow")})
	mi.name = "WildFind_" + kind
	mi.visibility_range_end = 160.0
	root.add_child(mi)
	var key := "wild_%s_%d" % [area, seed]
	var text: Array = TEXT[kind]
	var line: String = text[rng.randi() % text.size()]
	var loot: Array = LOOT.get(kind, [])
	var e := Examine.make(NAMES[kind], "翻找" if not loot.is_empty() else "看看", func(_who: FpController) -> Dictionary: return WildFinds.use(key, line, loot), Vector3(2.0, 1.6, 2.0))
	e.name = "WildFindUse"
	e.position = at + Vector3(0, 0.8, 0)
	e.verb_fn = func() -> String: return "看看" if loot.is_empty() or GameState.has_flag(key) else "翻找"
	root.add_child(e)
	return {"kind": kind, "name": NAMES[kind], "pos": Vector2(p.x, p.y), "key": key}


## 看 / 翻：第一次拿东西，记旗标；以后只是看看
static func use(key: String, line: String, loot: Array) -> Dictionary:
	if loot.is_empty() or GameState.has_flag(key):
		return {"toast": line}
	GameState.set_flag(key)
	var got := []
	for it: Array in loot:
		if str(it[0]) == "silver":
			GameState.add_silver(int(it[1]))
			got.append("%d 枚银币" % int(it[1]))
		else:
			GameState.add_item(str(it[0]), int(it[1]))
			got.append("%s ×%d" % [GameState.item_name(str(it[0])), int(it[1])])
	return {"toast": line + "\n（拿到：" + "、".join(got) + "）"}


static func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	m.vertex_color_use_as_albedo = true
	return m


static func _solid(body: StaticBody3D, at: Vector3, size: Vector3, b: Basis) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(b, at)
	body.add_child(cs)


static func _build(kit: MeshKit, kind: String, at: Vector3, b: Basis, rng: RandomNumberGenerator, body: StaticBody3D) -> void:
	match kind:
		"ruin":
			for layer in 7:                                              # 半截圆塔：一圈一圈石头，越往上缺得越多（缺口朝一边）
				var n := 18
				for k in n:
					var a := TAU * k / n
					var gap := absf(wrapf(a - 0.8, -PI, PI)) < 0.25 + layer * 0.22    # 塌开的一面
					if layer > 1 and (gap or rng.randf() < layer * 0.06):
						continue
					var rad := 2.1
					kit.box("stone", at + b * Vector3(cos(a) * rad, 0.2 + layer * 0.4, sin(a) * rad), Vector3(0.5, 0.4, 0.78), b * Basis(Vector3.UP, -a), 0.92 - layer * 0.03, 0.7)
			for k in 14:                                                 # 塌下来的石头，堆在缺口外头
				var a := 0.8 + rng.randf_range(-0.5, 0.5)
				var d := rng.randf_range(2.4, 4.2)
				kit.box("stone", at + b * Vector3(cos(a) * d, 0.12 + rng.randf() * 0.15, sin(a) * d), Vector3(0.45, 0.28, 0.55), Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)), 0.85, 0.6)
			_solid(body, at + Vector3(0, 1.2, 0), Vector3(4.2, 2.4, 4.2), b)
		"cairn":
			for k in 9:
				var lv := k / 4
				kit.box("stone", at + Vector3(rng.randf_range(-0.5, 0.5) * (1.0 - lv * 0.3), 0.18 + lv * 0.32, rng.randf_range(-0.5, 0.5) * (1.0 - lv * 0.3)), Vector3(0.45, 0.32, 0.4), Basis(Vector3.UP, rng.randf() * TAU), 0.9, 0.7)
			kit.box("timber", at + Vector3(0, 1.35, 0), Vector3(0.08, 1.2, 0.08), b)
			kit.box("timber", at + b * Vector3(0, 1.6, 0.06), Vector3(0.45, 0.3, 0.04), b, 0.8, 0.8)
			_solid(body, at + Vector3(0, 0.5, 0), Vector3(1.2, 1.0, 1.2), b)
		"frozen":                                                       # 一个人侧身蜷在雪里：兜帽的头、弓着的背、蜷起来的腿、往前伸的一只手、背上的包袱
			var P := func(x: float, y: float, z: float) -> Vector3: return at + b * Vector3(x, y, z)
			kit.tube("cloth", P.call(0.0, 0.28, -0.55), P.call(0.05, 0.3, 0.25), 0.24, 0.22, 10, 0.75)        # 弓着的背（斗篷）
			kit.tube("cloth", P.call(0.0, 0.26, -0.62), P.call(0.0, 0.26, -0.9), 0.15, 0.13, 10, 0.7)         # 兜帽
			kit.tube("cloth", P.call(0.05, 0.22, 0.25), P.call(0.22, 0.16, 0.6), 0.16, 0.12, 8, 0.7)          # 蜷着的大腿
			kit.tube("cloth", P.call(0.22, 0.16, 0.6), P.call(-0.05, 0.1, 0.78), 0.11, 0.09, 8, 0.65)         # 小腿收回来
			kit.tube("hide", P.call(-0.15, 0.2, -0.45), P.call(-0.35, 0.1, -1.25), 0.06, 0.045, 7, 0.7)       # 往前伸的一只手
			kit.tube("hide", P.call(0.28, 0.42, -0.2), P.call(0.32, 0.4, 0.2), 0.17, 0.16, 8, 0.7)            # 背上的包袱
			kit.tube("snow", P.call(0.05, 0.47, -0.5), P.call(0.08, 0.45, 0.2), 0.1, 0.08, 8, 1.0)            # 身上积的一层雪
		"camp":
			for k in 9:
				var a := TAU * k / 9
				kit.box("stone", at + Vector3(cos(a) * 0.7, 0.1, sin(a) * 0.7), Vector3(0.3, 0.2, 0.25), Basis(Vector3.UP, -a), 0.6, 0.5)
			kit.box("ash", at + Vector3(0, 0.03, 0), Vector3(1.0, 0.04, 1.0), b)
			for s in [-1.0, 1.0]:
				kit.cylinder("bark", at + b * Vector3(s * 1.7, 0.18, -0.8), at + b * Vector3(s * 1.7, 0.18, 0.8), 0.17, 0.16, 7, 0.8)
		"hut":                                                          # 斜搭的窝棚：前面一根横梁架在两根柱子上（1.6 米），木板从横梁斜着搭到后面的地上
			var slope := atan2(1.5, 2.4)
			var mid := Vector3(0, 0.85, -0.05)
			for k in 8:
				kit.box("timber", at + b * (mid + Vector3(-1.4 + k * 0.4, 0, 0)), Vector3(0.36, 0.06, 2.85), b * Basis(Vector3.RIGHT, slope), 0.8, 0.6)
			kit.box("snow", at + b * (mid + Vector3(0, 0.06, 0)), Vector3(3.2, 0.08, 2.85), b * Basis(Vector3.RIGHT, slope), 1.0, 1.0)
			kit.box("timber", at + b * Vector3(0, 1.62, -1.25), Vector3(3.3, 0.12, 0.14), b)
			for sx in [-1.5, 1.5]:
				kit.box("timber", at + b * Vector3(sx, 0.8, -1.25), Vector3(0.12, 1.6, 0.12), b)
			kit.box("hide", at + b * Vector3(-0.9, 1.0, -1.32), Vector3(0.8, 0.9, 0.04), b, 0.9, 0.7)       # 挂在横梁上的兽皮
			kit.box("hide", at + b * Vector3(0.3, 0.06, -0.3), Vector3(1.6, 0.06, 1.2), b, 0.7, 0.6)        # 地上铺的干草、皮子
			_solid(body, at + b * mid, Vector3(3.3, 0.3, 2.85), b * Basis(Vector3.RIGHT, slope))
		"cart":
			var tilt := b * Basis(Vector3.FORWARD, 0.35)
			kit.box("timber", at + b * Vector3(0, 0.6, 0), Vector3(1.6, 0.12, 3.0), tilt, 0.8, 0.6)
			for s in [-1.0, 1.0]:
				kit.box("timber", at + b * Vector3(s * 0.8, 0.85, 0), Vector3(0.08, 0.5, 3.0), tilt, 0.8, 0.6)
			kit.cylinder("timber", at + b * Vector3(-0.95, 0.5, 0.8), at + b * Vector3(-1.05, 0.5, 0.8), 0.5, 0.5, 12, 0.7)
			kit.cylinder("timber", at + b * Vector3(1.4, 0.15, -0.6), at + b * Vector3(1.5, 0.12, -0.6), 0.5, 0.5, 12, 0.7)   # 掉下来的轮子
			kit.box("timber", at + b * Vector3(0, 0.3, -2.1), Vector3(0.1, 0.1, 1.6), b * Basis(Vector3.RIGHT, 0.3))          # 车辕
			_solid(body, at + Vector3(0, 0.6, 0), Vector3(1.8, 1.2, 3.0), b)
