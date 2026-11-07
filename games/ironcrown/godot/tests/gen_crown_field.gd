extends Node
## 生成冠城一角预先算好的高度场和贴图分布（路线图 7.6；world/crown_city.gd 的 FIELD_PATH / PAINT_PATH）。CrownLayout 改了以后跑一次：
##   godot --headless --path games/ironcrown/godot res://tests/gen_crown_field.tscn
## 是个场景不是 --script（同 gen_harbor_field：用到的类读自动加载）
func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	CrownCity.compute_field()
	CrownCity.save_field()
	print("IC_GEN_CROWN ms=%d -> %s, %s" % [Time.get_ticks_msec() - t0, CrownCity.FIELD_PATH, CrownCity.PAINT_PATH])
	get_tree().quit()
