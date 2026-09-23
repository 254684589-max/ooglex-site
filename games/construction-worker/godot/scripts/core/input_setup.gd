class_name InputSetup
extends RefCounted
## 在代码里注册全部输入动作，避免在 project.godot 里手写冗长的 InputEvent 序列化。
## 如果在编辑器「项目设置 → 输入映射」里已经定义了同名动作，这里不会覆盖。

const KEY_ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"interact": [KEY_E],
	"pickup": [KEY_F],
	"tool_1": [KEY_1],
	"tool_2": [KEY_2],
	"tool_3": [KEY_3],
	"tool_4": [KEY_4],
	"tool_5": [KEY_5],
	"task_list": [KEY_TAB],
	"site_map": [KEY_M],
	"pause": [KEY_ESCAPE],
}

const MOUSE_ACTIONS := {
	"work": MOUSE_BUTTON_LEFT,
	"aim": MOUSE_BUTTON_RIGHT,
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
