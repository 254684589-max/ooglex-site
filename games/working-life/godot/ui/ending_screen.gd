class_name EndingScreen
extends Control
## 结局画面：标题、逐段出现的结局文字、这一生的数据总结；可以选择继续无限人生，或回到主菜单。

signal action(id: String)

var ending_id := ""
var _lines: Array = []
var _box: VBoxContainer
var _t := 0.0
var _shown := 0


func setup(id: String) -> void:
	ending_id = id


func _ready() -> void:
	UIKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.0, 0.03, 0.93)
	UIKit.full_rect(bg)
	add_child(bg)
	var e := EndingSystem.data(ending_id)
	var col := Mats.hex(String(e.get("color", "#22e4ff")))
	var scroll := ScrollContainer.new()
	UIKit.full_rect(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := MarginContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("margin_left", 60)
	center.add_theme_constant_override("margin_right", 60)
	center.add_theme_constant_override("margin_top", 50)
	center.add_theme_constant_override("margin_bottom", 40)
	scroll.add_child(center)
	_box = UIKit.vbox(14)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(_box)
	_box.add_child(UIKit.label("结局", 18, UIKit.DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var t := UIKit.hud_label(String(e.get("title", "")), 64, col)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(t)
	_box.add_child(UIKit.label(String(e.get("en", "")), 20, UIKit.DIM, HORIZONTAL_ALIGNMENT_CENTER))
	for p in e.get("text", []):
		var l := UIKit.label(String(p), 22, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)
		l.modulate.a = 0.0
		_box.add_child(l)
		_lines.append(l)
	var stats := UIKit.label(_summary(), 16, UIKit.CYAN, HORIZONTAL_ALIGNMENT_CENTER, true)
	stats.modulate.a = 0.0
	_box.add_child(stats)
	_lines.append(stats)
	var row := UIKit.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.modulate.a = 0.0
	_box.add_child(row)
	_lines.append(row)
	row.add_child(UIKit.button("继续人生（无限模式）", func(): action.emit("continue"), 260))
	row.add_child(UIKit.button("回到主菜单", func(): action.emit("menu"), 200))
	AudioManager.play_music("ending")


func _summary() -> String:
	var friends := NPCManager.count_at_least(50)
	return "在新澜市度过了 %d 天 · 最终职位：%s · 净资产 %s\n完成任务 %d 个 · 朋友 %d 位 · 住处：%s · 升职 %d 次" % [TimeManager.day, JobManager.title(), Fmt.yuan(EconomyManager.networth()), QuestManager.done_count(), friends, HousingManager.home_name(), JobManager.promotions]


func _process(delta: float) -> void:
	_t += delta
	var want := int(_t / 1.6)
	while _shown < mini(want, _lines.size()):
		var n: CanvasItem = _lines[_shown]
		var tw := create_tween()
		tw.tween_property(n, "modulate:a", 1.0, 1.0)
		_shown += 1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# 点击加速显示
		_t = maxf(_t, (_shown + 1) * 1.6)
