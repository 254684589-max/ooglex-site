class_name SaveSlotsWindow
extends UIWindow
## 存档槽：mode = "save" 保存到槽位 / "load" 读取 / "new" 选择新游戏使用的槽位。

signal slot_chosen(slot: int)

var mode := "load"


func _init(p_mode: String) -> void:
	mode = p_mode
	super({"save": "保存游戏", "load": "读取存档", "new": "新游戏 · 选择存档位"}.get(p_mode, "存档"), Vector2(640, 480))
	window_id = "slots"


func _ready() -> void:
	super()
	_build()


func _build() -> void:
	clear_body()
	if mode == "new":
		add_text("选择一个存档位。已有存档会被覆盖。", 15, UIKit.DIM)
	for i in range(1, SaveManager.SLOTS + 1):
		var card := UIKit.card(UIKit.CYAN if i != SaveManager.current_slot else UIKit.MAGENTA)
		body.add_child(card)
		var h := UIKit.hbox(10)
		card.add_child(h)
		var l := UIKit.label("存档 %d%s\n%s" % [i, "（当前）" if i == SaveManager.current_slot and GameManager.playing else "", SaveManager.slot_text(i)], 16, UIKit.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var has := SaveManager.has_save(i)
		var label: String = {"save": "保存到这里", "load": "读取", "new": "从这里开始"}.get(mode, "选择")
		var b := UIKit.small_button(label, func():
			force_close()
			slot_chosen.emit(i))
		b.disabled = mode == "load" and not has
		h.add_child(b)
