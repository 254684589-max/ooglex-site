extends Node
## 渲染规模统计（沿用 working-life/tests/perf_stats 的做法，开发用，不在 run_tests.sh 里）：
##   xvfb-run -a godot --path games/emberfall3d/godot --rendering-driver opengl3 res://tests/perf_stats.tscn
## 玩家站在大厅中央（无敌），5 个怪物围上来、祭司召唤、弓手放箭，采样 1 秒：绘制调用、图元、可见物体、帧率。
## xvfb 下是 llvmpipe 软件渲染，帧率只供参考；绘制调用与图元数与显卡无关，可以直接对照 TECH.md 的预算。

func _ready() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.auto_pack_test = false
	main.run_nav_bench = false
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var r: Dictionary = await main.perf_probe(4.0)
	print("大厅战斗镜头：绘制调用 %.0f，图元 %.0f，可见物体 %.0f，FPS %d（软件渲染，仅供参考），敌人 %d" % [r.draw_calls, r.primitives, r.objects, r.fps, r.enemies])
	get_tree().quit()
