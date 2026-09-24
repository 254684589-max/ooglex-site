class_name InputSetup
extends RefCounted
## 在代码里注册全部输入动作。如果在编辑器「项目设置 → 输入映射」里已经定义了同名动作，这里不会覆盖。

const KEY_ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"interact": [KEY_E],
	"use": [KEY_F],
	"phone": [KEY_TAB],
	"map": [KEY_M],
	"inventory": [KEY_I],
	"quests": [KEY_J],
	"character": [KEY_C],
	"pause": [KEY_ESCAPE],
	"time_speed": [KEY_T],
	"debug": [KEY_F1],
}

const MOUSE_ACTIONS := {
	"action": MOUSE_BUTTON_LEFT,
}


static func register() -> void:
	for action in KEY_ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.5)
		for keycode in KEY_ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
	for action in MOUSE_ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.5)
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_ACTIONS[action]
		InputMap.action_add_event(action, mb)
