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


func _tool_for(kind: String, at: Vector3) -> SurfaceTool:
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
	for p in [a, b, c]:
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(Vector2(p.x + p.z, p.y))
		st.add_vertex(p)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	_tri(st, a, b, c, n, col)
	_tri(st, a, c, d, n, col)


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
		if not cast_shadows or kind in ["glass", "neon", "win_warm", "win_cool", "decal", "water", "holo"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 远处的小物件不渲染（LOD）
		if kind in ["prop", "decal"]:
			mi.visibility_range_end = 140.0
			mi.visibility_range_end_margin = 10.0
		parent.add_child(mi)
		made += 1
	_groups.clear()
	return made
