extends SceneTree
## 生成金穗平原的枝条贴图（路线图 6.1b；world/plain_flora.gd 的 TWIG_TEX）：一张 1536 × 512 的图，三格，全是代码画的（原创，不用外部素材）：
##   第 0 格：一簇光秃秃的细枝（一根分叉六次，往上扇开）——落叶树树冠的梢、篱笆里的灌木
##   第 1 格：截头柳的一把枝条（从树头一把冒出来，下面暗、梢上金黄带红：冬天的黄枝柳）
##   第 2 格：一整棵落叶树的剪影（远处的树、地平线上那一排树用）
## 透明处的颜色填成该格的平均色（不然 mipmap 往外渗出黑边 / 白边）。改了以后跑一次：
##   godot --headless --path games/ironcrown/godot --script res://tests/gen_plain_twigs.gd
const W := 1536
const H := 512
const OUT := "res://chapters/ch3/trees/plain_twigs.png"

var rgba := PackedFloat32Array()
var rng := RandomNumberGenerator.new()


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	rgba.resize(W * H * 4)
	var bases := [Color(0.3, 0.27, 0.24), Color(0.42, 0.32, 0.18), Color(0.34, 0.32, 0.32)]
	for y in H:
		for x in W:
			var c: Color = bases[x / 512]
			var k := (y * W + x) * 4
			rgba[k] = c.r
			rgba[k + 1] = c.g
			rgba[k + 2] = c.b
			rgba[k + 3] = 0.0
	rng.seed = 6101
	# 第 0 格：一簇细枝
	for i in 3:
		var a := deg_to_rad(-90.0 + (i - 1) * 24.0 + rng.randf_range(-6, 6))
		_branch(Vector2(256 + (i - 1) * 14, 508), Vector2(cos(a), sin(a)), 150.0, 4.2, 6, 0, Color(0.28, 0.24, 0.21), Color(0.46, 0.4, 0.35))
	# 第 1 格：截头柳的一把枝条
	for i in 70:
		var spread := rng.randf_range(-1.0, 1.0)
		var a := deg_to_rad(-90.0 + spread * 38.0)
		var start := Vector2(512 + 256 + spread * 70.0 + rng.randf_range(-12, 12), 506 - absf(spread) * 26.0)
		var len := rng.randf_range(300.0, 470.0) * (1.0 - absf(spread) * 0.25)
		var tip := Color(0.82, 0.55, 0.2).lerp(Color(0.72, 0.3, 0.16), rng.randf() * 0.6)
		_withy(start, a, len, rng.randf_range(2.6, 3.6), Color(0.24, 0.2, 0.14), tip, rng.randf_range(-0.0016, 0.0016) - spread * 0.0009)
	# 第 2 格：一整棵树的剪影
	_line(Vector2(1024 + 256, 512), Vector2(1024 + 256 + 3, 300), 11.0, 8.0, Color(0.26, 0.24, 0.23), Color(0.28, 0.26, 0.25))
	for i in 5:
		var a := deg_to_rad(-90.0 + (i - 2) * 17.0 + rng.randf_range(-6, 6))     # 主枝往上（远看是竖着的椭圆树冠，不是一把平顶伞）
		_branch(Vector2(1024 + 256 + 3, 300 + i * 12), Vector2(cos(a), sin(a)), 105.0, 6.0, 6, 2, Color(0.26, 0.24, 0.23), Color(0.4, 0.37, 0.37))
	var bytes := PackedByteArray()
	bytes.resize(W * H * 4)
	for k in rgba.size():
		bytes[k] = clampi(int(rgba[k] * 255.0 + 0.5), 0, 255)
	var img := Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, bytes)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	img.save_png(OUT)
	print("IC_GEN_TWIGS ms=%d -> %s" % [Time.get_ticks_msec() - t0, OUT])
	quit()


## 一根枝：往前长一段（稍微弯），末端分两三叉，每叉短一点、细一点；tile 限制画在哪一格里
func _branch(p: Vector2, dir: Vector2, len: float, width: float, depth: int, tile: int, c0: Color, c1: Color) -> void:
	var steps := maxi(3, int(len / 10.0))
	var q := p
	var d := dir
	for s in steps:
		d = d.rotated(rng.randf_range(-0.12, 0.12)).normalized()
		d = (d + Vector2(0, -0.06)).normalized()            # 稍微往上长
		var n := q + d * (len / steps)
		var t := float(s) / steps
		_line(q, n, lerpf(width, width * 0.72, t), lerpf(width, width * 0.72, t * 1.05), c0, c0.lerp(c1, 1.0 - float(depth) / 6.0))
		q = n
	if depth <= 0:
		return
	var kids := 2 if rng.randf() < 0.6 else 3
	for k in kids:
		var ang := rng.randf_range(0.28, 0.62) * (1.0 if k % 2 == 0 else -1.0) + (rng.randf_range(-0.1, 0.1) if kids == 3 and k == 2 else 0.0)
		if kids == 3 and k == 2:
			ang = rng.randf_range(-0.12, 0.12)
		var nd := d.rotated(ang)
		var nq := q
		if not _inside(nq, tile):
			continue
		_branch(nq, nd, len * rng.randf_range(0.62, 0.76), maxf(width * 0.68, 0.7), depth - 1, tile, c0.lerp(c1, 0.25), c1)


## 柳条：几乎笔直、梢上慢慢弯开，下面暗、梢上亮
func _withy(p: Vector2, a: float, len: float, width: float, c0: Color, c1: Color, bend: float) -> void:
	var steps := int(len / 6.0)
	var q := p
	var ang := a
	for s in steps:
		ang += bend * 6.0 * (0.4 + float(s) / steps)
		var n := q + Vector2(cos(ang), sin(ang)) * (len / steps)
		var t := float(s) / steps
		if not _inside(n, 1):
			return
		_line(q, n, lerpf(width, 0.8, t), lerpf(width, 0.8, t + 1.0 / steps), c0.lerp(c1, pow(t, 0.7)), c0.lerp(c1, pow(minf(t + 1.0 / steps, 1.0), 0.7)))
		q = n


func _inside(p: Vector2, tile: int) -> bool:
	return p.x >= tile * 512 + 2 and p.x < tile * 512 + 510 and p.y >= 2 and p.y < H - 1


## 一段线：沿线每 0.7 像素盖一个软边的圆（半径从 w0 到 w1 的一半），颜色从 a 到 b；透明度取大的
func _line(p0: Vector2, p1: Vector2, w0: float, w1: float, a: Color, b: Color) -> void:
	var n := maxi(1, int(p0.distance_to(p1) / 0.7))
	for i in n + 1:
		var t := float(i) / n
		var c := p0.lerp(p1, t)
		var r := lerpf(w0, w1, t) * 0.5
		var col := a.lerp(b, t)
		var x0 := int(floor(c.x - r - 1.0))
		var x1 := int(ceil(c.x + r + 1.0))
		var y0 := int(floor(c.y - r - 1.0))
		var y1 := int(ceil(c.y + r + 1.0))
		for y in range(maxi(y0, 0), mini(y1, H - 1) + 1):
			for x in range(maxi(x0, 0), mini(x1, W - 1) + 1):
				var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
				var al := clampf(r - d + 0.6, 0.0, 1.0)
				if al <= 0.0:
					continue
				var k := (y * W + x) * 4
				if al > rgba[k + 3]:
					rgba[k] = col.r
					rgba[k + 1] = col.g
					rgba[k + 2] = col.b
					rgba[k + 3] = al
