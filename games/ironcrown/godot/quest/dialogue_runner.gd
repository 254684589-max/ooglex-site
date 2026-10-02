class_name DialogueRunner
extends RefCounted
## 对话树（路线图 2.1；TECH.md 4.5）：读 data/dialogue/<区域>.json，按节点推进。只管规则，不碰界面。
## 节点 = {text, options, do?}；选项 = {text, next | end | check, if?, do?}（2.2 起）：
##   if    条件列表，全部满足才显示：{"flag": 名}（为真）、{"flag": 名, "eq": 值}、{"not_flag": 名}；
##         2.3 起：{"quest_active": 任务}、{"quest_done": 任务}、{"not_quest": 任务}（还没接）、{"quest_stage": 任务, "eq": 阶段}、{"has_item": 物品}；
##         2.6 起：{"silver": 数量}（身上至少有这么多银币）；2.7 起：{"rep": 势力, "at_least": 数值}
##   check 检定：{"id": 唯一编号, "skill": speech|intimidate|insight, "dc": 难度, "pass": 成功去的节点, "fail": 失败去的节点}
##   do    效果列表（选中时 / 进入节点时执行）：{"set": 旗标名, "value": 值（默认 true）}；
##         2.3 起：{"quest": 任务}（接任务）、{"quest": 任务, "stage": 阶段}（推进）、{"quest_done": 任务}、{"clue": 线索}、{"take_item": 物品}；
##         2.6 起：{"pay": 数量}（付银币）；2.7 起：{"rep": 势力, "delta": 变化}（改声望）；3.1 起：{"give_item": 物品}（给玩家一件物品，例如买面包）
## 对话可以有 start_if：[{"if": [...], "node": 节点}]，第一个满足的决定从哪个节点开始（旗标改变 NPC 的态度）。
## 只认上面这些键（白名单），不执行任意表达式；用到的旗标必须登记在 data/flags.json。

const DIR := "res://data/dialogue/%s.json"


var data: Dictionary = {}     # 当前这段对话
var id := ""
var node_id := ""
var last_check := {}          # 刚做过的检定：{skill, ok}（界面显示「洞察检定成功」）

const OPTION_KEYS := ["text", "next", "end", "if", "check", "do"]
const NODE_KEYS := ["text", "options", "do"]
const COND_KEYS := ["flag", "not_flag", "eq", "quest_active", "quest_done", "not_quest", "quest_stage", "has_item", "silver", "rep", "at_least"]
const EFFECT_KEYS := ["set", "value", "quest", "stage", "quest_done", "clue", "take_item", "give_item", "pay", "rep", "delta"]


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
	var qd := GameState.quest_data()
	for c in conds:
		for key in c:
			if not key in COND_KEYS:
				errors.append("%s：条件里不认识的键 %s" % [where, key])
		for qk in ["quest_active", "quest_done", "not_quest", "quest_stage"]:
			if c.has(qk) and not qd.quests.has(str(c[qk])):
				errors.append("%s：任务 %s 不在 data/quests.json 里" % [where, c[qk]])
		if c.has("quest_stage") and qd.quests.has(str(c.quest_stage)) and not qd.quests[str(c.quest_stage)].stages.has(str(c.get("eq", ""))):
			errors.append("%s：任务 %s 没有阶段 %s" % [where, c.quest_stage, c.get("eq", "")])
		if c.has("flag") or c.has("not_flag"):
			var name := str(c.get("flag", c.get("not_flag", "")))
			if not registry.has(name):
				errors.append("%s：旗标 %s 没有登记在 data/flags.json" % [where, name])
		elif c.has("has_item") and GameState.item(str(c.has_item)).is_empty():
			errors.append("%s：物品 %s 不在 data/items.json 里" % [where, c.has_item])
		elif c.has("rep") and not GameState.progression().get("factions", {}).has(str(c.rep)):
			errors.append("%s：势力 %s 不在 data/progression.json 里" % [where, c.rep])
		elif c.has("silver") and int(c.silver) <= 0:
			errors.append("%s：银币条件要大于 0" % where)
		elif not (c.has("quest_active") or c.has("quest_done") or c.has("not_quest") or c.has("quest_stage") or c.has("has_item") or c.has("silver") or c.has("rep")):
			errors.append("%s：条件缺内容" % where)


static func _validate_effects(effects: Array, where: String, registry: Dictionary, errors: Array) -> void:
	var qd := GameState.quest_data()
	for e in effects:
		for key in e:
			if not key in EFFECT_KEYS:
				errors.append("%s：效果里不认识的键 %s" % [where, key])
		if e.has("set") and not registry.has(str(e.set)):
			errors.append("%s：旗标 %s 没有登记在 data/flags.json" % [where, e.set])
		for qk in ["quest", "quest_done"]:
			if e.has(qk) and not qd.quests.has(str(e[qk])):
				errors.append("%s：任务 %s 不在 data/quests.json 里" % [where, e[qk]])
		if e.has("stage") and qd.quests.has(str(e.get("quest", ""))) and not qd.quests[str(e.quest)].stages.has(str(e.stage)):
			errors.append("%s：任务 %s 没有阶段 %s" % [where, e.quest, e.stage])
		if e.has("clue") and not qd.clues.has(str(e.clue)):
			errors.append("%s：线索 %s 不在 data/quests.json 里" % [where, e.clue])
		for ik in ["take_item", "give_item"]:
			if e.has(ik) and GameState.item(str(e[ik])).is_empty():
				errors.append("%s：物品 %s 不在 data/items.json 里" % [where, e[ik]])
		if e.has("rep") and (not GameState.progression().get("factions", {}).has(str(e.rep)) or int(e.get("delta", 0)) == 0):
			errors.append("%s：声望效果的势力或变化不对" % where)
		if not (e.has("set") or e.has("quest") or e.has("quest_done") or e.has("clue") or e.has("take_item") or e.has("give_item") or e.has("pay") or e.has("rep")):
			errors.append("%s：效果缺内容" % where)


## 条件是否全部满足
static func conds_ok(conds: Array) -> bool:
	for c in conds:
		if c.has("quest_active"):
			if not GameState.quest_active(str(c.quest_active)):
				return false
		elif c.has("quest_done"):
			if not GameState.quest_done(str(c.quest_done)):
				return false
		elif c.has("not_quest"):
			if GameState.quests.has(str(c.not_quest)):
				return false
		elif c.has("quest_stage"):
			if not GameState.quest_active(str(c.quest_stage)) or GameState.quest_stage(str(c.quest_stage)) != str(c.get("eq", "")):
				return false
		elif c.has("has_item"):
			if not GameState.has_item(str(c.has_item)):
				return false
		elif c.has("silver"):
			if GameState.silver < int(c.silver):
				return false
		elif c.has("rep"):
			if GameState.get_rep(str(c.rep)) < int(c.get("at_least", 0)):
				return false
		elif c.has("not_flag"):
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
		if e.has("set"):
			GameState.set_flag(str(e.set), e.get("value", true))
		if e.has("quest"):
			if e.has("stage"):
				GameState.set_stage(str(e.quest), str(e.stage))
			else:
				GameState.start_quest(str(e.quest))
		if e.has("quest_done"):
			GameState.complete_quest(str(e.quest_done))
		if e.has("clue"):
			GameState.add_clue(str(e.clue))
		if e.has("take_item"):
			GameState.take_item(str(e.take_item))
		if e.has("give_item"):
			GameState.add_item(str(e.give_item))
		if e.has("pay"):
			GameState.add_silver(-int(e.pay))
		if e.has("rep"):
			GameState.change_rep(str(e.rep), int(e.get("delta", 0)))


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
