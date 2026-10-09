class_name MapTabs
extends HBoxContainer
## 地图册的页签条（路线图 3.11）：「本地」「一带」「北境西部」。区域地图（ui/map_panel.gd）和旅行地图（ui/travel_map.gd）各放一条，样子一样；
## 点别的页签发 view_requested，由 main 换面板（main._switch_map）。当前页签写成「◆ 本地」、按下状态——不设成灰的（灰的看起来像不能用，焦点也会跳过它）。
## 只有一页时整条藏起来（测试场）。

signal view_requested(view: String)

const ORDER := ["local", "region", "travel"]
const LABELS := {"local": "本地", "region": "一带", "travel": "北境西部"}
const MARK := "◆ "
const HEIGHT := 44.0

var btns := {}                 # 页 → 按钮
var current := ""
var group := ButtonGroup.new()


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 8)
	for v in ORDER:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(88, HEIGHT)
		b.focus_mode = Control.FOCUS_ALL
		b.add_theme_stylebox_override("focus", UiKit.focus_style())
		b.pressed.connect(_on_pressed.bind(v))
		add_child(b)
		btns[v] = b


## 显示哪几页、当前是哪一页
func setup(views: Array, active: String) -> void:
	current = active
	for v in ORDER:
		var b: Button = btns[v]
		b.visible = v in views
		b.set_pressed_no_signal(v == active)
		b.text = (MARK if v == active else "") + str(LABELS[v])
	visible = views.size() > 1


func active_button() -> Button:
	return btns.get(current)


func _on_pressed(v: String) -> void:
	if v == current:
		btns[v].set_pressed_no_signal(true)        # 再点一下当前页：保持按下，什么都不做
		return
	view_requested.emit(v)
