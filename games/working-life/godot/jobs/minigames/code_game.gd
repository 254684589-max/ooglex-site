class_name CodeGame
extends MinigameBase
## 程序员：每轮给一段有 Bug 的代码和需求说明，点出有问题的那一行。共 6 轮，越快得分越高。

const SNIPPETS := [
	{"desc": "计算列表 nums 里所有数字的和", "lines": ["func total(nums):", "    var s = 0", "    for i in range(1, len(nums)):", "        s += nums[i]", "    return s"], "bug": 2, "why": "range 应该从 0 开始，否则漏掉第一个数"},
	{"desc": "判断用户是否成年（18 岁及以上）", "lines": ["func is_adult(age):", "    if age > 18:", "        return true", "    return false"], "bug": 1, "why": "应该是 age >= 18"},
	{"desc": "返回两个数中较大的一个", "lines": ["func max2(a, b):", "    if a > b:", "        return b", "    return b"], "bug": 2, "why": "a 更大时应该返回 a"},
	{"desc": "统计字符串里字母 e 的个数", "lines": ["func count_e(text):", "    var n = 0", "    for ch in text:", "        if ch == \"e\":", "            n = 1", "    return n"], "bug": 4, "why": "应该是 n += 1"},
	{"desc": "购物车打 8 折后的总价", "lines": ["func discount(price):", "    var rate = 0.8", "    var result = price + rate", "    return result"], "bug": 2, "why": "应该是 price * rate"},
	{"desc": "找到列表里第一个负数的位置，没有返回 -1", "lines": ["func first_neg(nums):", "    for i in range(len(nums)):", "        if nums[i] < 0:", "            return i", "        return -1", "    return -1"], "bug": 4, "why": "循环里的 return -1 让它只检查了第一个数"},
	{"desc": "把温度从摄氏度转成华氏度", "lines": ["func to_f(c):", "    return c * 9 / 5 - 32"], "bug": 1, "why": "应该是 + 32"},
	{"desc": "倒计时：打印 10 到 1", "lines": ["func countdown():", "    var n = 10", "    while n > 0:", "        print(n)", "    return"], "bug": 3, "why": "循环里没有 n -= 1，会死循环"},
	{"desc": "用户登录：密码正确才返回 true", "lines": ["func login(pw, saved):", "    if pw = saved:", "        return true", "    return false"], "bug": 1, "why": "比较应该用 ==，= 是赋值"},
	{"desc": "计算平均分（列表可能为空）", "lines": ["func avg(scores):", "    var s = sum(scores)", "    return s / len(scores)"], "bug": 2, "why": "列表为空时会除以 0，需要先判断"},
	{"desc": "交换数组第 i 和第 j 个元素", "lines": ["func swap(arr, i, j):", "    arr[i] = arr[j]", "    arr[j] = arr[i]", "    return arr"], "bug": 1, "why": "需要临时变量保存 arr[i]，否则两个都变成 arr[j]"},
	{"desc": "判断 n 是不是偶数", "lines": ["func is_even(n):", "    return n % 2 == 1"], "bug": 1, "why": "偶数是 n % 2 == 0"},
	{"desc": "给 VIP 用户（等级 3 以上）发优惠券", "lines": ["func send_coupon(users):", "    for u in users:", "        if u.level < 3:", "            give_coupon(u)"], "bug": 2, "why": "条件反了，应该是 u.level >= 3"},
	{"desc": "读取配置里的端口号，默认 8080", "lines": ["func port(cfg):", "    if cfg.has(\"port\"):", "        return cfg[\"prot\"]", "    return 8080"], "bug": 2, "why": "拼写错误：prot 应为 port"},
]

var rounds := 6
var round_i := 0
var correct := 0
var time_bonus := 0.0
var _round_t := 0.0
var _order: Array = []


func _configure() -> void:
	title = "开发任务 · 星河科技"
	instructions = "读需求，找出有 Bug 的那一行并点击它。每轮 %d 秒，答得越快奖励越高。" % _round_time()
	duration = 6.0 * _round_time() + 4.0


func _round_time() -> int:
	return maxi(9, 16 - difficulty)


func _setup() -> void:
	_order = range(SNIPPETS.size())
	_order.shuffle()
	_show_round()


func _show_round() -> void:
	clear_content()
	if round_i >= rounds:
		finish()
		return
	_round_t = _round_time()
	var sn: Dictionary = SNIPPETS[_order[round_i % _order.size()]]
	content.add_child(UIKit.label("第 %d / %d 题 · 需求：%s" % [round_i + 1, rounds, sn["desc"]], 17, UIKit.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, true))
	var lines: Array = sn["lines"]
	for i in lines.size():
		var b := UIKit.button("%2d │ %s" % [i + 1, lines[i]], _pick.bind(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", Color(0.75, 1.0, 0.8))
		b.add_theme_font_size_override("font_size", 17)
		content.add_child(b)


func _tick(delta: float) -> void:
	_round_t -= delta
	if _round_t <= 0.0 and round_i < rounds:
		say("超时了", false)
		round_i += 1
		update_score()
		_show_round()


func _number_key(i: int) -> void:
	_pick(i)


func _pick(i: int) -> void:
	if done or round_i >= rounds:
		return
	var sn: Dictionary = SNIPPETS[_order[round_i % _order.size()]]
	if i == int(sn["bug"]):
		correct += 1
		time_bonus += maxf(0.0, _round_t) / _round_time() * 4.0
		say("✓ 找到了：%s" % sn["why"])
	else:
		say("× 不是这一行。答案是第 %d 行：%s" % [int(sn["bug"]) + 1, sn["why"]], false)
	round_i += 1
	update_score()
	_show_round()


func score_text() -> String:
	return "正确 %d / %d" % [correct, rounds]


func final_score() -> float:
	return correct / float(rounds) * 85.0 + time_bonus
