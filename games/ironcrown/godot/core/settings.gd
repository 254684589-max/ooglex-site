extends Node
## 玩家设置（GDD.md 第四节、第十二节）。2.8 起改动后立刻存进浏览器（Saves.save_settings），下次打开页面读回来。

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
var show_perf := false           # 左上角性能浮层（F3 或暂停菜单；网页 ?perf=1 时自动打开）
var quality := ""                # 玩家在菜单里选过的画质档（空 = 按设备自动）
var third_person := false        # 第三人称越肩视角（2.9，D6；V 键 / 菜单 / 触屏「视角」切换）
var loaded := false              # 读到过保存的设置（那就不再按系统「减少动态效果」改镜头摆动）

const SAVED_KEYS := ["fov", "sensitivity", "invert_y", "head_bob", "quality", "third_person"]


func _ready() -> void:
	var d := Saves.load_settings()
	for k in SAVED_KEYS:
		if d.has(k):
			_apply(k, d[k])
	loaded = not d.is_empty()


func to_dict() -> Dictionary:
	var d := {}
	for k in SAVED_KEYS:
		d[k] = get(k)
	return d


func set_value(key: String, value) -> void:
	if not _apply(key, value):
		return
	if key in SAVED_KEYS:
		Saves.save_settings(to_dict())
	changed.emit()


func _apply(key: String, value) -> bool:
	match key:
		"fov":
			fov = clampf(float(value), FOV_MIN, FOV_MAX)
		"sensitivity":
			sensitivity = clampf(float(value), SENS_MIN, SENS_MAX)
		"invert_y":
			invert_y = bool(value)
		"head_bob":
			head_bob = bool(value)
		"show_perf":
			show_perf = bool(value)
		"third_person":
			third_person = bool(value)
		"quality":
			quality = str(value) if str(value) in ["", "low", "medium", "high"] else ""
		_:
			push_warning("未知设置项：" + key)
			return false
	return true
