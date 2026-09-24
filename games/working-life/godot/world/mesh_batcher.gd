class_name MeshBatcher
extends RefCounted
## 把成百上千个方块、圆柱合并成少量网格（城市里的建筑、道路、街道设施都走这里）。
## 按「材质 × 空间格子」分组：同一格子里同一材质的所有几何体是一个网格，
## 既减少绘制调用，又保留视锥剔除与灯光范围剔除。

## Godot 以顺时针为正面
const FRONT_CLOCKWISE := true
const CELL := 96.0

var chunked := true
var _groups: Dictionary = {}
## 当前写入的材质类型（发光类材质不做环境光遮蔽）
var _kind := ""
const _NO_AO := ["ad", "neon", "holo", "decal", "lamp_warm", "lamp_cool", "leaf", "water", "glass", "win_warm", "win_cool"]


func _tool_for(kind: String, at: Vector3) -> SurfaceTool:
	_kind = kind
	var key := kind
	if chunked:
		key = "%s|%d|%d" % [kind, floori(at.x / CELL), floori(at.z / CELL)]
	if not _groups.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_groups[key] = {"st": st, "kind": kind, "count": 0}
	_groups[key]["count"] += 1
	return _groups[key]["st"]


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	var facing := (b - a).cross(c - a).dot(n)
	# 叉积与法线同向 = 逆时针；需要顺时针时交换 b、c
	if (facing > 0.0) == FRONT_CLOCKWISE:
		var t := b
		b = c
		c = t
	# 竖直面 UV = (x + z, y)，水平面 UV = (x, z)：都是米，材质里再按贴图尺寸缩放
	var flat := absf(n.y) > 0.7
	# 贴地的环境光遮蔽（烘焙进顶点色）：竖直面越靠近地面越暗，墙根、车底、树干底部有接触阴影
	var ao := not flat and not (_kind in _NO_AO)
	for p in [a, b, c]:
		if ao and p.y < 2.5 and p.y > -0.1:
			var f := lerpf(0.58, 1.0, clampf(p.y / 2.5, 0.0, 1.0))
			st.set_color(Color(col.r * f, col.g * f, col.b * f, col.a))
		else:
			st.set_color(col)
		st.set_normal(n)
		st.set_uv(Vector2(p.x, p.z) if flat else Vector2(p.x + p.z, p.y))
		st.add_vertex(p)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	_tri(st, a, b, c, n, col)
	_tri(st, a, c, d, n, col)


## 自带 UV 的四边形（树叶等贴图面片），a-b-c-d 依次对应 uv 的四个角
func quad_uv(kind: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, uvs: PackedVector2Array) -> void:
	var st := _tool_for(kind, (a + c) * 0.5)
	var n := (b - a).cross(d - a).normalized()
	for idx in [0, 1, 2, 0, 2, 3]:
		var p: Vector3 = [a, b, c, d][idx]
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(uvs[idx])
		st.add_vertex(p)


