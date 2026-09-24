class_name ProcTex
extends RefCounted
## 程序生成的贴图（不依赖外部美术素材）：
##   建筑立面（玻璃幕墙 / 办公楼带形窗 / 住宅 / 赛博深色塔楼）各一张颜色图 + 一张夜间灯光图，
##   沥青路面、人行道地砖、棕榈叶。全部用 fill_rect 画色块，启动时生成一次并缓存。
## 立面贴图覆盖 8 个开间 × 8 层（一个开间 3 米、一层 3.6 米），材质里按世界坐标平铺。

const SIZE := 512
const BAYS := 8
const FLOORS := 8
const BAY_W := 3.0
const FLOOR_H := 3.6
const STYLES := ["glass", "office", "res", "cyber"]

static var _cache: Dictionary = {}


static func facade(style: String) -> Array:
	var key := "fac_" + style
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(style) & 0x7fffffff
	var alb := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var emi := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	emi.fill(Color.BLACK)
	var cw := SIZE / BAYS
	var ch := SIZE / FLOORS
	match style:
		"glass":
			alb.fill(Color(0.36, 0.4, 0.44))
		"office":
			alb.fill(Color(0.78, 0.76, 0.72))
		"res":
			alb.fill(Color(0.82, 0.78, 0.7))
		_:
			alb.fill(Color(0.2, 0.21, 0.25))
	for fy in FLOORS:
		for bx in BAYS:
			var x0 := bx * cw
			var y0 := fy * ch
			var lit := rng.randf() < 0.42
			var warm := rng.randf() < 0.62
			var lc := Color(1.0, 0.74, 0.44) if warm else Color(0.62, 0.82, 1.0)
			if rng.randf() < 0.06:
				lc = [Color(1.0, 0.3, 0.6), Color(0.3, 1.0, 0.9), Color(0.7, 0.4, 1.0)][rng.randi() % 3]
			lc = lc * rng.randf_range(0.55, 1.0)
			match style:
				"glass":
					_glass_cell(alb, emi, rng, x0, y0, cw, ch, lit, lc)
				"office":
					_office_cell(alb, emi, rng, x0, y0, cw, ch, lit, lc)
				"res":
					_res_cell(alb, emi, rng, x0, y0, cw, ch, lit, lc)
				_:
					_cyber_cell(alb, emi, rng, x0, y0, cw, ch, lit, lc, bx, fy)
	var out := [_tex(alb), _tex(emi)]
	_cache[key] = out
	return out


## 玻璃幕墙：细竖梃 + 楼层间的深色窗槛墙，玻璃上半截更亮（映着天空）
static func _glass_cell(alb: Image, emi: Image, rng: RandomNumberGenerator, x0: int, y0: int, cw: int, ch: int, lit: bool, lc: Color) -> void:
	var base := Color(0.3, 0.42, 0.52).lerp(Color(0.45, 0.52, 0.56), rng.randf())
	base = base.darkened(rng.randf() * 0.18)
	var spandrel := int(ch * 0.2)
	alb.fill_rect(Rect2i(x0, y0, cw, spandrel), Color(0.2, 0.24, 0.28))
	var gy := y0 + spandrel
	var gh := ch - spandrel
	for s in 6:
		var t := float(s) / 5.0
		var c := base.lightened(0.28 * (1.0 - t)).darkened(0.12 * t)
		alb.fill_rect(Rect2i(x0, gy + gh * s / 6, cw, gh / 6 + 1), c)
	alb.fill_rect(Rect2i(x0, y0, 3, ch), Color(0.16, 0.18, 0.2))
	alb.fill_rect(Rect2i(x0 + cw / 2, gy, 1, gh), Color(0.22, 0.25, 0.28))
	if lit:
		var e := lc * 0.9
		emi.fill_rect(Rect2i(x0 + 3, gy + 2, cw - 4, gh - 3), e)
		# 百叶 / 窗帘遮住一部分
		if rng.randf() < 0.4:
			emi.fill_rect(Rect2i(x0 + 3, gy + 2, cw - 4, int(gh * rng.randf_range(0.2, 0.6))), e * 0.25)


