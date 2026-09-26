extends Node3D
## 阶段 1 灰盒场景：工程、渲染器、网页导出、章节包加载（1.1）与斜俯视相机（1.2）。
## 画面里的所有模型都是代码生成的**占位几何体**，不代表最终美术（ART.md）。
## 点击移动在 1.3 实现；在那之前主角沿固定路线走动，用来演示相机跟随与遮挡半透明。

const PITCH_DEG := 55.0
const WORLD_MASK := 1 | IsoCamera.OCCLUDER_LAYER   # 墙体与柱子：世界碰撞（第 1 层）+ 遮挡视线（第 2 层）
const PATROL := [Vector3(0, 0, 0), Vector3(-3.6, 0, 5.1), Vector3(-4.6, 0, 1.0), Vector3(5.1, 0, -3.6), Vector3(1.0, 0, -4.6)]
const PATROL_SPEED := 2.2

var auto_pack_test := true
var demo_patrol := true
var patrol_i := 1
var hero: Node3D
var torch_light: OmniLight3D
var camera: IsoCamera
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
	if hero and demo_patrol:
		var goal: Vector3 = PATROL[patrol_i]
		var to := goal - hero.position
		to.y = 0.0
		if to.length() < 0.05:
			patrol_i = (patrol_i + 1) % PATROL.size()
		else:
			hero.position += to.normalized() * minf(PATROL_SPEED * delta, to.length())
			hero.rotation.y = atan2(to.x, to.z)


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


func _box(size: Vector3, pos: Vector3, c: Color, solid := true) -> MeshInstance3D:
	## 占位方块。solid = true 时带静态碰撞体（世界 + 遮挡层），相机会在它挡住主角时把它变半透明。
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(c)
	if not solid:
		mi.position = pos
		add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.collision_layer = WORLD_MASK
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	body.add_child(mi)
	body.set_meta("fade_meshes", [mi])
	add_child(body)
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
	# 墙高 3.2 米（约主角身高的 1.8 倍）：55° 俯角下能挡住墙后约 2.2 米，才需要半透明
	_box(Vector3(12, 3.2, 0.6), Vector3(0, 1.6, -6), wall)
	_box(Vector3(0.6, 3.2, 12), Vector3(-6, 1.6, 0), wall)
	_box(Vector3(0.6, 3.2, 5), Vector3(6, 1.6, -3.5), wall)
	_box(Vector3(5, 3.2, 0.6), Vector3(-3.5, 1.6, 6), wall)
	for p in [Vector3(-3, 0, -3), Vector3(3, 0, 3), Vector3(-3, 0, 3)]:
		_box(Vector3(0.7, 3.0, 0.7), p + Vector3(0, 1.5, 0), Color(0.42, 0.38, 0.34))

	# 火把（占位）：柱 + 发光球 + 闪烁点光源
	_box(Vector3(0.16, 1.6, 0.16), Vector3(-5.4, 0.8, -5.4), Color(0.3, 0.2, 0.12), false)
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

	# 斜俯视相机（camera/iso_camera.gd）
	camera = IsoCamera.new()
	camera.pitch_deg = PITCH_DEG
	camera.target = hero
	add_child(camera)


# ---------------- 界面 ----------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	info = Label.new()
	info.anchor_right = 1.0
	info.offset_left = 16
	info.offset_top = 12
	info.offset_right = -16
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 18)
	info.add_theme_color_override("font_color", Color(0.91, 0.52, 0.23))
	info.text = "余烬陷落 EMBERFALL · 大作版灰盒原型（阶段 1.2 斜俯视相机）\n画面全部为占位几何体，不代表最终美术。主角沿固定路线走动（点击移动在下一步），挡住主角的墙会变半透明；滚轮缩放。"
	layer.add_child(info)
	pack_label = Label.new()
	pack_label.anchor_top = 1.0
	pack_label.anchor_bottom = 1.0
	pack_label.anchor_right = 1.0
	pack_label.offset_left = 16
	pack_label.offset_right = -16
	pack_label.offset_top = -56
	pack_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pack_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pack_label.add_theme_font_size_override("font_size", 16)
	pack_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))
	layer.add_child(pack_label)
	_refresh_labels()


func _refresh_labels() -> void:
	if pack_label:
		pack_label.text = "%s　·　渲染器：%s" % [pack_state, RenderingServer.get_current_rendering_method()]
