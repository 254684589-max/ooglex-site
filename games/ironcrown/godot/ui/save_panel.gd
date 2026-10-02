class_name SavePanel
extends Control
## 存档 / 读档（路线图 2.8）：从暂停菜单打开，盖在菜单上面（游戏本来就暂停着）。
## 五行：栏位 1–3（「存到这里」/「读取」）、自动存档与快速存档（只能「读取」）。每行写场景、等级、主线、游戏时间、存档时间；
## 存档坏了写明「已退回上一份」或「损坏，读不了」。正在和敌人打的时候不能存档（按钮旁写原因）。

signal closed

var f: Dictionary
var box: VBoxContainer
var main: Node
var status: Label


func _ready() -> void:
	f = UiKit.frame(self, "存档 / 读档")
	box = f.box
	(f.close as Button).pressed.connect(close)
	get_tree().root.size_changed.connect(_fit)
	hide()


func open() -> void:
	show()
	refresh()
	(f.close as Button).grab_focus()
	print("IC_SAVES open")


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func refresh(message := "") -> void:
	UiKit.clear(box)
	var why: String = main.can_save() if main else ""
	status = UiKit.label(box, message if message != "" else ("× " + why if why != "" else "存在这台设备的浏览器里；清除浏览器数据会把存档一起清掉。"), why != "" and message == "", 14)
	var slots := Saves.list_slots()
	for s in Saves.SLOTS:
		var info: Dictionary = slots[s]
		var text: String = str(Saves.SLOT_NAMES[s]) + "  "
		if info.has("summary"):
			text += "%s\n%s" % [info.summary, _time_text(str(info.saved_at))]
			if str(info.note) != "":
				text += "\n" + str(info.note)
		elif info.has("error"):
			text += "（损坏，读不了：%s）" % info.error
		else:
			text += "（空）"
		UiKit.label(box, text, not info.has("summary"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		if s in Saves.MANUAL:
			var sb := _btn(row, "覆盖" if info.has("summary") else "存到这里", func():
				var ok: bool = main.save_game(s)
				refresh(("✓ 已存到" + Saves.SLOT_NAMES[s]) if ok else ("× " + Saves.last_error if Saves.last_error != "" else "× " + main.can_save())))
			sb.disabled = why != ""
		var lb := _btn(row, "读取", func(): main.load_game.call_deferred(s))     # 读档会重载场景：等按钮的信号发完
		lb.disabled = not info.has("summary")
		box.add_child(row)
		box.add_child(HSeparator.new())
	_fit()


func _btn(row: HBoxContainer, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(96, 36)
	b.pressed.connect(cb)
	row.add_child(b)
	return b


## 存档时间（UTC）→ 本地时间「2026-10-02 21:30」
static func _time_text(iso: String) -> String:
	if iso == "":
		return ""
	var unix := Time.get_unix_time_from_datetime_string(iso.trim_suffix("Z"))
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var local := Time.get_datetime_dict_from_unix_time(int(unix) + bias)
	return "%04d-%02d-%02d %02d:%02d" % [local.year, local.month, local.day, local.hour, local.minute]


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()


func _fit() -> void:
	if not is_inside_tree():
		return
	var w := UiKit.content_width(self, 520.0)
	for c in box.get_children():
		if c is Label:
			c.custom_minimum_size.x = w - 12.0
	UiKit.fit(self, f, 520.0)
	_refit.call_deferred()


func _refit() -> void:
	if is_inside_tree() and visible:
		UiKit.fit(self, f, 520.0)
