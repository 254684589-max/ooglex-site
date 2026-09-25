class_name PhoneWindow
extends UIWindow
## 手机（Tab）：游戏里主要的管理界面。主屏是 APP 图标，点进去是各个 APP。
## APP：消息、招聘、零工、银行、地图、任务、人物、住房、技能、投资、创业、联系人、约会、打车、房产、汽车、设置。

const APPS := [
	["messages", "消息", "信"], ["jobs", "招聘", "职"], ["gig", "零工", "单"], ["bank", "银行", "¥"], ["map", "地图", "◎"],
	["quests", "任务", "◆"], ["profile", "人物", "我"], ["housing", "住房", "家"], ["skills", "技能", "技"],
	["invest", "投资", "↗"], ["business", "创业", "企"], ["contacts", "联系人", "友"], ["romance", "约会", "爱"], ["transit", "打车", "的"],
	["property", "房产", "楼"], ["cars", "汽车", "车"], ["settings", "设置", "设"],
]

var app := ""
var ui: Node


func _init(p_app := "") -> void:
	app = p_app
	super("手机", Vector2(640, 700))
	window_id = "phone"


func _ready() -> void:
	super()
	open_app(app)
	Events.money_changed.connect(_soft_refresh)


func _soft_refresh() -> void:
	if app in ["bank", "invest", "business", "cars", "property", "gig"] and is_inside_tree():
		call_deferred("open_app", app)


func open_app(id: String) -> void:
	app = id
	clear_body()
	clear_footer()
	if id == "":
		_home()
		return
	var name := id
	for a in APPS:
		if a[0] == id:
			name = a[1]
	set_title("手机 · " + name)
	add_button("← 返回主屏", func(): open_app(""), true)
	var refresh := func(): open_app(app)
	match id:
		"messages":
			MessagesApp.build(body)
			GameManager.set_value("unread_messages", 0)
		"jobs":
			JobsApp.build(body, refresh)
		"bank":
			BankApp.build(body, refresh)
		"map":
			force_close()
			Events.panel_requested.emit("map", {})
		"quests":
			QuestsView.build(body, refresh)
		"profile":
			ProfileView.build(body, refresh)
		"housing":
			HousingApp.build(body, refresh)
		"skills":
			SkillsApp.build(body)
		"invest":
			InvestApp.build(body, refresh)
		"business":
			BusinessApp.build(body, refresh)
		"contacts":
			ContactsApp.build(body)
		"cars":
			CarsApp.build(body, refresh)
		"property":
			PropertyApp.build(body, refresh)
		"romance":
			RomanceApp.build(body, force_close)
		"gig":
			GigApp.build(body, refresh, force_close)
		"transit":
			force_close()
			Events.panel_requested.emit("travel", {"mode": "taxi"})
		"settings":
			force_close()
			Events.panel_requested.emit("settings", {})


func _home() -> void:
	set_title("手机")
	var top := UIKit.hbox(8)
	body.add_child(top)
	top.add_child(UIKit.label("%s %s  %s" % [TimeManager.date_text(), TimeManager.weekday_name(), TimeManager.clock_text()], 16, UIKit.DIM))
	top.add_child(UIKit.spacer())
	top.add_child(UIKit.label("%s %s" % [WeatherManager.icon(), WeatherManager.display_name()], 16, UIKit.DIM))
	body.add_child(UIKit.label("现金 %s · 银行卡 %s" % [Fmt.yuan(EconomyManager.cash), Fmt.yuan(EconomyManager.bank)], 18, UIKit.YELLOW))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(g)
	var unread := int(GameManager.get_value("unread_messages", 0))
	for a in APPS:
		var label: String = "%s\n%s" % [a[2], a[1]]
		if a[0] == "messages" and unread > 0:
			label = "%s %d\n%s" % [a[2], unread, a[1]]
		if a[0] == "jobs" and not JobManager.invites.is_empty():
			label = "%s ●\n%s" % [a[2], a[1]]
		var b := UIKit.button(label, open_app.bind(String(a[0])))
		b.custom_minimum_size = Vector2(110, 78)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(b)
	body.add_child(UIKit.label("提示：M 地图 · J 任务 · I 背包 · C 人物 · T 切换时间倍速 · Esc 菜单", 13, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
