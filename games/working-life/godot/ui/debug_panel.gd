class_name DebugPanel
extends UIWindow
## 开发者面板（F1）：加钱、改时间、传送、调属性、完成当前任务、改技能等。
## 只在调试构建或网页地址带 ?dev=1 时可用；正式发布版默认关闭。


func _init() -> void:
	super("开发者面板（F1）", Vector2(820, 640))
	window_id = "debug"


func _ready() -> void:
	super()
	_build()


func _row(title: String) -> HFlowContainer:
	body.add_child(UIKit.label(title, 16, UIKit.CYAN))
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	body.add_child(f)
	return f


func _b(parent: Control, text: String, cb: Callable) -> void:
	parent.add_child(UIKit.small_button(text, func():
		cb.call()
		Events.say("调试：" + text, "info")))


func _build() -> void:
	clear_body()
	add_text("当前：第 %d 天 %s · 现金 %s · 存款 %s · 章节 %d · 任务 %s" % [TimeManager.day, TimeManager.clock_text(), Fmt.yuan(EconomyManager.cash), Fmt.yuan(EconomyManager.bank), GameManager.chapter, QuestManager.tracked_id()], 14, UIKit.DIM)
	var money := _row("金钱")
	_b(money, "+¥1,000", func(): EconomyManager.earn(1000, "其他", "调试"))
	_b(money, "+¥100,000", func(): EconomyManager.earn(100000, "其他", "调试"))
	_b(money, "+¥5,000,000（存款）", func(): EconomyManager.earn(5000000, "其他", "调试", true))
	var t := _row("时间与天气")
	_b(t, "+1 小时", func(): TimeManager.advance(60))
	_b(t, "+6 小时", func(): TimeManager.advance(360))
	_b(t, "跳到明早 08:00", func(): TimeManager.advance(TimeManager.minutes_until(8.0), "sleep"))
	_b(t, "晴", func(): WeatherManager.set_weather("sunny"))
	_b(t, "阴", func(): WeatherManager.set_weather("cloudy"))
	_b(t, "雨", func(): WeatherManager.set_weather("rain"))
	var tp := _row("传送")
	for id in DataDB.ids("locations"):
		_b(tp, DataDB.location_name(id), func():
			var p := GameManager.location_front(id)
			if p != Vector3.INF and GameManager.player != null:
				GameManager.player.teleport(p, 0.0)
				force_close())
	var st := _row("属性")
	_b(st, "全部回满", func():
		for s in ["energy", "hunger", "mood", "health"]:
			PlayerManager.set_stat(s, 100)
		PlayerManager.set_stat("stress", 0))
	_b(st, "体力清零", func(): PlayerManager.set_stat("energy", 1))
	_b(st, "压力 90", func(): PlayerManager.set_stat("stress", 90))
	_b(st, "声望 +20", func(): PlayerManager.change_reputation(20))
	var sk := _row("技能")
	for id in SkillManager.ids():
		_b(sk, "%s +1 级" % DataDB.skill_name(id), func(): SkillManager.set_level(id, SkillManager.level(id) + 1))
	_b(sk, "全部 Lv.10", func():
		for id2 in SkillManager.ids():
			SkillManager.set_level(id2, 10))
	var q := _row("任务 / 剧情")
	_b(q, "完成当前追踪任务", func(): QuestManager.debug_complete_tracked())
	_b(q, "所有 NPC 关系 +20", func():
		for id in DataDB.ids("npcs"):
			NPCManager.change_relation(id, 20))
	_b(q, "解锁全部交通", func(): GameManager.set_flag("debug_all_transport"))
	_b(q, "触发随机事件（上午）", func(): EventManager.roll("morning", true))
	_b(q, "触发随机事件（中午）", func(): EventManager.roll("day", true))
	var j := _row("职业")
	_b(j, "当前职业绩效 100", func(): JobManager.change_perf(100))
	_b(j, "当前职业出勤 +10 班", func():
		if JobManager.has_job():
			JobManager.current["shifts_level"] = int(JobManager.current["shifts_level"]) + 10
			JobManager.current["shifts_total"] = int(JobManager.current["shifts_total"]) + 10)
	for id in DataDB.ids("jobs"):
		_b(j, "入职：%s" % String(DataDB.job(id).get("name", "")), func(): JobManager.hire(id, 0))
	var bz := _row("创业")
	_b(bz, "公司账户 +¥1,000,000", func(): BusinessManager.adjust_cash(1000000))
	_b(bz, "公司模拟 10 天", func():
		for i in 10:
			BusinessManager.simulate_day())