## 办公楼：浅色石材 + 通长带形窗 + 窗间墙
static func _office_cell(alb: Image, emi: Image, rng: RandomNumberGenerator, x0: int, y0: int, cw: int, ch: int, lit: bool, lc: Color) -> void:
	var stone := Color(0.76, 0.74, 0.7).darkened(rng.randf() * 0.08)
	alb.fill_rect(Rect2i(x0, y0, cw, ch), stone)
	alb.fill_rect(Rect2i(x0, y0 + ch - 3, cw, 3), stone.darkened(0.3))
	var wy := y0 + int(ch * 0.3)
	var wh := int(ch * 0.55)
	var wx := x0 + 6
	var ww := cw - 12
	var glass := Color(0.16, 0.22, 0.28).lerp(Color(0.32, 0.4, 0.46), rng.randf())
	for s in 4:
		alb.fill_rect(Rect2i(wx, wy + wh * s / 4, ww, wh / 4 + 1), glass.lightened(0.18 * (3 - s) / 3.0))
	alb.fill_rect(Rect2i(wx, wy - 2, ww, 2), stone.lightened(0.15))
	alb.fill_rect(Rect2i(wx + ww / 2, wy, 2, wh), Color(0.3, 0.3, 0.32))
	if lit:
		emi.fill_rect(Rect2i(wx + 1, wy + 1, ww - 2, wh - 2), lc)
		if rng.randf() < 0.35:
			emi.fill_rect(Rect2i(wx + 1, wy + 1, (ww - 2) / 2, wh - 2), Color.BLACK)


## 住宅：暖色抹灰 + 独立窗洞 + 阳台板 + 各家不同的窗帘
static func _res_cell(alb: Image, emi: Image, rng: RandomNumberGenerator, x0: int, y0: int, cw: int, ch: int, lit: bool, lc: Color) -> void:
	var wall := Color(0.82, 0.77, 0.68).lerp(Color(0.72, 0.62, 0.55), rng.randf() * 0.5)
	alb.fill_rect(Rect2i(x0, y0, cw, ch), wall)
	var wx := x0 + int(cw * 0.2)
	var ww := int(cw * 0.6)
	var wy := y0 + int(ch * 0.2)
	var wh := int(ch * 0.55)
	alb.fill_rect(Rect2i(wx - 2, wy - 2, ww + 4, wh + 4), wall.darkened(0.35))
	var curtain := Color.from_hsv(rng.randf(), rng.randf_range(0.1, 0.4), rng.randf_range(0.35, 0.7))
	alb.fill_rect(Rect2i(wx, wy, ww, wh), Color(0.18, 0.22, 0.26))
	alb.fill_rect(Rect2i(wx, wy, ww, wh / 3), Color(0.35, 0.4, 0.45))
	if rng.randf() < 0.5:
		alb.fill_rect(Rect2i(wx, wy, ww / 3, wh), curtain)
	alb.fill_rect(Rect2i(wx + ww / 2, wy, 1, wh), wall.darkened(0.4))
	# 阳台板与栏杆
	if rng.randf() < 0.45:
		alb.fill_rect(Rect2i(x0 + 2, y0 + ch - 8, cw - 4, 3), wall.darkened(0.45))
		alb.fill_rect(Rect2i(x0 + 2, y0 + ch - 16, cw - 4, 8), wall.darkened(0.2))
	# 空调外机
	if rng.randf() < 0.3:
		alb.fill_rect(Rect2i(x0 + cw - 12, y0 + ch - 14, 9, 7), Color(0.88, 0.88, 0.86))
	if lit:
		emi.fill_rect(Rect2i(wx, wy, ww, wh), lc)
		if rng.randf() < 0.5:
			emi.fill_rect(Rect2i(wx, wy, ww / 3, wh), lc * 0.35)


## 赛博塔楼：深色金属板 + 窄窗 + 零星霓虹竖条
static func _cyber_cell(alb: Image, emi: Image, rng: RandomNumberGenerator, x0: int, y0: int, cw: int, ch: int, lit: bool, lc: Color, bx: int, fy: int) -> void:
	var panel := Color(0.19, 0.2, 0.24).lightened(rng.randf() * 0.08)
	alb.fill_rect(Rect2i(x0, y0, cw, ch), panel)
	alb.fill_rect(Rect2i(x0, y0, cw, 2), panel.darkened(0.5))
	alb.fill_rect(Rect2i(x0, y0, 2, ch), panel.darkened(0.4))
	var wy := y0 + int(ch * 0.35)
	var wh := int(ch * 0.35)
	alb.fill_rect(Rect2i(x0 + 4, wy, cw - 8, wh), Color(0.08, 0.1, 0.14))
	alb.fill_rect(Rect2i(x0 + 4, wy, cw - 8, wh / 3), Color(0.22, 0.28, 0.36))
	if lit:
		emi.fill_rect(Rect2i(x0 + 4, wy, cw - 8, wh), lc * 0.8)
	if bx % 4 == 1:
		var nc := Color(0.1, 0.85, 1.0) if fy % 2 == 0 else Color(1.0, 0.2, 0.55)
		alb.fill_rect(Rect2i(x0 + cw - 5, y0, 3, ch), nc * 0.6)
		emi.fill_rect(Rect2i(x0 + cw - 5, y0, 3, ch), nc)


