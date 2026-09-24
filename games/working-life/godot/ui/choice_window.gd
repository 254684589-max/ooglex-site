class_name ChoiceWindow
extends UIWindow
## 通用选择窗口：一段说明文字 + 一列选项按钮。用于旅馆前台、睡觉、随机事件、确认框、结算等。
## options：[{text, cb: Callable, enabled := true, hint := "", close := true}]


func _init(p_title: String, text: String, options: Array, p_size := Vector2(620, 440)) -> void:
	super(p_title, p_size, true)
	if text != "":
		add_text(text, 18)
	for o in options:
		var b := UIKit.button(String(o.get("text", "")), Callable())
		b.disabled = not bool(o.get("enabled", true))
		b.custom_minimum_size.y = 44
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var cb: Callable = o.get("cb", Callable())
		var close_after := bool(o.get("close", true))
		b.pressed.connect(func():
			if close_after:
				force_close()
			if cb.is_valid():
				cb.call())
		body.add_child(b)
		if String(o.get("hint", "")) != "":
			body.add_child(UIKit.label("　" + String(o["hint"]), 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
