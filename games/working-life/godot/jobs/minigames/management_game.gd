class_name ManagementGame
extends MinigameBase
## 管理决策：分配任务（技能匹配 + 负荷）、控制预算（在预算内选价值最高的组合）、招聘（选最合适的人）、
## 处理突发事件。共 5 张决策卡。

const INCIDENTS := [
	{"q": "核心客户凌晨投诉系统宕机，要求赔偿。", "opts": ["先恢复服务并致电道歉，再按合同协商补偿", "推给技术部处理", "拒绝赔偿，合同没写"], "a": 0},
	{"q": "两位组长为资源分配吵到你办公室。", "opts": ["各打五十大板", "拉上两人对齐目标，按项目优先级重新分配", "谁声音大听谁的"], "a": 1},
	{"q": "季度目标完不成了，还剩两周。", "opts": ["要求全员通宵", "放弃目标", "聚焦最可能成交的机会，砍掉低价值事项，同步风险"], "a": 2},
	{"q": "明星员工提出离职，理由是晋升太慢。", "opts": ["坦诚沟通职业发展路径，能给的机会立刻兑现", "直接批准", "用高薪强留但不谈原因"], "a": 0},
	{"q": "财务发现一笔报销疑似造假。", "opts": ["当作没看见", "按制度调查核实，结果公开透明处理", "直接开除当事人"], "a": 1},
]
const NAMES := ["小王", "阿美", "老周", "Kevin", "小赵", "莉莉"]
const SKILLS := ["开发", "设计", "销售", "财务"]

var rounds := 5
var round_i := 0
var points := 0.0
var _answer := 0
var _explain := ""
var company_mode := false


func _configure() -> void:
	title = "管理决策 · 云途集团" if not company_mode else "经营决策 · 你的公司"
	instructions = "每张决策卡选一个方案（键盘 1~3）。好的管理者会看技能匹配、工作负荷和性价比。"
	duration = 80.0


func _setup() -> void:
	_show_round()


func _show_round() -> void:
	clear_content()
	if round_i >= rounds:
		finish()
		return
	match round_i % 4:
		0:
			_assign_round()
		1:
			_budget_round()
		2:
			_incident_round()
		3:
			_hire_round()


func _assign_round() -> void:
	var need: String = SKILLS[rng.randi() % SKILLS.size()]
	content.add_child(UIKit.label("任务：客户需求急需一名「%s」负责人。谁来做？" % need, 17, UIKit.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, true))
	var best := -1
	var best_v := -INF
	var h := UIKit.hbox(10)
	content.add_child(h)
	var names := NAMES.duplicate()
	names.shuffle()
	for i in 3:
		var skill := rng.randi_range(2, 9)
		var load := rng.randi_range(30, 110)
		var v := skill * 10.0 - maxf(0.0, load - 80.0) * 3.0
		if v > best_v:
			best_v = v
			best = i
		h.add_child(big_button("%d. %s\n%s能力 %d\n工作负荷 %d%%" % [i + 1, names[i], need, skill, load], _pick.bind(i)))
	_answer = best
	_explain = "负荷不超标（≤80%%）前提下能力最强的是 %d 号" % (best + 1)


func _budget_round() -> void:
	var budget := rng.randi_range(8, 14) * 10
	var projects: Array = []
	for i in 4:
		projects.append([["官网改版", "渠道推广", "系统升级", "员工培训", "客户活动", "数据平台"][rng.randi() % 6], rng.randi_range(3, 8) * 10, rng.randi_range(2, 12) * 10])
	content.add_child(UIKit.label("本月预算 %d 万。以下组合里，哪个在预算内总价值最高？" % budget, 17, UIKit.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, true))
	var combos := [[0, 1], [1, 2], [2, 3], [0, 3], [0, 2], [1, 3]]
	combos.shuffle()
	var shown := combos.slice(0, 3)
	var best := 0
	var best_v := -INF
	for i in 3:
		var c: Array = shown[i]
		var cost: int = int(projects[c[0]][1]) + int(projects[c[1]][1])
		var val: int = int(projects[c[0]][2]) + int(projects[c[1]][2])
		var v := float(val) if cost <= budget else -1000.0 + val
		if v > best_v:
			best_v = v
			best = i
	var h := UIKit.hbox(10)
	content.add_child(h)
	for i in 3:
		var c2: Array = shown[i]
		var a: Array = projects[c2[0]]
		var b2: Array = projects[c2[1]]
		h.add_child(big_button("%d. %s + %s\n成本 %d 万\n价值 %d 万" % [i + 1, a[0], b2[0], int(a[1]) + int(b2[1]), int(a[2]) + int(b2[2])], _pick.bind(i)))
	_answer = best
	_explain = "不超预算的组合里价值最高的是 %d 号" % (best + 1)


func _incident_round() -> void:
	var inc: Dictionary = INCIDENTS[rng.randi() % INCIDENTS.size()]
	content.add_child(UIKit.label("突发：%s" % inc["q"], 17, UIKit.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, true))
	var opts: Array = inc["opts"]
	for i in opts.size():
		var b := big_button("%d. %s" % [i + 1, opts[i]], _pick.bind(i))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(b)
	_answer = int(inc["a"])
	_explain = "先止损、讲事实、对齐目标，是更稳妥的做法"


func _hire_round() -> void:
	content.add_child(UIKit.label("招聘：团队缺一名能长期干下去的骨干。选谁？", 17, UIKit.YELLOW))
	var best := 0
	var best_v := -INF
	var h := UIKit.hbox(10)
	content.add_child(h)
	for i in 3:
		var ability := rng.randi_range(3, 9)
		var fit := rng.randi_range(2, 9)
		var salary := rng.randi_range(8, 25)
		var v := ability * 2.0 + fit * 2.0 - salary * 0.4
		if v > best_v:
			best_v = v
			best = i
		h.add_child(big_button("%d. 候选人%s\n能力 %d · 契合度 %d\n期望月薪 %dk" % [i + 1, "ABC"[i], ability, fit, salary], _pick.bind(i)))
	_answer = best
	_explain = "综合能力、契合度与薪资，%d 号性价比最高" % (best + 1)


func _number_key(i: int) -> void:
	if i < 3:
		_pick(i)


func _pick(i: int) -> void:
	if done or round_i >= rounds:
		return
	if i == _answer:
		points += 1.0
		say("✓ 好决定：%s" % _explain)
	else:
		say("× 不是最优：%s" % _explain, false)
	round_i += 1
	update_score()
	_show_round()


func score_text() -> String:
	return "正确决策 %d / %d" % [int(points), rounds]


func final_score() -> float:
	return points / float(rounds) * 90.0 + clampf(time_left / duration, 0.0, 1.0) * 10.0
