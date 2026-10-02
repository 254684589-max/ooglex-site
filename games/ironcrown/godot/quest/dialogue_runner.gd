class_name DialogueRunner
extends RefCounted
## 对话树（路线图 2.1；TECH.md 4.5）：读 data/dialogue/<区域>.json，按节点推进。只管规则，不碰界面。
## 节点 = {text, options, do?}；选项 = {text, next | end | check, if?, do?}（2.2 起）：
##   if    条件列表，全部满足才显示：{"flag": 名}（为真）、{"flag": 名, "eq": 值}、{"not_flag": 名}
##   check 检定：{"id": 唯一编号, "skill": speech|intimidate|insight, "dc": 难度, "pass": 成功去的节点, "fail": 失败去的节点}
##   do    效果列表（选中时 / 进入节点时执行）：{"set": 旗标名, "value": 值（默认 true）}
## 对话可以有 start_if：[{"if": [...], "node": 节点}]，第一个满足的决定从哪个节点开始（旗标改变 NPC 的态度）。
## 只认上面这些键（白名单），不执行任意表达式；用到的旗标必须登记在 data/flags.json。

const DIR := "res://data/dialogue/%s.json"


var data: Dictionary = {}     # 当前这段对话
var id := ""
var node_id := ""
var last_check := {}          # 刚做过的检定：{skill, ok}（界面显示「洞察检定成功」）

const OPTION_KEYS := ["text", "next", "end", "if", "check", "do"]
const NODE_KEYS := ["text", "options", "do"]
const COND_KEYS := ["flag", "not_flag", "eq"]


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
			if not o.get("end", false) and not o.has("check") and not nodes.has(str(o.get("next", ""))):
				errors.append("%s：选项「%s」指向不存在的节点 %s" % [nid, o.get("text", ""), o.get("next", "")])
	var registry := GameState.flag_registry()
	for k in d.get("start_if", []):
		if not nodes.has(str(k.get("node", ""))):
			errors.append("start_if 指向不存在的节点 %s" % k.get("node", ""))
		_validate_conds(k.get("if", []), "start_if", registry, errors)
	for nid in nodes:
		var n: Dictionary = nodes[nid]
		for key in n:
			if not key in NODE_KEYS:
				errors.append("%s：不认识的键 %s" % [nid, key])
		_validate_effects(n.get("do", []), nid, registry, errors)
		for o in n.get("options", []):
			for key in o:
				if not key in OPTION_KEYS:
					errors.append("%s：选项「%s」有不认识的键 %s" % [nid, o.get("text", ""), key])
			_validate_conds(o.get("if", []), nid, registry, errors)
			_validate_effects(o.get("do", []), nid, registry, errors)
			if o.has("check"):
				var c: Dictionary = o.check
				if not GameState.SKILL_NAMES.has(str(c.get("skill", ""))):
					errors.append("%s：检定的技能不认识：%s" % [nid, c.get("skill", "")])
				if str(c.get("id", "")) == "" or typeof(c.get("dc")) not in [TYPE_INT, TYPE_FLOAT]:
					errors.append("%s：检定缺编号或难度" % nid)
				for branch in ["pass", "fail"]:
					if not nodes.has(str(c.get(branch, ""))):
						errors.append("%s：检定的 %s 指向不存在的节点 %s" % [nid, branch, c.get(branch, "")])
	var seen := {start: true}
	var stack := [start]
	for k in d.get("start_if", []):
		if nodes.has(str(k.get("node", ""))) and not seen.has(str(k.node)):
			seen[str(k.node)] = true
			stack.append(str(k.node))
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		for o in nodes[cur].get("options", []):
			for nx in _targets(o):
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


## 一个选项可能去的节点（next，或检定的 pass / fail）
static func _targets(o: Dictionary) -> Array:
	if o.has("check"):
		return [str(o.check.get("pass", "")), str(o.check.get("fail", ""))]
	return [str(o.get("next", ""))]


static func _validate_conds(conds: Array, where: String, registry: Dictionary, errors: Array) -> void:
	for c in conds:
		for key in c:
			if not key in COND_KEYS:
				errors.append("%s：条件里不认识的键 %s" % [where, key])
		var name := str(c.get("flag", c.get("not_flag", "")))
		if name == "":
			errors.append("%s：条件缺旗标名" % where)
		elif not registry.has(name):
			errors.append("%s：旗标 %s 没有登记在 data/flags.json" % [where, name])


static func _validate_effects(effects: Array, where: String, registry: Dictionary, errors: Array) -> void:
	for e in effects:
		for key in e:
			if not key in ["set", "value"]:
				errors.append("%s：效果里不认识的键 %s" % [where, key])
		if not registry.has(str(e.get("set", ""))):
			errors.append("%s：旗标 %s 没有登记在 data/flags.json" % [where, e.get("set", "")])


## 条件是否全部满足
static func conds_ok(conds: Array) -> bool:
	for c in conds:
		if c.has("not_flag"):
			if GameState.has_flag(str(c.not_flag)):
				return false
		elif c.has("eq"):
			if GameState.get_flag(str(c.flag)) != c.eq:
				return false
		elif not GameState.has_flag(str(c.get("flag", ""))):
			return false
	return true


static func apply(effects: Array) -> void:
	for e in effects:
		GameState.set_flag(str(e.set), e.get("value", true))


func _enter(nid: String) -> void:
	node_id = nid
	apply(data.nodes[nid].get("do", []))


func start(area: String, dialogue_id: String) -> bool:
	var all := load_file(area)
	if not all.has(dialogue_id):
		push_warning("找不到对话：%s / %s" % [area, dialogue_id])
		return false
	data = all[dialogue_id]
	id = dialogue_id
	last_check = {}
	var first: String = data.start
	for k in data.get("start_if", []):
		if conds_ok(k.get("if", [])):
			first = str(k.node)
			break
	_enter(first)
	return true


func speaker() -> String:
	return str(data.get("speaker", ""))


func node() -> Dictionary:
	return data.nodes.get(node_id, {})


func text() -> String:
	return str(node().get("text", ""))


## 现在能看到的选项（条件不满足的隐藏）
func options() -> Array:
	var out := []
	for o in node().get("options", []):
		if conds_ok(o.get("if", [])):
			out.append(o)
	return out


## 选项显示的文字：检定选项前面加「[口才 · 把握较大]」
static func option_label(o: Dictionary) -> String:
	if o.has("check"):
		var c: Dictionary = o.check
		var chance := GameState.check_chance(str(c.skill), int(c.dc))
		return "[%s · %s] %s" % [GameState.SKILL_NAMES.get(str(c.skill), c.skill), GameState.chance_label(chance), o.text]
	return str(o.text)


## 选第 i 个选项：返回 true 表示对话继续，false 表示结束
func choose(i: int) -> bool:
	var opts := options()
	if i < 0 or i >= opts.size():
		return true
	var o: Dictionary = opts[i]
	apply(o.get("do", []))
	last_check = {}
	if o.has("check"):
		var c: Dictionary = o.check
		var ok := GameState.check(str(c.id), str(c.skill), int(c.dc))
		last_check = {"skill": str(c.skill), "ok": ok}
		_enter(str(c.pass if ok else c.fail))
		return true
	if o.get("end", false) or not data.nodes.has(str(o.get("next", ""))):
		node_id = ""
		return false
	_enter(str(o.next))
	return true
