class_name Schedule
extends RefCounted
## NPC 作息（路线图 4.6；STORY.md 4.2「NPC 作息：同一个人按时段换地方、换开场白」）。时段跟着剧情走（不做自由昼夜时钟，GameState.daypart），
## 所以作息就是「这个时段这个人在哪」：data/schedules.json 给每个人写不在老地方的那几个时段（没写的时段在老地方，区域脚本照常放）。
## 区域搭好以后 main 调 apply(world, area)：这个时段不在这儿的人拿掉、在这儿换了站位的挪过去、从别处过来的人放进来；剧情把时段推到别的（对话效果 daypart）时再调一次，人当场换地方。
## 换开场白不在这里：对话节点的 text_if（DialogueRunner，按 {"daypart": ...} 条件挑一句）。

const PATH := "res://data/schedules.json"
const META := "ic_schedules"


static func data() -> Dictionary:
	if not Engine.has_meta(META):
		var f := FileAccess.open(PATH, FileAccess.READ)
		var d: Variant = JSON.parse_string(f.get_as_text()) if f else null
		Engine.set_meta(META, d.get("people", {}) if d is Dictionary else {})
	return Engine.get_meta(META)


## 这个人现在（GameState.daypart）不在老地方时的去处 {area, pos, yaw}；在老地方返回 {}
static func slot(id: String, daypart := "") -> Dictionary:
	var p: Dictionary = data().get(id, {})
	if GameState.chapter < int(p.get("chapter", 0)) and not Engine.has_meta("ic_daypart_param_done"):
		return {}                        # 还没到这个人所在的那一章（序章是夜里，直接开鹭沼截图时托宾照样在泥炭场）；网址带 ?daypart= 预览时段的照样按作息走
	var dp := daypart if daypart != "" else GameState.daypart
	return (p.get("away", {}) as Dictionary).get(dp, {})


## 这个人现在在哪个区域
static func area_of(id: String, daypart := "") -> String:
	var s := slot(id, daypart)
	return str(s.area) if not s.is_empty() else str(data().get(id, {}).get("home", ""))


## 按作息摆人：拿掉不在这儿的、挪动换了站位的、放进从别处来的。返回这次动过的人的编号（测试、日志用）
static func apply(world: Node3D, area: String) -> Array:
	var moved := []
	for id: String in data():
		var p: Dictionary = data()[id]
		var s := slot(id)
		var node := world.find_child("Npc_" + id, true, false) as Npc
		var here := area_of(id) == area
		if node != null and not here:
			node.get_parent().remove_child(node)
			node.queue_free()
			moved.append(id)
		elif here and not s.is_empty():
			if node == null:
				node = _make(id, p)
				world.add_child(node)
			var at: Array = s.pos
			node.position = Vector3(float(at[0]), float(at[1]), float(at[2]))
			node.rotation.y = float(s.yaw)
			moved.append(id)
	return moved                         # 在老地方的人由区域脚本放（剧情条件不满足、区域脚本没放的，就不在）


## 从别处过来的人：名字、衣服颜色、对话从 schedules.json 里拿（和老地方放的一样）
static func _make(id: String, p: Dictionary) -> Npc:
	var n := Npc.make(str(p.name), [], Color(str(p.coat)))
	n.name = "Npc_" + id
	n.dialogue_area = str(p.dialogue)
	n.dialogue_id = id
	return n


## 校验（测试用）：区域认得、站位是三个数、时段认得、有名字和对话文件
static func validate() -> Array:
	var errors := []
	for id: String in data():
		var p: Dictionary = data()[id]
		for k in ["home", "name", "coat", "dialogue"]:
			if str(p.get(k, "")) == "":
				errors.append("%s：缺 %s" % [id, k])
		if not Areas.known(str(p.get("home", ""))):
			errors.append("%s：老地方 %s 不认识" % [id, p.get("home", "")])
		for dp: String in p.get("away", {}):
			var s: Dictionary = p.away[dp]
			if not Daypart.valid(dp):
				errors.append("%s：时段 %s 不认识" % [id, dp])
			if not Areas.known(str(s.get("area", ""))):
				errors.append("%s/%s：区域 %s 不认识" % [id, dp, s.get("area", "")])
			if not (s.get("pos") is Array and (s.pos as Array).size() == 3) or not s.has("yaw"):
				errors.append("%s/%s：要写 pos [x, y, z] 和 yaw" % [id, dp])
	return errors
