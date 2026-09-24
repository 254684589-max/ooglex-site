extends SceneTree
## 把真实照片材质（CC0 / MIT，来源见 godot/assets/textures/photo/SOURCES.md）加工成游戏用的贴图。
## 只用 Godot 自带的 Image 类，不需要额外依赖。用法：
##   git clone --depth 1 https://github.com/playcanvas/engine <src>/pc          （只需要 examples/assets/textures）
##   git clone --depth 1 https://github.com/godotengine/godot-demo-projects <src>/gdp
##   godot --headless -s games/working-life/tools/bake_photo_textures.gd -- <src> games/working-life/godot/assets/textures/photo

var src := ""
var out := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("用法：-- <源目录> <输出目录>")
		quit(1)
		return
	src = args[0].trim_suffix("/") + "/"
	out = args[1].trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(out)
	var trail := _load("pc/examples/assets/textures/rocky_trail_diff_1k.jpg")
	var cracked := _load("pc/examples/assets/textures/rock_boulder_cracked_diff_1k.jpg")
	var cement := _load("gdp/3d/truck_town/town/model/textures/cement_lossy.webp")
	var grass := _load("gdp/3d/truck_town/town/model/textures/grass_lossy.webp")
	var stone := _load("pc/examples/assets/textures/bricks076a/color.webp")
	var stone_n := _load("pc/examples/assets/textures/bricks076a/normal.webp")

	# 沥青：砂石路照片去色、压暗、降低对比，再叠一点龟裂纹理
	var asphalt := _gray(trail)
	_levels(asphalt, 0.2, 0.44, 0.9)
	var cr := _gray(cracked)
	_levels(cr, 0.0, 1.0, 1.0)
	_multiply(asphalt, cr, 0.28)
	_tint(asphalt, Color(1.0, 0.99, 0.97))
	_save(asphalt, "asphalt_albedo", 1024)
	var asphalt_h := _gray(trail)
	_save_normal(asphalt_h, "asphalt_normal", 1024, 3.0)

	# 混凝土（桥墩、墙、地面）
	var concrete := cement.duplicate()
	_normalize(concrete, 0.62)
	_save(concrete, "concrete_albedo", 1024)
	_save_normal(_gray(cement), "concrete_normal", 512, 1.5)

	# 人行道：混凝土方砖，贴图覆盖 4.8 米 = 8×8 块 60 厘米方砖，砖缝与每块砖轻微色差
	var paving := cement.duplicate()
	paving.resize(1024, 1024)
	_normalize(paving, 0.58)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := 8
	var s := 1024 / n
	for y in n:
		for x in n:
			var f := rng.randf_range(0.96, 1.03)
			_scale_rect(paving, Rect2i(x * s, y * s, s, s), f)
	for k in n:
		paving.fill_rect(Rect2i(k * s, 0, 3, 1024), Color(0.36, 0.36, 0.36))
		paving.fill_rect(Rect2i(0, k * s, 1024, 3), Color(0.36, 0.36, 0.36))
	_save(paving, "paving_albedo", 1024)

	# 墙面细节层：亮度归一到 0.85 左右（与立面贴图相乘，保留原来的颜色，只增加抹灰 / 混凝土的质感）
	var plaster := cement.duplicate()
	_normalize(plaster, 0.86)
	_levels_keep(plaster, 0.9)
	_save(plaster, "plaster_detail", 512)

	# 底层外墙石材（ambientCG Bricks076A），同样归一，法线直接用原套
	var st := stone.duplicate()
	_normalize(st, 0.8)
	_save(st, "stone_albedo", 1024)
	_save(stone_n, "stone_normal", 1024)

	# 屋顶：混凝土压暗 + 砾石
	var roof := cement.duplicate()
	_normalize(roof, 0.34)
	var gravel := _gray(trail)
	_levels(gravel, 0.0, 1.0, 1.0)
	_multiply(roof, gravel, 0.35)
	_save(roof, "roof_albedo", 512)

	# 草坪：去掉一些饱和度、压暗，更像真实草地
	var lawn := grass.duplicate()
	_desaturate(lawn, 0.35)
	_normalize(lawn, 0.32)
	_multiply(lawn, _gray(trail), 0.25)
	_save(lawn, "grass_albedo", 512)

	# 泥土 / 空地（城外远处的地面、货场道砟）
	var dirt := trail.duplicate()
	_desaturate(dirt, 0.3)
	_normalize(dirt, 0.36)
	_save(dirt, "dirt_albedo", 1024)
	print("done")
	quit()


