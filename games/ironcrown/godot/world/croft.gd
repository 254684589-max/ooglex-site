class_name Croft
extends RefCounted
## 余火高地的矮石屋（路线图 5.2a，D12；STORY.md 5.2「干砌石墙的矮石屋、草皮屋顶压着石头」）：原创的高地牧羊人小屋。
## 和霜渡镇的半木结构房子（House）不一样：墙是 0.6 米厚的干砌石、只有一人多高，屋顶是厚厚的草皮、压满了雪，屋檐下一圈草绳吊着压顶的石头（防风把草皮掀了）；
## 窗又小又深，门矮，山墙头上一个粗石烟囱。窗户的亮 / 暗、光晕用 House 的那一套材质（Daypart.set_windows 认得：白天灭、黄昏和夜里亮）。
## 本地坐标同 House：原点在正面墙脚中点，正面朝 +Z，往 -Z 纵深 d。

const WALL_H := 1.95
const WALL_T := 0.6
const PITCH := 33.0
const EAVE := 0.35
const TURF := 0.38                  # 草皮屋顶的厚度


static func build(parent: Node3D, pos: Vector3, yaw: float, spec: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Croft_" + str(spec.get("id", ""))
	root.position = pos
	root.rotation_degrees.y = yaw
	root.add_to_group("house")
	parent.add_child(root)
	var w: float = spec.get("w", 7.0)
	var d: float = spec.get("d", 5.0)
	var door_x: float = spec.get("door_x", 0.0)
	var lit: float = spec.get("lit", 0.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 1))
	var kit := MeshKit.new()
	var windows := {"lit": 0, "dark": 0}
	# 墙：一圈厚石墙（墙脚宽一点、往上微收）
	kit.box("stone", Vector3(0, WALL_H * 0.5, -d * 0.5), Vector3(w, WALL_H, d), Basis.IDENTITY, 1.0, 0.5)
	kit.box("stone", Vector3(0, 0.22, -d * 0.5), Vector3(w + 0.2, 0.44, d + 0.2), Basis.IDENTITY, 0.75, 0.45)
	for cx in [-w * 0.5, w * 0.5]:                          # 四角的大石块（墙角往外鼓一点，像垒出来的）
		for cz in [0.0, -d]:
			kit.box("stone", Vector3(cx, WALL_H * 0.45, cz), Vector3(0.75, WALL_H * 0.9, 0.75), Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), 0.9, 0.5)
	# 门：矮、深，木板门，门楣一条长石
	kit.box("timber", Vector3(door_x, 0.82, 0.03), Vector3(0.9, 1.64, 0.08), Basis.IDENTITY, 0.75, 0.6)
	kit.box("stone", Vector3(door_x, 1.74, 0.08), Vector3(1.4, 0.2, 0.32), Basis.IDENTITY, 0.9, 0.8)
	for s in [-1.0, 1.0]:
		kit.box("stone", Vector3(door_x + s * 0.58, 0.85, 0.06), Vector3(0.26, 1.7, 0.26), Basis.IDENTITY, 0.85, 0.6)
	# 窗：正面一扇或两扇（避开门），山墙一扇
	var front := []
	for x in [-w * 0.3, w * 0.3]:
		if absf(x - door_x) > 1.3:
			front.append(x)
	for x in front:
		House._window(kit, Vector3(x, 1.2, 0.0), 0.45, 0.42, rng.randf() < lit, false, windows)
	var side_on := rng.randf() < lit
	var sb := Basis(Vector3.UP, PI * 0.5)                    # 东山墙（本地 +X）上的窗：先在正面做好再转过去
	var side_kit := MeshKit.new()
	House._window(side_kit, Vector3(0, 1.2, 0), 0.4, 0.4, side_on, true, windows)
	_merge_rotated(kit, side_kit, Transform3D(sb, Vector3(w * 0.5, 0, -d * 0.5)))
	# 屋顶：屋脊顺着宽（前后两坡），草皮厚、檐口露草，坡面压满雪；山墙是石砌的三角
	var rise := (d * 0.5 + EAVE) * tan(deg_to_rad(PITCH))
	var ridge_y := WALL_H + rise
	for side in [1.0, -1.0]:                               # 前坡、后坡
		var eave_z := EAVE if side > 0 else -d - EAVE
		var mid_z := -d * 0.5
		var a := Vector3(-w * 0.5 - EAVE, WALL_H - 0.02, eave_z)
		var b := Vector3(w * 0.5 + EAVE, WALL_H - 0.02, eave_z)
		var c := Vector3(w * 0.5 + EAVE, ridge_y, mid_z)
		var e := Vector3(-w * 0.5 - EAVE, ridge_y, mid_z)
		var n := (b - a).cross(e - a).normalized()
		if n.y < 0:
			n = -n
		var up := n * TURF
		kit.quad("thatch", [a + up, b + up, c + up, e + up] if side > 0 else [b + up, a + up, e + up, c + up], n)        # 草皮的上面（雪盖着大半）
		kit.quad("thatch", [a, b, b + up, a + up] if side > 0 else [b, a, a + up, b + up], Vector3(0, 0, side).normalized())   # 檐口：一道厚厚的草皮边
		var inset := 0.22                                  # 雪：从檐口往里 0.22 米起、一直盖到屋脊，比草皮高一点
		var sa := a.lerp(e, inset / a.distance_to(e)) + up + n * 0.06
		var sbb := b.lerp(c, inset / b.distance_to(c)) + up + n * 0.06
		kit.quad("snow", [sa, sbb, c + up + n * 0.1, e + up + n * 0.1] if side > 0 else [sbb, sa, e + up + n * 0.1, c + up + n * 0.1], n, [0.92, 0.92, 1.0, 1.0])
		# 压顶的石头：草绳从屋脊挂下来，过了檐口吊一块石头
		var count := int(w / 0.95)
		for k in count:
			var t := (float(k) + 0.5) / float(count)
			var ex := lerpf(-w * 0.5, w * 0.5, t) + rng.randf_range(-0.08, 0.08)
			var hang := Vector3(ex, WALL_H - 0.02 + TURF * 0.5, eave_z + side * 0.05)
			var stone_c := hang + Vector3(0, -0.42 - rng.randf_range(0.0, 0.12), 0)
			kit.cylinder("rope", hang, stone_c + Vector3(0, 0.1, 0), 0.015, 0.015, 4)
			kit.box("stone", stone_c, Vector3(0.24, 0.2, 0.2) * rng.randf_range(0.85, 1.2), Basis(Vector3.UP, rng.randf_range(-0.5, 0.5)), 0.95, 0.7)
	for gx in [-w * 0.5, w * 0.5]:                          # 山墙三角（石砌）
		var s := 1.0 if gx > 0 else -1.0
		kit.tri("stone", Vector3(gx, WALL_H, 0.0), Vector3(gx, WALL_H, -d), Vector3(gx, ridge_y - 0.1, -d * 0.5), Vector3(s, 0, 0))
	kit.box("snow", Vector3(0, ridge_y + TURF + 0.08, -d * 0.5), Vector3(w + EAVE * 2.0, 0.2, 0.55), Basis.IDENTITY, 1.0, 0.9)   # 屋脊上一道厚雪
	# 烟囱：西山墙头上一根粗石烟囱
	var cx := -w * 0.5 + 0.35
	var ch := ridge_y + 0.9
	kit.box("stone", Vector3(cx, ch * 0.5 + 0.4, -d * 0.5), Vector3(0.8, ch - 0.8, 0.8), Basis.IDENTITY, 1.0, 0.6)
	kit.box("snow", Vector3(cx, ch + 0.02, -d * 0.5), Vector3(0.86, 0.08, 0.86))
	if spec.get("smoke", true):
		Atmos.smoke(root, Vector3(cx, ch + 0.25, -d * 0.5))
	var mats := {"stone": Look.mat("stone"), "timber": Look.mat("timber"), "snow": Look.mat("snow"), "thatch": Look.thatch(),
		"glass_lit": Look.glass_lit(), "glass_dark": Look.glass_dark(), "halo": Look.halo(Look.WINDOW_COLOR, 0.32), "rope": Look.mat("peat")}
	var mi := kit.build(mats)
	mi.name = "Mesh"
	root.add_child(mi)
	root.set_meta("windows", windows)
	root.set_meta("seed", int(spec.get("seed", 1)))
	root.set_meta("size", Vector2(w, d))
	return root


