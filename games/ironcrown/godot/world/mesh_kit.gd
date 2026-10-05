class_name MeshKit
extends RefCounted
## 把一栋房子（或一棵树）的盒子、斜面、三角面、圆柱按材质合并成一个网格：每种材质一次绘制调用（TECH.md 第五节预算）。
## 顶点色当作遮蔽亮度（材质开了 vertex_color_use_as_albedo）：墙脚、屋檐下传入较暗的值。
## UV 按每个面自己的平面方向投影（1 单位 = 1 米，材质的 uv1_scale 决定多少米平铺一次），并生成切线给法线贴图用。
## 不用三向投影：1.4 实测三向投影每张贴图要采样三次，软件渲染下帧率从 13.7 掉到 3（TECH.md 4.6）。
## 用法：kit.box("stone", ...) … 最后 kit.build({"stone": Look.mat("stone"), ...}) 得到一个 MeshInstance3D。

var tools := {}
var counts := {}


func _st(key: String) -> SurfaceTool:
	if not tools.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[key] = st
		counts[key] = 0
	return tools[key]


func _v(st: SurfaceTool, p: Vector3, n: Vector3, shade: float, u: Vector3, v: Vector3) -> void:
	st.set_normal(n)
	st.set_color(Color(shade, shade, shade))
	st.set_uv(Vector2(p.dot(u), p.dot(v)))
	st.add_vertex(p)


## 面的贴图方向：u 沿水平（屋顶上沿屋脊），v 朝下（图片上方对着世界上方）
static func _axes(n: Vector3) -> Array:
	var ref := Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT
	var u := n.cross(ref).normalized()
	var v := n.cross(u).normalized()
	return [u, v]


## 四边形：p0..p3 沿边依次给出，n 是朝外的法线；绕向按法线自动调成 Godot 的正面（从外面看顺时针）
func quad(key: String, pts: Array, n: Vector3, shades := [1.0, 1.0, 1.0, 1.0]) -> void:
	var st := _st(key)
	var order := [0, 1, 2, 0, 2, 3]
	if (pts[1] - pts[0]).cross(pts[2] - pts[0]).dot(n) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	var ax := _axes(n)
	for i in order:
		_v(st, pts[i], n, shades[i], ax[0], ax[1])
	counts[key] += 2


func tri(key: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3, shade := 1.0) -> void:
	var st := _st(key)
	var pts := [a, b, c]
	if (b - a).cross(c - a).dot(n) > 0.0:
		pts = [a, c, b]
	var ax := _axes(n)
	for p in pts:
		_v(st, p, n, shade, ax[0], ax[1])
	counts[key] += 1


## 盒子：center 中心、size 尺寸、basis 朝向（默认轴对齐）；ctop / cbot 侧面上下两端的遮蔽亮度；bottom = 是否画底面
func box(key: String, center: Vector3, size: Vector3, basis := Basis.IDENTITY, ctop := 1.0, cbot := 1.0, bottom := false) -> void:
	var h := size * 0.5
	var c := func(x: float, y: float, z: float) -> Vector3: return center + basis * Vector3(x * h.x, y * h.y, z * h.z)
	var px: Vector3 = basis.x.normalized()
	var py: Vector3 = basis.y.normalized()
	var pz: Vector3 = basis.z.normalized()
	quad(key, [c.call(-1, 1, -1), c.call(1, 1, -1), c.call(1, 1, 1), c.call(-1, 1, 1)], py, [ctop, ctop, ctop, ctop])
	if bottom:
		quad(key, [c.call(-1, -1, -1), c.call(1, -1, -1), c.call(1, -1, 1), c.call(-1, -1, 1)], -py, [cbot, cbot, cbot, cbot])
	quad(key, [c.call(1, 1, -1), c.call(1, 1, 1), c.call(1, -1, 1), c.call(1, -1, -1)], px, [ctop, ctop, cbot, cbot])
	quad(key, [c.call(-1, 1, -1), c.call(-1, 1, 1), c.call(-1, -1, 1), c.call(-1, -1, -1)], -px, [ctop, ctop, cbot, cbot])
	quad(key, [c.call(-1, 1, 1), c.call(1, 1, 1), c.call(1, -1, 1), c.call(-1, -1, 1)], pz, [ctop, ctop, cbot, cbot])
	quad(key, [c.call(-1, 1, -1), c.call(1, 1, -1), c.call(1, -1, -1), c.call(-1, -1, -1)], -pz, [ctop, ctop, cbot, cbot])