## 沥青：颗粒噪声 + 车辙 + 补丁
static func asphalt() -> Texture2D:
	if _cache.has("asphalt"):
		return _cache["asphalt"]
	var img := _noise_image(256, 0.03, Color(0.15, 0.15, 0.155), Color(0.17, 0.17, 0.175), 11)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 14:
		var r := Rect2i(rng.randi() % 220, rng.randi() % 220, rng.randi_range(12, 40), rng.randi_range(8, 30))
		img.fill_rect(r, Color(0.13, 0.13, 0.135) if i % 2 else Color(0.165, 0.165, 0.17))
	var t := _tex(img)
	_cache["asphalt"] = t
	return t


## 人行道地砖：60 厘米方砖 + 砖缝
static func paving() -> Texture2D:
	if _cache.has("paving"):
		return _cache["paving"]
	var img := _noise_image(256, 0.02, Color(0.4, 0.39, 0.38), Color(0.45, 0.44, 0.43), 21)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var n := 8
	var s := 256 / n
	for y in n:
		for x in n:
			if rng.randf() < 0.18:
				img.fill_rect(Rect2i(x * s + 1, y * s + 1, s - 2, s - 2), Color(0.42, 0.41, 0.4).darkened(rng.randf() * 0.12))
	for k in n:
		img.fill_rect(Rect2i(k * s, 0, 2, 256), Color(0.22, 0.22, 0.22))
		img.fill_rect(Rect2i(0, k * s, 256, 2), Color(0.22, 0.22, 0.22))
	var t := _tex(img)
	_cache["paving"] = t
	return t


## 路面法线：噪声凹凸
static func bumps() -> Texture2D:
	if _cache.has("bumps"):
		return _cache["bumps"]
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.12
	noise.fractal_octaves = 3
	noise.seed = 4
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 1.5
	nt.noise = noise
	_cache["bumps"] = nt
	return nt


## 植物贴图集（带透明度，512×256）：
##   x 0–127   羽状叶（椰子类棕榈、行道树）
##   x 128–383 扇形叶 + 叶柄（华盛顿棕榈，洛杉矶街头最常见的那种）
##   x 384–511 枯叶裙（挂在树冠下面的一圈干枯老叶）
const FOLIAGE_FEATHER := Rect2(0.0, 0.0, 0.25, 1.0)
const FOLIAGE_FAN := Rect2(0.25, 0.0, 0.5, 1.0)
const FOLIAGE_SKIRT := Rect2(0.75, 0.0, 0.25, 1.0)


