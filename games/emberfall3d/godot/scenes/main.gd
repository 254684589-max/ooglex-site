extends Node3D
## 阶段 1.1 灰盒场景：验证工程、兼容渲染器、网页导出与章节包加载。
## 画面里的所有模型都是代码生成的**占位几何体**，不代表最终美术（ART.md）。

const PITCH_DEG := 55.0
const YAW_DEG := 45.0
const CAM_DIST := 15.0

var auto_pack_test := true
var hero: Node3D
var torch_light: OmniLight3D
var camera: Camera3D
var info: Label
var pack_label: Label
var pack_state := "章节包：未测试"
var t := 0.0


func _ready() -> void:
	_build_world()
	_build_ui()
	PackLoader.pack_loaded.connect(_on_pack_loaded)
	print("EF_READY renderer=%s web=%s" % [RenderingServer.get_current_rendering_method(), OS.has_feature("web")])
	if auto_pack_test and OS.has_feature("web"):
		pack_state = "章节包：下载中……"
		_refresh_labels()
		PackLoader.load_chapter("ch_test")


func _process(delta: float) -> void:
	t += delta
	if torch_light:
		torch_light.light_energy = 2.2 + sin(t * 11.0) * 0.18 + sin(t * 7.3) * 0.12
	if hero:
		hero.position.y = sin(t * 2.0) * 0.03


func _on_pack_loaded(id: String, ok: bool, ms: int, detail: String) -> void:
	if ok:
		var scene := load("res://packs/%s/marker.tscn" % id) as PackedScene
		if scene:
			var inst := scene.instantiate()
			inst.position = Vector3(3.5, 0, -2.5)
			add_child(inst)
			pack_state = "章节包 %s：加载成功，用时 %d 毫秒" % [id, ms]
			print("EF_PACK_OK id=%s ms=%d" % [id, ms])
		else:
			pack_state = "章节包 %s：已挂载，但找不到场景" % id
			print("EF_PACK_FAIL id=%s reason=scene_missing" % id)
	else:
		pack_state = "章节包 %s：加载失败（%s）" % [id, detail]
		print("EF_PACK_FAIL id=%s reason=%s" % [id, detail])
	_refresh_labels()


# ---------------- 场景 ----------------

func _mat(c: Color, emissive: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
	return m


func _box(size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(c)
	mi.position = pos
	add_child(mi)
	return mi


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.03, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.26, 0.24, 0.34)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.08, 0.1)
	env.fog_density = 0.02
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.6, 0.85)
	moon.light_energy = 0.35
	moon.shadow_enabled = true
	moon.rotation_degrees = Vector3(-60, 30, 0)
	add_child(moon)

	# 地面（占位）
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(28, 28)
	ground.mesh = plane
	ground.material_override = _mat(Color(0.23, 0.21, 0.19))
	add_child(ground)

	# 一间有缺口的灰盒房间 + 石柱（占位）
	var wall := Color(0.36, 0.33, 0.3)
	_box(Vector3(12, 2.4, 0.6), Vector3(0, 1.2, -6), wall)
	_box(Vector3(0.6, 2.4, 12), Vector3(-6, 1.2, 0), wall)
	_box(Vector3(0.6, 2.4, 5), Vector3(6, 1.2, -3.5), wall)
	_box(Vector3(5, 2.4, 0.6), Vector3(-3.5, 1.2, 6), wall)
	for p in [Vector3(-3, 0, -3), Vector3(3, 0, 3), Vector3(-3, 0, 3)]:
		_box(Vector3(0.7, 3.0, 0.7), p + Vector3(0, 1.5, 0), Color(0.42, 0.38, 0.34))

	# 火把（占位）：柱 + 发光球 + 闪烁点光源
	_box(Vector3(0.16, 1.6, 0.16), Vector3(-5.4, 0.8, -5.4), Color(0.3, 0.2, 0.12))
	var flame := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.16
	sph.height = 0.32
	flame.mesh = sph
	flame.material_override = _mat(Color(1.0, 0.55, 0.16), 3.0)
	flame.position = Vector3(-5.4, 1.7, -5.4)
	add_child(flame)
	torch_light = OmniLight3D.new()
	torch_light.light_color = Color(1.0, 0.58, 0.25)
	torch_light.omni_range = 7.0
	torch_light.position = Vector3(-5.4, 1.9, -5.4)
	add_child(torch_light)

	# 主角占位：胶囊 + 「武器」方块 + 跟随暖光
	hero = Node3D.new()
	add_child(hero)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.8
	body.mesh = cap
	body.material_override = _mat(Color(0.55, 0.47, 0.38))
	body.position.y = 0.9
	hero.add_child(body)
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, 1.1, 0.08)
	blade.mesh = bm
	blade.material_override = _mat(Color(0.8, 0.82, 0.86))
	blade.position = Vector3(0.45, 1.0, 0)
	blade.rotation_degrees.z = -20
	hero.add_child(blade)
	var hero_light := OmniLight3D.new()
	hero_light.light_color = Color(1.0, 0.72, 0.45)
	hero_light.light_energy = 1.3
	hero_light.omni_range = 6.0
	hero_light.position = Vector3(0, 2.4, 0)
	hero.add_child(hero_light)

	# 斜俯视相机（固定俯角 55°、偏航 45°）
	camera = Camera3D.new()
	camera.fov = 40.0
	var p := deg_to_rad(PITCH_DEG)
	var y := deg_to_rad(YAW_DEG)
	camera.position = Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * CAM_DIST
	add_child(camera)
	camera.look_at(Vector3(0, 0.8, 0), Vector3.UP)
	camera.current = true


# ---------------- 界面 ----------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	info = Label.new()
	info.position = Vector2(16, 12)
	info.add_theme_font_size_override("font_size", 18)
	info.add_theme_color_override("font_color", Color(0.91, 0.52, 0.23))
	info.text = "余烬陷落 EMBERFALL · 大作版灰盒原型（阶段 1.1）\n画面全部为占位几何体，不代表最终美术"
	layer.add_child(info)
	pack_label = Label.new()
	pack_label.anchor_top = 1.0
	pack_label.anchor_bottom = 1.0
	pack_label.offset_left = 16
	pack_label.offset_top = -44
	pack_label.add_theme_font_size_override("font_size", 16)
	pack_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))
	layer.add_child(pack_label)
	_refresh_labels()


func _refresh_labels() -> void:
	if pack_label:
		pack_label.text = "%s　·　渲染器：%s" % [pack_state, RenderingServer.get_current_rendering_method()]
