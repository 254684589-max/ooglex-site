extends Node
## 输入动作用代码注册（沿用 working-life 的做法，便于阅读和修改）。
## 键盘移动是可选操作（GDD.md 第三节）：W/A/S/D 与方向键，按屏幕方向移动。

const ACTIONS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"potion_hp": [KEY_Q],        # P3：与 V0.1 相同的按键
	"potion_mp": [KEY_E],
	"char_panel": [KEY_C],
	"inv_panel": [KEY_I],        # P6：背包（V0.1 同键）
	"town_portal": [KEY_T],      # P8：回城卷轴（V0.1 同键）
	"map_toggle": [KEY_TAB],     # P8：自动地图（V0.1 同键）
	"quest_panel": [KEY_J],      # P8：任务日志（V0.1 放在角色面板里，3D 版单独一个面板）
}


func _ready() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
