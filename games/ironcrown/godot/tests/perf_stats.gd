extends Node
## 渲染开销对照（开发用，不在 run_tests.sh 里；沿用 emberfall3d/tests/perf_stats 的做法）：
##   xvfb-run -a godot --path games/ironcrown/godot --rendering-driver opengl3 res://tests/perf_stats.tscn
## 在霜渡镇固定机位 0 依次关掉各项，各采样 2 秒：帧率（软件渲染，只看相对变化）、绘制调用、图元。

var main: Node


func _ready() -> void:
	get_window().size = Vector2i(640, 360)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	for i in 5:
		await get_tree().process_frame
	await _case("中画质（基准）", func(): main.apply_quality("medium"))
	await _case("低画质", func(): main.apply_quality("low"))
	main.apply_quality("medium")
	await _case("中画质 - 雾带", func(): _fog(false))
	_fog(true)
	await _case("中画质 - 月光阴影", func(): main.moon.shadow_enabled = false)
	main.moon.shadow_enabled = true
	await _case("中画质 - 街灯光源", func(): _lamps(false))
	_lamps(true)
	await _case("中画质 - 泛光", func(): main.env.glow_enabled = false)
	main.env.glow_enabled = true
	await _case("中画质 - 法线与 ARM 贴图", func(): _maps(false))
	await _case("再去掉各向异性过滤", func(): _aniso(false))
	await _case("再去掉贴图（纯色）", func(): _plain())
	get_tree().quit()


func _case(name: String, setup: Callable) -> void:
	setup.call()
	for i in 3:
		await get_tree().process_frame
	var n := 0
	var dc := 0.0
	var prim := 0.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		n += 1
	print("PERF %-20s 帧率 %.1f  绘制调用 %.0f  图元 %.0f" % [name, n / 3.0, dc / n, prim / n])


func _fog(on: bool) -> void:
	for f in get_tree().get_nodes_in_group("fog_band"):
		f.visible = on


func _lamps(on: bool) -> void:
	for l in get_tree().get_nodes_in_group("street_lamp"):
		l.light.visible = on


func _maps(on: bool) -> void:
	for k in Look.PHOTO:
		var m := Look.mat(k)
		m.normal_enabled = on
		m.ao_enabled = on


func _aniso(on: bool) -> void:
	for k in Look.PHOTO:
		Look.mat(k).texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC if on else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _plain() -> void:
	for k in Look.PHOTO:
		var m := Look.mat(k)
		m.albedo_texture = null
		m.roughness_texture = null
		m.uv1_triplanar = false
