class_name FarLod
extends RefCounted
## 远处换一份单色网格（路线图 6.7a）：金穗平原上一栋房子一个网格好几种材质（石头、灰泥 / 土坯、木头、屋顶、雪、窗……）就是好几次绘制，
## 从营地往西南看麦渡、坠星院、磨坊、庄园二十来栋房子一共一两百次（电脑中画质那个机位 542 次，预算 400）。
## far_copy：把一个网格里普通的表面压成一个表面、颜色写进顶点色（同 MeshKit.flatten；带贴图的用材质上记的平均颜色 meta "avg"，
## 没记的用 albedo_color），自发光、不受光、透明、双面的表面原样留着；原来那份 visibility_range_end = dist、这份 visibility_range_begin = dist。
## 远处那份不投影（远处本来就在阴影距离以外）。用法：FarLod.apply(root, dist)——root 底下表面 ≥ MIN_SURFACES、够大的网格都换。

const MIN_SURFACES := 3
const MIN_SIZE := 3.0
static var _flat: StandardMaterial3D


static func apply(root: Node, dist: float) -> int:
	var n := 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("far_lod") or mi.skin != null or mi.mesh == null or mi.mesh.get_surface_count() < MIN_SURFACES or mi.visibility_range_end > 0.0 or mi.visibility_range_begin > 0.0:
			continue
		if mi.get_aabb().size.length() < MIN_SIZE:
			continue
		var twin := far_copy(mi)
		if twin == null:
			continue
		mi.visibility_range_end = dist
		twin.visibility_range_begin = dist
		n += 1
	return n


static func far_copy(mi: MeshInstance3D) -> MeshInstance3D:
	var m := mi.mesh
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var out := ArrayMesh.new()
	var special := []
	for si in m.get_surface_count():
		var mat := mi.get_surface_override_material(si) if mi.get_surface_override_material(si) else m.surface_get_material(si)
		if mi.material_override:
			mat = mi.material_override
		var bm := mat as BaseMaterial3D
		if bm == null or bm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or bm.emission_enabled or bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or bm.cull_mode != BaseMaterial3D.CULL_BACK:
			special.append(si)
			continue
		var a := m.surface_get_arrays(si)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nn: Variant = a[Mesh.ARRAY_NORMAL]
		var vc: Variant = a[Mesh.ARRAY_COLOR]
		var ix: Variant = a[Mesh.ARRAY_INDEX]
		var base: Color = bm.get_meta("avg", bm.albedo_color) if bm.albedo_texture != null else bm.albedo_color
		var shade := bm.vertex_color_use_as_albedo and vc is PackedColorArray and (vc as PackedColorArray).size() == v.size()
		var has_n := nn is PackedVector3Array and (nn as PackedVector3Array).size() == v.size()
		var start := verts.size()
		verts.append_array(v)
		for i in v.size():
			norms.append((nn as PackedVector3Array)[i] if has_n else Vector3.UP)
			var s: Color = (vc as PackedColorArray)[i] if shade else Color.WHITE
			cols.append(Color(base.r * s.r, base.g * s.g, base.b * s.b))
		if ix is PackedInt32Array and (ix as PackedInt32Array).size() > 0:
			for i in ix:
				idx.append(start + i)
		else:
			for i in v.size():
				idx.append(start + i)
	if verts.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if _flat == null:
		_flat = MeshKit.flat_mat(0.95)
	out.surface_set_material(0, _flat)
	for si in special:
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.surface_get_arrays(si))
		out.surface_set_material(out.get_surface_count() - 1, mi.material_override if mi.material_override else m.surface_get_material(si))
	var twin := MeshInstance3D.new()
	twin.name = str(mi.name) + "Far"
	twin.mesh = out
	twin.transform = mi.transform
	twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	twin.set_meta("far_lod", true)
	mi.set_meta("far_lod", true)
	mi.add_sibling(twin)
	return twin