## 碰撞：屋身一个盒子（同 House.solids 的格式：[[变换, 尺寸]]，按 pos、yaw 摆好）
static func solids(pos: Vector3, yaw: float, spec: Dictionary) -> Array:
	var w: float = spec.get("w", 7.0)
	var d: float = spec.get("d", 5.0)
	var place := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), pos)
	return [[place * Transform3D(Basis.IDENTITY, Vector3(0, 1.4, -d * 0.5)), Vector3(w + 0.3, 2.8, d + 0.3)]]


## 把另一个 MeshKit 里的面转一下并进来（山墙上的窗）
static func _merge_rotated(kit: MeshKit, other: MeshKit, xf: Transform3D) -> void:
	for key in other.tools:
		var st: SurfaceTool = other.tools[key]
		var arr := st.commit_to_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var cols = arr[Mesh.ARRAY_COLOR]
		var uvs = arr[Mesh.ARRAY_TEX_UV]
		var dst := kit._st(str(key))
		for i in verts.size():
			dst.set_normal(xf.basis * norms[i])
			if cols != null:
				dst.set_color(cols[i])
			if uvs != null:
				dst.set_uv(uvs[i])
			dst.add_vertex(xf * verts[i])
		kit.counts[key] = int(kit.counts.get(key, 0)) + verts.size() / 3
