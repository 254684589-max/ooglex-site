class_name RigBuilder
extends RefCounted
## 程序化角色网格（2.6 之三，方案 1：代码搭的角色，不用外部素材）。
## 用锥管（tube）、椭球（ellipsoid）、方块（block）拼身体，每个顶点绑到骨骼上（关节处两根骨骼按比例过渡，
## 手肘膝盖弯曲时不裂开），整个角色合成一个蒙皮网格，最多三个面：
##   BODY 布 / 皮 / 骨（粗糙）· METAL 金属（带一点金属感）· GLOW 发光件（眼睛、灼痕，颜色由角色配方指定）
## 美术规则（ART.md 第二节「手绘感材质」）：不用照片贴图，把明暗直接画进顶点色——上亮下暗、越靠近地面越暗、
## 每个部件带一点颜色抖动；缩到几十像素高时剪影和色块依然清楚。
## 顶点坐标是「模型空间、静止姿势」（手臂自然下垂，面朝 +Z，角色的右手在 -X）。

enum { BODY, METAL, GLOW }

## ring 的骨骼说明：整数 = 只跟这根骨骼；[a, b, t] = a、b 两根按 t 过渡（t = 跟 b 的比例）
var _s: Array = []
var _seed := 1


func _init() -> void:
	for i in 3:
		_s.append({"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(),
			"b": PackedInt32Array(), "w": PackedFloat32Array(), "i": PackedInt32Array()})


static func _hash(n: int) -> float:
	n = (n * 374761393 + 668265263) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n ^ (n >> 16)) / 2147483647.0


func _shade(surf: int, col: Color, p: Vector3, n: Vector3) -> Color:
	if surf == GLOW:
		return col
	# 上亮下暗（假装顶光）+ 贴地压暗（假环境光遮蔽）+ 一点抖动（手绘感）
	var top := 0.72 + 0.34 * clampf(n.y * 0.5 + 0.5, 0.0, 1.0)
	var ground := lerpf(0.62, 1.0, clampf(p.y / 0.9, 0.0, 1.0))
	_seed += 1
	var j := 1.0 + (_hash(_seed) - 0.5) * 0.08
	var k := top * ground * j
	return Color(col.r * k, col.g * k, col.b * k)


func _vert(surf: int, p: Vector3, n: Vector3, col: Color, bone) -> int:
	var s: Dictionary = _s[surf]
	s.v.append(p)
	s.n.append(n.normalized())
	s.c.append(_shade(surf, col, p, n))
	if bone is Array:
		var t: float = clampf(bone[2], 0.0, 1.0)
		s.b.append_array(PackedInt32Array([bone[0], bone[1], 0, 0]))
		s.w.append_array(PackedFloat32Array([1.0 - t, t, 0.0, 0.0]))
	else:
		s.b.append_array(PackedInt32Array([bone, 0, 0, 0]))
		s.w.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	return s.v.size() - 1


func _tri(surf: int, a: int, b: int, c: int) -> void:
	## 统一绕向：Godot 的正面是「从法线方向看顺时针」，(b - a) × (c - a) 要和法线反向
	var s: Dictionary = _s[surf]
	var pa: Vector3 = s.v[a]
	var nsum: Vector3 = s.n[a] + s.n[b] + s.n[c]
	if (s.v[b] - pa).cross(s.v[c] - pa).dot(nsum) > 0.0:
		s.i.append_array(PackedInt32Array([a, c, b]))
	else:
		s.i.append_array(PackedInt32Array([a, b, c]))


static func _frame(axis: Vector3) -> Array:
	var ref := Vector3.FORWARD if absf(axis.dot(Vector3.UP)) > 0.9 else Vector3.UP
	var u := axis.cross(ref).normalized()
	var v := axis.cross(u).normalized()
	return [u, v]


## 锥管：沿折线 pts 的一串截面，radii 每个截面的半径（Vector2：横向、纵深两个方向，可以做扁的躯干），
## bones 每个截面的骨骼说明。caps：两端是否封口（封口向外鼓一点，看起来圆）。
func tube(pts: Array, radii: Array, bones: Array, col: Color, surf := BODY, sides := 8, caps := true, facing := Vector3.ZERO) -> void:
	var n := pts.size()
	var rings: Array = []
	for k in n:
		var p: Vector3 = pts[k]
		var axis: Vector3 = ((pts[mini(k + 1, n - 1)] as Vector3) - (pts[maxi(k - 1, 0)] as Vector3)).normalized()
		var f := _frame(axis)
		var u: Vector3 = f[0]
		var v: Vector3 = f[1]
		if facing != Vector3.ZERO:
			# 让截面的「纵深」方向对准 facing（躯干扁的一面朝前）
			v = (facing - axis * facing.dot(axis)).normalized()
			u = axis.cross(v).normalized()
		var r: Vector2 = radii[k]
		var ring: Array = []
		for i in sides:
			var a := TAU * i / sides
			var dir := u * cos(a) + v * sin(a)
			var pos := p + u * cos(a) * r.x + v * sin(a) * r.y
			ring.append(_vert(surf, pos, dir, col, bones[k]))
		rings.append(ring)
	for k in n - 1:
		for i in sides:
			var j := (i + 1) % sides
			_tri(surf, rings[k][i], rings[k + 1][i], rings[k + 1][j])
			_tri(surf, rings[k][i], rings[k + 1][j], rings[k][j])
	if caps:
		for e in [0, n - 1]:
			var r: Vector2 = radii[e]
			if r.x <= 0.001 and r.y <= 0.001:
				continue
			var inward: Vector3 = ((pts[e] as Vector3) - (pts[1 if e == 0 else n - 2] as Vector3)).normalized()
			var c := _vert(surf, (pts[e] as Vector3) + inward * minf(r.x, r.y) * 0.5, inward, col, bones[e])
			for i in sides:
				_tri(surf, c, rings[e][i], rings[e][(i + 1) % sides])


