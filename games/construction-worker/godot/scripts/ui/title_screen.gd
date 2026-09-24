class_name TitleScreen
extends Control
## 标题画面：背景是缓缓环绕工地的镜头（由 main.gd 控制），左侧是菜单。

signal action(name: String)

var _continue_btn: Button
var _save_info: Label
var _menu: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	UIKit.full_rect(self)
	# 左侧渐变遮罩
	var shade := TextureRect.new()
	UIKit.full_rect(shade)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := Gradient.new()
	grad.set_color(0, Color(0.03, 0.035, 0.05, 0.92))
	grad.set_color(1, Color(0.03, 0.035, 0.05, 0.0))
	grad.set_offset(0, 0.25)
	grad.set_offset(1, 0.75)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	gt.width = 256
	gt.height = 8
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(shade)
	var margin := MarginContainer.new()
	UIKit.full_rect(margin)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 56 if not GameState.touch_mode else 28)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)
	var col := UIKit.vbox(12)
	margin.add_child(col)
	col.add_child(UIKit.spacer(false, true))
	var tag := UIKit.hud_label("BRICK BY BRICK · V0.1", 18, UIKit.DIM)
	col.add_child(tag)
	var title := UIKit.hud_label("工地搬砖", 76, UIKit.YELLOW)
	title.add_theme_constant_override("outline_size", 14)
	col.add_child(title)
	var stripe := ColorRect.new()
	stripe.custom_minimum_size = Vector2(300, 8)
	stripe.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
void fragment() {
	float s = step(0.5, fract((UV.x * 24.0 + UV.y * 2.0) * 0.5));
	COLOR = mix(vec4(0.08, 0.08, 0.08, 1.0), vec4(1.0, 0.78, 0.1, 1.0), s);
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	stripe.material = sm
	col.add_child(stripe)
	var sub := UIKit.hud_label("从临时工干起：搬砖、挣钱、吃饭、睡觉，\n亲手参与建成这座城市最高的一栋楼。", 20, UIKit.TEXT)
	col.add_child(sub)
	col.add_child(UIKit.spacer(false, false))
	_menu = UIKit.vbox(10)
	_menu.custom_minimum_size.x = 300
	_menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_menu)
	_continue_btn = UIKit.button("继续游戏", func(): action.emit("continue"), 300)
	_menu.add_child(_continue_btn)
	_save_info = UIKit.hud_label("", 15, UIKit.DIM)
	_menu.add_child(_save_info)
	_menu.add_child(UIKit.button("开始新游戏", func(): action.emit("new"), 300))
	_menu.add_child(UIKit.button("操作说明", func(): action.emit("help"), 300))
	col.add_child(UIKit.spacer(false, true))
	var foot := UIKit.hud_label("Godot 4 · 灰盒原型版 · 存档保存在本机浏览器", 14, UIKit.DIM)
	col.add_child(foot)


func refresh() -> void:
	var has := SaveSystem.has_save()
	_continue_btn.disabled = not has
	_continue_btn.visible = true
	_save_info.text = ("存档：" + SaveSystem.describe_save()) if has else "还没有存档"
	if has:
		_continue_btn.grab_focus()
	else:
		(_menu.get_child(2) as Button).grab_focus()
