extends Node
## 玩家设置（GDD.md 第四节、第十二节）。暂时只存在内存里，刷新页面后恢复默认；存到浏览器在 2.7 存档一步做。

signal changed

const FOV_MIN := 60.0
const FOV_MAX := 100.0
const SENS_MIN := 0.3
const SENS_MAX := 3.0
const MOUSE_DEG_PER_PX := 0.12   # 灵敏度倍数 1.0 时，鼠标每移动 1 像素转多少度
const TOUCH_DEG_PER_PX := 0.25   # 触屏拖动每 1 像素转多少度（手指移动距离短，比鼠标大）

var fov := 75.0
var sensitivity := 1.0           # 倍数
var invert_y := false
var head_bob := true             # 系统「减少动态效果」时默认关闭（main.gd 启动时设置）
var reduced_motion := false


func set_value(key: String, value) -> void:
	match key:
		"fov":
			fov = clampf(float(value), FOV_MIN, FOV_MAX)
		"sensitivity":
			sensitivity = clampf(float(value), SENS_MIN, SENS_MAX)
		"invert_y":
			invert_y = bool(value)
		"head_bob":
			head_bob = bool(value)
		_:
			push_warning("未知设置项：" + key)
			return
	changed.emit()
