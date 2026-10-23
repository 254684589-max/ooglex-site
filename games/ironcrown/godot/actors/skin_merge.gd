class_name SkinMerge
extends RefCounted
## 把一个人身上挂在同一副骨架上的几块蒙皮网格（衣服、头、头发、胡子……）合成一块（路线图 B.6b）：
## 绘制调用按「网格 × 材质」算，A.2 的服装包一个人十几块网格；合成一块以后同一种材质（比如皮肤：衣服里的胳膊 + 头）只画一次。
## 每块网格有自己的 Skin（绑定的骨头和绑定姿势）：合成一份，各块的骨头编号按它重新对上。
## 藏起来的部件（摘掉的兜帽）不合进去；原来的网格藏起来不删（网页版删掉已经交给渲染器的蒙皮网格会报错，A.2a）。
## 格式对不上的（骨头权重 4 / 8 个不一样、有的有切线有的没有）那几块原样留着。

static func merge(skel: Skeleton3D) -> MeshInstance3D:
	var parts: Array = []
	for mi: MeshInstance3D in skel.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.skin == null or not mi.visible:
			continue
		parts.append(mi)
	parts = parts.filter(func(mi): return mi.mesh is ArrayMesh and mi.mesh.get_blend_shape_count() == 0)
	if parts.size() < 2:
		return null
	var skin := Skin.new()
	var bind_of := {}                    # 骨头名 → 合成后的编号
	var groups := {}                     # 材质名 → {mat, arrays: [...]}
	var order: Array = []
	for mi: MeshInstance3D in parts:
		var s: Skin = mi.skin
		var remap := PackedInt32Array()
		remap.resize(s.get_bind_count())
		for b in s.get_bind_count():
			var bname := str(s.get_bind_name(b))
			if bname == "":
				var bi := s.get_bind_bone(b)
				bname = skel.get_bone_name(bi) if bi >= 0 else "#%d" % b
			if not bind_of.has(bname):
				bind_of[bname] = skin.get_bind_count()
				skin.add_named_bind(bname, s.get_bind_pose(b))
			remap[b] = int(bind_of[bname])
		var mesh: ArrayMesh = mi.mesh
		for si in mesh.get_surface_count():
			var mat := mi.get_active_material(si)
			var key := (mat.resource_name if mat and mat.resource_name != "" else str(mat.get_instance_id() if mat else 0)) + ":%d" % mesh.surface_get_format(si)
			var arr := mesh.surface_get_arrays(si)
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			for k in bones.size():
				bones[k] = remap[bones[k]] if bones[k] < remap.size() else 0
			arr[Mesh.ARRAY_BONES] = bones
			if not groups.has(key):
				groups[key] = {"mat": mat, "list": [], "format": mesh.surface_get_format(si)}
				order.append(key)
			groups[key].list.append(arr)
	var out := ArrayMesh.new()
	for key in order:
		var g: Dictionary = groups[key]
		var merged := _concat(g.list)
		var flags: int = g.format & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS | Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged, [], {}, flags)
		out.surface_set_material(out.get_surface_count() - 1, g.mat)
	var mi := MeshInstance3D.new()
	mi.name = "Merged"
	mi.mesh = out
	mi.skin = skin
	skel.add_child(mi)
	mi.skeleton = mi.get_path_to(skel)
	for p: MeshInstance3D in parts:
		p.visible = false
	mi.set_meta("parts", PackedStringArray(parts.map(func(p): return str(p.name))))      # 合进去了哪些部件（测试用：弓手的兜帽在里面，剑兵的不在）
	return mi


## 同一种材质的几块：顶点、法线、切线、贴图坐标、骨头、权重接起来，索引加上偏移
static func _concat(list: Array) -> Array:
	if list.size() == 1:
		return list[0]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var keys := [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]
	for k in keys:
		if list.all(func(a): return a[k] != null):
			var acc = list[0][k].duplicate()
			for i in range(1, list.size()):
				acc.append_array(list[i][k])
			out[k] = acc
	var idx := PackedInt32Array()
	var base := 0
	for a in list:
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ii: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(verts.size()))
		for v in ii:
			idx.append(v + base)
		base += verts.size()
	out[Mesh.ARRAY_INDEX] = idx
	return out
