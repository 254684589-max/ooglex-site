extends SceneTree
## 生成双钥港预先算好的高度场和贴图分布（路线图 7.1；world/harbor.gd 的 FIELD_PATH / PAINT_PATH）。HarborLayout 改了以后跑一次：
##   godot --headless --path games/ironcrown/godot --script res://tests/gen_harbor_field.gd
func _init() -> void:
	var t0 := Time.get_ticks_msec()
	Harbor.compute_field()
	Harbor.save_field()
	print("IC_GEN_HARBOR ms=%d -> %s, %s" % [Time.get_ticks_msec() - t0, Harbor.FIELD_PATH, Harbor.PAINT_PATH])
	quit()