func _load(rel: String) -> Image:
	var img := Image.load_from_file(src + rel)
	if img == null:
		push_error("缺少源文件：" + rel)
		quit(1)
	img.convert(Image.FORMAT_RGB8)
	return img


func _save(img: Image, name: String, size: int) -> void:
	var o := img.duplicate() as Image
	if o.get_width() != size:
		o.resize(size, size, Image.INTERPOLATE_LANCZOS)
	o.save_webp(out + name + ".webp", true, 0.86)
	print("wrote ", name, " ", size)


func _save_normal(height: Image, name: String, size: int, strength: float) -> void:
	var h := height.duplicate() as Image
	h.resize(size, size, Image.INTERPOLATE_LANCZOS)
	h.convert(Image.FORMAT_RGBA8)
	h.bump_map_to_normal_map(strength)
	h.convert(Image.FORMAT_RGB8)
	h.save_webp(out + name + ".webp", true, 0.92)
	print("wrote ", name, " ", size)


func _gray(img: Image) -> Image:
	var g := img.duplicate() as Image
	for y in g.get_height():
		for x in g.get_width():
			var c := g.get_pixel(x, y)
			var l := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
			g.set_pixel(x, y, Color(l, l, l))
	return g


func _mean(img: Image) -> float:
	var sum := 0.0
	var step := 4
	var cnt := 0
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			sum += c.r * 0.3 + c.g * 0.59 + c.b * 0.11
			cnt += 1
	return sum / maxi(cnt, 1)


## 整体缩放亮度，使平均亮度等于 target
func _normalize(img: Image, target: float) -> void:
	var k := target / maxf(_mean(img), 0.001)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(minf(c.r * k, 1.0), minf(c.g * k, 1.0), minf(c.b * k, 1.0)))


## 以均值为中心压缩对比度（amount < 1 更柔和）
func _levels_keep(img: Image, amount: float) -> void:
	var m := _mean(img)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(m + (c.r - m) * amount, m + (c.g - m) * amount, m + (c.b - m) * amount))


## 灰度图映射到 [lo, hi]，gamma 调整
func _levels(img: Image, lo: float, hi: float, gamma: float) -> void:
	var mn := 1.0
	var mx := 0.0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var v := img.get_pixel(x, y).r
			mn = minf(mn, v)
			mx = maxf(mx, v)
	for y in img.get_height():
		for x in img.get_width():
			var v := clampf((img.get_pixel(x, y).r - mn) / maxf(mx - mn, 0.001), 0.0, 1.0)
			v = lerpf(lo, hi, pow(v, gamma))
			img.set_pixel(x, y, Color(v, v, v))


## a *= lerp(1, b, amount)（b 为 0–1 灰度）
func _multiply(a: Image, b: Image, amount: float) -> void:
	var bb := b.duplicate() as Image
	if bb.get_size() != a.get_size():
		bb.resize(a.get_width(), a.get_height())
	for y in a.get_height():
		for x in a.get_width():
			var c := a.get_pixel(x, y)
			var f := lerpf(1.0, 0.55 + bb.get_pixel(x, y).r * 0.9, amount)
			a.set_pixel(x, y, Color(minf(c.r * f, 1.0), minf(c.g * f, 1.0), minf(c.b * f, 1.0)))


func _tint(img: Image, t: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * t.r, c.g * t.g, c.b * t.b))


func _desaturate(img: Image, amount: float) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var l := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
			img.set_pixel(x, y, c.lerp(Color(l, l, l), amount))


func _scale_rect(img: Image, r: Rect2i, f: float) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(minf(c.r * f, 1.0), minf(c.g * f, 1.0), minf(c.b * f, 1.0)))
