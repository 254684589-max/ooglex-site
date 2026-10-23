extends SceneTree
## 生成余火高地预先算好的高度场和贴图分布（路线图 5.1a；world/highland.gd 的 FIELD_PATH / PAINT_PATH）。HighlandLayout 改了以后跑一次：
##   godot --headless --path games/ironcrown/godot --script res://tests/gen_highland_field.gd
func _init() -> void:
	var t0 := Time.get_ticks_msec()
	Highland.compute_field()
	Highland.save_field()
	print("IC_GEN_HIGHLAND ms=%d -> %s, %s" % [Time.get_ticks_msec() - t0, Highland.FIELD_PATH, Highland.PAINT_PATH])
	quit()
