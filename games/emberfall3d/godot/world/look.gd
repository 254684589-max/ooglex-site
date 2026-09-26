class_name Look
extends RefCounted
## 画面风格（ART.md 第二、七节，阶段 2.3）。
## - 写实贴图（2.6 之二）：地牢地面、墙、镇上泥土地用 Poly Haven 的 CC0 照片扫描 PBR 贴图
##   （颜色 + 法线 + ARM：遮蔽 / 粗糙度 / 金属度三合一），来源见 assets/SOURCES.md；导入为 Basis Universal
##   （网页上一份文件，按设备转成显卡压缩格式）。缺文件或 photo_enabled = false 时退回下面的程序化贴图。
## - 程序化贴图：石板地面、砖墙（手绘感：每块石头颜色略有不同、上左亮边 / 下右暗边假装倒角、灰缝）。
##   贴图按世界坐标三向投影（triplanar），灰盒几何体不用做 UV。
## - 环境：暖光冷影（阴影偏冷紫、火光偏暖）、深度雾、泛光（让火焰发光）、对比度与饱和度微调。
## - 圆形假阴影、径向渐变光晕贴图。
## 生成的贴图全局缓存，只生成一次。
## 画质分档见 apply_quality()：low（手机默认）/ medium（电脑默认）/ high。

const TIERS := ["low", "medium", "high"]

static var _floor_tex: ImageTexture
static var _brick_tex: ImageTexture
static var _radial_tex: GradientTexture2D
static var _ground_tex: ImageTexture
static var _floor_nrm: ImageTexture
static var _brick_nrm: ImageTexture
static var _heights := {}          # 画石块时顺手记下的高度图（灰缝低、石面高、边缘倒角），用来生成法线贴图


# ---------------- 程序化贴图 ----------------

static func _h(x: int, y: int, s: int = 0) -> float:
	## 整数哈希 → [0, 1)。比 FastNoiseLite 逐像素采样快得多，网页上生成贴图也不卡。
	var n := (x * 374761393 + y * 668265263 + s * 2147483647) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n ^ (n >> 16)) / 2147483647.0


static func _stones(size: int, rows: int, cols_per_row: Array, base: Color, var_amt: float, grout: Color, seed_v: int, irregular: bool) -> Image:
	## 画一张可平铺的「石块」贴图：rows 行，每行 cols 块；irregular = true 时每块宽度随机（0.6–1.4 倍），
	## 石板看起来不像棋盘格。每块：底色小幅抖动 + 细颗粒 + 上左亮边 + 下右暗边；块间灰缝。
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var hmap := Image.create(size, size, false, Image.FORMAT_RGB8)
	_heights[seed_v] = hmap
	var row_h := size / rows
	for r in rows:
		var cols: int = cols_per_row[r % cols_per_row.size()]
		# 本行每块的宽度（像素），总和 = size，保证左右可平铺
		var ws: Array[float] = []
		var total := 0.0
		for c in cols:
			var w := 0.6 + _h(r, c, seed_v + 3) * 0.8 if irregular else 1.0
			ws.append(w)
			total += w
		var off := int(_h(r, 99, seed_v) * size) if irregular else (size / cols / 2 if r % 2 == 1 else 0)
		var x0 := 0.0
		for c in cols:
			var col_w := int(round(ws[c] / total * size))
			var stone_seed := r * 131 + c * 17 + seed_v
			var k := (_h(r, c, seed_v) - 0.5) * 2.0 * var_amt
			var tone := Color(base.r * (1.0 + k), base.g * (1.0 + k * 0.95), base.b * (1.0 + k * 0.9))
			var warm := (_h(c, r, seed_v + 7) - 0.5) * 0.03
			tone = Color(tone.r + warm, tone.g, tone.b - warm)
			for yy in row_h:
				for xx in col_w:
					var px := (int(x0) + xx + off) % size
					var py := r * row_h + yy
					var g := 2
					var col: Color
					if xx < g or yy < g:
						col = grout
						hmap.set_pixel(px, py, Color(0.05, 0.05, 0.05))
					else:
						# 高度：离石块边缘越近越低（倒角），石面带一点起伏和每块不同的倾斜
						var e := mini(mini(xx - g, yy - g), mini(col_w - 1 - xx, row_h - 1 - yy))
						var bev := smoothstep(0.0, 6.0, float(e))
						var tilt := (_h(r, c, seed_v + 41) - 0.5) * 0.12 * (float(xx) / col_w - 0.5)
						var hv := clampf(0.25 + 0.55 * bev + (_h(px >> 2, py >> 2, stone_seed + 5) - 0.5) * 0.12 + tilt, 0.0, 1.0)
						hmap.set_pixel(px, py, Color(hv, hv, hv))
						var n := (_h(px, py, stone_seed) - 0.5) * 0.1
						col = Color(tone.r + n, tone.g + n, tone.b + n)
						if xx < g + 3 or yy < g + 3:
							col = col.lightened(0.1)        # 上左亮边：假装倒角受光
						elif xx > col_w - 4 or yy > row_h - 4:
							col = col.darkened(0.25)        # 下右暗边
					img.set_pixel(px, py, col)
			x0 += col_w
	return img


