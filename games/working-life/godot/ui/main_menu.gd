class_name MainMenu
extends Control
## 主菜单：继续游戏、新游戏、读取存档、设置、制作人员、退出。背景是缓慢环绕的霓虹城市。

signal action(id: String)

var _continue: Button
var _sub: Label
var _t := 0.0
var _title: Label


func _ready() -> void:
	UIKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var grad := ColorRect.new()
	grad.color = Color(0.02, 0.0, 0.05, 0.35)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.full_rect(grad)
	add_child(grad)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	scroll.offset_left = 56
	scroll.offset_right = 560
	scroll.offset_top = 28
	scroll.offset_bottom = -60
	add_child(scroll)
	var left := UIKit.vbox(8)
	left.custom_minimum_size = Vector2(420, 0)
	scroll.add_child(left)
	_title = UIKit.hud_label("打工", 96, UIKit.MAGENTA)
	_title.add_theme_constant_override("outline_size", 14)
	_title.add_theme_color_override("font_outline_color", Color(0.1, 0.0, 0.15, 0.9))
	left.add_child(_title)
	var en := UIKit.hud_label("H U S T L E   C I T Y", 26, UIKit.CYAN)
	left.add_child(en)
	left.add_child(UIKit.hud_label("霓虹城市里，一个普通人的奋斗 · v%s" % String(ProjectSettings.get_setting("application/config/version", "1.0")), 17, UIKit.DIM))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 14)
	left.add_child(sp)
	_continue = _btn(left, "继续游戏", "continue")
	_sub = UIKit.hud_label("", 14, UIKit.DIM)
	left.add_child(_sub)
	_btn(left, "新游戏", "new")
	_btn(left, "读取存档", "load")
	_btn(left, "设置", "settings")
	_btn(left, "制作人员", "credits")
	_btn(left, "退出" if not OS.has_feature("web") else "返回游戏中心", "quit")
	var hint := UIKit.hud_label("WASD 移动 · Shift 跑 · 空格跳 · 鼠标看 · E 交互 · F 使用 · 左键执行 · Tab 手机 · M 地图 · I 背包 · J 任务 · C 人物 · Esc 菜单", 14, UIKit.DIM)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_left = 56
	hint.offset_right = -24
	hint.offset_top = -50
	hint.offset_bottom = -8
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	refresh()


func _btn(parent: Control, text: String, id: String) -> Button:
	var b := UIKit.button(text, func(): action.emit(id))
	b.custom_minimum_size = Vector2(300, 44)
	b.add_theme_font_size_override("font_size", 21)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(b)
	return b


func refresh() -> void:
	var slot := SaveManager.latest_slot()
	_continue.disabled = slot == 0
	_sub.text = ("　存档 %d：%s" % [slot, String(SaveManager.read(slot).get("summary", ""))]) if slot > 0 else "　还没有存档"
	if visible and is_inside_tree() and slot > 0:
		_continue.grab_focus()


func _process(delta: float) -> void:
	_t += delta
	if _title != null:
		var flick := 1.0 if fmod(_t, 5.0) > 0.12 else 0.4
		_title.modulate = Color(1, 1, 1, flick)