const _FACES := [
	[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
	[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
]


## 方块。rot 为方块自身的旋转；skip_bottom 省掉底面（放在地上的物体看不到底）
func box(kind: String, center: Vector3, size: Vector3, col: Color, rot := Basis.IDENTITY, skip_bottom := false) -> void:
	var st := _tool_for(kind, center)
	var hs := size * 0.5
	for f in _FACES:
		var n: Vector3 = f[0]
		if skip_bottom and n.y < -0.5:
			continue
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var hn := absf(n.dot(hs))
		var hu := absf(u.dot(hs))
		var hv := absf(v.dot(hs))
		var fc := n * hn
		var p0 := center + rot * (fc - u * hu - v * hv)
		var p1 := center + rot * (fc + u * hu - v * hv)
		var p2 := center + rot * (fc + u * hu + v * hv)
		var p3 := center + rot * (fc - u * hu + v * hv)
		_quad(st, p0, p1, p2, p3, (rot * n).normalized(), col)


## 圆柱 / 圆台（沿 Y 轴）。radius_top < 0 时与底部同半径
func cylinder(kind: String, center: Vector3, radius: float, height: float, col: Color, sides := 10, rot := Basis.IDENTITY, radius_top := -1.0) -> void:
	var st := _tool_for(kind, center)
	var rt := radius if radius_top < 0.0 else radius_top
	var hh := height * 0.5
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var b0 := center + rot * (d0 * radius + Vector3(0, -hh, 0))
		var b1 := center + rot * (d1 * radius + Vector3(0, -hh, 0))
		var t0 := center + rot * (d0 * rt + Vector3(0, hh, 0))
		var t1 := center + rot * (d1 * rt + Vector3(0, hh, 0))
		var mid := (d0 + d1).normalized()
		var slope := (radius - rt) / maxf(height, 0.001)
		var n := (rot * (mid + Vector3(0, slope, 0))).normalized()
		_quad(st, b0, b1, t1, t0, n, col)
		var top := center + rot * Vector3(0, hh, 0)
		var bot := center + rot * Vector3(0, -hh, 0)
		var up := (rot * Vector3.UP).normalized()
		if rt > 0.001:
			_tri(st, top, t0, t1, up, col)
		_tri(st, bot, b1, b0, -up, col)


## 双坡屋顶：底边矩形 w×d（中心 base 在檐口高度），屋脊高 h，沿 x（along_x）或沿 z；山墙三角用 gable_kind
func gable_roof(kind: String, base: Vector3, w: float, d: float, h: float, col: Color, along_x: bool, gable_kind: String, gable_col: Color) -> void:
	var st := _tool_for(kind, base)
	# 统一成「屋脊沿 x」计算，沿 z 时交换坐标轴
	var L := w if along_x else d
	var S := d if along_x else w
	var hl := L * 0.5
	var hs := S * 0.5
	var f := func(a: float, y: float, c: float) -> Vector3:
		return base + (Vector3(a, y, c) if along_x else Vector3(c, y, a))
	var r0: Vector3 = f.call(-hl, h, 0.0)
	var r1: Vector3 = f.call(hl, h, 0.0)
	var s0: Vector3 = f.call(-hl, 0.0, -hs)
	var s1: Vector3 = f.call(hl, 0.0, -hs)
	var n0: Vector3 = f.call(-hl, 0.0, hs)
	var n1: Vector3 = f.call(hl, 0.0, hs)
	var ns: Vector3 = f.call(0.0, hs, -h) - base
	var nn: Vector3 = f.call(0.0, hs, h) - base
	_quad(st, s0, s1, r1, r0, ns.normalized(), col)
	_quad(st, n0, n1, r1, r0, nn.normalized(), col)
	var gt := _tool_for(gable_kind, base)
	var ge: Vector3 = f.call(-1.0, 0.0, 0.0) - base
	_tri(gt, s0, n0, r0, ge.normalized(), gable_col)
	_tri(gt, s1, n1, r1, -ge.normalized(), gable_col)


## 立在两点之间的细杆（脚手架钢管、塔吊桁架）
func beam(kind: String, from: Vector3, to: Vector3, thickness: float, col: Color) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.001:
		return
	var y := dir / length
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	var basis := Basis(x, y, z)
	box(kind, (from + to) * 0.5, Vector3(thickness, length, thickness), col, basis)


## 全部分组合成一个多材质网格（行驶中的车等需要整体移动的物体用）
func to_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for key in _groups:
		var g: Dictionary = _groups[key]
		var st: SurfaceTool = g["st"]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, Mats.batch(String(g["kind"])))
	_groups.clear()
	return mesh


## 生成网格节点，挂到 parent 下
func build(parent: Node3D, cast_shadows := true) -> int:
	var made := 0
	for key in _groups:
		var g: Dictionary = _groups[key]
		var st: SurfaceTool = g["st"]
		var mesh := st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Batch_" + String(key).replace("|", "_").replace("-", "m")
		mi.mesh = mesh
		mi.material_override = Mats.batch(String(g["kind"]))
		var kind := String(g["kind"])
		if not cast_shadows or kind in ["glass", "neon", "win_warm", "win_cool", "decal", "water", "holo", "lamp_warm", "lamp_cool", "ad"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 远处的小物件不渲染（LOD）
		if kind in ["prop", "decal", "leaf"]:
			mi.visibility_range_end = 140.0 if kind != "leaf" else 220.0
			mi.visibility_range_end_margin = 10.0
		parent.add_child(mi)
		made += 1
	_groups.clear()
	return made
