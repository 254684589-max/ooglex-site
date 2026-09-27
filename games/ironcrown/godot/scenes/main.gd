extends Node3D
## 《铁冠之争》主场景（阶段 1.1：灰盒）。
## 只搭一段静止的雾夜街道，验证工程、兼容渲染器与网页导出跑得通；第一人称移动在 1.2，正式的霜渡镇主街在 1.4。
## 画面全部是占位几何体，界面上明确标注。

const EYE_HEIGHT := 1.65                        # 视高（GDD.md 第四节）
const FOG_COLOR := Color("1c2a3a")              # 夜空与远雾（ART.md 第四节）
const AMBIENT_COLOR := Color("6f8faf")          # 月光 / 环境光
const WINDOW_COLOR := Color("ffc873")           # 窗光
const LAMP_COLOR := Color("ff9a3c")             # 街灯
const TITLE := "铁冠之争 · 灰盒原型（占位几何体）"
const SUBTITLE := "阶段 1.1：静止的雾夜街道，只用来验证网页导出。第一人称移动在下一步加入。"

var camera: Camera3D
var env: Environment
var title_label: Label
var status_label: Label


func _ready() -> void:
	_build_environment()
	_build_street()
	_build_camera()
	_build_ui()
	print("IC_READY renderer=%s web=%s size=%s" % [
		ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		OS.has_feature("web"), get_viewport().get_visible_rect().size])


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = FOG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT_COLOR
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = FOG_COLOR
	env.fog_density = 0.045
	env.glow_enabled = true
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_color = AMBIENT_COLOR
	moon.light_energy = 0.25
	moon.rotation_degrees = Vector3(-50, 30, 0)
	add_child(moon)


func _mat(color: Color, emission := Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 0.8
	return m


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	add_child(mi)
	return mi


func _build_street() -> void:
	var stone := _mat(Color("5e6670"))
	stone.roughness = 0.45                      # 湿石板：稍亮的高光
	_box(Vector3(12, 0.2, 80), Vector3(0, -0.1, -30), stone)             # 街道
	var ground := _mat(Color("2a3036"))
	_box(Vector3(80, 0.2, 80), Vector3(0, -0.12, -30), ground)           # 两侧泥地
	var wall := _mat(Color("4a4c50"))
	var timber := _mat(Color("3a2a20"))
	var glow := _mat(WINDOW_COLOR, WINDOW_COLOR)
	# 两排灰盒房子：石砌底层 + 木构上层 + 一扇亮窗（ART.md 第六节的比例，占位）
	for i in 5:
		for side in [-1, 1]:
			var z := -6.0 - i * 11.0
			var x: float = side * 10.0
			_box(Vector3(7, 3, 8), Vector3(x, 1.5, z), wall)
			_box(Vector3(7.4, 2.6, 8.4), Vector3(x, 4.3, z), timber)
			_box(Vector3(0.1, 1.0, 1.2), Vector3(x - side * 3.52, 1.8, z), glow)
	# 两盏街灯：真实点光源（TECH.md 4.6：视野内 ≤ 4 盏）
	for z in [-8.0, -26.0]:
		_box(Vector3(0.15, 3.2, 0.15), Vector3(4.5, 1.6, z), timber)
		_box(Vector3(0.35, 0.35, 0.35), Vector3(4.5, 3.3, z), _mat(LAMP_COLOR, LAMP_COLOR))
		var lamp := OmniLight3D.new()
		lamp.light_color = LAMP_COLOR
		lamp.light_energy = 2.0
		lamp.omni_range = 9.0
		lamp.position = Vector3(4.5, 3.0, z)
		add_child(lamp)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.position = Vector3(0, EYE_HEIGHT, 4)
	camera.rotation_degrees = Vector3(-4, 0, 0)
	add_child(camera)
	camera.make_current()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var box := VBoxContainer.new()
	box.position = Vector2(16, 16)
	layer.add_child(box)
	title_label = Label.new()
	title_label.text = TITLE
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color("e8dcc0"))
	box.add_child(title_label)
	status_label = Label.new()
	status_label.text = SUBTITLE
	status_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY   # 中文按字换行，不在空格处断开
	status_label.custom_minimum_size = Vector2(300, 0)
	status_label.add_theme_color_override("font_color", Color("a9b4c0"))
	box.add_child(status_label)
	get_tree().root.size_changed.connect(_fit_ui)
	_fit_ui()


func _fit_ui() -> void:
	# 界面按 UiScale 缩放后，说明文字不超过屏幕宽度（360px 手机也不横向溢出）
	var w := get_tree().root
	var logical_w := w.size.x / maxf(w.content_scale_factor, 0.01)
	status_label.custom_minimum_size.x = clampf(logical_w - 32.0, 200.0, 640.0)
