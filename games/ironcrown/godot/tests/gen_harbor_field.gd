extends Node
## 生成双钥港预先算好的高度场和贴图分布（路线图 7.1；world/harbor.gd 的 FIELD_PATH / PAINT_PATH）。HarborLayout 改了以后跑一次：
##   godot --headless --path games/ironcrown/godot res://tests/gen_harbor_field.tscn
## 是个场景不是 --script：Harbor 用到的类（房子、门、陈设，7.2）读自动加载，--script 模式下没有自动加载、编不过
func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	Harbor.compute_field()
	Harbor.save_field()
	print("IC_GEN_HARBOR ms=%d -> %s, %s" % [Time.get_ticks_msec() - t0, Harbor.FIELD_PATH, Harbor.PAINT_PATH])
	get_tree().quit()
