class_name Interactable
extends StaticBody3D
## 可交互物体的基类（TECH.md 4.2）：门、可拾取物、NPC 都继承它。
## 物理层 3「可交互」（位值 4）让屏幕中心的射线找到它；需要挡路的物体同时在层 1「世界」。
## interact() 返回一个结果字典交给 main 显示：kind（种类）、toast（屏幕上方的提示）、speech（底部字幕）等。

const LAYER_WORLD := 1
const LAYER_INTERACT := 4

var display_name := ""
var verb := "使用"


func _init() -> void:
	collision_layer = LAYER_WORLD | LAYER_INTERACT
	collision_mask = 0


func verb_now() -> String:
	return verb


func prompt() -> String:
	return "%s · %s" % [verb_now(), display_name]


func can_interact() -> bool:
	return true


func interact(_who: FpController) -> Dictionary:
	return {}
