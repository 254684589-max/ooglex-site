extends SceneTree
## 生成金穗平原预先算好的高度场和贴图分布（路线图 6.1a；world/plain.gd 的 FIELD_PATH / PAINT_PATH）。PlainLayout 改了以后跑一次：
##   godot --headless --path games/ironcrown/godot --script res://tests/gen_plain_field.gd
func _init() -> void:
	var t0 := Time.get_ticks_msec()
	Plain.compute_field()
	Plain.save_field()
	print("IC_GEN_PLAIN ms=%d -> %s, %s" % [Time.get_ticks_msec() - t0, Plain.FIELD_PATH, Plain.PAINT_PATH])
	quit()
