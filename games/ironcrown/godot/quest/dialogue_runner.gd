class_name DialogueRunner
extends RefCounted
## 对话树（路线图 2.1；TECH.md 4.5）：读 data/dialogue/<区域>.json，按节点推进。只管规则，不碰界面。
## 节点 = {text, options: [{text, next | end}]}。条件与效果（检定、旗标）在 2.2 加入，这里先只认 next / end。

const DIR := "res://data/dialogue/%s.json"


var data: Dictionary = {}     # 当前这段对话
var id := ""
var node_id := ""


## 读过的对话文件缓存在 Engine 的元数据里：这个脚本用 static var 做缓存时，退出时脚本释放不掉（2.1 实测，引擎报「resources still in use」）
static func load_file(area: String) -> Dictionary:
	if Engine.has_meta("ic_dialogue_" + area):
		return Engine.get_meta("ic_dialogue_" + area)
	var path := DIR % area
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("对话文件打不开：" + path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("对话文件不是合法的 JSON：" + path)
		return {}
	Engine.set_meta("ic_dialogue_" + area, parsed)
	return parsed


## 检查一段对话：开始节点存在、每个选项要么 next 指向存在的节点要么 end、每个节点都从开始节点走得到、从开始节点出发能走到结束
static func validate(d: Dictionary) -> Array:
	var errors: Array = []
	var nodes: Dictionary = d.get("nodes", {})
	var start: String = d.get("start", "")
	if not nodes.has(start):
		errors.append("开始节点不存在：%s" % start)
		return errors
	for nid in nodes:
		var n: Dictionary = nodes[nid]
		if str(n.get("text", "")) == "":
			errors.append("%s：没有台词" % nid)
		var opts: Array = n.get("options", [])
		if opts.is_empty():
			errors.append("%s：没有选项（对话会卡住）" % nid)
		for o in opts:
			if str(o.get("text", "")) == "":
				errors.append("%s：有选项没有文字" % nid)
			if not o.get("end", false) and not nodes.has(str(o.get("next", ""))):
				errors.append("%s：选项「%s」指向不存在的节点 %s" % [nid, o.get("text", ""), o.get("next", "")])
	var seen := {start: true}
	var stack := [start]
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		for o in nodes[cur].get("options", []):
			var nx := str(o.get("next", ""))
			if nodes.has(nx) and not seen.has(nx):
				seen[nx] = true
				stack.append(nx)
	var can_end := false
	for nid in nodes:
		if not seen.has(nid):
			errors.append("%s：从开始节点走不到" % nid)
		else:
			for o in nodes[nid].get("options", []):     # 不用匿名函数：静态函数里的匿名函数加上静态变量，退出时脚本释放不掉
				if o.get("end", false):
					can_end = true
	if not can_end:
		errors.append("没有任何选项能结束对话")
	return errors


func start(area: String, dialogue_id: String) -> bool:
	var all := load_file(area)
	if not all.has(dialogue_id):
		push_warning("找不到对话：%s / %s" % [area, dialogue_id])
		return false
	data = all[dialogue_id]
	id = dialogue_id
	node_id = data.start
	return true


func speaker() -> String:
	return str(data.get("speaker", ""))


func node() -> Dictionary:
	return data.nodes.get(node_id, {})


func text() -> String:
	return str(node().get("text", ""))


func options() -> Array:
	return node().get("options", [])


## 选第 i 个选项：返回 true 表示对话继续，false 表示结束
func choose(i: int) -> bool:
	var opts := options()
	if i < 0 or i >= opts.size():
		return true
	var o: Dictionary = opts[i]
	if o.get("end", false) or not data.nodes.has(str(o.get("next", ""))):
		node_id = ""
		return false
	node_id = str(o.next)
	return true