static func palm_leaf() -> Texture2D:
	if _cache.has("palm"):
		return _cache["palm"]
	var img := Image.create(512, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	# 羽状叶
	for y in range(4, 254, 3):
		var t := float(y) / 256.0
		var reach := int(60.0 * sin(t * PI) * rng.randf_range(0.75, 1.0))
		var g := Color(0.16, 0.34, 0.12).lerp(Color(0.32, 0.46, 0.18), rng.randf())
		img.fill_rect(Rect2i(64 - reach, y, reach, 2), g)
		img.fill_rect(Rect2i(64, y + 1, reach, 2), g.darkened(0.12))
	img.fill_rect(Rect2i(62, 0, 3, 256), Color(0.36, 0.4, 0.2))
	# 扇形叶：叶柄从下边中点伸上来，顶端放射出几十片细长小叶
	var cx := 256.0
	var cy := 140.0
	img.fill_rect(Rect2i(254, 140, 4, 116), Color(0.42, 0.4, 0.24))
	var ang := -100.0
	while ang <= 100.0:
		var rad := deg_to_rad(ang)
		var length := rng.randf_range(96.0, 124.0) * (0.75 + 0.25 * cos(rad * 0.8))
		var base := Color(0.3, 0.45, 0.2).lerp(Color(0.46, 0.56, 0.28), rng.randf())
		var droop := absf(ang) / 100.0
		var step := 0.0
		while step < length:
			var k := step / length
			var dx := sin(rad) * step
			var dy := -cos(rad) * step + droop * droop * k * k * 40.0
			var w := 3 if k < 0.7 else 2
			img.fill_rect(Rect2i(int(cx + dx), int(cy + dy), w, w), base.darkened(k * 0.15))
			step += 1.5
		ang += rng.randf_range(4.0, 6.5)
	# 枯叶裙：竖向的干叶纤维，下沿参差
	for x in range(384, 512, 2):
		var len2 := rng.randi_range(170, 250)
		var c := Color(0.44, 0.36, 0.25).lerp(Color(0.62, 0.52, 0.36), rng.randf())
		img.fill_rect(Rect2i(x, 0, 2, len2), c.darkened(rng.randf() * 0.3))
	var t2 := _tex(img)
	_cache["palm"] = t2
	return t2


## 屋顶：沥青卷材 + 接缝 + 补丁
static func roof() -> Texture2D:
	if _cache.has("roof"):
		return _cache["roof"]
	var img := _noise_image(256, 0.06, Color(0.25, 0.25, 0.26), Color(0.33, 0.33, 0.34), 31)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for k in 4:
		img.fill_rect(Rect2i(0, k * 64, 256, 2), Color(0.38, 0.38, 0.39))
		img.fill_rect(Rect2i(k * 64 + rng.randi() % 20, 0, 1, 256), Color(0.22, 0.22, 0.23))
	for i in 8:
		img.fill_rect(Rect2i(rng.randi() % 230, rng.randi() % 230, rng.randi_range(10, 30), rng.randi_range(8, 24)), Color(0.2, 0.2, 0.21) if i % 2 else Color(0.36, 0.35, 0.34))
	var t := _tex(img)
	_cache["roof"] = t
	return t


## 广告牌画面贴图集（2×2 四种设计，同时用作夜间自发光）：色块、大图形与「文字行」
static func ads() -> Texture2D:
	if _cache.has("ads"):
		return _cache["ads"]
	var img := Image.create(512, 512, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var designs := [
		[Color(1.0, 0.55, 0.3), Color(0.95, 0.3, 0.5), Color(1, 1, 0.95), Color(0.15, 0.08, 0.2)],
		[Color(0.06, 0.1, 0.25), Color(0.1, 0.25, 0.5), Color(0.85, 0.9, 1.0), Color(0.9, 0.95, 1.0)],
		[Color(0.95, 0.94, 0.9), Color(0.92, 0.9, 0.86), Color(0.85, 0.12, 0.15), Color(0.1, 0.1, 0.12)],
		[Color(0.05, 0.5, 0.5), Color(0.1, 0.35, 0.45), Color(1.0, 0.85, 0.2), Color(1, 1, 1)],
	]
	for d in 4:
		var ox := (d % 2) * 256
		var oy := (d / 2) * 256
		var c: Array = designs[d]
		for y in 16:
			img.fill_rect(Rect2i(ox, oy + y * 16, 256, 16), (c[0] as Color).lerp(c[1], y / 15.0))
		match d:
			0:
				img.fill_rect(Rect2i(ox + 150, oy + 40, 80, 80), c[2])
			1:
				img.fill_rect(Rect2i(ox + 170, oy + 30, 50, 100), Color(0.05, 0.05, 0.07))
				img.fill_rect(Rect2i(ox + 174, oy + 36, 42, 86), c[2])
			2:
				img.fill_rect(Rect2i(ox, oy, 90, 256), c[2])
			_:
				for k in 5:
					img.fill_rect(Rect2i(ox, oy + 30 + k * 40, 256, 12), c[2])
		# 文字行
		var tx := ox + (110 if d == 2 else 20)
		var ty := oy + 150
		img.fill_rect(Rect2i(tx, ty, rng.randi_range(90, 130), 22), c[3])
		for k in 3:
			img.fill_rect(Rect2i(tx, ty + 34 + k * 14, rng.randi_range(60, 120), 7), (c[3] as Color).lerp(c[1], 0.3))
		img.fill_rect(Rect2i(ox, oy, 256, 3), Color(0.9, 0.9, 0.9))
		img.fill_rect(Rect2i(ox, oy + 253, 256, 3), Color(0.9, 0.9, 0.9))
	var t := _tex(img)
	_cache["ads"] = t
	return t


static func _noise_image(size: int, freq: float, a: Color, b: Color, seed_v: int) -> Image:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = freq
	noise.fractal_octaves = 3
	noise.seed = seed_v
	var img := noise.get_seamless_image(size, size)
	img.convert(Image.FORMAT_RGB8)
	var grad := Gradient.new()
	grad.set_color(0, a)
	grad.set_color(1, b)
	# 灰度 → 颜色：逐行读写（256×256，启动时一次）
	for y in size:
		for x in size:
			img.set_pixel(x, y, grad.sample(img.get_pixel(x, y).r))
	return img


static func _tex(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
