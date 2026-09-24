class_name AnalysisGame
extends MinigameBase
## 金融分析：看走势图与均线判断下一阶段趋势，或在几个投资方案里选风险收益比最好的一个。共 5 轮。

var rounds := 5
var round_i := 0
var correct := 0
var _answer := 0
var _explain := ""


func _configure() -> void:
	title = "投研工作台 · 澜海资本"
	instructions = "根据图表与数据作答（键盘 1~3）。趋势题：看价格与 20 日均线的位置和方向；方案题：比较「预期收益 ÷ 波动」。"
	duration = 75.0


func _setup() -> void:
	_show_round()


func _show_round() -> void:
	clear_content()
	if round_i >= rounds:
		finish()
		return
	if round_i % 2 == 0:
		_trend_round()
	else:
		_portfolio_round()


func _trend_round() -> void:
	var trend: int = [-1, 0, 1][rng.randi() % 3]
	var vals: Array = []
	var p := 100.0
	for i in 60:
		var drift := float(trend) * 0.006 if i > 25 else -float(trend) * 0.002
		p *= 1.0 + drift + rng.randf_range(-0.012, 0.012) * (1.0 + difficulty * 0.15)
		vals.append(p)
	var ma := ChartView.moving_average(vals, 20)
	var chart := ChartView.new()
	chart.custom_minimum_size = Vector2(300, 190)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.set_series([{"values": vals, "color": UIKit.CYAN, "width": 2.0}, {"values": ma, "color": UIKit.YELLOW, "width": 1.5}], "点", "过去 60 个交易日 · 青线 = 价格，黄线 = 20 日均线")
	content.add_child(UIKit.label("第 %d / %d 题：这只股票接下来一周最可能怎么走？" % [round_i + 1, rounds], 17, UIKit.YELLOW))
	content.add_child(chart)
	# 正确答案由生成时的趋势决定；平稳趋势对应「震荡」
	_answer = [2, 1, 0][trend + 1]
	_explain = ["价格在均线上方且均线向上：上涨趋势", "价格围绕均线来回：震荡", "价格跌破均线且均线向下：下跌趋势"][_answer]
	var h := UIKit.hbox(10)
	content.add_child(h)
	for i in 3:
		h.add_child(big_button(["1. 上涨 ↑", "2. 震荡 ↔", "3. 下跌 ↓"][i], _pick.bind(i)))


func _portfolio_round() -> void:
	content.add_child(UIKit.label("第 %d / %d 题：客户想要风险收益比最好的方案，选哪一个？" % [round_i + 1, rounds], 17, UIKit.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, true))
	var best := -1
	var best_ratio := -INF
	var opts: Array = []
	for i in 3:
		var ret := rng.randf_range(3.0, 14.0)
		var vol := rng.randf_range(2.0, 20.0)
		opts.append([ret, vol])
		if ret / vol > best_ratio:
			best_ratio = ret / vol
			best = i
	_answer = best
	_explain = "方案 %d 的「收益 ÷ 波动」最高（%.2f）" % [best + 1, best_ratio]
	var h := UIKit.hbox(10)
	content.add_child(h)
	for i in 3:
		var o: Array = opts[i]
		h.add_child(big_button("%d. 方案%s\n预期年化 %.1f%%\n波动率 %.1f%%" % [i + 1, "ABC"[i], o[0], o[1]], _pick.bind(i)))


func _number_key(i: int) -> void:
	if i < 3:
		_pick(i)


func _pick(i: int) -> void:
	if done or round_i >= rounds:
		return
	if i == _answer:
		correct += 1
		say("✓ 正确：%s" % _explain)
	else:
		say("× 答错了：%s" % _explain, false)
	round_i += 1
	update_score()
	_show_round()


func score_text() -> String:
	return "正确 %d / %d" % [correct, rounds]


func final_score() -> float:
	return correct / float(rounds) * 90.0 + clampf(time_left / duration, 0.0, 1.0) * 10.0