static func ground_texture() -> ImageTexture:
	## 烬原镇的泥土地（P7）：大块的深浅斑驳（4 级网格插值）+ 细颗粒 + 零星的枯草色，可平铺
	if _ground_tex == null:
		var size := 128
		var img := Image.create(size, size, false, Image.FORMAT_RGB8)
		var base := Color(0.36, 0.3, 0.22)
		var grass := Color(0.3, 0.33, 0.18)
		var cells := 8
		for y in size:
			for x in size:
				var fx := float(x) / size * cells
				var fy := float(y) / size * cells
				var ix := int(fx)
				var iy := int(fy)
				var tx := fx - ix
				var ty := fy - iy
				var a := _h(ix % cells, iy % cells, 5)
				var b := _h((ix + 1) % cells, iy % cells, 5)
				var c := _h(ix % cells, (iy + 1) % cells, 5)
				var d := _h((ix + 1) % cells, (iy + 1) % cells, 5)
				var m := lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)
				var col := base.lerp(grass, clampf((m - 0.45) * 2.0, 0.0, 1.0))
				var n := (_h(x, y, 11) - 0.5) * 0.08
				col = Color(col.r * (0.85 + m * 0.3) + n, col.g * (0.85 + m * 0.3) + n, col.b * (0.85 + m * 0.3) + n)
				img.set_pixel(x, y, col)
		img.generate_mipmaps()
		_ground_tex = ImageTexture.create_from_image(img)
	return _ground_tex


static func floor_texture() -> ImageTexture:
	if _floor_tex == null:
		# 石板：4 行，每行 3–4 块，错缝；覆盖 4 米见方
		var img := _stones(256, 5, [3, 4, 3, 2, 4], Color(0.34, 0.31, 0.28), 0.1, Color(0.09, 0.075, 0.07), 11, true)
		img.generate_mipmaps()
		_floor_tex = ImageTexture.create_from_image(img)
	return _floor_tex


static func brick_texture() -> ImageTexture:
	if _brick_tex == null:
		# 砖墙：8 行，每行 4 块（每块约 0.5 米 × 0.25 米），错缝；覆盖 2 米见方
		var img := _stones(256, 8, [4], Color(0.38, 0.33, 0.29), 0.1, Color(0.11, 0.09, 0.08), 29, false)
		img.generate_mipmaps()
		_brick_tex = ImageTexture.create_from_image(img)
	return _brick_tex


## 法线贴图（2.6 样板间）：由石块高度图生成，火把从侧面照过来时石块的倒角和灰缝有真实的明暗
static func _normal_from(seed_v: int, strength: float) -> ImageTexture:
	var hm: Image = (_heights[seed_v] as Image).duplicate()
	hm.bump_map_to_normal_map(strength)
	hm.generate_mipmaps()
	return ImageTexture.create_from_image(hm)


