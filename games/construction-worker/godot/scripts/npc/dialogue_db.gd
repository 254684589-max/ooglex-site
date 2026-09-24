class_name DialogueDB
extends RefCounted
## 对话数据与对话动作。
##
## 对话节点格式：
##   {"speaker": "工头老王", "text": "……", "options": [
##       {"text": "干！", "next": "accepted", "action": "accept_first_job"},
##       {"text": "没事了", "next": ""}   # next 为空 = 结束对话
##   ]}
## 动作（action）在 run_action() 里执行，可以返回一个新的 next 覆盖默认跳转。

const NAMES := {
	"wang": "工头老王",
	"liu": "工友大刘",
	"chen": "食堂老板老陈",
}


static func has_dialogue(npc_id: String) -> bool:
	return NAMES.has(npc_id)


static func start_node(npc_id: String) -> String:
	match npc_id:
		"wang":
			return "first" if not GameState.has_flag("met_wang") else "hub"
		"liu":
			return "first" if not GameState.has_flag("met_liu") else "hub"
		"chen":
			return "hub"
	return "hub"


static func node_for(npc_id: String, node_id: String) -> Dictionary:
	var n: Dictionary = {}
	match npc_id:
		"wang":
			n = _wang(node_id)
		"liu":
			n = _liu(node_id)
		"chen":
			n = _chen(node_id)
	if n.is_empty():
		return {}
	n["speaker"] = NAMES.get(npc_id, npc_id)
	return n


static func _opt(text: String, next := "", action := "") -> Dictionary:
	return {"text": text, "next": next, "action": action}


# ---------------------------------------------------------------- 工头老王
static func _wang(node_id: String) -> Dictionary:
	match node_id:
		"first":
			return {"text": "你就是老乡介绍来的？看着挺结实。我是这儿的工头，姓王，大家都叫我老王。",
				"options": [_opt("王工好！我是来找活干的。", "offer")]}
		"offer":
			return {"text": "咱这儿不讲虚的：一天 280，管一顿饭，干不干？",
				"options": [_opt("干！", "accepted", "accept_first_job"), _opt("我再想想……", "think")]}
		"think":
			return {"text": "想好了再来找我。天一黑，活可就没了。",
				"options": [_opt("好的，我一会儿再来。")]}
		"accepted":
			var t := TaskSystem.get_active()
			if t == null:
				return {"text": "爽快！安全帽先拿着，进场必须戴。今天天色晚了，明天早上六点来找我派活。",
					"options": [_opt("好，明天一早就来！")]}
			return {"text": "爽快！安全帽拿着，进场必须戴。饭票中午去食堂换盒饭。\n" + t.accept_line,
				"options": [_opt("明白，这就去！")]}
		"hub":
			return _wang_hub()
		"task_ok":
			var active := TaskSystem.get_active()
			return {"text": active.accept_line if active != null else "去吧。",
				"options": [_opt("好嘞！")]}
		"abandon_confirm":
			return {"text": "不想干了？那这活我先找别人，已经搬的就当帮忙了，不算钱。",
				"options": [_opt("算了，我接着干。", "hub"), _opt("嗯，我不干了。", "", "abandon_task")]}
		"ask":
			return {"text": "有啥想问的？",
				"options": [
					_opt("怎么才能多挣钱？", "ask_money"),
					_opt("以后能不能不光卖力气？", "ask_future"),
					_opt("这楼盖好了有多高？", "ask_tower"),
					_opt("没事了，我去干活。", ""),
				]}
		"ask_money":
			return {"text": "力气是练出来的。搬得多了，一次就能多拿几块，干得快，一天能多接几份活。水泥、钢筋的活钱也不少，就是累。",
				"options": [_opt("还有别的想问。", "ask"), _opt("明白了。")]}
		"ask_future":
			return {"text": "当然。先把砖搬明白，再跟师傅学砌墙、抹灰、绑钢筋，手艺在身上，工钱就不止这个数。干得好，以后班组交给你带也不是不行。",
				"options": [_opt("还有别的想问。", "ask"), _opt("我记住了！")]}
		"ask_tower":
			return {"text": "效果图你在大门口看见没？滨江中心，建成了三百多米，全城第一高。你今天搬的每一块砖，将来都在这楼里头。",
				"options": [_opt("还有别的想问。", "ask"), _opt("那我可得好好干。")]}
	return {}