## 两点之间的锥形肢体（手臂、腿、骨头）：a 端半径 ra、b 端半径 rb；bone_b 给了就在靠 b 的一端平滑过渡到 bone_b
func limb(a: Vector3, b: Vector3, ra: float, rb: float, bone_a: int, col: Color, bone_b := -1, surf := BODY, sides := 7, bulge := 0.0) -> void:
	var pts := [a, a.lerp(b, 0.5), b.lerp(a, 0.12), b]
	var mid := (ra + rb) * 0.5 * (1.0 + bulge)
	var radii := [Vector2(ra, ra), Vector2(mid, mid), Vector2(lerpf(rb, mid, 0.2), lerpf(rb, mid, 0.2)), Vector2(rb, rb)]
	var bones: Array = [bone_a, bone_a, bone_a, bone_a]
	if bone_b >= 0:
		bones = [bone_a, bone_a, [bone_a, bone_b, 0.3], [bone_a, bone_b, 0.5]]
	tube(pts, radii, bones, col, surf, sides)


## 椭球：center、三个半轴 radii，basis 旋转；rings × sides 的经纬网格
func ellipsoid(center: Vector3, radii: Vector3, bone, col: Color, surf := BODY, basis := Basis.IDENTITY, rings := 5, sides := 8) -> void:
	var idx: Array = []
	for r in rings + 1:
		var th := PI * r / rings
		var row: Array = []
		for i in sides:
			var ph := TAU * i / sides
			var unit := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var pos := center + basis * (unit * radii)
			var nrm := basis * (unit / radii)
			row.append(_vert(surf, pos, nrm, col, bone))
		idx.append(row)
	for r in rings:
		for i in sides:
			var j := (i + 1) % sides
			var a: int = idx[r][i]
			var b: int = idx[r + 1][i]
			var c: int = idx[r + 1][j]
			var d: int = idx[r][j]
			# 两极的一圈顶点重合，只出一个三角形（不留退化三角形）
			if r == 0:
				_tri(surf, a, b, c)
			elif r == rings - 1:
				_tri(surf, a, b, d)
			else:
				_tri(surf, a, b, c)
				_tri(surf, a, c, d)


## 方块（可以上窄下宽：top 是顶面相对底面的缩放），平面法线；用于护甲片、靴子、剑身、盾牌等
func block(center: Vector3, size: Vector3, bone, col: Color, surf := BODY, basis := Basis.IDENTITY, top := Vector2.ONE) -> void:
	var h := size * 0.5
	var corners: Array = []
	for y in [-1, 1]:
		for z in [-1, 1]:
			for x in [-1, 1]:
				var sx := h.x * (top.x if y > 0 else 1.0)
				var sz := h.z * (top.y if y > 0 else 1.0)
				corners.append(center + basis * Vector3(x * sx, y * h.y, z * sz))
	# 六个面：每个面 4 个角（corners 的下标：x 变化最快，然后 z，然后 y）
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	for f in faces:
		var p0: Vector3 = corners[f[0]]
		var nrm: Vector3 = (((corners[f[1]] as Vector3) - p0).cross((corners[f[3]] as Vector3) - p0)).normalized()
		var fc: Vector3 = ((corners[f[0]] as Vector3) + corners[f[1]] + corners[f[2]] + corners[f[3]]) * 0.25
		if nrm.dot(fc - center) < 0.0:
			nrm = -nrm
		var ids: Array = []
		for k in 4:
			ids.append(_vert(surf, corners[f[k]], nrm, col, bone))
		_tri(surf, ids[0], ids[1], ids[2])
		_tri(surf, ids[0], ids[2], ids[3])


## 尖刺 / 角：底面中心 base、尖端 tip、底半径 r
func spike(base: Vector3, tip: Vector3, r: float, bone, col: Color, surf := BODY, sides := 6) -> void:
	tube([base, tip], [Vector2(r, r), Vector2(0, 0)], [bone, bone], col, surf, sides, true)


func triangle_count() -> int:
	var t := 0
	for s in _s:
		t += (s.i as PackedInt32Array).size() / 3
	return t


## 生成 ArrayMesh；返回 {mesh, surfaces: [面种类...]}（空的面不生成）
func commit() -> Dictionary:
	var mesh := ArrayMesh.new()
	var kinds: Array = []
	for k in 3:
		var s: Dictionary = _s[k]
		if (s.i as PackedInt32Array).is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = s.v
		arr[Mesh.ARRAY_NORMAL] = s.n
		arr[Mesh.ARRAY_COLOR] = s.c
		arr[Mesh.ARRAY_BONES] = s.b
		arr[Mesh.ARRAY_WEIGHTS] = s.w
		arr[Mesh.ARRAY_INDEX] = s.i
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		kinds.append(k)
	return {"mesh": mesh, "surfaces": kinds, "tris": triangle_count()}
