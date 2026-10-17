class_name Looks
extends RefCounted
## 人物的样子（路线图 A.2）：data/looks.json 按 NPC 的名字配打扮——服装、头、头发、颜色（CharacterModel 的 parts / look）。
## 没配的 NPC 照旧是占位胶囊。远处（LOD_FAR 米以外）换回胶囊、动作停下（一个真人模型 1.4–3.4 万个三角形，胶囊几十个）。

const PATH := "res://data/looks.json"
const DIR := "res://assets/characters/outfits/"
const META := "ic_looks"
const LOD_FAR := 32.0


static func data() -> Dictionary:
	if not Engine.has_meta(META):
		var f := FileAccess.open(PATH, FileAccess.READ)
		var d: Variant = JSON.parse_string(f.get_as_text()) if f else null
		Engine.set_meta(META, d if d is Dictionary else {})
	return Engine.get_meta(META)


static func has(npc_name: String) -> bool:
	return (data().get("people", {}) as Dictionary).has(npc_name)


## 这个人的部件路径和颜色：{"parts": [...], "look": {"tex": {材质: 贴图路径}, "tint": {材质: 颜色}}, "hide": [...]}；没配返回 {}
static func spec(npc_name: String) -> Dictionary:
	var p: Dictionary = data().get("people", {}).get(npc_name, {})
	if p.is_empty():
		return {}
	var pre: Dictionary = data().get("presets", {}).get(str(p.get("preset", "")), {})
	var parts := []
	for n in pre.get("parts", []) + p.get("hair", []):
		parts.append(DIR + str(n) + ".gltf")
	var tex := {}
	for k in pre.get("tex", {}):
		tex[k] = DIR + str(pre.tex[k]) + ".png"
	var tint: Dictionary = (pre.get("tint", {}) as Dictionary).duplicate()
	tint.merge(p.get("tint", {}), true)
	if p.has("hair_color"):
		for m in ["MI_Hair_1", "MI_Hair_2"]:          # 头发、眉毛、胡子都用这两个材质（贴图是灰的，按人上色）
			tint[m] = str(p.hair_color)
	return {"parts": parts, "look": {"tex": tex, "tint": tint}, "hide": pre.get("hide", [])}


## 搭一个人：CharacterModel（还没放进场景树；放进去以后 _ready 才加载模型）
static func make(npc_name: String) -> CharacterModel:
	var s := spec(npc_name)
	if s.is_empty():
		return null
	var m := CharacterModel.new()
	m.name = "Look"
	m.parts = s.parts
	m.look = s.look
	m.set_meta("hide", s.hide)
	return m


## 模型加载完以后：藏掉不要的部件（兜帽），远处不画（换回胶囊）
static func finish(m: CharacterModel) -> void:
	if not m.loaded:
		return
	for n in m.get_meta("hide", []):
		var node := m.scene_root.find_child(str(n), true, false)
		if node != null:
			(node as Node3D).visible = false       # 藏起来，不删：网页版删掉已经交给渲染器的蒙皮网格会报「material is null」（A.2a 实测）
	for mi: MeshInstance3D in m.scene_root.find_children("*", "MeshInstance3D", true, false):
		mi.visibility_range_end = LOD_FAR
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF      # NPC 不投影（低画质本来就没有阴影；中高画质省一半绘制）


## 校验（测试用）：预设、部件文件、贴图、颜色都对得上
static func validate() -> Array:
	var errors := []
	var pres: Dictionary = data().get("presets", {})
	for k in pres:
		for n in pres[k].get("parts", []):
			if not ResourceLoader.exists(DIR + str(n) + ".gltf"):
				errors.append("预设 %s：没有部件 %s" % [k, n])
		for m in pres[k].get("tex", {}):
			if not ResourceLoader.exists(DIR + str(pres[k].tex[m]) + ".png"):
				errors.append("预设 %s：没有贴图 %s" % [k, pres[k].tex[m]])
	for who in data().get("people", {}):
		var p: Dictionary = data().people[who]
		if not pres.has(str(p.get("preset", ""))):
			errors.append("%s：预设 %s 不认识" % [who, p.get("preset", "")])
		for n in p.get("hair", []):
			if not ResourceLoader.exists(DIR + str(n) + ".gltf"):
				errors.append("%s：没有发型 %s" % [who, n])
		for c in [p.get("hair_color", "#000")] + (p.get("tint", {}) as Dictionary).values():
			if not Color.html_is_valid(str(c)):
				errors.append("%s：颜色 %s 不对" % [who, c])
	return errors