static func floor_normal() -> ImageTexture:
	if _floor_nrm == null:
		floor_texture()
		_floor_nrm = _normal_from(11, 6.0)
	return _floor_nrm


static func brick_normal() -> ImageTexture:
	if _brick_nrm == null:
		brick_texture()
		_brick_nrm = _normal_from(29, 6.0)
	return _brick_nrm


static func radial_texture() -> GradientTexture2D:
	## 中心白、边缘透明的径向渐变（假阴影、光晕共用，靠材质颜色染色）
	if _radial_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		_radial_tex = GradientTexture2D.new()
		_radial_tex.gradient = g
		_radial_tex.fill = GradientTexture2D.FILL_RADIAL
		_radial_tex.fill_from = Vector2(0.5, 0.5)
		_radial_tex.fill_to = Vector2(1.0, 0.5)
		_radial_tex.width = 64
		_radial_tex.height = 64
	return _radial_tex


# ---------------- 写实贴图（2.6 之二） ----------------

## kind → Poly Haven 素材名、贴图覆盖的米数（原始扫描约 1.8 / 1.8 / 3.15 米见方，按斜俯视镜头下的石块大小放大一点）、
## 基础染色（照片本身的颜色已经对，只按场景的冷暖光压一压亮度）
const PHOTO := {
	"floor": {"id": "monastery_stone_floor", "meters": 2.6, "tint": Color(0.92, 0.9, 0.9)},
	"wall": {"id": "rock_wall_08", "meters": 2.4, "tint": Color(1.3, 1.26, 1.22)},
	"ground": {"id": "forest_ground_04", "meters": 4.5, "tint": Color(0.95, 0.92, 0.88)},
}
static var photo_dir := "res://assets/textures/%s/%s_%s_1k.jpg"   # 测试会临时改成不存在的路径，验证退回程序化贴图

static var photo_enabled := true   # false：全部用程序化贴图（对比截图、网页 ?tex=proc）
static var _photo := {}


static func photo_set(kind: String) -> Dictionary:
	## {albedo, normal, arm}；三张缺任何一张都返回空（调用方退回程序化贴图）
	if not photo_enabled or not PHOTO.has(kind):
		return {}
	if not _photo.has(kind):
		var id: String = PHOTO[kind].id
		var d := {}
		for pair in [["albedo", "diff"], ["normal", "nor_gl"], ["arm", "arm"]]:
			var path := photo_dir % [id, id, pair[1]]
			var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
			if tex == null:
				push_warning("写实贴图缺文件，退回程序化贴图：" + path)
				d = {}
				break
			d[pair[0]] = tex
		_photo[kind] = d
	return _photo[kind]


static func _photo_material(kind: String, tint: Color) -> StandardMaterial3D:
	var p := photo_set(kind)
	if p.is_empty():
		return null
	var cfg: Dictionary = PHOTO[kind]
	var m := _triplanar(p.albedo, cfg.meters, cfg.tint * tint, p.normal)
	# ARM：R = 环境光遮蔽（只影响环境光，火把直射不受影响）、G = 粗糙度；石头与泥土都不是金属
	m.roughness_texture = p.arm
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = 1.0
	m.ao_enabled = true
	m.ao_texture = p.arm
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.ao_light_affect = 0.25
	m.metallic = 0.0
	return m


# ---------------- 材质 ----------------