static func _wang_hub() -> Dictionary:
	var options: Array = []
	var text := ""
	var active := TaskSystem.get_active()
	if active != null:
		var obj := TaskSystem.next_open_objective()
		var remain := TaskSystem.wants("deliver", obj) if not obj.is_empty() else 0
		text = "「%s」干得咋样了？还差 %d%s。" % [active.title, remain, ItemDB.unit(String(obj.get("item", "")))]
		options.append(_opt("这就去干。"))
		options.append(_opt("这活我不想干了……", "abandon_confirm"))
	elif not TimeSystem.is_work_hours():
		text = "都下班了！去食堂吃口热乎的，回宿舍睡觉，明天早上六点再来找我。"
	else:
		var avail := TaskSystem.available_tasks()
		if avail.is_empty():
			text = "今天没啥活了，你歇着吧。明天一早再来。"
		else:
			text = "来得正好，手上有活。想干哪个？" if TaskSystem.tasks_done_today() == 0 else "还有力气？那再给你派点活。"
			for t in avail:
				options.append(_opt("接活：%s（¥%d）" % [t.title, t.reward], "task_ok", "accept:" + t.id))
	options.append(_opt("想问点事……", "ask"))
	options.append(_opt("没事了。"))
	return {"text": text, "options": options}


# ---------------------------------------------------------------- 工友大刘
static func _liu(node_id: String) -> Dictionary:
	match node_id:
		"first":
			return {"text": "新来的？我叫大刘，搬砖搬了八年了。有啥不懂的尽管问！",
				"options": [_opt("刘哥好，想请教几件事。", "hub", "met_liu"), _opt("回头再聊！", "", "met_liu")]}
		"hub":
			var carrying := ""
			if GameState.player != null:
				carrying = GameState.player.carried_item()
			var text := "别光跟我唠，东西还在你手上呢！有啥快问。" if carrying != "" else "说吧，想问啥？"
			return {"text": text,
				"options": [
					_opt("砖怎么搬？", "how_carry"),
					_opt("累了怎么办？", "how_rest"),
					_opt("饿了渴了呢？", "how_eat"),
					_opt("晚上干啥？", "how_sleep"),
					_opt("没事了，干活去。"),
				]}
		"how_carry":
			return {"text": "走到砖堆跟前按 F 拿一块，再按 F 再拿一块。刚来的一次只能拿一块，练熟了能拿六块。搬到亮着黄框的卸货区，走进框里按 F 或者点鼠标左键放下，放在框外面可不算数。",
				"options": [_opt("还有呢？", "hub"), _opt("懂了！")]}
		"how_rest":
			return {"text": "看左下角的体力条。跑步掉得快，扛得越重掉得越快。体力太低走不动道，眼前还发晃。站着歇会儿就能缓过来，吃口饭也能回点劲，晚上睡一觉就满了。",
				"options": [_opt("还有呢？", "hub"), _opt("懂了！")]}
		"how_eat":
			return {"text": "食堂在东南角，找老陈打饭，盒饭十五块，老王给的饭票能换一份。小卖部就在食堂旁边。施工楼南边有个凉茶桶，免费喝，就是喝完得等一会儿才续上。",
				"options": [_opt("还有呢？", "hub"), _opt("懂了！")]}
		"how_sleep":
			return {"text": "天黑就收工。宿舍在西南角，进门那间最里头靠墙那张是你的铺。睡一觉就是第二天。可别熬到后半夜，会累趴下的。",
				"options": [_opt("还有呢？", "hub"), _opt("懂了！")]}
	return {}


# ---------------------------------------------------------------- 食堂老陈
static func _chen(node_id: String) -> Dictionary:
	match node_id:
		"hub":
			var text := "来啦！今天有红烧肉盒饭，香着呢。吃点啥？"
			if EconomySystem.meal_tickets > 0:
				text = "哟，拿着饭票呢？盒饭给你打满满一盒！"
			return {"text": text,
				"options": [_opt("看看菜单。", "", "open_shop:canteen"), _opt("先不吃了。")]}
	return {}


# ---------------------------------------------------------------- 动作
## 执行对话动作。返回值非空时代替选项里写的 next。
static func run_action(npc_id: String, action: String) -> String:
	if action == "":
		return ""
	if action.begins_with("accept:"):
		var id := action.substr(7)
		if TaskSystem.accept(id):
			var t := TaskSystem.get_task(id)
			Events.say("接到任务：%s" % t.title, "good")
			return ""
		return "hub"
	if action.begins_with("open_shop:"):
		Events.shop_requested.emit(action.substr(10))
		return ""
	match action:
		"accept_first_job":
			GameState.set_flag("met_wang")
			PlayerStats.equip("hardhat")
			Events.say("获得：黄色安全帽", "good")
			if TaskSystem.accept("haul_bricks"):
				Events.say("接到任务：搬砖（¥280）", "good")
		"abandon_task":
			TaskSystem.abandon()
			Events.say("放弃了当前任务", "warn")
		"met_liu":
			GameState.set_flag("met_liu")
	return ""
