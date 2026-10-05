extends Node
## 输入动作用代码注册（沿用余烬陷落 / 打工的做法，便于阅读和修改）。按键见 GDD.md 第三节。

const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_C, KEY_CTRL],   # 切换蹲下
	"jump": [KEY_SPACE],
	"interact": [KEY_E],          # 交互：对话、开门、拾取（1.3）
	"perf_toggle": [KEY_F3],      # 性能浮层（1.5）
	"quest_log": [KEY_J],         # 任务日志（2.3）
	"inventory": [KEY_I],         # 背包（2.6）
	"character": [KEY_K],         # 角色：属性、技能、声望（2.7）
	"quick_save": [KEY_F8],       # 快速存档（2.8；不用 F5：浏览器里 F5 是刷新页面）
	"quick_load": [KEY_F9],       # 快速读档（2.8）
	"camera_toggle": [KEY_V],     # 第一 / 第三人称切换（2.9）
	"sheathe": [KEY_R],           # 拔剑 / 收剑（2.4）
	"attack_key": [KEY_F],        # 攻击的键盘键（2.4；主要是鼠标左键，在 main 里处理）
	"block_key": [KEY_Q],         # 格挡的键盘键（2.5；主要是鼠标右键按住）
	"order_follow": [KEY_1],      # 小队命令（B.2，军阵战斗里）：跟随我
	"order_hold": [KEY_2],        # 原地坚守
	"order_charge": [KEY_3],      # 冲锋（对话面板打开时数字键选选项，游戏暂停，不会误下命令）
	"pause": [KEY_ESCAPE],
}


func _ready() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