static func _triplanar(tex: Texture2D, meters: float, tint: Color, nrm: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	if nrm:
		m.normal_enabled = true
		m.normal_texture = nrm
		m.normal_scale = 1.0
	# 顶点色当作「环境光遮蔽」乘到颜色上（地下城网格在墙脚、墙角写入较暗的顶点色；没有顶点色的网格按白色算，不受影响）
	m.vertex_color_use_as_albedo = true
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	var s := 1.0 / meters
	m.uv1_scale = Vector3(s, s, s)
	m.roughness = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## 以下三个材质的 tint 都是「相对染色」（楼层主题、灰盒里各件的明暗），乘在各自的基础染色上。

static func floor_material(tint := Color(1, 1, 1)) -> StandardMaterial3D:
	var m := _photo_material("floor", tint)
	return m if m else _triplanar(floor_texture(), 4.0, Color(0.85, 0.82, 0.8) * tint, floor_normal())


static func wall_material(tint := Color(1, 1, 1)) -> StandardMaterial3D:
	## 每面墙一个新材质（相机要单独把挡视线的墙变半透明），但共用同一张贴图
	var m := _photo_material("wall", tint)
	return m if m else _triplanar(brick_texture(), 2.0, tint, brick_normal())


static func ground_material(tint := Color(1, 1, 1)) -> StandardMaterial3D:
	## 烬原镇的露天泥土地
	var m := _photo_material("ground", tint)
	return m if m else _triplanar(ground_texture(), 6.0, tint)


static func rim(m: StandardMaterial3D, amount := 0.3) -> StandardMaterial3D:
	## 角色轮廓光：暗场景里剪影清楚（ART.md 第七节）
	m.rim_enabled = true
	m.rim = amount
	m.rim_tint = 0.2
	return m


static func blob_shadow(radius: float, strength := 0.55) -> MeshInstance3D:
	## 圆形假阴影：低画质关掉实时阴影后，角色脚下仍有落地感
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.6, radius * 2.6)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = radial_texture()
	m.albedo_color = Color(0.02, 0.01, 0.02, strength)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.02
	mi.name = "BlobShadow"
	return mi


# ---------------- 环境 ----------------

static func crypt_environment() -> Environment:
	## 修道院地窖 / 灰盒大厅：冷紫阴影 + 暖色火光（ART.md 第 3.3 节「序章 · 烬原」地下部分）
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.025, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.28, 0.24, 0.42)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.04, 0.06)
	env.fog_density = 0.022
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.0
	return env


## 各楼层主题的环境光与雾（阶段 P2）：地窖冷紫、墓穴阴绿、熔渊暗红、深渊幽紫。
## 与 V0.1 THEMES 的色调对应；火把仍是主要的暖色光源。
const THEME_ENV := {
	"crypt": {"ambient": Color(0.28, 0.24, 0.42), "fog": Color(0.06, 0.04, 0.06), "bg": Color(0.035, 0.025, 0.03)},
	"catacomb": {"ambient": Color(0.22, 0.32, 0.3), "fog": Color(0.035, 0.06, 0.05), "bg": Color(0.02, 0.035, 0.03)},
	"inferno": {"ambient": Color(0.42, 0.2, 0.16), "fog": Color(0.1, 0.03, 0.02), "bg": Color(0.05, 0.012, 0.008)},
	"abyss": {"ambient": Color(0.3, 0.2, 0.5), "fog": Color(0.05, 0.03, 0.09), "bg": Color(0.025, 0.015, 0.045)},
	# 烬原镇（P7）：黄昏的露天小镇，环境光更亮、雾更淡，远处偏暮蓝
	"town": {"ambient": Color(0.42, 0.36, 0.44), "fog": Color(0.13, 0.11, 0.15), "bg": Color(0.07, 0.06, 0.09), "fog_density": 0.012, "ambient_energy": 0.45},
}


static func apply_theme(env: Environment, theme: String) -> void:
	var e: Dictionary = THEME_ENV.get(theme, THEME_ENV.crypt)
	env.ambient_light_color = e.ambient
	env.fog_light_color = e.fog
	env.background_color = e.bg
	env.fog_density = e.get("fog_density", 0.022)
	env.ambient_light_energy = e.get("ambient_energy", 0.3)


static func default_tier() -> String:
	return "low" if DisplayServer.is_touchscreen_available() else "medium"