## 两端粗细不同的多棱柱（树干、树枝）：从 a 到 b，半径 r0 → r1
func cylinder(key: String, a: Vector3, b: Vector3, r0: float, r1: float, sides := 6, shade := 1.0) -> void:
	var axis := (b - a)
	if axis.length() < 0.001:
		return
	var dir := axis.normalized()
	var ref := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var u := dir.cross(ref).normalized()
	var v := dir.cross(u).normalized()
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var n0 := u * cos(a0) + v * sin(a0)
		var n1 := u * cos(a1) + v * sin(a1)
		var mid := (n0 + n1).normalized()
		quad(key, [a + n0 * r0, a + n1 * r0, b + n1 * r1, b + n0 * r1], mid, [shade * 0.8, shade * 0.8, shade, shade])


## 把几个网格（各自可能有几个表面、几种材质）压成**一个表面**：每个表面的颜色写进顶点色，配一种开了顶点色的材质就能画，
## 一次绘制调用（B.5：军阵的占位兵原来身子、头、鼻子、布带、盾、小旗、兵器各一次，60 人超预算）。
## 坐标换算到 root 的本地坐标；带贴图的材质（木头）写不进顶点色，用 wood 代替；材质本身开了顶点色的（遮蔽亮度）乘进去。
## 返回的网格配 flat_mat() 那种材质（vertex_color_is_srgb：顶点色和材质颜色一样按 sRGB 算，颜色和原来一致）。
static func flatten(parts: Array, root: Node3D, wood := Color("4a3a2e")) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for mi: MeshInstance3D in parts:
		var xf := _relative(mi, root)
		var nb := xf.basis.inverse().transposed()
		var m := mi.mesh
		for si in m.get_surface_count():
			var a := m.surface_get_arrays(si)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var n: Variant = a[Mesh.ARRAY_NORMAL]
			var has_n := n is PackedVector3Array and (n as PackedVector3Array).size() == v.size()
			var vc: Variant = a[Mesh.ARRAY_COLOR]
			var ix: Variant = a[Mesh.ARRAY_INDEX]
			var mat := mi.material_override
			if mat == null:
				mat = mi.get_surface_override_material(si) if mi.get_surface_override_material(si) else m.surface_get_material(si)
			var base := Color.WHITE
			var shade := false
			if mat is BaseMaterial3D:
				base = wood if (mat as BaseMaterial3D).albedo_texture != null else (mat as BaseMaterial3D).albedo_color
				shade = (mat as BaseMaterial3D).vertex_color_use_as_albedo and vc is PackedColorArray and (vc as PackedColorArray).size() == v.size()
			var start := verts.size()
			for i in v.size():
				verts.append(xf * v[i])
				norms.append((nb * (n as PackedVector3Array)[i]).normalized() if has_n else Vector3.UP)
				var s: Color = (vc as PackedColorArray)[i] if shade else Color.WHITE
				cols.append(Color(base.r * s.r, base.g * s.g, base.b * s.b))
			if ix is PackedInt32Array and (ix as PackedInt32Array).size() > 0:
				for i in ix:
					idx.append(start + i)
			else:
				for i in v.size():
					idx.append(start + i)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## 配 flatten() 网格的材质：颜色全在顶点色里
static func flat_mat(roughness := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = roughness
	return m


## node 相对 root 的变换（不要求已经进场景树）
static func _relative(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## 合并成一个网格；keys 的顺序就是表面的顺序，没有内容的材质跳过
func build(materials: Dictionary) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for key in materials:
		if not tools.has(key):
			continue
		var st: SurfaceTool = tools[key]
		st.generate_tangents()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[key])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi
